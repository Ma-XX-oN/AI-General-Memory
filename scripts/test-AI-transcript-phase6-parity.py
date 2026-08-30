#!/usr/bin/env python3

import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CURRENT = ROOT / 'scripts' / 'AI-transcript.py'
LEGACY = Path(os.environ['LEGACY_AI_TRANSCRIPT']).resolve()
CORE = Path(os.environ['AI_CONVERSATION_CORE']).resolve()

CASES = (
  ('chatgpt', CORE / 'tests/fixtures/chatgpt/chatgpt-direct.jsonl'),
  ('claude', CORE / 'tests/fixtures/claude/claude-rich-subagent.jsonl'),
  ('codex', CORE / 'tests/fixtures/codex/codex-rich.jsonl'),
)
COMMON_VARIANTS = (
  ('default', ['--color', 'never']),
  ('date', ['--color', 'never', '-d']),
  ('record-number', ['--color', 'never', '-n']),
  ('record-comment', ['--color', 'never', '-N']),
  ('metadata-combined', ['--color', 'never', '-d', '-n', '-N']),
  ('ansi', ['--color', 'always']),
)
CLAUDE_VARIANTS = (
  ('separate-thoughts', ['--color', 'never', '-T']),
  ('separate-thoughts-metadata-ansi', ['--color', 'always', '-T', '-d', '-n', '-N']),
)


def run(script, fixture, args, env):
  result = subprocess.run(
    [sys.executable, str(script), '--file', str(fixture), *args],
    cwd=ROOT,
    env=env,
    text=True,
    encoding='utf-8',
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    check=False,
  )
  return result.returncode, result.stdout, result.stderr


def first_difference(actual, expected):
  common = min(len(actual), len(expected))
  offset = next((i for i in range(common) if actual[i] != expected[i]), common)
  lo = max(0, offset - 80)
  hi = offset + 160
  return (
    f'offset={offset}, current_len={len(actual)}, legacy_len={len(expected)}, '
    f'current={actual[lo:hi]!r}, legacy={expected[lo:hi]!r}'
  )


def main():
  env = os.environ.copy()
  env['AI_CONVERSATION_CORE'] = str(CORE)
  failures = []
  for provider, fixture in CASES:
    variants = list(COMMON_VARIANTS)
    if provider == 'claude':
      variants.extend(CLAUDE_VARIANTS)
    for name, args in variants:
      legacy_rc, legacy_out, legacy_err = run(LEGACY, fixture, args, env)
      current_rc, current_out, current_err = run(CURRENT, fixture, args, env)
      if legacy_rc != current_rc:
        failures.append(
          f'{provider}/{name}: return code differs: current={current_rc}, legacy={legacy_rc}; '
          f'current stderr={current_err!r}; legacy stderr={legacy_err!r}'
        )
        continue
      if current_out != legacy_out:
        failures.append(
          f'{provider}/{name}: stdout differs: {first_difference(current_out, legacy_out)}'
        )
      if current_err != legacy_err:
        failures.append(
          f'{provider}/{name}: stderr differs: current={current_err!r}, legacy={legacy_err!r}'
        )
  if failures:
    raise SystemExit('\n'.join(failures))
  print('PASS: Phase 6 production parity with pre-migration AI-transcript.py')


if __name__ == '__main__':
  main()
