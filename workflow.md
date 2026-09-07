# Workflow Guidance

This file captures global default workflow rules for test-driven delivery and
for reducing repeated command-approval prompts which will slow or halt your
progress. These defaults apply to all projects unless a project-specific
`AGENTS.md`/`CODEX.md` rule overrides them.

## TTD Rules

1. Before any substantive bug fix, refactor, or new development, agree to the
   expected behaviour and test scope.
2. Before coding, enumerate every affected production entry point and consumer,
   especially when a changed contract crosses module, process, repository, or
   application boundaries. Do not assume one component test represents all
   consumers.
3. Define the real user-visible production acceptance path and write its
   acceptance/regression test before implementation. The test must exercise the
   actual behaviour-producing entry point where feasible, not only a helper or
   lower-level component that is expected to be equivalent.
4. Run that acceptance test before the fix and require it to fail for the exact
   intended defect. If it passes, the test does not prove the bug and must be
   corrected before implementation begins.
5. Keep stable unit and system/integration test commands in addition to the
   production-path acceptance test. Component and unit tests are necessary but
   do not substitute for production-path acceptance when behaviour crosses a
   contract boundary.
6. Keep at least one replayable capture path (fixture/log recording) so
   unexpected production behaviour can be turned into a direct regression test.
7. Implement only after the failing acceptance proof exists, then run the same
   exact acceptance test after the change and require it to pass.
8. Run the broader agreed unit, integration, build, packaging, and deployment
   checks at the end of each applicable stage and before commit/completion.
9. Never mark an issue, checklist item, phase, or task complete, and never close
   an issue, until every acceptance criterion has direct test or verification
   evidence and the required tests have passed against the final deliverable.
10. If a required acceptance test cannot be automated or executed in the current
    environment, do not claim completion. Obtain explicit user verification; if
    the work must move to another capable environment/conversation, provide a
    fenced copyable prompt containing the exact verification task and criteria.
11. Run test commands separately (parallel is fine when independent).
12. After tests finish, report concise results and call out failures/regressions.
13. If expectations or golden outputs need to change, agree to that change first.

## Approval-Friction Reduction

1. Prefer smaller independent commands and already-approved prefixes; split
   multi-step work into separate commands (parallel when independent) to reduce
   approval prompts and speed up workflow.
2. Keep command shapes stable across runs (same ordering/quoting/flags unless
   required) and avoid ad-hoc variants that trigger new approvals.
3. **Issue each command as its own tool call — never chain commands with `&&`,
   `;`, or `|` unless the whole pipeline was already approved as a unit.**
   Chaining changes the command string, making it a new unapproved shape even
   if each individual part was previously approved.
4. Run dependent operations sequentially and verify each step.
5. For long-running commands, capture output once to a log and inspect the log.
6. Be aware that commands that run freely inside the sandbox can become much
   stricter when they must run outside it. For outside-sandbox workflows, keep
   command shapes stable and keep transient helper files out of repos so their
   creation and cleanup do not trigger extra approval prompts.

## Commit Workflow (Bash / Claude Code)

Same motivation as the PowerShell section below: write the message via a
file so the `git commit -F` command string is stable and approve-once eligible.

1. Use Conventional Commit format for every commit.
2. Keep commit body bullet lines contiguous (no blank separators between bullets).
3. **Resolve the session PID once** at the start of any commit sequence
   (must be **sourced**, not executed — executing breaks the process chain):

   ```bash
   . ~/.claude/scripts/session-pid.sh
   ```

   The script **prints** the PID to stdout (e.g. `11032`).  It does **not**
   set a `SESSION_PID` shell variable — `$SESSION_PID` will always be empty.
   Read the printed number from the Bash tool output and substitute it
   literally into the steps below.

   If PowerShell is unavailable the script exits 1 with an error message —
   fall back to a fixed path (`/tmp/claude-commit-msg.txt`) in that case.
4. **Write the commit message** using the Write tool (no approval needed):
   - Write tool path: `/tmp/claude-commit-msg-<PID>.txt`
     (where `<PID>` is the number printed in step 3)
   - The Write tool maps `/tmp` → `C:\tmp`; git requires the Windows form.
5. **Stable commit command** (approve-once eligible with prefix `git commit -F C:/tmp/claude-commit-msg-`):

   ```bash
   git commit -F C:/tmp/claude-commit-msg-<PID>.txt
   ```

6. Do not store transient commit message files in repos.

## Commit Workflow (PowerShell)

Rules 5–7 exist specifically to produce a **stable commit command string** that
never changes between commits.  A fixed command string can be pre-approved once
by the user and reused without triggering a new approval prompt each time.
Embedding the message inline (e.g. `-m "..."` or a heredoc) makes every commit
command unique, defeating pre-approval.

1. Use Conventional Commit format for every git commit message.
2. Keep commit body bullet lines contiguous (no blank separators between bullets).
3. Avoid Markdown backticks in `git commit -m` strings in PowerShell.
4. Use a session-scoped commit message file in `%TEMP%`:
   - Primary path: `$commitMsgPath = Join-Path $env:TEMP ("codex-commit-msg-" + $env:CODEX_THREAD_ID + ".txt")`
5. Use a stable commit command shape:
   - `git commit -F $commitMsgPath`
6. Do not store transient commit message files in repos.
7. Reason for rules 4-6: a temp file under `%TEMP%` avoids repository writes for
   commit-message plumbing. That matters because sandboxed git commands may work
   with little friction, while outside-sandbox commands are stricter about
   approval shape and cleanup side effects.
