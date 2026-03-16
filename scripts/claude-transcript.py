#!/usr/bin/env python3
"""
claude-transcript.py - Generate a Markdown transcript from a Claude Code session.

Usage:
    python claude-transcript.py --id <glob>           match session by title glob
    python claude-transcript.py --id <glob>:<N>       pick Nth match when ambiguous
    python claude-transcript.py --id latest           most recently modified session
    python claude-transcript.py --id <uuid>           raw session UUID
    python claude-transcript.py --list                list sessions for project
    python claude-transcript.py --id <id> [output]   write transcript to file

CLAUDE_CONFIG_DIR defaults to ~/.claude.
--project defaults to the current working directory.

The transcript includes:
  - User messages (system-injected tags stripped)
  - Claude thinking turns (collapsed in <details>)
  - Claude text responses
  - File edits/writes (collapsed in <details>)
  - Bash commands run (collapsed in <details>)
"""

import argparse
import datetime
import fnmatch
import glob as glob_mod
import json
import os
import re
import sys

# XML-like tags injected by Claude Code into user message text blocks.
_SYSTEM_TAG_RE = re.compile(
    r"<(?:ide_opened_file|ide_selection|system[\-_]reminder|system|env|"
    r"claude_background_info|user[\-_]prompt[\-_]submit[\-_]hook|"
    r"command[\-_]name|antml:[a-z_]+)[^>]*>.*?</[^>]+>",
    re.DOTALL | re.IGNORECASE,
)


# ── Path helpers ─────────────────────────────────────────────────────────────

def _claude_dir():
    cfg = os.environ.get("CLAUDE_CONFIG_DIR")
    if cfg:
        return cfg
    return os.path.join(os.path.expanduser("~"), ".claude")


def _encode_project_path(path):
    """Encode a filesystem path to the project folder key Claude Code uses."""
    path = path.replace("\\", "/")
    return re.sub(r"[^a-zA-Z0-9]", "-", path)


def _project_dir(project_path=None):
    if project_path is None:
        project_path = os.getcwd()
    key = _encode_project_path(project_path)
    return os.path.join(_claude_dir(), "projects", key)


def _all_project_dirs():
    """Return all project directory paths under the Claude config projects folder."""
    base = os.path.join(_claude_dir(), "projects")
    if not os.path.isdir(base):
        return []
    return sorted(
        os.path.join(base, d)
        for d in os.listdir(base)
        if os.path.isdir(os.path.join(base, d))
    )


def _project_label(proj_dir):
    """Extract a short human-readable label from an encoded project directory name."""
    name = os.path.basename(proj_dir)
    parts = [p for p in re.split(r"-+", name) if p]
    return parts[-1] if parts else name


# ── Session lookup ────────────────────────────────────────────────────────────

def _session_files(proj_dir):
    """Return [(mtime, path), ...] for all session JSONL files, newest first."""
    paths = glob_mod.glob(os.path.join(proj_dir, "*.jsonl"))
    result = [(os.path.getmtime(p), p) for p in paths]
    result.sort(reverse=True)
    return result


def _strip_system(text):
    """Remove system-injected XML blocks from a text string."""
    return _SYSTEM_TAG_RE.sub("", text).strip()


def _session_title(path):
    """
    Derive a display title from the first real user text in the session
    (first 80 chars after stripping system-injected content).
    """
    try:
        with open(path, encoding="utf-8") as f:
            for raw in f:
                raw = raw.strip()
                if not raw:
                    continue
                rec = json.loads(raw)
                if rec.get("type") != "user" or rec.get("isSidechain"):
                    continue
                for block in rec.get("message", {}).get("content", []):
                    if block.get("type") != "text":
                        continue
                    text = _strip_system(block.get("text", ""))
                    if text:
                        return text[:80]
    except Exception:
        pass
    return "(no title)"


def find_session(session_id, proj_dir):
    """
    Resolve *session_id* to a JSONL path.

    Accepts:
      - ``'latest'``: most recently modified session
      - a UUID: exact filename (without ``.jsonl``) match
      - a title glob (``*`` / ``?``): case-insensitive fnmatch on derived title
      - ``<glob>:<N>``: pick the Nth (1-based) match when ambiguous

    Returns ``(path, None)`` on unambiguous success.
    Returns ``(None, [(title, path), ...])`` when multiple matches exist and
    no ``:N`` index was provided.
    """
    files = _session_files(proj_dir)
    if not files:
        raise FileNotFoundError(f"No sessions found in:\n  {proj_dir}")

    if session_id == "latest":
        return files[0][1], None

    # Exact UUID match (filename without extension)
    for _, path in files:
        if os.path.splitext(os.path.basename(path))[0] == session_id:
            return path, None

    # UUID prefix match — allows the 8-char prefix shown in grep output
    if re.match(r'^[0-9a-f-]+$', session_id, re.IGNORECASE):
        prefix_matches = [
            path for _, path in files
            if os.path.splitext(os.path.basename(path))[0].startswith(session_id)
        ]
        if len(prefix_matches) == 1:
            return prefix_matches[0], None
        elif len(prefix_matches) > 1:
            return None, [(_session_title(p), p) for p in prefix_matches]

    # Title glob with optional :N suffix
    which = None
    pattern = session_id
    if ":" in session_id:
        head, tail = session_id.rsplit(":", 1)
        if tail.isdigit():
            pattern, which = head, int(tail)

    # Bare words implicitly get wildcard wrapping
    if "*" not in pattern and "?" not in pattern:
        pattern = f"*{pattern}*"

    matches = []
    for _, path in files:
        title = _session_title(path)
        if fnmatch.fnmatch(title.lower(), pattern.lower()):
            matches.append((title, path))

    if not matches:
        raise FileNotFoundError(
            f"No session matching '{session_id}'\nSearched: {proj_dir}"
        )
    if len(matches) == 1:
        return matches[0][1], None
    if which is not None:
        if 1 <= which <= len(matches):
            return matches[which - 1][1], None
        raise ValueError(f"Index {which} out of range (1\u2013{len(matches)})")
    return None, matches


def _session_ctime(path):
    """Return creation datetime from the first JSONL record with a *timestamp* field."""
    try:
        with open(path, encoding="utf-8") as f:
            for raw in f:
                raw = raw.strip()
                if not raw:
                    continue
                rec = json.loads(raw)
                ts = rec.get("timestamp")
                if ts:
                    ts_clean = ts.rstrip("Z").split(".")[0]  # "2026-03-14T02:19:59"
                    return datetime.datetime.strptime(ts_clean, "%Y-%m-%dT%H:%M:%S")
    except Exception:
        pass
    return None


def list_sessions(proj_dir):
    """Print a numbered session list to stdout."""
    files = _session_files(proj_dir)
    if not files:
        print("No sessions found.", file=sys.stderr)
        return
    for i, (mtime, path) in enumerate(files, 1):
        dt = datetime.datetime.fromtimestamp(mtime).strftime("%Y-%m-%d %H:%M")
        title = _session_title(path)
        sid = os.path.splitext(os.path.basename(path))[0]
        print(f"{i:3}. [{dt}] {title:<60}  ({sid[:8]}...)")


try:
    import colorama as _cm
    if hasattr(_cm, "just_fix_windows_console"):
        _cm.just_fix_windows_console()
    _C_RESET   = _cm.Style.RESET_ALL
    _C_MATCH   = _cm.Style.BRIGHT + _cm.Fore.RED
    _C_DATE    = _cm.Fore.CYAN
    _C_PROJECT = _cm.Fore.YELLOW
    _C_TITLE   = _cm.Style.BRIGHT
except ImportError:
    _C_RESET   = "\033[0m"
    _C_MATCH   = "\033[1;31m"
    _C_DATE    = "\033[36m"
    _C_PROJECT = "\033[33m"
    _C_TITLE   = "\033[1m"


def _ansi(s, color, *, active):
    """Wrap *s* in *color* ANSI escape when *active*, resetting after."""
    return f"{color}{s}{_C_RESET}" if active else s


def _plain_to_ignorepunct_rx(plain):
    """
    Build a regex from a plain search string that ignores punctuation and tags.

    Splits *plain* on non-word characters, then joins the resulting words
    with ``(?:<[^>]+>|[^\\w])*`` so any punctuation, whitespace, or
    HTML/XML tags between words in the target text are accepted.
    """
    words = [re.escape(w) for w in re.split(r"[^\w]+", plain.lower()) if w]
    return re.compile(r"(?:<[^>]+>|[^\w])*".join(words), re.IGNORECASE)


def _colorize(line, spans, *, active):
    """Highlight match *spans* within *line* using ANSI codes when *active*."""
    if not active or not spans:
        return line
    out, prev = [], 0
    for start, end in sorted(spans):
        out.append(line[prev:start])
        out.append(_C_MATCH + line[start:end] + _C_RESET)
        prev = end
    out.append(line[prev:])
    return "".join(out)


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


def _session_grep(path, *, plain=None, rx=None, before=0, after=0):
    """Return all context hunks from matching messages in the session at *path*."""
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
                            texts.append(_strip_system(block.get("text", "")))
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
                        elif btype == "tool_use" and block.get("name") == "TodoWrite":
                            todos = block.get("input", {}).get("todos", [])
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
                for text in texts:
                    hunks.extend(
                        _grep_context(text, plain=plain, rx=rx, before=before, after=after)
                    )
    except Exception:
        pass
    return hunks


def grep_sessions(proj_dir, *, plain=None, rx=None, before=0, after=0):
    """Return [(mtime, path, hunks), ...] for sessions with matching text."""
    results = []
    for mtime, path in _session_files(proj_dir):
        hunks = _session_grep(path, plain=plain, rx=rx, before=before, after=after)
        if hunks:
            results.append((mtime, path, hunks))
    return results


# ── Transcript generation ─────────────────────────────────────────────────────

def _user_text(content):
    """
    Extract clean human-written text from user message content blocks.
    Strips system-injected XML tags; embeds images as inline data URIs.
    """
    parts = []
    for block in content:
        btype = block.get("type")
        if btype == "text":
            text = _strip_system(block.get("text", ""))
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


def generate_transcript(path):
    """Parse *path* and return the full Markdown transcript as a string."""
    with open(path, encoding="utf-8") as f:
        records = [json.loads(l) for l in f if l.strip()]

    title = _session_title(path)
    sid = os.path.splitext(os.path.basename(path))[0]

    out = [f"# {title}\n\n*Session: {sid}*\n"]

    last_user_text = None  # deduplicate retried user messages
    for rec in records:
        if rec.get("isSidechain"):
            continue

        rtype = rec.get("type")

        # ── User turn ──────────────────────────────────────────────────────
        if rtype == "user":
            content = rec.get("message", {}).get("content", [])
            # Skip turns where content is not a list (e.g. compacted summaries)
            if not isinstance(content, list):
                continue
            # Skip turns that are only tool_result blocks (no human text)
            if all(isinstance(b, dict) and b.get("type") == "tool_result" for b in content):
                continue
            text = _user_text(content)
            if text and text != last_user_text:
                last_user_text = text
                out.append(f"## User\n\n{text}\n")

        # ── Assistant turn ─────────────────────────────────────────────────
        elif rtype == "assistant":
            msg = rec.get("message", {})
            # Skip synthetic boilerplate messages
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
                # Render every TodoWrite in this turn so the progression is visible
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


# ── Entry point ───────────────────────────────────────────────────────────────

if __name__ == "__main__":
    ap = argparse.ArgumentParser(
        description="Generate a Markdown transcript from a Claude Code session.",
        epilog=(
            "Examples:\n"
            "  %(prog)s --list\n"
            "  %(prog)s --id latest out.md\n"
            "  %(prog)s --id 'codex session'\n"
            "  %(prog)s --id 'codex*:2' out.md\n"
            "  %(prog)s --id f4b19167-d8a7-4a10-81c5-d03920efd017\n"
            "\n"
            "Grep output header format:\n"
            "  [creation]-[modification] [project]  (uuid-prefix) title\n"
            "  Creation time: timestamp of the first record in the session JSONL.\n"
            "  Modification time: file mtime.\n"
            "  [project] label appears only with --all-projects."
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    ap.add_argument(
        "--id",
        metavar="GLOB_OR_UUID",
        help=(
            "Select session by title glob, UUID, or 'latest'. "
            "Append :<N> to pick the Nth result when ambiguous."
        ),
    )
    ap.add_argument(
        "--list",
        action="store_true",
        help="List sessions for the project and exit.",
    )
    grep_group = ap.add_mutually_exclusive_group()
    grep_group.add_argument(
        "--grep",
        metavar="TEXT",
        help="List sessions containing TEXT (plain case-insensitive substring) and exit.",
    )
    grep_group.add_argument(
        "--grep-re",
        metavar="PATTERN",
        dest="grep_re",
        help=(
            "List sessions matching PATTERN (case-insensitive regex) and exit.  "
            "Uses 'regex' module if installed (pip install regex), otherwise 're'."
        ),
    )
    ap.add_argument(
        "--ls",
        action="store_true",
        help="With --grep/--grep-re: show a numbered session list instead of matching lines.",
    )
    ap.add_argument(
        "--ignore-punctuation",
        action="store_true",
        dest="ignore_punct",
        help=(
            "With --grep: ignore punctuation and HTML tags when matching, so "
            "backticks, dashes, HTML tags, etc. between words are skipped."
        ),
    )
    ap.add_argument(
        "-A", "--after-context",
        metavar="N", type=int, default=0, dest="after_context",
        help="With --grep/--grep-re: print N lines of context after each match.",
    )
    ap.add_argument(
        "-B", "--before-context",
        metavar="N", type=int, default=0, dest="before_context",
        help="With --grep/--grep-re: print N lines of context before each match.",
    )
    ap.add_argument(
        "-C", "--context",
        metavar="N", type=int, default=None,
        help="With --grep/--grep-re: print N lines of context before and after each match.",
    )
    ap.add_argument(
        "--color", "--colour",
        metavar="WHEN", default="auto", choices=["always", "auto", "never"],
        help="Colorize matches: always, auto (tty; default), or never.",
    )
    ap.add_argument(
        "--project",
        metavar="PATH",
        help="Project directory to search (default: current working directory).",
    )
    ap.add_argument(
        "--all-projects",
        action="store_true",
        dest="all_projects",
        help="Search all projects (with --grep/--grep-re/--list) instead of just the current one.",
    )
    ap.add_argument(
        "output",
        nargs="?",
        help="Output file path (default: stdout).",
    )
    args = ap.parse_args()

    if args.all_projects:
        proj_dirs = _all_project_dirs()
        proj_dir = None
    else:
        proj_dir = _project_dir(args.project)
        if not os.path.isdir(proj_dir):
            print(
                f"No Claude Code project directory found:\n  {proj_dir}",
                file=sys.stderr,
            )
            sys.exit(1)
        proj_dirs = [proj_dir]

    if args.list:
        if args.all_projects:
            all_files = []
            for pd in proj_dirs:
                for mtime, path in _session_files(pd):
                    all_files.append((mtime, path, pd))
            all_files.sort(reverse=True)
            for i, (mtime, path, pd) in enumerate(all_files, 1):
                dt = datetime.datetime.fromtimestamp(mtime).strftime("%Y-%m-%d %H:%M")
                title = _session_title(path)
                sid = os.path.splitext(os.path.basename(path))[0]
                print(f"{i:3}. [{dt}] {title:<60}  ({sid[:8]}...) [{_project_label(pd)}]")
        else:
            list_sessions(proj_dir)
        sys.exit(0)

    if args.grep or args.grep_re:
        before = args.before_context
        after = args.after_context
        if args.context is not None:
            before = after = args.context
        use_color = (
            args.color == "always"
            or (args.color == "auto" and sys.stdout.isatty())
        )
        if args.grep_re:
            try:
                import regex as _remod
            except ImportError:
                import re as _remod
            try:
                rx = _remod.compile(args.grep_re, _remod.IGNORECASE)
            except _remod.error as exc:
                print(f"Invalid regex: {exc}", file=sys.stderr)
                sys.exit(1)
            all_results = []
            for pd in proj_dirs:
                for item in grep_sessions(pd, rx=rx, before=before, after=after):
                    all_results.append((pd, *item))
            label = f"grep-re '{args.grep_re}'"
        else:
            if args.ignore_punct:
                _rx = _plain_to_ignorepunct_rx(args.grep)
                _kw = {"rx": _rx}
            else:
                _kw = {"plain": args.grep.lower()}
            all_results = []
            for pd in proj_dirs:
                for item in grep_sessions(pd, before=before, after=after, **_kw):
                    all_results.append((pd, *item))
            label = f"grep '{args.grep}'"
        all_results.sort(key=lambda x: x[1], reverse=True)
        if not all_results:
            print(f"No sessions match {label}.", file=sys.stderr)
        elif args.ls:
            for i, (pd, mtime, path, _hunks) in enumerate(all_results, 1):
                dt = datetime.datetime.fromtimestamp(mtime).strftime("%Y-%m-%d %H:%M")
                title = _session_title(path)
                sid = os.path.splitext(os.path.basename(path))[0]
                plabel = f" [{_project_label(pd)}]" if args.all_projects else ""
                print(f"{i:3}. [{dt}] {title:<60}  ({sid[:8]}...){plabel}")
        else:
            for session_idx, (pd, mtime, path, hunks) in enumerate(all_results):
                if session_idx > 0:
                    print()
                mtime_str = datetime.datetime.fromtimestamp(mtime).strftime("%Y-%m-%d %H:%M")
                title = _session_title(path)
                sid = os.path.splitext(os.path.basename(path))[0]
                ctime_dt = _session_ctime(path)
                ctime_str = ctime_dt.strftime("%Y-%m-%d %H:%M") if ctime_dt else mtime_str
                plabel = f" [{_project_label(pd)}]" if args.all_projects else ""
                date_part = _ansi(f"[{ctime_str}]-[{mtime_str}]", _C_DATE, active=use_color)
                proj_part = _ansi(plabel, _C_PROJECT, active=use_color) if plabel else ""
                print(f"{date_part}{proj_part}")
                print(_ansi(f"({sid[:8]}) {title}", _C_TITLE, active=use_color))
                for hunk_idx, hunk in enumerate(hunks):
                    if hunk_idx > 0:
                        print("--")
                    for is_match, line, spans in hunk:
                        print(_colorize(line, spans, active=use_color))
        sys.exit(0)

    if not args.id:
        ap.print_help(sys.stderr)
        sys.exit(1)

    if proj_dir is None:
        print("--all-projects cannot be used with --id", file=sys.stderr)
        sys.exit(1)

    try:
        session_path, ambiguous = find_session(args.id, proj_dir)
    except (FileNotFoundError, ValueError) as exc:
        print(f"Error: {exc}", file=sys.stderr)
        sys.exit(1)

    if ambiguous:
        print(
            f"Ambiguous: {len(ambiguous)} sessions match '{args.id}':",
            file=sys.stderr,
        )
        for i, (title, _path) in enumerate(ambiguous, 1):
            sid = os.path.splitext(os.path.basename(_path))[0]
            print(f"  {i:3}. {title:<60}  ({sid[:8]}...)", file=sys.stderr)
        print(f"\nUse --id '{args.id}:<N>' to select one.", file=sys.stderr)
        sys.exit(1)

    print(f"Session: {session_path}", file=sys.stderr)
    transcript = generate_transcript(session_path)

    if args.output:
        with open(args.output, "w", encoding="utf-8") as fh:
            fh.write(transcript)
        print(f"Written to: {args.output}", file=sys.stderr)
    else:
        sys.stdout.reconfigure(encoding="utf-8")
        print(transcript)
