# Coding Practices

This file records shared coding-practice guidance for AI assistants working on Adrian's projects. It is intended to be reusable across Codex, Claude, and similar agents.

The central standard is: produce code that is correct, understandable, testable, maintainable, and difficult to misuse. Good practice is not primarily about surface style; it is about making the intended behavior explicit and making incorrect behavior easier to catch.

For Multi-AI and similar projects, the top rule is:

> Understand and prove the mechanism first; then implement the smallest explicit design that satisfies the required behavior.

## Architecture and Design

- Put correctness before cleverness. Verify that the chosen mechanism can actually provide the behavior required before building around it.
- Prefer simple, explicit architecture. One clear path is usually better than several overlapping mechanisms, hidden state, speculative extensibility, or fallback paths that obscure failure.
- Keep ownership and boundaries clear. Each piece of state and behavior should have an obvious owner, and each layer should avoid independently reinterpreting the same semantics.
- Encode important invariants directly in the design. Examples: one worker incarnation maps to one worker id; one WebContents maps to one webContents id; a disposed worker cannot later emit active-worker events; one application run maps to one application diagnostic log.
- Preserve identity across lifecycles. If something is created, replaced, or destroyed, its identity should remain traceable through terminal events and diagnostics.
- Prefer evidence before architecture. Do not build a complicated subsystem based only on assumptions about Electron, Chromium, ChatGPT, or another runtime. Instrument, observe, then choose the design.
- Keep components small and cohesive. Split modules when responsibilities are genuinely distinct, not merely to make files shorter.
- Apply DRY with judgment. Reuse genuine concepts and mechanisms, but do not create an abstraction merely because two pieces of code currently look similar.
- Look for established design patterns that naturally fit the task. Use patterns when they clarify ownership, lifecycle, composition, state transitions, or extensibility. Do not apply patterns ceremonially.
- Avoid speculative complexity. Do not implement something merely because it might be needed later.
- Use the platform's intended APIs where feasible. Prefer supported platform mechanisms over DOM hacks, monkeypatches, undocumented internals, or emulation unless evidence shows the supported route cannot meet the requirement.
- Make changes reviewable. A change should have a defined problem, intended behavior, focused diff, tests or verification, and documentation updates where semantics changed.

## Contracts and Failure Handling

- Failures should be visible. Avoid swallowing errors, silently changing paths, silently retrying forever, or falling back to a different mechanism without an explicit design decision.
- Use offensive coding for trusted interfaces and data. When inputs or APIs are under our control or contractually trustworthy, enforce contracts, fail fast, and use assertions, preconditions, postconditions, and invariants to catch programmer misuse.
- Use defensive coding at genuinely untrusted boundaries: user input, network input, malformed external data, unreliable communication channels, or known-poor external interfaces.
- Treat third-party libraries according to their documented contracts unless there is evidence that the implementation, communication channel, or dependency is unreliable enough to require additional defensive handling.
- Fallbacks are exceptional. They are normally justified only by unavoidable unreliable external systems, communication channels, poorly behaved dependencies, or other constraints outside our control.
- Do not add fallback paths merely to conceal failures in interfaces we control. Silent fallback can hide defects, corrupt assumptions, and make failures much harder to diagnose.
- Prefer explicit state transitions over loose collections of booleans. For example, `created -> renderer assigned -> ready -> disposed` is easier to reason about than unrelated flags whose combinations imply the real state.
- Avoid temporal coupling where possible. Code should not depend on several unrelated calls happening in a particular undocumented order. Where ordering is inherently important, encode and document it.
- Do not destroy information prematurely. Capture data needed for terminal events before destroying the object or handle that owns the data.

## Testing Discipline

- Tests must be non-volatile. Expected results should come from a stable, independent oracle: specification-derived constants, fixed fixtures, known golden outputs, independently established values, externally observable behavior, or a separately implemented reference algorithm whose correctness has already been established.
- Do not derive expected results from the implementation under test, from the same production function, or from an equivalent copy of the same unproven logic. Otherwise the test can reproduce the same defect and falsely pass.
- A known-correct legacy or reference implementation may be used as an oracle for a replacement, refactor, optimization, port, alternate implementation, or new algorithm. This is especially useful for differential testing when the reference implementation's correctness has already been established and the two implementations are meaningfully independent.
- Keep fixed specification or golden cases where practical, even when using differential tests, so both implementations cannot silently agree on the same mistaken assumption.
- Prefer outcome-shaped tests. Tests should establish the behavior that matters, not merely that a particular function was called or that incidental implementation details remained unchanged.
- Pure deterministic logic belongs in fast unit tests. Runtime behavior should be tested at the runtime level when practical.
- Use regression-first bug fixing when feasible: write or identify a test that fails for the demonstrated bug, fix the bug, then verify the regression and surrounding behavior remain green.
- A strong test strategy may combine fixed specification or golden vectors, differential tests against a trusted independent reference implementation, edge-case/property/invariant tests, and runtime or integration tests where relevant.
- For refactor or new development, agree expected behavior and the test plan before coding. If expectations change, re-agree before updating tests or fixtures.
- Tests must reflect semantics, not just code coverage. When a bug reveals that a type, API, boundary, or test shape is semantically wrong, prefer the clean semantic fix over the smallest local patch, even if the patch is quicker.
- For core semantic modules, freeze a short local contract before refactoring: identity, input-domain meaning, and mapping semantics. If any of the three is unsettled, stop and resolve it first.
- Before refactoring, cleanup, or optimization in a core semantic module, add or update at least one test that proves the intended semantic behavior, not just implementation self-consistency.
- For exactness-sensitive code, do not rely only on numerically friendly inputs such as powers of two, symmetric cases, or clean boundary values. Treat friendly cases as smoke tests, not proof, and include adversarial, odd, prime, or otherwise non-dyadic inputs early enough to expose representation and rounding problems.
- If correctness depends on exact identity, preserve exact provenance until the last possible moment, prefer exact-by-construction implementation paths over recomputation plus comparison, keep exact-identity and approximate-geometric APIs semantically separate, and do not collapse tests that appear textually similar until you confirm they are proving the same semantic claim.
- For global default TTD/testing/approval-friction workflow details that apply to all projects unless overridden locally, follow `~/.codex/workflow.md`.

## Build and Test Execution

- For CMake builds/tests in workspace repos, check `.vscode/settings.json` and `CMakePresets.json`/`CMakeUserPresets.json` first and mirror those settings. Use manual command lines only when those sources are absent or the user explicitly overrides them.
- For CMake workflows, never run configure and build concurrently. Run them sequentially (`cmake -S/-B` then `cmake --build`) to avoid regenerate/build race conditions.
- For build/linker mismatch triage, follow `~/.codex/build_issues.md` before ad-hoc fixes.

## C++ Test Readability

- In C++ tests and examples, prefer declaring variables immediately before first use rather than hoisting declarations to the top of the scope.
- In multi-stage C++ tests and examples, add short local comments that label setup or intent blocks so readers do not have to scan to the final assertion to understand the scenario.
- When extending a test area that already has a readable exemplar file, mirror that file's readability conventions for structure, local comments, and declaration placement unless the user asks for a different style.
- In constexpr-heavy C++ tests, prefer named `constexpr bool` scenario blocks with inline setup/intent comments over bare piles of `static_assert`s so each compile-time proof is readable without reconstructing the scenario from the final predicate.
- For every new test file, give each `constexpr` scenario block and each `TEST(...)` block a short local comment that states exactly what behavior it is proving before the assertions.
- Do not rely on helper names, test names, or long setup/helper sections alone to communicate test intent; the reader should not have to reconstruct the purpose from the assertions.
- When a new test file has substantial helper/setup code, add section comments that separate fixture-building helpers from the actual scenarios under test.

## Robot Framework

Robot Framework is appropriate when acceptance, integration, UI, or system workflows benefit from readable, reusable, keyword-driven scenarios. It should complement fast unit tests and focused logic tests, not replace them.

- Use Robot Framework for workflows where readable end-to-end behavior matters: user-visible flows, runtime behavior, multi-process coordination, UI automation, installer/update flows, or cross-component acceptance checks.
- Keep reusable keywords in shared Robot resource files or test libraries. Domain-level keywords should express user or system actions and expected outcomes, not low-level implementation trivia.
- Hide low-level driver details behind keywords. Test cases should read like stable behavior specifications, while libraries handle selectors, protocol calls, waits, setup, teardown, and diagnostics.
- Design Robot tests with the same oracle discipline as other tests. Do not compute expected values using the production logic being tested; use fixtures, known expected outputs, reference behavior, or externally observable outcomes.
- Prefer condition-based waits and explicit readiness checks over arbitrary sleeps. Use sleeps only when the delay itself is the behavior under test or when a documented external constraint requires it.
- Use tags, setup, teardown, logs, screenshots, captured artifacts, and diagnostic attachments to make failures easy to interpret.
- Keep Robot libraries documented and versioned with the test contracts they support. When a keyword's semantics change, update its documentation and dependent tests together.
- Avoid bloated, brittle Robot scenarios. Push repeated mechanics into reusable keywords, keep each scenario focused on one meaningful outcome, and leave detailed logic permutations to unit, property, or differential tests.

## Observability, Resources, and Security

- Observability is part of the design. Useful logging, stable ids, lifecycle events, meaningful error context, and reproducible diagnostics should be designed in rather than bolted on after something breaks.
- Bound resources deliberately. Logs, queues, retained snapshots, caches, listeners, renderers, and buffers should have understood lifetimes and deterministic cleanup.
- Protect sensitive data by default. Do not log credentials, cookies, authorization headers, arbitrary message bodies, or conversation content unless there is a deliberate need and an explicit bounded diagnostic design.
- Preserve diagnostic context without retaining unnecessary private or high-volume data.

## Documentation and Comments

- Documentation should describe reality. Comments and design docs should explain invariants, reasons, contracts, ownership, lifetimes, units, assumptions, and non-obvious constraints.
- Comment intent and local meaning where it helps the reader understand the immediate layer without tracing several levels outward. This includes files, classes, functions, important variables/constants, and non-obvious blocks.
- Do not treat "comment comprehensively" as "comment every variable". Prefer useful comments that clarify intent, invariants, contracts, lifecycle, or domain meaning over comments that restate syntax or obvious assignments.
- Comments are part of the implementation. Keep them synchronized with behavior, ownership, contracts, and assumptions. Stale or misleading comments are defects.
- If implementation and documentation disagree, one of them needs fixing.

## Workflow and Scope

- Distinguish coding practice from project workflow. Issues, branch continuity, development revisions, CI, and live acceptance support good engineering, but the code itself should remain sound even if GitHub and CI were removed.
- Prefer portability where inexpensive and platform specificity where necessary. Do not unnecessarily hard-code platform assumptions, but do not pretend something is cross-platform until it has actually been validated.
- Keep unrelated cleanup out of focused changes unless it is truly needed to complete the requested work safely.
