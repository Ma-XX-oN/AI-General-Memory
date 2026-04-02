# ahk-test

AutoHotkey v2 test suite for PasteAsMd and its HTML parsing pipeline.

## Running the tests

From the repo root (`ahk-test/..`):

```bat
set AHK="C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe"
%AHK% ahk-test\test-norm.ahk
%AHK% ahk-test\test-norm-integration.ahk
%AHK% ahk-test\test-paste-md-fixtures.ahk
%AHK% ahk-test\test-parser.ahk
%AHK% ahk-test\test-dom.ahk
```

Or from within the `ahk-test/` directory:

```bat
set AHK="C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe"
%AHK% test-norm.ahk
%AHK% test-norm-integration.ahk
%AHK% test-paste-md-fixtures.ahk
%AHK% test-parser.ahk
%AHK% test-dom.ahk
```

Results are written to `*.log` files alongside each test script.

Important:

- The maintained AHK test scripts exit non-zero on failures:
  - logged `Chk(...)` failures return exit code `1` via the shared `TestFinish()` helper
  - uncaught fatal errors are routed through the shared `OnError` handler and exit `1` without the popup path
- Treat the process exit code as the primary pass/fail signal.
- Inspect the corresponding `*.log` file for failure details, including the `Results: X passed, Y failed` summary and any `FAIL` lines.

Clean generated test logs:

```bat
%AHK% ahk-test\test-clean.ahk
%AHK% test-clean.ahk
```

## Test files

| Script | What it tests | Count |
|---|---|---|
| `test-norm.ahk` | `HtmlNorm` unit tests (source detection, poster injection, normalizer helpers) | 47 |
| `test-norm-integration.ahk` | Integration tests using real clipboard HTML captured from each source | 66 |
| `test-paste-md-fixtures.ahk` | End-to-end fixture tests: reads `PasteAsMd_*.log`, converts, compares `*.expected.md` | 130 |
| `test-parser.ahk` | `HtmlParser` unit tests | 45 |
| `test-dom.ahk` | `HtmlDom` / `DomNode` API tests | 53 |
| `test-clean.ahk` | Cleanup helper: deletes generated `test-*.log`, `PasteAsMd_*.actual.md`, and `PasteAsMd_*.fixture.log` files | — |
| `test-helpers.ahk` | Shared helpers (`Log`, `Chk`, `DumpNode`) — not run directly | — |

## Fixture files

`PasteAsMd_*.log` files contain debug captures from real clipboard pastes (or
lorem-ipsum stand-ins where content is private).  Each log has three sections
decoded by the fixture runner. Canonical fixture logs are stored as UTF-8 with
BOM and use CRLF throughout:

- `0. source` — expected source detection (`claudecode`, `claudeweb`, `codex`, `chatgpt`, or `unknown`)
- `1. plain (canonical text capture)` — lossless plain-text clipboard content serialized into canonical UTF-8 log text with CRLF
- `2. cfHtml (raw full payload)` — exact CF\_HTML clipboard payload; its stored offsets remain UTF-8 byte positions and are offset-sensitive

`PasteAsMd_*.expected.md` files are the expected markdown output for each fixture.
`PasteAsMd_*.actual.md` files are generated at test time and excluded from git.

### Pinned runtime logs (`Pin current log`)

From `PasteAsMd` menu:

- `Pin current log` prompts for an optional comment.
- Blank comment creates: `PasteAsMd_debug_<TIMESTAMP>.log`
- Comment creates: `PasteAsMd_debug_<TIMESTAMP>_<COMMENT>.log`

Pinned-log features (`Delete pinned history`, `Pinned file names`, `Pinned full names`)
match both filename forms.

### Converting pinned logs into fixtures

1. Pin a runtime debug log from the menu.
2. Copy it into `ahk-test/` and rename it to `PasteAsMd_<NAME>.log`.
3. Anonymise text: run `sanitize-fixture-log.py --input <file> --output <file>` to
   scramble visible text in sections `1` and `2` while preserving byte lengths.
   The script automatically strips sections `2b` and `3`–`6` (not used by the
   harness; may contain unsanitised derived text).
   - **Codex fixtures**: the sanitiser scrambles `extensionId=openai.chatgpt` inside
     the `SourceURL:` header, breaking source detection.  After sanitising, restore
     the original `extensionId=openai.chatgpt` bytes at their known offset within the
     URL value (offset 188 in the standard Codex webview URL).
4. Ensure it includes at least these sections:
   - `0. source`
   - `1. plain (canonical text capture)`
   - `2. cfHtml (raw full payload)`
5. Add expected markdown:
   - default: `PasteAsMd_<NAME>.expected.md`
   - scenario case: `PasteAsMd_<NAME>.<CASE>.expected.md`
6. If you want a replay log, copy the canonical source log to `PasteAsMd_<NAME>.fixture.log`; sections after `2` are optional and ignored by the harness.

Canonical fixture note:

- The harness expects canonical `PasteAsMd` logs only: UTF-8 with BOM, CRLF section framing, no visible EOL markers.
- Section `1` is a canonical text capture, not a raw UTF-16 byte dump.
- Section `2` is preserved exactly as CF\_HTML text; its `StartHTML` / `EndHTML` / `StartFragment` / `EndFragment` headers remain UTF-8 byte offsets and must already match the stored payload.
- **Do not run `normalize-eol.pl` on fixture log files.** Fixture logs must stay in
  their original CRLF format as produced by the runtime. Using `show-eol.pl` for
  inspection is safe; using `normalize-eol.pl` to rewrite the file is not.

## Fixture Harness CLI

`test-paste-md-fixtures.ahk` supports these switches:

| Switch | Effect |
|---|---|
| `/ls` | Lists fixture indices/files and exits. |
| `/fixture:<n\|path>` | Runs only fixture index `n` from `/ls`, or a specific fixture log path/name when the value is not numeric. Relative paths resolve from `scripts/ahk-test`. |
| `/log:<path>` | Writes the harness log to a specific path. Relative paths resolve from `scripts/ahk-test`. |
| `/fixtureOutputLogs:0\|1` | Enables/disables per-scenario fixture output logs (`0` default, `1` enabled). |

Examples:

```bat
%AHK% ahk-test\test-paste-md-fixtures.ahk
%AHK% ahk-test\test-paste-md-fixtures.ahk /ls
%AHK% ahk-test\test-paste-md-fixtures.ahk /fixture:7
%AHK% ahk-test\test-paste-md-fixtures.ahk /fixture:PasteAsMd_ChatGPT-ButtonLinks.log
%AHK% ahk-test\test-paste-md-fixtures.ahk /fixture:..\tmp\PasteAsMd_large.log
%AHK% ahk-test\test-paste-md-fixtures.ahk /fixture:7 /log:..\tmp\fixture-7.log
%AHK% ahk-test\test-paste-md-fixtures.ahk /fixture:7 /fixtureOutputLogs:1
%AHK% ahk-test\test-paste-md-fixtures.ahk /fixtureOutputLogs:1
```

No switches run the full fixture suite.
`/fixtureOutputLogs:1` with no other switch runs the full fixture set and emits
per-scenario `.fixture.log` files.

The harness log records `Elapsed: ...` for each fixture and `Suite elapsed: ...`
for the full run, so branch-to-branch timing comparisons can be taken from
`test-paste-md-fixtures.log`.
Use `/log:<path>` when multiple harness runs need separate logs.

Cleanup is handled by `test-clean.ahk`:

- deletes generated `test-*.log` files
- deletes generated `PasteAsMd_*.actual.md` files
- deletes generated `PasteAsMd_*.fixture.log` files
- does **not** delete fixture source captures (`PasteAsMd_*.log`)
- does **not** delete expected outputs (`*.expected.md`)

## Fixture Metadata (in `.log` header)

Fixture scenario metadata lives in the fixture `.log` header:

1. Keep line 1 as the title (`PasteAsMd debug — ...`).
2. Put scenario metadata lines after line 1.
3. Metadata parsing stops at the first `===` section marker.
4. Each non-blank metadata line is one scenario.

If there are no metadata lines, the harness runs one default scenario.

### Metadata line format

Comma-separated `key:value` pairs, for example:

```text
case:renumber3,prompt:3
case:renumber3_plain,prompt:3,asQuoted:0
case:cancel,prompt:CANCEL,expectAbort:1
```

Supported keys:

- `case` (required on each metadata line; if you want the default unsuffixed scenario, omit metadata lines entirely)
- `prompt` (optional): `CANCEL` or integer `> = 1`
- `expectAbort` (optional): `0` or `1` (default `0`)
- `asQuoted` (optional): `0` or `1` (default `1`)

Unknown keys fail metadata parsing.

### File mapping per scenario

For fixture file `PasteAsMd_<NAME>.log`:

- default (no metadata): expects `PasteAsMd_<NAME>.expected.md`
- scenario `case:<CASE>`: expects `PasteAsMd_<NAME>.<CASE>.expected.md`

Generated outputs:

- markdown output: `PasteAsMd_<NAME>.actual.md` or `PasteAsMd_<NAME>.<CASE>.actual.md`
- fixture output log (when `/fixtureOutputLogs:1`): `PasteAsMd_<NAME>.fixture.log` or `PasteAsMd_<NAME>.<CASE>.fixture.log`

See also: [Fixture-Logging-Reference.md](Fixture-Logging-Reference.md).

## Change Log

Lists what commits relate to what `PasteAsMd_*.expected.md` entries.  This will
allow being able to track if a fix was good, or could have been done better for
possible future cleanup passes.

### d665140 fix(htmlnorm): preserve Codex inline function-reference button text

PasteAsMd_Codex-ButtonLinks.expected.md

Codex renders inline function/file references as `<button class="...
text-token-text-link-foreground hover:underline">` elements.  The generic
button-strip rule (`<button\b[^>]*>.*?</button>` → empty) removed these along
with UI buttons (copy, thumbs, etc.), silently dropping the text content.

Added a targeted preserve pass before the generic strip that matches the
`text-token-text-link-foreground` class and replaces the button with its inner
content (`$1`).  Residual `<span>` wrappers left by the pass are cleaned up by
the existing span-stripping step (step 13).

From stage 2. cfHtml (raw full payload) (Simplified)

```html
<button class="... text-token-text-link-foreground hover:underline" ...>
  <span ...>SphericalFaceLattice.post_init() (line 260)</span>
</button>
```

**Fix applied here** (step 4 in `HtmlNorm.Normalize`).

From stage 6. FINAL md (pasted) — before fix

```md
> 2.  Lattice construction still recomputes...in a row.
>      builds each row by calling `geometry.unit_point(...)` for every `(u,v)`.
>      For interior nodes,  and  recompute...
```

From stage 6. FINAL md (pasted) — after fix

```md
> 2.  Lattice construction still recomputes...in a row.
>      SphericalFaceLattice.post_init() (line 260) builds each row by calling
>      `geometry.unit_point(...)` for every `(u,v)`. For interior nodes,
>      discrete_unit_point() (line 238) and discrete_unit_point() (line 239) recompute...
```

### da886b5 fix(htmlnorm): handle ChatGPT section-element turn containers

PasteAsMd_ChatGPT-SectionTurns.expected.md

ChatGPT changed their renderer so conversation turns are now wrapped in
`<section data-turn="...">` instead of `<article data-turn="...">`.
`_InjectPosterPlaceholders` only matched `<article>`, so `## User` /
`## ChatGPT` headings were not injected for any ChatGPT clipboard paste.

Updated all three patterns to match `(?:article|section)` so both old
and new clipboard captures work.

From stage 2. cfHtml (raw full payload) (Simplified)

```html
<section ... data-turn="assistant" ...>...</section>
<section ... data-turn="user" ...>...</section>
<section ... data-turn="assistant" ...>...</section>
```

**Fix applied here.**

From stage 6. FINAL md (pasted)

```md
## ChatGPT

> Ems tbsdp ddtfbbj gqd oppbn ...

## User

> Ugzuj axml g rihc zg iraaes ...

## ChatGPT

> Wsj. Zre p owao. Ylhn'p htq ...
```

### 38e74b8 fix(cliphelper): keep CF_HTML offsets as UTF-8 byte positions

Affected runtime/files:

- `ClipHelper.ahk`
- `test-paste-md-fixtures.ahk`

`CF_HTML` offsets are defined in UTF-8 bytes, so the runtime and fixtures must
preserve that payload model exactly. Character-count slicing is not sufficient
once the clipboard HTML contains non-ASCII text.

The runtime fix keeps the existing numeric headers and applies them correctly:

- `ClipboardWaiter.GetHtml()` decodes the clipboard payload as UTF-8 text.
- `ClipboardWaiter.SelectHtmlSection()` re-encodes that text as UTF-8 and slices
  the requested byte range directly from the stored offsets.
- `PasteMd` consumers that inspect the pre-fragment context now use the same
  UTF-8 byte-range slicing helper instead of character-based substring logic.

The fixture harness now validates canonical logs directly:

- section payload length must match the declared `len=...`
- each section boundary must be followed by the one canonical CRLF separator block or EOF
- the stored CF\_HTML offsets are used as-is against the canonical payload

### 7bf4898 fix(paste-md): strip trailing empty list items for non-bare-li fragments

PasteAsMd_ChatGPT-TrailingEmptyBullet.expected.md

When the source app includes a trailing empty `<li>` after a `<p>` (a cursor
artifact from copy), the empty bullet was pasted because
`NormalizeIncidentalListIntentHtml` only stripped it for bare-`<li>` fragments.
Added `StripTrailingEmptyListItems` and called it unconditionally so the
stripping applies regardless of fragment shape.

From stage 2. cfHtml (raw full payload) (Simplified)

```html
<html><body>
<!--StartFragment-->
<p>Right now the document looks like it is trying to cover:</p>
<ul><li><p></p></li></ul>
<!--EndFragment-->
</body></html>
```

From stage 4. mdRaw (pandoc output)

```md
Right now the document looks like it is trying to cover:

-
```

**Fix applied here.**

From stage 6. FINAL md (pasted)

```md
> Right now the document looks like it is trying to cover:
```

### 81bd5f6 fix(paste-md): preserve unordered intent for parent-list fragments

PasteAsMd_Codex-OrderedList-Parent.expected.md
PasteAsMd_Codex-OrderedList-Nested.expected.md

Moves incidental list correction from markdown patching to structural HTML
normalization before pandoc.

From stage 2. cfHtml (raw full payload) (Simplified)

```html
<html>
<body>
<!--StartFragment-->
<li>...</li>
<li>...</li>
<!--EndFragment-->
</body>
</html>
```

From stage 3. htmlPrep (after _PreprocessHtml) (Simplified)

```html
<ol>
  <li>...</li>
  <li>...</li>
</ol>
```

**Fix applied here.**

From stage 4. mdRaw (pandoc output)

```md
- item A
- item B
```

From 5. md (after CleanMarkdown)

```md
- item A
- item B
```

### 469b843 fix(paste-md): handle nested unordered list selection

PasteAsMd_Codex-OrderedList-Nested.expected.md

Fixes unordered lists being rendered as ordered (numbered).  This is a slightly
more complicated case of the previous.

From stage 2. cfHtml (raw full payload) (Simplified)

```html
<html>
<body>
<!--StartFragment-->
<li>
  <p>For each integer <code>M = 0, 1, 2, ...</code> compute:</p>
  <ul>
    <li><p><code>P_e.shell</code> ...</p></li>
    <li><p><code>P_e.skin(M)</code></p></li>
    <li><p><code>P_e.rib(M)</code> ...</p></li>
  </ul>
</li>
<li><p></p></li>
<!--EndFragment-->
</body>
</html>
```

From stage 3. htmlPrep (after _PreprocessHtml) (Simplified)

```html
<ol>
  <li>
    <p>For each integer <code>M = 0, 1, 2, ...</code> compute:</p>
    <ul>
      <li><p><code>P_e.shell</code> ...</p></li>
      <li><p><code>P_e.skin(M)</code></p></li>
      <li><p><code>P_e.rib(M)</code> ...</p></li>
    </ul>
  </li>
  <li><p></p></li>
</ol>
```

From stage 4. mdRaw (pandoc output)

```md
1.  For each integer `M = 0, 1, 2, ...` compute:¶
¶
    - `P_e.shell` (independent of `M`)¶
    - `P_e.skin(M)`¶
    - `P_e.rib(M)` (if defined; else `undef`)¶
¶
2.  ¶
```

**Fix applied here.**

From 5. md (after CleanMarkdown)

```md
1.  For each integer `M = 0, 1, 2, ...` compute:¶
¶
    - `P_e.shell` (independent of `M`)¶
    - `P_e.skin(M)`¶
    - `P_e.rib(M)` (if defined; else `undef`)¶
¶
2.  ¶
```

### df73bc2 fix(paste-md): fixed inappropriate numbering of an unordered list

PasteAsMd_Codex-OrderedList-Parent.expected.md

Fixes unordered lists being rendered as ordered (numbered).

From stage 2. cfHtml (raw full payload) (Simplified)

```html
<html>
<body>
<!--StartFragment-->
<li><p>...top flange width...</p></li>
<li><p>...rib height...</p></li>
<li><p></p></li>
<!--EndFragment-->
</body>
</html>
```

From stage 3. htmlPrep (after _PreprocessHtml) (Simplified)

```html
<ol>
  <li><p>wt = top flange width (total or per side)</p></li>
  <li><p><math>h_r</math>hr = rib height (web height)</p></li>
  <li><p></p></li>
</ol>
```

From stage 4. mdRaw (pandoc output)

```md
1.  wt​ = top flange width (total or per side)¶
¶
2.  $`h_r`$hr​ = rib height (web height)¶
¶
3.  ¶
```

**Fix applied here.**

From 5. md (after CleanMarkdown)

```md
1.  wt​ = top flange width (total or per side)¶
2.  $`h_r`$hr​ = rib height (web height)¶
3.  ¶
```

### c7cdd78 fix(paste-md): add edited-file fixture and monaco diff normalization

PasteAsMd_Codex-EditedFile.expected.md

Added the ability to convert Codex's diff representation to an actual diff
fenced code block.
