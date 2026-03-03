#ErrorStdOut
#Requires AutoHotkey v2.0
#Include ../PasteAsMd.ahk
#Include test-helpers.ahk

_logPath := A_ScriptDir "\test-paste-md-fixtures.log"
try FileDelete _logPath

passed := 0
failed := 0

fixtures := [
  { file: "PasteAsMd_ClaudeCode.log",           source: "claudecode", withUser: false, assistantLabel: "Claude Code" },
  { file: "PasteAsMd_ClaudeCode-with-User.log", source: "claudecode", withUser: true,  assistantLabel: "Claude Code" },
  { file: "PasteAsMd_ClaudeWeb.log",            source: "claudeweb",  withUser: false, assistantLabel: "Claude Web" },
  { file: "PasteAsMd_ClaudeWeb-with-User.log",  source: "claudeweb",  withUser: true,  assistantLabel: "Claude Web" },
  { file: "PasteAsMd_Codex.log",                source: "codex",      withUser: false, assistantLabel: "Codex" },
  { file: "PasteAsMd_Codex-with-User.log",      source: "codex",      withUser: true,  assistantLabel: "Codex" },
  { file: "PasteAsMd_Codex-EditedFile.log",     source: "codex",      withUser: false, assistantLabel: "Codex" },
  { file: "PasteAsMd_ChatGPT.log",              source: "chatgpt",    withUser: false, assistantLabel: "ChatGPT" },
  { file: "PasteAsMd_ChatGPT-with-User.log",    source: "chatgpt",    withUser: true,  assistantLabel: "ChatGPT" },
  { file: "PasteAsMd_ChatGPT-with-User2.log",   source: "chatgpt",    withUser: true,  assistantLabel: "ChatGPT" },
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
  expectedPath := _SiblingWithSuffix(path, expectedSuffix)
  actualPath := _SiblingWithSuffix(path, actualSuffix)
  Log("")
  Log("Fixture: " fx.file)

  Chk("fixture exists", FileExist(path) != "", path)
  if !FileExist(path)
    continue

  logText := FileRead(path, "UTF-8")
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

  converted := PasteMd._ConvertFromCaptured(plain, cfHtml, true, fx.withUser, false, false, "")

  ChkEqNorm("source", converted["source"], fx.source)

  finalMd := converted["finalMd"]
  _WriteUtf8(actualPath, finalMd)

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
}

Log("")
Log("Results: " passed " passed, " failed " failed")
ExitApp

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
  ; Reverse _DbgSection's marker stream exactly (CRLF-aware).
  tokCRLF := "⏎¶⏎`r¶`r`n¶`r`n"
  tokCR := "⏎`r¶`r`n"
  tokLF := "¶`r`n"
  tokCRLF_LF := "⏎¶⏎`r¶`n¶`n"
  tokCR_LF := "⏎`r¶`n"
  tokLF_LF := "¶`n"
  out := ""
  pos := 1
  while (pos <= StrLen(s)) {
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
    if (SubStr(s, pos, StrLen(tokCRLF_LF)) = tokCRLF_LF) {
      out .= "`r`n"
      pos += StrLen(tokCRLF_LF)
      continue
    }
    if (SubStr(s, pos, StrLen(tokCR_LF)) = tokCR_LF) {
      out .= "`r"
      pos += StrLen(tokCR_LF)
      continue
    }
    if (SubStr(s, pos, StrLen(tokLF_LF)) = tokLF_LF) {
      out .= "`n"
      pos += StrLen(tokLF_LF)
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

ChkEqNorm(label, got, expected) {
  gotN := NormalizeEol(got)
  expectedN := NormalizeEol(expected)
  detail := "got len=" StrLen(gotN) " expected len=" StrLen(expectedN)
  if (StrLen(gotN) <= 40 && StrLen(expectedN) <= 40) {
    detail .= " got=`"" gotN "`" expected=`"" expectedN "`""
  } else {
    detail .= " got head=`"" SubStr(gotN, 1, 24) "`" expected head=`"" SubStr(expectedN, 1, 24) "`""
    detail .= " got tail=`"" SubStr(gotN, -23) "`" expected tail=`"" SubStr(expectedN, -23) "`""
  }
  Chk(label, gotN = expectedN, detail)
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
