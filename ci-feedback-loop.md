# Directed CI Feedback Loop

This document describes how to use a **directed** CI feedback loop for bug
fixes and feature implementation.  It applies to all coding tasks regardless
of language, project, or test framework.

## The Two Loops

**Undirected loop** (commit → observe → fix):
Commit code, wait for CI, read the failure, fix one symptom, repeat.  Works,
but each round only addresses what CI reported — not necessarily the root
cause.  Churn accumulates as adjacent root causes surface one by one.

**Directed loop** (diagnose → test → implement → done):
Trace the root cause *before* touching any code.  Write one test that
captures exactly the broken mechanism.  Implement the minimal fix.  Done in
one round.

**Core rule: iteration count is proportional to diagnosis depth.**
A shallow diagnosis (read the error message, guess a fix) produces many
iterations.  A deep diagnosis (trace the execution path to the specific line
that causes the failure) produces one.

## Workflow

### 1. Diagnose the root cause in full

Before writing a test or a fix:

- Trace the execution path from the symptom to the root cause.
- Identify the specific method, condition, or line responsible.
- State the root cause in **one sentence** before touching any file.

Do not write a test against a symptom.  A symptom test can pass even when the
root cause is still present (if the symptom changes) or fail for the wrong
reason (if the symptom manifests differently).  Test the mechanism.

**Example:** "The word cursor falls back to fragment-level because
`TryCreateWindowsMediaBookmarkBoundaries` declares failure when
`!observed.SequenceEqual(expected)` — even when partial coverage is
sufficient — causing `EngineWordTrackingUnavailable` to set
`_activeHighlightMode = Fragment`."

### 2. Write the smallest failing test that captures the broken mechanism

Choose the test type that most directly exercises the identified mechanism:

- **Behavioral (reflection/instantiation)**: preferred.  Invokes the actual
  production code path and asserts the expected behavior.  Hardware-independent
  paths must use this form.
- **Source-inspection**: acceptable when the path requires live hardware
  (TTS synthesis, audio device, UI framework) and cannot run in a headless
  test.  Inspect structural invariants — that the failing guard has been
  removed or qualified, that the logging call exists, etc.
- **Integration/system**: use when the bug spans multiple components and a
  unit-level test cannot prove the cross-component contract.

Before writing, confirm the test will fail specifically because of the
identified root cause — not because of a setup error or an unrelated guard.

### 3. Run the test: confirm FAIL

Run the test against unmodified code and verify:

- The test fails.
- The failure message cites the broken mechanism you identified — not a
  different failure, not a test infrastructure error.

If the test passes on unmodified code, the test does not prove the bug.
Correct the test before proceeding.

### 4. Implement the minimal fix

Write only enough code to satisfy the failing test.  Do not add speculative
error handling, fallbacks, or adjacent improvements unless a separate failing
test requires them.

### 5. Run the test: confirm PASS

Run the same test against the fixed code and verify it passes.  Also run the
full test suite to confirm no regressions.

### 6. Commit on explicit instruction only

Stop when the work is done.  Wait for an explicit commit instruction.
"Continue" or "go ahead" authorizes work, not a commit.

## Why this works

The directed loop is faster because the bottleneck is almost never the build
or test run — it is the gap between *what* failed and *why*.  Spending two
minutes tracing the root cause before writing code eliminates the most
expensive CI round-trips.

The undirected loop generates churn: each iteration fixes one symptom CI
reported, leaving adjacent root causes intact until they surface in a later
round.

## Quick checklist (before writing a single line of code)

- [ ] I can name the specific method/condition/line that is wrong.
- [ ] I have stated the root cause in one sentence.
- [ ] My planned test targets the mechanism, not the observable symptom.
- [ ] I know which test type to use (behavioral, source-inspection, or
      integration) and why.
