#!/usr/bin/env python3

from pathlib import Path

path = Path('scripts/AI-transcript-tests.sh')
text = path.read_text(encoding='utf-8')
old = r'''check "chatgpt-direct: google favicon service used"     0 'google\.com/s2/favicons\?domain=https://docs\.python\.org&sz=32' "" $SCRIPT --chatgpt --file scripts/fixtures/chatgpt-direct.jsonl'''
new = r'''check "chatgpt-direct: google favicon service used"     0 'google\.com/s2/favicons\?domain=https://docs\.python\.org&amp;sz=32' "" $SCRIPT --chatgpt --file scripts/fixtures/chatgpt-direct.jsonl'''
if old not in text:
  if new in text:
    raise SystemExit(0)
  raise SystemExit('favicon assertion anchor not found')
path.write_text(text.replace(old, new, 1), encoding='utf-8')
