;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Paste as md
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
#Requires AutoHotkey v2.0
#SingleInstance Force
#Include ClipHelper.ahk

; Ctrl+Alt+Shift+V
^!+v::ShowPasteMenu()

; Change this if pandoc isn't on PATH.
PANDOC_EXE := "C:\Users\adria\AppData\Local\Pandoc\pandoc.exe"

PASTE_DELAY_MS := 50

global gPasteMenu := Menu()
gPasteMenu.Add("Paste as md", PasteAsMd)
gPasteMenu.Add("Paste as md quoted", PasteAsMdQuoted)

/**
 * Shows the markdown paste menu at the current cursor position.
 */
ShowPasteMenu() {
  global gPasteMenu
  gPasteMenu.Show()
}

/**
 * Menu callback: pastes clipboard content as markdown.
 * @param {string} ItemName - Menu item label
 * @param {number} ItemPos - Menu item position
 * @param {object} MenuObj - Menu object
 */
PasteAsMd(ItemName, ItemPos, MenuObj) {
  PasteMd.PasteMarkdown(false)
}

/**
 * Menu callback: pastes clipboard content as quoted markdown (blockquote).
 * @param {string} ItemName - Menu item label
 * @param {number} ItemPos - Menu item position
 * @param {object} MenuObj - Menu object
 */
PasteAsMdQuoted(ItemName, ItemPos, MenuObj) {
  PasteMd.PasteMarkdown(true)
}

class PasteMd {
  /**
   * Converts clipboard content to markdown (or quoted markdown) and pastes it.
   * Prefers CF_HTML → pandoc conversion, with plain-text fallback.
   * @param {boolean} asQuoted - If true, prefixes every line with blockquote syntax (>).
   */
  static PasteMarkdown(asQuoted) {
  global PANDOC_EXE, PASTE_DELAY_MS

  clipSaved := ClipboardAll()
  plain := StrReplace(A_Clipboard, "`r", "")
  try {
    htmlFrag := ClipboardWaiter.GetHtmlSection()
    if (htmlFrag = "") {
      md := PasteMd.CleanPlainText(plain)
    } else {
      md := PasteMd.HtmlToGfmViaPandoc(htmlFrag, PANDOC_EXE)
      md := PasteMd.CleanMarkdown(md)
      md := StrReplace(md, "`r", "")

      ; Never paste empty.  If conversion failed/empty, use plain text.
      if (Trim(md, " `t`n") = "" && Trim(plain, " `t`n") != "") {
        md := PasteMd.CleanPlainText(plain)
      }
    }

    if (asQuoted) {
      md := PasteMd.QuoteMarkdown(md)
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

  /**
   * Runs pandoc to convert HTML content to GitHub-flavored markdown.
   * @param {string} html - HTML content to convert
   * @param {string} pandocExe - Path to pandoc executable
   * @returns {string} Markdown text, or empty string on conversion/read failure
   */
  static HtmlToGfmViaPandoc(html, pandocExe) {
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

  /**
   * Normalizes plain text for markdown-safe paste.
   * Removes CR, trims trailing whitespace, and removes edge blank lines.
   * @param {string} s - Text to normalize
   * @returns {string} Normalized text
   */
  static CleanPlainText(s) {
  s := StrReplace(s, "`r", "")
  lines := StrSplit(s, "`n")
  out := ""
  for i, line in lines {
    line := RTrim(line, " `t")
    out .= (i = 1 ? "" : "`n") . line
  }
  return Trim(out, "`n")
  }

  /**
   * Normalizes markdown lines and simplifies inline HTML.
   * Preserves fenced code blocks. Removes empty headings.
   * @param {string} md - Markdown text to clean
   * @returns {string} Cleaned markdown
   */
  static CleanMarkdown(md) {
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

    outLine := PasteMd.SimplifyMarkdownInlineHtml(outLine)
    out .= (out = "" ? "" : "`n") . outLine
  }

  return Trim(out, "`n")
  }

  /**
   * PCRE regex pattern for matching HTML tags and quoted strings.
   * Includes recursive subroutines for robust HTML parsing.
   * Used as a component in SimplifyMarkdownInlineHtml pattern matching.
   */
  static re_htags := "
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

  /**
   * Converts common inline HTML constructs to markdown equivalents.
   * Strips residual non-escaped tags that reduce readability.
   * Handles <span>, <code>, <strong>, <b>, <em>, <i>, and <a> tags.
   * @param {string} line - Text line containing HTML
   * @returns {string} Line with HTML converted to markdown
   */
  static SimplifyMarkdownInlineHtml(line) {
    line := PasteMd.DecodeBasicHtmlEntities(line)

    ; Chat/app UI exports often wrap inline code in styled spans.
    while RegExMatch(line, "<span\b[^>]*>((?&inside_htag))</span>" PasteMd.re_htags, &m) {
      inner := PasteMd.DecodeBasicHtmlEntities(m[1])
      inner := StrReplace(inner, "`r", "")
      inner := StrReplace(inner, "`n", " ")
      replacement := (inner = "") ? "" : ("``" . inner . "``")
      line := SubStr(line, 1, m.Pos - 1) . replacement . SubStr(line, m.Pos + m.Len)
    }

    while RegExMatch(line, "<code\b[^>]*+>((?&inside_htag))</code>" PasteMd.re_htags, &m) {
      inner := PasteMd.DecodeBasicHtmlEntities(m[1])
      inner := StrReplace(inner, "`r", "")
      inner := StrReplace(inner, "`n", " ")
      replacement := (inner = "") ? "" : ("``" . inner . "``")
      line := SubStr(line, 1, m.Pos - 1) . replacement . SubStr(line, m.Pos + m.Len)
    }

    ; Convert semantic emphasis tags before fallback stripping.
    while RegExMatch(line, "<(strong|b)\b[^>]*+>((?&inside_htag))</\1>" PasteMd.re_htags, &m) {
      replacement := (m[2] = "") ? "" : ("**" . m[2] . "**")
      line := SubStr(line, 1, m.Pos - 1) . replacement . SubStr(line, m.Pos + m.Len)
    }
    while RegExMatch(line, "<(em|i)\b[^>]*+>((?&inside_htag))</\1>" PasteMd.re_htags, &m) {
      replacement := (m[2] = "") ? "" : ("*" . m[2] . "*")
      line := SubStr(line, 1, m.Pos - 1) . replacement . SubStr(line, m.Pos + m.Len)
    }

    ; Convert HTML links to markdown links for readable output.
    while RegExMatch(line, "<a\b[^>]*\bhref\s*=\s*(['`"])(.*?)\1[^>]*>((?&inside_htag))</a>" PasteMd.re_htags, &m) {
      href := PasteMd.DecodeBasicHtmlEntities(m[2])
      text := PasteMd.DecodeBasicHtmlEntities(m[3])

      ; Convert semantic emphasis inside link text before stripping residual tags.
      while RegExMatch(text, "<(strong|b)\b[^>]*>((?&inside_htag))</\1>" PasteMd.re_htags, &inner) {
      replacement := (inner[2] = "") ? "" : ("**" . inner[2] . "**")
      text := SubStr(text, 1, inner.Pos - 1) . replacement . SubStr(text, inner.Pos + inner.Len)
    }
    while RegExMatch(text, "<(em|i)\b[^>]*>((?&inside_htag))</\1>" PasteMd.re_htags, &inner) {
      replacement := (inner[2] = "") ? "" : ("*" . inner[2] . "*")
      text := SubStr(text, 1, inner.Pos - 1) . replacement . SubStr(text, inner.Pos + inner.Len)
    }

    ; Remove any unknown tags that are not escaped
    text := RegExReplace(text, "((?&inside_htag))<[^>]++>" PasteMd.re_htags, "$1")
    if (text = "") {
      text := href
    }
    replacement := "[" . text . "](" . href . ")"
    line := SubStr(line, 1, m.Pos - 1) . replacement . SubStr(line, m.Pos + m.Len)
  }

  ; Remove any unknown tags that are not escaped
  line := RegExReplace(line, "\G((?&inside_htag))(?<!\\)<(?:[^>'`"]++|(?&quoted_string))*+>" PasteMd.re_htags, "$1")
  line := RegExReplace(line, "((?:[^\\]|\\[^<>])++)\\([<>])" PasteMd.re_htags, "$1$2")
  ; Strip common presentational tags that hurt readability in markdown output.
  ; line := RegExReplace(line, "</?(?:div|p|font|mark|u|small|sup|sub)\b[^>]*>", "")
  ; line := RegExReplace(line, "<br\s*/?>", " ")

  return line
  }

  /**
   * Decodes common HTML entities used in clipboard fragments.
   * Handles &nbsp;, &quot;, &apos;, &lt;, &gt;, &amp;, and numeric entity references.
   * @param {string} s - Text containing HTML entities
   * @returns {string} Text with entities decoded
   */
  static DecodeBasicHtmlEntities(s) {
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

  /**
   * Converts markdown to blockquote form by prefixing each line with ">".
   * Blank lines become ">" with no trailing space.
   * @param {string} md - Markdown text to quote
   * @returns {string} Quoted markdown
   */
  static QuoteMarkdown(md) {
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
}

