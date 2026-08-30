#!/usr/bin/env python3

import ast
from pathlib import Path

path = Path('scripts/AI-transcript.py')
text = path.read_text(encoding='utf-8')

old = '''  def render(self, provider, records, source_indexes):
    """Render canonical Markdown for one provider record sequence."""
    response = self.request({
      "operation": "render",
      "provider": provider,
      "records": records,
      "source_indexes": source_indexes,
    })
    return response["markdown"]
'''
new = '''  def render(self, provider, records, source_indexes, projections):
    """Render canonical Markdown for one provider record sequence."""
    response = self.request({
      "operation": "render",
      "provider": provider,
      "records": records,
      "source_indexes": source_indexes,
      "projections": projections,
    })
    return response["markdown"]
'''
if old not in text:
  raise SystemExit('bridge render method anchor not found')
text = text.replace(old, new, 1)

start = text.find('def _core_presentation_supported():')
end = text.find('\ndef _core_record_timestamp(', start)
if start < 0 or end < 0:
  raise SystemExit('presentation-support helper anchor not found')
text = text[:start] + text[end + 1:]

anchor = '''def _core_record_timestamp(source, record):
  """Return the source timestamp string used by the Python record filter."""
'''
helper = '''def _core_projection(rec_no, ts_str, *, rec_width):
  """Return consumer presentation metadata for one canonical source event."""
  policy = _display_policy()
  suffix = ""
  if policy.show_date or policy.record_number:
    rendered = _build_hunk_prefix(rec_no, ts_str, rec_width=rec_width).rstrip()
    if rendered:
      suffix = " " + rendered
  colors = {}
  if policy.render_color:
    colors = {
      "user": _C_ROLE_USER,
      "ai": _C_ROLE_AI,
      "thought": _C_ROLE_THOUGHT,
      "reset": _C_RESET,
    }
  return {
    "heading_suffix": suffix,
    "record_comment": _record_comment(rec_no),
    "separate_thoughts": policy.separate_thoughts,
    "colors": colors,
  }


'''
if helper not in text:
  pos = text.find(anchor)
  if pos < 0:
    raise SystemExit('record timestamp helper anchor not found')
  text = text[:pos] + helper + text[pos:]

old = '''  records = []
  source_indexes = []
  with open(session.path, encoding="utf-8") as source:
    for source_index, raw in enumerate(line for line in source if line.strip()):
      record = json.loads(raw)
      records.append(record)
      rec_no = source_index + 1
      if rec_filter and not rec_filter.is_trivial():
        if not rec_filter.allows_rec(rec_no):
          continue
        if not rec_filter.allows_ts(_core_record_timestamp(session.source, record)):
          continue
      source_indexes.append(source_index)

  body = _core_bridge().render(session.source, records, source_indexes)
'''
new = '''  records = []
  source_indexes = []
  projections = {}
  rec_width = max(1, len(str(session.rc)))
  with open(session.path, encoding="utf-8") as source:
    for source_index, raw in enumerate(line for line in source if line.strip()):
      record = json.loads(raw)
      records.append(record)
      rec_no = source_index + 1
      ts_str = _core_record_timestamp(session.source, record)
      if rec_filter and not rec_filter.is_trivial():
        if not rec_filter.allows_rec(rec_no):
          continue
        if not rec_filter.allows_ts(ts_str):
          continue
      source_indexes.append(source_index)
      projections[str(source_index)] = _core_projection(
        rec_no, ts_str, rec_width=rec_width
      )

  body = _core_bridge().render(
    session.source, records, source_indexes, projections
  )
'''
if old not in text:
  raise SystemExit('core transcript body anchor not found')
text = text.replace(old, new, 1)

# Replace each concrete provider transcript implementation with the shared bridge.
tree = ast.parse(text)
lines = text.splitlines(keepends=True)
replacements = []
for node in tree.body:
  if not isinstance(node, ast.ClassDef) or node.name == 'SessionStore':
    continue
  for child in node.body:
    if not isinstance(child, (ast.FunctionDef, ast.AsyncFunctionDef)) or child.name != 'transcript':
      continue
    if not child.body or not isinstance(child.body[0], ast.Expr):
      raise SystemExit(f'{node.name}.transcript has no leading docstring')
    doc = child.body[0]
    if not isinstance(doc.value, ast.Constant) or not isinstance(doc.value.value, str):
      raise SystemExit(f'{node.name}.transcript has no leading docstring')
    replacements.append((doc.end_lineno, child.end_lineno))

if len(replacements) != 3:
  raise SystemExit(f'expected 3 concrete transcript methods, found {len(replacements)}')

for doc_end, fn_end in sorted(replacements, reverse=True):
  lines[doc_end:fn_end] = ['    return _core_transcript(session, rec_filter)\n']

path.write_text(''.join(lines), encoding='utf-8')
