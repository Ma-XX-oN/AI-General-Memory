#!/usr/bin/env python3
import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CORE = Path(os.environ["AI_CONVERSATION_CORE"]).resolve()
SCRIPT = ROOT / "scripts" / "AI-transcript.py"


def run_path(path, *args):
  env = os.environ.copy()
  env["AI_CONVERSATION_CORE"] = str(CORE)
  result = subprocess.run(
    [sys.executable, str(SCRIPT), "--file", str(path),
     "--color", "never", *args],
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
      f"{path.name} exited {result.returncode}: {result.stderr.strip()}"
    )
  return result


def fixture(provider, name):
  return CORE / "tests" / "fixtures" / provider / name


def records(path):
  with path.open(encoding="utf-8") as source:
    return [json.loads(line) for line in source if line.strip()]


def main():
  chatgpt_path = fixture("chatgpt", "chatgpt-direct.jsonl")
  chatgpt = run_path(chatgpt_path, "--turn-id")
  chatgpt_ids = [
    rec.get("id") for rec in records(chatgpt_path)
    if isinstance(rec.get("id"), str) and rec.get("id")
  ]
  assert any(
    f"turn_id={record_id}" in chatgpt.stdout
    for record_id in chatgpt_ids
  ), "ChatGPT --turn-id emitted no native source message id"
  assert "<!-- turn_id=" not in chatgpt.stdout, (
    "ChatGPT --turn-id used an ordinary HTML provenance comment"
  )

  with tempfile.TemporaryDirectory() as tmp:
    claude_path = Path(tmp) / "claude-turn-id.jsonl"
    claude_path.write_text(
      '{"type":"user","uuid":"claude-user-uuid","timestamp":"2026-01-02T12:00:01.000Z","message":{"role":"user","content":[{"type":"text","text":"Hello"}]}}\n'
      '{"type":"assistant","uuid":"claude-assistant-uuid","timestamp":"2026-01-02T12:00:02.000Z","message":{"role":"assistant","content":[{"type":"text","text":"Hi"}]}}\n',
      encoding="utf-8",
    )
    claude = run_path(claude_path, "--turn-id")
    claude_debug = run_path(claude_path, "-N")
  assert "turn_id=claude-user-uuid" in claude.stdout, (
    "Claude User --turn-id did not use the native source record uuid"
  )
  assert "turn_id=claude-assistant-uuid" in claude.stdout, (
    "Claude Assistant --turn-id did not use the native source record uuid"
  )
  assert "<!-- turn_id=" not in claude.stdout, (
    "Claude --turn-id used an ordinary HTML provenance comment"
  )
  assert "record_id=claude-user-uuid record_index=0" in claude_debug.stdout, (
    "Claude -N did not preserve the native source record uuid as record_id"
  )
  assert "turn_id=" not in claude_debug.stdout, (
    "Claude -N reused the first-class turn_id label for debug provenance"
  )

  codex_path = fixture("codex", "codex-rich.jsonl")
  codex = run_path(codex_path, "--turn-id")
  assert "turn_id=" not in codex.stdout, (
    "Codex --turn-id unexpectedly emitted a turn id"
  )
  assert (
    "Codex records do not expose a suitable unique UUID for turn_id; "
    "no turn IDs will be emitted."
  ) in codex.stderr, "Codex --turn-id warning was not emitted"
  codex_debug = run_path(codex_path, "-N")
  assert "record_index=" in codex_debug.stdout, (
    "Codex -N emitted no source record_index"
  )
  assert "record_id=" not in codex_debug.stdout, (
    "Codex -N invented a native source record_id"
  )
  assert "turn_id=" not in codex_debug.stdout, (
    "Codex -N reused conversational turn_id as debug provenance"
  )

  chatgpt_debug = run_path(chatgpt_path, "-N")
  assert any(
    f"record_id={record_id}" in chatgpt_debug.stdout
    for record_id in chatgpt_ids
  ), "ChatGPT -N did not preserve native source message ids as record_id"
  assert "<!-- turn_id=" not in chatgpt_debug.stdout, (
    "ChatGPT -N reused the first-class turn_id label for debug provenance"
  )

  numbered = run_path(chatgpt_path, "-n")
  first_visible = next(
    index + 1 for index, rec in enumerate(records(chatgpt_path))
    if rec.get("author", {}).get("role") in ("user", "assistant")
  )
  assert re.search(
    rf"^## User\s+{first_visible}:\s*$", numbered.stdout, re.MULTILINE
  ), "ChatGPT first visible User heading has the wrong JSONL record number"

  dated_numbered = run_path(chatgpt_path, "-d", "-n")
  assert re.search(
    rf"^## User \[[^\]]+\]:\s+{first_visible}:\s*$",
    dated_numbered.stdout,
    re.MULTILINE,
  ), "ChatGPT -d/-n shared heading projection is malformed"

  combined = run_path(chatgpt_path, "-d", "-n", "--turn-id")
  assert re.search(
    rf"^## User \[[^\]]+\]:\s+{first_visible}:\s+turn_id=[^\s]+\s*$",
    combined.stdout,
    re.MULTILINE,
  ), "ChatGPT combined heading metadata order is malformed"

  print("PASS: turn-id, debug provenance, and JSONL record-number projection")


if __name__ == "__main__":
  main()
