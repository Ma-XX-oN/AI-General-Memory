# File Header Documentation Style

File-level doc comments (the `/** @file ... */` block or equivalent) must
follow a **reader-first** style.  The goal is a compact reference entry a
reader can scan cold.

## C++ Doxygen block

For C++ files, the block opens like this — two lines, never a one-liner:

```cpp
/**
 * @file filename.ext
 * @author Author Name (email@example.com)
 * @brief One-line summary of the file.
 * @version 0.1
 * @date YYYY-MM-DD
 * @copyright Copyright (c) YYYY
```

`@brief` is the lead sentence — never write a separate paragraph that
restates it.

### Synopsis paragraph

An optional prose block placed between `@copyright` and `## Overview`.
Use it when there is cross-cutting context a reader needs before scanning
the bullet list: non-obvious invariants, design trade-offs, usage
constraints, or relationships between symbols that the bullet list can't
capture.

```cpp
 * @copyright Copyright (c) 2026
 *
 * Synopsis prose goes here.  Keep to 3–6 lines.  Every sentence must name
 * at least one real symbol, type, or file from this codebase.
 *
 * ## Overview
```

Omit when `@brief` already says everything a cold reader needs.

## Sections

Sections appear in this order; all are optional except `## Overview`.
Every section heading must be followed by a blank ` *` line.

1. **`## Overview`** — Bullet list of the public symbols the file provides.
   Each bullet names the real type or function with its full template
   signature when relevant, then says what it does for the caller.

   **Bullet format — two lines, with blank separator:**

   ```cpp
    * - `TypeName<T, U>`
    *
    *   What the caller uses it for, written from the caller's perspective.
   ```

   Use 3 spaces of indentation after ` * ` for the description continuation.
   Never put the symbol and its description on the same line.

2. **`## Usage`** — Numbered steps for the caller.  Every step names the
   actual function or type involved.  Omit for pure utility headers where
   there is no meaningful call sequence.

3. **`## Call shape`** — Arrow-chain or indented hierarchy showing the
   invocation path and/or stack position (what calls in from above, what
   this calls below).  Prefer the compact arrow-chain style.  Omit for
   standalone utility files.

4. **`## Deep Dive`** — Non-obvious invariants or mechanics a reader of
   the public API would not expect.  Omit freely; do not fill with facts
   already implied by the type names.

5. **`@see`** — Cross-references to directly related files.

## Formatting rules

- **Lines ≤ 78 characters** (including the leading ` * ` prefix).
- **Blank ` *` line after every `## Heading`.**
- **No em-dashes (`—`) in doc blocks.**
  Use two hyphens (`--`) or rephrase the sentence.
- The `/** @file` opener always occupies its own line; `@file filename` is
  always the second line.  Never compress to a single-line `/** @file ... */`.

## Content rules

- Never open with refactor history, original authorship narrative, or
  implementation defensiveness.
- Keep content local to the file's responsibility — no commentary that
  belongs in a commit message or PR description.
- Define any jargon terms (e.g. "lowering", "emitted form") in the
  synopsis or `## Overview`, not buried in function docs.
- **The single most important rule:** every sentence must contain at least
  one real name — a type, function, template parameter, constant, or file
  name from this codebase.  A sentence that could apply to any C++ file
  belongs in a style guide, not a file doc.  The primary failure mode is
  sections that look structured but contain no specific facts: *"call the
  entry point and feed the result to higher-level code"* says nothing.

## Verification pass

After writing or editing a doc block, do a second pass to catch errors
before committing.  For every symbol named in the block:

1. **Grep for the exact name** in the file's implementation.  Zero matches
   means the name is wrong or the symbol lives in another file.  Common
   failure modes:
   - Wrong function name (e.g. `validate_argument_pack` vs
     `validate_arguments`).
   - Nonexistent symbol (e.g. `drain_all()` or `make_span()` that was
     never implemented).
   - Symbol from the wrong file (e.g. listing `EnumSettings` in
     `enum_core.hpp` when it is defined in `enum_builder.hpp`).
2. **Check template parameters** match the actual signature in count and
   name (e.g. `Foo<BlockT, IndexT, PoolSize>` is three params, not two).
3. **Confirm `@see` paths** point to files that actually exist and are
   not self-references to the current file.

This pass takes under a minute and has caught many errors that would
otherwise silently mislead future readers.
