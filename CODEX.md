# Global Notes for Codex

## Working Rules

- If the user says to "remember" something, store project-specific rules in the project's `CODEX.md`. Store cross-project rules in `~/.codex/CODEX.md`, generalized when possible.
- For Conventional Commit messages with detail lines, format details as bullet points with no blank lines between bullets.
- When composing git commit bodies with bullet detail lines, generate contiguous bullet lines with no blank separator lines (for example avoid multiple `-m` paragraphs that insert empty lines).
- In PowerShell, never place Markdown backticks inside git commit -m strings; use plain text, single-quoted -m values, or git commit -F with a here-string to avoid escape-related character loss.
- Always use Conventional Commit format for every git commit message.
- For each user question/task: capture `START` before the first action; the first successful `START` capture is immutable for that turn (never overwrite it on retries), capture `END` immediately before sending the final response, and report `ELAPSED` as real wall-clock turn time.
- When a user asks a direct question, answer it before making any code or documentation modifications.
- For timing capture, use one `Get-Date -Format o` at start and one `Get-Date -Format o` at end per turn; if multiple start captures exist, use the earliest successful timestamp as `START`; do not use `pid-timer.ps1`, PID-based timers, or user environment-variable timing state.
- Compute elapsed from those two timestamps in the response text only; do not run extra timing/calculation commands.
- Report timing in a fenced code block with exactly these lines: `START=...`, `END=...`, `ELAPSED=...`.
- Format `ELAPSED` as `m:ss.fff` (minutes, colon, zero-padded seconds with milliseconds), for example `ELAPSED=1:07.532`.
- Preserve each file's existing line endings (CRLF/LF) when editing; do not change line endings unless explicitly requested.
- Before editing any file, check its line-ending status; if mixed, notify before editing and abort; if non-mixed, keep all edits consistent with the original style.
- For any non-mixed file, after editing, every line must still use that original line ending style; if that cannot be guaranteed, normalize to the original style and report.
- For PowerShell workflows, use `~/.codex/scripts/show-eol.ps1` (detect) and `~/.codex/scripts/normalize-eol.ps1` (normalize) with an explicit target EOL (`CRLF` or `LF`) instead of ad-hoc EOL commands.
- For non-PowerShell workflows, use `~/.codex/scripts/show-eol.pl` (detect) and `~/.codex/scripts/normalize-eol.pl` (normalize) instead of ad-hoc EOL commands.
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
- For any command execution, prefer already-approved command prefixes; if a required action is not covered, request scoped escalation first instead of running an ad-hoc variant.
- Before running build/test/tool commands, perform an execution-rule preflight: identify applicable project/global `CODEX.md` command prerequisites and include them directly in the command line/environment.
- For CMake builds/tests in workspace repos, check `.vscode/settings.json` and `CMakePresets.json`/`CMakeUserPresets.json` first and mirror those settings; use manual command lines only when those sources are absent or the user explicitly overrides them.
- For CMake workflows, never run configure and build concurrently; run them sequentially (`cmake -S/-B` then `cmake --build`) to avoid regenerate/build race conditions.
- For build/linker mismatch triage, follow `~/.codex/build_issues.md` before ad-hoc fixes.
- For file edits, use approved editing tools and keep one consistent editing method per session/task unless explicitly asked to change.
- For file edits, use patch-style edits only; do not use whole-file rewrite commands.
- For EOL detection, use `rg` and keep one consistent `rg` method unless explicitly asked to change.
- Universal rule: for repeated tasks, use one approved method consistently and do not switch variations unless explicitly requested.
- Use definitive language when facts are certain; if uncertain, state uncertainty explicitly.
- For timing output in chat responses, always use a fenced code block (not inline/backtick list items) to prevent webview auto-link artifacts.
- Before sending any response, run a definitiveness pass to remove unjustified hedging and use direct language for confirmed facts.
- In Markdown text, when you DO NOT intend the literal sequence `>=`, write it with whitespace as `> =` to prevent auto-conversion to `≥`.
- For any question about current file contents, perform a fresh read of the target file in the same turn before answering; do not answer from cached context alone.
- When asked to re-review ("anything else?", "check again"), do a fresh pass instead of assuming prior checks were exhaustive.
- When fixing one item in a repeated pattern/group, check sibling occurrences and update them together unless the user explicitly limits scope.
- Prefer public APIs when fixing external library usage; avoid bypassing behavior by calling private/internal APIs directly unless you are working inside that library.
- If a fix is not working after 2-3 attempts, stop and summarize: goal, attempts tried, blocker, and ask the user to collaborate on next steps.
- If the user says STOP, stop immediately, answer the question directly, and do not retry the blocked action in any form (including variants or reworded permission prompts) unless the user explicitly asks to resume.
- If the user denies an authorization request and gives a reason, do not repeat the same request or a semantic variant; change approach to directly address the stated reason first.
- Question assumptions that appear incorrect or unclear before implementing them.
- For long-running commands (builds/tests), capture output to a log once, then inspect the log instead of rerunning only to view different sections.
- When maintaining files under `~/.codex/`, read `~/.codex/README.md` first and keep related index/reference entries consistent.
- For any edit under `~/.codex/`, run a hard preflight before changing files: read `~/.codex/README.md`, verify target-file tracking with `git -C ~/.codex ls-files -- <path>` and `.gitignore`, check EOL style, and do not edit until all checks pass.
- For OpenSCAD JS documentation, require JSDoc on public symbols and use `@slot`/`@deref` plus full `@type` docs for slot-based constants/typedefs.
- For GitHub markdown docs, avoid raw `<svg>` tags and sanitize punctuation-heavy anchors when generating intra-doc links.
- For non-trivial diagrams where layout precision matters, prefer an ASCII-first draft and then convert to SVG; avoid relying on Mermaid auto-layout for final authoritative diagrams.
- When editing diagrams, preserve graph semantics and local associations (connectivity, arrow targets, neighboring relationships) while moving elements; do not optimize a single element in isolation.
- For SVG diagram styling, use class/token-based semantics and redundant encodings (color plus line-style/weight) so meaning remains clear under color-vision deficiencies and grayscale.

## Useful Patterns

- [Generalized bracketed-text regex](regex-patterns.md#generalized-bracketed-text-matching)
- [Regex patterns reference](regex-patterns.md)

## Operational References

- [Build issue triage guide](build_issues.md)
- [Testing guidelines](testing.md)
- [Codex home README (memory file maintenance conventions)](README.md)

## Design Lessons

- Generalize before optimizing: extract domain-specific parsing into a reusable spec API.
- Put shape in data, not code: declare parameters/defaults once, reuse everywhere.
- Keep semantics separate from structure: helper normalizes shape; caller validates meaning/types.
- Prefer explicit canonical outputs (fixed slots plus variadic tail) over ad-hoc branching.
- Preserve diagnostics while simplifying APIs: keep provenance internally and caller API simple.
- Make defaults declarative in spec definitions instead of scattering defaults in function bodies.
- Extend capability only for real use-cases (for example a named variadic block) and keep scope narrow.
- Use clear namespace/type names that read naturally at call sites.
- Treat documentation and examples as part of correctness, not optional polish.
- Verify incrementally with build/tests during refactors to preserve behavior.
- Never run build and tests concurrently; always complete build first, then run tests.
