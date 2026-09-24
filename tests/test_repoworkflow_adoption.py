from __future__ import annotations

import json
from pathlib import Path
import re
import subprocess
import sys
import unittest


ROOT = Path(__file__).resolve().parents[1]
REPOWORKFLOW_SHA = "120600d5cb9fed9afcd6b89365af4860bc67efc7"
VERSION_PATTERN = re.compile(r'^VERSION\s*=\s*"([^"]+)"\s*$', re.MULTILINE)


def read_text(relative: str) -> str:
  return (ROOT / relative).read_text(encoding="utf-8")


def read_json(relative: str) -> dict:
  return json.loads(read_text(relative))


class RepoWorkflowAdoptionTests(unittest.TestCase):
  def test_repoworkflow_is_pinned_real_submodule(self) -> None:
    modules = read_text(".gitmodules")
    self.assertIn('[submodule "RepoWorkflow"]', modules)
    self.assertIn("path = RepoWorkflow", modules)
    self.assertIn("url = https://github.com/Ma-XX-oN/RepoWorkflow.git", modules)
    tree = subprocess.run(
      ["git", "ls-tree", "HEAD", "RepoWorkflow"],
      cwd=ROOT,
      check=True,
      text=True,
      capture_output=True,
    ).stdout.strip()
    self.assertEqual(f"160000 commit {REPOWORKFLOW_SHA}\tRepoWorkflow", tree)

  def test_consumer_configuration_preserves_aigm_environment(self) -> None:
    self.assertEqual({
      "schema": 1,
      "versionCommand": ["python", "scripts/workflow_version.py"],
      "repository": {
        "integrationBranch": "master",
        "authoritativeRemote": "origin",
      },
      "environments": [{
        "id": "ubuntu-node22-python313",
        "required": True,
        "platform": "linux",
        "capabilities": ["node-22", "python-3.13"],
        "validationCommand": ["python", "scripts/repoworkflow_validate.py"],
      }],
    }, read_json(".ci/repoworkflow.json"))

  def test_github_mapping_and_branch_policy_are_repository_facts(self) -> None:
    self.assertEqual({
      "schema": 1,
      "prepareRunner": "ubuntu-latest",
      "runners": {"ubuntu-node22-python313": "ubuntu-latest"},
    }, read_json(".ci/github.json"))
    self.assertEqual({
      "schema": 1,
      "integrationBranch": "master",
      "branches": {
        "issue-21-repoworkflow-adoption": {
          "parent": "master",
          "allowedDependencies": [],
          "integrationTarget": "master",
        }
      },
      "patterns": [{
        "pattern": "issue-*",
        "parent": "master",
        "allowedDependencies": [],
      }],
    }, read_json(".ci/branch-policy.json"))

  def test_version_hook_matches_authoritative_version_source(self) -> None:
    source = read_text("scripts/AI_transcript_version.py")
    matches = VERSION_PATTERN.findall(source)
    self.assertEqual(1, len(matches))
    expected = matches[0]
    self.assertRegex(expected, r"^\d+\.\d+\.\d+-issue\.\d+\.\d+$")
    result = subprocess.run(
      [sys.executable, "scripts/workflow_version.py"],
      cwd=ROOT,
      text=True,
      capture_output=True,
    )
    self.assertEqual(0, result.returncode, result.stderr or result.stdout)
    self.assertEqual(expected, result.stdout.strip())

  def test_validation_hook_preserves_prerequisites_and_repository_validator(self) -> None:
    hook = read_text("scripts/repoworkflow_validate.py")
    self.assertIn("git", hook)
    self.assertIn("submodule", hook)
    self.assertIn("--recursive", hook)
    self.assertIn("colorama", hook)
    self.assertIn("regex", hook)
    self.assertIn("scripts/ci_environment.py", hook)
    self.assertIn("tests/test_ci_contract.py", hook)
    self.assertIn("tests/test_repoworkflow_adoption.py", hook)

  def test_github_ci_is_canonical_repoworkflow_adapter(self) -> None:
    self.assertEqual(
      read_text("RepoWorkflow/templates/github/ci.yml"),
      read_text(".github/workflows/ci.yml"),
    )


if __name__ == "__main__":
  unittest.main()
