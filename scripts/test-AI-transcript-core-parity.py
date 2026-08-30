#!/usr/bin/env python3

import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CORE = Path(os.environ["AI_CONVERSATION_CORE"]).resolve()
SCRIPT = ROOT / "scripts" / "AI-transcript.py"

CASES = (
  (
    "chatgpt",
    CORE / "tests" / "fixtures" / "chatgpt" / "chatgpt-direct.jsonl",
    CORE / "tests" / "golden" / "chatgpt" / "chatgpt-direct.canonical.md",
  ),
  (
    "claude",
    CORE / "tests" / "fixtures" / "claude" / "claude-rich-subagent.jsonl",
    CORE / "tests" / "golden" / "claude" / "claude-rich-subagent.canonical.md",
  ),
  (
    "codex",
    CORE / "tests" / "fixtures" / "codex" / "codex-rich.jsonl",
    CORE / "tests" / "golden" / "codex" / "codex-rich.canonical.md",
  ),
)


def transcript_body(text):
  """Return the transcript beginning with its first Markdown turn heading."""
  start = text.find("## ")
  if start < 0:
    raise AssertionError("AI-transcript.py output has no transcript heading")
  return text[start:]


def main():
  """Verify all three production provider entry points match canonical output."""
  env = os.environ.copy()
  env["AI_CONVERSATION_CORE"] = str(CORE)
  failures = []
  for provider, fixture, expected_path in CASES:
    result = subprocess.run(
      [sys.executable, str(SCRIPT), "--file", str(fixture), "--color", "never"],
      cwd=ROOT,
      env=env,
      text=True,
      encoding="utf-8",
      stdout=subprocess.PIPE,
      stderr=subprocess.PIPE,
      check=False,
    )
    if result.returncode != 0:
      failures.append(
        f"{provider}: AI-transcript.py exited {result.returncode}: {result.stderr.strip()}"
      )
      continue
    actual = transcript_body(result.stdout)
    expected = expected_path.read_text(encoding="utf-8")
    if actual != expected:
      failures.append(f"{provider}: production transcript differs from canonical golden")

  if failures:
    raise SystemExit("\n".join(failures))
  print("PASS: AI-transcript.py canonical parity for ChatGPT, Claude, and Codex")


if __name__ == "__main__":
  main()
