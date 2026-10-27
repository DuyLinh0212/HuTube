from contextlib import ExitStack, redirect_stdout
from copy import deepcopy
from io import StringIO
import json
import os
import stat
import subprocess
from pathlib import Path
import sys
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from ec2_autodeploy import Deployer, REQUIRED_JOBS, gate_reason

SHA = "a" * 40
OLD = "b" * 40
REPO = "example/project"
CONTEXTS = ["Vercel – dalitu", "Vercel – dalitu-admin"]


class GateTests(unittest.TestCase):
    def setUp(self):
        self.run = {"event": "push", "head_branch": "main", "head_sha": SHA,
                    "head_repository": {"full_name": REPO},
                    "status": "completed", "conclusion": "success"}
        self.jobs = [{"name": name, "status": "completed", "conclusion": "success"}
                     for name in REQUIRED_JOBS]
        self.status = {"state": "success", "statuses": [
            {"context": name, "state": "success"} for name in CONTEXTS]}

    def reason(self):
        return gate_reason(self.run, SHA, self.jobs, self.status, REPO, CONTEXTS)

    def test_exact_main_revision_with_all_checks_is_eligible(self):
        self.assertIsNone(self.reason())

    def test_wrong_event_branch_revision_and_fork_are_rejected(self):
        original = deepcopy(self.run)
        for field, value in [("event", "pull_request"), ("head_branch", "develop"),
                             ("head_sha", OLD), ("head_repository", {"full_name": "fork/project"}),
                             ("status", "in_progress"), ("conclusion", "failure"),
                             ("conclusion", "cancelled")]:
            with self.subTest(field=field, value=value):
                self.run = {**deepcopy(original), field: value}
                self.assertIsNotNone(self.reason())

    def test_required_job_cannot_be_missing_skipped_or_failed(self):
        original = deepcopy(self.jobs)
        for name in REQUIRED_JOBS:
            with self.subTest(job=name):
                self.jobs = [job for job in deepcopy(original) if job["name"] != name]
                self.assertIsNotNone(self.reason())
                for conclusion in ("skipped", "failure", "cancelled", None):
                    self.jobs = deepcopy(original)
                    next(job for job in self.jobs if job["name"] == name)["conclusion"] = conclusion
                    self.assertIsNotNone(self.reason())

    def test_any_additional_unsuccessful_job_blocks_deployment(self):
        for conclusion in ("skipped", "failure", "cancelled", None):
            with self.subTest(conclusion=conclusion):
                self.jobs = [job for job in self.jobs if job["name"] != "future-check"]
                self.jobs.append({"name": "future-check", "status": "completed", "conclusion": conclusion})
                self.assertIsNotNone(self.reason())

    def test_duplicate_job_name_cannot_hide_failure(self):
        self.jobs.insert(0, {"name": "backend", "status": "completed", "conclusion": "failure"})
        self.assertIsNotNone(self.reason())

    def test_vercel_context_must_exist_and_succeed(self):
        original = deepcopy(self.status)
        for name in CONTEXTS:
            with self.subTest(context=name):
                self.status = deepcopy(original)
                self.status["statuses"] = [item for item in self.status["statuses"] if item["context"] != name]
                self.assertIsNotNone(self.reason())
                for state in ("pending", "failure", "error"):
                    self.status = deepcopy(original)
                    next(item for item in self.status["statuses"] if item["context"] == name)["state"] = state
                    self.assertIsNotNone(self.reason())

    def test_any_unsuccessful_combined_status_blocks_deployment(self):
        self.status["state"] = "pending"
        self.assertIsNotNone(self.reason())


class RecoveryTests(unittest.TestCase):
    def setUp(self):
        self.stack = ExitStack()
        self.addCleanup(self.stack.close)
        self.stack.enter_context(redirect_stdout(StringIO()))
        directory = self.stack.enter_context(TemporaryDirectory())
        self.deployer = Deployer({"repo_dir": directory, "state_dir": directory,
                                  "repository": REPO})
        self.snapshot = {"directory": str(Path(directory) / "rollback"),
                         "sha": OLD, "images": {"api": "old-api", "recommendation": "old-rec"}}
        defaults = {"preflight": None, "snapshot": self.snapshot, "update_checkout": None,
                    "pull_images": ({}, {"api": "new-api", "recommendation": "new-rec"}),
                    "prepare": None, "tip": SHA, "activate": None,
                    "verify": {"api": "new-api", "recommendation": "new-rec"}, "rollback": None,
                    "eligible": (SHA, 123), "set_default_image_tags": None,
                    "cleanup_storage": None}
        self.mocks = {name: self.stack.enter_context(patch.object(self.deployer, name, return_value=value))
                      for name, value in defaults.items()}

    def test_pull_failure_leaves_running_services_untouched(self):
        self.mocks["pull_images"].side_effect = OSError("simulated registry failure")
        with self.assertRaises(OSError):
            self.deployer.deploy(SHA, 123)
        self.mocks["activate"].assert_not_called()
        self.mocks["rollback"].assert_not_called()
        self.assertEqual(SHA, self.deployer.state["failed_sha"])
        self.assertNotIn("pending", self.deployer.state)

    def test_health_failure_restores_previous_images_and_quarantines_revision(self):
        self.mocks["verify"].side_effect = TimeoutError("simulated unhealthy release")
        with self.assertRaises(TimeoutError):
            self.deployer.deploy(SHA, 123)
        self.mocks["rollback"].assert_called_once_with(self.snapshot)
        self.assertEqual(SHA, self.deployer.state["failed_sha"])
        self.assertNotEqual(SHA, self.deployer.state.get("sha"))

    def test_activation_failure_also_rolls_back(self):
        self.mocks["activate"].side_effect = OSError("simulated container startup failure")
        with self.assertRaises(OSError):
            self.deployer.deploy(SHA, 123)
        self.mocks["rollback"].assert_called_once_with(self.snapshot)

    def test_failed_rollback_retains_recovery_checkpoint(self):
        self.mocks["verify"].side_effect = TimeoutError("simulated unhealthy release")
        self.mocks["rollback"].side_effect = OSError("simulated rollback failure")
        with self.assertRaises(OSError):
            self.deployer.deploy(SHA, 123)
        checkpoint = json.loads(self.deployer.state_path.read_text())
        self.assertEqual("activate", checkpoint["pending"]["phase"])
        self.assertEqual(SHA, checkpoint["pending"]["sha"])

    def test_newer_main_during_pull_prevents_activation(self):
        self.mocks["tip"].return_value = "c" * 40
        self.deployer.deploy(SHA, 123)
        self.mocks["activate"].assert_not_called()
        self.mocks["rollback"].assert_not_called()
        self.assertNotIn("failed_sha", self.deployer.state)
        self.assertEqual(self.snapshot, self.deployer.state["baseline_snapshot"])

    def test_changed_ci_or_vercel_checks_during_pull_prevent_activation(self):
        self.mocks["eligible"].return_value = None
        self.deployer.deploy(SHA, 123)
        self.mocks["activate"].assert_not_called()
        self.mocks["rollback"].assert_not_called()
        self.assertNotIn("failed_sha", self.deployer.state)

    def test_success_is_recorded_only_after_health_checks(self):
        def verified(*_args):
            checkpoint = json.loads(self.deployer.state_path.read_text())
            self.assertNotIn("sha", checkpoint)
            self.assertEqual("activate", checkpoint["pending"]["phase"])
            return {"api": "new-api", "recommendation": "new-rec"}
        self.mocks["verify"].side_effect = verified
        self.deployer.deploy(SHA, 123)
        self.assertEqual(SHA, self.deployer.state["sha"])
        self.assertEqual(123, self.deployer.state["run_id"])
        self.assertNotIn("pending", self.deployer.state)
        self.assertNotIn("baseline_snapshot", self.deployer.state)
        self.mocks["rollback"].assert_not_called()

    def test_interrupted_activation_rolls_back_before_another_attempt(self):
        self.deployer.state["pending"] = {"sha": SHA, "phase": "activate", "snapshot": self.snapshot}
        self.deployer.recover_interrupted()
        self.mocks["rollback"].assert_called_once_with(self.snapshot)
        self.assertEqual(SHA, self.deployer.state["failed_sha"])

    def test_interrupted_pull_and_legacy_build_do_not_restart_services(self):
        for phase in ("pull", "build"):
            self.deployer.state["pending"] = {"sha": SHA, "phase": phase, "snapshot": self.snapshot}
            self.deployer.recover_interrupted()
        self.mocks["rollback"].assert_not_called()
        self.assertEqual(SHA, self.deployer.state["failed_sha"])

    def test_cleanup_failure_cannot_rollback_a_verified_release(self):
        self.mocks["cleanup_storage"].side_effect = OSError("cleanup unavailable")
        self.deployer.deploy(SHA, 123)
        self.assertEqual(SHA, self.deployer.state["sha"])
        self.assertNotIn("failed_sha", self.deployer.state)
        self.mocks["rollback"].assert_not_called()


class ImageDownloadTests(unittest.TestCase):
    def setUp(self):
        self.stack = ExitStack()
        self.addCleanup(self.stack.close)
        self.stack.enter_context(redirect_stdout(StringIO()))
        directory = self.stack.enter_context(TemporaryDirectory())
        self.deployer = Deployer({"repo_dir": directory, "state_dir": directory, "repository": REPO})
        self.repo = "ghcr.io/" + REPO + "/api"
        self.digests = {"api": "sha256:" + "1" * 64, "recommendation": "sha256:" + "2" * 64}
        self.ids = {"api": "sha256:" + "3" * 64, "recommendation": "sha256:" + "4" * 64}
        self.images = {service: {
            "Id": self.ids[service], "Os": "linux", "Architecture": "amd64",
            "RepoDigests": [self.repo + "@" + digest],
            "Config": {"Labels": {"org.opencontainers.image.revision": SHA,
                                   "org.opencontainers.image.source": "https://github.com/" + REPO,
                                   "io.dalitu.service": service}}}
            for service, digest in self.digests.items()}
        self.commands = []
        self.run = self.stack.enter_context(patch.object(self.deployer, "run", side_effect=self.command))
        self.compose = self.stack.enter_context(patch.object(self.deployer, "compose"))

    def command(self, *args, **_kwargs):
        self.commands.append(args)
        if args[:2] == ("docker", "pull"):
            service = "recommendation" if ":recommendation-" in args[2] else "api"
            return "Layers downloaded\nDigest: " + self.digests[service] + "\nStatus: Downloaded newer image"
        if args[:3] == ("docker", "image", "inspect"):
            # A tag can change after pull; verification must use the returned digest.
            for service, digest in self.digests.items():
                if args[3] == self.repo + "@" + digest:
                    return json.dumps([self.images[service]])
            self.fail("Inspection used an unverified reference: " + repr(args))
        self.fail("Production attempted an unexpected operation: " + repr(args))

    def test_downloads_both_services_and_pins_the_pulled_digest(self):
        env, expected = self.deployer.pull_images(SHA)
        self.assertEqual(self.ids, expected)
        self.assertEqual({"DALITU_API_IMAGE": self.repo + "@" + self.digests["api"],
                          "DALITU_RECOMMENDATION_IMAGE": self.repo + "@" + self.digests["recommendation"]}, env)
        self.assertEqual([self.repo + ":" + SHA, self.repo + ":recommendation-" + SHA],
                         [command[2] for command in self.commands if command[1] == "pull"])
        self.compose.assert_called_once_with("config", "--quiet", env=env)

    def test_wrong_revision_service_source_platform_digest_or_id_is_rejected(self):
        original = deepcopy(self.images["api"])
        changes = [("revision", OLD), ("service", "recommendation"), ("source", "https://github.com/other/repo"),
                   ("Architecture", "arm64"), ("Os", "windows"), ("RepoDigests", []), ("Id", "unknown")]
        for field, value in changes:
            with self.subTest(field=field):
                image = deepcopy(original)
                label = {"revision": "org.opencontainers.image.revision", "service": "io.dalitu.service",
                         "source": "org.opencontainers.image.source"}.get(field)
                if label:
                    image["Config"]["Labels"][label] = value
                else:
                    image[field] = value
                self.images["api"] = image
                with self.assertRaisesRegex(ValueError, "does not match"):
                    self.deployer.pull_images(SHA)
        self.compose.assert_not_called()

    def test_missing_labels_are_rejected(self):
        self.images["api"]["Config"]["Labels"] = None
        with self.assertRaises(ValueError):
            self.deployer.pull_images(SHA)
        self.compose.assert_not_called()

    def test_missing_malformed_or_ambiguous_registry_digest_is_rejected(self):
        for output in ["Already exists", "Digest: sha256:invalid", "Digest: " + self.digests["api"] +
                       "\nDigest: " + self.digests["recommendation"]]:
            with self.subTest(output=output), patch.object(self.deployer, "run", return_value=output):
                with self.assertRaisesRegex(ValueError, "one immutable digest"):
                    self.deployer.pull_images(SHA)
        self.compose.assert_not_called()

    def test_missing_second_image_does_not_fall_back_to_build(self):
        def unavailable(*args, **kwargs):
            if args[:2] == ("docker", "pull") and ":recommendation-" in args[2]:
                raise subprocess.CalledProcessError(1, "docker pull")
            return self.command(*args, **kwargs)
        self.run.side_effect = unavailable
        with self.assertRaises(subprocess.SubprocessError):
            self.deployer.pull_images(SHA)
        self.compose.assert_not_called()
        self.assertFalse(any("build" in command for command in self.commands))


class StorageCleanupTests(unittest.TestCase):
    def setUp(self):
        self.stack = ExitStack()
        self.addCleanup(self.stack.close)
        self.stack.enter_context(redirect_stdout(StringIO()))
        directory = self.stack.enter_context(TemporaryDirectory())
        self.deployer = Deployer({"repo_dir": directory, "state_dir": directory,
                                  "repository": REPO})
        self.active = {name: "sha256:active-" + name for name in ("api", "recommendation", "caddy")}
        self.stack.enter_context(patch.object(self.deployer, "image_ids", return_value=self.active))
        self.inventory = []
        self.removed = []
        self.cache_pruned = False
        self.command = self.stack.enter_context(patch.object(self.deployer, "run", side_effect=self.docker_command))
        for service, image in self.active.items():
            self.add_image("dalitu-" + service + ":rollback-123-" + OLD[:12], image)
        self.rollback = self.deployer.directory / "rollback" / "456-" / "snapshot"
        self.rollback.mkdir(parents=True)
        refs = {service: {"image": "dalitu-" + service + ":rollback-456-" + SHA[:12]}
                for service in self.active}
        for service, item in refs.items():
            self.add_image(item["image"], "sha256:rollback-" + service)
        (self.rollback / "override.json").write_text(json.dumps({"services": refs}))
        self.deployer.state["rollback_directory"] = str(self.rollback)

    def add_image(self, tag, image):
        repository, version = tag.split(":", 1)
        self.inventory.append({"Repository": repository, "Tag": version, "ID": image})

    def docker_command(self, *args, **_kwargs):
        if args == ("docker", "ps", "-aq"):
            return "running\nstopped"
        if args[:4] == ("docker", "inspect", "--format", "{{.Image}}"):
            return self.active["api"] + "\nsha256:stopped-container"
        if args[:3] == ("docker", "image", "ls"):
            return "\n".join(json.dumps(item) for item in self.inventory)
        if args[:3] == ("docker", "image", "rm"):
            self.assertEqual(4, len(args), "Removal must target one tag without force")
            self.removed.append(args[3])
            return ""
        if args[:3] == ("docker", "builder", "prune"):
            self.cache_pruned = True
            self.assertIn("--keep-storage", args)
            return ""
        self.fail("Unexpected cleanup command: " + repr(args))

    def test_only_obsolete_managed_builds_are_removed(self):
        obsolete = ["dalitu-api:git-" + "c" * 40,
                    "dalitu-recommendation:rollback-100-" + "d" * 12]
        for tag in obsolete:
            self.add_image(tag, "sha256:obsolete")
        self.add_image("dalitu-api:git-" + SHA, self.active["api"])
        self.add_image("dalitu-api:git-" + OLD, "sha256:rollback-api")
        self.add_image("dalitu-api:git-" + "e" * 40, "sha256:stopped-container")
        self.add_image("rabbitmq:latest", "sha256:unrelated")
        self.add_image("dalitu-api:operator-backup", "sha256:manual-backup")
        self.add_image("<none>:<none>", "sha256:unmanaged-dangling")
        self.deployer.cleanup_storage()
        self.assertEqual(sorted(obsolete), self.removed)
        self.assertTrue(self.cache_pruned)

    def test_state_and_interrupted_deployment_images_remain_protected(self):
        self.deployer.state.update({"images": {"api": "sha256:state"},
                                    "baseline_snapshot": {"images": {"api": "sha256:baseline"}},
                                    "pending": {"snapshot": {"images": {"api": "sha256:pending"}}}})
        for marker, image in [("c", "state"), ("d", "baseline"), ("e", "pending")]:
            self.add_image("dalitu-api:git-" + marker * 40, "sha256:" + image)
        self.deployer.cleanup_storage()
        self.assertEqual([], self.removed)

    def test_registry_cleanup_preserves_active_rollback_and_other_packages(self):
        repo = self.deployer.image_repository
        obsolete = [repo + ":" + "c" * 40, repo + ":recommendation-" + "d" * 40]
        for tag in obsolete:
            self.add_image(tag, "sha256:obsolete")
        self.add_image(repo + ":" + SHA, self.active["api"])
        self.add_image(repo + ":recommendation-" + OLD, "sha256:rollback-recommendation")
        self.add_image(repo + ":operator-backup", "sha256:backup")
        self.add_image("ghcr.io/other/project/api:" + "e" * 40, "sha256:other-package")
        self.deployer.cleanup_storage()
        self.assertEqual(sorted(obsolete), self.removed)

    def test_missing_rollback_image_prevents_any_removal(self):
        self.inventory = [item for item in self.inventory if item["ID"] != "sha256:rollback-api"]
        with self.assertRaises(KeyError):
            self.deployer.cleanup_storage()
        self.assertEqual([], self.removed)
        self.assertFalse(self.cache_pruned)

    def test_missing_or_external_checkpoint_prevents_any_removal(self):
        for directory in [self.deployer.directory / "rollback" / "missing", self.deployer.repo]:
            with self.subTest(directory=directory):
                self.deployer.state["rollback_directory"] = str(directory)
                with self.assertRaises((OSError, ValueError)):
                    self.deployer.cleanup_storage()
        self.assertEqual([], self.removed)
        self.assertFalse(self.cache_pruned)

    def test_container_inventory_error_prevents_any_removal(self):
        self.command.side_effect = subprocess.CalledProcessError(1, "docker")
        with self.assertRaises(subprocess.SubprocessError):
            self.deployer.cleanup_storage()
        self.assertEqual([], self.removed)

    def test_preflight_reclaims_space_before_checking_minimum(self):
        for name in (".env.ec2-api", "recommendation-service/.env.ec2"):
            path = self.deployer.repo / name
            path.parent.mkdir(exist_ok=True)
            path.touch()
        def git(*args):
            return {("branch", "--show-current"): "main",
                    ("status", "--porcelain", "--untracked-files=no"): "",
                    ("remote", "get-url", "origin"): "https://github.com/" + REPO + ".git"}[args]
        disk = type("Disk", (), {"free": 4 * 1024 ** 3})()
        with patch.object(self.deployer, "git", side_effect=git), \
                patch.object(self.deployer, "cleanup_storage") as cleanup, \
                patch("ec2_autodeploy.shutil.disk_usage", return_value=disk) as usage:
            cleanup.side_effect = lambda: self.assertEqual(0, usage.call_count)
            self.deployer.preflight()
            cleanup.assert_called_once()
            disk.free = 1024 ** 3
            cleanup.side_effect = None
            with self.assertRaisesRegex(ValueError, "after cleanup"):
                self.deployer.preflight()


class SnapshotTests(unittest.TestCase):
    def test_installer_allows_switching_to_the_git_checkout_owner(self):
        installer = Path(__file__).resolve().parents[1] / "install-ec2-autodeploy.sh"
        source = installer.read_text(encoding="utf-8")
        self.assertIn("User=root\n", source)
        self.assertIn("NoNewPrivileges=false\n", source)
        self.assertNotIn("NoNewPrivileges=true\n", source)

    def test_deferred_checkout_uses_saved_active_compose_not_unactivated_file(self):
        with TemporaryDirectory() as directory:
            root = Path(directory)
            repo, state = root / "repo", root / "state"
            repo.mkdir()
            baseline = state / "baseline"
            baseline.mkdir(parents=True)
            (repo / "docker-compose.ec2.yml").write_text("unactivated new config")
            (baseline / "docker-compose.ec2.yml").write_text("active old config")
            deployer = Deployer({"repo_dir": str(repo), "state_dir": str(state),
                                 "repository": REPO, "api_url": "http://127.0.0.1"})
            images = {name: "old-" + name for name in ("api", "recommendation", "caddy")}
            deployer.state["baseline_snapshot"] = {"directory": str(baseline), "images": images}
            def command(*args, **_kwargs):
                self.assertNotIn("inspect", args, "Mutable checkout label must not override the saved baseline")
                return "active caddy config" if "cat" in args else ""
            with patch.object(deployer, "image_ids", return_value=images), \
                    patch.object(deployer, "compose", return_value="container"), \
                    patch.object(deployer, "run", side_effect=command), \
                    patch("ec2_autodeploy.read_json", return_value={"commitSha": OLD}):
                snapshot = deployer.snapshot(SHA)
            saved = Path(snapshot["directory"])
            self.assertEqual("active old config", (saved / "docker-compose.ec2.yml").read_text())
            self.assertEqual("active caddy config\n", (saved / "Caddyfile").read_text())


class MessagingPreparationTests(unittest.TestCase):
    def test_prepares_broker_before_migration_without_restarting_application(self):
        with TemporaryDirectory() as directory:
            config = Path(directory) / "deploy/rabbitmq/rabbitmq.conf"
            config.parent.mkdir(parents=True)
            config.write_text("log.console = true\n")
            config.chmod(0o600)
            secret = Path(directory) / ".env.rabbitmq"
            secret.write_text("RABBITMQ_DEFAULT_PASS=isolated-test-only\n")
            secret.chmod(0o600)
            deployer = Deployer({"repo_dir": directory, "state_dir": str(Path(directory) / "state"), "repository": REPO})
            calls = []
            def compose(*args, **_kwargs):
                if args[0] == "up" and os.name != "nt":
                    self.assertEqual(0o644, stat.S_IMODE(config.stat().st_mode))
                    self.assertEqual(0o600, stat.S_IMODE(secret.stat().st_mode))
                calls.append(args)
                return "api\nrabbitmq\nmigrate" if args == ("config", "--services") else ""
            with patch.object(deployer, "compose", side_effect=compose), patch.object(deployer, "run"):
                deployer.prepare({}, {"images": {"caddy": "caddy:2"}})
            self.assertEqual(("config", "--services"), calls[0])
            self.assertEqual("rabbitmq", calls[1][-1])
            self.assertIn("--wait", calls[1])
            self.assertEqual("migrate", calls[2][-1])
            self.assertEqual(3, len(calls))

    def test_older_compose_without_broker_still_prepares_normally(self):
        with TemporaryDirectory() as directory:
            deployer = Deployer({"repo_dir": directory, "state_dir": str(Path(directory) / "state"), "repository": REPO})
            with patch.object(deployer, "compose", return_value="api\nmigrate") as compose, patch.object(deployer, "run"):
                deployer.prepare({}, {"images": {"caddy": "caddy:2"}})
            self.assertEqual(2, compose.call_count)


if __name__ == "__main__":
    unittest.main()
