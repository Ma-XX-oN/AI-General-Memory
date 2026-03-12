/**
 * End-to-end fixture harness:
 * - reads captured PasteAsMd debug logs (plain + CF_HTML sections)
 * - runs PasteMd._ConvertFromCaptured via seam inputs
 * - compares final markdown to checked-in expected outputs
 * - optionally writes per-scenario fixture output logs
 */
#ErrorStdOut
#Requires AutoHotkey v2.0
#Include ../PasteAsMd.ahk
#Include test-helpers.ahk

emitFixtureOutputLogs := false

passed := 0
failed := 0
suiteStartTick := A_TickCount

/**
 * Fixture registry: one fixture source log per entry.
 */
fixtures := [
  "PasteAsMd_ClaudeCode.log",
  "PasteAsMd_ClaudeCode-with-User.log",
  "PasteAsMd_ClaudeWeb.log",
  "PasteAsMd_ClaudeWeb-with-User.log",
  "PasteAsMd_Codex.log",
  "PasteAsMd_Codex-with-User.log",
  "PasteAsMd_Codex-EditedFile.log",
  "PasteAsMd_Codex-OrderedList-Parent.log",
  "PasteAsMd_Codex-OrderedList-Nested.log",
  "PasteAsMd_Codex-OrderedList-Prompt.log",
  "PasteAsMd_Codex-NestedShell-UL.log",
  "PasteAsMd_Codex-NestedShell-OL.log",
  "PasteAsMd_KaTeX-DuplicateMath.log",
  "PasteAsMd_ChatGPT.log",
  "PasteAsMd_ChatGPT-with-User.log",
  "PasteAsMd_ChatGPT-with-User2.log",
  "PasteAsMd_ChatGPT-FirstUserPrompt.log",
  "PasteAsMd_ChatGPT-ButtonLinks.log",
  "PasteAsMd_ChatGPT-LargeClipboard-fixture.log",
  "PasteAsMd_ChatGPT-TrailingEmptyBullet.log",
]

opts := ParseHarnessOptions(A_Args, fixtures.Length)
_logPath := opts["logPath"] != "" ? opts["logPath"] : A_ScriptDir "\test-paste-md-fixtures.log"
try FileDelete _logPath
; Per-fixture output logs are controlled via CLI only: /fixtureOutputLogs:0|1
if (opts["error"] != "") {
  Log("Argument error: " opts["error"])
  ExitApp 2
}

if (opts["listOnly"]) {
  ListFixtures(fixtures)
  ExitApp
}

if (opts["fixtureIndex"] > 0) {
  idx := opts["fixtureIndex"]
  fixtures := [fixtures[idx]]
} else if (opts["fixturePath"] != "") {
  fixtures := [opts["fixturePath"]]
}

emitFixtureOutputLogs := opts["emitFixtureOutputLogs"]

expectedSuffix := ".expected.md"
actualSuffix := ".actual.md"

/**
 * Required debug sections that must exist in each fixture source log.
 * These provide seam inputs for _ConvertFromCaptured.
 */
required := [
  PasteMd.LOG_SECTION_SOURCE,
  PasteMd.LOG_SECTION_PLAIN,
  PasteMd.LOG_SECTION_CFHTML,
]

Log("── PasteAsMd fixture regressions ─────────────────────────────")
Chk("NormalizeWhitespaceOnlyMarkdownLines clears spacer-only lines", PasteMd.NormalizeWhitespaceOnlyMarkdownLines("alpha`n   `nomega") = "alpha`n`nomega")
Chk("QuoteMarkdown preserves canonical blank lines", PasteMd.QuoteMarkdown(PasteMd.NormalizeWhitespaceOnlyMarkdownLines("alpha`n   `nomega")) = "> alpha`n>`n> omega")
Chk("UnquoteBlankLinesAroundPosterHeadings accepts spaced quote spacers", PasteMd.UnquoteBlankLinesAroundPosterHeadings("## User`n>   `n## ChatGPT") = "## User`n`n## ChatGPT")
Chk("UnquoteBlankLinesAroundPosterHeadings collapses spacer runs", PasteMd.UnquoteBlankLinesAroundPosterHeadings("> body`n>`n>   `n## User`n>   `n>`n> answer") = "> body`n`n## User`n`n> answer")
bt := Chr(96)
nbsp := Chr(160)
inlineTagCode := "- Comments, maybe" nbsp bt "<script>" bt "/" bt "<style>" bt nbsp "if they ever appear."
Chk("CleanMarkdown preserves tags inside inline code spans", PasteMd.CleanMarkdown(inlineTagCode) = inlineTagCode)
for fx in fixtures {
  fixtureStartTick := A_TickCount
  path := _ResolveFixturePath(fx)
  Log("")
  Log("Fixture: " _Basename(path))
  if (_IsCustomFixtureArg(fx))
    Log("  Path: " path)

  try {
    Chk("fixture exists", FileExist(path) != "", path)
    if !FileExist(path)
      continue

    logText := FileRead(path, "UTF-8")
    scenarios := ParseFixtureScenarios(logText)
    Chk("scenario metadata parsed", scenarios.Length > 0)
    if (scenarios.Length = 0)
      continue

    try {
      sections := ParseDbgSections(logText)
      Chk("debug sections parsed", true)
    } catch as e {
      Chk("debug sections parsed", false, e.Message)
      continue
    }

    missing := false
    for label in required {
      has := sections.Has(label)
      Chk("section present: " label, has)
      if !has
        missing := true
    }
    if missing
      continue

    /**
     * Seam inputs decoded from captured debug sections.
     */
    expectedSource := Trim(SectionToText(sections[PasteMd.LOG_SECTION_SOURCE]), " `t`r`n")
    plain := SectionToText(sections[PasteMd.LOG_SECTION_PLAIN])
    cfHtml := SectionToText(sections[PasteMd.LOG_SECTION_CFHTML])
    for sc in scenarios {
      caseId := sc["case"]
      /**
       * Default scenario uses unsuffixed files.
       * Metadata scenarios use .<CASE> suffixes.
       */
      expectedPath := _SiblingWithSuffix(path, caseId = "" ? expectedSuffix : ("." caseId expectedSuffix))
      actualPath := _SiblingWithSuffix(path, caseId = "" ? actualSuffix : ("." caseId actualSuffix))
      outputLogPath := _SiblingWithSuffix(path, caseId = "" ? ".fixture.log" : ("." caseId ".fixture.log"))
      Log("Scenario: " (caseId = "" ? "default" : caseId))

      prevPromptFn := ""
      try {
        if (sc["hasPrompt"]) {
          if HasMethod(PasteMd, "SetOrderedListPromptProvider") {
            promptFn := MakePromptProvider(sc["prompt"])
            prevPromptFn := PasteMd.SetOrderedListPromptProvider(promptFn)
          } else {
            Log("  note: prompt scenario skipped (provider unavailable): " caseId)
            continue
          }
        }

        ; Match runtime UI behavior: speaker labels are tied to quoted mode only.
        showPoster := sc["asQuoted"]
        converted := PasteMd._ConvertFromCaptured(plain, cfHtml, sc["asQuoted"], showPoster, false, sc["hasPrompt"])
        if (emitFixtureOutputLogs)
          _WriteFixtureOutputLog(outputLogPath, plain, cfHtml, converted, sc["asQuoted"])
        ChkEqNorm("source", converted["source"], expectedSource)
        aborted := converted.Has("aborted") ? converted["aborted"] : false

        if (sc["expectAbort"]) {
          Chk("conversion aborted", aborted)
        } else {
          Chk("conversion not aborted", !aborted)
        }

        finalMd := converted["finalMd"]
        _WriteUtf8(actualPath, finalMd)

        if (aborted) {
          if FileExist(expectedPath) {
            expectedFinal := FileRead(expectedPath, "UTF-8")
            ChkEqNorm("finalMd", finalMd, expectedFinal)
          } else {
            Log("  note: aborted scenario expected output missing, comparison skipped: " _Basename(expectedPath))
          }
          continue
        }

        if FileExist(expectedPath) {
          expectedFinal := FileRead(expectedPath, "UTF-8")
          ChkEqNorm("finalMd from " expectedPath, finalMd, expectedFinal)
        } else {
          Log("  note: expected output missing, comparison skipped: " _Basename(expectedPath))
        }

        Chk("no placeholder: ¤POSTER_", !InStr(finalMd, "¤POSTER_"))
        Chk("no placeholder: ¤USERMSG_", !InStr(finalMd, "¤USERMSG_"))
        Chk("no placeholder: ¤THINKING_", !InStr(finalMd, "¤THINKING_"))
        Chk("no placeholder: ¤CHK¤", !InStr(finalMd, "¤CHK¤"))
        Chk("no placeholder: ¤UNCHK¤", !InStr(finalMd, "¤UNCHK¤"))

      } finally {
        if (prevPromptFn != "" && HasMethod(PasteMd, "SetOrderedListPromptProvider"))
          PasteMd.SetOrderedListPromptProvider(prevPromptFn)
      }
    }
  } finally {
    Log("  Elapsed: " _FormatElapsedMs(A_TickCount - fixtureStartTick))
  }
}

Log("")
Log("Suite elapsed: " _FormatElapsedMs(A_TickCount - suiteStartTick))
TestFinish()

/**
 * Parses fixture harness CLI arguments.
 * Supported switches:
 * - /ls
 * - /fixture:<n|path>
 * - /log:<path>
 * - /fixtureOutputLogs:0|1
 * @param {Array} args - Raw CLI args (A_Args).
 * @param {integer} fixtureCount - Number of available fixtures.
 * @returns {Map} Parsed options map with optional error text.
 */
ParseHarnessOptions(args, fixtureCount) {
  opts := Map(
    "error", "",
    "listOnly", false,
    "fixtureIndex", 0,
    "fixturePath", "",
    "logPath", "",
    "emitFixtureOutputLogs", false
  )

  for arg in args {
    if RegExMatch(arg, "i)^/ls$") {
      opts["listOnly"] := true
      continue
    }
    if RegExMatch(arg, "i)^/fixture:(.+)$", &mFixture) {
      fixtureSpec := Trim(mFixture[1])
      if (opts["fixtureIndex"] > 0 || opts["fixturePath"] != "") {
        opts["error"] := "duplicate /fixture argument"
        return opts
      }
      if (fixtureSpec = "") {
        opts["error"] := "empty /fixture argument"
        return opts
      }
      if RegExMatch(fixtureSpec, "^\d+$") {
        idx := Integer(fixtureSpec)
        if (idx < 1 || idx > fixtureCount) {
          opts["error"] := "/fixture index out of range: " idx " (valid 1.." fixtureCount ")"
          return opts
        }
        opts["fixtureIndex"] := idx
      } else {
        opts["fixturePath"] := _ResolveFixturePath(fixtureSpec)
      }
      continue
    }
    if RegExMatch(arg, "i)^/fixtureOutputLogs:([01])$", &mOutput) {
      opts["emitFixtureOutputLogs"] := (mOutput[1] = "1")
      continue
    }
    if RegExMatch(arg, "i)^/log:(.+)$", &mLog) {
      if (opts["logPath"] != "") {
        opts["error"] := "duplicate /log argument"
        return opts
      }
      logSpec := Trim(mLog[1])
      if (logSpec = "") {
        opts["error"] := "empty /log argument"
        return opts
      }
      opts["logPath"] := _ResolveHarnessPath(logSpec)
      continue
    }

    opts["error"] := "unknown argument: " arg
    return opts
  }

  return opts
}

_ResolveFixturePath(fixtureSpec) {
  if RegExMatch(fixtureSpec, "i)^(?:[A-Z]:[\\/]|\\\\)")
    return fixtureSpec
  return A_ScriptDir "\" fixtureSpec
}

_ResolveHarnessPath(pathSpec) {
  if RegExMatch(pathSpec, "i)^(?:[A-Z]:[\\/]|\\\\)")
    return pathSpec
  return A_ScriptDir "\" pathSpec
}

_IsCustomFixtureArg(fixtureSpec) {
  return InStr(fixtureSpec, "\")
    || InStr(fixtureSpec, "/")
    || RegExMatch(fixtureSpec, "i)^[A-Z]:")
}

_FormatElapsedMs(elapsedMs) {
  return elapsedMs " ms (" Format("{:.3f}", elapsedMs / 1000.0) " s)"
}

/**
 * Writes the numbered fixture list to the harness log.
 * Used by /ls so users can target /fixture:<n>.
 * @param {Array} fixtures - Fixture descriptor objects.
 */
ListFixtures(fixtures) {
  Log("Fixture list")
  for fx in fixtures {
    Log("  " A_Index ". " fx)
  }
}

/**
 * Creates a deterministic prompt provider callback for scenario testing.
 * @param {string} response - Prompt response to return.
 * @returns {Func} Callback matching ordered-list prompt signature.
 */
MakePromptProvider(response) {
  return (defaultStart, expected, plain, htmlFrag) => response
}

/**
 * Expands fixture scenario metadata from the fixture log header.
 * If no metadata lines exist, returns a single default scenario.
 * @param {string} logText - Full fixture source log text.
 * @returns {Array} Scenario maps.
 */
ParseFixtureScenarios(logText) {
  scenarios := []

  if RegExMatch(logText, "m)^=== ", &mSec)
    header := SubStr(logText, 1, mSec.Pos - 1)
  else
    header := logText

  header := StrReplace(header, "`r", "")
  lines := StrSplit(header, "`n")
  metaLines := []

  Loop lines.Length {
    idx := A_Index
    if (idx = 1)
      continue
    line := Trim(lines[idx], " `t")
    if (line != "")
      metaLines.Push(line)
  }

  if (metaLines.Length = 0) {
    scenarios.Push(Map(
      "case", "",
      "hasPrompt", false,
      "prompt", "",
      "expectAbort", false,
      "asQuoted", true
    ))
    return scenarios
  }

  for line in metaLines {
    err := ""
    sc := ParseFixtureScenarioLine(line, &err)
    if (sc = 0) {
      Log("  invalid scenario metadata: " line)
      if (err != "")
        Log("  parse error: " err)
      return []
    }
    scenarios.Push(sc)
  }
  return scenarios
}

/**
 * Parses one metadata scenario line.
 * Accepted keys: case, prompt, expectAbort, asQuoted.
 * @param {string} line - One metadata line.
 * @param {string} err - Output parse/validation error text.
 * @returns {Map|integer} Scenario map, or 0 on parse error.
 */
ParseFixtureScenarioLine(line, &err := "") {
  err := ""
  pairs := Map()

  for part in StrSplit(line, ",") {
    part := Trim(part, " `t")
    if (part = "")
      continue
    if !RegExMatch(part, "i)^([a-z][a-z0-9_]*)\s*:\s*(.+)$", &mPair) {
      err := "invalid key:value pair: " part
      return 0
    }
    key := StrLower(mPair[1])
    value := Trim(mPair[2], " `t")
    pairs[key] := value
  }

  allowed := Map(
    "case", true,
    "prompt", true,
    "expectabort", true,
    "asquoted", true
  )
  for key, _ in pairs {
    if !allowed.Has(key) {
      err := "unknown metadata key: " key
      return 0
    }
  }

  if !pairs.Has("case") || Trim(pairs["case"], " `t") = "" {
    err := "case is required when metadata lines are present"
    return 0
  }

  scenario := Map(
    "case", pairs["case"],
    "hasPrompt", false,
    "prompt", "",
    "expectAbort", false,
    "asQuoted", true
  )

  if pairs.Has("prompt") {
    promptValue := Trim(pairs["prompt"], " `t")
    if (StrUpper(promptValue) != "CANCEL") {
      if !RegExMatch(promptValue, "^\d+$") || Integer(promptValue) < 1 {
        err := "prompt must be CANCEL or integer >= 1"
        return 0
      }
    }
    scenario["hasPrompt"] := true
    scenario["prompt"] := promptValue
  }

  if pairs.Has("expectabort") {
    val := Trim(pairs["expectabort"], " `t")
    if !RegExMatch(val, "^[01]$") {
      err := "expectAbort must be 0 or 1"
      return 0
    }
    scenario["expectAbort"] := (val = "1")
  }

  if pairs.Has("asquoted") {
    val := Trim(pairs["asquoted"], " `t")
    if !RegExMatch(val, "^[01]$") {
      err := "asQuoted must be 0 or 1"
      return 0
    }
    scenario["asQuoted"] := (val = "1")
  }

  return scenario
}

/**
 * Splits a debug log into named sections declared by "=== ... (len=n) ===".
 * @param {string} logText - Full debug log text.
 * @returns {Map} Section map: label -> { raw, len }.
 */
ParseDbgSections(logText) {
  sections := Map()
  firstHeaderPos := RegExMatch(logText, "m)^=== ", &mFirstHeader)
  if (!firstHeaderPos)
    return sections

  pos := firstHeaderPos
  pat := "s)^=== ([^\r\n]+?) \(len=(\d+)\) ===\r\n"
  sepLen := StrLen(PasteMd.LOG_SECTION_SEPARATOR)
  while (pos <= StrLen(logText)) {
    if !RegExMatch(SubStr(logText, pos), pat, &m) {
      throw Error("section header must start at character " pos " and use canonical CRLF framing")
    }

    label := m[1]
    sectionLen := Integer(m[2])
    contentStart := pos + m.Len
    contentEnd := contentStart + sectionLen - 1
    if (contentEnd > StrLen(logText)) {
      throw Error("section '" label "' len=" sectionLen " exceeds remaining file length")
    }

    content := SubStr(logText, contentStart, sectionLen)
    sections[label] := { raw: content, len: sectionLen }

    pos := contentStart + sectionLen
    if (pos > StrLen(logText))
      break

    if (SubStr(logText, pos, sepLen) != PasteMd.LOG_SECTION_SEPARATOR) {
      throw Error("section '" label "' must be followed by exactly one canonical CRLF separator block or EOF")
    }

    pos += sepLen
    if (pos > StrLen(logText))
      break
    if (SubStr(logText, pos, 4) != "=== ") {
      throw Error("unexpected text after section '" label "'; expected next header at character " pos)
    }
  }
  return sections
}

/**
 * Returns one parsed debug section and validates the declared length.
 * @param {Map} section - Section object containing raw and len.
 * @returns {string} Section text.
 */
SectionToText(section) {
  if (StrLen(section.raw) != section.len) {
    throw Error("section length mismatch: declared len=" section.len " actual len=" StrLen(section.raw))
  }
  return section.raw
}

/**
 * Normalizes line endings to LF for stable comparisons.
 * @param {string} s - Input text.
 * @returns {string} LF-normalized text.
 */
NormalizeEol(s) {
  s := StrReplace(s, "`r`n", "`n")
  s := StrReplace(s, "`r", "`n")
  return s
}

/**
 * Repeats a string count times.
 * @param {string} str - Token to repeat.
 * @param {integer} count - Repeat count.
 * @returns {string} Repeated string.
 */
StrRepeat(str, count) {
  return StrReplace(Format("{: " count ".s}", ""), " ", str)
}

/**
 * Formats a full got/expected detail block for failure logs.
 * @param {string} gotN - Normalized actual text.
 * @param {string} expectedN - Normalized expected text.
 * @param {string} suffix - Optional label suffix.
 * @returns {string} Formatted detail block.
 */
ChkGotExpectedDetail(gotN, expectedN, suffix := "") {
  return "`n🢃🢃🢃🢃    got" suffix "   🢃🢃🢃🢃`n" gotN      "🢀`n" StrRepeat("🢁", 18 + StrLen(suffix)) "`n"
       . "`n🢃🢃🢃🢃 expected" suffix " 🢃🢃🢃🢃`n" expectedN "🢀`n" StrRepeat("🢁", 18 + StrLen(suffix))
}

/**
 * Generates a git-style no-index word diff for failure diagnostics.
 * @param {string} gotN - Normalized actual text.
 * @param {string} expectedN - Normalized expected text.
 * @returns {string} Diff and full got/expected detail text.
 */
diff(gotN, expectedN) {
  try {
    gotName := A_Temp "\got_" A_ScriptHWnd ".txt"
    FileAppend(gotN, gotName, "UTF-8")
    expectedName := A_Temp "\expected_" A_ScriptHWnd ".txt"
    FileAppend(expectedN, expectedName, "UTF-8")

    cmd := "git diff "
      ; . " --word-diff=color"
      . " --word-diff-regex=`"([a-zA-Z_][a-zA-Z_0-9]*|0([xX]([0-9][a-fA-F])+|[0-7]+|[bB][01]+)|[1-9][0-9]*(\.[0-9]+)?([eE][0-9]+|[pP][0-9a-fA-F])?|\S|\s)`""
      . " --no-index " expectedName " " gotName
    stdout := StrReplace(exec(cmd).stdout, StrReplace(gotName, "\", "/"), "got",,,2)
    stdout := StrReplace(stdout, StrReplace(expectedName, "\", "/"), "expected",,,2)
    return "`n" StrRepeat("🢃", 80) "`n" stdout "`n" StrRepeat("🢁", 80)
      . "`n" ChkGotExpectedDetail(gotN, expectedN)
  } finally {
    try FileDelete(gotName)
    try FileDelete(expectedName)
  }

  ; shell := ComObject("WScript.Shell")
  ; exec := shell.Exec(cmd)

  ; while (exec.Status == 0) {
  ;   Sleep 100
  ; }
  ; if 1
  ; return exec.StdOut.ReadAll()
}

/**
 * Executes a shell command and captures stdout/stderr.
 * @param {string} cmd - Command line to execute.
 * @param {string} id - Optional temp-file id prefix.
 * @returns {Map} Map with stdout and stderr text.
 */
exec(cmd, id := "") {
  try {
    stdout := A_Temp "\" id "_stdout_" A_ScriptHWnd
    stderr := A_Temp "\" id "_stderr_" A_ScriptHWnd
    shellCmd := Format('{1} /d /c {2} > "{3}" 2> "{4}"'
      , A_ComSpec, cmd, stdout, stderr)

    ; FileAppend shellCmd, "**", "UTF-8"
    shell := ComObject("WScript.Shell")
    exitCode := shell.Run(shellCmd, 0, true) ; hidden, wait for completion

    ; use 7 instead of 0 for minimized
    result := {
      stdout: FileRead(stdout, "UTF-8"),
      stderr: FileRead(stderr, "UTF-8")
    }
    return result
  } finally {
    try FileDelete(stdout)
    try FileDelete(stderr)
  }
}

/**
 * Compares expected/actual text after EOL normalization.
 * Logs an annotated diff block on mismatch.
 * @param {string} label - Assertion label.
 * @param {string} got - Actual text.
 * @param {string} expected - Expected text.
 */
ChkEqNorm(label, got, expected) {
  gotN := NormalizeEol(got)
  expectedN := NormalizeEol(expected)
  detail := "`ngot len=" StrLen(gotN) " expected len=" StrLen(expectedN)

  cond := gotN = expectedN
  if (!cond) {
    detail .= diff(gotN, expectedN)
  }
  Chk(label, cond, detail)
}

/**
 * Replaces a .log suffix with a sibling suffix.
 * @param {string} path - Source path.
 * @param {string} suffix - Replacement suffix.
 * @returns {string} Derived sibling path.
 */
_SiblingWithSuffix(path, suffix) {
  if RegExMatch(path, "i)\.log$")
    return RegExReplace(path, "i)\.log$", suffix)
  return path . suffix
}

/**
 * Writes UTF-8 text to a file path.
 * @param {string} path - Output file path.
 * @param {string} text - Text payload.
 */
_WriteUtf8(path, text) {
  f := FileOpen(path, "w", "UTF-8")
  f.Write(text)
  f.Close()
}

/**
 * Writes a replay-style output log for one fixture scenario.
 * Uses the same stage labels as runtime PasteAsMd debug logs.
 * @param {string} path - Output .fixture.log path.
 * @param {string} plain - Plain text seam input.
 * @param {string} cfHtml - CF_HTML seam input.
 * @param {Map} converted - Stage outputs from _ConvertFromCaptured.
 * @param {boolean} asQuoted - Whether quoted stage is present.
 */
_WriteFixtureOutputLog(path, plain, cfHtml, converted, asQuoted := true) {
  f := FileOpen(path, "w", "UTF-8")
  try {
    f.Write("PasteAsMd debug — " FormatTime(, "yyyy-MM-dd HH:mm:ss") PasteMd.LOG_SECTION_SEPARATOR)
    PasteMd._DbgSection(f, PasteMd.LOG_SECTION_SOURCE, converted["source"])
    PasteMd._DbgSection(f, PasteMd.LOG_SECTION_PLAIN, plain)
    PasteMd._DbgSection(f, PasteMd.LOG_SECTION_CFHTML, cfHtml, true)
    PasteMd._DbgSection(f, PasteMd.LOG_SECTION_HTML_FRAG, converted["htmlFragRaw"], true)
    PasteMd._WriteCfHtmlOffsetsSection(f, cfHtml)

    if (converted["htmlFrag"] = "") {
      PasteMd._DbgSection(f, "3. md (CleanPlainText – no HTML path)", converted["mdAfterClean"])
    } else {
      PasteMd._DbgSection(f, "3. htmlPrep (after _PreprocessHtml)", converted["htmlPrep"])
      if (converted["usedNoTagPlainPath"]) {
        PasteMd._DbgSection(f, "3b. md (no HTML tags → plain text path)", converted["mdAfterClean"])
      } else {
        PasteMd._DbgSection(f, "4. mdRaw (pandoc output)", converted["mdRaw"])
        PasteMd._DbgSection(f, "5. md (after CleanMarkdown)", converted["mdAfterClean"])
      }
      PasteMd._DbgSection(f, "5c. expected list start (ordered-list fix)", "" converted["expectedListStart"])
      PasteMd._DbgSection(f, "5d. md (after RestoreOrderedListStart)", converted["mdAfterOrderedList"])
    }

    if (asQuoted)
      PasteMd._DbgSection(f, "5e. md (after SHOW_POSTER replacement)", converted["mdAfterPoster"])

    PasteMd._DbgSection(f, "6. FINAL md (pasted)", converted["finalMd"])
  } finally {
    f.Close()
  }
}

/**
 * Returns filename component from a path.
 * @param {string} path - Input path.
 * @returns {string} Basename only.
 */
_Basename(path) {
  SplitPath(path, &name)
  return name
}
