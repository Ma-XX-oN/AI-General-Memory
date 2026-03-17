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
    _C_RESET   = _cm.Style.RESET_ALL
    _C_MATCH   = _cm.Style.BRIGHT + _cm.Fore.RED
    _C_DATE    = _cm.Fore.CYAN
    _C_PROJECT = _cm.Fore.YELLOW
    _C_TITLE   = _cm.Style.BRIGHT
    _COLORAMA_OK = True
except ImportError:
    _C_RESET   = ""
    _C_MATCH   = ""
    _C_DATE    = ""
    _C_PROJECT = ""
    _C_TITLE   = ""
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


def _plain_to_words_only_rx(plain):
    """
    Build a regex from a plain search string that ignores punctuation and tags.

    Splits *plain* on non-word characters, then joins the resulting words
    with ``(?:<[^>]+>|[^\\w])*`` so any punctuation, whitespace, or
    HTML/XML tags between words in the target text are accepted.
    """
    words = [re.escape(w) for w in re.split(r"[^\w]+", plain.lower()) if w]
    sep = r"(?:<[^>]+>)*(?:[^\w<>](?:<[^>]+>)*)+"
    return re.compile(sep.join(words), re.IGNORECASE)


def _grep_context(text, *, plain=None, rx=None, before=0, after=0):
    """
    Find all matches in *text* and return context hunks.

    Each hunk is a list of ``(is_match, line_text, spans)`` tuples where
    *spans* is a list of ``(start, end)`` character offsets of matches
    within *line_text*.
    """
    lines = text.splitlines()
    if not lines:
        return []

    match_info = {}  # line_idx -> [(start, end), ...]
    for i, line in enumerate(lines):
        if plain is not None:
            spans, pos, lower = [], 0, line.lower()
            while True:
                idx = lower.find(plain, pos)
                if idx < 0:
                    break
                spans.append((idx, idx + len(plain)))
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


# ── SessionStore ABC ──────────────────────────────────────────────────────────

class SessionStore(ABC):
    """Abstract store; each AI backend provides a concrete subclass."""

    @abstractmethod
    def is_available(self):
        """Return True if this AI's session storage exists on disk."""

    @abstractmethod
    def sessions(self, *, all_projects=False):
        """Return all Session objects, sorted newest-first by mtime."""

    @abstractmethod
    def find(self, id_or_glob, *, all_projects=False):
        """Resolve UUID prefix/full UUID/title glob.

        *:N suffix is NOT handled here — strip it before calling.*

        Returns ``(session, [])`` on unambiguous match.
        Returns ``(None, [candidates])`` when ambiguous.
        Raises ``FileNotFoundError`` when not found.
        """

    @abstractmethod
    def grep(self, session, *, plain=None, rx=None, before=0, after=0, first_only=False):
        """Return context hunks for all matches in *session*.

        Each hunk is a list of ``(is_match, line_text, [(start, end), ...])``
        tuples.  When *first_only* is True, return as soon as any match is
        found (used for fast AND membership checks).
        """

    @abstractmethod
    def transcript(self, session):
        """Return the full Markdown transcript string for *session*."""


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


def _cl_session_grep(path, *, plain=None, rx=None, before=0, after=0, first_only=False):
    """Return context hunks from matching content in the Claude session at *path*.

    When *first_only* is True, return as soon as any match is found (used for
    the AND membership check in :func:`_session_display_hunks`).
    """
    hunks = []
    try:
        with open(path, encoding="utf-8") as f:
            for raw in f:
                raw = raw.strip()
                if not raw:
                    continue
                rec = json.loads(raw)
                if rec.get("isSidechain"):
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
                for text in texts:
                    hunks.extend(
                        _grep_context(text, plain=plain, rx=rx, before=before, after=after)
                    )
                    if first_only and hunks:
                        return hunks
    except Exception:
        pass
    return hunks


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

    def grep(self, session, *, plain=None, rx=None, before=0, after=0, first_only=False):
        return _cl_session_grep(
            str(session.path), plain=plain, rx=rx, before=before, after=after,
            first_only=first_only,
        )

    def transcript(self, session):
        """Return the full Markdown transcript for *session*."""
        path = str(session.path)
        with open(path, encoding="utf-8") as f:
            records = [json.loads(l) for l in f if l.strip()]

        line1, line2 = _format_session_lines(session)
        out = [f"{line1}\n{line2}\n"]

        last_user_text = None  # deduplicate retried user messages
        for rec in records:
            if rec.get("isSidechain"):
                continue

            rtype = rec.get("type")

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
                    out.append(f"## User\n\n{text}\n")

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

                block = "## Claude"

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
        print("Warning: multiple matches, using first:", file=sys.stderr)
        for m in matches:
            print(f"  {m}", file=sys.stderr)
    return matches[0]


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


def _cx_session_grep(path, *, plain=None, rx=None, before=0, after=0, first_only=False):
    """Return context hunks from matching messages in the Codex session at *path*.

    When *first_only* is True, return as soon as any match is found.
    """
    hunks = []
    try:
        with open(path, encoding="utf-8") as f:
            for raw in f:
                raw = raw.strip()
                if not raw:
                    continue
                rec = json.loads(raw)
                rtype = rec.get("type")
                payload = rec.get("payload", {})
                if rtype == "event_msg":
                    if payload.get("type") not in ("user_message", "agent_message"):
                        continue
                    text = payload.get("message", "")
                    if text:
                        hunks.extend(
                            _grep_context(text, plain=plain, rx=rx, before=before, after=after)
                        )
                        if first_only and hunks:
                            return hunks
                elif rtype == "response_item" and payload.get("type") == "custom_tool_call":
                    inp = payload.get("input", "")
                    if inp:
                        hunks.extend(
                            _grep_context(inp, plain=plain, rx=rx, before=before, after=after)
                        )
                        if first_only and hunks:
                            return hunks
    except Exception:
        pass
    return hunks


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
        return Session(
            source="codex",
            id=sid,
            path=Path(path),
            title="(no title)",
            ctime=ctime,
            mtime=mtime,
            project=None,
            rc=rc,
        )

    def sessions(self, *, all_projects=False):
        # Codex has no project partitioning; all_projects is a no-op
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

        if not all_matches:
            raise FileNotFoundError(f"No Codex session matching '{id_or_glob}'")
        if len(all_matches) == 1:
            return all_matches[0], []
        return None, all_matches

    def grep(self, session, *, plain=None, rx=None, before=0, after=0, first_only=False):
        return _cx_session_grep(
            str(session.path), plain=plain, rx=rx, before=before, after=after,
            first_only=first_only,
        )

    def transcript(self, session):
        """Return the full Markdown transcript for *session*."""
        path = str(session.path)
        with open(path, encoding="utf-8") as f:
            lines = [json.loads(l) for l in f if l.strip()]

        # First pass: collect messages in order
        msgs = []
        for idx, l in enumerate(lines):
            if l.get("type") != "event_msg":
                continue
            et = l["payload"].get("type")
            if et == "user_message":
                text = l["payload"].get("message", "")
                m = re.search(r"## My request for Codex:\n(.+)", text, re.DOTALL)
                if m:
                    text = m.group(1).strip()
                images = _cx_get_images_before(lines, idx)
                msgs.append({"role": "user", "text": text, "images": images, "idx": idx})
            elif et == "agent_message":
                phase = l["payload"].get("phase", "")
                text = l["payload"].get("message", "")
                msgs.append(
                    {"role": "codex", "phase": phase, "text": text, "idx": idx, "patches": []}
                )

        # Second pass: attach patches to each final Codex message
        prev_idx = 0
        for msg in msgs:
            if msg["role"] == "codex" and msg["phase"] != "commentary":
                msg["patches"] = _cx_get_patches_between(lines, prev_idx, msg["idx"])
            if msg["role"] == "user":
                prev_idx = msg["idx"]

        line1, line2 = _format_session_lines(session)
        out = [f"{line1}\n{line2}\n"]

        i = 0
        while i < len(msgs):
            msg = msgs[i]

            if msg["role"] == "user":
                img_md = "\n".join(f'![image]({url})' for url in msg["images"])
                block = f'## User\n\n{msg["text"]}'
                if img_md:
                    block += f"\n\n{img_md}"
                out.append(block + "\n")
                i += 1

            else:  # codex turn
                commentary_items = []
                while i < len(msgs) and msgs[i]["role"] == "codex" and msgs[i]["phase"] == "commentary":
                    commentary_items.append(msgs[i]["text"])
                    i += 1

                final_msg = None
                if i < len(msgs) and msgs[i]["role"] == "codex" and msgs[i]["phase"] != "commentary":
                    final_msg = msgs[i]
                    i += 1

                block = "## Codex"
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
    line1 = f"{ai_part} {date_part}{proj_part} records: {session.rc}"
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


# ── Multi-pattern grep helper ─────────────────────────────────────────────────

def _session_display_hunks(store, session, patterns_kw, before, after):
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
        hunks = store.grep(session, before=before, after=after, **patterns_kw[0])
        return hunks if hunks else None

    # Multiple patterns: AND check — stop scanning as soon as first match found
    for kw in patterns_kw:
        if not store.grep(session, before=0, after=0, first_only=True, **kw):
            return None

    # All patterns match — build combined OR regex for display
    parts = []
    for kw in patterns_kw:
        if "plain" in kw:
            parts.append(re.escape(kw["plain"]))
        else:
            parts.append(kw["rx"].pattern)
    combined_rx = re.compile("|".join(f"(?:{p})" for p in parts), re.IGNORECASE)
    return store.grep(session, rx=combined_rx, before=before, after=after)


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
            print(f"Error: {exc}", file=sys.stderr)
            sys.exit(1)

    if not all_matches:
        print(f"Error: No session matching '{id_val}'", file=sys.stderr)
        sys.exit(1)

    if len(all_matches) == 1:
        return all_matches[0]

    if which is not None:
        if 1 <= which <= len(all_matches):
            return all_matches[which - 1]
        print(
            f"Error: Index {which} out of range (1\u2013{len(all_matches)})",
            file=sys.stderr,
        )
        sys.exit(1)

    # Ambiguous
    print(f"Ambiguous: {len(all_matches)} sessions match '{id_val}':", file=sys.stderr)
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
        print(
            f"Warning: --id given {len(id_args)} times; using last value '{id_args[-1]}'",
            file=sys.stderr,
        )
    id_val = id_args[-1] if id_args else None

    if args.output and not id_val:
        ap.error("output file requires --id")

    # ── Color setup ────────────────────────────────────────────────────────────

    use_color = (
        args.color == "always"
        or (args.color == "auto" and sys.__stdout__.isatty())
    )
    if use_color and not _COLORAMA_OK:
        print(
            "Warning: colorama not installed; color output disabled. "
            "pip install colorama",
            file=sys.stderr,
        )
        use_color = False

    # ── Store setup ────────────────────────────────────────────────────────────

    claude_store = ClaudeSessionStore(project=args.project)
    codex_store  = CodexSessionStore()

    stores = {}  # ordered: "claude" before "codex"
    if args.codex:
        if not codex_store.is_available():
            print(
                "Error: Codex is not installed (~/.codex/sessions/ not found)",
                file=sys.stderr,
            )
            sys.exit(1)
        stores["codex"] = codex_store
    elif args.claude:
        if not claude_store.is_available():
            print(
                "Error: Claude is not installed (~/.claude/projects/ not found)",
                file=sys.stderr,
            )
            sys.exit(1)
        stores["claude"] = claude_store
    else:
        # --both-AIs (default): silently skip unavailable stores
        if claude_store.is_available():
            stores["claude"] = claude_store
        if codex_store.is_available():
            stores["codex"] = codex_store
        if not stores:
            print("Error: Neither Claude nor Codex is installed", file=sys.stderr)
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
            try:
                try:
                    import regex as _remod
                except ImportError:
                    import re as _remod
                for p in args.grep_re:
                    rx = _remod.compile(p, _remod.IGNORECASE)
                    patterns_kw.append({"rx": rx})
            except _remod.error as exc:
                print(f"Invalid regex: {exc}", file=sys.stderr)
                sys.exit(1)
        if args.grep:
            for p in args.grep:
                if args.words_only:
                    patterns_kw.append({"rx": _plain_to_words_only_rx(p)})
                else:
                    patterns_kw.append({"plain": p.lower()})
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
            hunks = _session_display_hunks(store, session, patterns_kw, before, after)
            if hunks is not None:
                matched.append((session, hunks))

        if not matched:
            print(f"No sessions match {grep_label}.", file=sys.stderr)
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
                for hunk_idx, hunk in enumerate(hunks):
                    if hunk_idx > 0:
                        print("--")
                    for _is_match, line, spans in hunk:
                        print(_colorize(line, spans, active=use_color))
        sys.exit(0)

    # Branch 2: --id without --grep (primary: transcript / list row)
    if id_val:
        session = _resolve_single_session(stores, id_val, args.all_projects)

        if args.ls:
            print_session_list_row(1, session, use_color=use_color)
            sys.exit(0)

        print(f"Session: {session.path}", file=sys.stderr)
        store = stores[session.source]
        transcript_text = store.transcript(session)

        if args.output:
            with open(args.output, "w", encoding="utf-8") as fh:
                fh.write(transcript_text)
            print(f"Written to: {args.output}", file=sys.stderr)
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
            print("No sessions found.", file=sys.stderr)
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
    main()
