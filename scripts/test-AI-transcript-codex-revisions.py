#!/usr/bin/env python3
"""Regression tests for Codex rollback history, titles, and recorded IDE context."""

from __future__ import annotations

import os
import pathlib
import shutil
import subprocess
import sys
import tempfile


ROOT = pathlib.Path(__file__).resolve().parent.parent
SCRIPT = ROOT / "scripts" / "AI-transcript.py"
WORKER = ROOT / "scripts" / "AI-transcript-core-worker.mjs"
FIXTURE = ROOT / "scripts" / "fixtures" / "codex-revision-history.jsonl"
SESSION_INDEX = ROOT / "scripts" / "fixtures" / "codex-session-index.jsonl"
CORE = ROOT / "dependencies" / "AIConversationCore"
TITLE = "Check Paris time (MODIFIED)"
IDE_CONTEXT = "# Context from my IDE setup:"


def _run(*extra_args: str, include_index: bool = True) -> subprocess.CompletedProcess[str]:
  """Run the production transcript entry point with an isolated Codex home."""
  with tempfile.TemporaryDirectory() as temp_dir:
    codex_home = pathlib.Path(temp_dir)
    if include_index:
      shutil.copyfile(SESSION_INDEX, codex_home / "session_index.jsonl")
    env = os.environ.copy()
    env["AI_CONVERSATION_CORE"] = str(CORE)
    env["CODEX_HOME"] = str(codex_home)
    return subprocess.run(
      [
        sys.executable,
        str(SCRIPT),
        "--codex",
        "--file",
        str(FIXTURE),
        "-n",
        "-d",
        *extra_args,
      ],
      cwd=ROOT,
      env=env,
      text=True,
      encoding="utf-8",
      stdout=subprocess.PIPE,
      stderr=subprocess.PIPE,
      check=False,
    )


def _require_success(result: subprocess.CompletedProcess[str]) -> str:
  """Return stdout after requiring a successful production invocation."""
  if result.returncode != 0:
    raise AssertionError(
      f"AI-transcript.py exited {result.returncode}: {result.stderr.strip()}"
    )
  return result.stdout


def _assert_core_owns_session_index_parsing() -> None:
  """Require Python to discover only the index path and the core to parse it."""
  script_text = SCRIPT.read_text(encoding="utf-8")
  worker_text = WORKER.read_text(encoding="utf-8")
  if "def _codex_session_index_records" in script_text:
    raise AssertionError("Python still parses Codex session_index.jsonl records")
  if "def _codex_session_index_path" not in script_text:
    raise AssertionError("Python must discover the optional Codex session-index path")
  if "loadConversationSources" not in worker_text:
    raise AssertionError("Node worker must delegate supplied-source reading/parsing to the core")
  if "session_index_records" in worker_text:
    raise AssertionError("worker still accepts pre-parsed Codex session-index records")


def _assert_default_hides_history() -> None:
  """Require current-branch output by default while preserving recorded context."""
  output = _require_success(_run())
  if TITLE not in output:
    raise AssertionError(f"latest session-index title is missing:\n{output}")
  if "What is an apple" in output or "What is an tree?" in output or "What is an pool?" in output:
    raise AssertionError(f"rolled-back revisions leaked into default output:\n{output}")
  if "What is a puck?" not in output or "## User (edited)" not in output:
    raise AssertionError(f"current edited revision is not labelled correctly:\n{output}")
  if "Model changed from GPT-5.4 to GPT-5.5" not in output:
    raise AssertionError(f"Codex model-change event is missing:\n{output}")
  if IDE_CONTEXT not in output:
    raise AssertionError(f"recorded Codex IDE context was stripped:\n{output}")


def _assert_history_switch_exposes_revisions() -> None:
  """Require the explicit switch to expose original/superseded revisions."""
  output = _require_success(_run("--include-rolled-back"))
  required = (
    "## User (original, aborted)",
    "What is an apple",
    "## User (superseded)",
    "What is an tree?",
    "What is an pool?",
    "## User (edited)",
    "What is a puck?",
  )
  missing = [value for value in required if value not in output]
  if missing:
    raise AssertionError(f"historical revision output is missing {missing!r}:\n{output}")
  if output.count("## User (superseded)") != 2:
    raise AssertionError(f"expected exactly two superseded User revisions:\n{output}")
  if output.count(IDE_CONTEXT) != 4:
    raise AssertionError(f"IDE context must remain on every recorded User revision:\n{output}")


def _assert_missing_index_falls_back_cleanly() -> None:
  """Require a missing supplementary index to leave transcript rendering usable."""
  output = _require_success(_run(include_index=False))
  if "What is a puck?" not in output:
    raise AssertionError(f"missing session index broke Codex rendering:\n{output}")
  if TITLE in output:
    raise AssertionError(f"missing session index unexpectedly supplied indexed title:\n{output}")


def main() -> int:
  """Validate architecture, default/current history, and opt-in historical output."""
  _assert_core_owns_session_index_parsing()
  _assert_default_hides_history()
  _assert_history_switch_exposes_revisions()
  _assert_missing_index_falls_back_cleanly()
  print("PASS: Codex source ownership, title, history, model change, and IDE context are preserved")
  return 0


if __name__ == "__main__":
  raise SystemExit(main())
