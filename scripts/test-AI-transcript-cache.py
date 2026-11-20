#!/usr/bin/env python3
"""Regression tests for the per-session metadata cache (#27)."""

from __future__ import annotations

import json
import os
import pathlib
import subprocess
import sys
import tempfile

try:
  from compression import zstd  # Python 3.14+
except ImportError:
  import zstandard as zstd  # Python < 3.14 (scripts/requirements-AI-transcript.txt)


ROOT = pathlib.Path(__file__).resolve().parent.parent
SCRIPT = ROOT / "scripts" / "AI-transcript.py"
CACHE_NAME = "ai-transcript.cache"

CX_ID = "01a1e600-1111-7222-8333-444455556666"
CX_ZST_ID = "01a1e601-1111-7222-8333-777788889999"
CL_ID = "0c1d2e3f-4a5b-4c6d-8e7f-a0b1c2d3e4f5"


def _cx_line(second: int, text: str = "x") -> str:
  """Return one Codex rollout line stamped 2026-11-16T16:05:<second>Z."""
  return json.dumps({
    "timestamp": f"2026-11-16T16:05:{second:02d}.000Z", "type": "event_msg",
    "payload": {"type": "user_message", "message": text},
  }) + "\n"


def _cl_title_line(title: str) -> str:
  """Return a Claude ai-title record line."""
  return json.dumps({"type": "ai-title", "aiTitle": title}) + "\n"


def _cl_user_line(second: int, text: str) -> str:
  """Return a Claude user record line."""
  return json.dumps({
    "type": "user", "isSidechain": False,
    "timestamp": f"2026-01-01T00:00:{second:02d}.000Z",
    "message": {"role": "user", "content": [{"type": "text", "text": text}]},
  }) + "\n"


class Env:
  """Isolated Claude and Codex homes plus a runner for the production script."""

  def __init__(self, root: pathlib.Path):
    self.codex = root / "codex"
    self.claude = root / "claude"
    day = self.codex / "sessions" / "2026" / "11" / "16"
    day.mkdir(parents=True)
    self.cx = day / f"rollout-2026-11-16T11-05-00-{CX_ID}.jsonl"
    self.cx.write_text(_cx_line(0) + _cx_line(1) + _cx_line(2), encoding="utf-8")
    self.cx_zst = day / f"rollout-2026-11-16T11-06-00-{CX_ZST_ID}.jsonl.zst"
    with zstd.open(self.cx_zst, "wt", encoding="utf-8") as out:
      out.write(_cx_line(10) + _cx_line(11))
    (self.codex / "session_index.jsonl").write_text(
      json.dumps({"id": CX_ID, "thread_name": "plain", "updated_at": "2026-11-16T16:05:00.0Z"}) + "\n"
      + json.dumps({"id": CX_ZST_ID, "thread_name": "compressed", "updated_at": "2026-11-16T16:06:00.0Z"}) + "\n",
      encoding="utf-8",
    )
    project = self.claude / "projects" / "C--fixture-project"
    project.mkdir(parents=True)
    self.cl = project / f"{CL_ID}.jsonl"
    self.cl.write_text(_cl_title_line("Title AAAA") + _cl_user_line(1, "hello"), encoding="utf-8")

  def run(self, *args: str) -> str:
    """Run the script and return stdout, requiring success."""
    env = os.environ.copy()
    env["CODEX_HOME"] = str(self.codex)
    env["CLAUDE_CONFIG_DIR"] = str(self.claude)
    result = subprocess.run(
      [sys.executable, str(SCRIPT), *args], cwd=ROOT, env=env, text=True,
      encoding="utf-8", stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False,
    )
    if result.returncode != 0:
      raise AssertionError(f"{args} exited {result.returncode}:\n{result.stderr}")
    return result.stdout

  def codex_ls(self) -> str:
    """Return --codex --ls output."""
    return self.run("--codex", "--ls")

  def claude_ls(self) -> str:
    """Return --claude --all-projects --ls output."""
    return self.run("--claude", "--all-projects", "--ls")

  def entry(self, home: pathlib.Path, session: pathlib.Path) -> dict:
    """Return the cache entry for *session* from the cache file under *home*."""
    data = json.loads((home / CACHE_NAME).read_text(encoding="utf-8"))
    for path, entry in data["files"].items():
      if pathlib.Path(path).name == session.name:
        return entry
    raise AssertionError(f"no cache entry for {session.name}: {sorted(data['files'])}")


def _require(text: str, needle: str, what: str) -> None:
  """Fail unless *needle* occurs in *text*."""
  if needle not in text:
    raise AssertionError(f"{what}: missing {needle!r}:\n{text}")


def _records_row(listing: str, short_id: str) -> str:
  """Return the line-1 text of the --ls row whose line 2 shows *short_id*."""
  lines = listing.splitlines()
  for i, line in enumerate(lines):
    if f"({short_id})" in line:
      return lines[i - 1]
  raise AssertionError(f"no --ls row for {short_id}:\n{listing}")


def test_cold_cache_and_location(env: Env) -> None:
  """A first run creates both cache files with correct counts and times."""
  _require(_records_row(env.codex_ls(), CX_ID[-8:]), "records: 3", "cold Codex count")
  _require(_records_row(env.claude_ls(), CL_ID[-8:]), "records: 2", "cold Claude count")
  entry = env.entry(env.codex, env.cx)
  if (entry["records"], entry["first_ts"], entry["last_ts"]) != (
      3, "2026-11-16T16:05:00.000Z", "2026-11-16T16:05:02.000Z"):
    raise AssertionError(f"wrong Codex cache entry: {entry}")
  if entry["size"] != env.cx.stat().st_size:
    raise AssertionError(f"cached size {entry['size']} != file size")
  env.entry(env.claude, env.cl)


def test_unchanged_file_not_reread(env: Env) -> None:
  """Same-size edits are not seen, proving the file is not reopened."""
  env.cl.write_text(
    env.cl.read_text(encoding="utf-8").replace("Title AAAA", "Title BBBB"), encoding="utf-8"
  )
  _require(env.claude_ls(), f"({CL_ID[-8:]}) Title AAAA", "unchanged-size Claude title")


def test_appended_file_read_incrementally(env: Env) -> None:
  """Growth is read from the cached size only, adding to the count and end time."""
  # Turn a space in the already-counted first line into a newline (same size).
  # A full rescan would now see one extra line; an incremental read will not.
  data = env.cx.read_bytes()
  space = data.index(b" ")
  env.cx.write_bytes(data[:space] + b"\n" + data[space + 1:])
  with env.cx.open("a", encoding="utf-8") as out:
    out.write(_cx_line(3))
  _require(_records_row(env.codex_ls(), CX_ID[-8:]), "records: 4", "incremental count")
  if env.entry(env.codex, env.cx)["last_ts"] != "2026-11-16T16:05:03.000Z":
    raise AssertionError("end time not updated from the appended record")


def test_partial_trailing_line(env: Env) -> None:
  """A record still being written is not counted until its newline arrives."""
  line = _cx_line(4)
  with env.cx.open("a", encoding="utf-8") as out:
    out.write(line[:20])
  _require(_records_row(env.codex_ls(), CX_ID[-8:]), "records: 4", "partial line not counted")
  if env.entry(env.codex, env.cx)["size"] == env.cx.stat().st_size:
    raise AssertionError("cached size includes the partial line")
  with env.cx.open("a", encoding="utf-8") as out:
    out.write(line[20:])
  _require(_records_row(env.codex_ls(), CX_ID[-8:]), "records: 5", "completed line counted")


def test_shrunk_file_rebuilt(env: Env) -> None:
  """A file that got smaller is rescanned from the start."""
  env.cx.write_text(_cx_line(0) + _cx_line(1), encoding="utf-8")
  _require(_records_row(env.codex_ls(), CX_ID[-8:]), "records: 2", "shrunk file rebuilt")


def test_compressed_file(env: Env) -> None:
  """Compressed files are cached, and rebuilt when their size changes."""
  _require(_records_row(env.codex_ls(), CX_ZST_ID[-8:]), "records: 2", "compressed count")
  with zstd.open(env.cx_zst, "wt", encoding="utf-8") as out:
    out.write(_cx_line(10) + _cx_line(11) + _cx_line(12) + _cx_line(13))
  _require(_records_row(env.codex_ls(), CX_ZST_ID[-8:]), "records: 4", "compressed rebuilt")
  if env.entry(env.codex, env.cx_zst)["last_ts"] != "2026-11-16T16:05:13.000Z":
    raise AssertionError("compressed end time not rebuilt")


def test_corrupt_cache_rebuilt(env: Env) -> None:
  """An unreadable cache file is silently replaced."""
  (env.codex / CACHE_NAME).write_text("not json {", encoding="utf-8")
  result = subprocess.run(
    [sys.executable, str(SCRIPT), "--codex", "--ls"], cwd=ROOT, text=True,
    encoding="utf-8", capture_output=True, check=False,
    env={**os.environ, "CODEX_HOME": str(env.codex), "CLAUDE_CONFIG_DIR": str(env.claude)},
  )
  if result.returncode != 0 or result.stderr.strip():
    raise AssertionError(f"corrupt cache was not silent:\n{result.stderr}")
  env.entry(env.codex, env.cx)


def test_deleted_file_dropped(env: Env) -> None:
  """Entries for files that no longer exist are removed."""
  env.cx_zst.unlink()
  env.codex_ls()
  data = json.loads((env.codex / CACHE_NAME).read_text(encoding="utf-8"))
  if any(pathlib.Path(p).name == env.cx_zst.name for p in data["files"]):
    raise AssertionError("deleted session still cached")


def main() -> int:
  """Run the cache scenarios in order on one isolated environment."""
  with tempfile.TemporaryDirectory() as temp_dir:
    env = Env(pathlib.Path(temp_dir))
    for test in (
      test_cold_cache_and_location,
      test_unchanged_file_not_reread,
      test_appended_file_read_incrementally,
      test_partial_trailing_line,
      test_shrunk_file_rebuilt,
      test_compressed_file,
      test_corrupt_cache_rebuilt,
      test_deleted_file_dropped,
    ):
      test(env)
  print("PASS: session metadata cache is reused, updated incrementally, and rebuilt when needed")
  return 0


if __name__ == "__main__":
  raise SystemExit(main())
