from pathlib import Path

path = Path('scripts/AI-transcript.py')
text = path.read_text()
assert 'import urllib.parse\n' in text
text = text.replace('import urllib.parse\n', 'import urllib.error\nimport urllib.parse\nimport urllib.request\n', 1)

old = '''def _cg_image_pointer_markdown(part):
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
new = '''def _cg_image_pointer_markdown(part):
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

  parsed = urllib.parse.urlparse(source)
  if parsed.scheme not in ("http", "https"):
    return f"[image not available]({source})"

  request = urllib.request.Request(source, method="HEAD", headers={"User-Agent": "AI-transcript.py"})
  try:
    with urllib.request.urlopen(request, timeout=3) as response:
      status = getattr(response, "status", 200)
      if 200 <= status < 400:
        return f"![image]({source})"
      if status in (404, 410):
        return "[image missing]"
      return f"[image not available]({source})"
  except urllib.error.HTTPError as error:
    if error.code in (404, 410):
      return "[image missing]"
    return f"[image not available]({source})"
  except (urllib.error.URLError, TimeoutError, OSError):
    return f"[image not available]({source})"
'''
assert old in text
text = text.replace(old, new, 1)
path.write_text(text)
