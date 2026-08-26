from pathlib import Path

script = Path('scripts/AI-transcript.py')
text = script.read_text()

helper_marker = '\ndef _cg_content_text_parts(rec, *, file_ref_index=None):\n'
assert helper_marker in text
helper = r'''
def _cg_image_pointer_markdown(part):
  """Render one ChatGPT ``image_asset_pointer`` without changing part order."""
  if not isinstance(part, dict):
    return "[image missing]"
  metadata = part.get("metadata") if isinstance(part.get("metadata"), dict) else {}
  source = metadata.get("asset_pointer_link") or part.get("asset_pointer_link") or part.get("asset_pointer")
  if not isinstance(source, str) or not source.strip():
    return "[image missing]"
  source = source.strip()
  if source.startswith("data:image/"):
    return f"![image]({source})"
  return f"[image not available]({source})"

'''
text = text.replace(helper_marker, '\n' + helper + helper_marker.lstrip('\n'), 1)

old = '''  cleaned = []
  image_placeholders = []
  if not isinstance(parts, list):
    return cleaned
  for part in parts:
    texts = []
    if isinstance(part, str):
      if part.strip():
        texts.append(part)
    elif isinstance(part, dict):
      if part.get("content_type") == "image_asset_pointer":
        image_placeholders.append("[image missing]")
        continue
'''
new = '''  cleaned = []
  if not isinstance(parts, list):
    return cleaned
  for part in parts:
    texts = []
    if isinstance(part, str):
      if part.strip():
        texts.append(part)
    elif isinstance(part, dict):
      if part.get("content_type") == "image_asset_pointer":
        cleaned.append(_cg_image_pointer_markdown(part))
        continue
'''
assert old in text
text = text.replace(old, new, 1)
assert '  cleaned.extend(image_placeholders)\n  return cleaned\n' in text
text = text.replace('  cleaned.extend(image_placeholders)\n  return cleaned\n', '  return cleaned\n', 1)
script.write_text(text)

fixture = Path('scripts/fixtures/chatgpt-direct.jsonl')
lines = fixture.read_text().splitlines()
import json
rec = json.loads(lines[1])
parts = rec['content']['parts']
assert parts[0].get('content_type') == 'image_asset_pointer'
parts.insert(1, {'content_type': 'image_asset_pointer'})
lines[1] = json.dumps(rec, separators=(',', ':'))
fixture.write_text('\n'.join(lines) + '\n')
