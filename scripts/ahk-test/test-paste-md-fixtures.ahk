#ErrorStdOut
#Requires AutoHotkey v2.0
#Include ../PasteAsMd.ahk
#Include test-helpers.ahk

_logPath := A_ScriptDir "\test-paste-md-fixtures.log"
try FileDelete _logPath

passed := 0
failed := 0

fixtures := [
  { file: "PasteAsMd_ClaudeCode.log",               source: "claudecode", withUser: false, assistantLabel: "Claude Code" },
  { file: "PasteAsMd_ClaudeCode-with-User.log",     source: "claudecode", withUser: true,  assistantLabel: "Claude Code" },
  { file: "PasteAsMd_ClaudeWeb.log",                source: "claudeweb",  withUser: false, assistantLabel: "Claude Web" },
  { file: "PasteAsMd_ClaudeWeb-with-User.log",      source: "claudeweb",  withUser: true,  assistantLabel: "Claude Web" },
  { file: "PasteAsMd_Codex.log",                    source: "codex",      withUser: false, assistantLabel: "Codex" },
  { file: "PasteAsMd_Codex-with-User.log",          source: "codex",      withUser: true,  assistantLabel: "Codex" },
  { file: "PasteAsMd_Codex-EditedFile.log",         source: "codex",      withUser: false, assistantLabel: "Codex" },
  { file: "PasteAsMd_Codex-OrderedList-Parent.log", source: "unknown",    withUser: false, assistantLabel: "Codex" },
  { file: "PasteAsMd_Codex-OrderedList-Nested.log", source: "unknown",    withUser: false, assistantLabel: "Codex" },
  { file: "PasteAsMd_Codex-OrderedList-Prompt.log", source: "codex",      withUser: false, assistantLabel: "Codex" },
  { file: "PasteAsMd_Codex-NestedShell-UL.log",     source: "codex",      withUser: false, assistantLabel: "Codex" },
  { file: "PasteAsMd_Codex-NestedShell-OL.log",     source: "codex",      withUser: false, assistantLabel: "Codex" },
  { file: "PasteAsMd_ChatGPT.log",                  source: "chatgpt",    withUser: false, assistantLabel: "ChatGPT" },
  { file: "PasteAsMd_ChatGPT-with-User.log",        source: "chatgpt",    withUser: true,  assistantLabel: "ChatGPT" },
  { file: "PasteAsMd_ChatGPT-with-User2.log",       source: "chatgpt",    withUser: true,  assistantLabel: "ChatGPT" },
]

expectedSuffix := ".expected.md"
actualSuffix := ".actual.md"

required := [
  "1. plain (A_Clipboard minus CR)",
  "2. cfHtml (raw full payload)",
]

Log("── PasteAsMd fixture regressions ─────────────────────────────")
for fx in fixtures {
  path := A_ScriptDir "\" fx.file
  Log("")
  Log("Fixture: " fx.file)

  Chk("fixture exists", FileExist(path) != "", path)
  if !FileExist(path)
    continue

  logText := FileRead(path, "UTF-8")
  scenarios := ParseFixtureScenarios(logText)
  Chk("scenario metadata parsed", scenarios.Length > 0)
  if (scenarios.Length = 0)
    continue

  sections := ParseDbgSections(logText)

  missing := false
  for label in required {
    has := sections.Has(label)
    Chk("section present: " label, has)
    if !has
      missing := true
  }
  if missing
    continue

  ; Inputs for seam: plain + cfHtml decoded from captured debug sections.
  plain := SectionToText(sections["1. plain (A_Clipboard minus CR)"])
  cfHtml := SectionToText(sections["2. cfHtml (raw full payload)"])
  for sc in scenarios {
    caseId := sc["case"]
    expectedPath := _SiblingWithSuffix(path, caseId = "" ? expectedSuffix : ("." caseId expectedSuffix))
    actualPath := _SiblingWithSuffix(path, caseId = "" ? actualSuffix : ("." caseId actualSuffix))
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

      converted := PasteMd._ConvertFromCaptured(plain, cfHtml, true, fx.withUser, false, sc["hasPrompt"])
      ChkEqNorm("source", converted["source"], fx.source)
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
        ChkEqNorm("finalMd", finalMd, expectedFinal)
      } else {
        Log("  note: expected output missing, comparison skipped: " _Basename(expectedPath))
      }

      Chk("no placeholder: ¤POSTER_", !InStr(finalMd, "¤POSTER_"))
      Chk("no placeholder: ¤USERMSG_", !InStr(finalMd, "¤USERMSG_"))
      Chk("no placeholder: ¤THINKING_", !InStr(finalMd, "¤THINKING_"))
      Chk("no placeholder: ¤CHK¤", !InStr(finalMd, "¤CHK¤"))
      Chk("no placeholder: ¤UNCHK¤", !InStr(finalMd, "¤UNCHK¤"))

      if fx.withUser {
        Chk("with-user has User label", InStr(finalMd, "## User"))
        Chk("with-user has assistant label", InStr(finalMd, "## " fx.assistantLabel))
      }
    } finally {
      if (prevPromptFn != "" && HasMethod(PasteMd, "SetOrderedListPromptProvider"))
        PasteMd.SetOrderedListPromptProvider(prevPromptFn)
    }
  }
}

Log("")
Log("Results: " passed " passed, " failed " failed")
ExitApp

MakePromptProvider(response) {
  return (defaultStart, expected, plain, htmlFrag) => response
}

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
      "expectAbort", false
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

  if !pairs.Has("case") || Trim(pairs["case"], " `t") = "" {
    err := "case is required when metadata lines are present"
    return 0
  }

  scenario := Map(
    "case", pairs["case"],
    "hasPrompt", false,
    "prompt", "",
    "expectAbort", false
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

  return scenario
}

ParseDbgSections(logText) {
  sections := Map()
  pat := "ms)^=== ([^\r\n]+?) \(len=(\d+)\) ===\R"
  pos := 1
  while RegExMatch(logText, pat, &m, pos) {
    label := m[1]
    sectionLen := Integer(m[2])
    contentStart := m.Pos + m.Len
    if RegExMatch(logText, "m)^=== ", &mNextAny, contentStart) {
      content := SubStr(logText, contentStart, mNextAny.Pos - contentStart)
      pos := mNextAny.Pos
    } else {
      content := SubStr(logText, contentStart)
      pos := StrLen(logText) + 1
    }
    sections[label] := { raw: TrimDbgSectionContent(content), len: sectionLen }
  }
  return sections
}

TrimDbgSectionContent(s) {
  if (SubStr(s, -3) = "`r`n`r`n")
    return SubStr(s, 1, StrLen(s) - 4)
  if (SubStr(s, -1) = "`n`n")
    return SubStr(s, 1, StrLen(s) - 2)
  return s
}

SectionToText(section) {
  s := DecodeDbgExact(section.raw)
  if (StrLen(s) > section.len)
    s := SubStr(s, 1, section.len)
  return s
}

DecodeDbgExact(s) {
  ; Reverse _DbgSection marker stream for:
  ; - current LF-only logger output
  ; - legacy output normalized to LF
  tokLegacyCRLF := "⏎¶⏎`n¶`n¶`n"
  tokLegacyCR := "⏎`n¶`n"
  tokCRLF := "⏎¶`n"
  tokCR := "⏎`n"
  tokLF := "¶`n"
  out := ""
  pos := 1
  while (pos <= StrLen(s)) {
    if (SubStr(s, pos, StrLen(tokLegacyCRLF)) = tokLegacyCRLF) {
      out .= "`r`n"
      pos += StrLen(tokLegacyCRLF)
      continue
    }
    if (SubStr(s, pos, StrLen(tokLegacyCR)) = tokLegacyCR) {
      out .= "`r"
      pos += StrLen(tokLegacyCR)
      continue
    }
    if (SubStr(s, pos, StrLen(tokCRLF)) = tokCRLF) {
      out .= "`r`n"
      pos += StrLen(tokCRLF)
      continue
    }
    if (SubStr(s, pos, StrLen(tokCR)) = tokCR) {
      out .= "`r"
      pos += StrLen(tokCR)
      continue
    }
    if (SubStr(s, pos, StrLen(tokLF)) = tokLF) {
      out .= "`n"
      pos += StrLen(tokLF)
      continue
    }
    out .= SubStr(s, pos, 1)
    pos += 1
  }
  return out
}

NormalizeEol(s) {
  s := StrReplace(s, "`r`n", "`n")
  s := StrReplace(s, "`r", "`n")
  return s
}

StrRepeat(str, count) {
  return StrReplace(Format("{: " count ".s}", ""), " ", str)
}

ChkGotExpectedDetail(gotN, expectedN, suffix := "") {
  return "`n🢃🢃🢃🢃    got" suffix "   🢃🢃🢃🢃`n" gotN      "🢀`n" StrRepeat("🢁", 18 + StrLen(suffix))
       . "`n🢃🢃🢃🢃 expected" suffix " 🢃🢃🢃🢃`n" expectedN "🢀`n" StrRepeat("🢁", 18 + StrLen(suffix))
}

ChkEqNorm(label, got, expected) {
  gotN := NormalizeEol(got)
  expectedN := NormalizeEol(expected)
  detail := "got len=" StrLen(gotN) " expected len=" StrLen(expectedN)
  cond := gotN = expectedN
  if (!cond) {
    if (StrLen(gotN) <= 100 && StrLen(expectedN) <= 100) {
      detail .= ChkGotExpectedDetail(gotN, expectedN)
    } else {
      len := 50
      detail .= ChkGotExpectedDetail(SubStr(gotN, 1, len), SubStr(expectedN, 1, len), " head")
      detail .= ChkGotExpectedDetail(SubStr(gotN, -len+1), SubStr(expectedN, -len+1),   " tail")
    }
  }
  Chk(label, cond, detail)
}

_SiblingWithSuffix(path, suffix) {
  if RegExMatch(path, "i)\.log$")
    return RegExReplace(path, "i)\.log$", suffix)
  return path . suffix
}

_WriteUtf8(path, text) {
  f := FileOpen(path, "w", "UTF-8")
  f.Write(text)
  f.Close()
}

_Basename(path) {
  SplitPath(path, &name)
  return name
}
