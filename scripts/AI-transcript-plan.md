# AI-transcript.py — Design & Implementation Plan

## Goal

Merge [claude-transcript.py](/c:/Users/adria/.codex/scripts/claude-transcript.py) and
[codex-transcript.py](/c:/Users/adria/.codex/scripts/codex-transcript.py) into a single
[AI-transcript.py](/c:/Users/adria/.codex/scripts/AI-transcript.py).
A `SessionStore` abstraction encapsulates the storage differences between the two AIs so
all display, grep, and CLI logic is written once.  The user selects which AI(s) to search
via `--claude`, `--codex`, or `--both-AIs` (default).

---

## Lessons learned from test-run

These are concrete bugs and design issues discovered while testing the existing scripts.
Each one informs a specific requirement on the new design.

### Codex session storage quirks

- **Rollout filenames, not UUID filenames.**  Sessions are stored as
  `rollout-YYYY-MM-DDThh-mm-ss-{uuid}.jsonl`, *not* `{uuid}.jsonl`.  A naive
  `*uuid*` glob matches both the rollout file and any direct-UUID file,
  causing the wrong file to be returned (rollout sorts first alphabetically).
  Fix: exact basename match before falling back to substring glob; when using
  the substring glob, prefer files whose stem equals the target UUID exactly.
  → `_find_session_file` must try exact match first.

- **UUID must be extracted from the rollout filename.**  Every place that does
  `os.path.splitext(os.path.basename(path))[0]` to get the session UUID
  produces the full `rollout-…` stem instead.  All downstream logic then
  fails: `_uuid7_ctime` can't parse it, index lookup misses, display shows
  `rollout-` as the UUID prefix.
  → Centralise in `Session.id`; the store populates it correctly on
  construction so callers never see the raw filename.

- **`updated_at` is UTC with 7-digit fractional seconds.**  Format:
  `2026-03-15T19:30:11.8795484Z`.  Python's `datetime.fromisoformat` only
  accepts up to 6 fractional digits; passing the raw string silently truncates
  or raises on older Python.  Additionally the value is UTC but
  `_uuid7_ctime` uses `datetime.fromtimestamp` (local), so naive concatenation
  of the two produces an inconsistent header where ctime and mtime are in
  different timezones.
  → Parse `updated_at` with truncation-to-6-digits + `astimezone().replace(tzinfo=None)`.
  → Both `ctime` and `mtime` on `Session` are always **local naive datetime**.

- **File mtime is unreliable for rollout files.**  `os.path.getmtime` on a
  rollout file returns the snapshot creation time (e.g. 15:30), not the
  session end time (e.g. 19:30 stored in `updated_at`).  The `--ls` row and
  the transcript header therefore showed different mtimes.
  → `CodexSessionStore` uses `updated_at` from the session index as `mtime`,
  falling back to file mtime only when the session is not in the index.

- **`_read_session_index` de-duplicates by id.**  The index file is an
  append-only log; the same session may appear multiple times with different
  `updated_at` values.  Keep the entry with the latest `updated_at`.
  → Already implemented in `codex-transcript.py`; replicate in new store.

- **Grep scans ALL `.jsonl` files including rollouts.**  `grep_sessions`
  currently globs `sessions/**/*.jsonl`, so it greps rollout files too.
  Rollout files contain the same content as the live session, so results are
  duplicated.  The index-based approach fixes this: only grep files that
  correspond to known session IDs.
  → `CodexSessionStore.sessions()` derives paths via the index; `grep` only
  scans those paths.

- **`--ls --grep` else-branch still used `updated_at[:16]` (raw UTC) for
  `mtime_str`**, and **ambiguous-match display** did the same.  These are
  additional inconsistencies that disappear once `Session.mtime` is a
  pre-converted local datetime.

### Claude session storage quirks

- **`_project_dir` defaults to CWD.**  Running the script from
  `~/.codex/scripts/` produces `No Claude Code project directory found`
  and exits before any `--ls` output.  Tests must be run from a project
  directory, or `--project` / `--all-projects` must be passed.
  → Document in test-matrix setup section.

- **`isSidechain` records must be skipped everywhere** — title derivation,
  grep, transcript generation.  Forgetting this causes tool-call side-channel
  messages to pollute output.

- **`model == "<synthetic>"` assistant messages are boilerplate** injected by
  Claude Code and must be skipped in all processing.

- **ctime comes from the `timestamp` field in the first JSONL record**, not
  from the filesystem `os.path.getctime`.  Filesystem ctime is unreliable on
  Windows (reflects copy time, not creation time).

- **`_session_title` fallback**: sessions that start with only tool-result
  user blocks (no human text) have no user text to use as title.  Fall back
  to the first non-empty non-synthetic assistant text block.  This
  significantly reduces the number of `(no title)` sessions.

### Grep content coverage

- **Claude tool-use blocks are searchable content.**  Grep must search:
  - User text (after `_strip_system`)
  - Assistant text and thinking blocks
  - `TodoWrite` → formatted as `N. ~~text~~` / `N. **text**` / `N. text`
  - `Edit` → `- old_string_lines` / `+ new_string_lines`
  - `Write` / `NotebookEdit` → `+ content_lines`
  - `Bash` → `$ command`

- **Codex searchable content:** `event_msg` user/agent message text and
  `response_item` `custom_tool_call` input (apply_patch diffs etc.).

### Display invariants

- **`use_color` must be computed before the first `--ls` branch**, not inside
  the `--grep` block.  The `--ls` standalone path and `--id --ls` path both
  need it.

- **Identical 2-line format across all three output contexts:**

  | Context | Line 1 | Line 2 |
  | --- | --- | --- |
  | `--grep` header | `which_AI [ctime]-[mtime] [proj] records: rc` | `(uuid8) title` |
  | `--ls` row | `N. which_AI [ctime]-[mtime] [proj] records: rc` (number prefix) | `(uuid8) title` (indented by `len("N. ")`) |
  | `--id` transcript header | `which_AI [ctime]-[mtime] [proj] records: rc` | `(uuid8) title` |

  The `N.` number prefix in `--ls` is the only difference.  Codex omits `[proj]`
  (no project concept).  A single `print_session_header` / `print_session_list_row`
  pair operating on `Session` objects ensures this can never drift.

- **ANSI codes:** cyan = date bracket, yellow = project label, bold = uuid +
  title.  No color in the transcript body.  Color is always off for the
  transcript header (it's written to a file or piped).

---

## Architecture

### `Session` dataclass

```python
@dataclass
class Session:
    source:  str            # "claude" | "codex"
    id:      str            # canonical UUID (never a rollout stem)
    path:    Path           # JSONL file path (may be a rollout file for Codex)
    title:   str            # first user message (claude) or thread_name (codex)
    ctime:   datetime       # creation time — local naive datetime
    mtime:   datetime       # last-modified time — local naive datetime
    project: str | None     # short project label (claude) or None (codex)
    rc:      int            # number of JSON records in the .jsonl file
```

**Invariants enforced by the store, not by callers:**

- `id` is always the canonical UUID, even when `path` is a rollout file.
- `ctime` and `mtime` are always local naive datetime (no tzinfo).
- `title` is never empty — falls back through assistant text to `"(no title)"`.
- `project` is None for Codex; a non-empty string for Claude.
- `rc` is the number of JSON records (lines) in the `.jsonl` file — not a message
  count, since each Claude message may span many records (tool use, tool results, etc.).

### `SessionStore` ABC

```python
class SessionStore(ABC):

    @abstractmethod
    def sessions(self, *, all_projects: bool = False) -> list[Session]:
        """All sessions, sorted newest-first by mtime."""

    @abstractmethod
    def find(self, id_or_glob: str, *,
             all_projects: bool = False) -> tuple[Session | None, list[Session]]:
        """Resolve UUID prefix/full UUID/title glob.
        Returns (session, []) on unambiguous match.
        Returns (None, [candidates]) when ambiguous.
        Raises FileNotFoundError when not found.
        """

    @abstractmethod
    def grep(self, session: Session, *, plain: str | None = None,
             rx=None, before: int = 0, after: int = 0
             ) -> list[list[tuple[bool, str, list]]]:
        """Context hunks for all matches.  Each hunk is a list of
        (is_match, line_text, [(start, end), ...]) tuples.
        """

    @abstractmethod
    def transcript(self, session: Session) -> str:
        """Full Markdown transcript string."""
```

### `ClaudeSessionStore(SessionStore)`

Private helpers (all instance methods or module-level private functions):

- `_project_dirs(all_projects)` → list of project dir paths
- `_session_files(proj_dir)` → `[(mtime_float, path), ...]` sorted newest first
- `_session_ctime(path)` → local naive datetime from first JSONL `timestamp` field
- `_session_title(path)` → first user text, fallback to first assistant text
- `_strip_system(text)` → remove XML system-injected blocks
- `_project_label(proj_dir)` → short human-readable label from encoded dir name
- `_session_id(path)` → `os.path.splitext(os.path.basename(path))[0]`
  (Claude files are named `{uuid}.jsonl` directly — no rollout complication)

`find` resolution order:

1. `"latest"` → newest session
2. Exact UUID match (filename without extension)
3. UUID prefix match (`re.match(r'^[0-9a-f-]+$', ...)` then `startswith`)
4. Title glob (`fnmatch` with implicit `*term*` wrapping)
5. `:N` suffix to pick from ambiguous results

Constructor: `ClaudeSessionStore(project: str | Path | None = None)`

### `CodexSessionStore(SessionStore)`

Private helpers:

- `_codex_home()` → `~/.codex` or `$CODEX_HOME`
- `_read_session_index()` → de-duplicated list of index entries, newest first
- `_find_session_file(uuid)` → path: exact stem match first, then glob fallback
- `_session_id_from_path(path)` → strips `rollout-YYYY-MM-DDThh-mm-ss-` prefix
- `_uuid7_ctime(uuid)` → local naive datetime from first 48 bits of UUID v7
- `_updated_at_local(updated_at)` → local naive datetime, handles 7-digit
  fractional seconds by truncating to 6 before `fromisoformat`

`find` resolution order:

1. `"latest"` → first entry in session index
2. UUID prefix match via index (`id.startswith(session_id)`)
3. Direct file lookup fallback (for IDs not in index)
4. Title glob (`fnmatch` on `thread_name`)
5. `:N` suffix to pick from ambiguous results

`sessions()` derives the path for each index entry via `_find_session_file`
and only yields sessions where the file exists.

Constructor: `CodexSessionStore()`

### Shared display functions

```python
def print_session_header(session: Session, *, use_color: bool = False) -> None:
    """Print the 2-line header used by --grep and --id transcript."""

def print_session_list_row(i: int, session: Session, *,
                           use_color: bool = False) -> None:
    """Print the N. [ctime]-[mtime] [project] / indent (uuid8) title row."""
```

Both functions format dates as `"%Y-%m-%d %H:%M"`.  Both call `_ansi`.
The only difference: `print_session_list_row` prefixes `{i:3}. ` and indents
line 2 by `len(prefix)` spaces.

### Shared grep utilities

```python
def _grep_context(text, *, plain, rx, before, after) -> list[hunk]
def _plain_to_ignorepunct_rx(plain) -> re.Pattern
def _colorize(line, spans, *, active) -> str
def _ansi(s, color, *, active) -> str
```

These are identical in both current scripts and can be copied verbatim.

---

## CLI design

```
AI-transcript.py [--claude | --codex | --both-AIs]
                 [--ls] [--show-empty]
                 [--id GLOB_OR_UUID] [--all-projects]
                 [--grep TEXT | --grep-re PATTERN]
                 [--words-only] [-A N] [-B N] [-C N]
                 [--color WHEN]
                 [--project PATH]
                 [output]
```

| Flag | Meaning |
| --- | --- |
| `--claude` | Claude sessions only |
| `--codex` | Codex sessions only |
| `--both-AIs` | Both *(default when none given)* |
| `--all-projects` | All Claude projects instead of CWD project; no-op for Codex |
| `--project PATH` | Override CWD for Claude project detection |
| `--ls` | List sessions — standalone, or modifier for `--grep` / `--id` |
| `--show-empty` | Include `(no title)` sessions in `--ls` (hidden by default) |
| `--id GLOB_OR_UUID` | Session by UUID prefix, full UUID, or title glob |
| `--grep TEXT` | Search content (plain, case-insensitive) |
| `--grep-re PATTERN` | Search content (regex) |
| `--words-only` | Match word characters only; ignore punctuation and HTML tags between words |
| `-A/-B/-C N` | Context lines around grep matches |
| `--color WHEN` | `always` / `auto` *(default, TTY detection)* / `never` |
| `output` | Write transcript to file instead of stdout |

### Flag dependency hierarchy

Flags are grouped by role.  Modifiers are only meaningful when their parent
operation is active.

```
Global (apply to every operation)
  --claude | --codex | --both-AIs   source selector (mutually exclusive)
  --color WHEN                       output colour control
  --project PATH                     override CWD for Claude store

Primary operations
  --grep TEXT / --grep-re PATTERN    search sessions; output = matching hunks
    --id GLOB_OR_UUID                  narrow scope to one session
    --ls                               show list rows only (suppress hunks)
    --words-only                       match words; ignore punctuation and HTML tags
    -A / -B / -C N                     context lines around matches
    --all-projects                     include all Claude projects
    --show-empty                       (only with --ls) include no-title rows

  --id GLOB_OR_UUID                  target a specific session; output = transcript
    --ls                               show list row only (suppress transcript)
    --all-projects                     search all Claude projects
    output                             write transcript to file

  --ls  (standalone — no --grep* or --id)
    --show-empty                       include no-title sessions
    --all-projects                     include all Claude projects
```

**`--grep*` + `--id` together** — `--id` acts as a scope narrower, not a mode
switcher.  Full behaviour:

- **Output mode**: hunks (same as `--grep*` alone).  The session is *not*
  printed as a transcript.
- **`--ls` modifier**: still works — `--grep FEA --id f4b19167 --ls` prints a
  list row if the session has matches, nothing if it does not.
- **`--all-projects`**: applies to the `--id` resolution step (Claude store
  only).  Codex has no project partitioning — all sessions live in a single
  global index (`~/.codex/sessions/`), so `--all-projects` is always
  implicitly true for Codex and the flag changes nothing there.
- **Ambiguous / not-found `--id`**: same error handling as standalone `--id`
  — print candidates to stderr and exit non-zero.
- **`output` file arg**: not valid here; `output` only applies when `--id` is
  used *without* `--grep*` (transcript mode).  argparse should reject the
  combination `--grep* --id ... output`.

**Multiple `--grep` / `--grep-re`** (`action='append'` in argparse):

- **Session level — AND**: only sessions containing *all* patterns are shown.
- **Line level — OR**: any line matching *any* pattern is highlighted.

Example: `--grep FEA --grep lattice` finds sessions discussing both, and
highlights every line that mentions either.  This mirrors piping greps:
`grep FEA | grep lattice` at the session level.

**Repeated flags — three categories:**

| Flag | argparse action | Behaviour on repeat |
| --- | --- | --- |
| `--grep` / `--grep-re` | `append` | accumulates; AND at session level, OR at line level |
| `--claude` / `--codex` / `--both-AIs` | `mutually_exclusive_group` | argparse error, exits non-zero |
| `--id` | `store` | last value wins; warn to stderr if given more than once |
| `-A` / `-B` / `-C`, `--color`, `--project` | `store` | last value wins silently |

**Invalid combinations** (argparse should reject):

- `--grep` and `--grep-re` together (plain and regex are exclusive)
- `--claude`, `--codex`, and `--both-AIs` more than one at a time
- `output` without `--id`
- `output` with `--grep*` (even if `--id` is also present — `output` is for transcript only)

### Resolved design questions

- **Default source**: `--both-AIs` when none given.  Partial installation is
  handled gracefully:
  - `--both-AIs` with only one AI installed: silently skip the missing store,
    proceed with the available one.  No warning — the user likely knows only
    one is installed.
  - `--claude` or `--codex` explicitly, but that AI is not installed: print an
    error to stderr and exit non-zero.  "Not installed" means the expected
    home directory does not exist (`~/.claude/projects/` for Claude,
    `~/.codex/sessions/` for Codex).
  - Neither installed: error to stderr and exit non-zero regardless of source
    flag.
- **`--all-projects` scope**: Claude-only.  Codex has no project partitioning
  (single global index), so it always returns all sessions regardless.
- **Output flag**: positional `output` arg (no `-o`); consistent with claude style.
- **Old scripts**: delete after migration; check for external callers in
  `CLAUDE.md` / `CODEX.md` / AHK scripts first.

### `main()` structure

```
parse args
determine stores = [ClaudeSessionStore, CodexSessionStore] per flags
compute use_color (BEFORE any branch)

if --grep / --grep-re:
    if --id:
        resolve single session from stores  # scope narrowing
        handle not-found / ambiguous
        sessions = [resolved_session]
    else:
        sessions = all sessions from stores sorted by mtime descending
    collect hunks for each session (AND across patterns, OR at line level)
    discard sessions with no matches
    if --ls:
        print_session_list_row for each  # suppress hunks
    else:
        print_session_header + hunks for each

elif --id:
    resolve session from all stores (respecting --all-projects for Claude)
    handle ambiguous / not-found
    if --ls:
        print_session_list_row           # suppress transcript
    else:
        generate and print/write transcript

elif --ls:
    collect sessions from all stores
    sort by mtime descending
    filter show_empty
    print_session_list_row for each

else:
    print help
```

`--grep*` is the primary output-mode driver (hunks); `--id` either narrows its
scope (when `--grep*` is present) or drives transcript output (alone).  `--ls`
always suppresses the normal output in favour of list rows.  Standalone `--ls`
(no `--grep*` or `--id`) is the final fallback.  All paths share the same
`print_session_list_row` call.

---

## Implementation steps

### Phase 1 — Skeleton

1. New file `AI-transcript.py` with:
   - `Session` dataclass
   - `SessionStore` ABC
   - Shared display functions (`print_session_header`, `print_session_list_row`)
   - Shared grep utilities (copied verbatim from either script)
   - Colorama setup (copied verbatim)
   - Argparse / `main()` skeleton (no store calls yet)

### Phase 2 — Claude store

2. Implement `ClaudeSessionStore` with all private helpers migrated from
   [claude-transcript.py](/c:/Users/adria/.codex/scripts/claude-transcript.py).
3. Wire `--claude --ls` path.  Verify output matches `claude-transcript.py --ls`.

### Phase 3 — Codex store

4. Implement `CodexSessionStore` with all private helpers migrated from
   [codex-transcript.py](/c:/Users/adria/.codex/scripts/codex-transcript.py),
   **including all fixes from the test run**:
   - `_find_session_file`: exact match before glob
   - `_session_id_from_path`: rollout filename handling
   - `_updated_at_local`: 7-digit fractional second truncation + UTC→local
   - `grep_sessions`: only scan index-known paths (no rollout duplicates)
   - Grep header mtime: use `_updated_at_local`, not `[:16]` slice
   - Ambiguous-match display: use `_updated_at_local`, not `[:16]` slice
5. Wire `--codex --ls` path.  Verify output matches `codex-transcript.py --ls`.

### Phase 4 — Unified paths

6. Implement `--both-AIs` (default) for `--ls`, `--grep`, `--id`.
7. Implement `--all-projects` for `--id` (Claude store only).
8. Implement `--id` ambiguous-match and not-found error paths.
9. Implement transcript generation and file output.

### Phase 5 — Verification

10. Run the full test matrix (see below) from the correct working directories.
11. Fix any failures.
12. Check EOL style with `show-eol.pl`; normalize if flipped.

### Phase 6 — Commit and clean up

13. Commit `AI-transcript.py`.
14. Verify no external callers of `claude-transcript.py` / `codex-transcript.py`
    in `CLAUDE.md`, `CODEX.md`, AHK scripts, shell aliases.
15. Delete old scripts.
16. Update references in `CLAUDE.md` / `CODEX.md`.
17. Commit deletions and doc updates.

---

## Test matrix

### Setup

- Claude tests must be run from a project directory (e.g. `sphere`), or use
  `--project <path>` / `--all-projects`.  Running from `~/.codex/scripts/`
  exits with `No Claude Code project directory found`.
- Known stable test IDs: `f4b19167` (claude, sphere), `019cf2fa` (codex).
- Run tests with `--color never` first for clean text comparison; then
  `--color always | cat -v` to verify ANSI codes.

### Matrix 1 — `--ls` modes

| # | Command | Expected | Setup |
| --- | --- | --- | --- |
| 1 | `--ls` | Both AIs, 2-line rows, newest first | any dir |
| 2 | `--ls --claude` | Claude sessions only | sphere dir |
| 3 | `--ls --codex` | Codex sessions only | any dir |
| 4 | `--ls --all-projects` | All Claude projects + Codex | any dir |
| 5 | `--ls --show-empty` | Includes `(no title)` rows | sphere dir |
| 6 | `--ls --id f4b19167` | Single 2-line row, claude session | sphere dir |
| 7 | `--ls --id 019cf2fa` | Single 2-line row, codex session | any dir |
| 8 | `--ls --id 8c63cfc4 --all-projects` | Finds session in `[claude]` project | any dir |
| 9 | `--ls --grep FEA` | 2-line rows for matching sessions | sphere dir |
| 10 | `--ls --grep FEA --both-AIs` | Rows from both AIs | any dir |
| 11 | `--ls --color always \| cat -v` | ANSI: `^[[36m` date, `^[[33m` proj, `^[[1m` id+title | any |
| 12 | `--ls --color never` | No `\033` codes in output | any dir |
| 13 | `--ls --codex` (Codex not installed) | Error to stderr: Codex not found; exit 1 | simulate by renaming `~/.codex` |
| 14 | `--ls --claude` (Claude not installed) | Error to stderr: Claude not found; exit 1 | simulate by renaming `~/.claude` |
| 15 | `--ls` (neither installed) | Error to stderr; exit 1 | simulate both missing |
| 16 | `--ls --both-AIs` (only Claude installed) | Claude sessions only; no error | simulate missing `~/.codex` |

### Matrix 2 — `--id` modes

| # | Command | Expected | Setup |
| --- | --- | --- | --- |
| 1 | `--id f4b19167` | Transcript; header `[ctime]-[mtime] [sphere]` / `(f4b19167) …` | sphere dir |
| 2 | `--id f4b19167-d8a7-4a10-81c5-d03920efd017` | Same transcript (full UUID) | sphere dir |
| 3 | `--id "FEA of structures"` | Transcript for title-glob match | sphere dir |
| 4 | `--id notexist` | Error to stderr; exit 1 | sphere dir |
| 5 | `--id "FEA"` | Ambiguous error if > 1 match; candidates listed | sphere dir |
| 6 | `--id 8c63cfc4` | Error (not in sphere) | sphere dir |
| 7 | `--id 8c63cfc4 --all-projects` | Transcript for `[claude]` session | any dir |
| 8 | `--claude --id 019cf2fa` | Error: not found in Claude | sphere dir |
| 9 | `--codex --id f4b19167` | Error: not found in Codex | any dir |
| 10 | `--id 019cf2fa` | Codex transcript; header `[ctime]-[mtime]` / `(019cf2fa) Implement wall builder…` | any dir |
| 11 | `--id 019cf2fa output.md` | Writes transcript to file; `Written to:` on stderr | any dir |
| 12 | `--id latest --codex` | Transcript for most-recent Codex session | any dir |
| 13 | `--id f4b19167 --id 019cf2fa` | Warning to stderr; uses `019cf2fa` (last-wins) | any dir |

### Matrix 3 — `--grep` / `--grep-re` modes

| # | Command | Finds in | Notes |
| --- | --- | --- | --- |
| 1 | `--grep "FEA"` | Assistant text | Basic case |
| 2 | `--grep "Provide test matrix"` | TodoWrite `todos[].content` | Formatted as `N. text` |
| 3 | `--grep "session_list_row"` | Edit `old_string`/`new_string` | Shown as `- ` / `+ ` lines |
| 4 | `--grep "python claude-transcript"` | Bash `command` | Shown as `$ cmd` |
| 5 | `--grep "def _session"` | Write/NotebookEdit `content` | Shown as `+ ` lines |
| 6 | `--grep "ignore punctuation" --words-only` | Matches through backticks/HTML | Verify vs without flag |
| 7 | `--grep "FEA" -B1 -A1` | Context lines | Separator `--` between hunks |
| 8 | `--grep-re "FEA\|lattice"` | Regex OR match | |
| 9 | `--grep "wall" --codex` | Codex session text | Codex only |
| 10 | `--grep "FEA" --ls` | List rows, no hunks | `--ls` modifier behaviour |
| 11 | `--grep "FEA" --both-AIs` | Both AIs' sessions | |
| 12 | `--grep "FEA" --id f4b19167` | Hunks from session f4b19167 only | sphere dir |
| 13 | `--grep "FEA" --grep "lattice"` | Only sessions matching both; lines matching either | sphere dir |
| 14 | `--grep "FEA" --grep "zzz"` | No output (AND: no session contains both) | sphere dir |
| 15 | `--grep "FEA" --grep-re "lattice"` | argparse error: plain and regex are exclusive | any dir |
| 16 | `--claude --codex` | argparse error: mutually exclusive source flags | any dir |

### Matrix 4 — Format/header consistency

Run each command and compare the header lines visually.

| # | Check | `--grep` header | `--ls` row | `--id` transcript |
| --- | --- | --- | --- | --- |
| 1 | Claude line 1 | `[ctime]-[mtime] [sphere] records: rc` | `N. [ctime]-[mtime] [sphere] records: rc` | `[ctime]-[mtime] [sphere] records: rc` |
| 2 | Claude line 2 | `(f4b19167) title` | `(f4b19167) title` (indented) | `(f4b19167) title` |
| 3 | Codex line 1 | `[ctime]-[mtime] records: rc` | `N. [ctime]-[mtime] records: rc` | `[ctime]-[mtime] records: rc` |
| 4 | Codex line 2 | `(019cf2fa) title` | `(019cf2fa) title` (indented) | `(019cf2fa) title` |
| 5 | Codex mtime consistent | `--ls` mtime = `--grep` mtime = `--id` mtime | All show `19:30` not `15:35` | UTC-converted to local |
| 6 | Colors present | `--color always` shows cyan/yellow/bold | same | n/a |
| 7 | Colors absent | `--color never` has no ANSI codes | same | n/a |
| 8 | Indentation | Line 2 indented by `len("N. ")` spaces | same indent | no indent |

---

## Future work (post-MVP)

### Grep line-number and timestamp prefixes

- **`-n` — record number prefix.**  Prepend the 1-based line number within the
  `.jsonl` file to each matched grep line, right-justified to the digit-width
  of the total record count (which is always shown in the header).  Example
  with 120 records:

  ```text
  [ctime]-[mtime] [proj] records: 120
  (f4b19167) title
   23: matched text
  ```

- **`-d` — timestamp prefix.**  Prepend `[<timestamp>]:` (followed by a
  space) to each matched grep line.  Timestamp source per AI:
  - Claude: explicit `timestamp` field present on every JSONL record.
  - Codex: decode from the UUID v7 embedded timestamp (first 48 bits →
    milliseconds since epoch).

- **Combined `-n -d` prefix order.**  When both flags are active, timestamp
  comes first and the right-justified line number follows, so the number
  column stays vertically aligned regardless of timestamp width:

  ```text
  [<timestamp>]: 23: matched text
  ```
- **ignore case flag `-i`**  Should be case sensitive unless `-i` is passed.

- Consolidate consecutive Claude turns into one heading
  - > Each API round-trip creates a separate JSONL record. When Claude uses a tool (Bash, Read, Edit), the sequence is: `assistant` (text + tool_use) → `user` (tool_results) → `assistant` (continuation). Each `assistant` record gets its own `## Claude` heading. This is the existing behavior from `claude-transcript.py` — the new code preserves it exactly. Consolidating consecutive Claude turns into one heading would be a post-MVP improvement if desired.
  - I think it's desired.
