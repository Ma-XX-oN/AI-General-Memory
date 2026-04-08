#!/usr/bin/python
import argparse
import json
import sys
from typing import TextIO


def prettify_jsonl_line(line: str) -> str:
  """
  Parse and format a single JSONL line.

  Parameters
  ----------
  line : str
    A single line containing one JSON value.

  Returns
  -------
  str
    The formatted representation of the parsed JSON value.

  Raises
  ------
  json.JSONDecodeError
    If `line` is not valid JSON.
  """
  obj = json.loads(line)
  return format_value(obj, 0)


def format_value(value, indent: int) -> str:
  """
  Format a JSON value at the given indentation level.

  Parameters
  ----------
  value : object
    The JSON-compatible value to format.
  indent : int
    The number of leading spaces for this value.

  Returns
  -------
  str
    The formatted text for `value`.
  """
  if isinstance(value, dict):
    return format_object(value, indent)
  if isinstance(value, list):
    return format_list(value, indent)
  return " " * indent + json.dumps(value, ensure_ascii=False)


def format_object(obj: dict, indent: int) -> str:
  """
  Format a JSON object with keys on their own lines.

  Parameters
  ----------
  obj : dict
    The object to format.
  indent : int
    The number of leading spaces for the opening and closing braces.

  Returns
  -------
  str
    The formatted text for `obj`.
  """
  if not obj:
    return " " * indent + "{}"

  lines = [" " * indent + "{"]
  items = list(obj.items())

  for i, (key, value) in enumerate(items):
    key_indent = " " * (indent + 2)
    lines.append(f'{key_indent}{json.dumps(key, ensure_ascii=False)}:')

    value_text = format_value(value, indent + 4)
    value_lines = value_text.splitlines()

    if i != len(items) - 1:
      value_lines[-1] += ","

    lines.extend(value_lines)

  lines.append(" " * indent + "}")
  return "\n".join(lines)


def format_list(values: list, indent: int) -> str:
  """
  Format a JSON array.

  Parameters
  ----------
  values : list
    The array to format.
  indent : int
    The number of leading spaces for the opening and closing brackets.

  Returns
  -------
  str
    The formatted text for `values`.
  """
  if not values:
    return " " * indent + "[]"

  lines = [" " * indent + "["]

  for i, value in enumerate(values):
    value_text = format_value(value, indent + 2)
    value_lines = value_text.splitlines()

    if i != len(values) - 1:
      value_lines[-1] += ","

    lines.extend(value_lines)

  lines.append(" " * indent + "]")
  return "\n".join(lines)


def build_parser() -> argparse.ArgumentParser:
  """
  Build the command-line argument parser.

  Returns
  -------
  argparse.ArgumentParser
    The configured parser for this program.
  """
  parser = argparse.ArgumentParser(
    description=(
      "Read JSONL records from a file or stdin and prettify each selected "
      "line independently."
    )
  )
  parser.add_argument(
    "-s",
    "--start",
    type=int,
    default=1,
    help="First 1-based line number to process.  Default: 1.",
  )
  parser.add_argument(
    "-e",
    "--end",
    type=int,
    default=None,
    help="Last 1-based line number to process.  Default: end of input.",
  )
  parser.add_argument(
    "filename",
    nargs="?",
    default=None,
    help="Input filename.  Default: stdin.",
  )
  return parser


def validate_args(start: int, end: int | None) -> None:
  """
  Validate parsed command-line arguments.

  Parameters
  ----------
  start : int
    First 1-based line number to process.
  end : int or None
    Last 1-based line number to process, or None for no upper bound.

  Raises
  ------
  ValueError
    If the requested line range is invalid.
  """
  if start < 1:
    raise ValueError("--start must be at least 1")
  if end is not None and end < 1:
    raise ValueError("--end must be at least 1")
  if end is not None and end < start:
    raise ValueError("--end must be greater than or equal to --start")


def iter_selected_lines(
  stream: TextIO,
  start: int,
  end: int | None,
):
  """
  Yield selected non-blank input lines from a text stream.

  Parameters
  ----------
  stream : TextIO
    The input stream to read.
  start : int
    First 1-based physical line number to process.
  end : int or None
    Last 1-based physical line number to process, or None for no upper bound.

  Yields
  ------
  str
    Each selected non-blank line, stripped of surrounding whitespace.
  """
  for line_number, raw_line in enumerate(stream, start=1):
    if line_number < start:
      continue
    if end is not None and line_number > end:
      break

    line = raw_line.strip()
    if not line:
      continue

    yield line


def process_stream(
  stream: TextIO,
  start: int,
  end: int | None,
) -> int:
  """
  Format selected JSONL lines from a stream and write them to stdout.

  Parameters
  ----------
  stream : TextIO
    The input stream to read.
  start : int
    First 1-based physical line number to process.
  end : int or None
    Last 1-based physical line number to process, or None for no upper bound.

  Returns
  -------
  int
    Process exit status.  Zero indicates success.
  """
  first = True

  for line in iter_selected_lines(stream, start, end):
    if not first:
      sys.stdout.write("\n")
    first = False

    sys.stdout.write(prettify_jsonl_line(line))
    sys.stdout.write("\n")

  return 0


def main() -> int:
  """
  Parse command-line arguments and process the requested input.

  Returns
  -------
  int
    Process exit status.  Zero indicates success.
  """
  parser = build_parser()
  args = parser.parse_args()

  try:
    validate_args(args.start, args.end)
  except ValueError as exc:
    print(f"error: {exc}", file=sys.stderr)
    return 2

  if args.filename is None:
    return process_stream(sys.stdin, args.start, args.end)

  with open(args.filename, "r", encoding="utf-8") as stream:
    return process_stream(stream, args.start, args.end)


if __name__ == "__main__":
  raise SystemExit(main())
