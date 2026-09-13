from pathlib import Path

CORE_SHA = 'b7961cb8dab11611a5af8f4304ae783295998cf2'


def replace_once(path, old, new, label):
  file_path = Path(path)
  text = file_path.read_text(encoding='utf-8')
  count = text.count(old)
  if count != 1:
    raise SystemExit(f'{label}: expected one match in {path}, found {count}')
  file_path.write_text(text.replace(old, new, 1), encoding='utf-8')


replace_once(
  'scripts/AI-transcript-core-worker.mjs',
  "const CORE_COMMIT = '3233cba838bbf2d2cea5a2a6f1900ed6014dcfb0';",
  f"const CORE_COMMIT = '{CORE_SHA}';",
  'worker Core pin',
)
replace_once(
  'scripts/AI-transcript-core-worker.mjs',
  '    markdown: core.renderCanonicalMarkdown(events)\n',
  '    markdown: core.renderCanonicalMarkdown(events, request.options ?? {})\n',
  'worker render options',
)

replace_once(
  'scripts/AI-transcript.py',
  '''  def render(self, provider, records, source_indexes, projections):
    """Render canonical Markdown for one provider record sequence."""
    response = self.request({
      "operation": "render",
      "provider": provider,
      "records": records,
      "source_indexes": source_indexes,
      "projections": projections,
    })
    return response["markdown"]
''',
  '''  def render(self, provider, records, source_indexes, projections, options):
    """Render canonical Markdown using caller presentation policy only."""
    response = self.request({
      "operation": "render",
      "provider": provider,
      "records": records,
      "source_indexes": source_indexes,
      "projections": projections,
      "options": options,
    })
    return response["markdown"]
''',
  'Python bridge render signature',
)

replace_once(
  'scripts/AI-transcript.py',
  '''def _core_projection(rec_no, ts_str, *, rec_width):
  """Return consumer presentation metadata for one canonical source event."""
  policy = _display_policy()
  heading_metadata = {}
  if policy.show_date:
    heading_metadata["timestamp"] = _parse_ts(ts_str, policy.display_tz)
  if policy.record_number:
    heading_metadata["record_number"] = f"{rec_no:{rec_width}}"
  if policy.show_turn_id and not policy.debug_record_comment:
    heading_metadata["show_turn_id"] = True
  colors = {}
  if policy.render_color:
    colors = {
      "user": _C_ROLE_USER,
      "ai": _C_ROLE_AI,
      "thought": _C_ROLE_THOUGHT,
      "timestamp": _C_RECDATE,
      "record_number": _C_RECNO,
      "reset": _C_RESET,
    }
  projection = {
    "debug_provenance": policy.debug_record_comment,
    "separate_thoughts": policy.separate_thoughts,
    "colors": colors,
  }
  if heading_metadata:
    projection["heading_metadata"] = heading_metadata
  return projection
''',
  '''def _core_projection():
  """Return non-semantic per-event presentation settings for Core."""
  policy = _display_policy()
  colors = {}
  if policy.render_color:
    colors = {
      "user": _C_ROLE_USER,
      "ai": _C_ROLE_AI,
      "thought": _C_ROLE_THOUGHT,
      "timestamp": _C_RECDATE,
      "record_number": _C_RECNO,
      "reset": _C_RESET,
    }
  return {
    "separate_thoughts": policy.separate_thoughts,
    "colors": colors,
  }


def _core_heading_options():
  """Return Core heading visibility and timezone presentation policy."""
  policy = _display_policy()
  heading = {
    "timestamp": policy.show_date,
    "recordNumber": policy.record_number,
    "turnId": policy.show_turn_id,
    "debugProvenance": policy.debug_record_comment,
  }
  tz = policy.display_tz
  if tz is not None:
    zone_key = getattr(tz, "key", None)
    if isinstance(zone_key, str) and zone_key:
      heading["timeZone"] = zone_key
    else:
      offset = tz.utcoffset(None)
      if offset is None:
        raise RuntimeError("Core heading timezone has no fixed offset")
      total_seconds = int(offset.total_seconds())
      if total_seconds % 60:
        raise RuntimeError("Core heading timezone offset must use whole minutes")
      total_minutes = total_seconds // 60
      sign = "+" if total_minutes >= 0 else "-"
      total_minutes = abs(total_minutes)
      heading["timeZone"] = (
        f"{sign}{total_minutes // 60:02d}:{total_minutes % 60:02d}"
      )
  return {"heading": heading}
''',
  'Core projection policy',
)

replace_once(
  'scripts/AI-transcript.py',
  '''  projections = {}
  rec_width = max(1, len(str(session.rc)))
  with open(session.path, encoding="utf-8") as source:
''',
  '''  projections = {}
  with open(session.path, encoding="utf-8") as source:
''',
  'record width removal',
)
replace_once(
  'scripts/AI-transcript.py',
  '''      projections[str(source_index)] = _core_projection(
        rec_no, ts_str, rec_width=rec_width
      )

  body = _core_bridge().render(
    session.source, records, source_indexes, projections
  )
''',
  '''      projections[str(source_index)] = _core_projection()

  body = _core_bridge().render(
    session.source,
    records,
    source_indexes,
    projections,
    _core_heading_options(),
  )
''',
  'Core transcript render options',
)

phase6 = Path('scripts/test-AI-transcript-phase6-parity.py')
text = phase6.read_text(encoding='utf-8')
text = text.replace(
  "_DEBUG_BODY = r'<!-- (?:turn_id=[^ ]+ )?record_index=\\d+ -->'",
  "_DEBUG_BODY = r'<!-- (?:record_id=[^ ]+ )?record_index=\\d+ -->'",
)
text = text.replace(
  "  if provider == 'chatgpt' and 'turn_id=' not in ''.join(comments):\n    failures.append(f'{provider}/{name}: ChatGPT debug provenance lost source turn_id')",
  "  if provider == 'chatgpt' and 'record_id=' not in ''.join(comments):\n    failures.append(f'{provider}/{name}: ChatGPT debug provenance lost source record_id')",
)
if "record_id=' not in ''.join(comments)" not in text:
  raise SystemExit('Phase 6 debug provenance migration did not apply')
phase6.write_text(text, encoding='utf-8')

turn_id_test = Path('scripts/test-AI-transcript-turn-id.py')
text = turn_id_test.read_text(encoding='utf-8')
text = text.replace('import json\n', 'import datetime\nimport json\n', 1)
insert = '''  default_chatgpt = run_path(chatgpt_path)
  assert "turn_id=" not in default_chatgpt.stdout, (
    "ChatGPT emitted turn IDs without --turn-id"
  )
  assert "<!-- turn_id=" not in chatgpt.stdout, (
    "ChatGPT --turn-id used obsolete HTML-comment syntax"
  )

  debug_turn_id = run_path(chatgpt_path, "--turn-id", "-N")
  assert "turn_id=" in debug_turn_id.stdout, (
    "ChatGPT --turn-id disappeared when debug provenance was enabled"
  )
  assert re.search(
    r"<!-- record_id=[^ ]+ record_index=\\d+ -->",
    debug_turn_id.stdout,
  ), "ChatGPT -N did not emit Core-owned record provenance"
  assert "<!-- turn_id=" not in debug_turn_id.stdout, (
    "Debug provenance incorrectly reused the turn_id comment label"
  )

'''
marker = '  with tempfile.TemporaryDirectory() as tmp:\n'
if text.count(marker) != 1:
  raise SystemExit('turn-id test insertion marker not found')
text = text.replace(marker, insert + marker, 1)
fixed_offset = '''  first_dated = next(
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

'''
marker = '  numbered = run_path(chatgpt_path, "-n")\n'
if text.count(marker) != 1:
  raise SystemExit('fixed-offset test insertion marker not found')
text = text.replace(marker, fixed_offset + marker, 1)
turn_id_test.write_text(text, encoding='utf-8')

replace_once(
  'scripts/AI-transcript-core.md',
  '`3233cba838bbf2d2cea5a2a6f1900ed6014dcfb0`.  The worker verifies the checkout',
  f'`{CORE_SHA}`.  The worker verifies the checkout',
  'Core integration doc pin',
)
replace_once(
  'scripts/AI-transcript-core.md',
  '''Python reads/filter-selects the source JSONL records and supplies consumer-specific
projection metadata such as date, record number, optional source turn ID,
ANSI presentation, separate-thought mode, and debug provenance enablement.  Provider interpretation,
canonical structures, and Markdown rendering remain in `AIConversationCore`.
''',
  '''Python reads/filter-selects the source JSONL records and supplies only presentation
policy: heading visibility, timezone choice, ANSI styling, and separate-thought mode.
Timestamp, record number, source turn ID, and debug provenance values are derived and
serialized by `AIConversationCore` from canonical source provenance.  Provider
interpretation, canonical structures, and Markdown rendering remain in Core.
''',
  'Core integration doc bridge contract',
)
replace_once(
  'scripts/AI-transcript-core.md',
  '''```markdown
## ChatGPT <!-- turn_id=<source_record_id> record_index=<zero-based-index> -->
```

The same rule applies to User/provider/sub-agent/question/plan/thought/tool and
other renderer-generated structural headings/groupings.  When one rendered group
represents multiple source records, the first source is attached to the opening
line and later source records are emitted on immediately following HTML-comment
lines.
''',
  '''```markdown
## ChatGPT <!-- record_id=<native-source-record-id> record_index=<zero-based-index> -->
```

When `--turn-id` and `-N` are both requested, visible `turn_id=...` heading metadata
and the debug provenance comment are emitted independently.  The same provenance
rule applies to User/provider/sub-agent/question/plan/thought/tool and other
renderer-generated structural headings/groupings.  Related-source structures use
their own Core-derived source metadata.
''',
  'Core integration doc debug contract',
)

workflow = Path('.github/workflows/ai-transcript-core-parity.yml')
text = workflow.read_text(encoding='utf-8')
text = text.replace(
  '          ref: 29a9fea4903f0214d450e1399a7af8e20823fcd1\n',
  f'          ref: {CORE_SHA}\n',
  1,
)
text = text.replace(
  '      - scripts/test-AI-transcript-core-parity.py\n',
  '      - scripts/test-AI-transcript-core-parity.py\n      - scripts/test-AI-transcript-turn-id.py\n',
  2,
)
text = text.replace(
  'run: python -m py_compile scripts/AI-transcript.py scripts/test-AI-transcript-phase6-parity.py scripts/test-AI-transcript-core-parity.py',
  'run: python -m py_compile scripts/AI-transcript.py scripts/test-AI-transcript-phase6-parity.py scripts/test-AI-transcript-core-parity.py scripts/test-AI-transcript-turn-id.py',
  1,
)
needle = '''      - name: Canonical production parity
        env:
          AI_CONVERSATION_CORE: ${{ github.workspace }}/.phase6-core
        run: python scripts/test-AI-transcript-core-parity.py
'''
addition = needle + '''      - name: Turn ID and Core-owned heading metadata
        env:
          AI_CONVERSATION_CORE: ${{ github.workspace }}/.phase6-core
        run: python scripts/test-AI-transcript-turn-id.py
'''
if text.count(needle) != 1:
  raise SystemExit('parity workflow insertion point not found')
text = text.replace(needle, addition, 1)
workflow.write_text(text, encoding='utf-8')
