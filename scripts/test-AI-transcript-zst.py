#!/usr/bin/env python3
"""Regression tests for reading Zstandard-compressed session files (#28)."""

from __future__ import annotations

import json
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile

try:
  from compression import zstd  # Python 3.14+
except ImportError:
  import zstandard as zstd  # Python < 3.14 (scripts/requirements-AI-transcript.txt)


ROOT = pathlib.Path(__file__).resolve().parent.parent
SCRIPT = ROOT / "scripts" / "AI-transcript.py"
CORE = ROOT / "dependencies" / "AIConversationCore"
CX_FIXTURE = ROOT / "scripts" / "fixtures" / "codex-revision-history.jsonl"
CL_FIXTURE = ROOT / "scripts" / "fixtures" / "t-mode.jsonl"

CX_ID = "01a07826-f445-7dd2-a370-3f3c7a3754a6"
CX_TITLE = "Compressed Codex session"
CX_UNINDEXED = "01a07900-aaaa-7bbb-8ccc-0123456789ab"
CL_ID = "0c1d2e3f-4a5b-4c6d-8e7f-a0b1c2d3e4f5"


def _record_count(path: pathlib.Path) -> int:
  """Return the number of non-blank JSONL lines in *path*."""
  return sum(1 for line in path.read_text(encoding="utf-8").splitlines() if line.strip())


def _compress(source: pathlib.Path, target: pathlib.Path) -> None:
  """Write *source* to *target* as a Zstandard-compressed file."""
  target.parent.mkdir(parents=True, exist_ok=True)
  with zstd.open(target, "wt", encoding="utf-8") as out:
    out.write(source.read_text(encoding="utf-8"))


class Homes:
  """Isolated Claude and Codex homes holding compressed sessions."""

  def __init__(self, root: pathlib.Path):
    self.codex = root / "codex"
    self.claude = root / "claude"
    self.day = self.codex / "sessions" / "2026" / "09" / "06"
    self.cx_zst = self.day / f"rollout-2026-09-06T19-17-01-{CX_ID}.jsonl.zst"
    _compress(CX_FIXTURE, self.cx_zst)
    _compress(CX_FIXTURE, self.day / f"rollout-2026-09-06T19-18-01-{CX_UNINDEXED}.jsonl.zst")
    (self.codex / "session_index.jsonl").write_text(
      json.dumps({"id": CX_ID, "thread_name": CX_TITLE,
                  "updated_at": "2026-09-06T20:00:00.0000000Z"}) + "\n",
      encoding="utf-8",
    )
    self.cl_zst = self.claude / "projects" / "C--fixture-project" / f"{CL_ID}.jsonl.zst"
    _compress(CL_FIXTURE, self.cl_zst)

  def run(self, *args: str, python: str = sys.executable) -> subprocess.CompletedProcess[str]:
    """Run the production entry point against these homes."""
    env = os.environ.copy()
    env["CODEX_HOME"] = str(self.codex)
    env["CLAUDE_CONFIG_DIR"] = str(self.claude)
    env["AI_CONVERSATION_CORE"] = str(CORE)
    return subprocess.run(
      [python, str(SCRIPT), *args],
      cwd=ROOT, env=env, text=True, encoding="utf-8",
      stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False,
    )


def _ok(result: subprocess.CompletedProcess[str], what: str) -> str:
  """Return stdout after requiring a successful run."""
  if result.returncode != 0:
    raise AssertionError(f"{what} exited {result.returncode}:\n{result.stderr}")
  return result.stdout


def _require(text: str, needle: str, what: str) -> None:
  """Fail unless *needle* occurs in *text*."""
  if needle not in text:
    raise AssertionError(f"{what}: missing {needle!r}:\n{text}")


def _assert_codex(homes: Homes) -> None:
  """Require compressed Codex sessions to list, resolve, grep, and render."""
  rc = _record_count(CX_FIXTURE)
  listing = _ok(homes.run("--codex", "--ls"), "--codex --ls")
  _require(listing, f"records: {rc}", "--codex --ls record count")
  _require(listing, f"({CX_ID[-8:]}) {CX_TITLE}", "--codex --ls row")
  row = _ok(homes.run("--codex", "--id", CX_ID[-8:], "--ls"), "--id indexed .zst")
  _require(row, f"({CX_ID[-8:]}) {CX_TITLE}", "--id indexed .zst")
  row = _ok(homes.run("--codex", "--id", CX_UNINDEXED[-8:], "--ls"), "--id unindexed .zst")
  _require(row, f"({CX_UNINDEXED[-8:]})", "--id unindexed .zst")
  grep = _ok(homes.run("--codex", "--grep", "puck", "--ls"), "--codex --grep")
  _require(grep, CX_ID[-8:], "--codex --grep")
  transcript = _ok(homes.run("--codex", "--id", CX_ID), "--codex transcript")
  _require(transcript, "What is a puck?", "--codex transcript")


def _assert_claude(homes: Homes) -> None:
  """Require a compressed Claude session to list, grep, and render."""
  listing = _ok(homes.run("--claude", "--all-projects", "--ls"), "--claude --ls")
  _require(listing, f"records: {_record_count(CL_FIXTURE)}", "--claude --ls record count")
  _require(listing, f"({CL_ID[-8:]})", "--claude --ls row")
  grep = _ok(homes.run("--claude", "--all-projects", "--grep", "Second thing", "--ls"),
             "--claude --grep")
  _require(grep, CL_ID[-8:], "--claude --grep")
  transcript = _ok(homes.run("--claude", "--all-projects", "--id", CL_ID[-8:]),
                   "--claude transcript")
  _require(transcript, "Second thing done.", "--claude transcript")


def _assert_file_mode(homes: Homes) -> None:
  """Require --file to read a compressed file directly."""
  transcript = _ok(homes.run("--claude", "--file", str(homes.cl_zst)), "--file .zst")
  _require(transcript, "Second thing done.", "--file .zst")


def _assert_plain_file_wins(homes: Homes) -> None:
  """Require a plain file to be preferred over its compressed twin, with an INFO line."""
  plain = homes.cl_zst.with_suffix("")
  shutil.copyfile(CL_FIXTURE, plain)
  try:
    result = homes.run("--claude", "--all-projects", "--ls")
    listing = _ok(result, "--ls with duplicate")
    if listing.count(f"({CL_ID[-8:]})") != 1:
      raise AssertionError(f"duplicate session listed twice:\n{listing}")
    _require(result.stderr, "INFO:", "duplicate notice")
    _require(result.stderr, plain.name, "duplicate notice names the plain file")
  finally:
    plain.unlink()


def _assert_corrupt_file_is_loud(homes: Homes) -> None:
  """Require a corrupt .zst to stop with an error naming the file."""
  bad_id = "01a07a00-bbbb-7ccc-8ddd-0123456789ab"
  bad = homes.day / f"rollout-2026-09-06T19-19-01-{bad_id}.jsonl.zst"
  bad.write_bytes(b"not zstd data")
  try:
    # --ls lists only indexed sessions; --id opens the unindexed file.
    result = homes.run("--codex", "--id", bad_id[-8:])
    if result.returncode == 0:
      raise AssertionError(f"corrupt .zst did not fail:\n{result.stdout}")
    _require(result.stderr, "ERROR:", "corrupt .zst error")
    _require(result.stderr, bad.name, "corrupt .zst error names the file")
    if "Traceback" in result.stderr:
      raise AssertionError(f"corrupt .zst produced a traceback:\n{result.stderr}")
  finally:
    bad.unlink()


def _assert_missing_decompressor_is_loud(homes: Homes, temp: pathlib.Path) -> None:
  """Require a clear error when no Zstandard decompressor is installed."""
  if sys.version_info >= (3, 14):
    print("SKIP: missing-decompressor case (Python 3.14+ always has compression.zstd)")
    return
  # Earlier steps cached the session's metadata; without the cache the
  # listing has to decompress the file.
  (homes.codex / "ai-transcript.cache").unlink(missing_ok=True)
  venv = temp / "bare-venv"
  subprocess.run([sys.executable, "-m", "venv", str(venv)], check=True)
  python = venv / ("Scripts/python.exe" if os.name == "nt" else "bin/python")
  result = homes.run("--codex", "--ls", python=str(python))
  if result.returncode == 0:
    raise AssertionError(f"missing decompressor did not fail:\n{result.stdout}")
  _require(result.stderr, "ERROR:", "missing decompressor error")
  _require(result.stderr, ".jsonl.zst", "missing decompressor error names the file")
  _require(result.stderr, "zstandard", "missing decompressor error says what to install")
  if "Traceback" in result.stderr:
    raise AssertionError(f"missing decompressor produced a traceback:\n{result.stderr}")


def main() -> int:
  """Validate compressed-session discovery, reading, and loud failures."""
  with tempfile.TemporaryDirectory() as temp_dir:
    temp = pathlib.Path(temp_dir)
    homes = Homes(temp)
    _assert_codex(homes)
    _assert_claude(homes)
    _assert_file_mode(homes)
    _assert_plain_file_wins(homes)
    _assert_corrupt_file_is_loud(homes)
    _assert_missing_decompressor_is_loud(homes, temp)
  print("PASS: compressed .jsonl.zst sessions are discovered and read; failures are loud")
  return 0


if __name__ == "__main__":
  raise SystemExit(main())
