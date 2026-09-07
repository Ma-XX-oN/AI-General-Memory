#!/usr/bin/env python3
"""Acceptance regression for Codex IDE context through the real CLI path."""

from __future__ import annotations

import json
import os
import pathlib
import subprocess
import sys
import tempfile


ROOT = pathlib.Path(__file__).resolve().parent.parent
SCRIPT = ROOT / "scripts" / "AI-transcript.py"
CORE = ROOT / "dependencies" / "AIConversationCore"
SESSION_ID = "01a07826-f445-7dd2-a370-3f3c7a3754a6"
PROMPT = "I'm doing some testing.  What time is it in Paris?"
CONTEXT_MESSAGE = (
  "# Context from my IDE setup:\n\n"
  "## Active file: sessions/example.jsonl\n\n"
  "## Active selection of the file:\n"
  " the repo instructions and the current transcript script first\n"
  "## Open tabs:\n"
  "- example.jsonl: sessions/example.jsonl\n\n"
  "## My request for Codex:\n"
  f"{PROMPT}"
)


def _write_session(codex_home: pathlib.Path, message: str) -> pathlib.Path:
  """Create one realistic Codex rollout that `--id latest` can discover."""
  session_dir = codex_home / "sessions" / "2026" / "09" / "06"
  session_dir.mkdir(parents=True)
  session_path = session_dir / (
    "rollout-2026-09-06T15-17-01-"
    f"{SESSION_ID}.jsonl"
  )
  records = [
    {
      "timestamp": "2026-09-06T19:17:01.000Z",
      "type": "session_meta",
      "payload": {"id": SESSION_ID},
    },
    {
      "timestamp": "2026-09-06T19:17:11.000Z",
      "type": "event_msg",
      "payload": {"type": "user_message", "message": message},
    },
  ]
  session_path.write_text(
    "".join(json.dumps(record, separators=(",", ":")) + "\n" for record in records),
    encoding="utf-8",
  )
  (codex_home / "session_index.jsonl").write_text(
    json.dumps({"id": SESSION_ID, "thread_name": "Check Paris time"}) + "\n",
    encoding="utf-8",
  )
  return session_path


def _run_latest(message: str) -> str:
  """Execute the same production CLI shape used by the reported failure."""
  with tempfile.TemporaryDirectory() as temp_dir:
    codex_home = pathlib.Path(temp_dir)
    _write_session(codex_home, message)
    env = os.environ.copy()
    env["AI_CONVERSATION_CORE"] = str(CORE)
    env["CODEX_HOME"] = str(codex_home)
    result = subprocess.run(
      [
        sys.executable,
        str(SCRIPT),
        "--id",
        "latest",
        "--codex",
        "-nd",
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
    return result.stdout


def _assert_context_projection() -> None:
  """Require the real CLI to expose Core #73's canonical context structure."""
  output = _run_latest(CONTEXT_MESSAGE)
  details = "> <details><summary># Context from my IDE setup:</summary>"
  if details not in output:
    raise AssertionError(
      "real CLI omitted the blockquoted IDE-context details disclosure:\n"
      f"{output}"
    )
  if "## My request for Codex:" in output:
    raise AssertionError(
      "real CLI leaked the removed Codex request marker:\n"
      f"{output}"
    )
  details_start = output.index(details)
  details_end = output.find("> </details>", details_start)
  prompt_at = output.find(PROMPT)
  if details_end < 0 or prompt_at <= details_end:
    raise AssertionError(
      "real CLI did not place the actual prompt after the context details block:\n"
      f"{output}"
    )
  prompt_line = next(
    (line for line in output.splitlines() if PROMPT in line),
    "",
  )
  if prompt_line.startswith(">"):
    raise AssertionError(
      "real CLI kept the actual prompt inside the context blockquote:\n"
      f"{output}"
    )
  ordered = [
    output.find("> ## Active file:", details_start),
    output.find("> ## Active selection of the file:", details_start),
    output.find("> ## Open tabs:", details_start),
  ]
  if not (ordered[0] >= 0 and ordered[0] < ordered[1] < ordered[2] < details_end):
    raise AssertionError(
      "real CLI changed or lost IDE-context section order:\n"
      f"{output}"
    )


def _assert_plain_user_is_unchanged() -> None:
  """Require ordinary Codex User messages to avoid an empty context disclosure."""
  output = _run_latest("Plain user prompt.")
  if "<details>" in output or "user_context" in output:
    raise AssertionError(
      "plain Codex User message emitted an IDE-context disclosure:\n"
      f"{output}"
    )
  if "Plain user prompt." not in output:
    raise AssertionError(f"plain Codex User prompt disappeared:\n{output}")


def main() -> int:
  """Run the production-entry-point acceptance checks."""
  _assert_context_projection()
  _assert_plain_user_is_unchanged()
  print("PASS: real AI-transcript.py --id latest --codex -nd renders Codex user context canonically")
  return 0


if __name__ == "__main__":
  raise SystemExit(main())
