# Workflow Guidance

This file captures global default workflow rules for test-driven delivery and
for reducing repeated command-approval prompts which will slow or halt your
progress. These defaults apply to all projects unless a project-specific
`AGENTS.md`/`CODEX.md` rule overrides them.

## TTD Rules

1. Before refactor or new development, agree to expected behavior and test scope.
2. Define stable unit and system/integration test commands before coding.
3. Keep at least one replayable capture path (fixture/log recording) so
   unexpected behavior can be turned into direct regression tests.
4. Run agreed tests at the end of each stage and before commit.
5. Run test commands separately (parallel is fine when independent).
6. After tests finish, report concise results and call out failures/regressions.
7. If expectations or golden outputs need to change, agree to that change first.

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

   If PowerShell is unavailable the script exits 1 with an error message —
   fall back to a fixed path (`/tmp/claude-commit-msg.txt`) in that case.
4. **Write the commit message** using the Write tool (no approval needed):
   - Write tool path: `/tmp/claude-commit-msg-<SESSION_PID>.txt`
   - The Write tool maps `/tmp` → `C:\tmp`; git requires the Windows form.
5. **Stable commit command** (approve-once eligible with prefix `git commit -F C:/tmp/claude-commit-msg-`):

   ```bash
   git commit -F C:/tmp/claude-commit-msg-<SESSION_PID>.txt
   ```

6. Do not store transient commit message files in repos.

## Commit Workflow (PowerShell)

Rules 5–7 exist specifically to produce a **stable commit command string** that
never changes between commits.  A fixed command string can be pre-approved once
by the user and reused without triggering a new approval prompt each time.
Embedding the message inline (e.g. `-m "..."` or a heredoc) makes every commit
command unique, defeating pre-approval.

1. Use Conventional Commit format for every commit.
2. Keep commit body bullet lines contiguous (no blank separators between bullets).
3. Avoid Markdown backticks in `git commit -m` strings in PowerShell.
4. Resolve the stable session PID once at the start of a commit sequence:
   - `$sessionPid = & "$env:CODEX_HOME/scripts/session-pid.ps1"`
   - If this fails, use a fixed fallback filename for this commit sequence:
     `$commitMsgPath = Join-Path $env:TEMP "codex-commit-msg.txt"`
5. Use a session-scoped commit message file in `%TEMP%`:
   - Primary path: `$commitMsgPath = Join-Path $env:TEMP ("codex-commit-msg-" + $sessionPid + ".txt")`
6. Use a stable commit command shape:
   - `git commit -F $commitMsgPath`
7. Do not store transient commit message files in repos.
