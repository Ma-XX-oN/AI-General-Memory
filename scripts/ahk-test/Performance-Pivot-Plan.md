# Performance Pivot Plan: Locate PasteAsMd Bottleneck

## Goal

Pause feature refactoring and identify where the performance regression was introduced.

## Scope

- Runtime path in `PasteAsMd.ahk` and `HtmlNorm.ahk`.
- Fixture harness path used by `test-paste-md-fixtures.ahk`.
- DOM migration impact (`HtmlDom.ahk` / `HtmlParser.ahk`) vs legacy regex paths.

## Phase 1: Baseline Timing Capture

1. Capture timings for:
   - real paste flow (manual run with debug log enabled),
   - fixture replay for one heavy fixture and one light fixture.
2. Record per-stage durations aligned to existing debug stages:
   - html extraction,
   - HtmlNorm preprocess,
   - pandoc call,
   - markdown cleanup,
   - quote/poster/user/thinking restoration,
   - ordered-list handling.
3. Store timing output in a dedicated perf log file (separate from fixture pass/fail logs).

## Phase 2: Differential Isolation

1. Compare timing between:
   - current HEAD,
   - known good commit (`e332c97`),
   - recent DOM-migration commits.
2. Use same inputs for each comparison:
   - one pinned large log,
   - one representative fixture log.
3. Identify first stage with significant delta.

## Phase 3: Hotspot Attribution

1. If hotspot is pre-pandoc:
   - profile DOM parse/serialize frequency,
   - profile repeated full-string scans in `HtmlNorm`.
2. If hotspot is pandoc-bound:
   - separate process-launch overhead vs input-size overhead.
3. If hotspot is post-pandoc:
   - profile markdown passes, especially repeated `RegExReplace` over full document.

## Phase 4: Remediation Strategy

1. Apply minimal-risk optimization first:
   - remove duplicated passes,
   - avoid parse->serialize loops where no mutation occurred,
   - cache derived structures inside single conversion call.
2. Re-run timing and fixture tests after each optimization stage.
3. Keep behavior fixed; no expected-file updates during perf-only remediation.

## Success Criteria

1. Bottleneck stage is identified with measured evidence.
2. Regression source commit range is narrowed.
3. At least one optimization reduces end-to-end conversion time on heavy input.
4. Fixture and DOM tests remain green after each optimization stage.

## Results

- `HtmlParse.ahk` worked for small clipboards, but for large payloads (~6 MB) it
  took way too long.  Full test wasn't run but was expected to take over an hour
  based on rate of HTML parse.
- MSHTML was faster, but still took too long (47 seconds for ~6 MB).
- `master` baseline runs in ~8 seconds for ~6 MB.

## Conclusion

This branch is currently a performance regression vs `master`. Keeping for
reference.
