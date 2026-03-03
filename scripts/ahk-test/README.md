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
| `test-paste-md-fixtures.ahk` | End-to-end fixture tests: reads `PasteAsMd_*.log`, converts, compares `*.expected.md` | 100 |
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
