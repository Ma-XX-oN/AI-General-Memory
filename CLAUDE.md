# Global Notes for Claude

## Memory management

When asked to remember something, place **general knowledge** (applicable to
any project) here in `~/.claude/CLAUDE.md` or its referenced files.  Place
**project-specific knowledge** in the project's own `CLAUDE.md`.  When
possible, distill project-specific lessons into general principles and store
them here.

When adding a new file to `~/.claude/`, also add a `!filename` entry to
`~/.claude/.gitignore` (which uses a deny-all `*` with explicit exceptions)
so the file is tracked by the `~/.claude/` git repo.

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
the call site first.

### Read and understand code before writing tests

Before writing tests for any function:

1. **Read the actual function** - look at its signature, parameters, and implementation.
2. **Verify the function exists** - don't invent APIs that aren't there.
3. **Understand the behavior** - trace through the code to know what it actually does.

Writing tests without reading the code results in:

- Tests for imaginary function signatures
- Tests that call functions with wrong argument counts
- Tests that assert behavior the function doesn't have

This is unacceptable. Own the mistake directly - don't use vague language like
"someone thought" to deflect blame for code you wrote.

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

### Offensive programming and testing strategy

When a project uses offensive programming (all input assumed safe and trusted,
with assertion guards solely to catch developer misuse):

- **Do not** write tests that intentionally trigger assertion guards.  A test
  that hits an assert is a buggy test, not a valid error-handling test.
- Tests should only exercise **valid usage paths**.
- When auditing assertion guards, check that they exist where they should and
  that their conditions make sense — not that they can be bypassed or toggled.

**OpenSCAD:** Guards are named `verify_*` and exist solely to tell developers
when they've used a function incorrectly.

### GitHub markdown rendering

- GitHub strips `<svg>` tags from markdown for security.  Use Unicode
  characters (e.g. ☰) or plain text instead.
- GitHub does not reliably link to anchors containing colons or URL-specific
  punctuation.  Sanitize anchors via `sanitize_anchor_id()`:
  colons become `__`, spaces and other URL punctuation become `_`.

## Useful Patterns

- [Generalized bracketed-text regex](regex-patterns.md#generalized-bracketed-text-matching)

## Time tracking (every prompt)

For **every** prompt — questions, coding tasks, research, all of them:

1. At the very start of your response, get the current time and output it.
2. At the very end of your response, get the current time and output it.
3. Output the elapsed time (minutes and seconds) between start and end.
