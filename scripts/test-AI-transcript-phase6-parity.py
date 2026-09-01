#!/usr/bin/env python3

import os
import re
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

_DEBUG_BODY = r'<!-- (?:record_id=[^ ]+ )?record_index=\d+ -->'
_DEBUG_COMMENT_RE = re.compile(r' ?' + _DEBUG_BODY)
_DEBUG_STANDALONE_RE = re.compile(r'^(?:> )?' + _DEBUG_BODY + r'$')


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


def _blank_markdown_line(line):
  raw = line[:-1] if line.endswith('\n') else line
  return raw in ('', '>')


def without_debug_provenance(text):
  """Remove canonical provenance while preserving the non-debug Markdown layout."""
  lines = text.splitlines(keepends=True)
  out = []
  skip_next_blank = False
  for index, line in enumerate(lines):
    if skip_next_blank and _blank_markdown_line(line):
      skip_next_blank = False
      continue
    skip_next_blank = False
    raw = line[:-1] if line.endswith('\n') else line
    if _DEBUG_STANDALONE_RE.fullmatch(raw):
      previous_blank = bool(out) and _blank_markdown_line(out[-1])
      next_blank = index + 1 < len(lines) and _blank_markdown_line(lines[index + 1])
      if previous_blank and next_blank:
        skip_next_blank = True
      continue
    out.append(_DEBUG_COMMENT_RE.sub('', line))
  return ''.join(out)


def first_difference(actual, expected):
  common = min(len(actual), len(expected))
  offset = next((i for i in range(common) if actual[i] != expected[i]), common)
  lo = max(0, offset - 80)
  hi = offset + 160
  return (
    f'offset={offset}, current_len={len(actual)}, expected_len={len(expected)}, '
    f'current={actual[lo:hi]!r}, expected={expected[lo:hi]!r}'
  )


def args_without_debug(args):
  return [arg for arg in args if arg != '-N']


def require_debug_shape(provider, name, output, failures):
  comments = _DEBUG_COMMENT_RE.findall(output)
  if not comments:
    failures.append(f'{provider}/{name}: debug mode emitted no canonical provenance comments')
    return
  joined = ''.join(comments)
  if provider in ('chatgpt', 'claude') and 'record_id=' not in joined:
    failures.append(f'{provider}/{name}: debug provenance lost source record_id')
  if provider == 'codex' and 'record_id=' in joined:
    failures.append(f'{provider}/{name}: Codex debug provenance invented a source record_id')
  if 'record_index=' not in joined:
    failures.append(f'{provider}/{name}: debug provenance lost record_index')
  if 'turn_id=' in joined:
    failures.append(f'{provider}/{name}: debug provenance reused the first-class turn_id label')
  if '<!-- record:' in output:
    failures.append(f'{provider}/{name}: legacy record comment syntax leaked into canonical debug output')


def require_chatgpt_contract(name, output, failures):
  plain = re.sub(r'\x1b\[[0-9;]*m', '', output)
  if plain.count('\n## ChatGPT') != 1:
    failures.append(f'chatgpt/{name}: expected exactly one ChatGPT response heading')
  if '\n### ChatGPT Commentary' not in plain:
    failures.append(f'chatgpt/{name}: missing ChatGPT Commentary heading')
  if 'Having a thought' not in plain:
    failures.append(f'chatgpt/{name}: missing singular thought group')
  if '<summary>Thoughts</summary>' in plain:
    failures.append(f'chatgpt/{name}: obsolete Thoughts summary survived canonical grammar')


def main():
  env = os.environ.copy()
  env['AI_CONVERSATION_CORE'] = str(CORE)
  failures = []

  for provider, fixture in CASES:
    variants = list(COMMON_VARIANTS)
    if provider == 'claude':
      variants.extend(CLAUDE_VARIANTS)

    current_cache = {}
    for name, args in variants:
      legacy_rc, legacy_out, legacy_err = run(LEGACY, fixture, args, env)
      current_rc, current_out, current_err = run(CURRENT, fixture, args, env)
      current_cache[tuple(args)] = (current_rc, current_out, current_err)

      if legacy_rc != current_rc:
        failures.append(
          f'{provider}/{name}: return code differs: current={current_rc}, legacy={legacy_rc}; '
          f'current stderr={current_err!r}; legacy stderr={legacy_err!r}'
        )
        continue
      if current_err != legacy_err:
        failures.append(
          f'{provider}/{name}: stderr differs: current={current_err!r}, legacy={legacy_err!r}'
        )

      has_debug = '-N' in args
      if has_debug:
        require_debug_shape(provider, name, current_out, failures)
        base_args = args_without_debug(args)
        if tuple(base_args) not in current_cache:
          base_rc, base_out, base_err = run(CURRENT, fixture, base_args, env)
          current_cache[tuple(base_args)] = (base_rc, base_out, base_err)
        else:
          base_rc, base_out, base_err = current_cache[tuple(base_args)]
        stripped = without_debug_provenance(current_out)
        if stripped != base_out:
          failures.append(
            f'{provider}/{name}: debug provenance changed non-debug rendering: '
            f'{first_difference(stripped, base_out)}'
          )

      if provider == 'chatgpt':
        require_chatgpt_contract(name, current_out, failures)
        continue

      if has_debug:
        continue

      if current_out != legacy_out:
        failures.append(
          f'{provider}/{name}: stdout differs outside approved Phase 6 changes: '
          f'{first_difference(current_out, legacy_out)}'
        )

  if failures:
    raise SystemExit('\n'.join(failures))
  print('PASS: Phase 6 historical parity, with only D015/D016 approved differences')


if __name__ == '__main__':
  main()
