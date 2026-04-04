#!/usr/bin/env python3
"""
AI-transcript.py — Unified transcript and session search for Claude and Codex.

Usage:
  python AI-transcript.py --ls                        list sessions (both AIs)
  python AI-transcript.py --ls --claude               Claude sessions only
  python AI-transcript.py --ls --codex                Codex sessions only
  python AI-transcript.py --ls --all-projects         all Claude projects + Codex
  python AI-transcript.py --id <glob_or_uuid>         transcript for one session
  python AI-transcript.py --id <id> [output]          write transcript to file
  python AI-transcript.py --id <id> --ls              one-row list entry
  python AI-transcript.py --grep TEXT                 search sessions
  python AI-transcript.py --grep TEXT --ls            list matching sessions
  python AI-transcript.py --grep TEXT --id <id>       grep within one session
  python AI-transcript.py --grep-re PATTERN           regex search
  python AI-transcript.py --grep TEXT --grep OTHER    AND search (both required)

Source selector (mutually exclusive): --claude | --codex | --both-AIs (default)
Session header format:
  [claude] [creation]-[modification] [project] records: N
  (uuid8) title
"""

import argparse
import datetime
import fnmatch
import glob as glob_mod
import json
import os
import re
import sys
from abc import ABC, abstractmethod
from dataclasses import dataclass
from pathlib import Path


# ── XML tags injected by Claude Code ─────────────────────────────────────────

_SYSTEM_TAG_RE = re.compile(
  r"<(?:ide_opened_file|ide_selection|system[\-_]reminder|system|env|"
  r"claude_background_info|user[\-_]prompt[\-_]submit[\-_]hook|"
  r"command[\-_]name|antml:[a-z_]+)[^>]*>.*?</[^>]+>",
  re.DOTALL | re.IGNORECASE,
)


# ── Colorama setup ────────────────────────────────────────────────────────────
# When colorama is not installed:
#   - --color=always  → warn to stderr, then disable color (empty strings)
#   - --color=auto    → silently disable color
#   - --color=never   → no color regardless
# _COLORAMA_OK tracks whether colorama imported successfully.

try:
  import colorama as _cm
  # strip=False: never discard ANSI codes (just_fix_windows_console() sets
  # strip=True when stdout is not a TTY, which breaks piped/captured output).
  _cm.init(strip=False, autoreset=False)

  # ── Diagnostic prefix colors — edit these to taste ──────────────────────
  # Fore: RED  GREEN  YELLOW  BLUE  CYAN  MAGENTA  WHITE
  # Style: BRIGHT  DIM   — combine with +, e.g. _cm.Fore.BLUE + _cm.Style.DIM
  _C_RESET    = _cm.Style.RESET_ALL
  _C_MATCH    = _cm.Style.BRIGHT + _cm.Fore.RED
  _C_DATE     = _cm.Fore.CYAN
  _C_PROJECT  = _cm.Fore.GREEN
  _C_TITLE    = _cm.Style.BRIGHT
  _C_RECDATE  = _cm.Fore.CYAN              # -d timestamp prefix
  _C_RECNO    = _cm.Style.DIM              # -n record-number prefix
  _C_RECORDS  = _cm.Style.DIM              # "records: N" in session header
  _C_INFO     = _cm.Fore.BLUE                   # INFO:    messages
  _C_WARN     = _cm.Fore.YELLOW                 # WARNING: messages
  _C_ERROR    = _cm.Fore.RED                    # ERROR:   messages
  _COLORAMA_OK = True
except ImportError:
  _C_RESET = _C_MATCH = _C_DATE = _C_PROJECT = _C_TITLE = ""
  _C_RECDATE = _C_RECNO = _C_RECORDS = ""
  _C_INFO  = _C_WARN  = _C_ERROR = ""
  _COLORAMA_OK = False

# Configure stdout for UTF-8 after colorama has had a chance to wrap it.
# If colorama wrapped sys.stdout with AnsiToWin32 (which lacks .reconfigure()),
# fall back to the underlying stream it wraps.
try:
  sys.stdout.reconfigure(encoding="utf-8")
except AttributeError:
  _underlying = getattr(sys.stdout, "wrapped", getattr(sys.stdout, "stream", None))
  if _underlying is not None and hasattr(_underlying, "reconfigure"):
    _underlying.reconfigure(encoding="utf-8")


# ── Diagnostic helpers ────────────────────────────────────────────────────────

def _diag(color, label, msg):
  """Print a prefixed diagnostic line to stderr, with colour when available."""
  use_color = _COLORAMA_OK and sys.stderr.isatty()
  if use_color:
    print(f"{color}{label}{_C_RESET} {msg}", file=sys.stderr)
  else:
    print(f"{label} {msg}", file=sys.stderr)


def _info(msg):
  """Print ``INFO: <msg>`` to stderr."""
  _diag(_C_INFO, "INFO:", msg)


def _warn(msg):
  """Print ``WARNING: <msg>`` to stderr."""
  _diag(_C_WARN, "WARNING:", msg)


def _error(msg):
  """Print ``ERROR: <msg>`` to stderr."""
  _diag(_C_ERROR, "ERROR:", msg)


# ── Shared utilities ──────────────────────────────────────────────────────────

def _count_records(path):
  """Count lines in a JSONL file (= number of JSON records)."""
  try:
    with open(path, encoding="utf-8") as f:
      return sum(1 for _ in f)
  except Exception:
    return 0


def _ansi(s, color, *, active):
  """Wrap *s* in *color* ANSI escape when *active* and color is non-empty."""
  return f"{color}{s}{_C_RESET}" if (active and color) else s


def _colorize(line, spans, *, active):
  """Highlight match *spans* within *line* using ANSI codes when *active*."""
  if not active or not spans or not _C_MATCH:
    return line
  out, prev = [], 0
  for start, end in sorted(spans):
    out.append(line[prev:start])
    out.append(_C_MATCH + line[start:end] + _C_RESET)
    prev = end
  out.append(line[prev:])
  return "".join(out)


def _plain_to_words_only_rx(plain, *, ignore_case=False):
  """
  Build a regex from a plain search string that ignores punctuation and tags.

  Splits *plain* on non-word characters, then joins the resulting words
  with ``(?:<[^>]+>|[^\\w])*`` so any punctuation, whitespace, or
  HTML/XML tags between words in the target text are accepted.

  When *ignore_case* is True the returned pattern is case-insensitive.
  """
  lower_p = plain.lower() if ignore_case else plain
  words = [re.escape(w) for w in re.split(r"[^\w]+", lower_p) if w]
  sep = r"(?:<[^>]+>)*(?:[^\w<>](?:<[^>]+>)*)+"
  flags = re.IGNORECASE if ignore_case else 0
  return re.compile(sep.join(words), flags)


def _grep_context(text, *, plain=None, rx=None, before=0, after=0, ignore_case=False):
  """
  Find all matches in *text* and return context hunks.

  Each hunk is a list of ``(is_match, line_text, spans)`` tuples where
  *spans* is a list of ``(start, end)`` character offsets of matches
  within *line_text*.

  When *ignore_case* is True, plain-text matching is case-insensitive.
  Regex patterns are expected to already carry the IGNORECASE flag when needed.
  """
  lines = text.splitlines()
  if not lines:
    return []

  match_info = {}  # line_idx -> [(start, end), ...]
  for i, line in enumerate(lines):
    if plain is not None:
      spans, pos = [], 0
      haystack = line.lower() if ignore_case else line
      needle   = plain.lower() if ignore_case else plain
      while True:
        idx = haystack.find(needle, pos)
        if idx < 0:
          break
        spans.append((idx, idx + len(needle)))
        pos = idx + 1
      if spans:
        match_info[i] = spans
    elif rx is not None:
      spans = [(m.start(), m.end()) for m in rx.finditer(line)]
      if spans:
        match_info[i] = spans

  if not match_info:
    return []

  # Build context ranges, merging adjacent/overlapping ones
  ranges = []
  for m in sorted(match_info):
    lo, hi = max(0, m - before), min(len(lines) - 1, m + after)
    if ranges and lo <= ranges[-1][1] + 1:
      ranges[-1][1] = max(ranges[-1][1], hi)
    else:
      ranges.append([lo, hi])

  return [
    [(i in match_info, lines[i], match_info.get(i, []))
     for i in range(lo, hi + 1)]
    for lo, hi in ranges
  ]


def _grep_context_tagged(tagged_lines, *, plain=None, rx=None, before=0, after=0,
                         ignore_case=False):
  """Find matches in a flat list of ``(line_text, rec_no, ts_str)`` tuples.

  Used for cross-record context (``-x`` / ``--cross-record``), where the
  caller has already flattened all searchable lines across record boundaries
  into a single sequence.

  Returns a list of hunks; each hunk is a list of
  ``(is_match, line_text, spans, rec_no, ts_str)`` tuples.
  """
  if not tagged_lines:
    return []

  match_info = {}  # idx -> [(start, end), ...]
  for i, (line, _rec_no, _ts_str) in enumerate(tagged_lines):
    if plain is not None:
      spans, pos = [], 0
      haystack = line.lower() if ignore_case else line
      needle   = plain.lower() if ignore_case else plain
      while True:
        idx = haystack.find(needle, pos)
        if idx < 0:
          break
        spans.append((idx, idx + len(needle)))
        pos = idx + 1
      if spans:
        match_info[i] = spans
    elif rx is not None:
      spans = [(m.start(), m.end()) for m in rx.finditer(line)]
      if spans:
        match_info[i] = spans

  if not match_info:
    return []

  n = len(tagged_lines)
  ranges = []
  for m in sorted(match_info):
    lo, hi = max(0, m - before), min(n - 1, m + after)
    if ranges and lo <= ranges[-1][1] + 1:
      ranges[-1][1] = max(ranges[-1][1], hi)
    else:
      ranges.append([lo, hi])

  return [
    [(i in match_info, tagged_lines[i][0], match_info.get(i, []),
      tagged_lines[i][1], tagged_lines[i][2])
     for i in range(lo, hi + 1)]
    for lo, hi in ranges
  ]


# ── Session dataclass ─────────────────────────────────────────────────────────

@dataclass
class Session:
  """A single AI session with all metadata pre-resolved by the store."""
  source:  str                # "claude" | "codex"
  id:      str                # canonical UUID (never a rollout stem)
  path:    Path               # JSONL file path (may be a rollout file for Codex)
  title:   str                # first user message or thread_name
  ctime:   datetime.datetime  # creation time — local naive datetime
  mtime:   datetime.datetime  # last-modified time — local naive datetime
  project: "str | None"       # short project label (claude) or None (codex)
  rc:      int                # number of JSON records in the .jsonl file


@dataclass
class RecordFilter:
  """Resolved record-range and timestamp-range bounds for session iteration.

  All bounds are inclusive and optional (None = no bound on that side).
  *rec_lo* and *rec_hi* are 1-based JSONL line numbers (matching rec_no).
  *ts_lo* and *ts_hi* are tz-aware UTC datetimes.
  """
  rec_lo: "int | None" = None
  rec_hi: "int | None" = None
  ts_lo:  "datetime.datetime | None" = None
  ts_hi:  "datetime.datetime | None" = None

  def is_trivial(self) -> bool:
    """True when no bounds are set (no filtering needed)."""
    return all(v is None for v in (self.rec_lo, self.rec_hi,
                                    self.ts_lo,  self.ts_hi))

  def allows_rec(self, rec_no: int) -> bool:
    """True when rec_no is within [rec_lo, rec_hi]."""
    if self.rec_lo is not None and rec_no < self.rec_lo:
      return False
    if self.rec_hi is not None and rec_no > self.rec_hi:
      return False
    return True

  def past_hi(self, rec_no: int) -> bool:
    """True when rec_no exceeds the upper bound — safe to break early."""
    return self.rec_hi is not None and rec_no > self.rec_hi

  def allows_ts(self, ts_str: "str | None") -> bool:
    """True when ts_str falls within [ts_lo, ts_hi]."""
    if self.ts_lo is None and self.ts_hi is None:
      return True
    if ts_str is None:
      return True   # no timestamp → don't filter it out
    dt = _parse_ts_to_dt(ts_str)
    if dt is None:
      return True   # unparseable → don't filter out
    if self.ts_lo is not None and dt < self.ts_lo:
      return False
    if self.ts_hi is not None and dt > self.ts_hi:
      return False
    return True


# ── SessionStore ABC ──────────────────────────────────────────────────────────

class SessionStore(ABC):
  """Abstract store; each AI backend provides a concrete subclass."""

  @abstractmethod
  def is_available(self) -> bool:
    """Return True if this AI's session storage exists on disk."""

  @abstractmethod
  def sessions(self, *, all_projects: bool = False) -> "list[Session]":
    """Return all Session objects, sorted newest-first by mtime."""

  @abstractmethod
  def find(self, id_or_glob: str, *, all_projects: bool = False) -> "tuple[Session | None, list[Session]]":
    """Resolve UUID prefix/full UUID/title glob.

    *:N suffix is NOT handled here — strip it before calling.*

    Returns ``(session, [])`` on unambiguous match.
    Returns ``(None, [candidates])`` when ambiguous.
    Raises ``FileNotFoundError`` when not found.
    """

  @abstractmethod
  def grep(self, session: "Session", *, plain: "str | None" = None,
           rx: "re.Pattern | None" = None, before: int = 0, after: int = 0,
           first_only: bool = False, ignore_case: bool = False,
           rec_filter: "RecordFilter | None" = None,
           cross_record: bool = False) -> "list[list[tuple]]":
    """Return context hunks for all matches in *session*.

    Each element of the returned list is a hunk: a list of
    ``(is_match, line_text, [(start, end), ...], rec_no, ts_str)`` tuples
    where *rec_no* is the 1-based JSONL record number and *ts_str* is the
    raw timestamp string (or ``None``).

    When *first_only* is True, return as soon as any match is found (used
    for fast AND membership checks).  *first_only* always uses per-record
    mode regardless of *cross_record*.
    If *rec_filter* is given, only records passing the filter are searched.
    When *cross_record* is True, context lines may span record boundaries.
    """

  @abstractmethod
  def transcript(self, session: "Session",
                 rec_filter: "RecordFilter | None" = None,
                 use_color: bool = False,
                 show_date: bool = False,
                 record_number: bool = False,
                 display_tz: "datetime.timezone | None" = None) -> str:
    """Return the full Markdown transcript string for *session*.

    If *rec_filter* is given, only records passing the filter are included.
    If *use_color* is True, ANSI colour codes are included in the header.
    If *show_date* is True, a formatted [timestamp] label is appended to
    each role heading.  If *record_number* is True, the JSONL record number
    is appended.  *display_tz* selects the timezone for timestamp display.
    """


# ── Claude-specific helpers ───────────────────────────────────────────────────

def _cl_dir():
  """Return the Claude config directory (respects CLAUDE_CONFIG_DIR env var)."""
  cfg = os.environ.get("CLAUDE_CONFIG_DIR")
  if cfg:
    return cfg
  return os.path.join(os.path.expanduser("~"), ".claude")


def _cl_encode_project_path(path):
  """Encode a filesystem path to the project folder key Claude Code uses."""
  path = path.replace("\\", "/")
  return re.sub(r"[^a-zA-Z0-9]", "-", path)


def _cl_project_dir(project_path=None):
  """Return the Claude project directory for *project_path* (default: CWD)."""
  if project_path is None:
    project_path = os.getcwd()
  key = _cl_encode_project_path(project_path)
  return os.path.join(_cl_dir(), "projects", key)


def _cl_all_project_dirs():
  """Return all project directory paths under ~/.claude/projects/."""
  base = os.path.join(_cl_dir(), "projects")
  if not os.path.isdir(base):
    return []
  return sorted(
    os.path.join(base, d)
    for d in os.listdir(base)
    if os.path.isdir(os.path.join(base, d))
  )


def _cl_project_label(proj_dir):
  """Extract a short human-readable label from an encoded project directory name."""
  name = os.path.basename(proj_dir)
  parts = [p for p in re.split(r"-+", name) if p]
  return parts[-1] if parts else name


def _cl_session_files(proj_dir):
  """Return [(mtime_float, path), ...] for all session JSONL files, newest first."""
  paths = glob_mod.glob(os.path.join(proj_dir, "*.jsonl"))
  result = [(os.path.getmtime(p), p) for p in paths]
  result.sort(reverse=True)
  return result


def _cl_strip_system(text):
  """Remove system-injected XML blocks from a text string."""
  return _SYSTEM_TAG_RE.sub("", text).strip()


def _cl_session_meta(path):
  """Return ``(title, ctime, rc)`` for the Claude JSONL session at *path*.

  Reads the file once, extracting all three values in a single pass:

  * *title* — first real user text (stripped of system tags), falling back
    to the first non-synthetic assistant text, then ``"(no title)"``.
  * *ctime* — ``datetime`` from the first record with a *timestamp* field,
    or ``None`` if absent.
  * *rc*    — total number of non-blank lines (= JSON record count).
  """
  title = "(no title)"
  ctime = None
  rc = 0
  asst_fallback = None
  try:
    with open(path, encoding="utf-8") as f:
      for raw in f:
        raw = raw.strip()
        if not raw:
          continue
        rc += 1
        rec = json.loads(raw)
        if rec.get("isSidechain"):
          continue
        if ctime is None:
          ts = rec.get("timestamp")
          if ts:
            try:
              ts_clean = ts.rstrip("Z").split(".")[0]
              ctime = datetime.datetime.strptime(ts_clean, "%Y-%m-%dT%H:%M:%S")
            except Exception:
              pass
        if title == "(no title)":
          rtype = rec.get("type")
          if rtype == "user":
            for block in rec.get("message", {}).get("content", []):
              if block.get("type") != "text":
                continue
              text = _cl_strip_system(block.get("text", ""))
              if text:
                title = text[:80]
                break
          elif rtype == "assistant" and asst_fallback is None:
            msg = rec.get("message", {})
            if msg.get("model") != "<synthetic>":
              for block in msg.get("content", []):
                if block.get("type") == "text":
                  text = block.get("text", "").strip()
                  if text:
                    asst_fallback = text[:80]
                    break
  except Exception:
    pass
  if title == "(no title)" and asst_fallback:
    title = asst_fallback
  return title, ctime, rc


def _cl_session_grep(path, *, plain=None, rx=None, before=0, after=0, first_only=False,
           ignore_case=False, rec_filter=None, cross_record=False):
  """Return context hunks from matching content in the Claude session at *path*.

  Each element of the returned list is a hunk: a list of
  ``(is_match, line_text, spans, rec_no, ts_str)`` tuples where *rec_no* is the
  1-based JSONL line number and *ts_str* is the raw timestamp string (or
  ``None``).

  When *first_only* is True, return as soon as any match is found (used for
  the AND membership check in :func:`_session_display_hunks`).  *first_only*
  always uses per-record mode regardless of *cross_record*.
  If *rec_filter* is given, only records passing the filter are searched.
  When *cross_record* is True, context lines may come from neighbouring records.
  """
  result = []
  rec_no = 0
  tagged = [] if (cross_record and not first_only) else None
  try:
    with open(path, encoding="utf-8") as f:
      for raw in f:
        raw = raw.strip()
        if not raw:
          continue
        rec_no += 1
        if rec_filter and not rec_filter.is_trivial():
          if rec_filter.past_hi(rec_no):
            break
          if not rec_filter.allows_rec(rec_no):
            continue
        rec = json.loads(raw)
        if rec.get("isSidechain"):
          continue
        ts_str = rec.get("timestamp")
        if rec_filter and not rec_filter.allows_ts(ts_str):
          continue
        texts = []
        rtype = rec.get("type")
        if rtype == "user":
          content = rec.get("message", {}).get("content", [])
          if not isinstance(content, list):
            continue
          for block in content:
            if block.get("type") == "text":
              texts.append(_cl_strip_system(block.get("text", "")))
        elif rtype == "assistant":
          msg = rec.get("message", {})
          if msg.get("model") == "<synthetic>":
            continue
          for block in msg.get("content", []):
            btype = block.get("type")
            if btype == "text":
              texts.append(block.get("text", ""))
            elif btype == "thinking":
              texts.append(block.get("thinking", ""))
            elif btype == "tool_use":
              name = block.get("name", "")
              inp = block.get("input", {})
              if name == "TodoWrite":
                todos = inp.get("todos", [])
                if todos:
                  lines = []
                  for j, item in enumerate(todos, 1):
                    c = item.get("content", "")
                    s = item.get("status", "pending")
                    if s == "completed":
                      lines.append(f"{j}. ~~{c}~~")
                    elif s == "in_progress":
                      lines.append(f"{j}. **{c}**")
                    else:
                      lines.append(f"{j}. {c}")
                  texts.append("\n".join(lines))
              elif name == "Edit":
                parts = []
                old_s = inp.get("old_string", "")
                new_s = inp.get("new_string", "")
                if old_s:
                  parts.extend(f"- {l}" for l in old_s.splitlines())
                if new_s:
                  parts.extend(f"+ {l}" for l in new_s.splitlines())
                if parts:
                  texts.append("\n".join(parts))
              elif name in ("Write", "NotebookEdit"):
                c = inp.get("content") or inp.get("new_source", "")
                if c:
                  texts.append(
                    "\n".join(f"+ {l}" for l in c.splitlines())
                  )
              elif name == "Bash":
                cmd = inp.get("command", "")
                if cmd:
                  texts.append(f"$ {cmd}")
        if tagged is not None:
          for text in texts:
            for line in text.splitlines():
              tagged.append((line, rec_no, ts_str))
        else:
          for text in texts:
            for hunk_lines in _grep_context(
              text, plain=plain, rx=rx, before=before, after=after,
              ignore_case=ignore_case,
            ):
              result.append([(im, l, s, rec_no, ts_str) for im, l, s in hunk_lines])
            if first_only and result:
              return result
  except Exception:
    pass
  if tagged is not None:
    return _grep_context_tagged(
      tagged, plain=plain, rx=rx, before=before, after=after, ignore_case=ignore_case,
    )
  return result


def _cl_user_text(content):
  """
  Extract clean human-written text from user message content blocks.

  Strips system-injected XML tags; embeds images as inline data URIs.
  """
  parts = []
  for block in content:
    btype = block.get("type")
    if btype == "text":
      text = _cl_strip_system(block.get("text", ""))
      if text:
        parts.append(text)
    elif btype == "image":
      src = block.get("source", {})
      if src.get("type") == "base64":
        mt = src.get("media_type", "image/png")
        data = src.get("data", "")
        parts.append(f"![image](data:{mt};base64,{data})")
      elif src.get("type") == "url":
        parts.append(f"![image]({src.get('url', '')})")
  return "\n\n".join(parts)


# ── ClaudeSessionStore ────────────────────────────────────────────────────────

class ClaudeSessionStore(SessionStore):
  """Session store backed by ~/.claude/projects/."""

  def __init__(self, project=None):
    """*project* overrides CWD for project directory detection."""
    self._project = project

  def is_available(self):
    return os.path.isdir(os.path.join(_cl_dir(), "projects"))

  def _project_dirs(self, all_projects=False):
    if all_projects:
      return _cl_all_project_dirs()
    pd = _cl_project_dir(self._project)
    return [pd] if os.path.isdir(pd) else []

  def _make_session(self, path, mtime_float, proj_dir):
    """Build a Session from a Claude JSONL file path and known mtime."""
    path = str(path)
    sid = os.path.splitext(os.path.basename(path))[0]
    title, ctime, rc = _cl_session_meta(path)
    mtime = datetime.datetime.fromtimestamp(mtime_float)
    return Session(
      source="claude",
      id=sid,
      path=Path(path),
      title=title,
      ctime=ctime or mtime,
      mtime=mtime,
      project=_cl_project_label(proj_dir),
      rc=rc,
    )

  def sessions(self, *, all_projects=False):
    result = []
    for pd in self._project_dirs(all_projects):
      for mtime_f, path in _cl_session_files(pd):
        result.append(self._make_session(path, mtime_f, pd))
    result.sort(key=lambda s: s.mtime, reverse=True)
    return result

  def find(self, id_or_glob, *, all_projects=False):
    """Resolve *id_or_glob* (without :N suffix) to a Session.

    Returns ``(session, [])`` on unique match.
    Returns ``(None, [candidates])`` when ambiguous.
    Raises ``FileNotFoundError`` when not found.
    """
    if id_or_glob == "latest":
      all_sess = self.sessions(all_projects=all_projects)
      if not all_sess:
        raise FileNotFoundError("No Claude sessions found")
      return all_sess[0], []

    all_matches = []

    for pd in self._project_dirs(all_projects):
      files = _cl_session_files(pd)
      if not files:
        continue

      # Exact UUID match (filename stem == pattern)
      for mtime_f, path in files:
        stem = os.path.splitext(os.path.basename(path))[0]
        if stem == id_or_glob:
          return self._make_session(path, mtime_f, pd), []

      # UUID prefix match — valid hex+dash string, allows 8-char short prefix.
      # Only skip title glob when prefix actually matched something; otherwise
      # fall through so e.g. "FEA" (all hex digits) still does a title search.
      if re.match(r"^[0-9a-f-]+$", id_or_glob, re.IGNORECASE):
        prefix_found = []
        for mtime_f, path in files:
          stem = os.path.splitext(os.path.basename(path))[0]
          if stem.startswith(id_or_glob):
            prefix_found.append(self._make_session(path, mtime_f, pd))
        if prefix_found:
          all_matches.extend(prefix_found)
          continue  # skip title glob — UUID prefix took priority

      # Title glob (bare words get implicit wildcard wrapping)
      glob_pat = (
        id_or_glob if ("*" in id_or_glob or "?" in id_or_glob)
        else f"*{id_or_glob}*"
      )
      for mtime_f, path in files:
        title, _, _ = _cl_session_meta(path)
        if fnmatch.fnmatch(title.lower(), glob_pat.lower()):
          all_matches.append(self._make_session(path, mtime_f, pd))

    if not all_matches:
      raise FileNotFoundError(f"No Claude session matching '{id_or_glob}'")
    if len(all_matches) == 1:
      return all_matches[0], []
    return None, all_matches

  def grep(self, session, *, plain=None, rx=None, before=0, after=0, first_only=False,
       ignore_case=False, rec_filter=None, cross_record=False):
    return _cl_session_grep(
      str(session.path), plain=plain, rx=rx, before=before, after=after,
      first_only=first_only, ignore_case=ignore_case, rec_filter=rec_filter,
      cross_record=cross_record,
    )

  def transcript(self, session, rec_filter=None, use_color=False,
                 show_date=False, record_number=False, display_tz=None):
    """Return the full Markdown transcript for *session*."""
    path = str(session.path)
    with open(path, encoding="utf-8") as f:
      if rec_filter and not rec_filter.is_trivial():
        records = []
        rec_nos = []
        for i, raw in enumerate((l for l in f if l.strip()), start=1):
          rec_no = i
          if rec_filter.past_hi(rec_no):
            break
          if not rec_filter.allows_rec(rec_no):
            continue
          rec = json.loads(raw)
          if not rec_filter.allows_ts(rec.get("timestamp")):
            continue
          records.append(rec)
          rec_nos.append(rec_no)
      else:
        records = [json.loads(l) for l in f if l.strip()]
        rec_nos = list(range(1, len(records) + 1))

    rec_width = len(str(session.rc))
    line1, line2 = _format_session_lines(session, use_color=use_color)
    out = [f"{line1}\n{line2}\n"]

    last_user_text = None  # deduplicate retried user messages
    for rec_no, rec in zip(rec_nos, records):
      if rec.get("isSidechain"):
        continue

      rtype = rec.get("type")
      suffix = ""
      if show_date or record_number:
        s = _build_hunk_prefix(rec_no, rec.get("timestamp"),
                               show_date=show_date, record_number=record_number,
                               rec_width=rec_width, tz=display_tz,
                               use_color=use_color).rstrip()
        if s:
          suffix = " " + s

      # ── User turn ──────────────────────────────────────────────────
      if rtype == "user":
        content = rec.get("message", {}).get("content", [])
        if not isinstance(content, list):
          continue
        if all(isinstance(b, dict) and b.get("type") == "tool_result" for b in content):
          continue
        text = _cl_user_text(content)
        if text and text != last_user_text:
          last_user_text = text
          out.append(f"## User{suffix}\n\n{text}\n")

      # ── Assistant turn ─────────────────────────────────────────────
      elif rtype == "assistant":
        msg = rec.get("message", {})
        if msg.get("model") == "<synthetic>":
          continue

        content = msg.get("content", [])
        thinking = [
          b.get("thinking", "")
          for b in content
          if b.get("type") == "thinking" and b.get("thinking")
        ]
        texts = [
          b.get("text", "")
          for b in content
          if b.get("type") == "text" and b.get("text")
        ]
        file_ops = [
          b for b in content
          if b.get("type") == "tool_use"
          and b.get("name") in ("Edit", "Write", "NotebookEdit")
        ]
        bash_ops = [
          b for b in content
          if b.get("type") == "tool_use" and b.get("name") == "Bash"
        ]
        todo_ops = [
          b for b in content
          if b.get("type") == "tool_use" and b.get("name") == "TodoWrite"
        ]

        if not thinking and not texts and not file_ops and not bash_ops and not todo_ops:
          continue

        block = f"## Claude{suffix}"

        if thinking:
          inner = "\n\n>\n\n".join(thinking)
          block += (
            f"\n\n<details>\n<summary>Thinking</summary>\n\n"
            f"{inner}\n\n</details>"
          )

        if texts:
          block += "\n\n" + "\n\n".join(texts)

        if file_ops:
          n = len(file_ops)
          label = f"{n} file change{'s' if n != 1 else ''}"
          ops_md = ""
          for op in file_ops:
            name = op.get("name")
            inp = op.get("input", {})
            fp = inp.get("file_path") or inp.get("notebook_path", "")
            if name == "Edit":
              old = inp.get("old_string", "")
              new = inp.get("new_string", "")
              diff = (
                "".join(f"- {l}\n" for l in old.splitlines())
                + "".join(f"+ {l}\n" for l in new.splitlines())
              )
              ops_md += f"\n**Edit** `{fp}`\n```diff\n{diff}```\n"
            elif name == "Write":
              ops_md += f"\n**Write** `{fp}` *(new file)*\n"
            elif name == "NotebookEdit":
              ops_md += f"\n**NotebookEdit** `{fp}`\n"
          block += (
            f"\n\n<details>\n<summary>{label}</summary>\n"
            f"{ops_md}\n</details>"
          )

        if bash_ops:
          n = len(bash_ops)
          label = f"{n} command{'s' if n != 1 else ''}"
          cmds_md = ""
          for op in bash_ops:
            inp = op.get("input", {})
            desc = inp.get("description", "")
            cmd = inp.get("command", "")
            cmds_md += f"\n**{desc}**\n```bash\n{cmd}\n```\n"
          block += (
            f"\n\n<details>\n<summary>{label}</summary>\n"
            f"{cmds_md}\n</details>"
          )

        if todo_ops:
          for op in todo_ops:
            todos = op.get("input", {}).get("todos", [])
            if not todos:
              continue
            items_md = ""
            for j, item in enumerate(todos, 1):
              text = item.get("content", "")
              status = item.get("status", "pending")
              if status == "completed":
                items_md += f"\n{j}. ~~{text}~~"
              elif status == "in_progress":
                items_md += f"\n{j}. **{text}**"
              else:
                items_md += f"\n{j}. {text}"
            block += (
              f"\n\n<details>\n<summary>Todos</summary>\n"
              f"{items_md}\n\n</details>"
            )

        out.append(block + "\n")

    return "\n".join(out)


# ── Codex-specific helpers ────────────────────────────────────────────────────

def _cx_home():
  """Return the Codex home directory (respects CODEX_HOME env var)."""
  return os.environ.get(
    "CODEX_HOME", os.path.join(os.path.expanduser("~"), ".codex")
  )


def _cx_updated_at_local(updated_at):
  """Convert a session-index *updated_at* ISO string to a local naive datetime.

  Handles the Windows Codex format ``YYYY-MM-DDThh:mm:ss.fffffffZ`` by
  truncating fractional seconds to 6 digits before parsing.
  Returns ``None`` if *updated_at* is empty or unparseable.
  """
  if not updated_at:
    return None
  try:
    ua = updated_at.replace("Z", "+00:00")
    if "." in ua:
      dot = ua.index(".")
      plus = ua.index("+", dot)
      ua = ua[:dot + 7] + ua[plus:]  # keep at most 6 fractional digits
    return datetime.datetime.fromisoformat(ua).astimezone().replace(tzinfo=None)
  except Exception:
    return None


def _cx_session_id_from_path(path):
  """Extract the canonical session UUID from a session file path.

  Handles plain UUID files (``<uuid>.jsonl``) and rollout snapshots
  (``rollout-YYYY-MM-DDThh-mm-ss-<uuid>.jsonl``).
  """
  stem = os.path.splitext(os.path.basename(path))[0]
  if stem.startswith("rollout-"):
    # Format: rollout-YYYY-MM-DDThh-mm-ss-{uuid-parts...}
    # Split: ["rollout", "YYYY", "MM", "DDThh", "mm", "ss", <uuid>...]
    parts = stem.split("-")
    if len(parts) > 6:
      return "-".join(parts[6:])
  return stem


def _cx_find_session_file(session_id):
  """Find the JSONL session file for the given session ID.

  Prefers an exact basename match (``<session_id>.jsonl``) over files that
  merely contain the ID as a substring (e.g. rollout snapshots).
  """
  sessions_dir = os.path.join(_cx_home(), "sessions")
  # Try exact match first
  exact = os.path.join(sessions_dir, f"{session_id}.jsonl")
  if os.path.isfile(exact):
    return exact
  # Substring glob fallback (handles rollout filenames)
  pattern = os.path.join(sessions_dir, "**", f"*{session_id}*.jsonl")
  matches = glob_mod.glob(pattern, recursive=True)
  exact_matches = [
    m for m in matches
    if os.path.splitext(os.path.basename(m))[0] == session_id
  ]
  if exact_matches:
    return exact_matches[0]
  if not matches:
    raise FileNotFoundError(
      f"No session file found for ID: {session_id}\n"
      f"Searched: {sessions_dir}"
    )
  if len(matches) > 1:
    _warn("multiple matches, using first:")
    for m in matches:
      print(f"  {m}", file=sys.stderr)
  return matches[0]


def _cx_first_user_message(path, *, max_chars=100):
  """Return the first user-message text from a Codex JSONL file, or None.

  Scans records until it finds the first ``event_msg`` with payload type
  ``user_message``.  The text is stripped and truncated to *max_chars*
  characters so it can serve as a synthetic session title.
  """
  try:
    with open(path, encoding="utf-8") as f:
      for line in f:
        try:
          rec = json.loads(line)
        except json.JSONDecodeError:
          continue
        if rec.get("type") == "event_msg":
          payload = rec.get("payload", {})
          if payload.get("type") == "user_message":
            text = payload.get("message", "").strip()
            # Strip IDE context preamble if present (same logic as transcript renderer)
            m = re.search(r"## My request for Codex:\n(.+)", text, re.DOTALL)
            if m:
              text = m.group(1).strip()
            if text:
              # Use only the first non-empty line to avoid multi-line titles
              first_line = next(
                (l for l in text.splitlines() if l.strip()), text
              ).strip()
              return first_line[:max_chars]
  except Exception:
    pass
  return None


def _cx_read_session_index():
  """
  Read session_index.jsonl and return a de-duplicated list of session dicts,
  sorted newest-first by updated_at.

  De-duplicates by id, keeping the entry with the latest updated_at.
  """
  path = os.path.join(_cx_home(), "session_index.jsonl")
  if not os.path.exists(path):
    return []
  entries = {}  # id → entry with latest updated_at
  with open(path, encoding="utf-8") as f:
    for line in f:
      line = line.strip()
      if not line:
        continue
      rec = json.loads(line)
      sid = rec.get("id")
      if not sid:
        continue
      if (
        sid not in entries
        or rec.get("updated_at", "") > entries[sid].get("updated_at", "")
      ):
        entries[sid] = rec
  result = list(entries.values())
  result.sort(key=lambda r: r.get("updated_at", ""), reverse=True)
  return result


def _cx_uuid7_ctime(sid):
  """Return creation datetime embedded in a UUID v7 session ID (first 48 bits = ms)."""
  try:
    hex48 = sid.replace("-", "")[:12]
    ms = int(hex48, 16)
    return datetime.datetime.fromtimestamp(ms / 1000)
  except Exception:
    return None


def _cx_session_grep(path, *, plain=None, rx=None, before=0, after=0, first_only=False,
           ignore_case=False, rec_filter=None, cross_record=False):
  """Return context hunks from matching messages in the Codex session at *path*.

  Each element of the returned list is a hunk: a list of
  ``(is_match, line_text, spans, rec_no, ts_str)`` tuples where *rec_no* is the
  1-based JSONL line number and *ts_str* is the raw timestamp string (or
  ``None``).

  When *first_only* is True, return as soon as any match is found.  *first_only*
  always uses per-record mode regardless of *cross_record*.
  If *rec_filter* is given, only records passing the filter are searched.
  When *cross_record* is True, context lines may come from neighbouring records.
  """
  result = []
  rec_no = 0
  tagged = [] if (cross_record and not first_only) else None
  try:
    with open(path, encoding="utf-8") as f:
      for raw in f:
        raw = raw.strip()
        if not raw:
          continue
        rec_no += 1
        if rec_filter and not rec_filter.is_trivial():
          if rec_filter.past_hi(rec_no):
            break
          if not rec_filter.allows_rec(rec_no):
            continue
        rec = json.loads(raw)
        ts_str = rec.get("timestamp")
        if rec_filter and not rec_filter.allows_ts(ts_str):
          continue
        rtype = rec.get("type")
        payload = rec.get("payload", {})
        texts = []
        if rtype == "event_msg":
          if payload.get("type") not in ("user_message", "agent_message"):
            continue
          text = payload.get("message", "")
          if text:
            texts.append(text)
        elif rtype == "response_item" and payload.get("type") == "custom_tool_call":
          inp = payload.get("input", "")
          if inp:
            texts.append(inp)
        if tagged is not None:
          for text in texts:
            for line in text.splitlines():
              tagged.append((line, rec_no, ts_str))
        else:
          for text in texts:
            for hunk_lines in _grep_context(
              text, plain=plain, rx=rx, before=before, after=after,
              ignore_case=ignore_case,
            ):
              result.append([(im, l, s, rec_no, ts_str) for im, l, s in hunk_lines])
            if first_only and result:
              return result
  except Exception:
    pass
  if tagged is not None:
    return _grep_context_tagged(
      tagged, plain=plain, rx=rx, before=before, after=after, ignore_case=ignore_case,
    )
  return result


def _cx_get_images_before(lines, idx):
  """Return base64 image URLs from the response_item/user preceding *idx*."""
  for i in range(idx - 1, -1, -1):
    l = lines[i]
    if (
      l.get("type") == "event_msg"
      and l.get("payload", {}).get("type") == "user_message"
    ):
      break  # hit previous user turn
    if (
      l.get("type") == "response_item"
      and l.get("payload", {}).get("role") == "user"
    ):
      content = l.get("payload", {}).get("content") or []
      imgs = [
        c["image_url"]
        for c in content
        if isinstance(c, dict)
        and c.get("type") == "input_image"
        and c.get("image_url")
      ]
      if imgs:
        return imgs
  return []


def _cx_get_patches_between(lines, start_idx, end_idx):
  """Return apply_patch inputs for all patches between two line indices."""
  patches = []
  for i in range(start_idx, end_idx):
    l = lines[i]
    if (
      l.get("type") == "response_item"
      and l.get("payload", {}).get("type") == "custom_tool_call"
      and l.get("payload", {}).get("name") == "apply_patch"
    ):
      patch_input = l["payload"].get("input", "")
      if patch_input:
        patches.append(patch_input)
  return patches


# ── CodexSessionStore ─────────────────────────────────────────────────────────

class CodexSessionStore(SessionStore):
  """Session store backed by ~/.codex/sessions/ and session_index.jsonl."""

  def is_available(self):
    return os.path.isdir(os.path.join(_cx_home(), "sessions"))

  def _make_session(self, entry):
    """Build a Session from a session index entry dict.  Returns None on error."""
    sid = entry.get("id", "")
    if not sid:
      return None
    try:
      path = Path(_cx_find_session_file(sid))
    except FileNotFoundError:
      return None
    title = entry.get("thread_name", "") or "(no title)"
    ctime = _cx_uuid7_ctime(sid)
    updated_at = entry.get("updated_at", "")
    mtime = _cx_updated_at_local(updated_at)
    if mtime is None:
      try:
        mtime = datetime.datetime.fromtimestamp(os.path.getmtime(str(path)))
      except Exception:
        mtime = ctime or datetime.datetime.now()
    if ctime is None:
      ctime = mtime
    rc = _count_records(str(path))
    return Session(
      source="codex",
      id=sid,
      path=path,
      title=title,
      ctime=ctime,
      mtime=mtime,
      project=None,
      rc=rc,
    )

  def _make_session_from_path(self, path, entries):
    """Build a Session from a file path, looking up the index for metadata."""
    path = str(path)
    sid = _cx_session_id_from_path(path)
    entry = next((e for e in entries if e.get("id", "") == sid), None)
    if entry:
      return self._make_session(entry)
    # Not in index: use file metadata only
    ctime = _cx_uuid7_ctime(sid)
    try:
      mtime = datetime.datetime.fromtimestamp(os.path.getmtime(path))
    except Exception:
      mtime = ctime or datetime.datetime.now()
    if ctime is None:
      ctime = mtime
    rc = _count_records(path)
    title = _cx_first_user_message(path) or "(no title)"
    return Session(
      source="codex",
      id=sid,
      path=Path(path),
      title=title,
      ctime=ctime,
      mtime=mtime,
      project=None,
      rc=rc,
    )

  def sessions(self, *, all_projects=False):
    """Return all Codex sessions, sorted newest-first.

    *all_projects* is accepted for API compatibility but is a no-op — Codex
    has no project partitioning, so all sessions are always returned.
    """
    entries = _cx_read_session_index()
    result = []
    for e in entries:
      sess = self._make_session(e)
      if sess is not None:
        result.append(sess)
    # Index is already sorted newest-first by updated_at
    return result

  def find(self, id_or_glob, *, all_projects=False):
    """Resolve *id_or_glob* (without :N suffix) to a Session.

    Returns ``(session, [])`` on unique match.
    Returns ``(None, [candidates])`` when ambiguous.
    Raises ``FileNotFoundError`` when not found.

    Note: *all_projects* is ignored (Codex has no project partitioning).
    """
    entries = _cx_read_session_index()
    indexed_ids = {e.get("id") for e in entries}

    if id_or_glob == "latest":
      if not entries:
        raise FileNotFoundError("Codex session_index.jsonl is empty or not found")
      sess = self._make_session(entries[0])
      if sess is None:
        raise FileNotFoundError("Latest Codex session file not found")
      return sess, []

    is_uuid_search = "*" not in id_or_glob and "?" not in id_or_glob
    all_matches = []

    if is_uuid_search:
      # UUID prefix via index
      prefix_matches = [e for e in entries if e.get("id", "").startswith(id_or_glob)]
      if len(prefix_matches) == 1:
        sess = self._make_session(prefix_matches[0])
        if sess:
          return sess, []
      elif len(prefix_matches) > 1:
        all_matches = [s for s in map(self._make_session, prefix_matches) if s]
        # Fall through to resolution below
      else:
        # No index match — try direct file lookup (full UUID not yet indexed)
        try:
          path = _cx_find_session_file(id_or_glob)
          sess = self._make_session_from_path(path, entries)
          if sess:
            return sess, []
        except FileNotFoundError:
          pass
        is_uuid_search = False  # allow title glob fallback

    if not is_uuid_search and not all_matches:
      # Title glob
      glob_pat = (
        id_or_glob if ("*" in id_or_glob or "?" in id_or_glob)
        else f"*{id_or_glob}*"
      )
      for e in entries:
        if fnmatch.fnmatch(e.get("thread_name", "").lower(), glob_pat.lower()):
          sess = self._make_session(e)
          if sess:
            all_matches.append(sess)

      # Fallback: scan session files not present in the index (e.g. recent
      # sessions whose index entry hasn't been written yet).  Use the first
      # user message as a synthetic title for matching.
      if not all_matches:
        sessions_dir = os.path.join(_cx_home(), "sessions")
        for fpath in glob_mod.glob(
            os.path.join(sessions_dir, "**", "*.jsonl"), recursive=True
        ):
          sid = _cx_session_id_from_path(fpath)
          if sid in indexed_ids:
            continue
          title = _cx_first_user_message(fpath) or ""
          if fnmatch.fnmatch(title.lower(), glob_pat.lower()):
            sess = self._make_session_from_path(fpath, entries)
            if sess:
              all_matches.append(sess)

    if not all_matches:
      raise FileNotFoundError(f"No Codex session matching '{id_or_glob}'")
    if len(all_matches) == 1:
      return all_matches[0], []
    return None, all_matches

  def grep(self, session, *, plain=None, rx=None, before=0, after=0, first_only=False,
       ignore_case=False, rec_filter=None, cross_record=False):
    return _cx_session_grep(
      str(session.path), plain=plain, rx=rx, before=before, after=after,
      first_only=first_only, ignore_case=ignore_case, rec_filter=rec_filter,
      cross_record=cross_record,
    )

  def transcript(self, session, rec_filter=None, use_color=False,
                 show_date=False, record_number=False, display_tz=None):
    """Return the full Markdown transcript for *session*."""
    path = str(session.path)
    with open(path, encoding="utf-8") as f:
      if rec_filter and not rec_filter.is_trivial():
        lines = []
        for i, raw in enumerate((l for l in f if l.strip()), start=1):
          rec_no = i
          if rec_filter.past_hi(rec_no):
            break
          if not rec_filter.allows_rec(rec_no):
            continue
          rec = json.loads(raw)
          if not rec_filter.allows_ts(rec.get("timestamp")):
            continue
          rec["_rec_no"] = rec_no
          lines.append(rec)
      else:
        lines = [json.loads(l) for l in f if l.strip()]

    # First pass: collect messages in order
    rec_width = len(str(session.rc))
    msgs = []
    for idx, l in enumerate(lines):
      if l.get("type") != "event_msg":
        continue
      et = l["payload"].get("type")
      rec_no = l.get("_rec_no", idx + 1)
      if et == "user_message":
        text = l["payload"].get("message", "")
        m = re.search(r"## My request for Codex:\n(.+)", text, re.DOTALL)
        if m:
          text = m.group(1).strip()
        images = _cx_get_images_before(lines, idx)
        msgs.append({"role": "user", "text": text, "images": images, "idx": idx,
                     "rec_no": rec_no, "ts": l.get("timestamp")})
      elif et == "agent_message":
        phase = l["payload"].get("phase", "")
        text = l["payload"].get("message", "")
        msgs.append(
          {"role": "codex", "phase": phase, "text": text, "idx": idx,
           "patches": [], "rec_no": rec_no, "ts": l.get("timestamp")}
        )

    # Second pass: attach patches to each final Codex message
    prev_idx = 0
    for msg in msgs:
      if msg["role"] == "codex" and msg["phase"] != "commentary":
        msg["patches"] = _cx_get_patches_between(lines, prev_idx, msg["idx"])
      if msg["role"] == "user":
        prev_idx = msg["idx"]

    line1, line2 = _format_session_lines(session, use_color=use_color)
    out = [f"{line1}\n{line2}\n"]

    i = 0
    while i < len(msgs):
      msg = msgs[i]

      if msg["role"] == "user":
        suffix = ""
        if show_date or record_number:
          s = _build_hunk_prefix(msg["rec_no"], msg["ts"],
                                 show_date=show_date, record_number=record_number,
                                 rec_width=rec_width, tz=display_tz,
                                 use_color=use_color).rstrip()
          if s:
            suffix = " " + s
        img_md = "\n".join(f'![image]({url})' for url in msg["images"])
        block = f'## User{suffix}\n\n{msg["text"]}'
        if img_md:
          block += f"\n\n{img_md}"
        out.append(block + "\n")
        i += 1

      else:  # codex turn
        codex_rec_no = msgs[i]["rec_no"]
        codex_ts = msgs[i]["ts"]
        commentary_items = []
        while i < len(msgs) and msgs[i]["role"] == "codex" and msgs[i]["phase"] == "commentary":
          commentary_items.append(msgs[i]["text"])
          i += 1

        final_msg = None
        if i < len(msgs) and msgs[i]["role"] == "codex" and msgs[i]["phase"] != "commentary":
          final_msg = msgs[i]
          i += 1

        suffix = ""
        if show_date or record_number:
          s = _build_hunk_prefix(codex_rec_no, codex_ts,
                                 show_date=show_date, record_number=record_number,
                                 rec_width=rec_width, tz=display_tz,
                                 use_color=use_color).rstrip()
          if s:
            suffix = " " + s
        block = f"## Codex{suffix}"
        if commentary_items:
          inner = "\n\n>\n\n".join(commentary_items)
          block += f"\n\n<details>\n<summary>Thoughts</summary>\n\n{inner}\n\n</details>"
        if final_msg:
          block += f"\n\n{final_msg['text']}"
          if final_msg["patches"]:
            n = len(final_msg["patches"])
            label = f"{n} file change{'s' if n != 1 else ''}"
            patches_md = "\n\n".join(
              f"```diff\n{p}\n```" for p in final_msg["patches"]
            )
            block += (
              f"\n\n<details>\n<summary>{label}</summary>\n\n"
              f"{patches_md}\n\n</details>"
            )
        out.append(block + "\n")

    return "\n".join(out)


# ── Shared display functions ──────────────────────────────────────────────────

def _format_session_lines(session, *, use_color=False):
  """Return ``(line1, line2)`` strings for a session header.

  Line 1: ``[source] [ctime]-[mtime] [project] records: N``
  Line 2: ``(uuid8) title``
  """
  ctime_str = session.ctime.strftime("%Y-%m-%d %H:%M")
  mtime_str = session.mtime.strftime("%Y-%m-%d %H:%M")
  ai_part   = _ansi(f"[{session.source}]", _C_PROJECT, active=use_color)
  date_part = _ansi(f"[{ctime_str}]-[{mtime_str}]", _C_DATE, active=use_color)
  proj_part = (
    _ansi(f" [{session.project}]", _C_PROJECT, active=use_color)
    if session.project else ""
  )
  rec_part = _ansi(f"records: {session.rc}", _C_RECORDS, active=use_color)
  line1 = f"{ai_part} {date_part}{proj_part} {rec_part}"
  line2 = _ansi(f"({session.id[:8]}) {session.title}", _C_TITLE, active=use_color)
  return line1, line2


def print_session_header(session, *, use_color=False):
  """Print the 2-line header used by --grep output and --id transcript display."""
  line1, line2 = _format_session_lines(session, use_color=use_color)
  print(line1)
  print(line2)


def print_session_list_row(i, session, *, use_color=False):
  """Print the ``N. line1 / indent line2`` row used by --ls output."""
  line1, line2 = _format_session_lines(session, use_color=use_color)
  prefix = f"{i:3}. "
  indent = " " * len(prefix)
  print(f"{prefix}{line1}")
  print(f"{indent}{line2}")


# ── Hunk-line prefix builder ──────────────────────────────────────────────────

def _parse_ts_to_dt(ts_str):
  """Parse a JSONL ISO-8601 timestamp to a tz-aware UTC datetime, or None."""
  if not ts_str:
    return None
  s = re.sub(r"\.\d+", "", ts_str).replace("Z", "+00:00")
  try:
    return datetime.datetime.fromisoformat(s)
  except ValueError:
    return None


def _parse_ts(ts_str, tz=None):
  """Normalise and convert a JSONL ISO-8601 timestamp string.

  Strips sub-second precision, replaces a trailing ``Z`` with ``+00:00`` so
  that ``datetime.fromisoformat`` accepts it, then converts to *tz*.  With
  ``tz=None`` the result is in the local system timezone (``dt.astimezone()``
  with no argument uses the OS locale).

  Returns a ``"YYYY-MM-DD HH:MM:SS"`` string, or ``"?"`` when *ts_str* is
  falsy.
  """
  if not ts_str:
    return "?"
  # Strip sub-second digits (e.g. .123456 or .8795484)
  s = re.sub(r"\.\d+", "", ts_str)
  # Normalise Z suffix so fromisoformat accepts it
  s = s.replace("Z", "+00:00")
  try:
    dt = datetime.datetime.fromisoformat(s)
    dt = dt.astimezone(tz)
    return dt.strftime("%Y-%m-%d %H:%M:%S")
  except (ValueError, OSError):
    # Fallback: best-effort raw slice
    return ts_str[:19].replace("T", " ")


def _resolve_tz(tz_str):
  """Resolve a timezone string to a ``datetime.tzinfo`` object.

  Accepts:

  - ``±HH:MM`` fixed offset (e.g. ``-04:00``, ``+05:30``) — resolved as a
    ``datetime.timezone``; no external dependencies.
  - IANA name (e.g. ``America/New_York``, ``UTC``) — resolved via
    ``zoneinfo`` (Python 3.9 stdlib).  Requires the ``tzdata`` package on
    platforms that do not ship a system timezone database (e.g. Windows).

  Returns ``(tzinfo, warning_msg)``.  On success *warning_msg* is ``None``.
  On IANA resolution failure *tzinfo* is ``None`` (caller falls back to local
  time) and *warning_msg* is a ``WARNING:`` string ready to print to stderr.
  """
  m = re.match(r"^([+-])(\d{2}):(\d{2})$", tz_str)
  if m:
    sign, hh, mm = m.group(1), int(m.group(2)), int(m.group(3))
    offset = datetime.timedelta(hours=hh, minutes=mm)
    if sign == "-":
      offset = -offset
    return datetime.timezone(offset), None
  # IANA name path
  try:
    import zoneinfo  # noqa: PLC0415
    return zoneinfo.ZoneInfo(tz_str), None
  except ImportError:
    return None, (
      "zoneinfo module not available; pip install tzdata; "
      "falling back to local time."
    )
  except KeyError:
    return None, (
      f"timezone '{tz_str}' not found; "
      "pip install tzdata; falling back to local time."
    )


def _parse_record_range(s, rc):
  """Parse ``"M:N"`` into a ``(lo, hi)`` 1-based inclusive pair.

  Either part may be empty (defaults: 1 and *rc* respectively).
  Negative values resolve Python-style: ``-1`` = *rc*, ``-2`` = *rc*-1, etc.
  Returns ``(lo, hi)`` clamped to ``[1, rc]``.  Raises ``ValueError`` on bad
  input.
  """
  if ":" not in s:
    raise ValueError(f"--records: expected M:N, got {s!r}")
  left, _, right = s.partition(":")
  def resolve(part, default):
    if not part.strip():
      return default
    n = int(part)           # raises ValueError if not an int
    if n < 0:
      n = rc + n + 1        # -1 → rc, -2 → rc-1, …
    return max(1, min(n, rc))
  lo = resolve(left,  1)
  hi = resolve(right, rc)
  return lo, hi


def _rollback_dt(dt, unit, tz):
  """Roll *dt* back by one unit (``'day'``, ``'month'``, or ``'year'``).

  Raises ``ValueError`` if the resulting date does not exist (e.g. Feb 30).
  """
  if unit == "day":
    return dt - datetime.timedelta(days=1)
  local = dt.astimezone(tz).replace(tzinfo=None)
  if unit == "month":
    m, y = local.month - 1, local.year
    if m == 0:
      m, y = 12, y - 1
    try:
      rolled = local.replace(year=y, month=m)
    except ValueError:
      raise ValueError(f"Day {local.day} does not exist in {y}-{m:02d}")
  else:  # year
    try:
      rolled = local.replace(year=local.year - 1)
    except ValueError:
      raise ValueError(
        f"Date {local.month:02d}-{local.day:02d} does not exist "
        f"in {local.year - 1}")
  return rolled.replace(tzinfo=tz).astimezone(datetime.timezone.utc)


def _parse_datetime_filter(s, ref_tz=None, anchor_dt=None):
  """Parse a partial datetime string to a tz-aware UTC datetime.

  Absolute (no prefix):

  - ``yyyy-MM-dd [hh:mm[:ss]]`` — full date; time defaults to midnight
  - ``MM-dd [hh:mm[:ss]]`` — current year assumed; wraps to prev year if future
  - ``dd hh:mm[:ss]`` — current month assumed; wraps to prev month if future
  - ``hh:mm[:ss]`` — today assumed; wraps to yesterday if future

  Relative (``-`` prefix, for ``--since``): offset from now:
  ``-mm``, ``-[dd ]hh:mm[:ss]``

  Relative (``+`` prefix, for ``--until``; requires *anchor_dt*):
  ``+mm``, ``+[dd ]hh:mm[:ss]`` — offset added to *anchor_dt*.

  Sub-leading components are normalised (``-100:90`` → ``−101:30``).
  Year/month components in relative form are not yet supported.
  Raises ``ValueError`` on unparseable input or invalid rollback date.
  """
  s = s.strip()
  tz = ref_tz or datetime.timezone.utc

  # ── Relative offset (- or +) ────────────────────────────────────────────────
  if s and s[0] in "+-":
    sign = 1 if s[0] == "+" else -1
    body = s[1:]
    # Optional leading days component separated by a single space
    if " " in body:
      day_str, body = body.split(" ", 1)
      days = int(day_str)
    else:
      days = 0
    parts = body.split(":")
    if len(parts) == 1:
      h, m, sec = 0, int(parts[0]), 0    # bare number = minutes
    elif len(parts) == 2:
      h, m, sec = int(parts[0]), int(parts[1]), 0
    else:
      h, m, sec = int(parts[0]), int(parts[1]), int(parts[2])
    # timedelta normalises out-of-range sub-components automatically
    delta = datetime.timedelta(days=days, hours=h, minutes=m, seconds=sec) * sign
    if sign > 0:
      if anchor_dt is None:
        raise ValueError("--until +offset requires --since to be set first")
      return anchor_dt + delta
    return datetime.datetime.now(datetime.timezone.utc) + delta

  # ── Absolute ────────────────────────────────────────────────────────────────
  now = datetime.datetime.now(tz)
  # Each tuple: (fmt, fill_year, fill_month, fill_day, rollback_unit)
  # rollback_unit: if resolved dt > now, roll back by this unit.
  formats = [
    ("%Y-%m-%d %H:%M:%S", None,     None,      None,    None),
    ("%Y-%m-%d %H:%M",    None,     None,      None,    None),
    ("%Y-%m-%d",          None,     None,      None,    None),    # midnight, no rollback
    ("%m-%d %H:%M:%S",    now.year, None,      None,    "year"),
    ("%m-%d %H:%M",       now.year, None,      None,    "year"),
    ("%m-%d",             now.year, None,      None,    "year"),  # midnight, rollback year
    ("%d %H:%M:%S",       now.year, now.month, None,    "month"),
    ("%d %H:%M",          now.year, now.month, None,    "month"),
    ("%H:%M:%S",          now.year, now.month, now.day, "day"),
    ("%H:%M",             now.year, now.month, now.day, "day"),
  ]
  for fmt, yr, mo, dy, rollback in formats:
    try:
      dt = datetime.datetime.strptime(s, fmt)
      if yr is not None: dt = dt.replace(year=yr)
      if mo is not None: dt = dt.replace(month=mo)
      if dy is not None: dt = dt.replace(day=dy)
      dt = dt.replace(tzinfo=tz).astimezone(datetime.timezone.utc)
      now_utc = now.astimezone(datetime.timezone.utc)
      if rollback and dt > now_utc:
        dt = _rollback_dt(dt, rollback, tz)
      return dt
    except ValueError:
      continue
  raise ValueError(f"Cannot parse datetime: {s!r}")


def _build_hunk_prefix(rec_no, ts_str, *, show_date=False, record_number=False,
                       rec_width=1, tz=None, use_color=False):
  """Return the prefix string to prepend to every line of a grep hunk.

  *rec_width* is the field width for right-justifying the record number,
  typically ``len(str(session.rc))`` so the column aligns across all hunks.

  Format (when both flags active): ``[YYYY-MM-DD HH:MM:SS]: {rec_no:>w}: ``
  Format (date only):               ``[YYYY-MM-DD HH:MM:SS]: ``
  Format (record number only):      ``{rec_no:>w}: ``
  Format (neither):                 ``""``
  """
  prefix = ""
  if show_date:
    ts_display = _parse_ts(ts_str, tz)
    if use_color:
      prefix += f"{_C_RECDATE}[{ts_display}]:{_C_RESET} "
    else:
      prefix += f"[{ts_display}]: "
  if record_number:
    if use_color:
      prefix += f"{_C_RECNO}{rec_no:{rec_width}}:{_C_RESET} "
    else:
      prefix += f"{rec_no:{rec_width}}: "
  return prefix


# ── Multi-pattern grep helper ─────────────────────────────────────────────────

def _session_display_hunks(store, session, patterns_kw, before, after, *,
                           ignore_case=False, rec_filter=None, cross_record=False):
  """Return display hunks if *session* matches ALL patterns (AND), else None.

  When multiple patterns are given:
  - AND condition: each pattern must produce at least one match.
  - Display: hunks are generated with an OR-combined regex so any matching
    line is highlighted.

  Note: with multiple patterns and context lines, the same line may appear
  in more than one hunk if it falls within the context range of matches from
  different patterns.  This is acceptable for the MVP; a proper fix would
  require merging overlapping hunk ranges (tracked as a future TODO).
  """
  if len(patterns_kw) == 1:
    hunks = store.grep(
      session, before=before, after=after, ignore_case=ignore_case,
      rec_filter=rec_filter, cross_record=cross_record, **patterns_kw[0]
    )
    return hunks if hunks else None

  # Multiple patterns: AND check — stop scanning as soon as first match found
  for kw in patterns_kw:
    if not store.grep(session, before=0, after=0, first_only=True,
                      ignore_case=ignore_case, rec_filter=rec_filter, **kw):
      return None

  # All patterns match — build combined OR regex for display
  parts = []
  for kw in patterns_kw:
    if "plain" in kw:
      parts.append(re.escape(kw["plain"]))
    else:
      parts.append(kw["rx"].pattern)
  flags = re.IGNORECASE if ignore_case else 0
  combined_rx = re.compile("|".join(f"(?:{p})" for p in parts), flags)
  return store.grep(session, rx=combined_rx, before=before, after=after,
                    ignore_case=ignore_case, rec_filter=rec_filter,
                    cross_record=cross_record)


# ── Session resolution helper ─────────────────────────────────────────────────

def _resolve_single_session(stores, id_val, all_projects):
  """Resolve *id_val* across all active stores.  Exits on error or ambiguity.

  Handles the ``:N`` suffix for selecting from an ambiguous list.
  Returns a single :class:`Session` on success.
  """
  # Parse :N suffix before passing to stores
  which = None
  base_id = id_val
  if ":" in id_val:
    head, tail = id_val.rsplit(":", 1)
    if tail.isdigit():
      base_id, which = head, int(tail)

  all_matches = []
  for store in stores.values():
    try:
      sess, candidates = store.find(base_id, all_projects=all_projects)
      if sess:
        all_matches.append(sess)
      else:
        all_matches.extend(candidates)
    except FileNotFoundError:
      pass
    except ValueError as exc:
      _error(str(exc))
      sys.exit(1)

  if not all_matches:
    _error(f"No session matching '{id_val}'")
    sys.exit(1)

  if len(all_matches) == 1:
    return all_matches[0]

  if which is not None:
    if 1 <= which <= len(all_matches):
      return all_matches[which - 1]
    _error(f"Index {which} out of range (1\u2013{len(all_matches)})")
    sys.exit(1)

  # Ambiguous
  _error(f"Ambiguous: {len(all_matches)} sessions match '{id_val}':")
  for i, sess in enumerate(all_matches, 1):
    proj = f" [{sess.project}]" if sess.project else ""
    print(
      f"  {i:3}. {sess.title:<55}  ({sess.id[:8]}...) [{sess.source}{proj}]",
      file=sys.stderr,
    )
  print(f"\nUse --id '{base_id}:<N>' to select one.", file=sys.stderr)
  sys.exit(1)


# ── Entry point ───────────────────────────────────────────────────────────────

def main():
  ap = argparse.ArgumentParser(
    description="Unified transcript and session search for Claude and Codex.",
    epilog=(
      "Examples:\n"
      "  %(prog)s --ls                            list all sessions (both AIs)\n"
      "  %(prog)s --ls --claude                   Claude sessions only\n"
      "  %(prog)s --ls --all-projects             all Claude projects + Codex\n"
      "  %(prog)s --id f4b19167                   Claude transcript by UUID prefix\n"
      "  %(prog)s --id latest --codex             latest Codex transcript\n"
      "  %(prog)s --id f4b19167 out.md            write transcript to file\n"
      "  %(prog)s --grep 'FEA' -C 3               show matching context\n"
      "  %(prog)s --grep 'FEA' --grep 'lattice'   AND search\n"
      "  %(prog)s --grep 'FEA' --id f4b19167      grep within one session\n"
      "  %(prog)s --grep-re 'FEA|lattice'         regex search\n"
      "\n"
      "Session header format:\n"
      "  [claude] [creation]-[modification] [project] records: N\n"
      "  (uuid8) title\n"
      "  Creation time: first JSONL timestamp (Claude) / UUID v7 decode (Codex).\n"
      "  Modification time: file mtime (Claude) / updated_at from index (Codex)."
    ),
    formatter_class=argparse.RawDescriptionHelpFormatter,
  )

  # Source selector (mutually exclusive)
  src_group = ap.add_mutually_exclusive_group()
  src_group.add_argument(
    "--claude", action="store_true",
    help="Claude sessions only.",
  )
  src_group.add_argument(
    "--codex", action="store_true",
    help="Codex sessions only.",
  )
  src_group.add_argument(
    "--both-AIs", action="store_true", dest="both_ais",
    help="Both AIs (default when no source flag given).",
  )

  # Session selector
  ap.add_argument(
    "--id",
    metavar="GLOB_OR_UUID",
    action="append",
    help=(
      "Select session by title glob, UUID (or prefix), or 'latest'. "
      "Append :<N> to pick the Nth result when ambiguous. "
      "Repeating --id warns and uses the last value."
    ),
  )

  # Search
  ap.add_argument(
    "--grep",
    metavar="TEXT",
    action="append",
    help=(
      "Search sessions for TEXT (plain, case-insensitive). "
      "Repeatable: multiple patterns use AND at session level, OR at line level."
    ),
  )
  ap.add_argument(
    "--grep-re",
    metavar="PATTERN",
    dest="grep_re",
    action="append",
    help=(
      "Search sessions matching PATTERN (case-insensitive regex). "
      "Repeatable with AND/OR semantics like --grep. "
      "May be combined with --grep."
    ),
  )

  # List / display modifiers
  ap.add_argument(
    "--ls",
    action="store_true",
    help=(
      "Standalone: list all sessions. "
      "With --grep: list matching sessions (suppress hunks). "
      "With --id: show list row (suppress transcript)."
    ),
  )
  ap.add_argument(
    "--show-empty",
    action="store_true", dest="show_empty",
    help="Include (no title) sessions in --ls output (hidden by default).",
  )
  ap.add_argument(
    "--words-only",
    action="store_true", dest="words_only",
    help=(
      "With --grep: match word characters only, ignoring punctuation "
      "and HTML tags between words."
    ),
  )
  ap.add_argument(
    "-i", "--ignore-case",
    action="store_true", dest="ignore_case",
    help="With --grep/--grep-re: match case-insensitively (default is case-sensitive).",
  )
  ap.add_argument(
    "-n", "--record-number",
    action="store_true", dest="record_number",
    help="With --grep: prefix each output line with its JSONL record number.",
  )
  ap.add_argument(
    "-d", "--show-date",
    action="store_true", dest="show_date",
    help="With --grep: prefix each output line with the record timestamp.",
  )
  ap.add_argument(
    "--tz",
    metavar="ZONE", dest="tz", default=None,
    help=(
      "Timezone for -d timestamps: IANA name (e.g. America/New_York) or "
      "±HH:MM fixed offset (e.g. -04:00). Implies -d. "
      "Defaults to local system time when omitted."
    ),
  )
  ap.add_argument(
    "--records",
    metavar="M:N", dest="records", default=None,
    help=(
      "Restrict to JSONL records M through N (1-based, inclusive). "
      "Either bound may be omitted (:N = 1..N, M: = M..end). "
      "Negative indices: -1 = last record, -2 = second-to-last, etc."
    ),
  )
  ap.add_argument(
    "--since",
    metavar="DT", dest="since", default=None,
    help=(
      "Include only records at or after DT. "
      "Absolute: hh:mm[:ss], dd hh:mm, MM-dd, yyyy-MM-dd [hh:mm[:ss]]. "
      "Relative: -mm or -[dd ]hh:mm[:ss] (offset from now)."
    ),
  )
  ap.add_argument(
    "--until",
    metavar="DT", dest="until", default=None,
    help=(
      "Include only records at or before DT. "
      "Absolute: same forms as --since. "
      "Relative: +mm or +[dd ]hh:mm[:ss] (offset from --since; requires --since)."
    ),
  )

  # Context lines
  ap.add_argument(
    "-A", "--after-context",
    metavar="N", type=int, default=0, dest="after_context",
    help="Print N lines of context after each match.",
  )
  ap.add_argument(
    "-B", "--before-context",
    metavar="N", type=int, default=0, dest="before_context",
    help="Print N lines of context before each match.",
  )
  ap.add_argument(
    "-C", "--context",
    metavar="N", type=int, default=None,
    help="Print N lines of context before and after each match.",
  )
  ap.add_argument(
    "-x", "--cross-record",
    action="store_true", default=False, dest="cross_record",
    help=(
      "Allow -A/-B/-C context to span across JSONL record boundaries. "
      "Without this flag, context is confined to the record that contains "
      "the match."
    ),
  )

  # Color
  ap.add_argument(
    "--color", "--colour",
    metavar="WHEN", default="auto", choices=["always", "auto", "never"],
    help="Colorize output: always, auto (TTY detection; default), or never.",
  )

  # Claude project
  ap.add_argument(
    "--project",
    metavar="PATH",
    help="Claude project directory (default: current working directory).",
  )
  ap.add_argument(
    "--all-projects",
    action="store_true", dest="all_projects",
    help=(
      "Include all Claude projects instead of just the current one. "
      "No-op for Codex (no project partitioning)."
    ),
  )

  # Output file
  ap.add_argument(
    "output",
    nargs="?",
    help="Write transcript to file instead of stdout (requires --id, no --grep).",
  )

  args = ap.parse_args()

  # ── Validate argument combinations ─────────────────────────────────────────

  if args.output and (args.grep or args.grep_re):
    ap.error("output file cannot be used with --grep/--grep-re (transcript mode only)")

  id_args = args.id or []
  if len(id_args) > 1:
    _warn(f"--id given {len(id_args)} times; using last value '{id_args[-1]}'")
  id_val = id_args[-1] if id_args else None

  if args.output and not id_val:
    ap.error("output file requires --id")

  # ── Timezone resolution ─────────────────────────────────────────────────────

  _display_tz = None  # None → local system time via dt.astimezone()
  if args.tz:
    args.show_date = True  # --tz implies -d
    _display_tz, _tz_warn = _resolve_tz(args.tz)
    if _tz_warn:
      _warn(_tz_warn)
      _display_tz = None  # fall back to local time

  # ── Record filter ──────────────────────────────────────────────────────────

  _rec_filter = None
  if args.records or args.since or args.until:
    _rec_filter = RecordFilter()
    if args.since:
      try:
        _rec_filter.ts_lo = _parse_datetime_filter(args.since, _display_tz)
      except ValueError as e:
        _error(str(e))
        sys.exit(1)
    if args.until:
      try:
        _rec_filter.ts_hi = _parse_datetime_filter(
          args.until, _display_tz, anchor_dt=_rec_filter.ts_lo)
      except ValueError as e:
        _error(str(e))
        sys.exit(1)
    # --records range is resolved per-session (may need session.rc for negatives)

  def _resolve_rec_filter(session):
    """Return a RecordFilter with rec_lo/rec_hi resolved for *session*."""
    if not args.records:
      return _rec_filter
    try:
      lo, hi = _parse_record_range(args.records, session.rc)
    except ValueError as e:
      _error(str(e))
      sys.exit(1)
    return RecordFilter(
      rec_lo=lo, rec_hi=hi,
      ts_lo=_rec_filter.ts_lo if _rec_filter else None,
      ts_hi=_rec_filter.ts_hi if _rec_filter else None,
    )

  # ── Color setup ────────────────────────────────────────────────────────────

  use_color = (
    args.color == "always"
    or (args.color == "auto" and sys.__stdout__ is not None and sys.__stdout__.isatty())
  )
  if use_color and not _COLORAMA_OK:
    _warn("colorama not installed; color output disabled. pip install colorama")
    use_color = False

  # ── Store setup ────────────────────────────────────────────────────────────

  claude_store = ClaudeSessionStore(project=args.project)
  codex_store  = CodexSessionStore()

  stores = {}  # ordered: "claude" before "codex"
  if args.codex:
    if not codex_store.is_available():
      _error("Codex is not installed (~/.codex/sessions/ not found)")
      sys.exit(1)
    stores["codex"] = codex_store
  elif args.claude:
    if not claude_store.is_available():
      _error("Claude is not installed (~/.claude/projects/ not found)")
      sys.exit(1)
    stores["claude"] = claude_store
  else:
    # --both-AIs (default): silently skip unavailable stores
    if claude_store.is_available():
      stores["claude"] = claude_store
    if codex_store.is_available():
      stores["codex"] = codex_store
    if not stores:
      _error("Neither Claude nor Codex is installed")
      sys.exit(1)

  # ── Build grep patterns ────────────────────────────────────────────────────

  patterns_kw = []  # list of {"plain": str} or {"rx": compiled_pattern}
  before = after = 0
  grep_label = ""

  if args.grep or args.grep_re:
    before = args.before_context
    after  = args.after_context
    if args.context is not None:
      before = after = args.context

    if args.grep_re:
      import re as _remod  # fallback; overridden below if regex is available
      try:
        try:
          import regex as _remod  # type: ignore[assignment]
        except ImportError:
          pass  # keep stdlib re
        for p in args.grep_re:
          flags = _remod.IGNORECASE if args.ignore_case else 0
          rx = _remod.compile(p, flags)
          patterns_kw.append({"rx": rx})
      except _remod.error as exc:
        _error(f"invalid regex: {exc}")
        sys.exit(1)
    if args.grep:
      for p in args.grep:
        if args.words_only:
          patterns_kw.append({"rx": _plain_to_words_only_rx(p, ignore_case=args.ignore_case)})
        else:
          patterns_kw.append({"plain": p})
    labels = []
    if args.grep_re:
      labels.append(f"grep-re {args.grep_re}")
    if args.grep:
      labels.append(f"grep {args.grep}")
    grep_label = " AND ".join(labels)

  # ── Dispatch ───────────────────────────────────────────────────────────────

  # Branch 1: --grep / --grep-re (primary: search)
  if args.grep or args.grep_re:
    if id_val:
      # --id scopes search to a single session
      session = _resolve_single_session(stores, id_val, args.all_projects)
      candidates = [session]
    else:
      # All sessions from all stores, sorted by mtime descending
      candidates = []
      for store in stores.values():
        candidates.extend(store.sessions(all_projects=args.all_projects))
      candidates.sort(key=lambda s: s.mtime, reverse=True)

    matched = []  # [(session, hunks), ...]
    for session in candidates:
      store = stores[session.source]
      hunks = _session_display_hunks(
        store, session, patterns_kw, before, after, ignore_case=args.ignore_case,
        rec_filter=_resolve_rec_filter(session), cross_record=args.cross_record,
      )
      if hunks is not None:
        matched.append((session, hunks))

    if not matched:
      _info(f"No sessions match {grep_label}.")
    elif args.ls:
      i = 0
      for session, _ in matched:
        if session.title == "(no title)" and not args.show_empty:
          continue
        i += 1
        print_session_list_row(i, session, use_color=use_color)
    else:
      for sess_idx, (session, hunks) in enumerate(matched):
        if sess_idx > 0:
          print()
        print_session_header(session, use_color=use_color)
        rec_width = len(str(session.rc))
        for hunk_idx, hunk_lines in enumerate(hunks):
          if hunk_idx > 0:
            print("--")
          for _is_match, line, spans, rec_no, ts_str in hunk_lines:
            prefix = _build_hunk_prefix(rec_no, ts_str,
                                        show_date=args.show_date,
                                        record_number=args.record_number,
                                        rec_width=rec_width,
                                        tz=_display_tz,
                                        use_color=use_color)
            print(prefix + _colorize(line, spans, active=use_color))
    sys.exit(0)

  # Branch 2: --id without --grep (primary: transcript / list row)
  if id_val:
    session = _resolve_single_session(stores, id_val, args.all_projects)

    if args.ls:
      print_session_list_row(1, session, use_color=use_color)
      sys.exit(0)

    _info(f"Session: {session.path}")
    store = stores[session.source]
    transcript_text = store.transcript(session, rec_filter=_resolve_rec_filter(session),
                                        use_color=use_color,
                                        show_date=args.show_date,
                                        record_number=args.record_number,
                                        display_tz=_display_tz)

    if args.output:
      with open(args.output, "w", encoding="utf-8") as fh:
        fh.write(transcript_text)
      _info(f"Written to: {args.output}")
    else:
      print(transcript_text)
    sys.exit(0)

  # Branch 3: --ls standalone
  if args.ls:
    all_sessions = []
    for store in stores.values():
      all_sessions.extend(store.sessions(all_projects=args.all_projects))
    all_sessions.sort(key=lambda s: s.mtime, reverse=True)

    if not all_sessions:
      _info("No sessions found.")
    else:
      i = 0
      for session in all_sessions:
        if session.title == "(no title)" and not args.show_empty:
          continue
        i += 1
        print_session_list_row(i, session, use_color=use_color)
    sys.exit(0)

  # No primary operation given
  ap.print_help(sys.stderr)
  sys.exit(1)


if __name__ == "__main__":
  try:
    main()
  except (BrokenPipeError, KeyboardInterrupt):
    sys.exit(0)
  except OSError as _e:
    # Windows raises EINVAL (22) when writing to a closed pipe (e.g. head/more).
    import errno as _errno
    if _e.errno in (_errno.EPIPE, _errno.EINVAL):
      sys.exit(0)
    raise
