#!/usr/bin/env python3
"""Regression tests for --id UUID fragment matching and the displayed short ID (#22)."""

from __future__ import annotations

import json
import os
import pathlib
import subprocess
import sys
import tempfile


ROOT = pathlib.Path(__file__).resolve().parent.parent
SCRIPT = ROOT / "scripts" / "AI-transcript.py"

# Real UUIDv7 pair created 0.5 s apart; both share the 8-character prefix.
CX_A = "01a1e51b-7e6a-7ce0-8d85-48bac7eee942"
CX_B = "01a1e51b-8055-7ea3-b0e5-e346f57f64fc"
# Title-only target: "cafe" is hex but neither a prefix nor a suffix of any ID.
CX_C = "01a1e600-1111-7222-8333-444455556666"
CX_TITLES = {CX_A: "Create PG for RWF 51", CX_B: "Guardian review", CX_C: "cafe notes"}

# UUIDv4 Claude sessions sharing a 4-character prefix.
CL_A = "f4b19167-1a2b-4c3d-8e4f-a1b2c3d4e5f6"
CL_B = "f4b1aaaa-9b8c-4d7e-9f60-0123456789ab"
CL_TITLES = {CL_A: "Claude alpha", CL_B: "Claude beta"}


def _write_jsonl(path: pathlib.Path, records: list[dict]) -> None:
  """Write *records* to *path* as JSONL, creating parent directories."""
  path.parent.mkdir(parents=True, exist_ok=True)
  path.write_text(
    "".join(json.dumps(record) + "\n" for record in records), encoding="utf-8"
  )


def _build_codex_home(codex_home: pathlib.Path) -> None:
  """Create an isolated Codex home with indexed rollout files."""
  day_dir = codex_home / "sessions" / "2026" / "11" / "16"
  index = []
  for second, (sid, title) in enumerate(CX_TITLES.items()):
    _write_jsonl(day_dir / f"rollout-2026-11-16T11-05-{second:02d}-{sid}.jsonl", [
      {"timestamp": "2026-11-16T16:05:46.000Z", "type": "session_meta",
       "payload": {"id": sid, "timestamp": "2026-11-16T16:05:46.000Z"}},
      {"timestamp": "2026-11-16T16:05:47.000Z", "type": "event_msg",
       "payload": {"type": "user_message", "message": title}},
    ])
    index.append({"id": sid, "thread_name": title,
                  "updated_at": f"2026-11-16T16:05:{second:02d}.0000000Z"})
  _write_jsonl(codex_home / "session_index.jsonl", index)


def _build_claude_home(claude_home: pathlib.Path) -> None:
  """Create an isolated Claude config directory with one project."""
  project_dir = claude_home / "projects" / "C--fixture-project"
  for sid, title in CL_TITLES.items():
    _write_jsonl(project_dir / f"{sid}.jsonl", [
      {"type": "user", "isSidechain": False,
       "timestamp": "2026-01-01T00:00:01.000Z",
       "message": {"role": "user", "content": [{"type": "text", "text": title}]}},
    ])


def _run(*args: str) -> subprocess.CompletedProcess[str]:
  """Run the production entry point against isolated Claude and Codex homes."""
  with tempfile.TemporaryDirectory() as temp_dir:
    temp = pathlib.Path(temp_dir)
    _build_codex_home(temp / "codex")
    _build_claude_home(temp / "claude")
    env = os.environ.copy()
    env["CODEX_HOME"] = str(temp / "codex")
    env["CLAUDE_CONFIG_DIR"] = str(temp / "claude")
    return subprocess.run(
      [sys.executable, str(SCRIPT), *args],
      cwd=ROOT,
      env=env,
      text=True,
      encoding="utf-8",
      stdout=subprocess.PIPE,
      stderr=subprocess.PIPE,
      check=False,
    )


def _resolve_codex(fragment: str) -> str:
  """Return the --ls row printed for a Codex --id that must resolve uniquely."""
  result = _run("--codex", "--id", fragment, "--ls")
  if result.returncode != 0:
    raise AssertionError(
      f"--id {fragment!r} failed ({result.returncode}): {result.stderr.strip()}"
    )
  return result.stdout


def _assert_codex_resolves(fragment: str, sid: str) -> None:
  """Require *fragment* to select exactly the Codex session *sid*."""
  output = _resolve_codex(fragment)
  expected = f"({sid[-8:]}) {CX_TITLES[sid]}"
  if expected not in output:
    raise AssertionError(f"--id {fragment!r} did not select {sid}:\n{output}")


def _assert_codex_fragments() -> None:
  """Require prefix, suffix, dashed, and full UUID fragments to resolve."""
  _assert_codex_resolves("c7eee942", CX_A)
  _assert_codex_resolves("48bac7eee942", CX_A)
  _assert_codex_resolves("8d85-48bac7eee942", CX_A)
  _assert_codex_resolves("C7EEE942", CX_A)
  _assert_codex_resolves("e346f57f64fc", CX_B)
  _assert_codex_resolves("01a1e51b-80", CX_B)
  _assert_codex_resolves(CX_A, CX_A)


def _assert_codex_ambiguous_prefix() -> None:
  """Require a shared UUIDv7 prefix to be ambiguous and list unique short IDs."""
  result = _run("--codex", "--id", "01a1e51b", "--ls")
  if result.returncode == 0:
    raise AssertionError(f"shared prefix unexpectedly resolved:\n{result.stdout}")
  if "Ambiguous: 2 sessions" not in result.stderr:
    raise AssertionError(f"expected two ambiguous matches:\n{result.stderr}")
  for sid in (CX_A, CX_B):
    if sid[-8:] not in result.stderr:
      raise AssertionError(f"ambiguity list lacks short ID of {sid}:\n{result.stderr}")
  if "(01a1e51b" in result.stderr:
    raise AssertionError(f"ambiguity list still shows the timestamp prefix:\n{result.stderr}")


def _assert_title_glob_fallback() -> None:
  """Require a fragment matching no UUID to fall through to the title search."""
  _assert_codex_resolves("cafe", CX_C)


def _assert_claude_fragments() -> None:
  """Require Claude prefix/suffix matching and last-8 short IDs."""
  for fragment, sid in (("a1b2c3d4e5f6", CL_A), ("456789ab", CL_B), ("f4b1aa", CL_B)):
    result = _run("--claude", "--all-projects", "--id", fragment, "--ls")
    if result.returncode != 0:
      raise AssertionError(f"Claude --id {fragment!r} failed: {result.stderr.strip()}")
    expected = f"({sid[-8:]}) {CL_TITLES[sid]}"
    if expected not in result.stdout:
      raise AssertionError(f"Claude --id {fragment!r} did not select {sid}:\n{result.stdout}")
  result = _run("--claude", "--all-projects", "--id", "f4b1", "--ls")
  if "Ambiguous: 2 sessions" not in result.stderr:
    raise AssertionError(f"expected Claude prefix ambiguity:\n{result.stderr}")


def _assert_help_documents_fragments() -> None:
  """Require --help to describe leading/trailing UUID fragment matching."""
  result = _run("--help")
  text = " ".join(result.stdout.split())
  for required in ("leading or trailing part of the UUID", "--id c7eee942"):
    if required not in text:
      raise AssertionError(f"--help lacks {required!r}:\n{result.stdout}")


def _assert_stale_index_entry_does_not_hide_file() -> None:
  """Require a fragment to find a session file even when a stale index entry,
  whose file no longer exists, has the same ID ending."""
  stale_id = "01a1e700-0000-7000-8000-0000deadbeef"
  real_id = "01a1e701-1111-7111-8111-1111deadbeef"
  with tempfile.TemporaryDirectory() as temp_dir:
    codex_home = pathlib.Path(temp_dir)
    _write_jsonl(
      codex_home / "sessions" / "2026" / "11" / "16"
      / f"rollout-2026-11-16T12-00-00-{real_id}.jsonl",
      [{"timestamp": "2026-11-16T17:00:00.000Z", "type": "session_meta",
        "payload": {"id": real_id}},
       {"timestamp": "2026-11-16T17:00:01.000Z", "type": "event_msg",
        "payload": {"type": "user_message", "message": "unindexed real session"}}],
    )
    _write_jsonl(codex_home / "session_index.jsonl", [
      {"id": stale_id, "thread_name": "file was deleted",
       "updated_at": "2026-11-16T16:00:00.0000000Z"},
    ])
    result = subprocess.run(
      [sys.executable, str(SCRIPT), "--codex", "--id", "deadbeef", "--ls"],
      cwd=ROOT, env={**os.environ, "CODEX_HOME": str(codex_home)},
      text=True, encoding="utf-8", capture_output=True, check=False,
    )
  if result.returncode != 0 or "unindexed real session" not in result.stdout:
    raise AssertionError(
      f"stale index entry hid the real session ({result.returncode}):\n"
      f"{result.stdout}{result.stderr}"
    )


def main() -> int:
  """Validate UUID fragment resolution, ambiguity output, and help text."""
  _assert_codex_fragments()
  _assert_codex_ambiguous_prefix()
  _assert_title_glob_fallback()
  _assert_stale_index_entry_does_not_hide_file()
  _assert_claude_fragments()
  _assert_help_documents_fragments()
  print("PASS: --id resolves leading/trailing UUID fragments and shows last-8 short IDs")
  return 0


if __name__ == "__main__":
  raise SystemExit(main())
