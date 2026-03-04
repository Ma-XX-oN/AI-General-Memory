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

## Test files

| Script | What it tests | Count |
|---|---|---|
| `test-norm.ahk` | `HtmlNorm` unit tests (source detection, poster injection, normalizer helpers) | 47 |
| `test-norm-integration.ahk` | Integration tests using real clipboard HTML captured from each source | 66 |
| `test-paste-md-fixtures.ahk` | End-to-end fixture tests: reads `PasteAsMd_*.log`, converts, compares `*.expected.md` | 130 |
| `test-parser.ahk` | `HtmlParser` unit tests | 45 |
| `test-dom.ahk` | `HtmlDom` / `DomNode` API tests | 53 |
| `test-helpers.ahk` | Shared helpers (`Log`, `Chk`, `DumpNode`) — not run directly | — |

## Fixture files

`PasteAsMd_*.log` files contain debug captures from real clipboard pastes (or
lorem-ipsum stand-ins where content is private).  Each log has two sections
decoded by the fixture runner:

- `1. plain (A_Clipboard minus CR)` — raw plain-text clipboard content
- `2. cfHtml (raw full payload)` — full CF\_HTML clipboard format

`PasteAsMd_*.expected.md` files are the expected markdown output for each fixture.
`PasteAsMd_*.actual.md` files are generated at test time and excluded from git.

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
