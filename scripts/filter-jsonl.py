#!/usr/bin/env python3
"""
filter-jsonl.py — Extract fields from JSONL records and emit CSV.

Usage:
  cat file.jsonl | python filter-jsonl.py --show FIELD [--show FIELD ...]
                                           [--filter EXPR [--filter EXPR ...]]

Each FIELD is a dot-separated path into the JSON object, e.g.
  payload.info.total_token_usage.total_tokens

--filter accepts a boolean expression over dot-path fields:
  --filter 'payload.type = "assistant_turn"'
  --filter 'count > 10 and (status = "ok" or status = "warn")'

Supported operators: = == != < > <= >=
Conjunctives: and, or, not, parentheses
Values: quoted strings or bare numbers (int/float)

One CSV row is emitted per input line that passes all filters.  Missing or
null fields produce an empty column.  Lines that are blank or fail JSON
parsing are silently skipped.
"""

import argparse
import ast
import csv
import json
import re
import sys


# ---------------------------------------------------------------------------
# Dot-path field accessor
# ---------------------------------------------------------------------------

def get_nested(obj, path):
  """Return the value at dot-separated *path* within *obj*, or None if absent.

  Traverses dicts only; stops and returns None if any intermediate key is
  missing or the current node is not a dict.

  @param obj  - The top-level parsed JSON object (dict).
  @param path - Dot-separated key path, e.g. ``"payload.type"``.
  @returns    The value at the path, or None.
  """
  cur = obj
  for part in path.split("."):
    if not isinstance(cur, dict):
      return None
    cur = cur.get(part)
    if cur is None:
      return None
  return cur


# ---------------------------------------------------------------------------
# Filter expression tokeniser
# ---------------------------------------------------------------------------

# Token kind constants
_TK_STRING = "STRING"
_TK_NUMBER = "NUMBER"
_TK_OP     = "OP"
_TK_LPAREN = "LPAREN"
_TK_RPAREN = "RPAREN"
_TK_AND    = "AND"
_TK_OR     = "OR"
_TK_NOT    = "NOT"
_TK_EXISTS = "EXISTS"
_TK_PATH   = "PATH"

# Single combined regex; order matters — longer ops before shorter
_TOKEN_RE = re.compile(
  r"(?P<WS>\s+)"
  r"|(?P<STRING>\"(?:[^\"\\]|\\.)*\"|'(?:[^'\\]|\\.)*')"
  r"|(?P<NUMBER>-?\d+(?:\.\d+)?)"
  r"|(?P<OP><=|>=|!=|==|[=<>])"
  r"|(?P<LPAREN>\()"
  r"|(?P<RPAREN>\))"
  r"|(?P<WORD>[A-Za-z_][A-Za-z0-9_.]*)"
)

_KEYWORDS = {"and": _TK_AND, "or": _TK_OR, "not": _TK_NOT, "exists": _TK_EXISTS}


class _Token:
  """A single token from a filter expression.

  @param kind  - One of the _TK_* constants.
  @param value - Parsed Python value (str, float, or original text).
  """
  __slots__ = ("kind", "value")

  def __init__(self, kind, value):
    self.kind = kind
    self.value = value

  def __repr__(self):
    return f"_Token({self.kind}, {self.value!r})"


def _tokenize(expr):
  """Tokenise *expr* into a list of :class:`_Token` objects.

  Raises :class:`ValueError` on unrecognised input.

  @param expr - Raw filter expression string.
  @returns    List of _Token instances (whitespace excluded).
  """
  tokens = []
  pos = 0
  while pos < len(expr):
    m = _TOKEN_RE.match(expr, pos)
    if m is None:
      raise ValueError(f"Unexpected character at position {pos}: {expr[pos]!r}")
    pos = m.end()
    kind = m.lastgroup
    raw = m.group()
    if kind == "WS":
      continue
    if kind == "STRING":
      tokens.append(_Token(_TK_STRING, ast.literal_eval(raw)))
    elif kind == "NUMBER":
      tokens.append(_Token(_TK_NUMBER, float(raw)))
    elif kind == "OP":
      # normalise == → =
      tokens.append(_Token(_TK_OP, "=" if raw == "==" else raw))
    elif kind == "LPAREN":
      tokens.append(_Token(_TK_LPAREN, raw))
    elif kind == "RPAREN":
      tokens.append(_Token(_TK_RPAREN, raw))
    elif kind == "WORD":
      low = raw.lower()
      if low in _KEYWORDS:
        tokens.append(_Token(_KEYWORDS[low], low))
      else:
        tokens.append(_Token(_TK_PATH, raw))
  return tokens


# ---------------------------------------------------------------------------
# AST nodes
# ---------------------------------------------------------------------------

class _Cmp:
  """Comparison node: <path> <op> <value>.

  @param path  - Dot-separated field path string.
  @param op    - Operator string: one of = != < > <= >=
  @param value - Python str or float literal.
  """
  __slots__ = ("path", "op", "value")

  def __init__(self, path, op, value):
    self.path = path
    self.op = op
    self.value = value


class _And:
  """Logical AND of two sub-expressions.

  @param left  - Left operand AST node.
  @param right - Right operand AST node.
  """
  __slots__ = ("left", "right")

  def __init__(self, left, right):
    self.left = left
    self.right = right


class _Or:
  """Logical OR of two sub-expressions.

  @param left  - Left operand AST node.
  @param right - Right operand AST node.
  """
  __slots__ = ("left", "right")

  def __init__(self, left, right):
    self.left = left
    self.right = right


class _Not:
  """Logical NOT of a sub-expression.

  @param expr - Operand AST node.
  """
  __slots__ = ("expr",)

  def __init__(self, expr):
    self.expr = expr


class _Exists:
  """Field-existence test: True when the dot-path resolves to a non-null value.

  @param path - Dot-separated field path string.
  """
  __slots__ = ("path",)

  def __init__(self, path):
    self.path = path


# ---------------------------------------------------------------------------
# Recursive-descent parser
# ---------------------------------------------------------------------------

class _Parser:
  """Recursive-descent parser for filter expressions.

  Grammar (lowest to highest precedence):
    expr       = or_expr
    or_expr    = and_expr ( OR and_expr )*
    and_expr   = not_expr ( AND not_expr )*
    not_expr   = NOT not_expr | atom
    atom       = LPAREN expr RPAREN | comparison
    comparison = PATH OP (STRING | NUMBER) | PATH EXISTS

  @param tokens - List of _Token objects from _tokenize().
  """

  def __init__(self, tokens):
    self._tokens = tokens
    self._pos = 0

  def _peek(self):
    """Return the current token, or None if exhausted."""
    if self._pos < len(self._tokens):
      return self._tokens[self._pos]
    return None

  def _consume(self, kind=None):
    """Consume and return the current token.

    Raises ValueError if *kind* is given and doesn't match.
    """
    tok = self._peek()
    if tok is None:
      raise ValueError("Unexpected end of expression")
    if kind is not None and tok.kind != kind:
      raise ValueError(f"Expected {kind}, got {tok.kind} ({tok.value!r})")
    self._pos += 1
    return tok

  def parse(self):
    """Parse the full expression and return the root AST node.

    Raises ValueError if trailing tokens remain after parsing.
    """
    node = self._or_expr()
    if self._peek() is not None:
      raise ValueError(f"Unexpected token: {self._peek()!r}")
    return node

  def _or_expr(self):
    """Parse: and_expr ( OR and_expr )*"""
    node = self._and_expr()
    while self._peek() and self._peek().kind == _TK_OR:
      self._consume(_TK_OR)
      right = self._and_expr()
      node = _Or(node, right)
    return node

  def _and_expr(self):
    """Parse: not_expr ( AND not_expr )*"""
    node = self._not_expr()
    while self._peek() and self._peek().kind == _TK_AND:
      self._consume(_TK_AND)
      right = self._not_expr()
      node = _And(node, right)
    return node

  def _not_expr(self):
    """Parse: NOT not_expr | atom"""
    if self._peek() and self._peek().kind == _TK_NOT:
      self._consume(_TK_NOT)
      return _Not(self._not_expr())
    return self._atom()

  def _atom(self):
    """Parse: LPAREN expr RPAREN | comparison"""
    tok = self._peek()
    if tok is None:
      raise ValueError("Unexpected end of expression in atom")
    if tok.kind == _TK_LPAREN:
      self._consume(_TK_LPAREN)
      node = self._or_expr()
      self._consume(_TK_RPAREN)
      return node
    return self._comparison()

  def _comparison(self):
    """Parse: PATH OP (STRING | NUMBER) | PATH EXISTS"""
    path_tok = self._consume(_TK_PATH)
    if self._peek() and self._peek().kind == _TK_EXISTS:
      self._consume(_TK_EXISTS)
      return _Exists(path_tok.value)
    op_tok = self._consume(_TK_OP)
    val_tok = self._peek()
    if val_tok is None or val_tok.kind not in (_TK_STRING, _TK_NUMBER):
      raise ValueError(
        f"Expected string or number after operator, got {val_tok!r}"
      )
    self._consume()
    return _Cmp(path_tok.value, op_tok.value, val_tok.value)


def parse_filter(expr):
  """Parse *expr* into an AST node ready for :func:`_eval_filter`.

  Raises :class:`ValueError` with a descriptive message on syntax errors.

  @param expr - Filter expression string.
  @returns    Root AST node (_Cmp, _Exists, _And, _Or, or _Not).
  """
  tokens = _tokenize(expr)
  return _Parser(tokens).parse()


# ---------------------------------------------------------------------------
# Filter evaluator
# ---------------------------------------------------------------------------

def _eval_filter(node, obj):
  """Evaluate filter AST *node* against JSON object *obj*.

  Missing fields evaluate to False in comparisons.  Numeric comparisons
  coerce the field value to float; string comparisons coerce to str.

  @param node - Root AST node from parse_filter().
  @param obj  - Parsed JSON object (dict).
  @returns    bool — True if the record passes the filter.
  """
  if isinstance(node, _Cmp):
    raw = get_nested(obj, node.path)
    if raw is None:
      return False
    op = node.op
    lit = node.value
    try:
      if isinstance(lit, float):
        field_val = float(raw)
      else:
        field_val = str(raw)
    except (TypeError, ValueError):
      return False
    if op == "=":
      return field_val == lit
    if op == "!=":
      return field_val != lit
    if op == "<":
      return field_val < lit
    if op == ">":
      return field_val > lit
    if op == "<=":
      return field_val <= lit
    if op == ">=":
      return field_val >= lit
    return False  # unknown op
  if isinstance(node, _And):
    return _eval_filter(node.left, obj) and _eval_filter(node.right, obj)
  if isinstance(node, _Or):
    return _eval_filter(node.left, obj) or _eval_filter(node.right, obj)
  if isinstance(node, _Not):
    return not _eval_filter(node.expr, obj)
  if isinstance(node, _Exists):
    return get_nested(obj, node.path) is not None
  raise TypeError(f"Unknown AST node type: {type(node)}")


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main():
  """Parse arguments, read JSONL from a file or stdin, and write CSV to stdout."""
  sys.stdout.reconfigure(encoding="utf-8")

  ap = argparse.ArgumentParser(
    description="Extract fields from JSONL records and emit CSV.",
    formatter_class=argparse.RawDescriptionHelpFormatter,
    epilog=(
      "Example:\n"
      "  filter-jsonl.py session.jsonl \\\n"
      "    --show payload.type \\\n"
      "    --show payload.info.total_token_usage.total_tokens \\\n"
      "    --filter 'payload.type = \"assistant_turn\"' \\\n"
      "    --filter 'payload.info.total_token_usage.total_tokens > 100'\n\n"
      "  cat session.jsonl | filter-jsonl.py - --show payload.type"
    ),
  )
  ap.add_argument(
    "file",
    nargs="?",
    metavar="FILE",
    default="-",
    help="JSONL file to read (default: stdin, or pass - explicitly for stdin).",
  )
  ap.add_argument(
    "--show",
    action="append",
    metavar="FIELD",
    dest="fields",
    help="Dot-separated field path to include as a CSV column (repeatable).",
  )
  ap.add_argument(
    "-n",
    action="store_true",
    dest="number",
    help="Prepend the 1-based input record number as the first CSV column.",
  )
  ap.add_argument(
    "--filter",
    action="append",
    metavar="EXPR",
    dest="filters",
    help=(
      "Boolean filter expression; only matching records are emitted "
      "(repeatable — all filters must pass). "
      "Operators: = == != < > <= >=. "
      "Conjunctives: and, or, not, parentheses. "
      "Example: 'a.b = \"x\" and (c.d < 5 or c.d > 9)'"
    ),
  )
  args = ap.parse_args()

  if not args.fields:
    ap.error("at least one --show FIELD is required")

  # Parse all filter expressions up-front so syntax errors are reported early.
  filter_nodes = []
  if args.filters:
    for expr in args.filters:
      try:
        filter_nodes.append(parse_filter(expr))
      except ValueError as exc:
        ap.error(f"invalid --filter expression {expr!r}: {exc}")

  writer = csv.writer(sys.stdout, lineterminator="\n")

  if args.file == "-":
    infile = sys.stdin
  else:
    try:
      infile = open(args.file, encoding="utf-8")
    except OSError as exc:
      ap.error(str(exc))

  try:
    rec_no = 0
    for raw in infile:
      raw = raw.strip()
      if not raw:
        continue
      rec_no += 1
      try:
        obj = json.loads(raw)
      except json.JSONDecodeError:
        continue

      # Apply all filters (AND semantics).
      if any(not _eval_filter(fn, obj) for fn in filter_nodes):
        continue

      row = [rec_no] if args.number else []
      for field in args.fields:
        val = get_nested(obj, field)
        row.append("" if val is None else val)
      writer.writerow(row)
  except (KeyboardInterrupt, BrokenPipeError):
    pass
  finally:
    if infile is not sys.stdin:
      infile.close()


if __name__ == "__main__":
  main()
