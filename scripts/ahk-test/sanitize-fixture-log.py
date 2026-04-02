#!/usr/bin/env python3
import argparse
import random
import regex
import sys
import time
import unicodedata
from pathlib import Path


ASCII_UPPER = list("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
ASCII_LOWER = list("abcdefghijklmnopqrstuvwxyz")
ASCII_DIGITS = list("0123456789")

POOLS = {
  "upper": {
    1: ASCII_UPPER,
    2: list("ĀĂĄĆĈĊČĎĐĒĔĖĘĚĜĞ"),
    3: list("ḀḂḄḆḈḊḌḎḐḒḔḖḘḚḜḞ"),
    4: [
      "\U00010400", "\U00010401", "\U00010402", "\U00010403",
      "\U00010404", "\U00010405", "\U00010406", "\U00010407",
      "\U00010408", "\U00010409", "\U0001040A", "\U0001040B",
      "\U0001040C", "\U0001040D", "\U0001040E", "\U0001040F",
    ],
  },
  "lower": {
    1: ASCII_LOWER,
    2: list("āăąćĉċčďđēĕėęěĝğ"),
    3: list("ḁḃḅḇḉḋḍḏḑḓḕḗḙḛḝḟ"),
    4: [
      "\U00010428", "\U00010429", "\U0001042A", "\U0001042B",
      "\U0001042C", "\U0001042D", "\U0001042E", "\U0001042F",
      "\U00010430", "\U00010431", "\U00010432", "\U00010433",
      "\U00010434", "\U00010435", "\U00010436", "\U00010437",
    ],
  },
  "letter": {
    1: ASCII_LOWER,
    2: list("āăąćĉċčďđēĕėęěĝğ"),
    3: list("あいうえおかきくけこさしすせそた"),
    4: [
      "\U00010428", "\U00010429", "\U0001042A", "\U0001042B",
      "\U0001042C", "\U0001042D", "\U0001042E", "\U0001042F",
      "\U00010430", "\U00010431", "\U00010432", "\U00010433",
      "\U00010434", "\U00010435", "\U00010436", "\U00010437",
    ],
  },
  "number": {
    1: ASCII_DIGITS,
    2: list("٠١٢٣٤٥٦٧٨٩"),
    3: list("０１２３４５６７８９"),
    4: [
      "\U000104A0", "\U000104A1", "\U000104A2", "\U000104A3",
      "\U000104A4", "\U000104A5", "\U000104A6", "\U000104A7",
      "\U000104A8", "\U000104A9",
    ],
  },
  "other": {
    1: ASCII_LOWER,
    2: list("øþßæçñðłħŋŧžœıſƒ"),
    3: list("あいうえおかきくけこさしすせそた"),
    4: [
      "\U00010428", "\U00010429", "\U0001042A", "\U0001042B",
      "\U0001042C", "\U0001042D", "\U0001042E", "\U0001042F",
      "\U00010430", "\U00010431", "\U00010432", "\U00010433",
      "\U00010434", "\U00010435", "\U00010436", "\U00010437",
    ],
  },
}

SECTION_HEADER_RE = regex.compile(r"(?m)^=== (?P<label>.+?) \(len=(?P<len>\d+)\) ===\r?\n")
TOKEN_RE = regex.compile(
  r"""(?isx)
  (?(DEFINE)
    (?P<dq>"[^"]*")
    (?P<sq>'[^']*')
  )
  <(?:[^>'"]++|(?&dq)|(?&sq))++>
  |
  &(?:[A-Za-z][A-Za-z\d]++|\#\d++|\#x[\da-fA-F]++);
  """
)
CFHTML_SECTION_RE = regex.compile(
  r"""(?isx)\A
  (?P<prefix>
    (?:[A-Za-z][A-Za-z0-9-]*:[^\r\n]*\r?\n)+
  )
  (?P<html><(?:html|body)\b.*)\Z
  """
)

# SourceURL query-parameter keys (lowercase) that DetectSource needs to
# identify the clipboard source.  These are preserved verbatim; everything
# else in the SourceURL is scrambled.
_PRESERVE_URL_PARAM_KEYS = frozenset({"extensionid"})


def utf8_len(ch: str) -> int:
  return len(ch.encode("utf-8"))


def utf16_units(text: str) -> int:
  return len(text.encode("utf-16-le")) // 2


def advance_utf16_units(text: str, start_index: int, unit_count: int) -> int:
  index = start_index
  remaining = unit_count
  while remaining > 0 and index < len(text):
    remaining -= 2 if ord(text[index]) > 0xFFFF else 1
    index += 1
  if remaining != 0:
    raise ValueError("UTF-16 section length overruns the file.")
  return index


def get_kind(ch: str) -> str | None:
  cat = unicodedata.category(ch)
  if cat == "Lu":
    return "upper"
  if cat == "Ll":
    return "lower"
  if cat in {"Lt", "Lm", "Lo"}:
    return "letter"
  if cat == "Nd":
    return "number"
  if cat.startswith("P") or cat.startswith("Z") or cat == "Sm":
    return None
  if cat in {"Cc", "Cf", "Cs", "Co", "Cn"}:
    return None
  return "other"


def replacement_for(ch: str, rnd: random.Random) -> str:
  kind = get_kind(ch)
  if kind is None:
    return ch
  byte_len = utf8_len(ch)
  pool = POOLS.get(kind, {}).get(byte_len)
  if not pool:
    raise ValueError(f"no pool for kind={kind!r} utf8={byte_len}")
  return rnd.choice(pool)


def sanitize_text(text: str, rnd: random.Random) -> str:
  return "".join(replacement_for(ch, rnd) for ch in text)


def sanitize_html_visible_text(html: str, rnd: random.Random) -> str:
  out: list[str] = []
  cursor = 0
  for match in TOKEN_RE.finditer(html):
    if match.start() > cursor:
      out.append(sanitize_text(html[cursor:match.start()], rnd))
    out.append(match.group(0))
    cursor = match.end()
  if cursor < len(html):
    out.append(sanitize_text(html[cursor:], rnd))
  return "".join(out)


def sanitize_source_url(url: str, rnd: random.Random) -> str:
  """Scramble a SourceURL while preserving query params DetectSource needs."""
  q_pos = url.find("?")
  if q_pos == -1:
    return sanitize_text(url, rnd)
  base = sanitize_text(url[:q_pos + 1], rnd)
  parts = []
  for param in url[q_pos + 1:].split("&"):
    sep = param.find("=")
    if sep != -1 and param[:sep].lower() in _PRESERVE_URL_PARAM_KEYS:
      parts.append(param)
    else:
      parts.append(sanitize_text(param, rnd))
  return base + "&".join(parts)


def sanitize_cfhtml_prefix(prefix: str, rnd: random.Random) -> str:
  out: list[str] = []
  cursor = 0
  for match in regex.finditer(r"(?mi)^(SourceURL:)([^\r\n]*)", prefix):
    out.append(prefix[cursor:match.start(2)])
    out.append(sanitize_source_url(match.group(2), rnd))
    cursor = match.end(2)
  out.append(prefix[cursor:])
  return "".join(out)


def sanitize_cfhtml(section: str, rnd: random.Random) -> str:
  match = CFHTML_SECTION_RE.match(section)
  if match is not None:
    prefix = match.group("prefix")
    html = match.group("html")
    return sanitize_cfhtml_prefix(prefix, rnd) + sanitize_html_visible_text(html, rnd)

  if "\r\n\r\n" in section:
    sep = "\r\n\r\n"
  elif "\n\n" in section:
    sep = "\n\n"
  else:
    raise ValueError("CF_HTML section does not contain a recognizable header/body boundary.")
  split_at = section.find(sep)
  prefix = section[: split_at + len(sep)]
  html = section[split_at + len(sep) :]
  return sanitize_cfhtml_prefix(prefix, rnd) + sanitize_html_visible_text(html, rnd)


def sanitize_fixture(text: str, rnd: random.Random) -> str:
  matches = list(SECTION_HEADER_RE.finditer(text))
  if not matches:
    raise ValueError("No debug sections found.")

  out: list[str] = []
  cursor = 0
  for match in matches:
    label = match.group("label")
    section_len = int(match.group("len"))
    content_start = match.end()
    content_end = advance_utf16_units(text, content_start, section_len)
    out.append(text[cursor:content_start])
    section = text[content_start:content_end]
    if label.startswith("1. plain "):
      sanitized = sanitize_text(section, rnd)
    elif label.startswith("2. cfHtml "):
      sanitized = sanitize_cfhtml(section, rnd)
    else:
      sanitized = section
    if utf16_units(sanitized) != utf16_units(section):
      raise ValueError(f"Sanitized section {label!r} changed UTF-16 length.")
    if len(sanitized.encode("utf-8")) != len(section.encode("utf-8")):
      raise ValueError(f"Sanitized section {label!r} changed UTF-8 byte length.")
    out.append(sanitized)
    cursor = content_end
    if label.startswith("2. cfHtml "):
      # Sections 3+ (2b, htmlPrep, mdRaw, etc.) are not used by the fixture
      # harness and may contain unsanitised text derived from the original
      # clipboard HTML.  Strip them, keeping only the trailing separator so
      # the canonical CRLF framing ends cleanly.
      sep = "\r\n\r\n"
      if text[cursor:cursor + 4] == sep:
        out.append(sep)
      return "".join(out)
  out.append(text[cursor:])
  return "".join(out)


def get_text_info(path: Path) -> tuple[str, bool]:
  raw = path.read_bytes()
  has_bom = raw.startswith(b"\xef\xbb\xbf")
  text = raw[3:].decode("utf-8") if has_bom else raw.decode("utf-8")
  return text, has_bom


def default_output_path(input_path: Path) -> Path:
  if input_path.suffix.lower() == ".log":
    return input_path.with_suffix(".sanitized.log")
  return Path(str(input_path) + ".sanitized")


def main() -> int:
  parser = argparse.ArgumentParser()
  parser.add_argument("--input", dest="input_path", required=True)
  parser.add_argument("--output", dest="output_path", default="")
  parser.add_argument("--seed", type=int, default=12345)
  args = parser.parse_args()

  input_path = Path(args.input_path).resolve()
  output_path = Path(args.output_path).resolve() if args.output_path else default_output_path(input_path)

  start = time.perf_counter()
  text, has_bom = get_text_info(input_path)
  rnd = random.Random(args.seed)
  sanitized = sanitize_fixture(text, rnd)
  data = sanitized.encode("utf-8")
  if has_bom:
    data = b"\xef\xbb\xbf" + data
  output_path.write_bytes(data)
  elapsed = time.perf_counter() - start

  print(f"Input : {input_path}")
  print(f"Output: {output_path}")
  print(f"Seed  : {args.seed}")
  print(f"Time  : {elapsed:.3f}s")
  return 0


if __name__ == "__main__":
  sys.exit(main())
