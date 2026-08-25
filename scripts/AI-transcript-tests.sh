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

PASS=0
FAIL=0
TEST=1
SELECTED=("$@")
RESET="$(tput sgr0)"
RED="$(tput setaf 1)"
GREEN="$(tput setaf 2)"
YELLOW="$(tput setaf 3)"

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
run_capture() {
  CAPTURE_STDOUT="$(mktemp)"
  CAPTURE_STDERR="$(mktemp)"
  "$@" >"$CAPTURE_STDOUT" 2>"$CAPTURE_STDERR"
  CAPTURE_RC=$?
}

cleanup_capture() {
  rm -f "$CAPTURE_STDOUT" "$CAPTURE_STDERR"
}

capture_stream_path() {
  case "$1" in
    stdout) printf '%s\n' "$CAPTURE_STDOUT" ;;
    stderr) printf '%s\n' "$CAPTURE_STDERR" ;;
    *) echo "invalid stream: $1" >&2; return 1 ;;
  esac
}

capture_preview() {
  { head -2 "$CAPTURE_STDOUT"; head -2 "$CAPTURE_STDERR"; } | tr '\n' '|'
}

check() {
  local desc="$1" want_rc="$2" pattern="$3" invert="$4"
  shift 4

  if test_selected $TEST; then 
  local out rc
  run_capture "$@"
  out="$(cat "$CAPTURE_STDOUT" "$CAPTURE_STDERR")"
  rc=$CAPTURE_RC

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
    printf '%d. %sPASS%s  %s\n' $TEST "$GREEN" "$RESET" "$desc"
    ((PASS++))
  else
  printf '%d. %sFAIL%s  %s\n' $TEST "$RED" "$RESET" "$desc"
    [[ $rc -ne $want_rc ]] && printf '      exit: got %d, want %d\n' "$rc" "$want_rc"
    if [[ -n "$pattern" ]]; then
    [[ "$invert" == "!" ]] \
      && printf '      output unexpectedly contains: %s\n' "$pattern" \
      || printf '      output missing: %s\n' "$pattern"
    fi
    printf '      output: %s\n' "$(capture_preview)"
    ((FAIL++))
  fi
  cleanup_capture
  else
  printf '%d. %sSKIPPED%s  %s\n' $TEST "$YELLOW" "$RESET" "$desc"
  fi
  ((TEST++))
}

# check_stream DESCRIPTION STREAM WANT_EXIT PATTERN INVERT CMD...
#   STREAM     stdout | stderr
check_stream() {
  local desc="$1" stream="$2" want_rc="$3" pattern="$4" invert="$5"
  shift 5

  if test_selected $TEST; then
  local rc ok=1 stream_file
  run_capture "$@"
  rc=$CAPTURE_RC
  stream_file="$(capture_stream_path "$stream")"

  [[ $rc -ne $want_rc ]] && ok=0
  if [[ -n "$pattern" ]]; then
    if grep -qE "$pattern" "$stream_file"; then
    [[ "$invert" == "!" ]] && ok=0
    else
    [[ "$invert" != "!" ]] && ok=0
    fi
  fi

  if [[ $ok -eq 1 ]]; then
    printf '%d. %sPASS%s  %s\n' $TEST "$GREEN" "$RESET" "$desc"
    ((PASS++))
  else
    printf '%d. %sFAIL%s  %s\n' $TEST "$RED" "$RESET" "$desc"
    [[ $rc -ne $want_rc ]] && printf '      exit: got %d, want %d\n' "$rc" "$want_rc"
    if [[ -n "$pattern" ]]; then
    [[ "$invert" == "!" ]] \
      && printf '      %s unexpectedly contains: %s\n' "$stream" "$pattern" \
      || printf '      %s missing: %s\n' "$stream" "$pattern"
    fi
    printf '      output: %s\n' "$(capture_preview)"
    ((FAIL++))
  fi
  cleanup_capture
  else
  printf '%d. %sSKIPPED%s  %s\n' $TEST "$YELLOW" "$RESET" "$desc"
  fi
  ((TEST++))
}

# ANSI check on a specific stream: look for a literal ESC byte
check_ansi() {
  local desc="$1" stream="$2" want_present="$3"   # want_present: "yes" or "no"
  shift 3

  if test_selected $TEST; then 
  local rc found=0 stream_file
  run_capture "$@"
  rc=$CAPTURE_RC
  stream_file="$(capture_stream_path "$stream")"
  LC_ALL=C grep -q $'\033' "$stream_file" && found=1

  local ok=1
  [[ $rc -ne 0 ]] && ok=0
  [[ "$want_present" == "yes" && $found -eq 0 ]] && ok=0
  [[ "$want_present" == "no"  && $found -eq 1 ]] && ok=0

  if [[ $ok -eq 1 ]]; then
    printf '%d. %sPASS%s  %s\n' $TEST "$GREEN" "$RESET" "$desc"
    ((PASS++))
  else
    printf '%d. %sFAIL%s  %s\n' $TEST "$RED" "$RESET" "$desc"
    [[ $rc -ne 0 ]] && printf '      exit: got %d, want 0\n' "$rc"
    [[ "$want_present" == "yes" && $found -eq 0 ]] && printf '      no ANSI codes in %s\n' "$stream"
    [[ "$want_present" == "no"  && $found -eq 1 ]] && printf '      ANSI codes present in %s (should be absent)\n' "$stream"
    printf '      output: %s\n' "$(capture_preview)"
    ((FAIL++))
  fi
  cleanup_capture
  else
  printf '%d. %sSKIPPED%s  %s\n' $TEST "$YELLOW" "$RESET" "$desc"
  fi
  ((TEST++))
}

cd "$(dirname "$0")/.." || exit 1

# Create a throw-away venv so the script is self-contained.  MSYS2 Python
# writes raw ANSI bytes to pipes (POSIX behaviour), making ESC bytes
# detectable by grep -qP '\x1b'.
VENV="/tmp/venv.$$"
python -m venv "$VENV" || { echo "Failed to create venv"; exit 1; }
trap 'rm -rf "$VENV"' EXIT
if   [[ -f "$VENV/bin/python"     ]]; then PYTHON="$VENV/bin/python"
elif [[ -f "$VENV/Scripts/python" ]]; then PYTHON="$VENV/Scripts/python"
else echo "Cannot find Python in venv at $VENV"; exit 1
fi
SCRIPT="$PYTHON scripts/AI-transcript.py"

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

# ── Bug #2/#3 (colorama present) + degradation (colorama absent) ─────────────
echo
echo "-- Colorama: color modes (Bug #2/#3) + degradation"
_colorama_was_installed=false
$PYTHON -c "import colorama" 2>/dev/null && _colorama_was_installed=true
! $_colorama_was_installed && $PYTHON -m pip install colorama -q  #2>/dev/null
$PYTHON -c "import colorama" 2>/dev/null || { echo "didn't install colorama"; exit 1; }
check_ansi "--color always: stdout has ANSI"             stdout yes  $SCRIPT --color always --ls
check_ansi "--color never: stdout has no ANSI"           stdout no   $SCRIPT --color never  --ls
check_ansi "--color auto in pipe: stdout has no ANSI"    stdout no   $SCRIPT --color auto   --ls
$PYTHON -m pip uninstall -y colorama -q #2>/dev/null
$PYTHON -c "import colorama" 2>/dev/null && { echo "colorama is still installed"; exit 1; }
check_ansi "--color always without colorama: stdout has no ANSI" stdout no $SCRIPT --color always --ls
check_stream "warning printed on stderr when colorama absent" stderr 0 "colorama not installed" "" $SCRIPT --color always --ls
check     "--color never without colorama: exits 0"       0   ""  ""   $SCRIPT --color never --ls
$_colorama_was_installed && { $PYTHON -m pip install colorama -q #2>/dev/null;
  echo "  (colorama restored)"; }

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
check "invalid regex: clean message" 1  "ERROR: invalid regex" ""  $SCRIPT --grep-re "unclosed["
check "invalid regex: no Traceback"  1  "Traceback"    "!"  $SCRIPT --grep-re "unclosed["

# ── Bug #7 (regex present) + degradation (regex absent) ─────────────────────
echo
echo "-- regex module: selection (Bug #7) + degradation"
_regex_was_installed=false
$PYTHON -c "import regex" 2>/dev/null && _regex_was_installed=true
! $_regex_was_installed && $PYTHON -m pip install regex -q # 2>/dev/null
check "--grep-re \\d+ exits 0"       0  ""      ""   $SCRIPT --grep-re "lattice[0-9]+" --ls
check "--grep-re works (finds/not)"  0  "error" "!"  $SCRIPT --grep-re "lattice[0-9]+" --ls
$PYTHON -m pip uninstall -y regex -q # 2>/dev/null
check "--grep-re without regex: falls back to re, exits 0"  0  ""       ""   $SCRIPT --grep-re "lattice" --ls
check "--grep-re without regex: still finds sessions"        0  "codex"  ""   $SCRIPT --grep-re "lattice" --ls
check "invalid --grep-re without regex: clean error"         1  "ERROR: invalid regex"  ""  $SCRIPT --grep-re "unclosed["
check "invalid --grep-re without regex: no Traceback"        1  "Traceback"      "!" $SCRIPT --grep-re "unclosed["
$_regex_was_installed && { $PYTHON -m pip install regex -q #2>/dev/null; 
  echo "  (regex restored)"; }

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
# --id by first-message text for a session not in session_index.jsonl (bug #23)
check "--id by first-msg for unindexed session"  0  "019d1acc"  "" $SCRIPT --codex --id "I want you to" --ls

# ── Case sensitivity (-i flag) ────────────────────────────────────────────────
echo
echo "-- Case sensitivity (-i flag)"
# Default: case-sensitive — uppercase LATTICE must NOT match lowercase "lattice"
check "case-sensitive default: LATTICE → no match"        0  "No sessions match"  ""  $SCRIPT --codex --grep "LATTICE" --ls
check "case-sensitive default: LATTICE → no sessions"     0  "codex"              "!" $SCRIPT --codex --grep "LATTICE" --ls
# With -i: uppercase LATTICE should find "lattice" sessions
check "-i: LATTICE finds codex sessions"                  0  "No sessions match"  "!" $SCRIPT --codex --grep "LATTICE" -i --ls
check "-i: sessions listed"                               0  "codex"              ""  $SCRIPT --codex --grep "LATTICE" -i --ls

# ── Record number prefix (-n flag) ────────────────────────────────────────────
echo
echo "-- Record number prefix (-n flag)"
# Without -n: output must NOT start any line with digits+colon
check "no -n: no record number prefix"    0  "^[0-9]+:"   "!" $SCRIPT --codex --id 019cf2fa --grep "lattice"
# With -n: at least one output line must start with digits+colon
check "-n: record number prefix present"  0  "^[0-9]+:"   ""  $SCRIPT --codex --id 019cf2fa --grep "lattice" -n

# ── Timestamp prefix (-d flag) ────────────────────────────────────────────────
echo
echo "-- Timestamp prefix (-d flag)"
# Without -d: no line starts with [YYYY-
check "no -d: no timestamp prefix"        0  "^\[20[0-9][0-9]-"  "!" $SCRIPT --codex --id 019cf2fa --grep "lattice"
# With -d: at least one line starts with [YYYY-
check "-d: timestamp prefix present"      0  "^\[20[0-9][0-9]-"  ""  $SCRIPT --codex --id 019cf2fa --grep "lattice" -d

# ── Combined -n -d ordering ───────────────────────────────────────────────────
echo
echo "-- Combined -n -d prefix order"
# With both -n and -d: timestamp appears before record number on the same line
check "-n -d: timestamp then rec number"  0  "^\[20[0-9][0-9]-.*\]: [0-9]+:"  ""  $SCRIPT --codex --id 019cf2fa --grep "lattice" -n -d

# ── Timezone display (--tz flag) ─────────────────────────────────────────────
echo
echo "-- Timezone display (--tz flag)"
# --tz UTC: implies -d; UTC is always available without tzdata
check "--tz UTC: implies -d, timestamp present"   0  "^\[20[0-9][0-9]-"  ""  $SCRIPT --codex --id 019cf2fa --grep "lattice" --tz UTC
# --tz ±HH:MM: fixed offset, no external deps
check "--tz +00:00: fixed offset timestamp present"  0  "^\[20[0-9][0-9]-"  ""  $SCRIPT --codex --id 019cf2fa --grep "lattice" --tz +00:00
# --tz with unresolvable IANA name: Warning on stderr, exit 0
check "--tz invalid zone: Warning emitted, exit 0"  0  "WARNING:"  ""  $SCRIPT --codex --id 019cf2fa --grep "lattice" --tz "Not/AZone"
# --tz with unresolvable IANA name: fallback to local time, timestamp still shown
check "--tz invalid zone: fallback timestamp shown"  0  "^\[20[0-9][0-9]-"  ""  $SCRIPT --codex --id 019cf2fa --grep "lattice" --tz "Not/AZone"

# ── Record-range filter (--records) ──────────────────────────────────────────
echo
echo "-- Record-range filter (--records)"
# :10 — first 10 records; record 7 is the first with content
check "--records :10: numbered output present"  0  "^ [0-9]"       ""  $SCRIPT --codex --id 019cf2fa --grep "." -n --records :10
# 7:7 — only record 7 (first record with content)
check "--records 7:7: record 7 present"         0  "^ 7:"          ""  $SCRIPT --codex --id 019cf2fa --grep "." -n --records 7:7
check "--records 7:7: no record 8"              0  "^ 8:"          "!" $SCRIPT --codex --id 019cf2fa --grep "." -n --records 7:7
# -4: — negative index; records 90-93; record 90 has content
check "--records=-4:: last records present"     0  "^[[:space:]]*[0-9]" ""  $SCRIPT --codex --id 019cf2fa --grep "." -n --records=-4:
check "--records 9999:9999: no matches"         0  "INFO:"         ""  $SCRIPT --codex --id 019cf2fa --grep "." --records 9999:9999

# ── Timestamp filter (--since / --until) ─────────────────────────────────────
echo
echo "-- Timestamp filter (--since / --until)"
check "--since future: no matches"              0  "INFO:"         ""  $SCRIPT --codex --id 019cf2fa --grep "lattice" --since "2099-01-01"
check "--until past: no matches"                0  "INFO:"         ""  $SCRIPT --codex --id 019cf2fa --grep "lattice" --until "2000-01-01"
check "--since 2026-01-01: has matches"         0  "lattice"       ""  $SCRIPT --codex --id 019cf2fa --grep "lattice" --since "2026-01-01"
check "--since relative -9999:00: has matches"  0  "lattice"       ""  $SCRIPT --codex --id 019cf2fa --grep "lattice" --since="-9999:00"
check "--until +offset relative to since"       0  "lattice"       ""  $SCRIPT --codex --id 019cf2fa --grep "lattice" --since "2026-01-01" --until "+9999:00"

# ── Transcript headings: -d / -n stamps (item 9) ─────────────────────────────
echo
echo "-- Transcript headings -d / -n (item 9)"
# Codex: -d stamps headings with [YYYY-
check "codex transcript -d: User heading has timestamp"   0  "^## User \[20"    ""  $SCRIPT --codex --id 019cf2fa -d
check "codex transcript -d: Codex heading has timestamp"  0  "^## Codex \[20"   ""  $SCRIPT --codex --id 019cf2fa -d
# Codex: -n stamps headings with record number
check "codex transcript -n: User heading has rec no"      0  "^## User  *[0-9]" ""  $SCRIPT --codex --id 019cf2fa -n
# Codex: no flags — headings are plain
check "codex transcript no flags: User heading plain"     0  "^## User$"        ""  $SCRIPT --codex --id 019cf2fa
check "codex transcript no flags: no bracket in User"     0  "^## User \["      "!" $SCRIPT --codex --id 019cf2fa
# Claude: -d stamps headings with [YYYY-
check "claude transcript -d: User heading has timestamp"   0  "^## User \[20"   ""  $SCRIPT --claude --file scripts/fixtures/t-mode.jsonl -d
check "claude transcript -d: Claude heading has timestamp" 0  "^## Claude \[20" ""  $SCRIPT --claude --file scripts/fixtures/t-mode.jsonl -d

# ── Fixture-based rendering tests ────────────────────────────────────────────
echo
echo "-- Fixture-based rendering tests (--file)"
# Ensure regex is available for the thinking-escape tests.
$PYTHON -m pip install regex -q

# thinking-lt-escape: <details> and <span> escaped outside fence; <code> inside fence NOT escaped
check "thinking-escape: <details> outside fence escaped"  0 '&lt;details'  ""  $SCRIPT --claude --file scripts/fixtures/thinking-lt-escape.jsonl
check "thinking-escape: <span> outside fence escaped"     0 '&lt;span'     ""  $SCRIPT --claude --file scripts/fixtures/thinking-lt-escape.jsonl
check "thinking-escape: <code> inside fence NOT escaped"  0 '&lt;code'     "!" $SCRIPT --claude --file scripts/fixtures/thinking-lt-escape.jsonl

# t-mode: without -T no inner Claude headings; with -T -d inner headings appear for each inline segment
check "t-mode: without -T no inner > ## Claude"  0 '> ## Claude'       "!" $SCRIPT --claude --file scripts/fixtures/t-mode.jsonl
check "t-mode: with -T -d inner heading present" 0 '> ## Claude \[20'  ""  $SCRIPT --claude --file scripts/fixtures/t-mode.jsonl -T -d

# adaptive-fence: Bash output containing ``` triggers 4-backtick outer fence
check "adaptive-fence: 4-backtick fence present" 0 '````' "" $SCRIPT --claude --file scripts/fixtures/adaptive-fence.jsonl

# exit-plan-mode: Approved Plan section collapsed into <details>
check "exit-plan-mode: Approved Plan in output" 0 'Approved Plan'  ""  $SCRIPT --claude --file scripts/fixtures/exit-plan-mode.jsonl
check "exit-plan-mode: <details> block present" 0 '<details>'      ""  $SCRIPT --claude --file scripts/fixtures/exit-plan-mode.jsonl

# notice: synthetic <synthetic> record rendered as *(system: ...)*
check "notice: *(system: ...) rendered" 0 '\*\(system:' "" $SCRIPT --claude --file scripts/fixtures/notice.jsonl

# codex-orphan-patch: apply_patch with no final agent_message shows file-change block (item 34)
check "codex-orphan-patch: file change block present"   0 '1 file change'   ""  $SCRIPT --codex --file scripts/fixtures/codex-orphan-patch.jsonl
check "codex-orphan-patch: patch content present"       0 'foo\.py'         ""  $SCRIPT --codex --file scripts/fixtures/codex-orphan-patch.jsonl

# chatgpt-direct: auto-detected ChatGPT transcript renders commentary and tool details
check "chatgpt-direct: auto-detect commentary heading"  0 '## ChatGPT Commentary' "" $SCRIPT --file scripts/fixtures/chatgpt-direct.jsonl
check "chatgpt-direct: explicit flag renders tool output" 0 'hello from python' "" $SCRIPT --chatgpt --file scripts/fixtures/chatgpt-direct.jsonl
check "chatgpt-direct: grouped cite block rendered"      0 '\*\*\(cite:' "" $SCRIPT --chatgpt --file scripts/fixtures/chatgpt-direct.jsonl
check "chatgpt-direct: cite sources named"              0 'Python Docs.*Example|Example.*Python Docs' "" $SCRIPT --chatgpt --file scripts/fixtures/chatgpt-direct.jsonl
check "chatgpt-direct: google favicon service used"     0 'google\.com/s2/favicons\?domain=https://docs\.python\.org&sz=32' "" $SCRIPT --chatgpt --file scripts/fixtures/chatgpt-direct.jsonl
check "chatgpt-direct: cite favicon size fixed"         0 'width="15" height="15"' "" $SCRIPT --chatgpt --file scripts/fixtures/chatgpt-direct.jsonl
check "chatgpt-direct: cite links kept together"        0 'display:inline-block;white-space:nowrap;' "" $SCRIPT --chatgpt --file scripts/fixtures/chatgpt-direct.jsonl
check "chatgpt-direct: tooltip falls back by URL"       0 'title="Python note&#10;&#10;Supporting note for the transcript fixture\."' "" $SCRIPT --chatgpt --file scripts/fixtures/chatgpt-direct.jsonl
check "chatgpt-direct: container exec inferred bash"    0 '```bash' "" $SCRIPT --chatgpt --file scripts/fixtures/chatgpt-direct.jsonl
check "chatgpt-direct: alt text rendered"               0 'Morris Plotkin checked uploaded file' "" $SCRIPT --chatgpt --file scripts/fixtures/chatgpt-direct.jsonl
check "chatgpt-direct: file cite rendered"              0 '`notes\.txt`' "" $SCRIPT --chatgpt --file scripts/fixtures/chatgpt-direct.jsonl
check "chatgpt-direct: raw cite token removed"          0 'cite' "!" $SCRIPT --chatgpt --file scripts/fixtures/chatgpt-direct.jsonl
check "chatgpt-direct: raw entity token removed"        0 'entity' "!" $SCRIPT --chatgpt --file scripts/fixtures/chatgpt-direct.jsonl
check "chatgpt-direct: raw file token removed"          0 'filecite' "!" $SCRIPT --chatgpt --file scripts/fixtures/chatgpt-direct.jsonl
check "chatgpt-direct: grep finds tool output"          0 'hello from python' "" $SCRIPT --chatgpt --file scripts/fixtures/chatgpt-direct.jsonl --grep "hello from python"

# ── Summary ──────────────────────────────────────────────────────────────────
echo
TOTAL=$((PASS + FAIL))
printf '=== %d/%d passed' "$PASS" "$TOTAL"
[[ $FAIL -gt 0 ]] && printf ' (%d FAILED)' "$FAIL"
printf '\n'
[[ $FAIL -eq 0 ]]
