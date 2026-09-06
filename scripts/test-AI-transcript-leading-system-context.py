#!/usr/bin/env python3
"""Regression tests for Claude title normalization and transcript start."""

from __future__ import annotations

import importlib.util
import os
import pathlib
import subprocess
import sys


ROOT = pathlib.Path(__file__).resolve().parent.parent
SCRIPT = ROOT / "scripts" / "AI-transcript.py"
FIXTURE = ROOT / "scripts" / "fixtures" / "claude-leading-system-context.jsonl"
CORE = ROOT / "dependencies" / "AIConversationCore"
PROMPT = "Can you provide me with simulations of these:"


def _load_script_module():
  """Load AI-transcript.py so source-level metadata helpers can be tested."""
  spec = importlib.util.spec_from_file_location("ai_transcript", SCRIPT)
  if spec is None or spec.loader is None:
    raise AssertionError(f"could not load {SCRIPT}")
  module = importlib.util.module_from_spec(spec)
  sys.modules[spec.name] = module
  spec.loader.exec_module(module)
  return module


def _assert_source_title_is_one_line() -> None:
  """Assert Claude metadata extraction itself produces the canonical title."""
  module = _load_script_module()
  title, _ctime, _rc = module._cl_session_meta(str(FIXTURE))
  if title != PROMPT:
    raise AssertionError(
      "Claude session metadata must derive its title from the first non-empty "
      f"visible user line; found {title!r}"
    )
  if "\n" in title or "\r" in title:
    raise AssertionError(f"Claude session title is multiline: {title!r}")


def _assert_production_output_boundary() -> None:
  """Run the production entry point and validate its metadata/body boundary."""
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
  lines = output.splitlines()
  nonblank = [line for line in lines if line.strip()]
  if len(nonblank) < 3:
    raise AssertionError(f"transcript output is unexpectedly short:\n{output}")
  if not nonblank[0].startswith("[claude] "):
    raise AssertionError(f"expected Claude metadata header first:\n{output}")
  if nonblank[1] != f"(claude-l) {PROMPT}":
    raise AssertionError(
      "expected exactly one one-line session title after metadata header, "
      f"found {nonblank[1]!r}:\n{output}"
    )
  if not nonblank[2].startswith("## User ") or not nonblank[2].endswith(":  3:"):
    raise AssertionError(
      "expected canonical User heading immediately after the two stdout metadata "
      f"lines, found {nonblank[2]!r}:\n{output}"
    )
  if output.count("## User") != 1:
    raise AssertionError(
      f"expected exactly one User heading, found {output.count('## User')}\n{output}"
    )
  if "ide_selection" in output or "repo is clean after the push" in output:
    raise AssertionError(f"injected IDE-selection content leaked into transcript:\n{output}")
  if PROMPT not in output:
    raise AssertionError(f"real first User prompt is missing:\n{output}")


def main() -> int:
  """Validate both the title producer and the final production boundary."""
  _assert_source_title_is_one_line()
  _assert_production_output_boundary()
  print("PASS: Claude title is normalized at source and transcript boundary is clean")
  return 0


if __name__ == "__main__":
  raise SystemExit(main())
