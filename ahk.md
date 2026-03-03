# AutoHotkey v2 Notes

## Running AHK scripts from Git Bash (MSYS2/Cygwin)

**Git Bash converts `/Switch` arguments to paths.**  Windows-style CLI
switches like `/ErrorStdOut` get silently rewritten to paths like
`C:\ErrorStdOut`.  Never pass them from Git Bash.

- Use the `#ErrorStdOut` **directive inside the script** instead of
  `/ErrorStdOut` on the command line.
- Run scripts with:
  `'C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe' 'script.ahk' 2>&1`

**`/tmp` in Git Bash** maps to `C:\Users\<user>\AppData\Local\Temp`
(confirmed via `cygpath -w /tmp`), **not** `C:\tmp`.  Pass the Windows
path — obtained with `cygpath -w /tmp` — when invoking Windows programs
that need a Windows path.

## String literals

- Backtick (`` ` ``) is the escape character.
- `` `` `` = literal backtick; `` `n `` = newline; `` `r `` = CR;
  `` `t `` = tab; `` `" `` = literal `"` (does **not** close the string).
- **The `` `" `` trap:** `` "```python" `` is parsed as `` `` `` (literal
  backtick) + `` ` `` (starts escape) + `` " `` (literal `"` — string does
  NOT close here) → the string never closes → compile error "Missing `"`".
- **Use `Chr(96)`** to build backtick strings in tests and generated code:
  `fence3 := Chr(96) Chr(96) Chr(96)` — three backticks, zero escape issues.

## Concatenation

- `.` is the explicit concatenation operator but **not required** — space
  between two expressions also concatenates: `"abc" var` = `"abc"` . var.
- `.` is mainly useful for **line continuation** at end of line.

## Continuation sections

- `)` closes a continuation section when it appears at the **start of a line**
  (leading whitespace ignored).
- Escape as `` `) `` to include a literal `)` in the string content.
- Multi-line string example:
  ```ahk
  str := "
  (
    content
  )"
  ```

## Other pitfalls

- `FileAppend s, "*"` requires an attached console; write to a file path instead.
- `#ErrorStdOut` directive → compile errors go to stderr, no dialog.
- Fat arrow `f(m, *) => expr` required for global functions (single-line `{ }` fails).
