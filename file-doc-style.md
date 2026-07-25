# File Header Documentation Style

File-level doc comments (the `/** @file ... */` block or equivalent) must
follow a **reader-first** style.  The goal is a compact reference entry a
reader can scan cold.

## C++ Doxygen block

For C++ files, the block opens with Doxygen tags:

```
@file, @author, @brief (one-line summary), @version, @date, @copyright
```

`@brief` is the lead sentence — never write a separate paragraph that
restates it.  Only add an expansion paragraph (placed between the tags and
the first section) when the `@brief` can't fit required conceptual
framing — for example, a "what to know first" note about a non-obvious
invariant or an independence between two configuration axes.

## Sections

Sections, in order (all optional except `## Overview`):

1. **`## Overview`** — Bullet list of the public symbols the file provides.
   Each bullet names the real type or function with its full template
   signature when relevant, then says what it does for the caller.  Format:
   ```
   - `TypeName<T, U>` — what the caller uses it for.
   ```
   Write from the caller's perspective, not the implementation's.

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

## Rules

- Never open with refactor history, original authorship narrative, or
  implementation defensiveness.
- Keep content local to the file's responsibility — no commentary that
  belongs in a commit message or PR description.
- Define any jargon terms (e.g. "lowering", "emitted form") in the
  expansion paragraph or `## Overview`, not buried in function docs.
- **The single most important rule:** every sentence must contain at least
  one real name — a type, function, template parameter, constant, or file
  name from this codebase.  A sentence that could apply to any C++ file
  belongs in a style guide, not a file doc.  The primary failure mode is
  sections that look structured but contain no specific facts: *"call the
  entry point and feed the result to higher-level code"* says nothing.
