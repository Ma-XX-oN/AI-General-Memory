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
lorem-ipsum stand-ins where content is private).  Each log has two sections
decoded by the fixture runner:

- `1. plain (A_Clipboard minus CR)` — raw plain-text clipboard content
- `2. cfHtml (raw full payload)` — full CF\_HTML clipboard format

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
3. Ensure it includes at least these sections:
   - `1. plain (A_Clipboard minus CR)`
   - `2. cfHtml (raw full payload)`
4. Add expected markdown:
   - default: `PasteAsMd_<NAME>.expected.md`
   - scenario case: `PasteAsMd_<NAME>.<CASE>.expected.md`
5. (Optional) Add scenario metadata lines in the log header (after title line, before first `===`).

## Fixture Harness CLI

`test-paste-md-fixtures.ahk` supports these switches:

| Switch | Effect |
|---|---|
| `/ls` | Lists fixture indices/files and exits. |
| `/fixture:<n>` | Runs only fixture index `n` from `/ls`. |
| `/fixtureOutputLogs:0\|1` | Enables/disables per-scenario fixture output logs (`0` default, `1` enabled). |

Examples:

```bat
%AHK% ahk-test\test-paste-md-fixtures.ahk
%AHK% ahk-test\test-paste-md-fixtures.ahk /ls
%AHK% ahk-test\test-paste-md-fixtures.ahk /fixture:7
%AHK% ahk-test\test-paste-md-fixtures.ahk /fixture:7 /fixtureOutputLogs:1
%AHK% ahk-test\test-paste-md-fixtures.ahk /fixtureOutputLogs:1
```

No switches run the full fixture suite.
`/fixtureOutputLogs:1` with no other switch runs the full fixture set and emits
per-scenario `.fixture.log` files.

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
case:cancel,prompt:CANCEL,expectAbort:1
case:strict-parse,expectParse:1
```

Supported keys:

- `case` (required on each metadata line; if you want the default unsuffixed scenario, omit metadata lines entirely)
- `prompt` (optional): `CANCEL` or integer `> = 1`
- `expectAbort` (optional): `0` or `1` (default `0`)
- `expectParse` (optional): `0` or `1` (default `0`). When `1`, fixture fails if parse diagnostics were recorded.

Unknown keys fail metadata parsing.

### File mapping per scenario

For fixture file `PasteAsMd_<NAME>.log`:

- default (no metadata): expects `PasteAsMd_<NAME>.expected.md`
- scenario `case:<CASE>`: expects `PasteAsMd_<NAME>.<CASE>.expected.md`

Generated outputs:

- markdown output: `PasteAsMd_<NAME>.actual.md` or `PasteAsMd_<NAME>.<CASE>.actual.md`
- fixture output log (when `/fixtureOutputLogs:1`): `PasteAsMd_<NAME>.fixture.log` or `PasteAsMd_<NAME>.<CASE>.fixture.log`
  - includes `3a. parse diagnostics (DOM parse pass-through)` when parse issues occur

See also: [Fixture-Logging-Reference.md](Fixture-Logging-Reference.md).

## Change Log

Lists what commits relate to what `PasteAsMd_*.expected.md` entries.  This will
allow being able to track if a fix was good, or could have been done better for
possible future cleanup passes.

### 694e5e3 fix(paste-md): add edited-file fixture and monaco diff normalization

PasteAsMd_Codex-EditedFile.expected.md

Added the ability to convert Codex's diff representation to an actual diff
fenced code block.

### 7b61d4f fix(paste-md): fixed inappropriate numbering of an unordered list

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

### 5fc3318 fix(paste-md): handle nested unordered list selection

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

### 096551c fix(paste-md): preserve unordered intent for parent-list fragments

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
