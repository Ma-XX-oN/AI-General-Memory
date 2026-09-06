#!/usr/bin/env python3
"""Regression test for Claude transcript start and injected-context suppression."""

from __future__ import annotations

import os
import pathlib
import re
import subprocess
import sys


ROOT = pathlib.Path(__file__).resolve().parent.parent
SCRIPT = ROOT / "scripts" / "AI-transcript.py"
FIXTURE = ROOT / "scripts" / "fixtures" / "claude-leading-system-context.jsonl"
CORE = ROOT / "dependencies" / "AIConversationCore"
PROMPT = "Can you provide me with simulations of these:"
TITLE_PREFIX = "(claude-l) "


def main() -> int:
  """Run the production transcript entry point and validate its visible start."""
  env = os.environ.copy()
  env["AI_CONVERSATION_CORE"] = str(CORE)
  result = subprocess.run(
    [
      sys.executable,
      str(SCRIPT),
      "--claude",
      "--file",
      str(FIXTURE),
      "-n",
      "-d",
    ],
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
  nonblank = [line for line in output.splitlines() if line.strip()]
  if len(nonblank) < 3:
    raise AssertionError(f"transcript output is unexpectedly short:\n{output}")
  if not nonblank[0].startswith("[claude] "):
    raise AssertionError(f"expected Claude metadata header first:\n{output}")
  if nonblank[1] != f"{TITLE_PREFIX}{PROMPT}":
    raise AssertionError(
      "expected exactly one single-line AI-transcript.py session-title header, "
      f"found {nonblank[1]!r}:\n{output}"
    )
  if not re.fullmatch(r"## User .*:\s+3:", nonblank[2]):
    raise AssertionError(
      "expected the canonical first User heading immediately after the two "
      f"AI-transcript.py metadata lines, found {nonblank[2]!r}:\n{output}"
    )
  if output.count("## User") != 1:
    raise AssertionError(
      f"expected exactly one User heading, found {output.count('## User')}\n{output}"
    )
  if "ide_selection" in output or "repo is clean after the push" in output:
    raise AssertionError(f"injected IDE-selection content leaked into transcript:\n{output}")
  if f"> {PROMPT}" not in output:
    raise AssertionError(f"real first User prompt is missing or malformed:\n{output}")

  print(
    "PASS: Claude transcript keeps exactly two stdout metadata lines before "
    "the first canonical User turn"
  )
  return 0


if __name__ == "__main__":
  raise SystemExit(main())
