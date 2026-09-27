import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "ci_contract.py"


def load_module():
  spec = importlib.util.spec_from_file_location("ci_contract", SCRIPT)
  module = importlib.util.module_from_spec(spec)
  assert spec.loader is not None
  spec.loader.exec_module(module)
  return module


class CiContractTests(unittest.TestCase):
  def setUp(self):
    self.ci = load_module()

  def test_complete_required_matrix_is_required_for_pass(self):
    config = {
      "environments": [
        {"id": "linux", "required": True},
        {"id": "windows", "required": True},
      ]
    }
    results = [
      {"schema": 1, "environment": "linux", "version": "1.0.0-issue.7.1", "commit": "abc", "status": "PASS"},
      {"schema": 1, "environment": "windows", "version": "1.0.0-issue.7.1", "commit": "abc", "status": "PASS"},
    ]
    outcome, tag, warnings = self.ci.evaluate_results(
      config, results, "1.0.0-issue.7.1", "abc"
    )
    self.assertEqual("PASS", outcome)
    self.assertEqual("v1.0.0-issue.7.1", tag)
    self.assertEqual([], warnings)

  def test_complete_genuine_failure_gets_ci_fail_tag(self):
    config = {
      "environments": [
        {"id": "linux", "required": True},
        {"id": "windows", "required": True},
      ]
    }
    results = [
      {"schema": 1, "environment": "linux", "version": "1.0.0-issue.7.1", "commit": "abc", "status": "FAIL"},
      {"schema": 1, "environment": "windows", "version": "1.0.0-issue.7.1", "commit": "abc", "status": "PASS"},
    ]
    outcome, tag, _ = self.ci.evaluate_results(
      config, results, "1.0.0-issue.7.1", "abc"
    )
    self.assertEqual("FAIL", outcome)
    self.assertEqual("v1.0.0-issue.7.1-CI-FAIL", tag)

  def test_missing_or_incomplete_required_result_never_tags(self):
    config = {
      "environments": [
        {"id": "linux", "required": True},
        {"id": "windows", "required": True},
      ]
    }
    outcome, tag, _ = self.ci.evaluate_results(
      config,
      [{"schema": 1, "environment": "linux", "version": "1.0.0-issue.7.1", "commit": "abc", "status": "PASS"}],
      "1.0.0-issue.7.1",
      "abc",
    )
    self.assertEqual("INCOMPLETE", outcome)
    self.assertIsNone(tag)

    outcome, tag, _ = self.ci.evaluate_results(
      config,
      [
        {"schema": 1, "environment": "linux", "version": "1.0.0-issue.7.1", "commit": "abc", "status": "PASS"},
        {"schema": 1, "environment": "windows", "version": "1.0.0-issue.7.1", "commit": "abc", "status": "INCOMPLETE"},
      ],
      "1.0.0-issue.7.1",
      "abc",
    )
    self.assertEqual("INCOMPLETE", outcome)
    self.assertIsNone(tag)

  def test_result_identity_mismatch_is_contract_error(self):
    config = {"environments": [{"id": "linux", "required": True}]}
    with self.assertRaises(self.ci.CiContractError):
      self.ci.evaluate_results(
        config,
        [{"schema": 1, "environment": "linux", "version": "1.0.0-issue.7.2", "commit": "abc", "status": "PASS"}],
        "1.0.0-issue.7.1",
        "abc",
      )

  def test_independent_validation_gates_continue_after_failure(self):
    with tempfile.TemporaryDirectory() as td:
      root = Path(td)
      subprocess.run(["git", "init"], cwd=root, check=True, capture_output=True)
      subprocess.run(["git", "config", "user.email", "ci-test@example.invalid"], cwd=root, check=True)
      subprocess.run(["git", "config", "user.name", "CI test"], cwd=root, check=True)
      (root / ".ci").mkdir()
      (root / "VERSION").write_text("1.0.0-issue.7.1\n", encoding="utf-8")
      (root / ".ci" / "run-ci-request").write_text("1.0.0-issue.7.1\n", encoding="utf-8")
      subprocess.run(["git", "add", "."], cwd=root, check=True)
      subprocess.run(["git", "commit", "-m", "fixture"], cwd=root, check=True, capture_output=True)
      config = {
        "version": {"kind": "plain", "path": "VERSION"},
        "environments": [{
          "id": "local",
          "runner": "local",
          "required": True,
          "steps": [
            {"name": "first fails", "kind": "validation", "command": [sys.executable, "-c", "raise SystemExit(1)"]},
            {"name": "second still runs", "kind": "validation", "command": [sys.executable, "-c", "print('ran')"]},
          ],
        }],
      }
      result_path = root.parent / f"{root.name}-result.json"
      try:
        rc = self.ci.run_environment(config, "local", result_path, root)
        result = json.loads(result_path.read_text(encoding="utf-8"))
      finally:
        result_path.unlink(missing_ok=True)
      self.assertEqual(1, rc)
      self.assertEqual("FAIL", result["status"])
      self.assertEqual(2, len(result["steps"]))
      self.assertEqual("second still runs", result["steps"][1]["name"])

  def test_result_tag_for_iteration_is_single_immutable_outcome(self):
    with tempfile.TemporaryDirectory() as td:
      root = Path(td)
      subprocess.run(["git", "init"], cwd=root, check=True, capture_output=True)
      subprocess.run(["git", "config", "user.email", "ci-test@example.invalid"], cwd=root, check=True)
      subprocess.run(["git", "config", "user.name", "CI test"], cwd=root, check=True)
      (root / "fixture").write_text("x\n", encoding="utf-8")
      subprocess.run(["git", "add", "."], cwd=root, check=True)
      subprocess.run(["git", "commit", "-m", "fixture"], cwd=root, check=True, capture_output=True)
      sha = subprocess.run(
        ["git", "rev-parse", "HEAD"],
        cwd=root,
        check=True,
        capture_output=True,
        text=True,
      ).stdout.strip()
      version = "1.0.0-issue.7.1"
      self.ci.create_tag(root, version, f"v{version}-CI-FAIL", sha, False)
      with self.assertRaises(self.ci.CiContractError):
        self.ci.create_tag(root, version, f"v{version}", sha, False)

  def test_workflow_is_request_gated_and_repository_runner_owns_tests(self):
    workflow = (ROOT / ".github" / "workflows" / "ci.yml").read_text(encoding="utf-8")
    environment = (ROOT / "scripts" / "ci_environment.py").read_text(encoding="utf-8")
    self.assertIn(".ci/run-ci-request", workflow)
    self.assertNotIn("pull_request:", workflow)
    self.assertIn("strategy:", workflow)
    self.assertIn("fail-fast: false", workflow)
    for required in (
      "test-AI-transcript-phase6-parity.py",
      "test-AI-transcript-core-parity.py",
      "test-AI-transcript-turn-id.py",
      "test-AI-transcript-leading-system-context.py",
      "test-AI-transcript-codex-revisions.py",
      "test-AI-transcript-codex-user-context-cli.py",
      "AI-transcript-tests.sh",
      '"npm", "test"',
      '"git", "diff", "--check"',
    ):
      self.assertIn(required, environment)


if __name__ == "__main__":
  unittest.main()
