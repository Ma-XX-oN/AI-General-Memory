;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Paste as md
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
#Requires AutoHotkey v2.0
#SingleInstance Force

; Ctrl+Alt+Shift+V
^!+v::ShowPasteMenu()

; Change this if pandoc isn't on PATH.
PANDOC_EXE := "C:\Users\adria\AppData\Local\Pandoc\pandoc.exe"

PASTE_DELAY_MS := 50

global gPasteMenu := Menu()
gPasteMenu.Add("Paste as md", PasteAsMd)
gPasteMenu.Add("Paste as md quoted", PasteAsMdQuoted)

; Show the markdown paste menu at the current cursor position.
ShowPasteMenu() {
  global gPasteMenu
  gPasteMenu.Show()
}

; Menu callback: paste clipboard content as markdown.
PasteAsMd(ItemName, ItemPos, MenuObj) {
  PasteMarkdown(false)
}

; Menu callback: paste clipboard content as quoted markdown.
PasteAsMdQuoted(ItemName, ItemPos, MenuObj) {
  PasteMarkdown(true)
}

#Include ClipHelper.ahk
; Convert current clipboard content to markdown (or quoted markdown) and paste.
; Prefer CF_HTML -> pandoc conversion, with plain-text fallback.
; asQuoted: true to prefix every line with markdown blockquote syntax.
PasteMarkdown(asQuoted) {
  global PANDOC_EXE, PASTE_DELAY_MS

  clipSaved := ClipboardAll()
  plain := StrReplace(A_Clipboard, "`r", "")
  static log := logger2()
  try {
    htmlFrag := ClipboardWaiter.GetHtmlSection()
    ; log.log_txt("=== htmlFrag ===`n`n" htmlFrag "`n`n")
    if (htmlFrag = "") {
      md := CleanPlainText(plain)
    } else {
      md := HtmlToGfmViaPandoc(htmlFrag, PANDOC_EXE)
      ; log.log_txt("=== md converted ===`n`n" md "`n`n")
      md := CleanMarkdown(md)
      ; log.log_txt("=== md clean ===" md "`n`n")
      md := StrReplace(md, "`r", "")

      ; Never paste empty.  If conversion failed/empty, use plain text.
      if (Trim(md, " `t`n") = "" && Trim(plain, " `t`n") != "") {
        md := CleanPlainText(plain)
      }
    }

    if (asQuoted) {
      md := QuoteMarkdown(md)
    }

    ; Remove CR unconditionally (LF-only).
    md := StrReplace(md, "`r", "")

    A_Clipboard := md
    Send "^v"
    Sleep PASTE_DELAY_MS
  } catch as e {
    MsgBox "Paste-as-markdown " e.File ":" e.Line " failed:`n`n" e.Message
  } finally {
    A_Clipboard := clipSaved
  }
}
; #Include ClipHelper.ahk
; if (0) {
;   return ClipboardWaiter.GetHtml(10000)
; }

; Read HTML fragment bytes from clipboard CF_HTML and return decoded UTF-8 text.
; Returns "" if format is unavailable, malformed, or clipboard access fails.
GetClipboardHtmlFragment() {
  ; CF_HTML uses the registered clipboard format name "HTML Format".
  ; It includes StartFragment/EndFragment byte offsets.

  cfHtml := DllCall(
    "RegisterClipboardFormat",
    "Str", "HTML Format",
    "UInt"
  )

  if (cfHtml = 0) {
    return ""
  }

  if !DllCall("OpenClipboard", "Ptr", A_ScriptHwnd, "Int") {
    return ""
  }

  try {
    hMem := DllCall("GetClipboardData", "UInt", cfHtml, "Ptr")
    if (hMem = 0) {
      return ""
    }

    pMem := DllCall("GlobalLock", "Ptr", hMem, "Ptr")
    if (pMem = 0) {
      return ""
    }

    try {
      cb := DllCall("GlobalSize", "Ptr", hMem, "UPtr")
      if (cb = 0) {
        return ""
      }

      buf := Buffer(cb, 0)
      DllCall("RtlMoveMemory", "Ptr", buf.Ptr, "Ptr", pMem, "UPtr", cb)

      ; Header is ASCII; decode only header region as CP0 for offset parsing.
      hdrLen := cb < 8192 ? cb : 8192
      header := StrGet(buf.Ptr, hdrLen, "CP0")

      start := ParseCfHtmlOffset(header, "StartFragment:")
      finish := ParseCfHtmlOffset(header, "EndFragment:")

      if (start < 0 || finish < 0 || finish <= start || finish > cb) {
        return ""
      }

      ; Decode fragment bytes as UTF-8 to avoid mojibake.
      html := Utf8BytesToString(buf.Ptr + start, finish - start)
      html := StrReplace(html, "<!--StartFragment -->", "")
      html := StrReplace(html, "<!--EndFragment -->", "")
      return html
    } finally {
      DllCall("GlobalUnlock", "Ptr", hMem)
    }
  } finally {
    DllCall("CloseClipboard")
  }
}

; Parse a numeric CF_HTML header offset for a key like "StartFragment:".
; Returns -1 if key is missing or value is invalid.
ParseCfHtmlOffset(cf, key) {
  pos := InStr(cf, key)
  if (pos = 0) {
    return -1
  }

  pos += StrLen(key)
  eol := InStr(cf, "`r`n", , pos)
  if (eol = 0) {
    eol := InStr(cf, "`n", , pos)
  }
  if (eol = 0) {
    return -1
  }

  numStr := SubStr(cf, pos, eol - pos)
  numStr := Trim(numStr)
  if (numStr = "") {
    return -1
  }

  return numStr + 0
}

; Decode a UTF-8 byte range into an AutoHotkey UTF-16 string.
; Returns "" when conversion fails.
Utf8BytesToString(ptr, byteLen) {
  cpUtf8 := 65001

  wlen := DllCall("MultiByteToWideChar"
    , "UInt", cpUtf8
    , "UInt", 0
    , "Ptr", ptr
    , "Int", byteLen
    , "Ptr", 0
    , "Int", 0
    , "Int")

  if (wlen <= 0) {
    return ""
  }

  wbuf := Buffer((wlen + 1) * 2, 0)

  out := DllCall("MultiByteToWideChar"
    , "UInt", cpUtf8
    , "UInt", 0
    , "Ptr", ptr
    , "Int", byteLen
    , "Ptr", wbuf.Ptr
    , "Int", wlen
    , "Int")

  if (out != wlen) {
    return ""
  }

  return StrGet(wbuf.Ptr, wlen, "UTF-16")
}

; Run pandoc to convert HTML content into GitHub-flavored markdown.
; Returns markdown text or "" on conversion/read failure.
HtmlToGfmViaPandoc(html, pandocExe) {
  tmpBase := A_Temp "\chatgpt_md_" A_TickCount
  tmpHtml := tmpBase ".html"
  tmpMd := tmpBase ".md"

  try FileDelete tmpHtml
  try FileDelete tmpMd

  ; Write UTF-8 without BOM.
  f := FileOpen(tmpHtml, "w", "UTF-8-RAW")
  f.Write(html)
  f.Close()

  ; No wrapping, LF-only.
  cmd := '"' . pandocExe . '" -f html -t gfm --wrap=none --eol=lf "' . tmpHtml . '"'
  cmd .= ' -o "' . tmpMd . '"'

  exitCode := RunWait(cmd, , "Hide")
  if (exitCode != 0) {
    try FileDelete tmpHtml
    try FileDelete tmpMd
    return ""
  }

  md := ""
  try {
    md := FileRead(tmpMd, "UTF-8")
  } catch {
    md := ""
  }

  try FileDelete tmpHtml
  try FileDelete tmpMd

  return md
}

; Normalize plain text for markdown-safe paste:
; remove CR, trim trailing horizontal whitespace, trim edge blank lines.
CleanPlainText(s) {
  s := StrReplace(s, "`r", "")
  lines := StrSplit(s, "`n")
  out := ""
  for i, line in lines {
    line := RTrim(line, " `t")
    out .= (i = 1 ? "" : "`n") . line
  }
  return Trim(out, "`n")
}

; Normalize markdown lines and simplify inline HTML where safe.
; Preserves fenced code blocks.
CleanMarkdown(md) {
  md := StrReplace(md, "`r", "")
  lines := StrSplit(md, "`n")

  out := ""
  inFence := false

  for i, line in lines {
    t := LTrim(line, " `t")

    ; Fence detection without regex (avoids backtick-escape problems).
    if (SubStr(t, 1, 3) = "``````") {
      inFence := !inFence
      outLine := RTrim(line, " `t")
      out .= (out = "" ? "" : "`n") . outLine
      continue
    }

    if (inFence) {
      out .= (out = "" ? "" : "`n") . line
      continue
    }

    outLine := RTrim(line, " `t")

    ; Drop empty headings like "###" or "### ".
    if RegExMatch(outLine, "^[#]{1,6}\s*$") {
      continue
    }

    outLine := SimplifyMarkdownInlineHtml(outLine)
    out .= (out = "" ? "" : "`n") . outLine
  }

  return Trim(out, "`n")
}

re_htags := "
(
  |(?x)(?!)
  (?<quoted_string> (?<quote>["'])(?:[^"'\\]*+|\\.|(?!\k<quote>).)++\k<quote>)
  (?<inside_htag>
    (?:
        [^<>\\'"]++                            (?# non-tag marker )
      | \\.                                    (?# non-escape marker )
      | (?&quoted_string)
      | < (?!/) (?<inner_id>[a-z]++) (?: [^>'"]++ | (?=['"])(?&quoted_string) )*+
        (?:
            (?<= / ) >                         (?# open/close tag so nothing inside )
          | > (?&inside_htag) </ \k<inner_id>\b >
        `)
    `)*+
  `)
)"

; Convert common inline HTML constructs into markdown equivalents and
; strip residual non-escaped tags that reduce readability.
SimplifyMarkdownInlineHtml(line) {
  line := DecodeBasicHtmlEntities(line)

  ; Chat/app UI exports often wrap inline code in styled spans.
  while RegExMatch(line, "<span\b[^>]*>((?&inside_htag))</span>" re_htags, &m) {
    inner := DecodeBasicHtmlEntities(m[1])
    inner := StrReplace(inner, "`r", "")
    inner := StrReplace(inner, "`n", " ")
    replacement := (inner = "") ? "" : ("``" . inner . "``")
    line := SubStr(line, 1, m.Pos - 1) . replacement . SubStr(line, m.Pos + m.Len)
  }

  while RegExMatch(line, "<code\b[^>]*+>((?&inside_htag))</code>" re_htags, &m) {
    inner := DecodeBasicHtmlEntities(m[1])
    inner := StrReplace(inner, "`r", "")
    inner := StrReplace(inner, "`n", " ")
    replacement := (inner = "") ? "" : ("``" . inner . "``")
    line := SubStr(line, 1, m.Pos - 1) . replacement . SubStr(line, m.Pos + m.Len)
  }

  ; Convert semantic emphasis tags before fallback stripping.
  while RegExMatch(line, "<(strong|b)\b[^>]*+>((?&inside_htag))</\1>" re_htags, &m) {
    replacement := (m[2] = "") ? "" : ("**" . m[2] . "**")
    line := SubStr(line, 1, m.Pos - 1) . replacement . SubStr(line, m.Pos + m.Len)
  }
  while RegExMatch(line, "<(em|i)\b[^>]*+>((?&inside_htag))</\1>" re_htags, &m) {
    replacement := (m[2] = "") ? "" : ("*" . m[2] . "*")
    line := SubStr(line, 1, m.Pos - 1) . replacement . SubStr(line, m.Pos + m.Len)
  }

  ; Convert HTML links to markdown links for readable output.
  while RegExMatch(line, "<a\b[^>]*\bhref\s*=\s*(['`"])(.*?)\1[^>]*>((?&inside_htag))</a>" re_htags, &m) {
    href := DecodeBasicHtmlEntities(m[2])
    text := DecodeBasicHtmlEntities(m[3])

    ; Convert semantic emphasis inside link text before stripping residual tags.
    while RegExMatch(text, "<(strong|b)\b[^>]*>((?&inside_htag))</\1>" re_htags, &inner) {
      replacement := (inner[2] = "") ? "" : ("**" . inner[2] . "**")
      text := SubStr(text, 1, inner.Pos - 1) . replacement . SubStr(text, inner.Pos + inner.Len)
    }
    while RegExMatch(text, "<(em|i)\b[^>]*>((?&inside_htag))</\1>" re_htags, &inner) {
      replacement := (inner[2] = "") ? "" : ("*" . inner[2] . "*")
      text := SubStr(text, 1, inner.Pos - 1) . replacement . SubStr(text, inner.Pos + inner.Len)
    }

    ; Remove any unknown tags that are not escaped
    text := RegExReplace(text, "((?&inside_htag))<[^>]++>" re_htags, "$1")
    if (text = "") {
      text := href
    }
    replacement := "[" . text . "](" . href . ")"
    line := SubStr(line, 1, m.Pos - 1) . replacement . SubStr(line, m.Pos + m.Len)
  }

  ; Remove any unknown tags that are not escaped
  line := RegExReplace(line, "\G((?&inside_htag))(?<!\\)<(?:[^>'`"]++|(?&quoted_string))*+>" re_htags, "$1")
  line := RegExReplace(line, "((?:[^\\]|\\[^<>])++)\\([<>])" re_htags, "$1$2")
  ; Strip common presentational tags that hurt readability in markdown output.
  ; line := RegExReplace(line, "</?(?:div|p|font|mark|u|small|sup|sub)\b[^>]*>", "")
  ; line := RegExReplace(line, "<br\s*/?>", " ")

  return line
}

; Decode a minimal set of common HTML entities used in copied fragments.
DecodeBasicHtmlEntities(s) {
  s := StrReplace(s, Chr(160), " ")
  s := StrReplace(s, "&nbsp;", Chr(160))
  s := StrReplace(s, "&#160;", Chr(160))
  s := StrReplace(s, "&quot;", '"')
  s := StrReplace(s, "&#34;", '"')
  s := StrReplace(s, "&apos;", "'")
  s := StrReplace(s, "&#39;", "'")
  s := StrReplace(s, "&lt;", "<")
  s := StrReplace(s, "&gt;", ">")
  s := StrReplace(s, "&amp;", "&")
  return s
}

; Convert markdown to blockquote form by prefixing each line with ">".
QuoteMarkdown(md) {
  ; Prefix each line.  Blank lines become ">" (no trailing space).
  md := StrReplace(md, "`r", "")
  lines := StrSplit(md, "`n")

  out := ""
  for i, line in lines {
    line := RTrim(line, " `t")
    q := (line = "") ? ">" : ("> " . line)
    out .= (i = 1 ? "" : "`n") . q
  }

  return Trim(out, "`n")
}

