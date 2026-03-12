#ErrorStdOut
#Requires AutoHotkey v2.0
#Include test-helpers.ahk

_logPath := A_ScriptDir "\test-cliphelper.log"
try FileDelete _logPath

passed := 0
failed := 0

; ── 1: UTF-8 fragment extraction ───────────────────────────────────────────────
Log("── 1: UTF-8 fragment extraction ──────────────────────")

cfUnicode := BuildCfHtml("<p>Préface</p>", "<p>café</p>")
fragUnicode := ClipboardWaiter.SelectHtmlSection(cfUnicode, ClipboardWaiter.HTML_SECTION_FRAGMENT)
htmlUnicode := ClipboardWaiter.SelectHtmlSection(cfUnicode, ClipboardWaiter.HTML_SECTION_HTML)
beforeUnicode := ClipboardWaiter.GetHtmlContextBeforeFragment(cfUnicode, fragUnicode)

Chk("fragment keeps accented text",
    fragUnicode = "<p>café</p>",
    fragUnicode)
Chk("html section keeps accented prefix",
    InStr(htmlUnicode, "<p>Préface</p><!--StartFragment--><p>café</p><!--EndFragment-->") != 0,
    htmlUnicode)
Chk("pre-fragment context extracted",
    beforeUnicode = "<html><body><p>Préface</p><!--StartFragment-->",
    beforeUnicode)

; ── 2: UTF-8 raw context slicing ──────────────────────────────────────────────
Log("── 2: UTF-8 raw context slicing ─────────────────────")

cfList := BuildCfHtml("<ol><li>Préface</li>", "<li>café</li>", "</ol>")
fragList := ClipboardWaiter.SelectHtmlSection(cfList, ClipboardWaiter.HTML_SECTION_FRAGMENT)
beforeList := ClipboardWaiter.GetHtmlContextBeforeFragment(cfList, fragList)

Chk("ordered-list fragment keeps accented text",
    fragList = "<li>café</li>",
    fragList)
Chk("pre-fragment context keeps accented prefix",
    InStr(beforeList, "<li>Préface</li><!--StartFragment-->") != 0,
    beforeList)
Chk("list start inferred across accented prefix",
    ClipboardWaiter.GetListStartFromHtmlContext(cfList, fragList) = 2)

; ── 3: Poster extraction from pre-fragment context ───────────────────────────
Log("── 3: Poster extraction ────────────────────────────")

cfPosterAi := BuildCfHtml('<div data-testid="assistant-message">', "<p>Answer</p>", "</div>")
cfPosterUser := BuildCfHtml('<div class="userMessageContainer_test">', "<p>Question</p>", "</div>")

Chk("assistant poster inferred from context",
    ClipboardWaiter.ExtractPosterFromContext(cfPosterAi) = "AI")
Chk("user poster inferred from context",
    ClipboardWaiter.ExtractPosterFromContext(cfPosterUser) = "User")

; ── summary ───────────────────────────────────────────────────────────────────
TestFinish()

BuildCfHtml(preFragmentHtml, fragmentHtml, postFragmentHtml := "") {
  startMarker := "<!--StartFragment-->"
  endMarker := "<!--EndFragment-->"
  html := "<html><body>" preFragmentHtml startMarker fragmentHtml endMarker postFragmentHtml "</body></html>"

  header := "Version:0.9`r`n"
    . "StartHTML:0000000000`r`n"
    . "EndHTML:0000000000`r`n"
    . "StartFragment:0000000000`r`n"
    . "EndFragment:0000000000`r`n"

  startHtml := Utf8ByteLen(header)
  endHtml := startHtml + Utf8ByteLen(html)
  prefix := "<html><body>" preFragmentHtml startMarker
  startFragment := startHtml + Utf8ByteLen(prefix)
  endFragment := startFragment + Utf8ByteLen(fragmentHtml)

  cfHtml := header html
  cfHtml := ReplaceCfHtmlOffset(cfHtml, "StartHTML:", startHtml)
  cfHtml := ReplaceCfHtmlOffset(cfHtml, "EndHTML:", endHtml)
  cfHtml := ReplaceCfHtmlOffset(cfHtml, "StartFragment:", startFragment)
  cfHtml := ReplaceCfHtmlOffset(cfHtml, "EndFragment:", endFragment)
  return cfHtml
}

ReplaceCfHtmlOffset(cfHtml, key, value) {
  pos := InStr(cfHtml, key)
  if (!pos)
    return cfHtml

  numStart := pos + StrLen(key)
  eol := InStr(cfHtml, "`n", , numStart)
  if (!eol)
    return cfHtml

  hasCr := (SubStr(cfHtml, eol - 1, 1) = "`r")
  digits := eol - numStart - (hasCr ? 1 : 0)
  return SubStr(cfHtml, 1, numStart - 1)
    . Format("{:0" digits "}", value)
    . SubStr(cfHtml, hasCr ? eol - 1 : eol)
}

Utf8ByteLen(s) {
  return ClipboardWaiter.Utf8ByteLen(s)
}

#Include ../PasteAsMd.ahk
