from contextlib import ExitStack, redirect_stdout
from copy import deepcopy
from io import StringIO
import json
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

    def test_only_expected_staging_skip_is_allowed(self):
        self.jobs.append({"name": "deploy-staging", "status": "completed", "conclusion": "skipped"})
        self.assertIsNone(self.reason())
        self.jobs.append({"name": "future-check", "status": "completed", "conclusion": "skipped"})
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
                    "build": ({}, {"api": "new-api", "recommendation": "new-rec"}),
                    "prepare": None, "tip": SHA, "activate": None,
                    "verify": {"api": "new-api", "recommendation": "new-rec"}, "rollback": None,
                    "eligible": (SHA, 123), "set_default_image_tags": None}
        self.mocks = {name: self.stack.enter_context(patch.object(self.deployer, name, return_value=value))
                      for name, value in defaults.items()}

    def test_build_failure_leaves_running_services_untouched(self):
        self.mocks["build"].side_effect = OSError("simulated build failure")
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

    def test_newer_main_during_build_prevents_activation(self):
        self.mocks["tip"].return_value = "c" * 40
        self.deployer.deploy(SHA, 123)
        self.mocks["activate"].assert_not_called()
        self.mocks["rollback"].assert_not_called()
        self.assertNotIn("failed_sha", self.deployer.state)
        self.assertEqual(self.snapshot, self.deployer.state["baseline_snapshot"])

    def test_changed_ci_or_vercel_checks_during_build_prevent_activation(self):
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

    def test_interrupted_build_does_not_restart_services(self):
        self.deployer.state["pending"] = {"sha": SHA, "phase": "build", "snapshot": self.snapshot}
        self.deployer.recover_interrupted()
        self.mocks["rollback"].assert_not_called()
        self.assertEqual(SHA, self.deployer.state["failed_sha"])


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


if __name__ == "__main__":
    unittest.main()
