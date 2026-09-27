#!/usr/bin/env python3
"""Enforce the permanent GitHub Actions workflow and repository-write policy."""

from __future__ import annotations

from pathlib import Path
import re
import sys


ROOT = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path(__file__).resolve().parents[1]
WORKFLOW_DIR = ROOT / ".github" / "workflows"
REQUIRED = {".github/workflows/ci.yml"}
ALLOWED = {
  ".github/workflows/ci.yml",
  ".github/workflows/ai-transcript-core-parity.yml",
  ".github/workflows/ai-transcript-codex-user-context.yml",
}
READ_ONLY = {
  ".github/workflows/ai-transcript-core-parity.yml",
  ".github/workflows/ai-transcript-codex-user-context.yml",
}


def fail(message: str) -> None:
  print(f"Actions policy violation: {message}", file=sys.stderr)
  raise SystemExit(1)


def has_contents_write(text: str) -> bool:
  return re.search(r"^\s*contents:\s*write\s*$", text, re.MULTILINE) is not None


def direct_repository_mutations(text: str) -> list[str]:
  commands = []
  for raw in text.splitlines():
    line = re.sub(r"^-?\s*run:\s*", "", raw.strip())
    if re.match(r"git\s+(?:add|commit|push)\b", line):
      commands.append(line)
    if re.match(r"(?:gh\s+api|curl)\b", line) and re.search(
      r"(?:--method|-X|--request)\s+(?:POST|PUT|PATCH|DELETE)\b",
      line,
      re.IGNORECASE,
    ):
      commands.append(line)
  return commands


def validate_ci(text: str) -> None:
  required_fragments = [
    "- '.github/workflows/**'",
    "python tests/test_actions_policy.py",
    "outputs:",
    "run_ci: ${{ steps.scope.outputs.run_ci }}",
    "needs: actions-policy",
    "if: needs.actions-policy.outputs.run_ci == 'true'",
  ]
  for fragment in required_fragments:
    if fragment not in text:
      fail(f"ci.yml is missing required policy/request-gating fragment: {fragment}")

  mutations = direct_repository_mutations(text)
  if mutations:
    fail(f"ci.yml contains direct repository mutation: {' | '.join(mutations)}")

  if has_contents_write(text):
    pattern = (
      r"python\s+scripts/ci_contract\.py\s+finalize\b"
      r"[\s\S]*?--tag\s+--push\b"
    )
    if re.search(pattern, text) is None:
      fail(
        "ci.yml grants contents: write without the approved "
        "ci_contract.py result-tag publication path"
      )


def validate_read_only(path: str, text: str) -> None:
  if has_contents_write(text):
    fail(f"{path} must remain read-only")
  if re.search(r"^\s*contents:\s*read\s*$", text, re.MULTILINE) is None:
    fail(f"{path} must explicitly declare contents: read")
  mutations = direct_repository_mutations(text)
  if mutations:
    fail(f"{path} contains repository mutation commands: {' | '.join(mutations)}")


if not WORKFLOW_DIR.is_dir():
  fail("missing .github/workflows directory")

workflow_paths = {
  f".github/workflows/{path.name}"
  for path in WORKFLOW_DIR.iterdir()
  if path.is_file() and path.suffix.lower() in {".yml", ".yaml"}
}

for required in REQUIRED:
  if required not in workflow_paths:
    fail(f"missing required permanent workflow {required}")

for workflow_path in sorted(workflow_paths):
  if workflow_path not in ALLOWED:
    fail(f"unexpected workflow file {workflow_path}")

  text = (ROOT / workflow_path).read_text(encoding="utf-8")
  if workflow_path == ".github/workflows/ci.yml":
    validate_ci(text)
  elif workflow_path in READ_ONLY:
    validate_read_only(workflow_path, text)
