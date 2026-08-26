from pathlib import Path
import json
import subprocess

p = Path('scripts/AI-transcript.py')
s = p.read_text()

anchor = '''def _cg_record_ts(rec):
  """Return the best available timestamp string for a ChatGPT record."""
  ts_str = _cg_float_ts_to_iso(rec.get("create_time"))
  if ts_str:
    return ts_str
  return _cg_float_ts_to_iso(rec.get("update_time"))


'''
insert = '''def _cg_record_ts(rec):
  """Return the best available timestamp string for a ChatGPT record."""
  ts_str = _cg_float_ts_to_iso(rec.get("create_time"))
  if ts_str:
    return ts_str
  return _cg_float_ts_to_iso(rec.get("update_time"))


def _cg_conversation_metadata(rec):
  """Return the conversation ID from one synthetic ChatGPT metadata record."""
  if not isinstance(rec, dict):
    return ""
  if rec.get("record_type") != "chatgpt_conversation_metadata":
    return ""
  if rec.get("schema_version") != 1:
    return ""
  conversation_id = rec.get("conversation_id")
  if not isinstance(conversation_id, str):
    return ""
  return conversation_id.strip()


def _cg_conversation_id_from_path(path):
  """Return the exported ChatGPT conversation ID, or ``""`` when absent."""
  try:
    with open(path, encoding="utf-8") as f:
      for raw in f:
        raw = raw.strip()
        if not raw:
          continue
        return _cg_conversation_metadata(json.loads(raw))
  except Exception:
    return ""
  return ""


def _cg_message_records(path):
  """Return ChatGPT message records, excluding the synthetic metadata record."""
  records = []
  with open(path, encoding="utf-8") as f:
    for raw in f:
      raw = raw.strip()
      if not raw:
        continue
      rec = json.loads(raw)
      if _cg_conversation_metadata(rec):
        continue
      records.append(rec)
  return records


'''
assert anchor in s
s = s.replace(anchor, insert, 1)

old_meta = '''        rc += 1
        rec = json.loads(raw)

        create_dt = _cg_float_ts_to_local(rec.get("create_time"))
'''
new_meta = '''        rec = json.loads(raw)
        if _cg_conversation_metadata(rec):
          continue
        rc += 1

        create_dt = _cg_float_ts_to_local(rec.get("create_time"))
'''
assert old_meta in s
s = s.replace(old_meta, new_meta, 1)

old_grep = '''        rec_no += 1
        if rec_filter and not rec_filter.is_trivial():
          if rec_filter.past_hi(rec_no):
            break
          if not rec_filter.allows_rec(rec_no):
            continue
        rec = json.loads(raw)
        _cg_register_file_reference(file_ref_index, rec)
'''
new_grep = '''        rec = json.loads(raw)
        if _cg_conversation_metadata(rec):
          continue
        rec_no += 1
        if rec_filter and not rec_filter.is_trivial():
          if rec_filter.past_hi(rec_no):
            break
          if not rec_filter.allows_rec(rec_no):
            continue
        _cg_register_file_reference(file_ref_index, rec)
'''
assert old_grep in s
s = s.replace(old_grep, new_grep, 1)

old_make = '''  def _make_session_from_path(self, path):
    """Build a Session from a ChatGPT JSONL file path."""
    path = str(path)
    stem = os.path.splitext(os.path.basename(path))[0]
    title, ctime, mtime, rc = _cg_session_meta(path)
'''
new_make = '''  def _make_session_from_path(self, path):
    """Build a Session from a ChatGPT JSONL file path."""
    global CHATGPT_CONVERSATION_ID
    path = str(path)
    if not CHATGPT_CONVERSATION_ID:
      CHATGPT_CONVERSATION_ID = _cg_conversation_id_from_path(path) or None
    stem = os.path.splitext(os.path.basename(path))[0]
    title, ctime, mtime, rc = _cg_session_meta(path)
'''
assert old_make in s
s = s.replace(old_make, new_make, 1)

start = s.index('  def transcript(self, session, rec_filter=None):\n', s.index('class ChatGPTSessionStore'))
body_start = s.index('    path = str(session.path)\n', start)
headings_at = s.index('    headings = _headings()\n', body_start)
replacement = '''    path = str(session.path)
    records = _cg_message_records(path)
    lines = []
    for rec_no, rec in enumerate(records, start=1):
      if rec_filter and not rec_filter.is_trivial():
        if rec_filter.past_hi(rec_no):
          break
        if not rec_filter.allows_rec(rec_no):
          continue
        ts_str = _cg_record_ts(rec)
        if not rec_filter.allows_ts(ts_str):
          continue
      rec = dict(rec)
      rec["_rec_no"] = rec_no
      lines.append(rec)

'''
s = s[:body_start] + replacement + s[headings_at:]

old_detect = '''        if not isinstance(rec, dict):
          return None
        if "author" in rec and "content" in rec:
          return "chatgpt"
'''
new_detect = '''        if not isinstance(rec, dict):
          return None
        if _cg_conversation_metadata(rec):
          return "chatgpt"
        if "author" in rec and "content" in rec:
          return "chatgpt"
'''
assert old_detect in s
s = s.replace(old_detect, new_detect, 1)

p.write_text(s)
subprocess.run(['python', '-m', 'py_compile', str(p)], check=True)

fixture = Path('scripts/fixtures/chatgpt-metadata-sandbox.jsonl')
metadata = {
  'record_type': 'chatgpt_conversation_metadata',
  'schema_version': 1,
  'conversation_id': 'fixture-conversation-123',
}
user = {
  'id': 'fixture-user-1',
  'author': {'role': 'user', 'name': None, 'metadata': {}},
  'create_time': 1783450000.0,
  'update_time': None,
  'content': {'content_type': 'text', 'parts': ['Please provide the generated file.']},
  'status': 'finished_successfully',
  'end_turn': None,
  'weight': 1,
  'metadata': {'is_visually_hidden_from_conversation': False},
  'recipient': 'all',
  'channel': None,
}
assistant = {
  'id': 'fixture-assistant-1',
  'author': {'role': 'assistant', 'name': None, 'metadata': {}},
  'create_time': 1783450001.0,
  'update_time': None,
  'content': {'content_type': 'text', 'parts': ['[Download fixture](sandbox:/mnt/data/work/fixture.txt)']},
  'status': 'finished_successfully',
  'end_turn': True,
  'weight': 1,
  'metadata': {'is_visually_hidden_from_conversation': False},
  'recipient': 'all',
  'channel': 'final',
}
fixture.write_text('\n'.join(json.dumps(record, separators=(',', ':')) for record in (metadata, user, assistant)) + '\n')

output = subprocess.run(
  ['python', str(p), '--file', str(fixture), '--color=never'],
  check=True, capture_output=True, text=True,
).stdout
assert '[chatgpt]' in output
assert 'records: 2' in output
assert 'chatgpt_conversation_metadata' not in output
expected = ('https://chatgpt.com/backend-api/conversation/fixture-conversation-123/'
            'interpreter/download?message_id=fixture-assistant-1&'
            'sandbox_path=%2Fmnt%2Fdata%2Fwork%2Ffixture.txt&download_intent=true')
assert expected in output
assert 'sandbox:/mnt/data/work/fixture.txt' not in output

# Explicit override remains authoritative.
override = subprocess.run(
  ['python', str(p), '--file', str(fixture), '--conversation-id', 'override-conversation', '--color=never'],
  check=True, capture_output=True, text=True,
).stdout
assert '/conversation/override-conversation/interpreter/download?' in override
assert '/conversation/fixture-conversation-123/interpreter/download?' not in override
