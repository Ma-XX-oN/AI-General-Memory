from pathlib import Path

path = Path('scripts/test-AI-transcript-phase6-parity.py')
text = path.read_text(encoding='utf-8')

marker = """_DEBUG_STANDALONE_RE = re.compile(r'^(?:> )?' + _DEBUG_BODY + r'$')
"""
addition = marker + """_HEADING_RECORD_PADDING_RE = re.compile(
  r'^(#{2,3} [^\\n]*?)[ \\t]+(\\d+):(?=(?:[ \\t]+<!--|[ \\t]*$))',
  re.MULTILINE,
)


def without_heading_record_padding(text):
  \"\"\"Normalize only legacy heading-number width padding superseded by D026.\"\"\"
  return _HEADING_RECORD_PADDING_RE.sub(
    lambda match: f'{match.group(1)} {match.group(2)}:',
    text,
  )
"""
if text.count(marker) != 1:
  raise SystemExit('debug regex marker not found')
text = text.replace(marker, addition, 1)

old = """      if current_out != legacy_out:
        failures.append(
          f'{provider}/{name}: stdout differs outside approved Phase 6 changes: '
          f'{first_difference(current_out, legacy_out)}'
        )
"""
new = """      comparison_current = current_out
      comparison_legacy = legacy_out
      if '-n' in args:
        comparison_current = without_heading_record_padding(comparison_current)
        comparison_legacy = without_heading_record_padding(comparison_legacy)
      if comparison_current != comparison_legacy:
        failures.append(
          f'{provider}/{name}: stdout differs outside approved Phase 6 changes: '
          f'{first_difference(comparison_current, comparison_legacy)}'
        )
"""
if text.count(old) != 1:
  raise SystemExit('legacy stdout comparison block not found')
text = text.replace(old, new, 1)
text = text.replace(
  "print('PASS: Phase 6 historical parity, with only D015/D016 approved differences')",
  "print('PASS: Phase 6 historical parity, with only D015/D016/D026 approved differences')",
  1,
)
path.write_text(text, encoding='utf-8')
