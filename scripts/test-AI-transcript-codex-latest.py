#!/usr/bin/env python3
"""Regression tests for Codex --id latest skipping Guardian review sessions (#24)."""

from __future__ import annotations

import json
import os
import pathlib
import subprocess
import sys
import tempfile


ROOT = pathlib.Path(__file__).resolve().parent.parent
SCRIPT = ROOT / "scripts" / "AI-transcript.py"

USER_ID = "01a1e51b-7e6a-7ce0-8d85-48bac7eee942"
USER_TITLE = "Create PG for RWF 51 (2)"
GUARDIAN_ID = "01a1e51b-8055-7ea3-b0e5-e346f57f64fc"
GUARDIAN_TITLE = "Guardian review"


def _write_session(day_dir: pathlib.Path, sid: str, second: int, meta: dict, text: str) -> None:
  """Write a minimal Codex rollout file whose session_meta payload includes *meta*."""
  day_dir.mkdir(parents=True, exist_ok=True)
  records = [
    {"timestamp": "2026-11-16T16:05:46.000Z", "type": "session_meta",
     "payload": {"id": sid, **meta}},
    {"timestamp": "2026-11-16T16:05:47.000Z", "type": "event_msg",
     "payload": {"type": "user_message", "message": text}},
  ]
  path = day_dir / f"rollout-2026-11-16T11-05-{second:02d}-{sid}.jsonl"
  path.write_text("".join(json.dumps(r) + "\n" for r in records), encoding="utf-8")


def _run(*args: str) -> subprocess.CompletedProcess[str]:
  """Run the production entry point against an isolated Codex home.

  The Guardian review is the newest index entry, as in the real case where it
  was created 0.5 s after the user's fork.
  """
  with tempfile.TemporaryDirectory() as temp_dir:
    codex_home = pathlib.Path(temp_dir)
    day_dir = codex_home / "sessions" / "2026" / "11" / "16"
    _write_session(day_dir, USER_ID, 46, {"thread_source": "user"}, "user prompt")
    _write_session(day_dir, GUARDIAN_ID, 47,
                   {"thread_source": "guardian_review",
                    "source": {"subagent": {"other": "guardian"}}},
                   "guardian prompt")
    index = [
      {"id": USER_ID, "thread_name": USER_TITLE, "updated_at": "2026-11-16T16:05:47.6644535Z"},
      {"id": GUARDIAN_ID, "thread_name": GUARDIAN_TITLE, "updated_at": "2026-11-16T16:05:47.7023253Z"},
    ]
    (codex_home / "session_index.jsonl").write_text(
      "".join(json.dumps(e) + "\n" for e in index), encoding="utf-8"
    )
    env = os.environ.copy()
    env["CODEX_HOME"] = str(codex_home)
    return subprocess.run(
      [sys.executable, str(SCRIPT), "--codex", *args],
      cwd=ROOT, env=env, text=True, encoding="utf-8",
      stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False,
    )


def _ok(result: subprocess.CompletedProcess[str], what: str) -> str:
  """Return stdout after requiring a successful run."""
  if result.returncode != 0:
    raise AssertionError(f"{what} exited {result.returncode}:\n{result.stderr}")
  return result.stdout


def main() -> int:
  """Validate that latest skips Guardian reviews, which stay listed and selectable."""
  latest = _ok(_run("--id", "latest", "--ls"), "--id latest")
  if f"({USER_ID[-8:]}) {USER_TITLE}" not in latest:
    raise AssertionError(f"--id latest did not return the user session:\n{latest}")
  if GUARDIAN_TITLE in latest:
    raise AssertionError(f"--id latest returned the Guardian review:\n{latest}")

  listing = _ok(_run("--ls"), "--ls")
  for sid, title in ((USER_ID, USER_TITLE), (GUARDIAN_ID, GUARDIAN_TITLE)):
    if f"({sid[-8:]}) {title}" not in listing:
      raise AssertionError(f"--ls lacks {title!r}:\n{listing}")

  explicit = _ok(_run("--id", GUARDIAN_ID[-8:], "--ls"), "--id <guardian>")
  if f"({GUARDIAN_ID[-8:]}) {GUARDIAN_TITLE}" not in explicit:
    raise AssertionError(f"Guardian review not selectable by --id:\n{explicit}")

  print("PASS: --id latest skips Guardian reviews; they stay listed and selectable")
  return 0


if __name__ == "__main__":
  raise SystemExit(main())
