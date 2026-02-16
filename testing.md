# Testing Guidelines

## Read and understand code before writing tests

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

## Offensive programming and testing strategy

When a project uses offensive programming (all input assumed safe and trusted,
with assertion guards solely to catch developer misuse):

- **Do not** write tests that intentionally trigger assertion guards.  A test
  that hits an assert is a buggy test, not a valid error-handling test.
- Tests should only exercise **valid usage paths**.
- When auditing assertion guards, check that they exist where they should and
  that their conditions make sense — not that they can be bypassed or toggled.

**OpenSCAD:** Guards are named `verify_*` and exist solely to tell developers
when they've used a function incorrectly.

## Always run tests after writing code or tests

Never declare work done without executing the relevant tests and confirming
they pass.  This applies to both sides: when writing tests, run them to verify
the expected outputs are correct; when writing or modifying code, run the
existing tests to verify the code works.
