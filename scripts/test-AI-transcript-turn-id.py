#!/usr/bin/env python3
import datetime
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


def heading_has_id(output, record_id):
  return re.search(
    rf"^##(?:#)? [^\n]*{re.escape(record_id)}(?:\s+<!--|\s*$)",
    output,
    re.MULTILINE,
  ) is not None


def main():
  chatgpt_path = fixture("chatgpt", "chatgpt-direct.jsonl")
  chatgpt = run_path(chatgpt_path, "--turn-id")
  chatgpt_ids = [
    rec.get("id") for rec in records(chatgpt_path)
    if isinstance(rec.get("id"), str) and rec.get("id")
  ]
  assert any(
    heading_has_id(chatgpt.stdout, record_id)
    for record_id in chatgpt_ids
  ), "ChatGPT --turn-id emitted no native source message id"
  assert "turn_id=" not in chatgpt.stdout, (
    "ChatGPT --turn-id still rendered the obsolete visible turn_id= prefix"
  )

  default_chatgpt = run_path(chatgpt_path)
  assert not any(
    heading_has_id(default_chatgpt.stdout, record_id)
    for record_id in chatgpt_ids
  ), "ChatGPT emitted turn IDs without --turn-id"
  assert "<!-- turn_id=" not in chatgpt.stdout, (
    "ChatGPT --turn-id used obsolete HTML-comment syntax"
  )

  debug_turn_id = run_path(chatgpt_path, "--turn-id", "-N")
  assert any(
    heading_has_id(debug_turn_id.stdout, record_id)
    for record_id in chatgpt_ids
  ), "ChatGPT --turn-id disappeared when debug provenance was enabled"
  assert "turn_id=" not in debug_turn_id.stdout, (
    "ChatGPT visible Turn ID regained the obsolete turn_id= prefix"
  )
  assert re.search(
    r"<!-- record_id=[^ ]+ record_index=\d+ -->",
    debug_turn_id.stdout,
  ), "ChatGPT -N did not emit Core-owned record provenance"
  assert "<!-- turn_id=" not in debug_turn_id.stdout, (
    "Debug provenance incorrectly reused the turn_id comment label"
  )

  with tempfile.TemporaryDirectory() as tmp:
    claude_path = Path(tmp) / "claude-turn-id.jsonl"
    claude_path.write_text(
      '{"type":"user","uuid":"claude-user-uuid","timestamp":"2026-01-02T12:00:01.000Z","message":{"role":"user","content":[{"type":"text","text":"Hello"}]}}\n'
      '{"type":"assistant","uuid":"claude-assistant-uuid","timestamp":"2026-01-02T12:00:02.000Z","message":{"role":"assistant","content":[{"type":"text","text":"Hi"}]}}\n',
      encoding="utf-8",
    )
    claude = run_path(claude_path, "--turn-id")
  assert heading_has_id(claude.stdout, "claude-user-uuid"), (
    "Claude User --turn-id did not use the native source record uuid"
  )
  assert heading_has_id(claude.stdout, "claude-assistant-uuid"), (
    "Claude Assistant --turn-id did not use the native source record uuid"
  )
  assert "turn_id=" not in claude.stdout, (
    "Claude --turn-id still rendered the obsolete visible turn_id= prefix"
  )

  codex = run_path(fixture("codex", "codex-rich.jsonl"), "--turn-id")
  assert "turn_id=" not in codex.stdout, (
    "Codex --turn-id unexpectedly emitted a turn id"
  )
  assert (
    "Codex records do not expose a suitable unique UUID for turn_id; "
    "no turn IDs will be emitted."
  ) in codex.stderr, "Codex --turn-id warning was not emitted"

  first_dated = next(
    rec for rec in records(chatgpt_path)
    if rec.get("author", {}).get("role") in ("user", "assistant")
    and rec.get("create_time") is not None
  )
  expected_fixed = datetime.datetime.fromtimestamp(
    float(first_dated["create_time"]), datetime.timezone.utc
  ) - datetime.timedelta(hours=4)
  fixed = run_path(chatgpt_path, "-d", "--tz=-04:00")
  assert expected_fixed.strftime("[%Y-%m-%d %H:%M:%S]:") in fixed.stdout, (
    "Core-owned fixed-offset timestamp projection did not preserve --tz=-04:00"
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

  print("PASS: turn-id and JSONL record-number transcript projection")


if __name__ == "__main__":
  main()
