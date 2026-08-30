#!/usr/bin/env python3

import ast
from pathlib import Path

PATH = Path('scripts/AI-transcript.py')
text = PATH.read_text(encoding='utf-8')

if 'import atexit\n' not in text:
  text = text.replace('import argparse\n', 'import argparse\nimport atexit\n', 1)
if 'import subprocess\n' not in text:
  text = text.replace('import sys\n', 'import sys\nimport subprocess\n', 1)

marker = '# ── Diagnostic helpers ────────────────────────────────────────────────────────\n'
bridge = r'''# ── AIConversationCore bridge ─────────────────────────────────────────────────

_CORE_BRIDGE = None


class _AIConversationCoreBridge:
  """Persistent line-delimited JSON bridge to AIConversationCore."""

  def __init__(self):
    worker = Path(__file__).with_name("AI-transcript-core-worker.mjs")
    node = os.environ.get("NODE", "node")
    try:
      self._process = subprocess.Popen(
        [node, str(worker)],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        encoding="utf-8",
        bufsize=1,
      )
    except OSError as exc:
      raise RuntimeError(
        "AIConversationCore requires Node.js and the AIConversationCore checkout; "
        "set AI_CONVERSATION_CORE to its repository path"
      ) from exc
    atexit.register(self.close)

  def request(self, payload):
    """Send one request to the persistent worker and return its JSON response."""
    if self._process.poll() is not None:
      stderr = self._process.stderr.read().strip() if self._process.stderr else ""
      raise RuntimeError(f"AIConversationCore worker exited early: {stderr}")
    assert self._process.stdin is not None
    assert self._process.stdout is not None
    self._process.stdin.write(json.dumps(payload, separators=(",", ":")) + "\n")
    self._process.stdin.flush()
    response_line = self._process.stdout.readline()
    if not response_line:
      stderr = self._process.stderr.read().strip() if self._process.stderr else ""
      raise RuntimeError(f"AIConversationCore worker returned no response: {stderr}")
    response = json.loads(response_line)
    if not response.get("ok"):
      raise RuntimeError(f"AIConversationCore worker error: {response.get('error', 'unknown error')}")
    return response

  def render(self, provider, records, source_indexes):
    """Render canonical Markdown for one provider record sequence."""
    response = self.request({
      "operation": "render",
      "provider": provider,
      "records": records,
      "source_indexes": source_indexes,
    })
    return response["markdown"]

  def close(self):
    """Terminate the worker process if it is still running."""
    process = getattr(self, "_process", None)
    if process is None or process.poll() is not None:
      return
    if process.stdin:
      process.stdin.close()
    try:
      process.wait(timeout=1)
    except subprocess.TimeoutExpired:
      process.terminate()
      process.wait(timeout=1)


def _core_bridge():
  """Return the process-wide persistent AIConversationCore bridge."""
  global _CORE_BRIDGE
  if _CORE_BRIDGE is None:
    _CORE_BRIDGE = _AIConversationCoreBridge()
  return _CORE_BRIDGE


def _core_presentation_supported():
  """Return whether canonical rendering can reproduce the active presentation."""
  policy = _display_policy()
  return not (
    policy.render_color
    or policy.show_date
    or policy.record_number
    or policy.debug_record_comment
    or policy.separate_thoughts
  )


def _core_record_timestamp(source, record):
  """Return the source timestamp string used by the Python record filter."""
  if source != "chatgpt":
    return record.get("timestamp")
  value = record.get("create_time")
  if value is None:
    value = record.get("update_time")
  if value is None:
    return None
  try:
    dt = datetime.datetime.fromtimestamp(float(value), datetime.timezone.utc)
  except (TypeError, ValueError, OSError, OverflowError):
    return None
  return dt.isoformat().replace("+00:00", "Z")


def _core_transcript(session, rec_filter=None):
  """Render one transcript body through the shared canonical JavaScript core."""
  records = []
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
  line1, line2 = _format_session_lines(session)
  return f"{line1}\n{line2}\n\n{body}"


'''
if '_AIConversationCoreBridge' not in text:
  if marker not in text:
    raise SystemExit('diagnostic helper marker not found')
  text = text.replace(marker, bridge + marker, 1)

# Insert the canonical fast path immediately after each concrete transcript
# method docstring.  AST locations prevent accidental edits to unrelated text.
tree = ast.parse(text)
lines = text.splitlines(keepends=True)
insertions = []
for node in tree.body:
  if not isinstance(node, ast.ClassDef) or node.name == 'SessionStore':
    continue
  for child in node.body:
    if not isinstance(child, ast.FunctionDef) or child.name != 'transcript':
      continue
    if not child.body or not isinstance(child.body[0], ast.Expr):
      raise SystemExit(f'{node.name}.transcript has no leading docstring')
    value = child.body[0].value
    if not isinstance(value, ast.Constant) or not isinstance(value.value, str):
      raise SystemExit(f'{node.name}.transcript has no leading docstring')
    insertions.append(child.body[0].end_lineno)

if len(insertions) != 3:
  raise SystemExit(f'expected 3 concrete transcript methods, found {len(insertions)}')

addition = (
  '    if _core_presentation_supported():\n'
  '      return _core_transcript(session, rec_filter)\n'
)
for line_no in sorted(insertions, reverse=True):
  # Avoid duplicate insertion when a workflow is retried.
  next_text = ''.join(lines[line_no:line_no + 2])
  if '_core_presentation_supported()' not in next_text:
    lines[line_no:line_no] = [addition]

PATH.write_text(''.join(lines), encoding='utf-8')
