from pathlib import Path

path = Path('.github/workflows/ai-transcript-core-parity.yml')
text = path.read_text(encoding='utf-8')
marker = """      - name: Install presentation dependencies
        run: python -m pip install colorama regex
"""
addition = """      - name: Install AIConversationCore dependencies
        working-directory: .phase6-core
        run: npm ci
""" + marker
count = text.count(marker)
if count != 1:
  raise SystemExit(f'expected one presentation dependency step, found {count}')
path.write_text(text.replace(marker, addition, 1), encoding='utf-8')
