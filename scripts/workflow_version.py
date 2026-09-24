#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
import re
import sys


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "scripts" / "AI_transcript_version.py"
VERSION_LINE = re.compile(r'^VERSION\s*=\s*"([^"]+)"\s*$')
DEVELOPMENT_VERSION = re.compile(r"^\d+\.\d+\.\d+-issue\.\d+\.\d+$")


def main() -> int:
  matches = []
  for line in SOURCE.read_text(encoding="utf-8").splitlines():
    match = VERSION_LINE.fullmatch(line)
    if match is not None:
      matches.append(match.group(1))
  if len(matches) != 1:
    print("version source must contain exactly one VERSION assignment", file=sys.stderr)
    return 1
  version = matches[0]
  if DEVELOPMENT_VERSION.fullmatch(version) is None:
    print(f"invalid development version: {version}", file=sys.stderr)
    return 1
  print(version)
  return 0


if __name__ == "__main__":
  raise SystemExit(main())
