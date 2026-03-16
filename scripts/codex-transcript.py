#!/usr/bin/env python3
"""
codex-transcript.py - Generate a Markdown transcript from a Codex session.

Usage:
    python codex-transcript.py --id <glob>            match session by thread name
    python codex-transcript.py --id <glob>:<N>        pick Nth match when ambiguous
    python codex-transcript.py --id latest            most recently updated session
    python codex-transcript.py --id <session-uuid>    raw session UUID
    python codex-transcript.py --list                 list all sessions
    python codex-transcript.py --id <id> [output]    write transcript to file

CODEX_HOME defaults to ~/.codex if the environment variable is not set.

The transcript includes:
  - User messages with embedded images (inline base64 data URIs)
  - Codex thinking turns (collapsed in <details><summary>Thoughts</summary>)
  - Codex final-answer turns
  - apply_patch diffs attached to the final answer that triggered them
"""

import argparse
import datetime
import fnmatch
import glob
import json
import os
import re
import sys


def _codex_home():
    return os.environ.get(
        "CODEX_HOME", os.path.join(os.path.expanduser("~"), ".codex")
    )


def _find_session_file(session_id):
    """Find the JSONL session file for the given raw session ID."""
    sessions_dir = os.path.join(_codex_home(), "sessions")
    pattern = os.path.join(sessions_dir, "**", f"*{session_id}*.jsonl")
    matches = glob.glob(pattern, recursive=True)
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


def _read_session_index():
    """
    Read session_index.jsonl and return a list of session dicts,
    de-duplicated by id and sorted newest-first by updated_at.
    """
    path = os.path.join(_codex_home(), "session_index.jsonl")
    if not os.path.exists(path):
        return []
    entries = {}  # id → entry with the latest updated_at
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


def find_session(session_id):
    """
    Resolve *session_id* to a JSONL file path.

    Accepts:
      - ``'latest'``: most recently updated session
      - a UUID: direct file lookup (backward-compatible)
      - a title glob (``*`` / ``?``): case-insensitive fnmatch on thread_name
      - ``<glob>:<N>``: pick the Nth (1-based) match when ambiguous

    Returns ``(path, None)`` on unambiguous success.
    Returns ``(None, [entry, ...])`` when multiple matches exist and
    no ``:N`` index was provided.
    """
    entries = _read_session_index()

    # 'latest' — most recently updated entry
    if session_id == "latest":
        if not entries:
            raise FileNotFoundError("session_index.jsonl is empty or not found")
        return _find_session_file(entries[0]["id"]), None

    # Bare UUID-like string (no wildcards, no colon): try direct file lookup first
    if "*" not in session_id and "?" not in session_id and ":" not in session_id:
        try:
            return _find_session_file(session_id), None
        except FileNotFoundError:
            pass  # fall through to title-glob search

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

    if not entries:
        raise FileNotFoundError("session_index.jsonl is empty or not found")

    matches = [
        e for e in entries
        if fnmatch.fnmatch(e.get("thread_name", "").lower(), pattern.lower())
    ]

    if not matches:
        raise FileNotFoundError(f"No session matching '{session_id}'")
    if len(matches) == 1:
        return _find_session_file(matches[0]["id"]), None
    if which is not None:
        if 1 <= which <= len(matches):
            return _find_session_file(matches[which - 1]["id"]), None
        raise ValueError(f"Index {which} out of range (1\u2013{len(matches)})")
    return None, matches


def list_sessions():
    """Print a numbered session list to stdout."""
    entries = _read_session_index()
    if not entries:
        print("No sessions found.", file=sys.stderr)
        return
    for i, e in enumerate(entries, 1):
        dt = e.get("updated_at", "")[:16].replace("T", " ")
        name = e.get("thread_name", "(no name)")
        sid = e.get("id", "")
        print(f"{i:3}. [{dt}] {name:<60}  ({sid[:8]}...)")


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
    Build a regex from a plain search string that ignores punctuation.

    Splits *plain* on non-word characters, then joins the resulting words
    with ``[^\\w]*`` so any punctuation/whitespace between words in the
    target text is accepted.
    """
    words = [re.escape(w) for w in re.split(r"[^\w]+", plain.lower()) if w]
    return re.compile(r"[^\w]*".join(words), re.IGNORECASE)


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
    """Return all context hunks from matching messages in the Codex session at *path*."""
    hunks = []
    try:
        with open(path, encoding="utf-8") as f:
            for raw in f:
                raw = raw.strip()
                if not raw:
                    continue
                rec = json.loads(raw)
                if rec.get("type") != "event_msg":
                    continue
                payload = rec.get("payload", {})
                if payload.get("type") not in ("user_message", "agent_message"):
                    continue
                text = payload.get("message", "")
                hunks.extend(
                    _grep_context(text, plain=plain, rx=rx, before=before, after=after)
                )
    except Exception:
        pass
    return hunks


def _uuid7_ctime(sid):
    """Return creation datetime embedded in a UUID v7 session ID (first 48 bits = ms since epoch)."""
    try:
        hex48 = sid.replace("-", "")[:12]
        ms = int(hex48, 16)
        return datetime.datetime.fromtimestamp(ms / 1000)
    except Exception:
        return None


def grep_sessions(*, plain=None, rx=None, before=0, after=0):
    """Return [(mtime, path, entry_or_None, hunks), ...] for sessions with matching text."""
    sessions_dir = os.path.join(_codex_home(), "sessions")
    if not os.path.isdir(sessions_dir):
        return []
    index_entries = _read_session_index()
    results = []
    for path in glob.glob(os.path.join(sessions_dir, "**", "*.jsonl"), recursive=True):
        hunks = _session_grep(path, plain=plain, rx=rx, before=before, after=after)
        if not hunks:
            continue
        base = os.path.splitext(os.path.basename(path))[0]
        entry = next((e for e in index_entries if e.get("id", "") in base), None)
        results.append((os.path.getmtime(path), path, entry, hunks))
    results.sort(key=lambda x: x[0], reverse=True)
    return results


def get_images_before(lines, idx):
    """
    Return base64 image data URIs from the response_item/user that
    immediately precedes the event_msg/user_message at `idx`.
    """
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


def get_patches_between(lines, start_idx, end_idx):
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


def generate_transcript(path):
    """Parse `path` and return the full Markdown transcript as a string."""
    with open(path, encoding="utf-8") as f:
        lines = [json.loads(l) for l in f if l.strip()]

    # First pass: collect all messages in order with their line indices
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
            images = get_images_before(lines, idx)
            msgs.append({"role": "user", "text": text, "images": images, "idx": idx})
        elif et == "agent_message":
            phase = l["payload"].get("phase", "")
            text = l["payload"].get("message", "")
            msgs.append(
                {"role": "codex", "phase": phase, "text": text, "idx": idx, "patches": []}
            )

    # Second pass: attach patches to each final Codex message.
    # Collect all patches since the last user message (i.e. the whole turn),
    # so commentary interleaved between patches doesn't cause patches to be skipped.
    prev_idx = 0
    for msg in msgs:
        if msg["role"] == "codex" and msg["phase"] != "commentary":
            msg["patches"] = get_patches_between(lines, prev_idx, msg["idx"])
        if msg["role"] == "user":
            prev_idx = msg["idx"]

    # Render
    out = []
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

        else:  # codex turn (commentary and/or final answer share one ## Codex heading)
            # Collect all consecutive commentary items for this turn
            commentary_items = []
            while i < len(msgs) and msgs[i]["role"] == "codex" and msgs[i]["phase"] == "commentary":
                commentary_items.append(msgs[i]["text"])
                i += 1

            # Peek at the next message: is it the final answer for this turn?
            final_msg = None
            if i < len(msgs) and msgs[i]["role"] == "codex" and msgs[i]["phase"] != "commentary":
                final_msg = msgs[i]
                i += 1

            # Build a single ## Codex block for the whole turn
            block = "## Codex"
            if commentary_items:
                separator = "\n\n>\n\n"
                inner = separator.join(commentary_items)
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


if __name__ == "__main__":
    ap = argparse.ArgumentParser(
        description="Generate a Markdown transcript from a Codex session.",
        epilog=(
            "Examples:\n"
            "  %(prog)s --list\n"
            "  %(prog)s --id latest out.md\n"
            "  %(prog)s --id 'beam overlap'\n"
            "  %(prog)s --id 'beam*:2' out.md\n"
            "  %(prog)s --id 019cd051-c2ac-72e0-ab6f-3e620157607a\n"
            "\n"
            "Grep output header format:\n"
            "  [creation]-[modification]  title (uuid-prefix)\n"
            "  Creation time: decoded from the UUID v7 session ID (first 48 bits = ms since epoch).\n"
            "  Modification time: updated_at from session_index.jsonl."
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    ap.add_argument(
        "--id",
        metavar="GLOB_OR_UUID",
        help=(
            "Select session by thread-name glob, UUID, or 'latest'. "
            "Append :<N> to pick the Nth result when ambiguous."
        ),
    )
    ap.add_argument(
        "--list",
        action="store_true",
        help="List all sessions and exit.",
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
            "With --grep: strip punctuation from both the search string and each "
            "line before matching, so backticks, dashes, etc. are ignored."
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
        "output",
        nargs="?",
        help="Output file path (default: stdout).",
    )
    args = ap.parse_args()

    if args.list:
        list_sessions()
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
            results = grep_sessions(rx=rx, before=before, after=after)
            label = f"grep-re '{args.grep_re}'"
        else:
            if args.ignore_punct:
                _rx = _plain_to_ignorepunct_rx(args.grep)
                _kw = {"rx": _rx}
            else:
                _kw = {"plain": args.grep.lower()}
            results = grep_sessions(before=before, after=after, **_kw)
            label = f"grep '{args.grep}'"
        if not results:
            print(f"No sessions match {label}.", file=sys.stderr)
        elif args.ls:
            for i, (mtime, path, entry, _hunks) in enumerate(results, 1):
                if entry:
                    dt = entry.get("updated_at", "")[:16].replace("T", " ")
                    name = entry.get("thread_name", "(no name)")
                    sid = entry.get("id", "")
                else:
                    dt = datetime.datetime.fromtimestamp(mtime).strftime("%Y-%m-%d %H:%M")
                    name = os.path.splitext(os.path.basename(path))[0]
                    sid = name
                print(f"{i:3}. [{dt}] {name:<60}  ({sid[:8]}...)")
        else:
            for session_idx, (mtime, path, entry, hunks) in enumerate(results):
                if session_idx > 0:
                    print()
                if entry:
                    mtime_str = entry.get("updated_at", "")[:16].replace("T", " ")
                    name = entry.get("thread_name", "(no name)")
                    sid = entry.get("id", "")
                else:
                    mtime_str = datetime.datetime.fromtimestamp(mtime).strftime("%Y-%m-%d %H:%M")
                    name = os.path.splitext(os.path.basename(path))[0]
                    sid = name
                ctime_dt = _uuid7_ctime(sid) if entry else None
                ctime_str = ctime_dt.strftime("%Y-%m-%d %H:%M") if ctime_dt else mtime_str
                print(_ansi(f"[{ctime_str}]-[{mtime_str}]", _C_DATE, active=use_color))
                print(_ansi(f"{name} ({sid[:8]})", _C_TITLE, active=use_color))
                for hunk_idx, hunk in enumerate(hunks):
                    if hunk_idx > 0:
                        print("--")
                    for is_match, line, spans in hunk:
                        print(_colorize(line, spans, active=use_color))
        sys.exit(0)

    if not args.id:
        ap.print_help(sys.stderr)
        sys.exit(1)

    try:
        session_path, ambiguous = find_session(args.id)
    except (FileNotFoundError, ValueError) as exc:
        print(f"Error: {exc}", file=sys.stderr)
        sys.exit(1)

    if ambiguous:
        print(
            f"Ambiguous: {len(ambiguous)} sessions match '{args.id}':",
            file=sys.stderr,
        )
        for i, e in enumerate(ambiguous, 1):
            name = e.get("thread_name", "(no name)")
            sid = e.get("id", "")
            print(f"  {i:3}. {name:<60}  ({sid[:8]}...)", file=sys.stderr)
        print(f"\nUse --id '{args.id}:<N>' to select one.", file=sys.stderr)
        sys.exit(1)

    print(f"Session: {session_path}", file=sys.stderr)
    transcript = generate_transcript(session_path)

    if args.output:
        with open(args.output, "w", encoding="utf-8") as f:
            f.write(transcript)
        print(f"Written to: {args.output}", file=sys.stderr)
    else:
        sys.stdout.reconfigure(encoding="utf-8")
        print(transcript)
