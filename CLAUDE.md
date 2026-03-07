# Global Notes for Claude

## Memory management

When asked to remember something, place **general knowledge** (applicable to
any project) here in `~/.claude/CLAUDE.md` or its referenced files.  Place
**project-specific knowledge** in the project's own `CLAUDE.md`.  When
possible, distill project-specific lessons into general principles and store
them here.

When adding or modifying files in `~/.claude/`, first read `~/.claude/README.md`
to understand the repo structure and conventions.  Then:

1. Add a `!filename` entry to `~/.claude/.gitignore` (deny-all with explicit
   exceptions).
2. Add an entry to the Contents table in `~/.claude/README.md`.
3. Reference the file from `CLAUDE.md` (or `CODEX.md` if applicable).

## Lessons Learned

### Be thorough on review tasks

When asked "is there anything else?" or "check again", do a genuinely fresh
pass rather than assuming prior checks were exhaustive.

### When fixing one of a pair/group, check all siblings

If a comment or pattern appears in multiple places (e.g. parallel comment
lines, repeated constants, similar code blocks), fix all occurrences together.

### When fixing library usage bugs, use public APIs

When encountering issues with library functions, prefer using the correct
public API that handles necessary preprocessing like caching.  Avoid calling
internal functions directly or modifying library internals, as this bypasses
design safeguards and can lead to fragile fixes.  Address the root cause at
the call site first.  Note: this applies to code *external* to the library.
When writing code that is *part of* the library, calling its private functions
is fine and often preferred — they exist to bypass checks/evaluation that only
the public API needs to perform for external callers.

### Ask for help when stuck

When a fix isn't working after 2-3 attempts, STOP and tell the user:

- What you are trying to do (the goal)
- What approach you tried
- Why it isn't working
- Ask to collaborate on the solution

Do not spin in circles retrying variations silently.  The user is a skilled
coder and can help break the problem down.  Say something like: "This problem
seems a bit too complex and I seem to be going around in circles, so I would
like to bounce some ideas off you to possibly get to a solution faster."

Also: when the user says STOP, stop immediately and answer their question
directly.  Do not continue analyzing or coding.

### Answer questions before taking action

**STRICT RULE:** When the user asks a question or raises an issue, answer it
fully first.  Do NOT modify any file or run any tool as part of the answer
unless the user has explicitly asked you to make the change.  Describing what
you would change is not the same as being asked to change it.  Wait for
explicit direction ("go ahead", "do it", "update it") before acting.

This applies even when you know exactly what the fix is.  Proposing a change
and immediately making it in the same response is a violation of this rule.

### Question things that don't seem right

Do NOT assume the user knows everything or that their suggestions are always
correct.  If something in the user's design doesn't feel right or make sense
(e.g. unnecessary backslash escaping in a context where there is no escape
mechanism), speak up and ask about it rather than silently including it.
The user would rather be questioned than have wrong assumptions baked in.

### Document all public symbols

All functions, modules, values and types must have JSDoc-style documentation
comments (`/** ... */`).  This includes `@param`, `@returns`, `@type`,
and `@typedef` tags as appropriate.  Private symbols should have at least a
brief `/** ... */` comment.

**OpenSCAD:** Also uses `@slot` and `@deref` tags.  Constants used as slot
indices must have full `@type` doc blocks (not just short inline comments),
matching the style used in `string_consts` and `spline_consts`.  For
slot-based object types (`@typedef {list}`), use `@deref` to indicate which
enum type dereferences the object:

```javascript
/**
 * @typedef {list} MyObject
 * @deref {MyObjectEnum}
 *
 * Description of the object.
 *
 * @slot {type} SLOT_NAME
 *   Description of slot.
 */
```

### Preserve line endings

Before editing a file, check its EOL style with
`~/.claude/scripts/show-eol.pl`.  After editing, verify the EOL hasn't
flipped; if it has, fix with `~/.claude/scripts/normalize-eol.pl <LF|CRLF>`.

### Redirect expensive command output to a temp file

Never pipe long-running commands (builds, large test suites) through
head/tail/grep directly.  Redirect to a temp file first
(`cmd 2>&1 | tee /tmp/output.log`), then examine the file.  Re-running an
expensive command just to see different parts of the output is wasteful.

### Never use MEMORY.md for learned information

Always store learned information in `~/.claude/CLAUDE.md` (general) or the
project's `CLAUDE.md` (project-specific).  Never use the auto-memory
`MEMORY.md` file — it hides information from the user.

### Be direct and precise

Use definitive language for confirmed facts.  If uncertain, say so explicitly.
Before responding, check for unjustified hedging and remove it.  Back claims
with verifiable evidence (counts, diffs, line references) rather than
assertions alone.

In debugging explanations, state the single minimal root cause first (one
sentence), then show the exact line-level behavior causing it, before any
secondary context.

In technical recommendations, explicitly separate confirmed facts from
preferences/inference, and include the strongest counterargument before the
final recommendation.  If a recommendation changes, state the concrete new
fact that caused the change.

For any question about current file contents, do a fresh read of the target
file in the same turn before answering; do not answer from cached context alone.

### Order transforms carefully

Do independent transforms first; do dependent or lossy transforms last.
Preserve semantic meaning before simplifying representation.

### Design principles

- Generalize before optimizing: extract domain-specific parsing into a
  reusable spec/API.
- Put shape in data, not code: declare parameters/defaults once, reuse
  everywhere.
- Keep semantics separate from structure: helpers normalize shape; callers
  validate meaning/types.
- Make defaults declarative in spec definitions instead of scattering them
  in function bodies.
- Verify incrementally with build/tests during refactors to preserve behavior.
- Prefer explicit canonical outputs (fixed slots + variadic tail) over
  ad-hoc branching.
- Preserve diagnostics while simplifying APIs: keep provenance internally,
  keep the caller API simple.
- Extend capability only for real use-cases; keep scope narrow.
- Treat documentation and examples as part of correctness, not optional polish.
- Never run build and tests concurrently; complete build first, then run tests.

### GitHub markdown rendering

- GitHub strips `<svg>` tags from markdown for security.  Use Unicode
  characters (e.g. ☰) or plain text instead.
- GitHub does not reliably link to anchors containing colons or URL-specific
  punctuation.  Sanitize anchors via `sanitize_anchor_id()`:
  colons become `__`, spaces and other URL punctuation become `_`.
- GitHub's monospace font renders Unicode box-drawing characters (U+2500–U+257F)
  at inconsistent widths, causing alignment drift in ASCII art diagrams.  Use
  plain ASCII (`+`, `-`, `|`) for diagrams intended to render correctly on
  GitHub; reserve box-drawing characters for local/IDE viewing only.
- In Markdown, write `> =` (with space) instead of `>=` to prevent
  auto-conversion to `≥`.

### Diagrams

- For precision diagrams, prefer an ASCII-first draft then convert to SVG;
  avoid relying on Mermaid auto-layout for final authoritative diagrams.
- When editing diagrams, preserve connectivity and neighboring relationships —
  don't optimize a single element in isolation.
- For SVG styling, use redundant encodings (color + line-style/weight) so
  meaning is clear under color-vision deficiencies and grayscale.

## AutoHotkey v2

See [ahk.md](ahk.md) for full notes. Critical reminders:

- Backtick (`` ` ``) is the escape character; `` `` `` = literal backtick; backtick before `"` = literal `"` (does NOT close the string — see ahk.md for the trap)
- Space concatenation (`"abc" var`) works — `.` is optional (useful for line continuation only)
- Git Bash converts `/Switch` args to paths — use `#ErrorStdOut` directive in script, not command-line flag
- Use `Chr(96)` to build backtick strings in tests (avoids the backtick-quote trap in string literals)

## Git commits

- Always use Conventional Commit format for every commit.
- Body bullet detail lines must be contiguous — no blank lines between bullets.
- PowerShell: never put Markdown backticks in `git commit -m` strings; use
  single-quoted `-m` or `git commit -F` with a temp file to avoid
  escape-related character loss.
- Use a stable `git commit -F` command so it can be pre-approved once per
  session.  Workflow:
  1. Source (not execute) `. ~/.claude/scripts/session-pid.sh` once to get the session PID.
     If it fails, use `/tmp/claude-commit-msg.txt` as a fixed fallback path.
  2. Write the commit message to `/tmp/claude-commit-msg-<SESSION_PID>.txt`
     using the Write tool (no approval needed).
  3. Commit with the stable command: `git commit -F /tmp/claude-commit-msg-<SESSION_PID>.txt`
     (approve-once eligible with prefix `git commit -F /tmp/claude-commit-msg-`).

## Useful Patterns

- [Generalized bracketed-text regex](regex-patterns.md#generalized-bracketed-text-matching)
- [AHK PCRE callout debugger](regex-patterns.md#ahk-pcre-callout-debugger)
- [Testing guidelines](testing.md)
- [Workflow guidance (TTD/tests/commit workflow)](workflow.md)
- [Build issue triage playbook](build_issues.md)

## Time tracking (every prompt)

For **every** prompt — questions, coding tasks, research, all of them:

1. At the very start of your response, get the current time and output it.
2. At the very end of your response, get the current time and output it.
3. Output the elapsed time in a fenced code block with exactly these lines:

   ```text
   START=<time>
   END=<time>
   ELAPSED=<m:ss>
   ```

   Format `ELAPSED` as `m:ss` (minutes, colon, zero-padded seconds), e.g. `1:07`.
