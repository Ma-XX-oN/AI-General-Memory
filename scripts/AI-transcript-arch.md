# AI-transcript.py — Architecture Reference

## Two-repo layout

| Asset | Location |
| --- | --- |
| Script | `~/.codex/scripts/AI-transcript.py` |
| Design plan | `~/.claude/scripts/AI-transcript-plan.md` |
| Test suite | `~/.claude/scripts/AI-transcript-tests.sh` |

Commits go to both repos as needed.  After pushing either, `git pull` in the
other to keep them in sync (per global CLAUDE.md rule).

## Key file sections

Find each section by grepping for the function or class name.  Line numbers
are intentionally omitted — use `grep "def SECTION_NAME"` instead.

| Section | Grep for |
| --- | --- |
| `_grep_context` | `def _grep_context(` |
| `_grep_context_tagged` | `def _grep_context_tagged(` |
| `SessionStore` ABC | `class SessionStore(` |
| `_md_quote` | `def _md_quote(` |
| `_md_code_fence` | `def _md_code_fence(` |
| `_cl_session_grep` | `def _cl_session_grep(` |
| `_cl_user_text` | `def _cl_user_text(` |
| `_cl_group_turns` | `def _cl_group_turns(` |
| `_cl_render_thought_item` | `def _cl_render_thought_item(` |
| `_cl_render_inline_item` | `def _cl_render_inline_item(` |
| `ClaudeSessionStore` | `class ClaudeSessionStore(` |
| `ClaudeSessionStore.transcript()` | `def transcript(` (first occurrence) |
| `ClaudeSessionStore.grep()` | `def grep(` (inside `ClaudeSessionStore`) |
| `_format_thought_items` (Codex) | `def _format_thought_items(` |
| `_cx_session_grep` | `def _cx_session_grep(` |
| `CodexSessionStore` | `class CodexSessionStore(` |
| `CodexSessionStore.transcript()` | `def transcript(` (third occurrence) |
| `_build_hunk_prefix` | `def _build_hunk_prefix(` |
| `_session_display_hunks` | `def _session_display_hunks(` |
| `main()` | `def main(` |

## Claude JSONL record schema

Each session is a `.jsonl` file; every line is one JSON record.

**Top-level fields on every record:**

```
type        "user" | "assistant" | "queue-operation" | ...
timestamp   ISO-8601 string or null
isSidechain bool — skip ALL records where truthy (injected context)
message     object (see below)
```

**`message` sub-fields:**

```
role    mirrors type ("user" or "assistant")
model   string; skip assistant records where model == "<synthetic>"
content list of content blocks (see below)
```

**Content block types by record role:**

*User records:*

```
{ type: "text",   text: "..." }               real human input
{ type: "image",  source: {type, data/url} }  screenshot/image
{ type: "tool_result",
    tool_use_id: "toolu_...",
    content: str | [{type:"text", text:"..."}] }   tool output
```

*Assistant records:*

```
{ type: "thinking", thinking: "..." }         extended thinking
{ type: "text",     text: "..." }             AI text output to user
{ type: "tool_use",
    id:    "toolu_...",
    name:  "Bash" | "Read" | "Edit" | ...,
    input: {…} }                              tool invocation
```

**Interleaving pattern within a single AI turn:**

```
assistant  →  tool_use block(s)
user       →  tool_result block(s)   ← matching tool_use_id values
assistant  →  tool_use or text
…
user       →  real user message (non-tool-result content)  ← ends the turn
```

Records to skip unconditionally: `isSidechain=true`, `model="<synthetic>"`,
`type="queue-operation"`.

## Transcript pipeline (Claude-specific)

### `_md_code_fence(text, lang="")`

Wraps `text` in a Markdown code fence using enough backticks to prevent
premature closing.  Scans `text` for the longest run of consecutive backticks
and uses `max(3, that_run + 1)` backticks for both the opening and closing
fence lines.

### `_cl_group_turns(rec_nos, records)`

Groups the flat record list into conversational turns.  Returns
`(items, plan_ids)` where `items` is a list of tuples:

```python
('user', rec_no, ts, rec)
    # A real user message, an AskUserQuestion answer, or an ExitPlanMode
    # plan-approval.  Both kinds of answer are identified by pre-scanning
    # for break_ids = ask_ids | plan_ids.

('assistant_turn', display_rec_no, display_ts, sub_records, tr_map)
    # All consecutive assistant records between real user messages.
    # sub_records = [(rec_no, ts, rec), ...]
    # tr_map      = {tool_use_id: result_text}   absorbed tool-result records
    # AskUserQuestion and ExitPlanMode tool-result records BREAK the turn
    # (not absorbed into tr_map).

('notice', rec_no, ts, text)
    # Synthetic assistant record (model="<synthetic>"), e.g. usage-limit
    # notification.  Collected as pending_notices during the inner turn
    # loop and appended to result AFTER the enclosing assistant_turn, so
    # notices appear after their turn in the output.
```

`plan_ids` is the set of ExitPlanMode tool-call IDs.  Callers use it to
distinguish plan-approval `user` records from regular user messages.

### Inline vs. thought-group classification

Inside `ClaudeSessionStore.transcript()` each `sub_record` in an
`assistant_turn` is classified as:

- **inline** — shown outside `<details>`, at the same level as user messages:
  - has `AskUserQuestion` or `EnterPlanMode`/`ExitPlanMode` tool_use, OR
  - has text content AND no tool_use (pure text-to-user record)
- **thought-group** — everything else: thinking-only, tool_use-only,
  text+tool_use narration, thinking+text+tool_use, etc.

**Rule:** consecutive thought-group records merge into ONE
`<details>Thoughts</details>` block.  An inline record flushes the current
thought group, appears inline, then a new thought group may start.

### `_cl_render_thought_item(rec, tr_map)`

Returns **raw** (unblockquoted) markdown for one thought-group sub-record.
The caller blockquotes the entire outer `<details>Thoughts</details>` block.

| Content | Output |
| --- | --- |
| `thinking` block | plain text; `<` on lines starting with `>` is escaped to `&lt;` (outside fenced blocks) so HTML tags written as markdown examples don't corrupt rendering when `_md_quote` adds an outer `>`; uses `regex` module possessive quantifiers + backreference `\1` for fence detection |
| `text` block | plain text |
| `Bash` tool_use | `<details><summary>desc or cmd_first_line</summary>` + cmd in ` ```bash ` fence + output in adaptive fence (via `_md_code_fence`) |
| `Edit`/`Write`/`NotebookEdit` | `<details><summary>file change</summary>` + diff/path |
| `TodoWrite` | `<details><summary>Todos</summary>` + numbered list |
| `Read`/`Glob`/`Grep`/`Task`/others | silently skipped |
| `AskUserQuestion`/`EnterPlanMode`/`ExitPlanMode` | handled by `_cl_render_inline_item`; should not appear here |

### `_cl_render_inline_item(rec, tr_map, question_counter)`

Renders inline records (text-only, AskUserQuestion, Enter/ExitPlanMode).
Applies `_md_quote()` to text content.
`question_counter` is a `[n]` one-element list for cross-call numbering.

| Tool | Output |
| --- | --- |
| text-only record | `_md_quote(text)` |
| `AskUserQuestion` | `### Question N` heading + blockquoted question text and option list |
| `EnterPlanMode` | `> *(entering plan mode)*` |
| `ExitPlanMode` | `> ### Plan` heading + doubly-blockquoted plan body |

### `ClaudeSessionStore.transcript()` main loop

Calls `_cl_group_turns()` and unpacks `(turns, plan_ids)`.  For each item:

- **`'user'`**: extracts text (or tool-result text for AskUserQuestion /
  ExitPlanMode answers).  If `is_plan_approval` (tool_use_id in `plan_ids`),
  scans for a `^#{0,6} *Approved Plan[: ]` heading; text before the heading
  is shown normally, text from the heading onward is collapsed into a
  `> <details><summary>Approved Plan</summary>` block.
- **`'notice'`**: emits `> *(system: notice_text)*`.
- **`'assistant_turn'`**: classifies each sub-record as inline or
  thought-group (see below), builds the `## Claude{suffix}` block.
  - Each thought group: collects `_cl_render_thought_item()` results, wraps
    in `> <details>\n> <summary>Thoughts</summary>` with `_md_quote()` applied
    to each item; in `-T` mode each item is prefixed with
    `> ### Thought N [suffix]`.
  - Each inline segment: calls `_cl_render_inline_item()`; in `-T` mode
    prefixed with `> ## Claude{inner_suffix}` where `inner_suffix` is built
    by `_build_hunk_prefix(sub_rec_no, sub_ts, ...)`.
  - The completed block is appended directly to `out` (no outer quoting).

### `_format_thought_items` (Codex only)

Used by `CodexSessionStore.transcript()`; not part of the Claude pipeline.

## Hunk data structure

`rec_no` and `ts_str` are per-line (not per-hunk) so that `-n`/`-d` display
works correctly when a hunk spans multiple records under `-x`.

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

## Adding a new parameter to the grep pipeline

When a new parameter needs to flow through the grep call chain, touch these
sites in this order (all in `AI-transcript.py`):

1. `_cl_session_grep(path, *, …, new_param=default)` — Claude grep fn
2. `_cx_session_grep(path, *, …, new_param=default)` — Codex grep fn
3. `SessionStore.grep(self, session, *, …, new_param=default)` — ABC
4. `ClaudeSessionStore.grep(…)` — passes to `_cl_session_grep`
5. `CodexSessionStore.grep(…)` — passes to `_cx_session_grep`
6. `_session_display_hunks(…, new_param=default)` — passes to `store.grep()`
7. argparse block — add flag if user-facing
8. `main()` call to `_session_display_hunks` — pass `args.new_param`

## Cross-record context (`-x` / `--cross-record`)

When `cross_record=True`, both grep functions skip the per-record
`_grep_context` calls and instead:

1. Flatten all searchable lines from all records into a
   `list[(line_text, rec_no, ts_str)]` tagged sequence.
2. Call `_grep_context_tagged(tagged, …)` which returns hunks whose lines
   each carry their own `rec_no`/`ts_str`.

`first_only=True` always uses the per-record path regardless of
`cross_record` (the AND membership check needs no context).

## Test fixtures (`scripts/fixtures/`)

Minimal JSONL files used with `--file` for repeatable rendering tests.
Run as: `python AI-transcript.py --claude --file scripts/fixtures/<name>.jsonl` (use `--codex` for Codex fixtures)

| File | Records | What it exercises | Key assertions |
| --- | --- | --- | --- |
| `thinking-lt-escape.jsonl` | user + assistant (thinking) | `<` escaping in thinking blocks: escaped on blockquoted lines outside a fence, left alone inside a ` ``` ` fence | `&lt;details` present; `&lt;span` present; `&lt;code` absent |
| `t-mode.jsonl` | user + 2× assistant (text) | `-T` mode inner headings: two consecutive inline sub-records each get `> ## Claude{suffix}` | without `-T`: `> ## Claude` absent; with `-T -d`: `> ## Claude \[20` present (twice) |
| `adaptive-fence.jsonl` | user + assistant (Bash tool_use) + user (tool_result with ` ``` `) + assistant (text) | `_md_code_fence` adaptive fencing: output containing triple backticks triggers a 4-backtick outer fence | ```````` present in output |
| `exit-plan-mode.jsonl` | user + assistant (ExitPlanMode tool_use) + user (tool_result with `# Approved Plan:`) + assistant (text) | ExitPlanMode plan-approval collapsing: text from `# Approved Plan:` onward is wrapped in `<details>` | `Approved Plan` present; `<details>` present |
| `notice.jsonl` | user + assistant (text) + assistant (`model="<synthetic>"`) + user | Synthetic notice rendering: `('notice', ...)` tuple emitted as `> *(system: ...)*` | `*(system:` present |
| `codex-orphan-patch.jsonl` | Codex: user + commentary agent_message + apply_patch + task_complete | Orphan-patch rendering (item 34): `apply_patch` with no final non-commentary agent_message still shows a file-change block | `1 file change` present; `foo.py` present |

### Writing new fixtures

Each line in a fixture file is one JSON object. Minimum required fields:

**User record** (real human message):

```json
{"type":"user","isSidechain":false,"timestamp":"2026-01-01T00:00:01.000Z","message":{"role":"user","content":[{"type":"text","text":"..."}]}}
```

**Assistant record** (normal AI output):

```json
{"type":"assistant","isSidechain":false,"timestamp":"2026-01-01T00:00:02.000Z","message":{"model":"claude-test","role":"assistant","content":[...]}}
```

**Assistant record** (synthetic notice — emitted as `> *(system: ...)*`):

```json
{"type":"assistant","isSidechain":false,"timestamp":"...","message":{"model":"<synthetic>","role":"assistant","content":[{"type":"text","text":"..."}]}}
```

Key rules:

- `isSidechain` must be `false` (truthy value causes the record to be skipped entirely).
- `model` on assistant records must be a non-empty string other than `"<synthetic>"` for normal records; use `"<synthetic>"` only for notice records.
- `timestamp` is optional but useful for `-d` / `-T -d` tests; use ISO-8601 UTC format.
- `tool_use_id` in a user `tool_result` block must match the `id` of a prior assistant `tool_use` block for the tool result to be absorbed into the turn (and thus rendered).
- `ExitPlanMode` tool-call IDs are collected into `plan_ids` by pre-scanning all records, so the `ExitPlanMode` `tool_use` must appear in the same file as its `tool_result`.
- Register each new fixture in `.gitignore` (`!scripts/fixtures/<name>.jsonl`), add a row to the table above, and add `check` calls to `AI-transcript-tests.sh`.
