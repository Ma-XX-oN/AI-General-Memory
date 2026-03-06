# Workflow Guidance for Codex

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
3. Run dependent operations sequentially and verify each step.
4. For long-running commands, capture output once to a log and inspect the log.

## Commit Workflow (PowerShell)

1. Use Conventional Commit format for every commit.
2. Keep commit body bullet lines contiguous (no blank separators between bullets).
3. Avoid Markdown backticks in `git commit -m` strings in PowerShell.
4. Use a process-scoped commit message file in `%TEMP%` by parent PID:
   - `%TEMP%\codex-commit-msg-<PARENT_PID>.txt`
5. Use a stable commit command shape:
   - `git commit -F (Join-Path $env:TEMP ("codex-commit-msg-" + (Get-CimInstance Win32_Process -Filter "ProcessId=$PID").ParentProcessId + ".txt"))`
6. Do not store transient commit message files in repos.
