# AI-transcript.py — Architecture Reference

## Two-repo layout

| Asset | Location |
| --- | --- |
| Script | `~/.codex/scripts/AI-transcript.py` |
| Design plan | `~/.claude/scripts/AI-transcript-plan.md` |
| Test suite | `~/.claude/scripts/AI-transcript-tests.sh` |

Commits go to both repos as needed.  After pushing either, `git pull` in the
other to keep them in sync (per global CLAUDE.md rule).

## Key file sections (approximate line numbers)

Line numbers drift as the file grows; use these as starting offsets for
parallel `Read` calls, not as exact references.

| Section | ~Line |
| --- | --- |
| `_grep_context` | 165 |
| `_grep_context_tagged` | 218 |
| `SessionStore` ABC + `grep()` signature | 280 |
| `_cl_session_grep` | 500 |
| `ClaudeSessionStore.grep()` | 720 |
| `_cx_session_grep` | 1050 |
| `CodexSessionStore.grep()` | 1320 |
| `_build_hunk_prefix` | 1680 |
| `_session_display_hunks` | 1710 |
| Argparse (`-A`/`-B`/`-C`/`-x`) | 1960 |
| `main()` context-resolution block | 2105 |
| `main()` grep display loop | 2175 |

## Hunk data structure (post-#17)

```python
# A session's grep result is:
list[                            # one entry per hunk
  list[                          # one entry per line in the hunk
    tuple[
      bool,       # is_match — True if this line contains a match
      str,        # line_text
      list,       # spans: [(start, end), ...] of match offsets
      int,        # rec_no — 1-based JSONL record number for THIS line
      str | None  # ts_str — raw timestamp string (or None) for THIS line
    ]
  ]
]
```

Before #17, `rec_no` and `ts_str` were on the outer `(rec_no, ts_str,
hunk_lines)` tuple — one per hunk.  They are now per-line so `-n`/`-d`
work correctly in cross-record hunks.

## Adding a new parameter to the grep pipeline

When a new parameter needs to flow through the grep call chain, touch these
sites in this order (all in `AI-transcript.py`):

1. `_cl_session_grep(path, *, ..., new_param=default)` — Claude grep fn
2. `_cx_session_grep(path, *, ..., new_param=default)` — Codex grep fn
3. `SessionStore.grep(self, session, *, ..., new_param=default)` — ABC
4. `ClaudeSessionStore.grep(...)` — passes to `_cl_session_grep`
5. `CodexSessionStore.grep(...)` — passes to `_cx_session_grep`
6. `_session_display_hunks(..., new_param=default)` — passes to `store.grep()`
7. `argparse` block — add flag if user-facing
8. `main()` call to `_session_display_hunks` — pass `args.new_param`

## Cross-record context (`-x` / `--cross-record`)

When `cross_record=True`, both grep functions skip the per-record
`_grep_context` calls and instead:

1. Flatten all searchable lines from all records into a
   `list[(line_text, rec_no, ts_str)]` tagged sequence.
2. Call `_grep_context_tagged(tagged, ...)` which returns hunks whose lines
   each carry their own `rec_no`/`ts_str`.

`first_only=True` always uses the per-record path regardless of
`cross_record` (the AND membership check needs no context).
