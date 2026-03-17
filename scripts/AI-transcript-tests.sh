#!/usr/bin/env bash
# AI-transcript-tests.sh — regression tests for AI-transcript.py
# Run from the .codex directory:  bash scripts/AI-transcript-tests.sh [N [N...]]
#   With no args: run all tests.
#   With one or more test numbers: run only those tests (others are skipped).
#
# Sessions used (local machine):
#   019cd970 — "Verify log files for CRLF switch"  (contains → arrows)
#   019cf2fa — "Implement wall builder per comment" (contains "lattice")
#   019cf1f9 — "Clarify TriPts migration plan"      (contains "moving on")

SCRIPT="python scripts/AI-transcript.py"
PASS=0
FAIL=0
TEST=1
SELECTED=("$@")

# test_selected N — returns 0 (true) if test N should run.
# With no selected tests, all run.  Otherwise only the listed numbers run.
test_selected() {
  [[ ${#SELECTED[@]} -eq 0 ]] && return 0
  local n="$1" t
  for t in "${SELECTED[@]}"; do
    [[ "$t" == "$n" ]] && return 0
  done
  return 1
}

# check DESCRIPTION WANT_EXIT PATTERN INVERT CMD...
#   WANT_EXIT  expected exit code
#   PATTERN    grep -E pattern to match in combined stdout+stderr ("" = skip)
#   INVERT     "!" = pattern must NOT be present; "" = must be present
check() {
  local desc="$1" want_rc="$2" pattern="$3" invert="$4"
  shift 4

  if test_selected $TEST; then 
    local out rc
    out=$("$@" 2>&1)
    rc=$?

    local ok=1
    [[ $rc -ne $want_rc ]] && ok=0
    if [[ -n "$pattern" ]]; then
        if echo "$out" | grep -qE "$pattern"; then
        [[ "$invert" == "!" ]] && ok=0
        else
        [[ "$invert" != "!" ]] && ok=0
        fi
    fi

    if [[ $ok -eq 1 ]]; then
        printf '%d. PASS  %s\n' $TEST "$desc"
        ((PASS++))
    else
        printf '%d. FAIL  %s\n' $TEST "$desc"
        [[ $rc -ne $want_rc ]] && printf '      exit: got %d, want %d\n' "$rc" "$want_rc"
        if [[ -n "$pattern" ]]; then
        [[ "$invert" == "!" ]] \
            && printf '      output unexpectedly contains: %s\n' "$pattern" \
            || printf '      output missing: %s\n' "$pattern"
        fi
        printf '      output: %s\n' "$(echo "$out" | head -2 | tr '\n' '|')"
        ((FAIL++))
    fi
  else
    printf '%d. SKIPPED  %s\n' $TEST "$desc"  
  fi
  ((TEST++))
}

# ANSI check: grep -P '\x1b' detects ESC byte in output
check_ansi() {
  local desc="$1" want_present="$2"   # want_present: "yes" or "no"
  shift 2

  if test_selected $TEST; then 
    local out rc
    out=$("$@" 2>&1); rc=$?
    local found=0
    echo "$out" | grep -qP '\x1b' && found=1

    local ok=1
    [[ $rc -ne 0 ]] && ok=0
    [[ "$want_present" == "yes" && $found -eq 0 ]] && ok=0
    [[ "$want_present" == "no"  && $found -eq 1 ]] && ok=0

    if [[ $ok -eq 1 ]]; then
      printf '%d. PASS  %s\n' $TEST "$desc"
      ((PASS++))
    else
      printf '%d. FAIL  %s\n' $TEST "$desc"
      [[ $rc -ne 0 ]] && printf '      exit: got %d, want 0\n' "$rc"
      [[ "$want_present" == "yes" && $found -eq 0 ]] && printf '      no ANSI codes in output\n'
      [[ "$want_present" == "no"  && $found -eq 1 ]] && printf '      ANSI codes present (should be absent)\n'
      ((FAIL++))
    fi
  else
    printf '%d. SKIPPED  %s\n' $TEST "$desc"  
  fi
  ((TEST++))
}

cd "$(dirname "$0")/.." || exit 1

echo "=== AI-transcript.py regression tests ==="
echo

# ── Sanity ────────────────────────────────────────────────────────────────────
echo "-- Sanity"
check "--ls exits 0"                     0  "(codex|claude)"  ""   $SCRIPT --ls
check "--help exits 0"                   0  "usage"           ""   $SCRIPT --help
check "--grep finds lattice sessions"    0  "codex"           ""   $SCRIPT --grep "lattice" --ls
check "--grep-re finds lattice sessions" 0  "codex"           ""   $SCRIPT --grep-re "lattice" --ls

# ── Bug #1: ap.error blocking --grep + --grep-re mixing ───────────────────────
echo
echo "-- Bug #1: --grep + --grep-re mixing"
check "mixing exits 0"                        0  ""                    ""   $SCRIPT --grep "lattice" --grep-re "wall" --ls
check "mixing: no 'cannot be combined' msg"   0  "cannot be combined"  "!"  $SCRIPT --grep "lattice" --grep-re "wall" --ls

# ── Bug #2/#3: colorama color modes ──────────────────────────────────────────
echo
echo "-- Bug #2/#3: colorama color modes"
check_ansi "--color always: ANSI codes present"    yes  $SCRIPT --color always --ls
check_ansi "--color never: ANSI codes absent"      no   $SCRIPT --color never  --ls
# --color auto in a pipe: isatty() returns False → no ANSI expected
check_ansi "--color auto in pipe: ANSI codes absent"  no   $SCRIPT --color auto --ls

# ── Bug #4: UnicodeEncodeError on → content ───────────────────────────────────
echo
echo "-- Bug #4: Unicode → content"
# grep with context (no --ls) prints matching lines including → glyph
check "--grep '→' exits 0"                0  ""                    ""   $SCRIPT --grep "→" --id 019cd970
check "--grep '→': no UnicodeEncodeError" 0  "UnicodeEncodeError"  "!"  $SCRIPT --grep "→" --id 019cd970

# ── Bug #5: words-only zero-width separator ────────────────────────────────────
echo
echo "-- Bug #5: --words-only separator"
# "movi ng on" should NOT match "moving on" (zero-width bug)
check "false-positive: 'movi ng on' → 0 matches"  0  "No sessions match"   ""  $SCRIPT --words-only --grep "movi ng on"
check "false-positive: no session listed"          0  "(codex|claude)"      "!" $SCRIPT --words-only --grep "movi ng on"
# "moving on" SHOULD still match
check "true-positive: 'moving on' finds sessions"  0  "No sessions match"   "!" $SCRIPT --words-only --grep "moving on"

# ── Bug #6 (already fixed): invalid --grep-re ────────────────────────────────
echo
echo "-- Bug #6: invalid --grep-re pattern"
check "invalid regex exits 1"        1  ""             ""   $SCRIPT --grep-re "unclosed["
check "invalid regex: clean message" 1  "Invalid regex" ""  $SCRIPT --grep-re "unclosed["
check "invalid regex: no Traceback"  1  "Traceback"    "!"  $SCRIPT --grep-re "unclosed["

# ── Bug #7 (already fixed): --grep-re uses regex/re ─────────────────────────
echo
echo "-- Bug #7: --grep-re module selection"
check "--grep-re \\d+ exits 0"       0  ""      ""   $SCRIPT --grep-re "lattice[0-9]+" --ls
check "--grep-re works (finds/not)"  0  "error" "!"  $SCRIPT --grep-re "lattice[0-9]+" --ls

# ── Optional-dependency degradation ─────────────────────────────────────────
echo
echo "-- Optional-dependency degradation (colorama)"
if python -c "import colorama" 2>/dev/null; then
  pip uninstall -y colorama -q 2>/dev/null
  check_ansi "--color always without colorama: no ANSI"  no  $SCRIPT --color always --ls
  check     "warning printed when colorama absent"        0  "colorama not installed"  ""  $SCRIPT --color always --ls
  check     "--color never without colorama: exits 0"     0  ""  ""   $SCRIPT --color never --ls
  pip install colorama -q 2>/dev/null
  echo "  (colorama restored)"
else
  TESTS_SKIPPED=4
  echo "$TEST. SKIP $TESTS_SKIPPED: colorama not currently installed"
  ((TEST+=$TESTS_SKIPPED))
fi

echo
echo "-- Optional-dependency degradation (regex)"
if python -c "import regex" 2>/dev/null; then
  pip uninstall -y regex -q 2>/dev/null
  check "--grep-re without regex: falls back to re, exits 0"  0  ""       ""   $SCRIPT --grep-re "lattice" --ls
  check "--grep-re without regex: still finds sessions"        0  "codex"  ""   $SCRIPT --grep-re "lattice" --ls
  check "invalid --grep-re without regex: clean error"         1  "Invalid regex"  ""  $SCRIPT --grep-re "unclosed["
  check "invalid --grep-re without regex: no Traceback"        1  "Traceback"      "!" $SCRIPT --grep-re "unclosed["
  pip install regex -q 2>/dev/null
  echo "  (regex restored)"
else
  TESTS_SKIPPED=4
  echo "$TEST. SKIP $TESTS_SKIPPED tests: regex not currently installed"
  ((TEST+=$TESTS_SKIPPED))
fi

# ── Bug #8: AND check correctness (perf fix must not break results) ───────────
echo
echo "-- Bug #8: AND check correctness"
# Single pattern and AND-of-two should both work
check "AND: two --grep flags exit 0"  0  "codex"  ""   $SCRIPT --grep "lattice" --grep "wall" --ls
# A pattern that exists + one that doesn't → no match
check "AND: impossible combo → 0"     0  "No sessions match"  ""  $SCRIPT --grep "lattice" --grep "ZZZIMPOSSIBLEZZZ"

# ── Bug #9/#10/#11: structural fixes (output should be unchanged) ─────────────
echo
echo "-- Bugs #9/#10/#11: structural (output unchanged)"
check "--ls record count visible"         0  "records:"    ""  $SCRIPT --ls
check "transcript --id has header"        0  "019cf2fa"    ""  $SCRIPT --id 019cf2fa --ls
check "--ls title shown"                  0  "wall builder" "" $SCRIPT --ls

# ── Per-AI source flags ───────────────────────────────────────────────────────
echo
echo "-- Per-AI source flags"
check "--codex --ls exits 0"                        0  "codex"   ""  $SCRIPT --codex --ls
check "--claude --all-projects --ls has sessions"   0  "claude"  ""  $SCRIPT --claude --all-projects --ls
check "--codex --grep finds sessions"               0  "codex"   ""  $SCRIPT --codex --grep "lattice" --ls
check "--claude --all-projects --grep exits 0"      0  ""        ""  $SCRIPT --claude --all-projects --grep "lattice" --ls
check "--codex --grep-re exits 0"                   0  "codex"   ""  $SCRIPT --codex --grep-re "lattice" --ls
check "--claude --all-projects --grep-re exits 0"   0  ""        ""  $SCRIPT --claude --all-projects --grep-re "lattice" --ls
# --id resolves from both stores
check "--id resolves codex session"       0  "019cf2fa"  "" $SCRIPT --id 019cf2fa --ls
# transcript works for each store
check "codex transcript exits 0"          0  "019cf2fa"  "" $SCRIPT --codex --id 019cf2fa

# ── Summary ──────────────────────────────────────────────────────────────────
echo
TOTAL=$((PASS + FAIL))
printf '=== %d/%d passed' "$PASS" "$TOTAL"
[[ $FAIL -gt 0 ]] && printf ' (%d FAILED)' "$FAIL"
printf '\n'
[[ $FAIL -eq 0 ]]
