#!/usr/bin/env python3
"""Regression coverage for the AI-General-Memory GitHub Actions policy."""

from __future__ import annotations

import shutil
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


HERE = Path(__file__).resolve().parent
REPOSITORY_ROOT = HERE.parent
CHECKER = REPOSITORY_ROOT / "scripts" / "check_actions_policy.py"


def make_root(workflows: dict[str, str]) -> Path:
  root = Path(tempfile.mkdtemp(prefix="aigm-actions-policy-"))
  workflow_dir = root / ".github" / "workflows"
  workflow_dir.mkdir(parents=True)
  for name, text in workflows.items():
    (workflow_dir / name).write_text(text, encoding="utf-8")
  return root


def run_checker(root: Path) -> subprocess.CompletedProcess[str]:
  return subprocess.run(
    [sys.executable, str(CHECKER), str(root)],
    check=False,
    text=True,
    capture_output=True,
  )


GOOD_CI = """name: CI
on:
  push:
    paths:
      - '.ci/run-ci-request'
      - '.github/workflows/**'
permissions:
  contents: read
jobs:
  actions-policy:
    outputs:
      run_ci: ${{ steps.scope.outputs.run_ci }}
    steps:
      - run: python tests/test_actions_policy.py
      - id: scope
        run: echo scope
  prepare:
    needs: actions-policy
    if: needs.actions-policy.outputs.run_ci == 'true'
    steps: []
"""


class ActionsPolicyTests(unittest.TestCase):
  def setUp(self) -> None:
    self.roots: list[Path] = []

  def tearDown(self) -> None:
    for root in self.roots:
      shutil.rmtree(root, ignore_errors=True)

  def root(self, workflows: dict[str, str]) -> Path:
    root = make_root(workflows)
    self.roots.append(root)
    return root

  def test_current_repository_workflows_satisfy_policy(self) -> None:
    result = run_checker(REPOSITORY_ROOT)
    self.assertEqual(0, result.returncode, result.stderr)

  def test_accepts_main_ci_policy_and_request_gate(self) -> None:
    result = run_checker(self.root({"ci.yml": GOOD_CI}))
    self.assertEqual(0, result.returncode, result.stderr)

  def test_accepts_optional_read_only_validation_workflows(self) -> None:
    root = self.root({
      "ci.yml": GOOD_CI,
      "ai-transcript-core-parity.yml": (
        "name: Core parity\npermissions:\n  contents: read\njobs: {}\n"
      ),
      "ai-transcript-codex-user-context.yml": (
        "name: Codex acceptance\npermissions:\n  contents: read\njobs: {}\n"
      ),
    })
    result = run_checker(root)
    self.assertEqual(0, result.returncode, result.stderr)

  def test_rejects_missing_ci(self) -> None:
    result = run_checker(self.root({}))
    self.assertNotEqual(0, result.returncode)
    self.assertIn("missing required permanent workflow", result.stderr)

  def test_rejects_unexpected_one_shot_workflow(self) -> None:
    root = self.root({
      "ci.yml": GOOD_CI,
      "issue999-fix.yml": "name: one shot\njobs: {}\n",
    })
    result = run_checker(root)
    self.assertNotEqual(0, result.returncode)
    self.assertIn("unexpected workflow file", result.stderr)

  def test_rejects_repository_write_on_validation_workflow(self) -> None:
    root = self.root({
      "ci.yml": GOOD_CI,
      "ai-transcript-core-parity.yml": (
        "name: Parity\npermissions:\n  contents: write\njobs: {}\n"
      ),
    })
    result = run_checker(root)
    self.assertNotEqual(0, result.returncode)
    self.assertIn("must remain read-only", result.stderr)

  def test_rejects_direct_git_push_from_ci(self) -> None:
    root = self.root({
      "ci.yml": GOOD_CI + "\n# bad\nrun: git push origin HEAD\n",
    })
    result = run_checker(root)
    self.assertNotEqual(0, result.returncode)
    self.assertIn("direct repository mutation", result.stderr)

  def test_rejects_write_permission_without_ci_contract_finalizer(self) -> None:
    bad = GOOD_CI + "\nfinalize:\n  permissions:\n    contents: write\n"
    result = run_checker(self.root({"ci.yml": bad}))
    self.assertNotEqual(0, result.returncode)
    self.assertIn("result-tag publication path", result.stderr)

  def test_accepts_ci_contract_result_tag_publication(self) -> None:
    good = GOOD_CI + """
  finalize:
    permissions:
      contents: write
    steps:
      - run: >-
          python scripts/ci_contract.py finalize
          --results-dir out
          --tag --push
"""
    result = run_checker(self.root({"ci.yml": good}))
    self.assertEqual(0, result.returncode, result.stderr)

  def test_rejects_ci_without_workflow_policy_trigger(self) -> None:
    bad = GOOD_CI.replace("      - '.github/workflows/**'\n", "")
    result = run_checker(self.root({"ci.yml": bad}))
    self.assertNotEqual(0, result.returncode)
    self.assertIn("workflow", result.stderr)

  def test_rejects_ci_without_policy_dependency(self) -> None:
    bad = GOOD_CI.replace("    needs: actions-policy\n", "")
    result = run_checker(self.root({"ci.yml": bad}))
    self.assertNotEqual(0, result.returncode)
    self.assertIn("needs: actions-policy", result.stderr)


if __name__ == "__main__":
  unittest.main()
