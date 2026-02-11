# Global Notes for Codex

## Working Rules

- Regex debugging: test quantifier behavior (`*`, `+`, `?`) on the first concrete match/counterexample before considering line-ending or engine-specific explanations.
- If the user says to "remember" something, add it to the project's `CODEX_PROJ.md`; if it is a rule that applies generally, add it to `~/.codex/CODEX.md`.
- For Conventional Commit messages with detail lines, format details as bullet points with no blank lines between bullets.
- Always use Conventional Commit format for every git commit message.
- For each user question/task: capture start time before doing work, capture end time after completion, and report elapsed time in minutes and seconds.
- For timing, use a stable timer file workflow (write start time to a fixed file, then read it later) rather than embedding changing timestamp literals in command strings.
- Preserve each file's existing line endings (CRLF/LF) when editing; do not change line endings unless explicitly requested.
- Before editing any file, check its line-ending status; if mixed, notify before editing and abort; if non-mixed, keep all edits consistent with the original style.
- For any non-mixed file, after editing, every line must still use that original line ending style; if that cannot be guaranteed, normalize to the original style and report.
- Do independent transformations first; do dependent or lossy transformations last.
- Preserve semantic meaning before simplifying representation.
- Encode invariants in code (for example, matching open/close tags with backreferences) rather than relying on assumptions.
- Be exact with language/tool syntax and escaping rules.
- Back implementation claims with verifiable outputs (counts/diff/line references), not assertions alone.
- Do not change code unless the user explicitly asks for code changes.
- In debugging/explanations, state the single minimal root cause first (one sentence), then show the exact line-level behavior causing it before any secondary context.
- For file and text reads, always use `rg`
- Do not use custom script workflows when an approved command set can do the job.
- Never use custom file-read utilities when `rg` can be used.
- For simple checks, use only `rg` or already-approved command prefixes; avoid ad-hoc command strings that trigger approval prompts.
- For file edits, use approved editing tools and keep one consistent editing method per session/task unless explicitly asked to change.
- For EOL detection, use `rg` and keep one consistent `rg` method unless explicitly asked to change.
- Universal rule: for repeated tasks, use one approved method consistently and do not switch variations unless explicitly requested.
- Use definitive language when facts are certain; if uncertain, state uncertainty explicitly.
- For timing output in chat responses, always use a fenced code block (not inline/backtick list items) to prevent webview auto-link artifacts.
- Before sending any response, run a definitiveness pass to remove unjustified hedging and use direct language for confirmed facts.
