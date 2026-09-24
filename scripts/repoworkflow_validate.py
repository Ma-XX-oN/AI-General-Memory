#!/usr/bin/env python3
from __future__ import annotations

import os
from pathlib import Path
import subprocess
import sys


ROOT = Path(__file__).resolve().parents[1]
PYTHON = sys.executable


def run(command: list[str], *, env: dict[str, str]) -> int:
  result = subprocess.run(command, cwd=ROOT, env=env)
  return result.returncode


def prerequisite(command: list[str], *, env: dict[str, str]) -> bool:
  if run(command, env=env) == 0:
    return True
  print("Prerequisite unavailable: " + " ".join(command), file=sys.stderr)
  return False


def main() -> int:
  env = dict(os.environ)
  env["PYTHONDONTWRITEBYTECODE"] = "1"

  if not prerequisite(
    ["git", "submodule", "update", "--init", "--recursive"],
    env=env,
  ):
    return 2
  if not prerequisite(
    [PYTHON, "-m", "pip", "install", "colorama", "regex"],
    env=env,
  ):
    return 2

  failures = 0
  for command in (
    [PYTHON, "-m", "unittest", "tests/test_repoworkflow_adoption.py"],
    [PYTHON, "scripts/ci_environment.py"],
  ):
    if run(command, env=env) != 0:
      failures += 1
  return 1 if failures else 0


if __name__ == "__main__":
  raise SystemExit(main())
