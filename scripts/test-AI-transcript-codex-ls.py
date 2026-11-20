#!/usr/bin/env python3
"""Regression tests for Codex --ls built from session files with last-record dates (#25)."""

from __future__ import annotations

import json
import os
import pathlib
import subprocess
import sys
import tempfile


ROOT = pathlib.Path(__file__).resolve().parent.parent
SCRIPT = ROOT / "scripts" / "AI-transcript.py"

# A: indexed, stale index updated_at, but most recently active.
A_ID = "01a1dcf4-3439-71f3-bbc2-5526b6def1ac"
# B: indexed with the newest updated_at, but least recently active.
B_ID = "01a1e000-0000-7000-8000-00000000000b"
# C: not in the index at all.
C_ID = "01a1e100-0000-7000-8000-00000000000c"
C_PROMPT = "unindexed prompt text"


def _write(path: pathlib.Path, sid: str, stamps: list[str], prompt: str) -> None:
  """Write a Codex rollout whose records carry *stamps* (ISO UTC)."""
  path.parent.mkdir(parents=True, exist_ok=True)
  lines = [json.dumps({"timestamp": stamps[0], "type": "session_meta",
                       "payload": {"id": sid, "thread_source": "user"}})]
  lines.append(json.dumps({"timestamp": stamps[0], "type": "event_msg",
                           "payload": {"type": "user_message", "message": prompt}}))
  lines += [json.dumps({"timestamp": ts, "type": "event_msg",
                        "payload": {"type": "token_count"}}) for ts in stamps[1:]]
  path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def _run(*args: str) -> str:
  """Run --codex with *args* against an isolated Codex home; return stdout."""
  with tempfile.TemporaryDirectory() as temp_dir:
    home = pathlib.Path(temp_dir)
    sessions = home / "sessions" / "2026" / "11"
    _write(sessions / "14" / f"rollout-2026-11-14T21-05-54-{A_ID}.jsonl", A_ID,
           ["2026-11-15T02:05:54.000Z", "2026-11-16T15:00:00.000Z"], "alpha prompt")
    _write(sessions / "15" / f"rollout-2026-11-15T10-00-00-{B_ID}.jsonl", B_ID,
           ["2026-11-15T15:00:00.000Z", "2026-11-15T15:30:00.000Z"], "beta prompt")
    _write(sessions / "16" / f"rollout-2026-11-16T05-00-00-{C_ID}.jsonl", C_ID,
           ["2026-11-16T10:00:00.000Z", "2026-11-16T12:00:00.000Z"], C_PROMPT)
    index = [
      {"id": A_ID, "thread_name": "Alpha", "updated_at": "2026-11-15T02:07:15.6152666Z"},
      {"id": B_ID, "thread_name": "Beta", "updated_at": "2026-11-16T20:00:00.0000000Z"},
    ]
    (home / "session_index.jsonl").write_text(
      "".join(json.dumps(e) + "\n" for e in index), encoding="utf-8"
    )
    env = {**os.environ, "CODEX_HOME": str(home)}
    result = subprocess.run(
      [sys.executable, str(SCRIPT), "--codex", *args], cwd=ROOT, env=env,
      text=True, encoding="utf-8", capture_output=True, check=False,
    )
    if result.returncode != 0:
      raise AssertionError(f"{args} exited {result.returncode}:\n{result.stderr}")
    return result.stdout


def _order(listing: str) -> list[str]:
  """Return the short IDs in --ls order."""
  ids = []
  for line in listing.splitlines():
    stripped = line.strip()
    if stripped.startswith("(") and ")" in stripped:
      ids.append(stripped[1:stripped.index(")")])
  return ids


def main() -> int:
  """Validate file-based listing, last-record dates, ordering, and latest."""
  listing = _run("--ls")
  expected = [A_ID[-8:], C_ID[-8:], B_ID[-8:]]
  if _order(listing) != expected:
    raise AssertionError(f"--ls order {_order(listing)} != {expected}:\n{listing}")
  if f"({C_ID[-8:]}) {C_PROMPT}" not in listing:
    raise AssertionError(f"unindexed session not listed with its fallback title:\n{listing}")
  if f"({A_ID[-8:]}) Alpha" not in listing:
    raise AssertionError(f"index title not used:\n{listing}")
  a_line = listing.splitlines()[_order(listing).index(A_ID[-8:]) * 2]
  if "-[2026-11-16 " not in a_line:
    raise AssertionError(f"end time not taken from the last record:\n{a_line}")
  latest = _run("--id", "latest", "--ls")
  if f"({A_ID[-8:]}) Alpha" not in latest:
    raise AssertionError(f"--id latest is not the most recently active session:\n{latest}")
  print("PASS: Codex --ls lists every session file, dated and ordered by last record")
  return 0


if __name__ == "__main__":
  raise SystemExit(main())
