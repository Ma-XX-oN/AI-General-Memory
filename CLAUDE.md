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

### Cover all dimensions when reviewing documents

When reviewing written documents, check all three dimensions — not just
spelling:

- **Typos/spelling** — words that don't exist
- **Grammar** — incorrect sentence structure (e.g. missing "to" in "get the
  AI understand", missing commas, wrong verb form)
- **Prose quality** — awkward phrasing, wordiness, poor flow, redundancy

Flagging only spelling errors while missing grammar mistakes and style problems
is an incomplete review.

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

### Use enough backticks when fencing content that may contain backticks

When wrapping arbitrary text in a Markdown code fence, scan the content for
the longest run of consecutive backticks it contains and use at least that
many **plus one** for the outer fence.  A fixed ` ``` ` (3-backtick) fence
will be prematurely closed by any triple-backtick sequence in the content,
causing everything after it to render as live Markdown instead of code.

### Ask when confused — never guess and implement

If there is **any** confusion about what to implement, what the requirements
mean, or how the pieces fit together, **stop and ask before writing a single
line of code**.  Do not guess at the intent, implement something plausible, and
then backtrack when it turns out to be wrong — that wastes time and can make
the situation worse than doing nothing.  Asking is always cheaper than
undoing.

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

### Committing is never part of completing a task

"Finishing work" and "committing" are two completely separate acts.  A commit
is never the natural last step of completing a task — it always requires its
own explicit instruction.  "Continue", "go ahead", "implement it", "fix it",
"do it", and all similar phrases authorize **work only**.  They never authorize
a commit.

Stop when the work is done.  Wait for an explicit commit instruction — words
like "commit it", "go ahead and commit", or equivalent.  When in doubt, ask:
"Ready to commit?"

This is doubly strict when the user has said "don't commit until I verify":
wait for (1) explicit verification and (2) a separate explicit commit
instruction before touching git at all.

### Answer questions before taking action

**STRICT RULE:** When the user asks a question or raises an issue, answer it
fully first.  Do NOT modify any file or run any tool as part of the answer
unless the user has explicitly asked you to make the change.  Describing what
you would change is not the same as being asked to change it.  Wait for
explicit direction ("go ahead", "do it", "update it") before acting.

This applies even when you know exactly what the fix is.  Proposing a change
and immediately making it in the same response is a violation of this rule.

Before acting on any instruction, also check whether the requested action
conflicts with an existing rule or has already been done.  If so, flag it and
ask rather than proceeding blindly.

### Question things that don't seem right

Do NOT assume the user knows everything or that their suggestions are always
correct.  If something in the user's design doesn't feel right or make sense
(e.g. unnecessary backslash escaping in a context where there is no escape
mechanism), speak up and ask about it rather than silently including it.
The user would rather be questioned than have wrong assumptions baked in.

### File header documentation style

See [file-doc-style.md](file-doc-style.md) for the full specification.

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

Before editing any file, read the **entire affected section** — not just the
area you expect to change.  Content after the intended insertion point often
constrains where and how the edit should be made.  When asked to "add to" a
list or section, default to appending at the end of that list/section, not
inserting at the first plausible gap.

### Keep each command as its own tool call

Never chain commands with `&&`, `;`, or `|` unless the whole pipeline was
already approved as a unit.  Chaining changes the command string into a new
unapproved shape even if each individual part was previously approved,
forcing the user to re-approve what should have been a prompt-free operation.

### Put inline comments at the end of shell commands

When adding a descriptive comment to a shell command, place it as a trailing
inline comment (`command args # description`), never on a preceding line.
Allow-list patterns like `Bash(grep:*)` match the full command string from the
start; a leading `# comment\n` prefix breaks the match and forces an
unnecessary approval prompt.

### Order transforms carefully

Do independent transforms first; do dependent or lossy transforms last.
Preserve semantic meaning before simplifying representation.

### Indentation: always 2 spaces

Use **2-space indentation** in all code (Python, JavaScript, shell, etc.) and
in all Markdown files.  Never use 4-space indentation.  When editing an
existing file that uses 4-space indentation, convert the whole file to 2-space
as part of the edit — never leave a file with mixed indentation.

### Design philosophy: encapsulation and TDD

- Prefer object or object-like structures (classes, dataclasses, named tuples,
  dicts with a defined schema) over loose collections of parallel variables.
  Encapsulation is the default; bare data is the exception.
- Break problems into the smallest testable units possible.  Every non-trivial
  function should be testable in isolation, without standing up a full system.
- Aim for Test-Driven Development (TDD): write the failing test first, then
  write only enough code to make it pass.  Never write more code than the
  current failing test requires.
- Design pipelines so each stage has a clear input/output contract.  Make the
  seams between stages explicit so they can be unit-tested independently.

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

### Check off plan items when implemented

Whenever a Future work item in a plan document (e.g. `AI-transcript-plan.md`) is fully implemented
and committed, immediately check it off in the plan (`[ ]` → `[x]`) and commit that change in the
same commit or a follow-up commit before moving on.  Never leave a completed item unchecked.

### Always use the Write tool for commit message files

Never use a bash heredoc to write the commit message temp file.  The Write tool
correctly places the file at `C:/tmp/`; a bash heredoc writing to `/tmp/` may
land in a different location on Windows (Git Bash and Windows resolve `/tmp/`
differently), causing git to silently read a stale file from a previous commit.

### SVG `<text>` elements need explicit fill in VS Code dark theme

VS Code's dark theme overrides the default SVG text color to invisible.  Always
set an explicit `fill` color on every `<text>` element in SVGs embedded in
Markdown files intended for VS Code preview.

### Call `sys.stdout.reconfigure` before initializing colorama

colorama wraps `sys.stdout` with `AnsiToWin32`, which does not implement
`reconfigure` or `isatty`.  Call `sys.stdout.reconfigure(encoding="utf-8")`
before importing or initializing colorama, not after.

### Use a virtual environment for test scripts that depend on packages

On Windows with multiple Python installs, bash resolves `python` to whichever
install appears first in `PATH`, which may lack required packages.  Use a
virtual environment in test scripts so the interpreter and packages are
determined by the venv, not PATH order.

### Read the full section before renumbering

Before converting a numbered list to headings or renumbering any sequence, read
the entire section to confirm all existing numbers.  Never start editing until
the complete number sequence is confirmed in one read — partial knowledge leads
to collisions and forced reverts.

### Ask for actual data before declaring a constraint acceptable

Never say a design constraint (memory usage, file size, performance) is "fine"
without knowing the actual numbers.  Ask the user for the concrete data first;
do not assume and then be corrected mid-implementation.

### Per-iteration exception handling in batch loops

In loops where partial results are acceptable (search, grep, batch processing),
catch exceptions inside the loop body — not around the whole loop — and log the
error before continuing.  A single `try/except` outside the loop aborts all
remaining iterations on the first failure.  Never use bare `except: pass`;
always log skipped records so failures are visible.

### Search before guessing; ask if search fails

When uncertain about a platform behavior, API contract, or environment
limitation, search for documentation first.  If no answer is found, ask the
user.  Never guess and iterate blindly through variations hoping one sticks.

### Verify comparative claims before asserting them

When making claims that compare tools, platforms, or services (e.g. "X has
this feature but Y doesn't"), confirm the claim before stating it as fact.
Unverified assumptions about other tools' capabilities can be wrong and
misleading — ask the user or search for confirmation first.

### Geometric calculations: formula first, then apply mechanically

When doing geometry (SVG coordinates, ellipse intersections, rotations), write
out the complete formula once with consistent variable names before computing
any numbers.  Apply it mechanically to each point.  Do not re-derive from
scratch mid-stream — re-derivation under pressure introduces errors and causes
spiraling.

### A single-word reply to a multi-option question is ambiguous — always ask

When the user replies with "Yes", "No", "Sure", or similar to a question that
offered multiple distinct options, that answer does not identify which option
they chose.  Ask which option they mean before taking any action.

### Ask before changing approach mid-task

When a better approach surfaces mid-task that involves a judgment call the user
should make (e.g. amend vs. new commit, merge vs. rebase, overwrite vs.
backup), stop and ask.  Do not assume and proceed.

### Update the ahk-test Change Log when adding a fixture

When adding a new fixture to `scripts/ahk-test/test-paste-md-fixtures.ahk`,
always add a corresponding entry to the `## Change Log` section in
`scripts/ahk-test/README.md` in the same commit.  Include: commit hash, fixture
filename, description of the bug, relevant before/after HTML and markdown.
Never skip this step — it has been forgotten twice.

### Use parallel reads instead of the Explore agent for known constructs

When the task targets known constructs (specific function names, flag
definitions, a display loop), skip the Explore agent and go directly to
parallel `Read` calls on the relevant file sections in a single message.
The Explore agent adds subprocess overhead (~60 s) and still requires
follow-up targeted reads for editing — it only pays off when the search is
genuinely open-ended and the locations are unpredictable.

### Batch all pre-edit reads into one parallel message

Before making any edits to a file, identify every section that needs reading
and issue all `Read` calls in a single message.  Sequential reads — one per
response — multiply round-trip latency unnecessarily.  Gather the complete
picture first, then edit.

### Don't run `wc -l` reflexively

`wc -l` is only useful when the line count is directly decision-relevant
(e.g. choosing a pagination strategy, verifying a file is non-empty).  Running
it as a reflex before reading a file adds a round-trip with no benefit — the
file size is not needed to identify which sections to read.

### Don't write todos before reading the code

Creating a todo list before reading any code produces guesses, not a plan.
Read the relevant sections first; only then write todos if the task genuinely
needs tracking.

### Don't re-derive design already agreed in conversation

Before implementing, scan back through the conversation to confirm what was
already decided.  Re-deriving settled conclusions in a thinking block wastes
tokens and delays the first edit.  Trust the conversation record.

### Read and implement the spec exactly; never invent prohibitions

Before implementing any feature, read the relevant spec text carefully and
implement exactly what it says — no more, no less.  Do not fill gaps with
assumptions and do not invent restrictions the spec does not state.

The failure mode to avoid: you have an implementation gap, you cannot easily
fill it, so you claim "the spec doesn't allow this" to justify leaving it out.
This is wrong even when the claim sounds plausible — it replaces a known gap
with a false assertion.  The correct framing for an unimplemented feature is
"not yet implemented" or "the spec doesn't cover this — should I leave it for
later?"

Reading the spec carefully in the first place prevents getting into the
position of having to defend an erroneous claim.

### Never present a gap-filling guess as a deliberate design choice

When you encounter a requirement gap and fill it with a guess, label it as a
guess.  Do not implement the guess silently and then, when challenged, defend
it as if it were a reasoned design decision.

The correct behaviour:
1. Notice the gap.
2. State it explicitly: "The spec doesn't cover X.  I'm assuming Y — is that right?"
3. If you must proceed without confirmation, mark the assumption in code (a
   `// TODO: assumed — verify` comment is fine) and flag it in your response.

Defending a guess as a design choice wastes the user's time twice: once when
they have to undo the wrong implementation, and again when they have to
re-explain what they actually wanted.  This extends the "Ask when confused"
rule to the specific failure mode of *post-hoc justification*.

### When a test fails, diagnose before splitting a single rule

When a clean, universal rule causes a test failure, the right response is to
understand *why* the test failed — not to immediately split the rule into
per-type special cases.  Special cases are usually a symptom of a wrong
diagnosis, not the fix.

Prefer one rule that works correctly for all cases over two rules that each
work for a subset.  A single universal rule is simpler, faster, and less likely
to have gaps.  If you find yourself splitting a rule mid-refactor, stop and
verify: is the original rule actually wrong, or did you misdiagnose the
failure?

### Only stage files you personally edited in the current session

When committing, only `git add` files that were modified in the current
conversation.  Pre-existing uncommitted changes from prior sessions belong in
their own separate commit.  Before staging, cross-check the file list against
what was actually touched — do not rely on memory alone.

### Read available resources before asserting any behaviour

Before stating how a library, API, compiler, or tool behaves, check what is
actually available on the system: read the relevant header, source file, man
page, or documentation.  "I don't know" is not a stopping point — look it up.
Asserting behaviour from recall alone when the authoritative source is one
tool call away is not acceptable.

### Don't store what you can derive; read the hierarchy before adding state

Before adding a new field to a type, check two things: (1) is the value
already reachable through existing fields or computable from them? (2) does
the existing type hierarchy already have a place for this state, and would
adding it at the base level duplicate something that belongs in a derived or
composed type?

Adding redundant storage creates consistency hazards.  Adding state at the
wrong level (e.g., parallel arrays in a base class when the design calls for
per-element bundles in a tuple of specialised types) breaks the design
invariants of the whole hierarchy.  Both mistakes share the same root:
proposing a change before reading what is already there.

### Design documents are as authoritative as code; surface contradictions

When a project has both a design document (README, spec, etc.) and
implementation code, treat them as equally authoritative sources.  If they
contradict each other, surface the conflict and ask which is correct — do not
silently resolve it by picking one side.  An answer is always in one of the two
sources; inference without reading both is not an answer.

### Don't carry qualifiers across a design change without re-deriving them

When porting state ownership from one type to another, the const (or volatile,
or other qualifier) model of the old type does not automatically transfer.
Reason from scratch: does any consumer of this type need to mutate its state?
If yes, `const` on the container's `item_type` (or similar) is wrong.  Copying
qualifiers blindly from the old design creates a cascade of build errors that
only surfaces after implementation — it is always cheaper to ask first.

### Verify no regressions after every rendering change

After any change to output-rendering code, spot-check the generated output for
ALL previously confirmed features before declaring the work done.  Do not assume
unchanged code paths are still intact.  At minimum check:

- Thought headings include date and record number when `-dn` flags are used.
- Output is wrapped in blockquotes (each line prefixed `>`) where expected.
- Code fences use enough backticks for their content.
- Section headings, prefixes, and suffixes match prior verified output.

If a feature disappears, treat it as a regression and fix it immediately, even
if the feature was not the target of the current change.

## API Explanations

When explaining APIs or writing API documentation, follow this structure and rules.

### Structure

Every API explanation follows four parts, in order:

1. **Setup** — Introduce the types and objects involved.
2. **Entry Point** — Show the declaration or construction; state what it represents and when it is used.
3. **Usage** — Show a complete, minimal runnable example.
4. **Explanation** — Describe the resulting behavior and any important implications.

These are a guide, not a rigid template.  For simple APIs, collapse or omit sections where doing so makes the explanation clearer.  Entry Point and Usage can be merged when showing the declaration separately would just repeat the usage example.

### Rules

- **Explain from the user's perspective** — Start from what the user creates and calls, not from internal implementation.
- **Show complete examples** — Prefer small, runnable examples over isolated fragments.
- **Explain relationships through usage** — Show how objects interact rather than describing internal mechanisms first.
- **Delay implementation details** — Explain how the API is used before explaining how it works internally.  For static tutorials where the mechanism is the point, add a `See also` or `Note` rather than burying internals at the end.
- **Explain multiple variants independently** — For APIs with several entry points or modes, explain each one separately.  Avoid mixing unrelated concepts.
- **Name things at the right level of abstraction** — Use generic names (`DataClass`, `DataList`) for generic concepts; use domain names (`Order`, `Connection`) for domain-specific APIs.  Match the name to the audience's frame of reference.
- **Introduce types before using them** — Never assume the reader knows what a variable represents.  Show construction before use in later examples.
- **Explain through increasing levels of detail** — Setup → basic usage → advanced usage → internal mechanism.  The internal mechanism comes last.

## C++

### Use `static_cast<T>(-1)` for all-bits-set unsigned values

When initializing an unsigned type to all-bits-set, prefer:

```cpp
std::numeric_limits<T>::max()
```

over the noisier `static_cast<T>(~T{})` and non-AUTOSAR compliant
`static_cast<T>(-1)`.  All are correct

- `static_cast` uses copy-initialization which permits narrowing
- `-1` is shorter and conveys the intent without extra ceremony
- but using `numeric_limits` prevents implicit sign changing.

Applies equally to default member initializers, local variables, and return
expressions.

### Prefer iterator interface over pointer arithmetic for standard library types

When working with standard library types that provide iterators, use the
iterator interface — not manual pointer arithmetic — for begin/end positions:

- `container.begin()` / `container.end()` — not `container.data()` /
  `container.data() + container.size()`

These are equivalent at runtime but the iterator forms are idiomatic C++ and
express intent more clearly.  Mixing both forms in the same codebase is wrong.

### EBO-via-inheritance breaks C++17 standard-layout

A class is **not** standard-layout in C++17 if both a base class and the
derived class have non-static data members (C++17 [class.prop]/3.5).  This is
the failure mode of EBO-via-private-inheritance: the base holds a size or
extent member, the derived holds a data pointer, and the derived type fails
`is_standard_layout_v<T>`.

Before storing a type as a member of a type that requires standard-layout
(intrusive containers, `static_assert(is_standard_layout_v<...>)`, etc.), check
whether the candidate type uses this EBO inheritance pattern.  Discover this
before the build, not after.

The portable C++17 fix is partial specialization: the static-extent primary
template holds only `m_data` and returns `Extent` from `size()`; the
dynamic-extent specialization holds both `m_data` and `m_size` as direct
members of the same class.  No attributes needed.

### Verify a fix fits the project's language standard

Before writing a fix that uses any attribute, keyword, or library feature,
check whether it is available in the project's language standard.
`[[no_unique_address]]` is C++20; MSVC additionally requires its own
`[[msvc::no_unique_address]]` variant.  If the project targets C++17, the
partial-specialization approach (see above) is the portable alternative.

### C++17 TMP: three patterns worth knowing

**Heterogeneous tuple type from a compile-time array, using `decltype`:**
```cpp
template<std::size_t... Is>
auto make_tuple_impl(std::index_sequence<Is...>)
  -> std::tuple<ElementType<array[Is].policy>...>;  // declared, never defined

using MyTuple = decltype(make_tuple_impl(std::make_index_sequence<N>{}));
```
`decltype` only needs the return type, so the function body is never needed.

**Bool-parameterised EBO for conditional per-element state:**
```cpp
template<bool> struct State;
template<> struct State<true>  { T data; };
template<> struct State<false> {};  // empty — EBO-eligible when inherited
```
Inheriting from `State<condition>` includes the field at zero cost when
`condition` is false.

GCC and Clang apply EBO automatically for multiple empty bases.  MSVC only
applies it unless the struct is annotated with `__declspec(empty_bases)`.  Use a
portability macro:

```cpp
#ifdef _MSC_VER
  #define EMPTY_BASES __declspec(empty_bases)
#else
  #define EMPTY_BASES
#endif

struct EMPTY_BASES MyState : Base1<cond1>, Base2<cond2>, Base3<cond3> { ... };
```

`EMPTY_BASES` is placed between `struct`/`class` and the type name.  On MSVC it
instructs the compiler to collapse all empty bases; on other compilers it
expands to nothing.

**Namespace-wrapped unscoped enum as `std::get<>` index:**
```cpp
namespace eKind_ns { enum eKind : std::size_t { A = 0, B = 1 }; }
using eKind = eKind_ns::eKind;
// std::get<eKind::A>(variant)  — no static_cast: unscoped enum converts implicitly
```
A scoped `enum class` would require an explicit `static_cast<std::size_t>` at
every call site.  The namespace wrapper gives scoping without losing the
implicit integer conversion.

### User direction

When pointing out something to the user, USE LINKS so that they doin't have to
go hunting for the file and line, like this:

```markdown
[file.ext:line](c:\full\path\to\file.ext#Lline)
```

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
  1. Run (source) `. ~/.claude/scripts/session-pid.sh` once.  The script
     **prints** the PID to stdout — it does NOT set a `SESSION_PID` shell
     variable.  Read the printed PID from the Bash tool output (e.g. `11032`)
     and use it literally in the steps below.  Never try to reference
     `$SESSION_PID` — it will always be empty.
     If the script fails, use `/tmp/claude-commit-msg.txt` as a fixed fallback path.
  2. Write the commit message to `/tmp/claude-commit-msg-<PID>.txt`
     using the Write tool (no approval needed).
     Note: the Write tool maps `/tmp` → `C:\tmp`; git requires the Windows form.
  3. Commit with the stable command: `git commit -F C:/tmp/claude-commit-msg-<PID>.txt`
     (approve-once eligible with prefix `git commit -F C:/tmp/claude-commit-msg-`).
- After any push to origin from either `~/.claude` or `~/.codex`, immediately
  `git pull` in the other repo so both stay in sync with origin.

## Useful Patterns

- [Generalized bracketed-text regex](regex-patterns.md#generalized-bracketed-text-matching)
- [AHK PCRE callout debugger](regex-patterns.md#ahk-pcre-callout-debugger)
- [Testing guidelines](testing.md)
- [Workflow guidance (TTD/tests/commit workflow)](workflow.md)
- [Build issue triage playbook](build_issues.md)
- [AI-transcript.py architecture and key locations](scripts/AI-transcript-arch.md)

## Transcript search

When asked to search Claude or Codex transcripts or sessions, use
`~/.claude/scripts/AI-transcript.py`.  Prefer this over manually grepping
session directories.

```bash
python ~/.claude/scripts/AI-transcript.py [--claude|--codex|--both-AIs] \
  [--ls | --id GLOB_OR_UUID | --grep TEXT | --grep-re PATTERN] [output.md]
```

Key flags: `--all-projects`, `-A/-B/-C` (context lines), `--words-only`, `--color`.

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
