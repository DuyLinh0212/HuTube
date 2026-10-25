#!/usr/bin/env python3
"""Poll public GitHub checks and deploy a verified main revision on an EC2 host."""
from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import signal
import subprocess
import time
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import urlencode
from urllib.request import Request, urlopen

REQUIRED_JOBS = {
    "backend", "web (user-web)", "web (admin-web)", "recommendation",
    "mobile", "e2e", "container", "deployment-checks",
}
SERVICES = ("api", "recommendation", "caddy")


class DeploymentDeferred(Exception):
    pass


def log(event, **fields):
    print(json.dumps({"time": datetime.now(timezone.utc).isoformat(),
                      "event": event, **fields}), flush=True)


def read_json(url):
    request = Request(url, headers={"Accept": "application/vnd.github+json",
                                   "X-GitHub-Api-Version": "2022-11-28",
                                   "User-Agent": "Dalitu-EC2-Autodeploy"})
    with urlopen(request, timeout=20) as response:
        return json.loads(response.read(2 * 1024 * 1024))


def write_json(path, value):
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    temporary = path.with_suffix(".tmp")
    temporary.write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8")
    temporary.chmod(0o600)
    os.replace(temporary, path)


def gate_reason(run, sha, jobs, status, repository, required_statuses):
    """Return a reason to wait, or None when all required checks passed."""
    if (run.get("event") != "push" or run.get("head_branch") != "main"
            or run.get("head_sha") != sha
            or run.get("head_repository", {}).get("full_name") != repository):
        return "CI run does not belong to this main revision"
    if run.get("status") != "completed" or run.get("conclusion") != "success":
        return "CI has not completed successfully"
    by_name = {job["name"]: job for job in jobs}
    if not REQUIRED_JOBS.issubset(by_name):
        return "A required CI job is missing"
    for job in jobs:
        name = job["name"]
        if name == "deploy-staging" and job.get("conclusion") == "skipped":
            continue
        if job.get("status") != "completed" or job.get("conclusion") != "success":
            return "A CI job has not succeeded: " + name
    statuses = {item["context"]: item["state"] for item in status.get("statuses", [])}
    if status.get("state") != "success" or any(
            statuses.get(name) != "success" for name in required_statuses):
        return "Vercel deployment checks have not all succeeded"
    return None


class Deployer:
    def __init__(self, config):
        self.config = config
        self.repo = Path(config["repo_dir"]).resolve()
        self.directory = Path(config["state_dir"]).resolve()
        self.state_path = self.directory / "state.json"
        self.state = json.loads(self.state_path.read_text()) if self.state_path.exists() else {}
        self.api = "https://api.github.com/repos/" + config["repository"]

    def run(self, *args, env=None, capture=False, timeout=120):
        environment = {**os.environ, "GIT_TERMINAL_PROMPT": "0", "COMPOSE_PARALLEL_LIMIT": "1"}
        environment.update(env or {})
        result = subprocess.run(args, cwd=self.repo, env=environment, text=True,
                                stdout=subprocess.PIPE if capture else None,
                                check=True, timeout=timeout)
        return (result.stdout or "").strip()

    def git(self, *args):
        return self.run("runuser", "-u", self.config["run_user"], "--", "git",
                        "-C", str(self.repo), *args, capture=True)

    def compose(self, *args, env=None, files=None, capture=False, timeout=120):
        command = ["docker", "compose", "--project-name", self.config["project_name"],
                   "--project-directory", str(self.repo)]
        for file in files or [self.repo / "docker-compose.ec2.yml"]:
            command += ["-f", str(file)]
        return self.run(*command, *args, env=env, capture=capture, timeout=timeout)

    def save(self):
        write_json(self.state_path, self.state)

    def tip(self):
        sha = read_json(self.api + "/branches/main")["commit"]["sha"]
        if not re.fullmatch(r"[0-9a-f]{40}", sha):
            raise ValueError("Invalid main revision")
        return sha

    def eligible(self, retry=False):
        sha = self.tip()
        if self.state.get("sha") == sha:
            log("already_deployed", sha=sha)
            return None
        if self.state.get("failed_sha") == sha and not retry:
            log("revision_quarantined", sha=sha)
            return None
        query = urlencode({"event": "push", "branch": "main", "head_sha": sha, "per_page": 1})
        url = self.api + "/actions/workflows/ci.yml/runs?" + query
        runs = read_json(url).get("workflow_runs", [])
        if not runs or runs[0].get("conclusion") != "success" or runs[0].get("status") != "completed":
            log("waiting_for_ci", sha=sha)
            return None
        run = runs[0]
        response = read_json(self.api + f"/actions/runs/{int(run['id'])}/jobs?per_page=100&filter=latest")
        if response.get("total_count", 0) > 100:
            raise ValueError("CI job count exceeds the checked page")
        status = read_json(self.api + "/commits/" + sha + "/status")
        reason = gate_reason(run, sha, response.get("jobs", []), status,
                             self.config["repository"], self.config["required_statuses"])
        if reason:
            log("waiting_for_checks", sha=sha, reason=reason)
            return None
        return sha, run["id"]

    def preflight(self):
        if self.git("branch", "--show-current") != "main":
            raise ValueError("Deployment checkout must be on main")
        if self.git("status", "--porcelain", "--untracked-files=no"):
            raise ValueError("Tracked server files have local modifications")
        expected = "https://github.com/" + self.config["repository"] + ".git"
        if self.git("remote", "get-url", "origin") != expected:
            raise ValueError("Unexpected deployment Git remote")
        if shutil.disk_usage(self.repo).free < 3 * 1024 ** 3:
            raise ValueError("At least 3 GiB of free disk is required before building")
        for path in (self.repo / ".env.ec2-api", self.repo / "recommendation-service/.env.ec2"):
            if not path.is_file():
                raise ValueError("An EC2 environment file is missing")

    def image_ids(self, files=None):
        result = {}
        for service in SERVICES:
            container = self.compose("ps", "-q", service, files=files, capture=True)
            if not container or "\n" in container:
                raise ValueError("Expected one running container for " + service)
            result[service] = self.run("docker", "inspect", "--format", "{{.Image}}", container, capture=True)
        return result

    def snapshot(self, sha):
        directory = self.directory / "rollback" / (str(time.time_ns()) + "-" + sha[:12])
        directory.mkdir(mode=0o700, parents=True)
        # Read the configuration actually used by the running containers. After
        # a previous rollback, HEAD may be newer than the active deployment.
        images = self.image_ids()
        baseline = self.state.get("baseline_snapshot")
        if baseline and baseline["images"] == images:
            source = str(Path(baseline["directory"]) / "docker-compose.ec2.yml")
        else:
            api_container = self.compose("ps", "-q", "api", capture=True)
            source = self.run("docker", "inspect", "--format",
                              '{{index .Config.Labels "com.docker.compose.project.config_files"}}',
                              api_container, capture=True).split(",")[0]
        source_path = Path(source).resolve()
        if not (source_path.is_relative_to(self.repo) or source_path.is_relative_to(self.directory)):
            raise ValueError("Active Compose file is outside the managed directories")
        shutil.copyfile(source_path, directory / "docker-compose.ec2.yml")
        caddy_container = self.compose("ps", "-q", "caddy", capture=True)
        caddy_config = self.run("docker", "exec", caddy_container, "cat", "/etc/caddy/Caddyfile", capture=True)
        (directory / "Caddyfile").write_text(caddy_config + "\n", encoding="utf-8")
        for name in ("docker-compose.ec2.yml", "Caddyfile"):
            (directory / name).chmod(0o600)
        old_sha = read_json(self.config["api_url"] + "/api/v1/system/info").get("commitSha")
        pinned = {}
        for service, image in images.items():
            tag = f"dalitu-{service}:rollback-{directory.name}"
            self.run("docker", "image", "tag", image, tag)
            pinned[service] = {"image": tag}
        pinned["migrate"] = {"image": pinned["api"]["image"]}
        pinned["caddy"]["volumes"] = [str(directory / "Caddyfile") + ":/etc/caddy/Caddyfile:ro"]
        write_json(directory / "override.json", {"services": pinned})
        return {"directory": str(directory), "images": images, "sha": old_sha}

    def update_checkout(self, sha):
        self.git("fetch", "origin", "main")
        if self.git("rev-parse", "origin/main") != sha:
            raise ValueError("Main advanced before checkout")
        self.git("merge", "--ff-only", sha)

    def build(self, sha):
        env = {"HUTUBE_COMMIT_SHA": sha, "DALITU_API_IMAGE": "dalitu-api:git-" + sha,
               "DALITU_RECOMMENDATION_IMAGE": "dalitu-recommendation:git-" + sha}
        self.compose("config", "--quiet", env=env)
        # Keep the two builds sequential on the small EC2 host.
        for service in ("api", "recommendation"):
            log("building", service=service, sha=sha)
            self.compose("build", service, env=env, timeout=1200)
        expected = {"api": self.run("docker", "image", "inspect", "--format", "{{.Id}}",
                                    env["DALITU_API_IMAGE"], capture=True),
                    "recommendation": self.run("docker", "image", "inspect", "--format", "{{.Id}}",
                                               env["DALITU_RECOMMENDATION_IMAGE"], capture=True)}
        return env, expected

    def prepare(self, env, snapshot):
        mount = "type=bind,src=" + str(self.repo / "Caddyfile") + ",dst=/etc/caddy/Caddyfile,readonly"
        self.run("docker", "run", "--rm", "--entrypoint", "caddy", "--mount", mount,
                 snapshot["images"]["caddy"], "validate", "--config", "/etc/caddy/Caddyfile")
        services = self.compose("config", "--services", env=env, capture=True).splitlines()
        if "rabbitmq" in services:
            log("starting_messaging")
            self.compose("up", "-d", "--no-deps", "--wait", "--wait-timeout", "120",
                         "rabbitmq", env=env, timeout=180)
        log("migrating")
        self.compose("run", "--rm", "--no-deps", "migrate", env=env, timeout=600)

    def activate(self, env):
        self.compose("up", "-d", "--no-deps", "--no-build", "--force-recreate",
                     "recommendation", "api", "caddy", env=env, timeout=180)

    def set_default_image_tags(self, images):
        # Existing operator commands should also select the last healthy images.
        for service, tag in (("api", "dalitu-api:local"),
                             ("recommendation", "hutube-ec2-recommendation")):
            self.run("docker", "image", "tag", images[service], tag)

    def verify(self, sha, expected, files=None, timeout=300):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            try:
                for base in (self.config["api_url"], self.config["public_api_url"]):
                    if read_json(base + "/health").get("status") != "healthy":
                        raise ValueError("API health is not healthy")
                    actual = read_json(base + "/api/v1/system/info").get("commitSha")
                    if sha and actual != sha:
                        raise ValueError("API is not running the expected revision")
                for base in (self.config["recommendation_url"], self.config["public_recommendation_url"]):
                    if read_json(base + "/health").get("status") != "ok":
                        raise ValueError("Recommendation health is not ok")
                actual_images = self.image_ids(files)
                if any(actual_images.get(name) != image for name, image in expected.items()):
                    raise ValueError("Running container images differ from the expected images")
                return actual_images
            except (OSError, ValueError, subprocess.SubprocessError):
                time.sleep(5)
        raise TimeoutError("The expected revision did not become healthy")

    def rollback(self, snapshot):
        log("rolling_back")
        directory = Path(snapshot["directory"])
        files = [directory / "docker-compose.ec2.yml", directory / "override.json"]
        self.compose("up", "-d", "--no-deps", "--no-build", "--force-recreate",
                     "recommendation", "api", "caddy", files=files, timeout=180)
        self.verify(snapshot["sha"], snapshot["images"], files=files, timeout=180)
        self.set_default_image_tags(snapshot["images"])
        log("rollback_succeeded", sha=snapshot["sha"])

    def recover_interrupted(self):
        pending = self.state.get("pending")
        if not pending:
            return
        if pending["phase"] == "activate":
            self.rollback(pending["snapshot"])
        self.state["baseline_snapshot"] = pending["snapshot"]
        self.state["failed_sha"] = pending["sha"]
        self.state.pop("pending", None)
        self.save()
        log("interrupted_revision_quarantined", sha=pending["sha"])

    def deploy(self, sha, run_id):
        self.preflight()
        snapshot = self.snapshot(sha)
        # Keep the active baseline even if Git advances but activation is later
        # deferred. A mutable checkout path may then contain unactivated config.
        self.state["baseline_snapshot"] = snapshot
        pending = {"sha": sha, "run_id": run_id, "phase": "build", "snapshot": snapshot}
        self.state["pending"] = pending
        self.save()
        try:
            self.update_checkout(sha)
            env, expected = self.build(sha)
            self.prepare(env, snapshot)
            if self.tip() != sha or self.eligible(retry=True) != (sha, run_id):
                raise DeploymentDeferred("Main or deployment checks changed during build")
            pending["phase"] = "activate"
            self.save()
            log("activating", sha=sha, run_id=run_id)
            self.activate(env)
            images = self.verify(sha, expected)
            self.set_default_image_tags(images)
        except DeploymentDeferred:
            self.state.pop("pending", None)
            self.save()
            log("deployment_deferred", sha=sha)
            return
        except (OSError, ValueError, subprocess.SubprocessError) as error:
            log("deployment_failed", sha=sha, error_type=type(error).__name__, phase=pending["phase"])
            if pending["phase"] == "activate":
                self.rollback(snapshot)
            self.state["failed_sha"] = sha
            self.state.pop("pending", None)
            self.save()
            raise
        self.state = {"sha": sha, "run_id": run_id, "images": images,
                      "updated_at": datetime.now(timezone.utc).isoformat(),
                      "rollback_directory": snapshot["directory"]}
        self.save()
        log("deployment_succeeded", sha=sha, run_id=run_id)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", default="/etc/dalitu-autodeploy.json")
    parser.add_argument("--check-only", action="store_true")
    parser.add_argument("--retry-failed", action="store_true")
    args = parser.parse_args()
    if os.geteuid() != 0:
        parser.error("Run through the systemd service or sudo")
    config = json.loads(Path(args.config).read_text(encoding="utf-8"))
    if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", config["repository"]):
        parser.error("Invalid GitHub repository")
    import fcntl
    directory = Path(config["state_dir"])
    directory.mkdir(mode=0o700, parents=True, exist_ok=True)
    with (directory / "deploy.lock").open("w") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            log("deployment_already_running")
            return
        deployer = Deployer(config)
        if not args.check_only:
            deployer.recover_interrupted()
        candidate = deployer.eligible(args.retry_failed)
        if candidate:
            log("checks_passed", sha=candidate[0], run_id=candidate[1], check_only=args.check_only)
            if not args.check_only:
                deployer.deploy(*candidate)


if __name__ == "__main__":
    def interrupted(_signum, _frame):
        raise InterruptedError("Deployment interrupted")
    signal.signal(signal.SIGTERM, interrupted)
    try:
        main()
    except Exception as error:
        # Avoid dumping HTTP response bodies, connection settings or env files.
        log("autodeploy_error", error_type=type(error).__name__)
        raise SystemExit(1)
