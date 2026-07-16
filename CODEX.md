# Global Notes for Codex

## Working Rules

### Memory Placement

- If the user says to "remember" something, store project-specific rules in the project's `CODEX.md`. Store cross-project rules in `~/.codex/CODEX.md` as global defaults that apply to all projects unless overridden locally.
- If the user says to store something in "your memory", store it only in Codex global memory (`~/.codex/CODEX.md`, or the configured `$CODEX_HOME/CODEX.md`). Do not store it in project-local memory, `.claude`, or any other tool's memory file.

### Commit Messages And Timing

- For Conventional Commit messages with detail lines, format details as bullet points with no blank lines between bullets.
- When composing git commit bodies with bullet detail lines, generate contiguous bullet lines with no blank separator lines (for example avoid multiple `-m` paragraphs that insert empty lines).
- In PowerShell, never place Markdown backticks inside git commit -m strings; use plain text, single-quoted -m values, or git commit -F with a here-string to avoid escape-related character loss.
- In PowerShell, never pass `$variables` intended for an inner `pwsh -Command` through an outer double-quoted command string; use a temp message file or a single-quoted inner command, and verify the resulting commit subject with `git log -1 --pretty=%s` after commit/amend.
- Always use Conventional Commit format for every git commit message.
- For each user question/task: capture `START` before the first action; the first successful `START` capture is immutable for that turn (never overwrite it on retries), capture `END` immediately before sending the final response, and report `ELAPSED` as real wall-clock turn time.
- When a user asks a direct question, answer it before making any code or documentation modifications.
- For timing capture, use one `Get-Date -Format o` at start and one `Get-Date -Format o` at end per turn; if multiple start captures exist, use the earliest successful timestamp as `START`; do not use `pid-timer.ps1`, PID-based timers, or user environment-variable timing state.
- Compute elapsed from those two timestamps in the response text only; do not run extra timing/calculation commands.
- Report timing in a fenced code block with exactly these lines: `START=...`, `END=...`, `ELAPSED=...`.
- Format `ELAPSED` as `m:ss.fff` (minutes, colon, zero-padded seconds with milliseconds), for example `ELAPSED=1:07.532`.
- After any push to origin from either `~/.codex` or `~/.claude`, immediately
  `git pull` in the other repo so both stay in sync with origin.

### File Integrity And EOL

- Always use `apply_patch` for manual file edits when that tool is available. Needing user approval does not change the editing method; ask for approval when required, but still prefer `apply_patch` over shell-based file writes. Use shell-based writing only when `apply_patch` truly cannot perform the edit.
- Preserve each file's existing line endings (CRLF/LF) when editing; do not change line endings unless explicitly requested.
- Before editing any file, check its line-ending status; if mixed, notify before editing and abort; if non-mixed, keep all edits consistent with the original style.
- For any non-mixed file, after editing, every line must still use that original line ending style; if that cannot be guaranteed, normalize to the original style and report.
- For PowerShell workflows, use `~/.codex/scripts/show-eol.ps1` (detect) and `~/.codex/scripts/normalize-eol.ps1` (normalize) with an explicit target EOL (`CRLF` or `LF`) instead of ad-hoc EOL commands.
- For non-PowerShell workflows, use `~/.codex/scripts/show-eol.pl` (detect) and `~/.codex/scripts/normalize-eol.pl` (normalize) instead of ad-hoc EOL commands.
- Never run EOL normalization and EOL inspection on the same file in parallel; run normalize first and inspect second, because `show-eol` can observe stale or mid-rewrite bytes during `normalize-eol`.
- Do independent transformations first; do dependent or lossy transformations last.
- Do not run dependent operations in parallel (for example `git add` -> `git commit` -> `git push`); run them sequentially and verify each step before starting the next to avoid order/race errors.
- Preserve semantic meaning before simplifying representation.

### Semantics, Scope, And Explanations

- Before adding machinery, indirection, or a preparatory workaround, run a simplification preflight: ask whether the planned extra step only exists to solve a problem that a more direct change would remove outright, and prefer the simpler fix when it preserves the actual design intent instead of solving side effects of your own added complexity.
- Prefer direct, representation-driven implementations over speculative policy or planning layers. Keep decision points close to the behavior they control, and introduce abstract classification frameworks only when repeated real cases prove they are needed.
- Reuse the real behavior-producing code paths instead of hand-reconstructing equivalent output when the representation already supports direct emission.
- Do not repeat checks for invariants already established by earlier control flow; keep the remaining path tight and obvious.
- Never add a silent no-op branch to a command-style or state-mutating function unless the contract explicitly defines a meaningful no-op case; if such a function receives invalid or degenerate input that would make it do nothing, treat that as a caller bug and reject/fail fast instead of quietly returning.
- In docs, specs, and checklists, restatement may emphasize an invariant but must not later weaken it (for example by calling a requirement optional); remove redundant wording that adds doubt without adding information.
- In commit messages, status notes, and TODOs, write for the future reader's decision-making: record current state, actionable next steps, or real risk; do not explain how the assistant created the situation unless that history materially changes action or meaning.
- Encode invariants in code (for example, matching open/close tags with backreferences) rather than relying on assumptions.
- Be exact with language/tool syntax and escaping rules.
- Back implementation claims with verifiable outputs (counts/diff/line references), not assertions alone.
- Do not change code unless the user explicitly asks for code changes.
- In debugging/explanations, state the single minimal root cause first (one sentence), then show the exact line-level behavior causing it before any secondary context.
- When introducing an alternate formalism, start with the user's primary operational model first, prove the mapping with trusted anchor cases, and label the formalism explicitly as a derived helper rather than the primary definition.
- Do not replace a user's working mental model with a mathematically equivalent abstraction until the correspondence is concrete and visible. Avoid overloaded terms like `weights` when the primary semantics are indexing, layout, or topology.
- For explanation-heavy restatements, use this checklist:
  1. State the primary model in the user's own terms.
  2. Show 2-3 anchor cases that force the mapping.
  3. Introduce any alternate notation only as a derived form.
  4. Say exactly what problem the alternate notation solves.
  5. Give one worked conversion both directions.
  6. Keep proof-oriented notation in the section where it is needed instead of promoting it to the whole system.

### Commands And Preflight

- For file and text reads, always use `rg`
- Do not use custom script workflows when an approved command set can do the job.
- Never use custom file-read utilities when `rg` can be used.
- When asked to search Codex or Claude transcripts/sessions, use the global Codex-home tool `~/.codex/scripts/AI-transcript.py` first instead of grepping raw transcript/session files directly. Treat it as a shared tool, not a project-local file, and do not search the current repo for it before using it.
- When a loaded memory/reference file points to another file (for example `~/.codex/...` or a relative Markdown link), resolve that path to an absolute path immediately using the referenced file's own base directory/home alias; do not reinterpret it relative to the current working directory.
- For simple checks, use only `rg` or already-approved command prefixes; avoid ad-hoc command strings that trigger approval prompts.
- For any command execution, prefer already-approved command prefixes; if a required action is not covered, request scoped escalation first instead of running an ad-hoc variant.
- Issue each command as its own tool call; do not chain with `&&`, `;`, or `|` unless that exact pipeline was already approved as one command shape.
- Before running build/test/tool commands, perform an execution-rule preflight: identify applicable project/global `CODEX.md` command prerequisites and include them directly in the command line/environment.

### Testing And Build Workflow

- For refactor or new development, agree expected behavior and the test plan before coding; if expectations change, re-agree before updating tests/fixtures.
- Tests must reflect semantics, not just code coverage. When a bug reveals that a type, API, boundary, or test shape is semantically wrong, prefer the clean semantic fix over the smallest local patch, even if the patch is quicker.
- For core semantic modules, freeze a short local contract before refactoring: identity, input-domain meaning, and mapping semantics. If any of the three is unsettled, stop and resolve it first.
- Before refactoring, cleanup, or optimization in a core semantic module, add or update at least one test that proves the intended semantic behavior, not just implementation self-consistency.
- For exactness-sensitive code, do not rely only on numerically friendly inputs such as powers of two, symmetric cases, or clean boundary values. Treat friendly cases as smoke tests, not proof, and include adversarial, odd, prime, or otherwise non-dyadic inputs early enough to expose representation and rounding problems.
- If correctness depends on exact identity, preserve exact provenance until the last possible moment, prefer exact-by-construction implementation paths over recomputation plus comparison, keep exact-identity and approximate-geometric APIs semantically separate, and do not collapse tests that appear textually similar until you confirm they are proving the same semantic claim.
- IMPORTANT! For global default TTD/testing/approval-friction workflow details (applies to all projects unless overridden locally), follow `~/.codex/workflow.md`.
- For CMake builds/tests in workspace repos, check `.vscode/settings.json` and `CMakePresets.json`/`CMakeUserPresets.json` first and mirror those settings; use manual command lines only when those sources are absent or the user explicitly overrides them.
- For CMake workflows, never run configure and build concurrently; run them sequentially (`cmake -S/-B` then `cmake --build`) to avoid regenerate/build race conditions.
- For build/linker mismatch triage, follow `~/.codex/build_issues.md` before ad-hoc fixes.
- In C++ tests and examples, prefer declaring variables immediately before first use rather than hoisting declarations to the top of the scope.
- In multi-stage C++ tests and examples, add short local comments that label setup or intent blocks so readers do not have to scan to the final assertion to understand the scenario.
- When extending a test area that already has a readable exemplar file, mirror that file's readability conventions for structure, local comments, and declaration placement unless the user asks for a different style.
- In constexpr-heavy C++ tests, prefer named `constexpr bool` scenario blocks with inline setup/intent comments over bare piles of `static_assert`s so each compile-time proof is readable without reconstructing the scenario from the final predicate.
- For every new test file, give each `constexpr` scenario block and each `TEST(...)` block a short local comment that states exactly what behavior it is proving before the assertions.
- Do not rely on helper names, test names, or long setup/helper sections alone to communicate test intent; the reader should not have to reconstruct the purpose from the assertions.
- When a new test file has substantial helper/setup code, add section comments that separate fixture-building helpers from the actual scenarios under test.

### Editing And Read Conventions

- For file edits, use approved editing tools and keep one consistent editing method per session/task unless explicitly asked to change.
- For file edits, use patch-style edits only; do not use whole-file rewrite commands.
- For EOL detection, use `rg` and keep one consistent `rg` method unless explicitly asked to change.
- For file-context reads, prefer anchor-based `rg -n "<anchor>" <file> -A/-B/-C` output over manual line-number enumeration filters because it is easier for users to read and for the assistant to write.
- If no stable anchor exists, use a two-pass `rg` workflow: first pass collects candidate line numbers (`rg -n`), second pass targets the selected line and prints context with `-A/-B/-C` (including piped `rg` forms) before falling back to manual line-number filters.
- Universal rule: for repeated tasks, use one approved method consistently and do not switch variations unless explicitly requested.

### Response Quality

- Use definitive language when facts are certain; if uncertain, state uncertainty explicitly.
- For timing output in chat responses, always use a fenced code block (not inline/backtick list items) to prevent webview auto-link artifacts.
- Before sending any response, run a definitiveness pass to remove unjustified hedging and use direct language for confirmed facts.
- For design and architecture questions, run a design-clarity preflight before answering: when the README or other design documents are clear, state the documented model directly and do not introduce hypothetical branches, alternate architectures, or conditional framing. Use conditional language only when the design documents are genuinely ambiguous, incomplete, or conflicting.
- Think before speaking: before answering, consider the user's actual runtime, operational constraints, and stated intent so you do not blurt out generic or context-blind conclusions.
- Ground recommendations in function/data semantics first; treat naming/style concerns as secondary unless the semantics are already settled.
- When a function or method parameter is intentionally unused, omit the parameter name in the declaration/definition instead of naming it and then silencing it with `(void)param;` or equivalent.
- For C++ code, run this unused-entity preflight before leaving a suppression in place: omit the parameter name when it is always unused, use `[[maybe_unused]]` when a parameter or local is only unused on some compile-time paths or in non-assert builds, and do not use `(void)x;` for unused-parameter suppression.
- In technical answers, explicitly separate confirmed facts from preferences/inference, and include the strongest counterargument before the final recommendation.
- If a recommendation changes, state the concrete new fact that caused the change.
- Once a direct question asks what something is and that answer is established, do not pad the reply with a follow-on list of what it is not unless the user explicitly asks for disambiguation.
- In Markdown text, when you DO NOT intend the literal sequence `>=`, write it with whitespace as `> =` to prevent auto-conversion to `≥`.
- For clickable local file references in chat responses on Windows, use Markdown links with a leading slash before the drive path, for example `[label](/c:/absolute/path/to/file.ext#L12)`.
- Before sending any Windows local file link, run a link-target preflight: the target must be the real absolute filesystem path (for example `/c:/...`), never the placeholder segment `/abs/path/`, and line anchors must use `#L12` form rather than `:12`.

### Troubleshooting And Guardrails

- For any question about current file contents, perform a fresh read of the target file in the same turn before answering; do not answer from cached context alone.
- If a required memory/reference file cannot be resolved or opened, stop and tell the user explicitly; do not silently ignore the missing reference or answer as if it had been loaded.
- When a script or test resolves output paths relative to its own location or executable location (for example via `A_ScriptDir`), treat logs and generated artifacts as worktree-specific; inspect the matching worktree/script directory instead of assuming the current shell's repo path.
- Do not misdiagnose worktree-relative or executable-relative output-path issues as sandbox problems; first verify the code's path-resolution rule and the fully resolved output path.
- When asked to re-review ("anything else?", "check again"), do a fresh pass instead of assuming prior checks were exhaustive.
- When fixing one item in a repeated pattern/group, check sibling occurrences and update them together unless the user explicitly limits scope.
- Prefer public APIs when fixing external library usage; avoid bypassing behavior by calling private/internal APIs directly unless you are working inside that library.
- If a fix is not working after 2-3 attempts, stop and summarize: goal, attempts tried, blocker, and ask the user to collaborate on next steps.
- If the user says STOP, stop immediately, answer the question directly, and do not retry the blocked action in any form (including variants or reworded permission prompts) unless the user explicitly asks to resume.
- If the user denies an authorization request and gives a reason, do not repeat the same request or a semantic variant; change approach to directly address the stated reason first.
- If a user reports a breakage, build failure, or behavior change and the evidence indicates it was not caused by the assistant's recent edits, say that explicitly, push back, and ask before modifying unrelated files or widening scope.
- Do not EVER touch the user's stuff without ASKING ABOUT IT FIRST. Always ask before touching their code, adjacent work, or active WIP beyond the exact scope they requested.
- Before making any edit outside the exact requested scope, stop and ask permission first. State the exact extra edit you want to make and why you think it is needed. Do not perform that extra edit unless the user explicitly approves it.
- If the apparent fix would require violating good coding practices or a clean architectural boundary, stop, tell the user exactly what the pressure is, and hash out a clean solution instead of implementing the bad shortcut.
- Question assumptions that appear incorrect or unclear before implementing them.
- For long-running commands (builds/tests), capture output to a log once, then inspect the log instead of rerunning only to view different sections.
- When maintaining files under `~/.codex/`, read `~/.codex/README.md` first and keep related index/reference entries consistent.
- For any edit under `~/.codex/`, run a hard preflight before changing files: read `~/.codex/README.md`, verify target-file tracking with `git -C ~/.codex ls-files -- <path>` and `.gitignore`, check EOL style, and do not edit until all checks pass.

### Documentation And Diagrams

- Never remove existing documentation or code comments without the user's explicit authorization. Documentation is preserve-by-default across all codebases.
- If an existing comment appears wrong, redundant, stale, or worth rewriting, preserve it first and ask before deleting, shortening, or replacing it with less detail.
- Before broad documentation or comment edits in an existing file, do a preflight comment audit against the current file so preserved documentation is not removed accidentally.
- In general documentation, avoid non-essential temporal/status phrasing such as "now", "currently", "before", or "previously"; state the invariant directly unless timeline context is the point (for example in a changelog).
- When closing a named namespace in code, write the closing comment in the form `// namespace Name`.
- For public API files, choose one recognized documentation standard before broad docstring work and use it while implementing, not as a later cleanup pass.
- HARD REQUIREMENT: for any code in a language that has a standard function documentation convention, every function and method must have a standard documentation block/docstring.  Here's a list of predefined docstring styles:
  - Python: NumPy-style
  - C/C++: doxygen
  - JavaScript: JsDoc
  - OpenSCAD: JsDoc variant. If unsure, ASK!
  - Other: Use prevailing standard.  If unsure, ASK!
- In Doxygen comments, when an `@brief` line wraps, indent continuation lines by two spaces after `*` (for example `*   continuation`), and align later paragraphs/tags back with the `@` column.
- In Doxygen comments, prefer real Doxygen cross-reference tags such as `@see`, `@sa`, and `@ref` over plain prose like "see ..." when you are pointing the reader at related APIs, types, or headers.
- If parameter meanings cannot be documented cleanly in the chosen standard, treat that as an unresolved API or semantic smell and stop to surface it before coding further.
- For API explanations and usage-oriented documentation, explain from the user's perspective first: start with what the user creates, names, and calls, then delay internal implementation details until later.
- Before editing or writing usage, operator, API, or README reference documentation, run a documentation preflight: classify the doc type first, then reject origin stories, personal motivation, historical background, refactor history, meta commentary, and phrases such as "what was known at the time" unless the user explicitly asked for history.
- For usage, operator, API, and README reference documentation, the opening must answer only the reader-first essentials: what this tool/file is, how to invoke or use it, what files or interfaces it reads/writes, and what the reader must know first. Do not let the opening drift into narrative background.
- For top-of-file file documentation and header overviews, write reader-first mini-reference docs: state what the file defines or owns first, then separate usage guidance from mechanics, use explicit section labels when they improve scanning (for example `Overview` and `Call shape`), and keep the content local to the file's actual responsibility instead of refactor history or meta commentary.
- For API explanations, prefer this structure when it fits the material: `Setup`, `Entry Point`, `Usage`, then `Explanation`, but treat it as a guide rather than a rigid template.
- In API explanations, introduce involved types and objects before later examples use them, and show the declaration, construction, or signature of the entry point before discussing implications.
- For simple APIs, collapse or omit explanation sections when the full structure adds ceremony without improving clarity, and merge `Entry Point` with `Usage` when separate sections would only repeat the same lesson.
- Prefer small complete examples over isolated fragments in API explanations, and explain relationships between objects through usage before describing internal mechanisms.
- Delay implementation details until after usage in reference-style explanations; for static tutorials where internal mechanism matters early, add a short `Note` or `See also` instead of letting the main flow become implementation-first.
- For APIs with multiple entry points or distinct modes, explain each variant separately instead of mixing unrelated cases together.
- In explanatory material, increase detail progressively: setup first, then basic usage, then more advanced usage, and only then internal mechanism.
- Choose example names at the right level of abstraction: keep reusable or generic components generic to the abstraction, and use domain names when the API itself is domain-specific.
- In component documentation, describe purpose, behavior, guarantees, and usage first; prefer positive descriptions of what the component does over long lists of unrelated things it does not do.
- Use design labels such as `intrusive`, `lock-free`, or `cache-friendly` only when they communicate a meaningful distinction; explain the concrete property directly instead of relying on the label alone.
- Treat versioned filenames such as `_v2` or `_v3` as tooling artifacts unless the code or docs establish a real semantic difference; do not infer design distinctions from the suffix alone.
- In documentation examples, prefer readability over compression; keep simple statements split when that makes structure and intent easier to scan.
- For reusable containers and structural helpers, document structure, operations, and invariants, not higher-level policy from a particular application.
- For evolving document sets, start with one authoritative document. Split into multiple documents only when distinct roles emerge, then make the set traversable with one visible `MAIN-*` or index document that links them all.
- When a document set splits, keep roles explicit and stable. Typical roles are:
  - plan: phases, current position, next step
  - contract/spec: accepted definitions and invariants
  - formal: extracted mathematical definition
  - design/realiser: implementation-facing derivation
  - main/index: navigation, status, and historical orientation
- After a decision is accepted in conversation, update the authoritative document first and verify the file reflects it before describing the decision as settled.
- Before sending a response that describes documentation changes, run the same documentation preflight again against the final wording so banned narrative content does not re-enter through the explanation or closeout.
- When introducing a helper formalism, baseline construction, or naming cleanup, state what problem it is trying to solve before presenting it. It is fine to introduce, but label it as a helper, baseline, or cleanup unless the user has agreed to promote it to the primary definition.
- Use status tags as navigation aids for phased or evolving document sets:
  1. Keep the vocabulary small and fixed.
  2. Use this default cross-project set unless a real semantic gap requires more:
     - `DONE`
     - `WIP`
     - `READY`
     - `PEND`
     - `LEGACY`
     - `BLOCKED`
  3. Define the legend once in the main/index document.
  4. Use the same tags consistently in titles, document maps, and major phase or section headers.
  5. Make tags visually scannable but lightweight.
  6. Avoid synonym drift such as mixing alternate labels like `PENDING`, `NEXT`, and `IN PROGRESS` with the default tag set unless there is a real semantic distinction.
- For OpenSCAD JS documentation, require JSDoc on public symbols and use `@slot`/`@deref` plus full `@type` docs for slot-based constants/typedefs.
- For GitHub markdown docs, avoid raw `<svg>` tags and sanitize punctuation-heavy anchors when generating intra-doc links.
- For GitHub markdown diagrams that must align, prefer plain ASCII (`+`, `-`, `|`) over Unicode box-drawing characters because GitHub monospace rendering can drift.
- For non-trivial diagrams where layout precision matters, prefer an ASCII-first draft and then convert to SVG; avoid relying on Mermaid auto-layout for final authoritative diagrams.
- When editing diagrams, preserve graph semantics and local associations (connectivity, arrow targets, neighboring relationships) while moving elements; do not optimize a single element in isolation.
- For SVG diagram styling, use class/token-based semantics and redundant encodings (color plus line-style/weight) so meaning remains clear under color-vision deficiencies and grayscale.

## Useful Patterns

- [Generalized bracketed-text regex](regex-patterns.md#generalized-bracketed-text-matching)
- [Regex patterns reference](regex-patterns.md)

## Operational References

- [Build issue triage guide](build_issues.md)
- [Testing guidelines](testing.md)
- [Workflow guidance (TTD/tests/approval friction)](workflow.md)
- [Session PID script (PowerShell)](scripts/session-pid.ps1)
- [Codex home README (memory file maintenance conventions)](README.md)

## Design Lessons

- When an existing abstraction is intended to be the foundation, extend or fix that abstraction first; do not build a parallel implementation layer just because it is easier to ship locally.
- If an intended use of an API feels awkward or requires duplicated machinery, treat that as evidence the API needs improvement and surface or implement that improvement instead of bypassing the API.
- Never violate core system constraints such as real-time no-allocation or streaming requirements for implementation convenience; if the foundational abstraction is awkward, fix it instead of staging whole payloads, allocating intermediate buffers, or building a parallel transport path.
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
