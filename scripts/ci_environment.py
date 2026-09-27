#!/usr/bin/env python3
"""Run the complete AI-General-Memory validation surface outside Actions YAML."""

from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
CORE = ROOT / "dependencies" / "AIConversationCore"
PYTHON = sys.executable
FAILURES: list[str] = []


def command_text(command: list[str]) -> str:
  """Render a command vector for durable diagnostics."""
  return " ".join(command)


def run_gate(
  name: str,
  command: list[str],
  *,
  cwd: Path = ROOT,
  env: dict[str, str] | None = None,
  input_text: str | None = None,
) -> subprocess.CompletedProcess[str] | None:
  """Run one independent validation gate and record a genuine failure."""
  print(f"\n=== {name} ===")
  print(f"$ {command_text(command)}")
  try:
    result = subprocess.run(
      command,
      cwd=cwd,
      env=env,
      input=input_text,
      text=True,
      capture_output=True,
    )
  except OSError as exc:
    print(f"{name}: FAILED: {exc}", file=sys.stderr)
    FAILURES.append(name)
    return None
  if result.stdout:
    print(result.stdout, end="")
  if result.stderr:
    print(result.stderr, end="", file=sys.stderr)
  if result.returncode:
    print(f"{name}: FAILED (exit {result.returncode})", file=sys.stderr)
    FAILURES.append(name)
    return result
  print(f"{name}: PASS")
  return result


def git_output(*args: str, cwd: Path = ROOT) -> str:
  """Run a required-success Git query and return stripped stdout."""
  return subprocess.run(
    ["git", *args],
    cwd=cwd,
    check=True,
    text=True,
    capture_output=True,
  ).stdout.strip()


def core_environment() -> dict[str, str]:
  """Return the environment used by production AI-transcript/Core gates."""
  env = dict(os.environ)
  env["AI_CONVERSATION_CORE"] = str(CORE)
  return env


def verify_core_identity() -> None:
  """Verify the gitlink, initialized submodule, and worker identity agree."""
  name = "Pinned AIConversationCore identity"
  try:
    expected = git_output("rev-parse", "HEAD:dependencies/AIConversationCore")
    actual = git_output("rev-parse", "HEAD", cwd=CORE)
  except (OSError, subprocess.CalledProcessError) as exc:
    print(f"{name}: FAILED: {exc}", file=sys.stderr)
    FAILURES.append(name)
    return
  if expected != actual:
    print(f"{name}: FAILED: expected {expected}, found {actual}", file=sys.stderr)
    FAILURES.append(name)
    return

  result = run_gate(
    name,
    ["node", "scripts/AI-transcript-core-worker.mjs"],
    input_text='{"operation":"ping"}\n',
  )
  if result is None or result.returncode:
    return
  try:
    response = json.loads(result.stdout.strip())
    assert response["ok"] is True
    assert response["core_commit"] == expected
  except (AssertionError, KeyError, json.JSONDecodeError) as exc:
    print(f"{name}: FAILED: invalid worker identity: {exc}", file=sys.stderr)
    if name not in FAILURES:
      FAILURES.append(name)


def resolve_master_sha() -> str:
  """Resolve the repository master commit from a full clean clone."""
  for ref in ("refs/remotes/origin/master", "refs/heads/master"):
    result = subprocess.run(
      ["git", "rev-parse", "-q", "--verify", ref],
      cwd=ROOT,
      text=True,
      capture_output=True,
    )
    if result.returncode == 0:
      return result.stdout.strip()
  raise RuntimeError("Full checkout does not contain master history")


def verify_pull_helper() -> None:
  """Exercise the real pull helper using local remotes instead of network transport."""
  name = "Pull helper from uninitialized clone"
  try:
    master_sha = resolve_master_sha()
  except RuntimeError as exc:
    print(f"{name}: FAILED: {exc}", file=sys.stderr)
    FAILURES.append(name)
    return

  with tempfile.TemporaryDirectory(prefix="aigm-pull-helper-") as temp_name:
    temp = Path(temp_name)
    remote = temp / "aigm.git"
    clone = temp / "clone"
    init = run_gate(
      f"{name} fixture remote",
      ["git", "init", "--bare", str(remote)],
    )
    if init is None or init.returncode:
      return
    publish = run_gate(
      f"{name} fixture master",
      ["git", "push", str(remote), f"{master_sha}:refs/heads/master"],
    )
    if publish is None or publish.returncode:
      return
    cloned = run_gate(
      f"{name} clone",
      ["git", "clone", "--no-recurse-submodules", "--branch", "master", str(remote), str(clone)],
    )
    if cloned is None or cloned.returncode:
      return

    env = dict(os.environ)
    core_uri = CORE.resolve().as_uri()
    env.update({
      "GIT_CONFIG_COUNT": "2",
      "GIT_CONFIG_KEY_0": "protocol.file.allow",
      "GIT_CONFIG_VALUE_0": "always",
      "GIT_CONFIG_KEY_1": f"url.{core_uri}.insteadOf",
      "GIT_CONFIG_VALUE_1": "https://github.com/Ma-XX-oN/AIConversationCore.git",
    })
    helper = run_gate(
      name,
      ["bash", "pull-AI-General-Memory.sh"],
      cwd=clone,
      env=env,
    )
    if helper is None or helper.returncode:
      return
    try:
      expected = git_output("rev-parse", "HEAD:dependencies/AIConversationCore", cwd=clone)
      actual = git_output("rev-parse", "HEAD", cwd=clone / "dependencies" / "AIConversationCore")
      if expected != actual:
        raise RuntimeError(f"expected Core {expected}, found {actual}")
    except (OSError, RuntimeError, subprocess.CalledProcessError) as exc:
      print(f"{name}: FAILED: {exc}", file=sys.stderr)
      if name not in FAILURES:
        FAILURES.append(name)


def materialize_legacy_baseline(path: Path) -> bool:
  """Materialize the independently established pre-Phase-6 production baseline."""
  name = "Materialize pre-Phase-6 production baseline"
  result = subprocess.run(
    [
      "git",
      "show",
      "abcc2f33783e3690b9e1335161c73e7dabaed757:scripts/AI-transcript.py",
    ],
    cwd=ROOT,
    text=True,
    capture_output=True,
  )
  if result.returncode:
    if result.stderr:
      print(result.stderr, end="", file=sys.stderr)
    print(f"{name}: FAILED", file=sys.stderr)
    FAILURES.append(name)
    return False
  path.write_text(result.stdout, encoding="utf-8")
  print(f"{name}: PASS")
  return True


def run_validation() -> int:
  """Run every existing AIGM/Core validation gate with independent failure visibility."""
  env = core_environment()

  run_gate("Pull-helper shell syntax", ["bash", "-n", "pull-AI-General-Memory.sh"])
  verify_core_identity()
  run_gate(
    "AI-transcript and Core version identity",
    [PYTHON, "scripts/test-AI-transcript-version.py"],
    env=env,
  )
  verify_pull_helper()

  py_compile_files = [
    "scripts/AI-transcript.py",
    "scripts/AI_transcript_version.py",
    "scripts/test-AI-transcript-version.py",
    "scripts/test-AI-transcript-phase6-parity.py",
    "scripts/test-AI-transcript-core-parity.py",
    "scripts/test-AI-transcript-turn-id.py",
    "scripts/test-AI-transcript-leading-system-context.py",
    "scripts/test-AI-transcript-codex-revisions.py",
    "scripts/test-AI-transcript-codex-user-context-cli.py",
  ]
  run_gate("Python syntax", [PYTHON, "-m", "py_compile", *py_compile_files])

  with tempfile.TemporaryDirectory(prefix="aigm-baseline-") as temp_name:
    baseline = Path(temp_name) / "AI-transcript-legacy.py"
    if materialize_legacy_baseline(baseline):
      historical_env = dict(env)
      historical_env["LEGACY_AI_TRANSCRIPT"] = str(baseline)
      run_gate(
        "Historical presentation parity",
        [PYTHON, "scripts/test-AI-transcript-phase6-parity.py"],
        env=historical_env,
      )

  run_gate(
    "Canonical production parity",
    [PYTHON, "scripts/test-AI-transcript-core-parity.py"],
    env=env,
  )
  run_gate(
    "Turn-ID and record-number projection",
    [PYTHON, "scripts/test-AI-transcript-turn-id.py"],
    env=env,
  )
  run_gate(
    "Leading Claude system-context regression",
    [PYTHON, "scripts/test-AI-transcript-leading-system-context.py"],
    env=env,
  )
  run_gate(
    "Codex revision-history regression",
    [PYTHON, "scripts/test-AI-transcript-codex-revisions.py"],
    env=env,
  )
  run_gate(
    "Codex user-context CLI acceptance",
    [PYTHON, "scripts/test-AI-transcript-codex-user-context-cli.py"],
    env=env,
  )

  portable_env = dict(env)
  portable_env["TERM"] = "xterm"
  run_gate(
    "Portable AI-transcript regression subset",
    ["bash", "scripts/AI-transcript-tests.sh", *[str(value) for value in range(69, 106)]],
    env=portable_env,
  )
  run_gate("Core regression suite", ["npm", "test"], cwd=CORE)
  run_gate("Diff hygiene", ["git", "diff", "--check"])

  print("\n=== AI-General-Memory CI summary ===")
  if FAILURES:
    print(f"FAIL: {len(FAILURES)} gate(s) failed:", file=sys.stderr)
    for name in FAILURES:
      print(f"- {name}", file=sys.stderr)
    return 1
  print("PASS: all repository-owned AI-General-Memory gates passed.")
  return 0


if __name__ == "__main__":
  raise SystemExit(run_validation())
