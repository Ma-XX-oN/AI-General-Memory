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


def _session_grep(path, *, plain=None, rx=None):
    """Return True if any message text in the session at *path* matches the search term."""
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
                for text in texts:
                    if plain is not None and plain in text.lower():
                        return True
                    if rx is not None and rx.search(text):
                        return True
    except Exception:
        pass
    return False


def grep_sessions(proj_dir, *, plain=None, rx=None):
    """Return [(mtime, path), ...] for sessions whose text matches the search term."""
    return [
        (mtime, path)
        for mtime, path in _session_files(proj_dir)
        if _session_grep(path, plain=plain, rx=rx)
    ]


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

            if not thinking and not texts and not file_ops and not bash_ops:
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
            "  %(prog)s --id f4b19167-d8a7-4a10-81c5-d03920efd017"
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
            "List sessions matching PATTERN (case-insensitive regex via 'regex' module) "
            "and exit.  Install with: pip install regex"
        ),
    )
    ap.add_argument(
        "--project",
        metavar="PATH",
        help="Project directory to search (default: current working directory).",
    )
    ap.add_argument(
        "output",
        nargs="?",
        help="Output file path (default: stdout).",
    )
    args = ap.parse_args()

    proj_dir = _project_dir(args.project)
    if not os.path.isdir(proj_dir):
        print(
            f"No Claude Code project directory found:\n  {proj_dir}",
            file=sys.stderr,
        )
        sys.exit(1)

    if args.list:
        list_sessions(proj_dir)
        sys.exit(0)

    if args.grep or args.grep_re:
        if args.grep_re:
            try:
                import regex as _regex
            except ImportError:
                print(
                    "The 'regex' module is required for --grep-re.  Install it with:\n"
                    "  pip install regex",
                    file=sys.stderr,
                )
                sys.exit(1)
            try:
                rx = _regex.compile(args.grep_re, _regex.IGNORECASE)
            except _regex.error as exc:
                print(f"Invalid regex: {exc}", file=sys.stderr)
                sys.exit(1)
            results = grep_sessions(proj_dir, rx=rx)
            label = f"grep-re '{args.grep_re}'"
        else:
            results = grep_sessions(proj_dir, plain=args.grep.lower())
            label = f"grep '{args.grep}'"
        if not results:
            print(f"No sessions match {label}.", file=sys.stderr)
        else:
            for i, (mtime, path) in enumerate(results, 1):
                dt = datetime.datetime.fromtimestamp(mtime).strftime("%Y-%m-%d %H:%M")
                title = _session_title(path)
                sid = os.path.splitext(os.path.basename(path))[0]
                print(f"{i:3}. [{dt}] {title:<60}  ({sid[:8]}...)")
        sys.exit(0)

    if not args.id:
        ap.print_help(sys.stderr)
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
