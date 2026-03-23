#!/usr/bin/bash
sed -n '/^=== 6\. FINAL/,$ p' "$1" > /tmp/final_before.md
sed -n '/^=== 6\. FINAL/,$ p' "$2" > /tmp/final_after.md
echo "before: $(wc -l < /tmp/final_before.md) lines"
echo "after:  $(wc -l < /tmp/final_after.md) lines"

git diff --word-diff --no-index /tmp/final_before.md /tmp/final_after.md 2>&1 | head -80