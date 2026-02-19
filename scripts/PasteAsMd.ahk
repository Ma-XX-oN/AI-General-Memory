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

PASTE_DELAY_MS := 500

; Set to true to dump pipeline stages to a log file for debugging.
DEBUG_PASTE_MD := true
DEBUG_PASTE_MD_LOG := A_ScriptDir "\PasteAsMd_debug.log"

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

  static CODE_FENCE := "``````"

  ; Temporary storage for thinking blocks extracted during preprocessing.
  static _thinkingBlocks := []

  /**
   * Writes a labelled debug section to the log file.
   * Replaces CR/LF with visible markers so EOL issues are obvious.
   * @param {object} f - FileOpen handle (already open for writing)
   * @param {string} label - Section heading
   * @param {string} s - Raw string to dump
   */
  static _DbgSection(f, label, s) {
    f.Write("=== " . label . " (len=" . StrLen(s) . ") ===`r`n")
    ; Show EOL characters visibly.
    vis := StrReplace(s, "`r`n", "⏎¶`r`n")   ; CRLF → visible + real CRLF
    vis := StrReplace(vis, "`r", "⏎`r`n")      ; lone CR
    vis := StrReplace(vis, "`n", "¶`r`n")       ; lone LF
    f.Write(vis)
    f.Write("`r`n`r`n")
  }

  /**
   * Converts clipboard content to markdown (or quoted markdown) and pastes it.
   * Prefers CF_HTML → pandoc conversion, with plain-text fallback.
   * @param {boolean} asQuoted - If true, prefixes every line with blockquote syntax (>).
   */
  static PasteMarkdown(asQuoted) {
    global PANDOC_EXE, PASTE_DELAY_MS, DEBUG_PASTE_MD, DEBUG_PASTE_MD_LOG

    dbg := DEBUG_PASTE_MD
    if (dbg) {
      dbgF := FileOpen(DEBUG_PASTE_MD_LOG, "w", "UTF-8")
      dbgF.Write("PasteAsMd debug — " . FormatTime(, "yyyy-MM-dd HH:mm:ss") . "`r`n`r`n")
    }

    clipSaved := ClipboardAll()
    plain := StrReplace(A_Clipboard, "`r", "")
    try {
      htmlFrag := ClipboardWaiter.GetHtmlSection()

      if (dbg) {
        PasteMd._DbgSection(dbgF, "1. plain (A_Clipboard minus CR)", plain)
        PasteMd._DbgSection(dbgF, "2. htmlFrag (CF_HTML fragment)", htmlFrag)
      }

      if (htmlFrag = "") {
        md := PasteMd.CleanPlainText(plain)
        if (dbg)
          PasteMd._DbgSection(dbgF, "3. md (CleanPlainText – no HTML path)", md)
      } else {
        htmlPrep := PasteMd.PreprocessHtmlCodeBlocks(htmlFrag)
        if (dbg)
          PasteMd._DbgSection(dbgF, "3. htmlPrep (after PreprocessHtmlCodeBlocks)", htmlPrep)

        ; If no meaningful HTML tags remain after preprocessing (just styled
        ; spans wrapping plain text, or <p> wrappers around plain lines as
        ; in ProseMirror/Codex), skip pandoc — plain text already has
        ; correct whitespace and indentation that pandoc would destroy.
        stripped := RegExReplace(htmlPrep, "i)<br\b[^>]*>", "")
        stripped := RegExReplace(stripped, "i)</?p\b[^>]*>", "")
        if !RegExMatch(stripped, "<[^>]++>") {
          md := PasteMd.CleanPlainText(plain)
          if (dbg)
            PasteMd._DbgSection(dbgF, "3b. md (no HTML tags → plain text path)", md)
        } else {
          mdRaw := PasteMd.HtmlToGfmViaPandoc(htmlPrep, PANDOC_EXE)
          if (dbg)
            PasteMd._DbgSection(dbgF, "4. mdRaw (pandoc output)", mdRaw)

          md := PasteMd.CleanMarkdown(mdRaw)
          md := PasteMd.RestoreThinkingBlocks(md)
          if (dbg)
            PasteMd._DbgSection(dbgF, "5. md (after CleanMarkdown)", md)

          md := StrReplace(md, "`r", "")
        }

        ; Never paste empty.  If conversion failed/empty, use plain text.
        if (Trim(md, " `t`n") = "" && Trim(plain, " `t`n") != "") {
          md := PasteMd.CleanPlainText(plain)
          if (dbg)
            PasteMd._DbgSection(dbgF, "5b. md (empty→plain fallback)", md)
        }
      }

      if (asQuoted) {
        md := PasteMd.QuoteMarkdown(md)
      }

      ; Remove CR unconditionally (LF-only).
      md := StrReplace(md, "`r", "")

      if (dbg) {
        PasteMd._DbgSection(dbgF, "6. FINAL md (pasted)", md)
        dbgF.Close()
      }

      A_Clipboard := md
      Send "^v"
      Sleep PASTE_DELAY_MS
    } catch as e {
      if (dbg) {
        try {
          dbgF.Write("!!! EXCEPTION: " . e.File . ":" . e.Line . " — " . e.Message . "`r`n")
          dbgF.Close()
        }
      }
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

    ; Strip <span> tags (presentational wrappers that cause backtick accumulation).
    md := RegExReplace(md, "i)</?span\b[^>]*>", "")

    ; Convert <br> tags to newlines so line breaks are preserved.
    md := RegExReplace(md, "i)<br\b[^>]*>", "`n")

    ; Convert block-level <code> elements (multi-line) to fenced code blocks.
    pos := 1
    while RegExMatch(md, "s)<code\b[^>]*>(.*?)</code>", &m, pos) {
      if InStr(m[1], "`n") {
        inner := RegExReplace(m[1], "<[^>]++>", "")
        inner := PasteMd.DecodeBasicHtmlEntities(inner)
        inner := Trim(inner, " `t`n")
        replacement := PasteMd.CODE_FENCE . "`n" . inner . "`n" . PasteMd.CODE_FENCE
        md := SubStr(md, 1, m.Pos - 1) . replacement . SubStr(md, m.Pos + m.Len)
        pos := m.Pos + StrLen(replacement)
      } else {
        pos := m.Pos + m.Len
      }
    }

    lines := StrSplit(md, "`n")

    out := ""
    inFence := false

    for i, line in lines {
      t := LTrim(line, " `t")

      ; Fence detection without regex (avoids backtick-escape problems).
      if (SubStr(t, 1, 3) = PasteMd.CODE_FENCE) {
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

    ; Collapse runs of 3+ newlines to 2 (at most one blank line).
    out := RegExReplace(out, "\n{3,}", "`n`n")

    return Trim(out, "`n")
  }

  /**
   * PCRE regex subroutine library for HTML parsing and backtick code spans.
   * Includes recursive subroutines for robust HTML tag matching,
   * plus a generic backtick code span pattern for any delimiter length.
   */
  static RE_HTML_LIB := "
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
  (?<codespan>(?<bt_open>``++)(?:[^``]++|(?!\k<bt_open>).)++\k<bt_open>)
  )"

  /**
   * Converts common inline HTML constructs to markdown equivalents.
   * Strips residual non-escaped tags that reduce readability.
   * Handles <code>, <strong>, <b>, <em>, <i>, and <a> tags.
   * @param {string} line - Text line containing HTML
   * @returns {string} Line with HTML converted to markdown
   */
  static SimplifyMarkdownInlineHtml(line) {
    line := PasteMd.DecodeBasicHtmlEntities(line)

    while RegExMatch(line, "<code\b[^>]*+>((?&inside_htag))</code>" PasteMd.RE_HTML_LIB, &m) {
      inner := PasteMd.DecodeBasicHtmlEntities(m[1])
      inner := StrReplace(inner, "`r", "")
      inner := StrReplace(inner, "`n", " ")
      replacement := (inner = "") ? "" : ("``" . inner . "``")
      line := SubStr(line, 1, m.Pos - 1) . replacement . SubStr(line, m.Pos + m.Len)
    }

    ; Convert semantic emphasis tags before fallback stripping.
    while RegExMatch(line, "<(strong|b)\b[^>]*+>((?&inside_htag))</\1>" PasteMd.RE_HTML_LIB, &m) {
      replacement := (m[2] = "") ? "" : ("**" . m[2] . "**")
      line := SubStr(line, 1, m.Pos - 1) . replacement . SubStr(line, m.Pos + m.Len)
    }
    while RegExMatch(line, "<(em|i)\b[^>]*+>((?&inside_htag))</\1>" PasteMd.RE_HTML_LIB, &m) {
      replacement := (m[2] = "") ? "" : ("*" . m[2] . "*")
      line := SubStr(line, 1, m.Pos - 1) . replacement . SubStr(line, m.Pos + m.Len)
    }

    ; Convert HTML links to markdown links for readable output.
    while RegExMatch(line, "<a\b[^>]*\bhref\s*=\s*(['`"])(.*?)\1[^>]*>((?&inside_htag))</a>" PasteMd.RE_HTML_LIB, &m) {
      href := PasteMd.DecodeBasicHtmlEntities(m[2])
      text := PasteMd.DecodeBasicHtmlEntities(m[3])

      ; Convert semantic emphasis inside link text before stripping residual tags.
      while RegExMatch(text, "<(strong|b)\b[^>]*>((?&inside_htag))</\1>" PasteMd.RE_HTML_LIB, &inner) {
        replacement := (inner[2] = "") ? "" : ("**" . inner[2] . "**")
        text := SubStr(text, 1, inner.Pos - 1) . replacement . SubStr(text, inner.Pos + inner.Len)
      }
      while RegExMatch(text, "<(em|i)\b[^>]*>((?&inside_htag))</\1>" PasteMd.RE_HTML_LIB, &inner) {
        replacement := (inner[2] = "") ? "" : ("*" . inner[2] . "*")
        text := SubStr(text, 1, inner.Pos - 1) . replacement . SubStr(text, inner.Pos + inner.Len)
      }

      ; Remove any unknown tags that are not escaped
      text := RegExReplace(text, "((?&inside_htag))<[^>]++>" PasteMd.RE_HTML_LIB, "$1")
      if (text = "") {
        text := href
      }
      replacement := "[" . text . "](" . href . ")"
      line := SubStr(line, 1, m.Pos - 1) . replacement . SubStr(line, m.Pos + m.Len)
    }

    ; Protect backtick code spans from tag stripping.
    _codeSpans := []
    pos := 1
    while RegExMatch(line, "(?&codespan)" PasteMd.RE_HTML_LIB, &m, pos) {
      _codeSpans.Push(m[0])
      placeholder := "¤CSPAN_" . _codeSpans.Length . "¤"
      line := SubStr(line, 1, m.Pos - 1) . placeholder . SubStr(line, m.Pos + m.Len)
      pos := m.Pos + StrLen(placeholder)
    }

    ; Remove any unknown tags that are not escaped
    line := RegExReplace(line, "\G((?&inside_htag))(?<!\\)<(?:[^>'`"]++|(?&quoted_string))*+>" PasteMd.RE_HTML_LIB, "$1")
    line := RegExReplace(line, "((?:[^\\]|\\[^<>])++)\\([<>])" PasteMd.RE_HTML_LIB, "$1$2")

    ; Restore backtick code spans.
    for i, span in _codeSpans {
      line := StrReplace(line, "¤CSPAN_" . i . "¤", span)
    }

    return line
  }

  /**
   * Decodes common HTML entities used in clipboard fragments.
   * Handles &nbsp;, &quot;, &apos;, &lt;, &gt;, &amp;, and numeric entity references.
   * @param {string} s - Text containing HTML entities
   * @returns {string} Text with entities decoded
   */
  static DecodeBasicHtmlEntities(s) {
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
   * Preprocesses HTML before pandoc conversion.
   * Strips UI artifacts (buttons, thinking blocks), converts code-like spans to <code>,
   * strips presentational spans, normalizes line breaks inside <code>,
   * and wraps multi-line code in <pre>.
   * @param {string} html - HTML fragment from clipboard
   * @returns {string} Preprocessed HTML
   */
  static PreprocessHtmlCodeBlocks(html) {
    ; Strip UI artifacts that don't belong in markdown output.
    html := RegExReplace(html, "is)<button\b[^>]*>.*?</button>", "")

    ; Extract Claude Code thinking blocks as placeholders so pandoc doesn't
    ; mangle them.  They get restored as raw HTML after markdown cleanup.
    this._thinkingBlocks := []
    pos := 1
    while RegExMatch(html, "is)<details\b[^>]*\bclass=`"[^`"]*\bthinking[^`"]*`"[^>]*>(.*?)</details>", &m, pos) {
      inner := m[1]
      ; Remove <summary> element.
      inner := RegExReplace(inner, "is)<summary\b[^>]*>.*?</summary>", "")
      ; Strip remaining HTML tags.
      inner := RegExReplace(inner, "<[^>]++>", "")
      inner := this.DecodeBasicHtmlEntities(inner)
      inner := Trim(inner, " `t`n`r")
      this._thinkingBlocks.Push(inner)
      placeholder := "¤THINKING_" . this._thinkingBlocks.Length . "¤"
      html := SubStr(html, 1, m.Pos - 1) . placeholder . SubStr(html, m.Pos + m.Len)
      pos := m.Pos + StrLen(placeholder)
    }

    ; Convert code-like <span> elements to <code> before stripping generic spans.
    ; Matches spans with inline-markdown/font-mono class (e.g., Codex/Claude Code).
    html := RegExReplace(html, "is)<span\b[^>]*\bclass=`"[^`"]*\b(?:inline-markdown|font-mono)\b[^`"]*`"[^>]*>(.*?)</span>", "<code>$1</code>")

    ; Strip remaining <span> tags globally (presentational wrappers).
    html := RegExReplace(html, "i)</?span\b[^>]*>", "")

    ; Process <code> elements: normalize line breaks and wrap in <pre> if multi-line.
    pos := 1
    while RegExMatch(html, "is)<code\b([^>]*)>(.*?)</code>", &m, pos) {
      content := m[2]
      attrs := m[1]

      ; Convert <br> tags to newlines.
      content := RegExReplace(content, "i)<br\b[^>]*>", "`n")

      ; Convert </div><div> sequences to newlines (VS Code line rendering).
      content := RegExReplace(content, "i)</div>\s*<div\b[^>]*>", "`n")

      ; Strip remaining HTML tags inside the code block.
      content := RegExReplace(content, "<[^>]++>", "")

      ; Clean up: remove CR, collapse consecutive blank lines.
      content := StrReplace(content, "`r", "")
      content := RegExReplace(content, "\n{2,}", "`n")

      if InStr(content, "`n") {
        ; Decode entities for fenced block (markdown output, not HTML).
        content := PasteMd.DecodeBasicHtmlEntities(content)
        ; Multi-line: check if already inside <pre>.
        beforeSnippet := SubStr(html, Max(1, m.Pos - 100), Min(100, m.Pos - 1))

        ; Only preserve class="language-xxx"; drop CSS classes like "whitespace-pre!".
        langAttr := ""
        if RegExMatch(attrs, "i)language-(\w+)", &langM) {
          langAttr := ' class="language-' . langM[1] . '"'
        }

        if RegExMatch(beforeSnippet, "i)<pre\b[^>]*>\s*$") {
          replacement := "<code" . langAttr . ">" . content . "</code>"
        } else {
          replacement := "<pre><code" . langAttr . ">" . content . "</code></pre>"
        }
      } else {
        ; Single-line: leave as inline <code> for pandoc.
        replacement := "<code" . attrs . ">" . content . "</code>"
      }

      html := SubStr(html, 1, m.Pos - 1) . replacement . SubStr(html, m.Pos + m.Len)
      pos := m.Pos + StrLen(replacement)
    }

    return html
  }

  /**
   * Replaces ¤THINKING_N¤ placeholders with clean <details> HTML blocks.
   * @param {string} md - Markdown text containing placeholders
   * @returns {string} Markdown with thinking blocks restored as raw HTML
   */
  static RestoreThinkingBlocks(md) {
    for i, content in this._thinkingBlocks {
      placeholder := "¤THINKING_" . i . "¤"
      if (content = "") {
        details := "<details>`n<summary>Thinking</summary>`n</details>"
      } else {
        details := "<details>`n<summary>Thinking</summary>`n`n" . content . "`n</details>"
      }
      md := StrReplace(md, placeholder, details)
    }
    return md
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

