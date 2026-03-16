#!/usr/bin/env python3
"""
codex-transcript.py - Generate a Markdown transcript from a Codex session.

Usage:
    python codex-transcript.py <session-id> [output-file]

If output-file is omitted, the transcript is written to stdout.
CODEX_HOME defaults to ~/.codex if the environment variable is not set.

The transcript includes:
  - User messages with embedded images (inline base64 data URIs)
  - Codex commentary turns (blockquoted)
  - Codex final-answer turns
  - apply_patch diffs attached to the final answer that triggered them
"""

import glob
import json
import os
import re
import sys


def find_session_file(session_id):
    """Find the JSONL session file for the given session ID."""
    codex_home = os.environ.get(
        "CODEX_HOME", os.path.join(os.path.expanduser("~"), ".codex")
    )
    sessions_dir = os.path.join(codex_home, "sessions")
    pattern = os.path.join(sessions_dir, "**", f"*{session_id}*.jsonl")
    matches = glob.glob(pattern, recursive=True)
    if not matches:
        raise FileNotFoundError(
            f"No session file found for ID: {session_id}\n"
            f"Searched: {sessions_dir}"
        )
    if len(matches) > 1:
        print(f"Warning: multiple matches, using first:", file=sys.stderr)
        for m in matches:
            print(f"  {m}", file=sys.stderr)
    return matches[0]


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
    if len(sys.argv) < 2:
        print(f"Usage: {sys.argv[0]} <session-id> [output-file]", file=sys.stderr)
        sys.exit(1)

    session_id = sys.argv[1]
    outfile = sys.argv[2] if len(sys.argv) > 2 else None

    session_path = find_session_file(session_id)
    print(f"Session: {session_path}", file=sys.stderr)

    transcript = generate_transcript(session_path)

    if outfile:
        with open(outfile, "w", encoding="utf-8") as f:
            f.write(transcript)
        print(f"Written to: {outfile}", file=sys.stderr)
    else:
        sys.stdout.reconfigure(encoding="utf-8")
        print(transcript)
