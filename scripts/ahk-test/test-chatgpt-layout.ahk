#ErrorStdOut
#Requires AutoHotkey v2.0
#Include ../PasteAsMd.ahk
#Include test-helpers.ahk

_logPath := A_ScriptDir "\test-chatgpt-layout.log"
try FileDelete _logPath
passed := 0
failed := 0

html := '<div data-markdown-text-style="assistant-message" style="color:red">'
    . '<div class="layout" title="a > b"><h2>Controller actions completed</h2>'
    . '<p>I have now:</p><ul><li><p>Accepted <a href="https://example.com/699">the handoff</a>.</p></li>'
    . '<li>Authorized <code>40a1ff6c</code>.</li></ul>'
    . '<p>The critical path is <strong>independent certification</strong>.</p></div>'
    . '<div class="turn-action-controls"><div>Copy response</div></div>'
    . '<div data-markdown-copy="exclude"><div>Widget controls</div></div></div>'
    . '<aside role="alert"><div>Maximum conversation length</div><button>Start new chat</button></aside>'
norm := HtmlNorm.Normalize(html, "chatgpt", true, false)
md := PasteMd.CleanMarkdown(PasteMd.HtmlToGfmViaPandoc(norm, PasteMd.PANDOC_EXE))
Chk("layout and CSS removed", !RegExMatch(md, 'i)</?div\b|style=|class='))
Chk("heading preserved", InStr(md, "## Controller actions completed"))
Chk("list and link preserved", InStr(md, "- Accepted [the handoff](https://example.com/699)."))
Chk("inline code preserved", InStr(md, Chr(96) "40a1ff6c" Chr(96)))
Chk("bold preserved", InStr(md, "**independent certification**"))
Chk("poster marker preserved", InStr(md, "¤POSTER_AI¤"))
Chk("UI subtrees removed", !RegExMatch(md, "Copy response|Widget controls|Maximum conversation length|Start new chat"))

fence := Chr(96) . Chr(96) . Chr(96)
mermaidSource := fence . "mermaid`nflowchart LR`n  A --> B`n" . fence
widget := '<div data-markdown-copy="code-block" data-markdown-copy-text="' . mermaidSource
    . '"><div>Rendered diagram</div></div><p>Following paragraph.</p>'
widgetFragment := '<div data-markdown-text-style="assistant-message">' . widget . '</div>'
headerFormat := "StartFragment:{:010}`r`nEndFragment:{:010}`r`n"
fragmentStart := StrLen(Format(headerFormat, 0, 0))
widgetCapture := Format(headerFormat, fragmentStart, fragmentStart + ClipboardWaiter.Utf8ByteLen(widgetFragment)) . widgetFragment
mermaidMd := PasteMd._ConvertFromCaptured("", widgetCapture, false, false, false, false)["finalMd"]
Chk("Mermaid has exactly one fence", Trim(mermaidMd, "`n") = mermaidSource . "`n`nFollowing paragraph.", mermaidMd)
literalExample := '<pre><code class="language-markdown">' . mermaidSource . '</code></pre>'
literalMd := PasteMd.HtmlToGfmViaPandoc(HtmlNorm.Normalize(literalExample, "chatgpt", false, false), PasteMd.PANDOC_EXE)
Chk("Literal nested fence example remains protected", InStr(literalMd, fence . Chr(96)) && InStr(literalMd, mermaidSource))

flattenedFragment := '<div><p>Before.</p><pre dir="ltr"><code>' . mermaidSource . '</code></pre>'
    . '<div><div>#chatgpt-mermaid-test{fill:red;}Diagram labels</div></div><p>After.</p>'
    . '<aside><div>You' . Chr(39) . 've reached the maximum length for this conversation, but you can keep talking by starting a new chat.</div></aside></div>'
flattenedCapture := Format(headerFormat, fragmentStart, fragmentStart + ClipboardWaiter.Utf8ByteLen(flattenedFragment)) . flattenedFragment
Chk("Flattened SVG signature identifies ChatGPT", DetectSource(flattenedCapture) = "chatgpt")
flattenedMd := PasteMd._ConvertFromCaptured("", flattenedCapture, true, true, false, false)["finalMd"]
expectedFlattened := "## ChatGPT`n`n> Before.`n>`n> " . fence . "mermaid`n> flowchart LR`n>   A --> B`n> " . fence
    . "`n>`n> *Diagram text (image unavailable):* Diagram labels`n>`n> After."
Chk("Flattened capture: complete output matches", RTrim(flattenedMd, "`n") = expectedFlattened, flattenedMd)

sampleSvg := '<svg id="chatgpt-mermaid-test" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 30"><svg><rect width="100" height="30" fill="red"/></svg><text x="5" y="20">A → B</text></svg>'
sampleFragment := '<div data-markdown-text-style="assistant-message"><p>Diagram:</p>' . sampleSvg . '<p>After.</p></div>'
sampleCapture := Format(headerFormat, fragmentStart, fragmentStart + ClipboardWaiter.Utf8ByteLen(sampleFragment)) . sampleFragment
for showImages in [false, true] {
    sampleMd := PasteMd._ConvertFromCaptured("", sampleCapture, true, true, showImages, false)["finalMd"]
    hasSvg := RegExMatch(sampleMd, "!\[Mermaid diagram\]\(data:image/svg\+xml;base64,([A-Za-z0-9+/=]+)\)", &sampleImage)
    Chk("SVG survives image toggle " . showImages, hasSvg)
    if hasSvg {
        roundtripSvg := DecodeSvgImage(sampleImage[1])
        withoutFallback := StrReplace(roundtripSvg, "<style>" . HtmlNorm.CHATGPT_SVG_FALLBACK_CSS . "</style>", "")
        Chk("Nested SVG geometry untouched " . showImages, withoutFallback == sampleSvg)
        Chk("Missing SVG stylesheet supplied " . showImages, withoutFallback != roundtripSvg)
    }
    Chk("SVG surrounding content preserved " . showImages, InStr(sampleMd, "> Diagram:") && InStr(sampleMd, "> After."))
}

suppliedSvg := StrReplace(sampleSvg, '<svg><rect', '<style>.node{fill:lime}</style><svg><rect')
HtmlNorm._svgBlocks := []
HtmlNorm._ExtractChatGptSvg(suppliedSvg)
Chk("Existing SVG stylesheet preserved exactly", HtmlNorm._svgBlocks[1] == suppliedSvg)
inlineSvg := StrReplace(sampleSvg, 'fill="red"', 'style="fill:orange !important;stroke:purple"')
HtmlNorm._svgBlocks := []
HtmlNorm._ExtractChatGptSvg(inlineSvg)
Chk("Explicit inline SVG styling preserved", StrReplace(HtmlNorm._svgBlocks[1], "<style>" . HtmlNorm.CHATGPT_SVG_FALLBACK_CSS . "</style>", "") == inlineSvg)
unrelatedSvg := StrReplace(sampleSvg, "chatgpt-mermaid-test", "unrelated-logo")
HtmlNorm._svgBlocks := []
Chk("Unrelated SVG not given ChatGPT defaults", HtmlNorm._ExtractChatGptSvg(unrelatedSvg) == unrelatedSvg && HtmlNorm._svgBlocks.Length = 0)

if A_Args.Length {
    capture := FileRead(A_Args[1], "UTF-8")
    plain := CapturedSection(capture, PasteMd.LOG_SECTION_PLAIN)
    cfHtml := CapturedSection(capture, PasteMd.LOG_SECTION_CFHTML)
    result := PasteMd._ConvertFromCaptured(plain, cfHtml, true, true, false, false)
    finalMd := result["finalMd"]
    output := A_ScriptDir "\test-chatgpt-layout.actual.md"
    try FileDelete output
    FileAppend finalMd, output, "UTF-8"
    Chk("capture: attribution preserved", InStr(finalMd, "## ChatGPT"))
    Chk("capture: quoted text preserved", InStr(finalMd, "> Planned next steps"))
    Chk("capture: layout markup removed", !RegExMatch(finalMd, 'i)</?div\b|style=|class=|markdown-copy='))
    Chk("capture: banner removed", !InStr(finalMd, "maximum length for this conversation"))
    Chk("capture: heading preserved", InStr(finalMd, "## Controller actions completed"))
    Chk("capture: final paragraph preserved", InStr(finalMd, "no PR was merged."))
    Chk("capture: Mermaid source restored", InStr(finalMd, "> " . fence . "mermaid`n> flowchart LR"))
    Chk("capture: no outer quadruple fence", !InStr(finalMd, fence . Chr(96)))
    Chk("capture: no rendered diagram CSS", !InStr(finalMd, "@keyframes") && !InStr(finalMd, "stroke-dasharray"))
    Chk("capture: second diagram image present", RegExMatch(finalMd, "!\[Mermaid diagram\]\(data:image/svg\+xml;base64,"))
    if InStr(cfHtml, '<svg id="chatgpt-mermaid-') {
        hasImage := RegExMatch(finalMd, "!\[Mermaid diagram\]\(data:image/svg\+xml;base64,([A-Za-z0-9+/=]+)\)", &embedded)
        Chk("capture: second diagram embedded as SVG", hasImage)
        if hasImage {
            decodedSvg := DecodeSvgImage(embedded[1])
            Chk("capture: normalized SVG encoded losslessly", decodedSvg == PasteMd._svgBlocks[2])
            xml := ComObject("MSXML2.DOMDocument.6.0")
            xml.async := false
            xml.resolveExternals := false
            Chk("capture: SVG is valid standalone XML", xml.loadXML(decodedSvg), xml.parseError.reason)
            Log("SVG root id: " . xml.documentElement.getAttribute("id"))
            styleNode := xml.selectSingleNode("//*[local-name()='style']")
            Log("SVG stylesheet: " . (styleNode ? SubStr(styleNode.text, 1, 350) : "MISSING"))
            Chk("capture: flowchart stylesheet preserved", !!styleNode)
            rawPat := 'is)<svg\b[^>]*\bid="' . xml.documentElement.getAttribute("id") . '"[^>]*>.*?</svg>'
            if !RegExMatch(cfHtml, rawPat, &rawSvg)
                throw Error("Original SVG missing from raw capture")
            Chk("capture: only fallback style changes original SVG", StrReplace(decodedSvg, "<style>" . HtmlNorm.CHATGPT_SVG_FALLBACK_CSS . "</style>", "") == rawSvg[0])
            Chk("capture: arrow fill and label font defaults included", InStr(styleNode.text, "fill:none") && InStr(styleNode.text, ".node text{font-size:14px;font-weight:600"))
            Chk("capture: second diagram labels preserved", InStr(decodedSvg, "Executor") && InStr(decodedSvg, "certification"))
            Chk("capture: second diagram edges preserved", InStr(decodedSvg, "L_F_G_0") && InStr(decodedSvg, "L_A_D_0"))
            preview := A_ScriptDir "\test-chatgpt-svg.actual.html"
            try FileDelete preview
            FileAppend '<!doctype html><meta charset="utf-8"><style>body{background:#000;color:#ededed;margin:24px}img{max-width:100%;height:auto}</style><h2>RWF — Current dependency state</h2><img src="data:image/svg+xml;base64,' . embedded[1] . '">', preview, "UTF-8"
        }
    } else {
        Chk("capture: flattened labels retained", InStr(finalMd, "#109 Executor") && InStr(finalMd, "#699 Final convergence"))
        Chk("capture: unavailable image identified", InStr(finalMd, "Diagram text (image unavailable)"))
    }
    Log("Capture output length: " StrLen(finalMd))
    if (A_Args.Length > 1 && A_Args[2] = "/clipboardRoundtrip")
        CheckClipboardRoundtrip(plain, cfHtml)
}
TestFinish()

/**
 * Reads a length-delimited section from a captured PasteAsMd debug log.
 * @param {string} capture
 * @param {string} label
 * @returns {string}
 */
CapturedSection(capture, label) {
    if !RegExMatch(capture, "m)^=== \Q" . label . "\E \(len=(\d+)\) ===\r\n", &m)
        throw Error("Missing captured section: " label)
    return SubStr(capture, m.Pos + m.Len, Integer(m[1]))
}

/**
 * Decodes an embedded SVG image for exact comparison with the captured SVG.
 * @param {string} encoded
 * @returns {string}
 */
DecodeSvgImage(encoded) {
    size := 0
    if !DllCall("Crypt32\CryptStringToBinaryW", "Str", encoded, "UInt", 0, "UInt", 1, "Ptr", 0, "UInt*", &size, "Ptr", 0, "Ptr", 0)
        throw OSError(A_LastError)
    bytes := Buffer(size)
    if !DllCall("Crypt32\CryptStringToBinaryW", "Str", encoded, "UInt", 0, "UInt", 1, "Ptr", bytes.Ptr, "UInt*", &size, "Ptr", 0, "Ptr", 0)
        throw OSError(A_LastError)
    return StrGet(bytes, size, "UTF-8")
}

/**
 * Exercises the production clipboard snapshot/restore sequence with a captured
 * payload, restoring the user's clipboard in all cases. No keys are sent.
 * @param {string} plain
 * @param {string} cfHtml
 */
CheckClipboardRoundtrip(plain, cfHtml) {
    userClipboard := ClipboardAll()
    try {
        A_Clipboard := plain
        if !DllCall("User32\OpenClipboard", "Ptr", A_ScriptHwnd)
            throw OSError(A_LastError)
        handle := 0
        try {
            size := StrPut(cfHtml, "UTF-8")
            handle := DllCall("Kernel32\GlobalAlloc", "UInt", 2, "UPtr", size, "Ptr")
            if !handle
                throw OSError(A_LastError)
            ptr := DllCall("Kernel32\GlobalLock", "Ptr", handle, "Ptr")
            if !ptr
                throw OSError(A_LastError)
            StrPut(cfHtml, ptr, size, "UTF-8")
            DllCall("Kernel32\GlobalUnlock", "Ptr", handle)
            if !DllCall("User32\SetClipboardData", "UInt", ClipboardWaiter.HtmlFormatId(), "Ptr", handle, "Ptr")
                throw OSError(A_LastError)
            handle := 0
        } finally {
            if handle
                DllCall("Kernel32\GlobalFree", "Ptr", handle)
            DllCall("User32\CloseClipboard")
        }
        Chk("clipboard: original HTML installed exactly", ClipboardWaiter.GetHtml() == cfHtml)
        saved := ClipboardAll()
        Chk("clipboard: snapshot leaves HTML unchanged", ClipboardWaiter.GetHtml() == cfHtml)
        A_Clipboard := "Temporary paste payload"
        A_Clipboard := saved
        Chk("clipboard: restore preserves original HTML exactly", ClipboardWaiter.GetHtml() == cfHtml)
        Chk("clipboard: restore preserves original plain text", A_Clipboard == plain)
    } finally {
        A_Clipboard := userClipboard
    }
}
