#!/usr/bin/env python3
"""Regression checks for AI-transcript and AIConversationCore version identity."""

import json
import os
import re
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "AI-transcript.py"
WORKER = ROOT / "scripts" / "AI-transcript-core-worker.mjs"
CORE_ROOT = ROOT / "dependencies" / "AIConversationCore"
VERSION_PATTERN = re.compile(r"^\d+\.\d+\.\d+(?:-issue\.\d+\.\d+)?$")


def _run_version():
  """Return AI-transcript --version output after enforcing a clean invocation."""
  result = subprocess.run(
    [sys.executable, str(SCRIPT), "--version"],
    cwd=ROOT,
    text=True,
    capture_output=True,
    check=False,
  )
  assert result.returncode == 0, result.stderr
  assert result.stderr == "", result.stderr
  version = result.stdout.strip()
  assert VERSION_PATTERN.fullmatch(version), version
  return version


def _ping_core():
  """Return the worker ping response using the pinned Core checkout."""
  env = os.environ.copy()
  env["AI_CONVERSATION_CORE"] = str(CORE_ROOT)
  result = subprocess.run(
    ["node", str(WORKER)],
    cwd=ROOT,
    env=env,
    input='{"operation":"ping"}\n',
    text=True,
    capture_output=True,
    check=False,
  )
  assert result.returncode == 0, result.stderr
  lines = [line for line in result.stdout.splitlines() if line.strip()]
  assert len(lines) == 1, result.stdout
  response = json.loads(lines[0])
  assert response["ok"] is True
  return response


def main():
  """Verify caller version CLI plus Core semantic and commit identity."""
  _run_version()

  response = _ping_core()
  expected_commit = subprocess.check_output(
    ["git", "-C", str(CORE_ROOT), "rev-parse", "HEAD"],
    text=True,
  ).strip()
  package = json.loads((CORE_ROOT / "package.json").read_text(encoding="utf-8"))

  assert response["core_commit"] == expected_commit
  assert response["core_version"] == package["version"]
  assert VERSION_PATTERN.fullmatch(response["core_version"])
  print("PASS AI-transcript/Core version identity")


if __name__ == "__main__":
  main()
