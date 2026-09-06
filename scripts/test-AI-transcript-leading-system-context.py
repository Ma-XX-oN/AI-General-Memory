#!/usr/bin/env python3
"""Regression test for Claude transcript start and injected-context suppression."""

from __future__ import annotations

import os
import pathlib
import subprocess
import sys


ROOT = pathlib.Path(__file__).resolve().parent.parent
SCRIPT = ROOT / "scripts" / "AI-transcript.py"
FIXTURE = ROOT / "scripts" / "fixtures" / "claude-leading-system-context.jsonl"
CORE = ROOT / "dependencies" / "AIConversationCore"
PROMPT = "Can you provide me with simulations of these:"


def main() -> int:
  """Run the production transcript entry point and validate its visible start."""
  env = os.environ.copy()
  env["AI_CONVERSATION_CORE"] = str(CORE)
  result = subprocess.run(
    [sys.executable, str(SCRIPT), "--claude", "--file", str(FIXTURE)],
    cwd=ROOT,
    env=env,
    text=True,
    encoding="utf-8",
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    check=False,
  )
  if result.returncode != 0:
    raise AssertionError(
      f"AI-transcript.py exited {result.returncode}: {result.stderr.strip()}"
    )

  output = result.stdout
  lines = output.splitlines()
  if not lines or not lines[0].startswith("[claude] "):
    raise AssertionError(f"expected Claude metadata header first:\n{output}")
  first_body_line = next((line for line in lines[1:] if line.strip()), "")
  if first_body_line != "## User":
    raise AssertionError(
      "expected the first non-blank line after the metadata header to be "
      f"'## User', found {first_body_line!r}:\n{output}"
    )
  if output.count("## User") != 1:
    raise AssertionError(
      f"expected exactly one User heading, found {output.count('## User')}\n{output}"
    )
  if "ide_selection" in output or "repo is clean after the push" in output:
    raise AssertionError(f"injected IDE-selection content leaked into transcript:\n{output}")
  if f"## User\n\n> {PROMPT}" not in output:
    raise AssertionError(f"real first User prompt is missing or malformed:\n{output}")

  print("PASS: Claude transcript starts directly with the first real User turn")
  return 0


if __name__ == "__main__":
  raise SystemExit(main())
