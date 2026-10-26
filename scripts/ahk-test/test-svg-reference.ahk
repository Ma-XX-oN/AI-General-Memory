#ErrorStdOut
#Requires AutoHotkey v2.0
#Include ../PasteAsMd.ahk
#Include test-helpers.ahk

; Reference-only repair: resolve the missing stylesheet from a saved page.
; This does not add a saved-file dependency to the production paste path.
_logPath := A_ScriptDir "\test-svg-reference.log"
try FileDelete _logPath
passed := 0
failed := 0

savedPage := FileRead(A_Args[1], "UTF-8")
capture := FileRead(A_Args[2], "UTF-8")
originalSvg := FindSvg(capture, "L_F_G_0")
referenceSvg := FindSvg(savedPage, "L_F_G_0")
original := ComObject("MSXML2.DOMDocument.6.0")
reference := ComObject("MSXML2.DOMDocument.6.0")
original.resolveExternals := false
reference.resolveExternals := false
if !original.loadXML(originalSvg) || !reference.loadXML(referenceSvg)
    throw Error("Reference SVG could not be parsed")
Chk("Same diagram viewBox", original.documentElement.getAttribute("viewBox") = reference.documentElement.getAttribute("viewBox"))
originalEdges := original.selectNodes("//*[@data-edge='true']")
referenceEdges := reference.selectNodes("//*[@data-edge='true']")
Chk("Same number of edges", originalEdges.length = referenceEdges.length)
for edge in originalEdges {
    id := edge.getAttribute("data-id")
    match := reference.selectSingleNode("//*[@data-edge='true' and @data-id='" . id . "']")
    Chk("Edge geometry matches: " . id, match && edge.getAttribute("d") = match.getAttribute("d"))
}
styleNode := reference.selectSingleNode("//*[local-name()='style']")
if !styleNode
    throw Error("Saved SVG has no stylesheet")
css := StrReplace(styleNode.text, reference.documentElement.getAttribute("id"), original.documentElement.getAttribute("id"))
RegExMatch(originalSvg, "<svg\b[^>]*>", &opening)
styledSvg := SubStr(originalSvg, 1, opening.Len) . "<style>" . css . "</style>" . SubStr(originalSvg, opening.Len + 1)
styled := ComObject("MSXML2.DOMDocument.6.0")
styled.resolveExternals := false
Chk("Styled SVG is valid XML", styled.loadXML(styledSvg), styled.parseError.reason)
Chk("Arrow fill rule included", InStr(css, ".flowchart-link{") && InStr(css, "fill:none"))
Chk("Node font rules included", InStr(css, ".node text{font-size:14px;font-weight:600"))
Chk("Group backgrounds included", InStr(css, ".cluster rect{fill:rgb(48, 48, 48)"))
if failed
    TestFinish()

PasteMd._svgBlocks := [styledSvg]
image := PasteMd.RestoreSvgBlocks("¤SVG_1¤")
md := FileRead(A_ScriptDir "\test-chatgpt-layout.actual.md", "UTF-8")
if !RegExMatch(md, "!\[Mermaid diagram\]\(data:image/svg\+xml;base64,[A-Za-z0-9+/=]+\)", &oldImage)
    throw Error("Generated Markdown has no SVG image to repair")
md := SubStr(md, 1, oldImage.Pos - 1) . image . SubStr(md, oldImage.Pos + oldImage.Len)
outputMd := A_ScriptDir "\test-chatgpt-styled.actual.md"
try FileDelete outputMd
FileAppend md, outputMd, "UTF-8"
RegExMatch(image, "\((data:image/svg\+xml;base64,[A-Za-z0-9+/=]+)\)", &uri)
outputHtml := A_ScriptDir "\test-chatgpt-styled.actual.html"
try FileDelete outputHtml
FileAppend '<!doctype html><meta charset="utf-8"><style>body{background:#000;color:#ededed;font-family:system-ui;margin:24px}img{max-width:100%;height:auto}</style><h2>RWF — Current dependency state</h2><img src="' . uri[1] . '">', outputHtml, "UTF-8"
Log("Reference-only styled preview generated.")
TestFinish()

/**
 * Finds the complete SVG containing a known edge identifier.
 * @param {string} html
 * @param {string} edgeId
 * @returns {string}
 */
FindSvg(html, edgeId) {
    pos := 1
    while RegExMatch(html, 'is)<svg\b(?=[^>]*\bid="chatgpt-mermaid-)[^>]*>', &m, pos) {
        endPos := HtmlNorm._FindMatchingElementEnd(html, m.Pos, "svg")
        if !endPos
            throw Error("Unclosed reference SVG")
        svg := SubStr(html, m.Pos, endPos - m.Pos + 1)
        if InStr(svg, edgeId)
            return svg
        pos := endPos + 1
    }
    throw Error("Diagram not found: " . edgeId)
}
