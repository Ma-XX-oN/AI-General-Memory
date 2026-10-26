;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; HtmlNorm — Source detection and HTML normalization for PasteAsMd
;
; Replaces PreprocessHtmlCodeBlocks in PasteAsMd.ahk with a more accurate
; normalizer that handles Codex, Claude Code, Claude Web, and ChatGPT web.
;
; No dependencies — does not require HtmlParser.ahk or MSHTML as it's oo slow.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

/**
 * Detects the source application from a full CF_HTML clipboard payload.
 *
 * Uses the `extensionId` field and `SourceURL` in the CF_HTML header to
 * distinguish the four supported sources:
 *
 * - "claudecode"  extensionId contains "anthropic" or "claude", fragment has
 *                 content_xGDvVg class (Claude Code VS Code extension)
 * - "claudeweb"   extensionId contains "anthropic" or "claude", no
 *                 content_xGDvVg class (Claude.ai web)
 * - "codex"       extensionId contains "openai.chatgpt" (ChatGPT VS Code ext)
 * - "chatgpt"     no extensionId; HTML fragment contains ChatGPT turn/search
 *                 attributes such as `data-turn-id=` or
 *                 `data-chatgpt-search-unit-key=`
 * - "unknown"     none of the above
 *
 * @param {string} cfHtml - Full CF_HTML clipboard payload (not just the fragment)
 * @returns {string} Source identifier string
 */
DetectSource(cfHtml) {
    if RegExMatch(cfHtml, "i)extensionId=([^&`r`n]++)", &m) {
        extId := StrLower(m[1])
        if InStr(extId, "openai.chatgpt")
            return "codex"
        if InStr(extId, "anthropic") || InStr(extId, "claude")
            return "claudecode"   ; real Claude Web (browser) never has extensionId
    }
    ; Claude Web (browser): no extensionId in header; detect from HTML content.
    if InStr(cfHtml, "font-claude-response") || InStr(cfHtml, "data-is-streaming") || InStr(cfHtml, "code-block__code")
        return "claudeweb"
    ; ChatGPT web: no extensionId.  Full-turn copies may have data-turn-id on
    ; <section>/<article>, or newer search-unit role attributes on wrapper divs.
    ; Sub-selection copies omit the container but keep CodeMirror overflow-visible! <pre>.
    if InStr(cfHtml, "data-turn-id=")
        || InStr(cfHtml, "data-chatgpt-search-unit-key=")
        || InStr(cfHtml, "data-content-search-unit-key=")
        || InStr(cfHtml, "data-user-message-bubble=")
        || InStr(cfHtml, "data-markdown-text-style=`"assistant-message`"")
        || InStr(cfHtml, "overflow-visible!")
        || RegExMatch(cfHtml, "i)<div\b[^>]*>\s*#chatgpt-mermaid-[\w-]+\{")
        return "chatgpt"
    return "unknown"
}

/**
 * Normalizes an HTML fragment from clipboard for downstream pandoc conversion.
 *
 * Populated arrays after `Normalize()` returns:
 *   - `HtmlNorm._thinkingBlocks` — inner texts of thinking blocks (¤THINKING_N¤)
 *   - `HtmlNorm._userMsgBlocks`  — user message raw text (¤USERMSG_N¤)
 *   - `HtmlNorm._svgBlocks`      — original diagram SVGs (¤SVG_N¤)
 *
 * These must be copied into `PasteMd._thinkingBlocks` / `_userMsgBlocks` by
 * the caller before invoking `RestoreThinkingBlocks` / `RestoreUserMsgBlocks`.
 * Copy `_svgBlocks` as well before invoking `RestoreSvgBlocks`.
 */
class HtmlNorm {
    /**
     * Version marker emitted by PasteAsMd debug logs for runtime verification.
     * @type {string}
     */
    static VERSION := "HtmlNorm/2026-10-22.3"

    /**
     * Fallback for ChatGPT Mermaid SVGs whose clipboard serialization omits CSS.
     *
     * The shared dark flowchart constants are taken from the saved ChatGPT page
     * used to verify the SVG rendering. We deliberately assume these defaults
     * are stable enough to embed: shared/scoped application CSS need not make
     * each exported image depend on the application or a saved HTML file.
     * This is an assumption, not a promise about OpenAI's renderer. If a later
     * theme/renderer changes these defaults, update this single definition from
     * a complete reference and check the rendered output again.
     *
     * Embed only when the recognized ChatGPT SVG has no stylesheet. Keep all
     * supplied inline styling, geometry, and existing stylesheets. Each SVG is
     * a separate image, so these generic selectors cannot affect its neighbors.
     * Explicit diagram classes and themes can differ; the status-class colors
     * below are fallback assumptions as well, not inferred diagram semantics.
     * Missing SVG geometry cannot be recovered by supplying CSS.
     * @type {string}
     */
    static CHATGPT_SVG_FALLBACK_CSS := '
    (
    svg,.label{font-family:-apple-system-body,ui-sans-serif,-apple-system,system-ui,"Segoe UI",Helvetica,"Apple Color Emoji",Arial,sans-serif,"Segoe UI Emoji","Segoe UI Symbol";font-size:16px;fill:rgb(237,237,237);color:rgb(237,237,237)}
    .edge-thickness-normal{stroke-width:1px}.edge-thickness-thick{stroke-width:3.5px}
    .edge-pattern-solid{stroke-dasharray:0}.edge-thickness-invisible{stroke-width:0;fill:none}
    .edge-pattern-dashed{stroke-dasharray:3}.edge-pattern-dotted{stroke-dasharray:2}
    .marker{fill:rgb(175,175,175);stroke:rgb(175,175,175)}.marker.cross{stroke:rgb(175,175,175)}
    p{margin:0}.cluster-label text,.label text,span,.cluster text{fill:rgb(237,237,237);color:rgb(237,237,237)}
    .cluster-label span,.cluster span{color:rgb(237,237,237)}.cluster-label span p{background-color:transparent}
    .rough-node .label text,.node .label text,.image-shape .label,.icon-shape .label{text-anchor:middle}
    .node .katex path{fill:#000;stroke:#000;stroke-width:1px}
    .rough-node .label,.node .label,.image-shape .label,.icon-shape .label{text-align:center}
    .root .anchor path{fill:rgb(175,175,175)!important;stroke-width:0;stroke:rgb(175,175,175)}
    .arrowheadPath{fill:rgb(175,175,175)}.edgePath .path{stroke:rgb(175,175,175);stroke-width:1px}
    .flowchart-link{stroke:rgb(175,175,175);fill:none}
    .edgeLabel{background-color:rgb(0,0,0);text-align:center}.edgeLabel p{background-color:rgb(0,0,0)}
    .edgeLabel rect{opacity:.5;background-color:rgb(0,0,0);fill:rgb(0,0,0)}.labelBkg{background-color:rgba(0,0,0,.5)}
    .cluster rect{fill:rgb(48,48,48);stroke:rgba(255,255,255,.15);stroke-width:1px}
    .flowchartTitleText{text-anchor:middle;font-size:18px;fill:rgb(237,237,237)}rect.text{fill:none;stroke-width:0}
    .icon-shape,.image-shape{background-color:rgb(0,0,0);text-align:center}
    .icon-shape p,.image-shape p{background-color:rgb(0,0,0);padding:2px}
    .icon-shape .label rect,.image-shape .label rect{opacity:.5;background-color:rgb(0,0,0);fill:rgb(0,0,0)}
    .label-icon{display:inline-block;height:1em;overflow:visible;vertical-align:-.125em}
    .node .label-icon path{fill:currentColor;stroke:revert;stroke-width:revert}
    .node text{font-size:14px;font-weight:600;letter-spacing:normal;fill:rgb(153,206,255)}
    .edgeLabels text{font-size:13px;font-weight:600;letter-spacing:-.08px;fill:rgb(153,206,255)}
    .node tspan[font-weight="normal"],.edgeLabels tspan[font-weight="normal"]{font-weight:600}
    .edgeLabel .label rect{opacity:1;rx:13px;ry:13px;fill:rgb(0,14,26);stroke:rgb(26,62,95);stroke-width:1px}
    .node rect,.node circle,.node ellipse,.node polygon,.node path{fill:rgb(0,40,77);stroke:rgba(255,255,255,.1);stroke-width:1px}
    .node rect{rx:16px;ry:16px}.node.mermaid-decision .label-container{fill:rgb(0,14,26);stroke:rgb(26,62,95);stroke-dasharray:2,2}
    .edgePaths .flowchart-link{stroke:rgb(175,175,175);stroke-width:1px;stroke-linecap:round;stroke-linejoin:round}
    .done rect,.done polygon,.done ellipse,.done circle,.done path{fill:rgb(20,83,45)!important;stroke:rgb(34,197,94)!important;color:#fff!important;stroke-width:2px!important}.done tspan{fill:#fff!important}
    .active rect,.active polygon,.active ellipse,.active circle,.active path{fill:rgb(30,64,175)!important;stroke:rgb(59,130,246)!important;color:#fff!important;stroke-width:2px!important}.active tspan{fill:#fff!important}
    .blocked rect,.blocked polygon,.blocked ellipse,.blocked circle,.blocked path{fill:rgb(127,29,29)!important;stroke:rgb(239,68,68)!important;color:#fff!important;stroke-width:2px!important}.blocked tspan{fill:#fff!important}
    )'

    /**
     * Thinking block inner texts; index N corresponds to placeholder ¤THINKING_N¤.
     * @type {Array}
     */
    static _thinkingBlocks := []

    /**
     * User message raw text blocks; index N corresponds to placeholder ¤USERMSG_N¤.
     * @type {Array}
     */
    static _userMsgBlocks := []

    /**
     * Original diagram SVGs, indexed by their protected placeholders.
     * @type {Array}
     */
    static _svgBlocks := []

    /**
     * Normalizes an HTML fragment for pandoc processing.
     *
     * Transforms are applied in order:
     *   1.  Image/SVG handling: drop if no accessible text, else (img: text); leave when showImg
     *   2.  Poster-label placeholder injection (when showPoster)
     *   3.  Diff-block normalization (diffs-container → pre/code language-diff)
     *   4.  Button stripping
     *   5.  ChatGPT code block extraction (pre.overflow-visible! → pre/code)
     *   6.  KaTeX wrapper collapse (keep MathML, drop visual HTML fallback)
     *   7.  Task-list checkbox normalization (canonical <input type="checkbox">)
     *   8.  Thinking block extraction (→ ¤THINKING_N¤)
     *   9.  Inline-code span promotion (inline-markdown/font-mono → <code>)
     *   10. User message extraction (→ ¤USERMSG_N¤)
     *   11. Claude Web language-label div removal
     *   12. Footnote URL stripping (long URLs → #fragment)
     *   13. Nested-span bold promotion
     *   14. Residual span tag removal
     *   15. Bare <li> list wrapping in <ol>
     *   16. <code> element normalization (line-break conversion, pre-wrapping)
     *   17. Empty code/pre removal
     *   18. Nested container unwrapping
     *
     * @param {string} htmlFrag  - HTML fragment from the CF_HTML clipboard
     * @param {string} source    - Source identifier from DetectSource()
     * @param {boolean} showPoster - Inject ¤POSTER_AI¤/¤POSTER_User¤ markers
     * @param {boolean} showImg    - Keep <img> tags for pandoc when true
     * @returns {string} Canonical HTML ready for pandoc
     */
    static Normalize(htmlFrag, source, showPoster, showImg) {
        HtmlNorm._thinkingBlocks := []
        HtmlNorm._userMsgBlocks  := []
        HtmlNorm._svgBlocks := []
        html := htmlFrag

        if (source = "chatgpt") {
            html := HtmlNorm._RemoveChatGptUi(html)
            html := HtmlNorm._ExtractChatGptSvg(html)
        }

        ; 1. Handle <img> tags.
        html := HtmlNorm._ProcessImgTags(html, showImg)

        ; 2. Inject poster-label placeholders.
        if showPoster
            html := HtmlNorm._InjectPosterPlaceholders(html, source)

        ; 3. Convert tool diff containers into canonical language-diff code blocks.
        html := HtmlNorm._NormalizeSimpleDiffBlocks(html)

        ; 4. Preserve semantic inline entity buttons, then strip UI buttons.
        html := RegExReplace(html
            , "is)<button\b(?=[^>]*\bbehavior-btn\b)(?=[^>]*\bentity-underline\b)[^>]*+>(.*?)</button>"
            , "<u>$1</u>")
        ; Preserve inline link-style buttons (e.g. Codex function references with
        ; text-token-text-link-foreground): keep their text content, strip only the wrapper.
        ; The <span> tags left inside are removed by the residual span stripper in step 13.
        html := RegExReplace(html
            , "is)<button\b(?=[^>]*\btext-token-text-link-foreground\b)[^>]*+>(.*?)</button>"
            , "$1")
        html := RegExReplace(html, "is)<button\b[^>]*+>.*?</button>", "")

        ; 5. ChatGPT: normalize CodeMirror code blocks before any span stripping.
        if (source = "chatgpt")
            html := HtmlNorm._NormalizeChatGptCodeBlocks(html)

        ; 6. Keep only semantic MathML from KaTeX wrappers.
        html := HtmlNorm._NormalizeKatexMath(html)

        ; 7. Normalize task-list checkboxes.
        html := HtmlNorm._NormalizeTaskListItems(html)

        ; 8. Extract thinking blocks.
        html := HtmlNorm._ExtractThinkingBlocks(html)

        ; 9. Promote inline-code spans.
        html := RegExReplace(html, "is)<span\b[^>]*\bclass=`"[^`"]*\b(?:inline-markdown|font-mono)\b[^`"]*`"[^>]*+>(.*?)</span>", "<code>$1</code>")

        ; 10. Extract whitespace-sensitive user message text.
        html := HtmlNorm._ExtractUserMessages(html)

        ; 11. Strip Claude Web language-label divs (font-small p-3.5 pb-0).
        html := RegExReplace(html, "is)<div\b[^>]*\bclass=`"[^`"]*\bfont-small\b[^`"]*\bp-3[^`"]*`"[^>]*+>.*?</div>", "")

        ; 12. Strip long footnote hrefs, keeping only the #fragment.
        html := RegExReplace(html, "i)href=`"[^`"]*#(user-content-[^`"]*+)`"", "href=`"#$1`"")

        ; 12b. Strip <p> wrapper inside footnote definition <li> elements.
        ;      <li id="user-content-fn-N"><p>text</p></li> → <li id="...">text</li>
        ;      Without this, pandoc renders footnote lists in loose format (number on
        ;      its own line, content indented), instead of tight (number + content inline).
        html := RegExReplace(html, "is)(<li\b[^>]*\bid=`"user-content-fn-[^`"]*+`"[^>]*+>)\s*+<p\b[^>]*+>(.*?)</p>\s*+(</li>)", "$1$2$3")

        ; 12c. Tight-list normalization: unwrap wrapper-only block containers in list items.
        ;      <li><div><div><p>text</p></div></div></li> → <li>text</li>
        ;      This avoids raw HTML wrapper output from pandoc.
        html := HtmlNorm._NormalizeListItemBlockWrappers(html)

        ; 12d. Tight-list normalization: unwrap solitary paragraph wrappers in list items.
        ;      <li><p>text</p></li> → <li>text</li>
        ;      This avoids loose-list markdown output (blank lines between items).
        html := HtmlNorm._NormalizeTightListItems(html)

        ; 13. Promote ChatGPT's current bold selection shape before span stripping.
        html := HtmlNorm._NormalizeNestedSpanBold(html)

        ; 14. Strip residual <span> tags.
        html := RegExReplace(html, "i)</?+span\b[^>]*+>", "")

        ; 15. Wrap bare top-level <li> siblings in <ol>.
        htmlNoTrailingBr := RegExReplace(html, "is)(?:<br\b[^>]*+>\s*+)++$", "")
        trimmed := Trim(htmlNoTrailingBr, " `t`r`n")
        if (trimmed != "" && RegExMatch(trimmed, "is)^(?:<li\b[^>]*+>.*?</li>\s*)+$"))
            html := "<ol>" . trimmed . "</ol>"

        ; 16. Normalize <code> elements.
        html := HtmlNorm._NormalizeCodeElements(html)

        ; 17. Remove empty code/pre blocks before pandoc emits blank fences.
        html := HtmlNorm._RemoveEmptyCodeBlocks(html)

        ; 18. Unwrap nested containers that obscure code blocks.
        if (source != "chatgpt" || HtmlNorm._HasChatGptCodeContainerShape(html))
            html := HtmlNorm._UnwrapNestedContainers(html)

        return html
    }

    ; ─────────────────────────────────────────────────────────────────────────
    ; Phase methods
    ; ─────────────────────────────────────────────────────────────────────────

    /**
     * Removes ChatGPT action controls and conversation status banners.
     * Removes whole balanced UI subtrees while retaining message content.
     * @param {string} html
     * @returns {string}
     */
    static _RemoveChatGptUi(html) {
        ; Some clipboard providers flatten SVG into a leaf div containing its
        ; stylesheet and labels. Treat that representation like the SVG image.
        ; Without SVG bytes, retain the labels and identify the unavailable image.
        pos := 1
        while RegExMatch(html, "is)<div\b[^>]*>(\s*#chatgpt-mermaid-[\w-]+\{[^<]*)</div>", &flat, pos) {
            labels := flat[1]
            rule := "is)\A\s*(?:#chatgpt-mermaid-[^{}<]*|@keyframes[^{}<]*)(?<block>\{(?:[^{}]++|(?&block))*\})"
            while RegExMatch(labels, rule, &css)
                labels := SubStr(labels, css.Len + 1)
            replacement := "<p><em>Diagram text (image unavailable):</em> " . labels . "</p>"
            html := SubStr(html, 1, flat.Pos - 1) . replacement . SubStr(html, flat.Pos + flat.Len)
            pos := flat.Pos + StrLen(replacement)
        }
        pos := 1
        pat := 'is)<(div|aside)\b(?:[^>"' . "'" . ']|"[^"]*"|' . "'[^']*'" . ')*>'
        while RegExMatch(html, pat, &m, pos) {
            tag := m[0]
            isControls := RegExMatch(tag, 'i)\b(?:data-)?markdown-copy="exclude"')
                || RegExMatch(tag, 'i)\bclass="[^"]*\bturn-action-controls\b')
            isBanner := (StrLower(m[1]) = "aside" && (InStr(tag, 'role="alert"')
                || RegExMatch(SubStr(html, m.Pos), "is)^<aside\b[^>]*>(?:(?!</aside>).)*You've reached the maximum length for this conversation")))
            if (isControls || isBanner) {
                endPos := HtmlNorm._FindMatchingElementEnd(html, m.Pos, m[1])
                if endPos {
                    html := SubStr(html, 1, m.Pos - 1) . SubStr(html, endPos + 1)
                    pos := m.Pos
                    continue
                }
            }
            pos := m.Pos + m.Len
        }
        ; ChatGPT decorates real links with UI attributes. Keep the destination
        ; so pandoc parses their bold/code children instead of emitting raw HTML.
        pos := 1
        linkPat := 'is)<a\b(?:[^>"' . "'" . ']|"[^"]*"|' . "'[^']*'" . ')*>'
        while RegExMatch(html, linkPat, &m, pos) {
            replacement := "<a>"
            if RegExMatch(m[0], 'is)\bhref\s*=\s*("[^"]*"|' . "'[^']*'" . ')', &href)
                replacement := "<a href=" . href[1] . ">"
            html := SubStr(html, 1, m.Pos - 1) . replacement . SubStr(html, m.Pos + m.Len)
            pos := m.Pos + StrLen(replacement)
        }
        return html
    }

    /**
     * Protects ChatGPT diagram SVGs from generic image stripping and pandoc.
     * A containing code widget can later replace its placeholder with Mermaid
     * source; otherwise the original SVG is restored as an embedded image.
     * @param {string} html
     * @returns {string}
     */
    static _ExtractChatGptSvg(html) {
        pos := 1
        while RegExMatch(html, 'is)<svg\b(?=[^>]*\bid="chatgpt-mermaid-)[^>]*>', &m, pos) {
            endPos := HtmlNorm._FindMatchingElementEnd(html, m.Pos, "svg")
            if !endPos
                throw Error("Unclosed ChatGPT diagram SVG")
            svg := SubStr(html, m.Pos, endPos - m.Pos + 1)
            if !RegExMatch(svg, "i)<style\b")
                svg := SubStr(svg, 1, m.Len) . "<style>" . HtmlNorm.CHATGPT_SVG_FALLBACK_CSS . "</style>" . SubStr(svg, m.Len + 1)
            HtmlNorm._svgBlocks.Push(svg)
            replacement := "<p>¤SVG_" . HtmlNorm._svgBlocks.Length . "¤</p>"
            html := SubStr(html, 1, m.Pos - 1) . replacement . SubStr(html, endPos + 1)
            pos := m.Pos + StrLen(replacement)
        }
        return html
    }

    /**
     * Replaces `<img>` and `<svg>` elements according to the showImg flag.
     *
     * When showImg is false:
     *   - No accessible text (alt / title / aria-label / SVG `<title>`): dropped.
     *   - Has accessible text: replaced with `(img: <text>)`.
     *
     * When showImg is true, leaves elements in place for pandoc.
     *
     * @param {string} html
     * @param {boolean} showImg
     * @returns {string}
     */
    static _ProcessImgTags(html, showImg) {
        if showImg
            return html
        ; <img> tags (self-closing).
        pos := 1
        while RegExMatch(html, "i)<img\b([^>]*+)>", &m, pos) {
            attrs := m[1]
            accessText := ""
            if (RegExMatch(attrs, "i)\balt\s*+=\s*+['`"]([^'`"]*+)[`"']", &mA) && mA[1] != "")
                accessText := mA[1]
            else if (RegExMatch(attrs, "i)\btitle\s*+=\s*+['`"]([^'`"]*+)[`"']", &mT) && mT[1] != "")
                accessText := mT[1]
            else if (RegExMatch(attrs, "i)\baria-label\s*+=\s*+['`"]([^'`"]*+)[`"']", &mL) && mL[1] != "")
                accessText := mL[1]
            replacement := (accessText = "") ? "" : "(img: " . accessText . ")"
            html := SubStr(html, 1, m.Pos - 1) . replacement . SubStr(html, m.Pos + m.Len)
            pos := m.Pos + StrLen(replacement)
        }
        ; <svg>…</svg> elements — same rule, checking aria-label, title attr, or <title> child.
        pos := 1
        while RegExMatch(html, "is)<svg\b([^>]*+)>.*?</svg>", &m, pos) {
            attrs := m[1]
            full  := m[0]
            accessText := ""
            if (RegExMatch(attrs, "i)\baria-label\s*+=\s*+['`"]([^'`"]*+)[`"']", &mL) && mL[1] != "")
                accessText := mL[1]
            else if (RegExMatch(attrs, "i)\btitle\s*+=\s*+['`"]([^'`"]*+)[`"']", &mT) && mT[1] != "")
                accessText := mT[1]
            else if (RegExMatch(full, "i)<title\b[^>]*+>(.*?)</title>", &mTc) && mTc[1] != "")
                accessText := HtmlNorm._DecodeBasicHtmlEntities(mTc[1])
            replacement := (accessText = "") ? "" : "(img: " . accessText . ")"
            html := SubStr(html, 1, m.Pos - 1) . replacement . SubStr(html, m.Pos + m.Len)
            pos := m.Pos + StrLen(replacement)
        }
        return html
    }

    /**
     * Injects ¤POSTER_AI¤ / ¤POSTER_User¤ paragraph placeholders at the start
     * of each detected message container.  Only the patterns for the detected
     * source are applied; this prevents cross-source false positives (e.g. the
     * Codex flex-col patterns matching inner divs inside ChatGPT articles).
     * @param {string} html
     * @param {string} source - Source identifier from DetectSource()
     * @returns {string}
     */
    static _InjectPosterPlaceholders(html, source) {
        if (source = "claudecode") {
            ; AI turn
            html := RegExReplace(html, "i)(<div\b[^>]*\bdata-testid=`"assistant-message`"[^>]*+>)", "$1<p>¤POSTER_AI¤</p>")
            ; user turn (class has both message_* and userMessageContainer_*)
            html := RegExReplace(html, "i)(<div\b[^>]*\bclass=`"[^`"]*\bmessage_\w+\s+[^`"]*\buserMessageContainer_[^>]*+>)", "$1<p>¤POSTER_User¤</p>")
        } else if (source = "codex") {
            ; AI turn (group min-w-0 flex-col)
            html := RegExReplace(html, "i)(<div\b[^>]*\bclass=`"[^`"]*\bgroup\b[^`"]*\bmin-w-0\b[^`"]*\bflex-col\b[^`"]*`"[^>]*+>)", "$1<p>¤POSTER_AI¤</p>")
            ; user turn (flex-col items-end)
            html := RegExReplace(html, "i)(<div\b[^>]*\bclass=`"[^`"]*\bflex-col\b[^`"]*\bitems-end\b[^`"]*`"[^>]*+>)", "$1<p>¤POSTER_User¤</p>")
        } else if (source = "claudeweb") {
            ; AI turn (data-is-streaming or font-claude-response)
            html := RegExReplace(html, "i)(<div\b[^>]*(?:\bdata-is-streaming\b|\bclass=`"[^`"]*\bfont-claude-response\b[^`"]*`")[^>]*+>)", "$1<p>¤POSTER_AI¤</p>")
            ; user turn (data-testid="user-message")
            html := RegExReplace(html, "i)(<div\b[^>]*\bdata-testid=`"user-message`"[^>]*+>)", "$1<p>¤POSTER_User¤</p>")
        } else if (source = "chatgpt") {
            ; Flattened captures retain the application signature but no roles.
            if RegExMatch(html, "i)<pre\b[^>]*>\s*<code>\s*" . Chr(96) . "{3,}mermaid")
                && !RegExMatch(html, "i)data-(?:turn|markdown-text-style|user-message-bubble)=")
                html := "<p>¤POSTER_AI¤</p>" . html
            ; AI turn: prefer data-turn="assistant"; fall back to legacy data-turn-id="request-WEB:..." prefix.
            ; Both patterns may match the same turn container in older captures — the duplicate dedup in
            ; PasteMarkdown collapses consecutive same-type markers, so double injection is harmless.
            html := RegExReplace(html, "i)(<(?:article|section)\b[^>]*\bdata-turn=`"assistant`"[^>]*+>)", "$1<p>¤POSTER_AI¤</p>")
            html := RegExReplace(html, "i)(<(?:article|section)\b[^>]*\bdata-turn-id=`"request-WEB:[^`"]*+`"[^>]*+>)", "$1<p>¤POSTER_AI¤</p>")
            html := RegExReplace(html, "i)(<div\b[^>]*\bdata-(?:chatgpt-search|content-search)-unit-key=`"[^`"]*:assistant`"[^>]*+>)", "$1<p>¤POSTER_AI¤</p>")
            html := RegExReplace(html, "i)(<div\b[^>]*\bdata-markdown-text-style=`"assistant-message`"[^>]*+>)", "$1<p>¤POSTER_AI¤</p>")
            ; User turn: prefer data-turn="user"; fall back to legacy plain-UUID data-turn-id.
            html := RegExReplace(html, "i)(<(?:article|section)\b[^>]*\bdata-turn=`"user`"[^>]*+>)", "$1<p>¤POSTER_User¤</p>")
            html := RegExReplace(html, "i)(<div\b[^>]*\bdata-(?:chatgpt-search|content-search)-unit-key=`"[^`"]*:user`"[^>]*+>)", "$1<p>¤POSTER_User¤</p>")
            html := RegExReplace(html, "i)(<div\b[^>]*\bdata-user-message-bubble=`"true`"[^>]*+>)", "$1<p>¤POSTER_User¤</p>")
        }
        return html
    }

    /**
     * Converts VS Code chat/tool diff widgets to canonical HTML diff code blocks.
     *
     * Input shape (Codex/Claude tool output):
     * - <diffs-container ...>
     *   - many <div data-line-type="...">...</div> rows with line text
     *
     * Output shape:
     * - <pre><code class="language-diff">...</code></pre>
     *
     * Also preserves the edited filename when present in a nearby header button
     * (for example "test-paste-md-fixtures.ahk") by inserting a short
     * `<p><code>filename</code></p>` line before the diff block.
     *
     * Line-type mapping:
     * - deletion rows => '-' prefix
     * - addition rows => '+' prefix
     * - context/other rows => ' ' prefix
     *
     * @param {string} html
     * @returns {string}
     */
    static _NormalizeSimpleDiffBlocks(html) {
        pos := 1
        while RegExMatch(html, "is)<diffs-container\b[^>]*+>(.*?)</diffs-container>", &mDiff, pos) {
            inner := mDiff[1]
            fileName := ""
            ; The editable filename appears in a button before the diff block.
            ; Some captures include very large inline style payloads between header
            ; and diff body, so scan the full prefix and keep the last non-empty
            ; button label.
            before := SubStr(html, 1, mDiff.Pos - 1)
            btnPos := 1
            while RegExMatch(before, "is)<button\b[^>]*+>(.*?)</button>", &mBtn, btnPos) {
                btnText := RegExReplace(mBtn[1], "<[^>]++>", "")
                btnText := HtmlNorm._DecodeBasicHtmlEntities(btnText)
                btnText := Trim(btnText, " `t`r`n")
                if (btnText != "")
                    fileName := btnText
                btnPos := mBtn.Pos + mBtn.Len
            }
            linePos := 1
            diffLines := []
            while RegExMatch(inner, "is)<div\b[^>]*\bdata-line-type\s*+=\s*+['`"]([^'`"]++)['`"][^>]*+>(.*?)</div>", &mLine, linePos) {
                lineType := StrLower(mLine[1])
                lineHtml := mLine[2]
                lineText := RegExReplace(lineHtml, "<[^>]++>", "")
                lineText := HtmlNorm._DecodeBasicHtmlEntities(lineText)
                lineText := StrReplace(lineText, "`r", "")
                lineText := Trim(lineText, "`n")
                prefix := " "
                if InStr(lineType, "deletion")
                    prefix := "-"
                else if InStr(lineType, "addition")
                    prefix := "+"
                diffLines.Push(prefix . lineText)
                linePos := mLine.Pos + mLine.Len
            }

            if (diffLines.Length = 0) {
                pos := mDiff.Pos + mDiff.Len
                continue
            }

            diffText := ""
            for _, line in diffLines
                diffText .= (diffText = "" ? "" : "`n") . line

            ; Escape for safe embedding inside <code>.
            diffText := StrReplace(diffText, "&", "&amp;")
            diffText := StrReplace(diffText, "<", "&lt;")
            diffText := StrReplace(diffText, ">", "&gt;")

            header := ""
            if (fileName != "") {
                fileNameEsc := StrReplace(fileName, "&", "&amp;")
                fileNameEsc := StrReplace(fileNameEsc, "<", "&lt;")
                fileNameEsc := StrReplace(fileNameEsc, ">", "&gt;")
                header := "<p><code>" . fileNameEsc . "</code></p>"
            }

            replacement := header . '<pre><code class="language-diff">' . diffText . '</code></pre>'
            html := SubStr(html, 1, mDiff.Pos - 1) . replacement . SubStr(html, mDiff.Pos + mDiff.Len)
            pos := mDiff.Pos + StrLen(replacement)
        }
        return html
    }

    /**
     * Converts ChatGPT CodeMirror code blocks to canonical `<pre><code>` form.
     *
     * ChatGPT renders code blocks as `<pre class="overflow-visible! ...">` wrapping
     * a deeply nested CodeMirror viewer.  Pandoc interprets the class on `<pre>`
     * as a language tag, producing ` ```overflow-visible! ` fences.
     *
     * This method finds such `<pre>` blocks, strips all inner HTML tags, and
     * re-emits the code as `<pre><code>entity-safe text</code></pre>`.
     *
     * Must be called before span-stripping so that the structural divs are
     * still present (their stripping is idempotent here since they carry no text).
     *
     * @param {string} html
     * @returns {string}
     */
    static _NormalizeChatGptCodeBlocks(html) {
        ; An unlabelled code container can hold the widget's fenced copy source.
        ; Explicitly labelled examples (such as language-markdown) stay literal.
        pos := 1
        while RegExMatch(html, "is)<pre\b[^>]*>\s*<code>(.*?)</code>\s*</pre>", &m, pos) {
            replacement := HtmlNorm._MermaidCopyToCodeHtml(HtmlNorm._DecodeBasicHtmlEntities(m[1]))
            if (replacement != "") {
                html := SubStr(html, 1, m.Pos - 1) . replacement . SubStr(html, m.Pos + m.Len)
                pos := m.Pos + StrLen(replacement)
            } else
                pos := m.Pos + m.Len
        }
        ; Rendered Mermaid widgets carry fenced Markdown in their copy attribute.
        ; Convert the widget to semantic code, leaving fence emission to pandoc.
        pos := 1
        widgetPat := 'is)<div\b(?:[^>"' . "'" . ']|"[^"]*"|' . "'[^']*'" . ')*>'
        while RegExMatch(html, widgetPat, &m, pos) {
            if RegExMatch(m[0], 'is)\b(?:data-)?markdown-copy-text="([^"]*)"', &copy) {
                source := HtmlNorm._DecodeBasicHtmlEntities(copy[1])
                replacement := HtmlNorm._MermaidCopyToCodeHtml(source)
                if (replacement != "") {
                    endPos := HtmlNorm._FindMatchingElementEnd(html, m.Pos, "div")
                    if endPos {
                        html := SubStr(html, 1, m.Pos - 1) . replacement . SubStr(html, endPos + 1)
                        pos := m.Pos + StrLen(replacement)
                        continue
                    }
                }
            }
            pos := m.Pos + m.Len
        }
        pos := 1
        while RegExMatch(html, "is)<pre\b[^>]*\boverflow-visible\b[^>]*+>(.*?)</pre>", &m, pos) {
            inner := m[1]
            ; Convert <br> to newlines before stripping all other tags.
            inner := RegExReplace(inner, "i)<br\b[^>]*+>", "`n")
            ; Strip all HTML tags — leaves only the plain code text plus structural whitespace.
            codeText := RegExReplace(inner, "<[^>]++>", "")
            codeText := StrReplace(codeText, "`r", "")
            codeText := Trim(codeText, " `t`n")
            if (codeText = "") {
                pos := m.Pos + m.Len
                continue
            }
            ; Decode HTML entities so the raw code characters are correct.
            codeText := HtmlNorm._DecodeBasicHtmlEntities(codeText)
            ; Re-encode for safe embedding inside <code>…</code>.
            codeText := StrReplace(codeText, "&", "&amp;")
            codeText := StrReplace(codeText, "<", "&lt;")
            codeText := StrReplace(codeText, ">", "&gt;")
            replacement := "<pre><code>" . codeText . "</code></pre>"
            html := SubStr(html, 1, m.Pos - 1) . replacement . SubStr(html, m.Pos + m.Len)
            pos := m.Pos + StrLen(replacement)
        }
        return html
    }

    /**
     * Converts fenced Mermaid copy text to canonical HTML, or returns an empty
     * string when the text is not a complete Mermaid block.
     * @param {string} source
     * @returns {string}
     */
    static _MermaidCopyToCodeHtml(source) {
        pat := "is)\A\s*(" . Chr(96) . "{3,})mermaid[^\S\r\n]*\r?\n(.*?)\r?\n\1\s*\z"
        if !RegExMatch(source, pat, &code)
            return ""
        content := StrReplace(code[2], "&", "&amp;")
        content := StrReplace(content, "<", "&lt;")
        content := StrReplace(content, ">", "&gt;")
        return '<pre><code class="language-mermaid">' . content . '</code></pre>'
    }

    /**
     * Collapses KaTeX wrapper spans to semantic MathML only.
     *
     * KaTeX emits sibling branches inside `<span class="katex">`:
     * - `<span class="katex-mathml">...</span>` semantic source
     * - `<span class="katex-html" ...>...</span>` visual layout fallback
     *
     * The generic residual-span stripper removes the wrapper tags but leaves the
     * visual branch text behind, which duplicates math as flattened garbage.
     *
     * @param {string} html
     * @returns {string}
     */
    static _NormalizeKatexMath(html) {
        pos := 1
        patKatex := "is)<span\b[^>]*\bclass\s*+=\s*+['`"][^'`"]*(?<![-\w])katex(?![-\w])[^'`"]*['`"][^>]*+>"
        while RegExMatch(html, patKatex, &mKatex, pos) {
            if (mKatex.Pos != pos && mKatex.Pos < pos)
                break
            katexEnd := HtmlNorm._FindMatchingElementEnd(html, mKatex.Pos, "span")
            if !katexEnd {
                pos := mKatex.Pos + mKatex.Len
                continue
            }
            katexBlock := SubStr(html, mKatex.Pos, katexEnd - mKatex.Pos + 1)
            collapsed := HtmlNorm._CollapseKatexSpanBlock(katexBlock)
            if (collapsed = katexBlock) {
                pos := katexEnd + 1
                continue
            }
            html := SubStr(html, 1, mKatex.Pos - 1) . collapsed . SubStr(html, katexEnd + 1)
            pos := mKatex.Pos + StrLen(collapsed)
        }
        return html
    }

    /**
     * Returns semantic MathML from a `<span class="katex">...</span>` block when
     * its only substantive children are `katex-mathml` and `katex-html`.
     * @param {string} katexBlock
     * @returns {string}
     */
    static _CollapseKatexSpanBlock(katexBlock) {
        if !RegExMatch(katexBlock, "is)^<span\b[^>]*+>", &mOpen)
            return katexBlock

        closeLen := StrLen("</span>")
        innerLen := StrLen(katexBlock) - mOpen.Len - closeLen
        if (innerLen < 0)
            return katexBlock
        inner := SubStr(katexBlock, mOpen.Len + 1, innerLen)

        pos := HtmlNorm._SkipHtmlWhitespace(inner, 1)
        if !RegExMatch(inner, "is)<span\b[^>]*\bclass\s*+=\s*+['`"][^'`"]*(?<![-\w])katex-mathml(?![-\w])[^'`"]*['`"][^>]*+>", &mMath, pos)
            return katexBlock
        if (mMath.Pos != pos)
            return katexBlock
        mathEnd := HtmlNorm._FindMatchingElementEnd(inner, pos, "span")
        if !mathEnd
            return katexBlock
        mathBlock := SubStr(inner, pos, mathEnd - pos + 1)
        if !RegExMatch(mathBlock, "is)^<span\b[^>]*+>", &mMathOpen)
            return katexBlock
        mathInnerLen := StrLen(mathBlock) - mMathOpen.Len - closeLen
        if (mathInnerLen < 0)
            return katexBlock
        mathInner := SubStr(mathBlock, mMathOpen.Len + 1, mathInnerLen)

        pos := HtmlNorm._SkipHtmlWhitespace(inner, mathEnd + 1)
        if !RegExMatch(inner, "is)<span\b[^>]*\bclass\s*+=\s*+['`"][^'`"]*(?<![-\w])katex-html(?![-\w])[^'`"]*['`"][^>]*+>", &mHtml, pos)
            return katexBlock
        if (mHtml.Pos != pos)
            return katexBlock
        htmlEnd := HtmlNorm._FindMatchingElementEnd(inner, pos, "span")
        if !htmlEnd
            return katexBlock

        pos := HtmlNorm._SkipHtmlWhitespace(inner, htmlEnd + 1)
        if (pos <= StrLen(inner))
            return katexBlock
        return mathInner
    }

    /**
     * Normalizes task-list `<li>` elements to a canonical checkbox-input form.
     *
     * Processes any `<li class="task-list-item">` that contains
     * `<input type="checkbox">`, regardless of whether the input is a direct
     * child or wrapped in a `<p>` tag (as ChatGPT does).
     *
     * Output form is:
     *   <li><input type="checkbox" disabled [checked] /> text</li>
     *
     * This lets pandoc emit GFM task-list markers natively.
     *
     * @param {string} html
     * @returns {string}
     */
    static _NormalizeTaskListItems(html) {
        pos := 1
        while RegExMatch(html, "is)<li\b([^>]*+)>(.*?)</li>", &mTask, pos) {
            liAttrs := mTask[1]
            liInner := mTask[2]
            ; Supported task-list containers:
            ; - Standard markdown renderers: class contains task-list-item
            ; - Claude Code todo tool rows: class contains todoItem_*
            if (!RegExMatch(liAttrs, "i)\btask-list-item\b")
                && !RegExMatch(liAttrs, "i)\btodoItem_")) {
                pos := mTask.Pos + mTask.Len
                continue
            }
            ; Find <input type="checkbox"> anywhere inside the item
            ; (direct child OR inside a <p> wrapper, as ChatGPT does).
            if !RegExMatch(liInner, "is)<input\b[^>]*\btype\s*+=\s*+['`"]checkbox['`"][^>]*+>", &mInput) {
                pos := mTask.Pos + mTask.Len
                continue
            }
            checked := RegExMatch(liInner, "i)\bchecked\b")
            if (!checked) {
                if RegExMatch(liAttrs, "i)\bcompleted_")
                    checked := true
                else if RegExMatch(liInner, "i)\btext-decoration\s*:\s*line-through\b")
                    checked := true
            }
            ; Capture text that follows the <input> tag.
            text := SubStr(liInner, mInput.Pos + mInput.Len)
            text := RegExReplace(text, "is)<span\b[^>]*+>\s*+</span>", "")
            text := RegExReplace(text, "<[^>]++>", "")
            text := HtmlNorm._DecodeBasicHtmlEntities(text)
            text := Trim(text, " `t`r`n" . Chr(160))
            ; Re-encode for HTML context.
            text := StrReplace(text, "&", "&amp;")
            text := StrReplace(text, "<", "&lt;")
            text := StrReplace(text, ">", "&gt;")
            inputTag := checked
                ? '<input type="checkbox" disabled checked />'
                : '<input type="checkbox" disabled />'
            replacement := "<li>" . inputTag
            if (text != "")
                replacement .= " " . text
            replacement .= "</li>"
            html := SubStr(html, 1, mTask.Pos - 1) . replacement . SubStr(html, mTask.Pos + mTask.Len)
            pos := mTask.Pos + StrLen(replacement)
        }
        return html
    }

    /**
     * Unwraps block-only containers inside simple list items.
     *
     * ChatGPT may emit ordinary bullet items as nested block containers such as
     * `<li><div><div><p>text</p></div></div></li>`. Pandoc preserves those
     * `<div>` wrappers as raw HTML in GFM, which produces blank list markers
     * after `CleanMarkdown()` removes the tags. This normalization restores the
     * semantic list item before pandoc sees it.
     *
     * Wrapper-only leaf items with empty paragraph content are removed. Items
     * that contain nested lists or sibling content are left for the broader
     * HTML pipeline.
     *
     * @param {string} html
     * @returns {string}
     */
    static _NormalizeListItemBlockWrappers(html) {
        if !RegExMatch(html, "i)<li\b")
            return html
        if !RegExMatch(html, "i)<div\b")
            return html
        if !RegExMatch(html, "i)<p\b")
            return html

        pos := 1
        while RegExMatch(html, "is)<li\b[^>]*+>", &mLi, pos) {
            liEnd := HtmlNorm._FindMatchingElementEnd(html, mLi.Pos, "li")
            if !liEnd {
                pos := mLi.Pos + mLi.Len
                continue
            }

            liBlock := SubStr(html, mLi.Pos, liEnd - mLi.Pos + 1)
            replacement := HtmlNorm._NormalizeListItemBlockWrapper(liBlock)
            if (replacement = liBlock) {
                pos := liEnd + 1
                continue
            }

            html := SubStr(html, 1, mLi.Pos - 1) . replacement . SubStr(html, liEnd + 1)
            pos := mLi.Pos + StrLen(replacement)
        }
        return html
    }

    /**
     * Unwraps a single list item whose only content is nested `<div>` wrappers
     * around one leaf `<p>`.
     * @param {string} liBlock
     * @returns {string}
     */
    static _NormalizeListItemBlockWrapper(liBlock) {
        if !RegExMatch(liBlock, "is)^<li\b([^>]*+)>", &mLi)
            return liBlock

        attrs := mLi[1]
        closeLen := StrLen("</li>")
        innerLen := StrLen(liBlock) - mLi.Len - closeLen
        if (innerLen < 0 || SubStr(liBlock, StrLen(liBlock) - closeLen + 1) != "</li>")
            return liBlock

        inner := HtmlNorm._UnwrapOnlyNestedDivs(SubStr(liBlock, mLi.Len + 1, innerLen))
        if (inner = "")
            return liBlock

        pos := HtmlNorm._SkipHtmlWhitespace(inner, 1)
        if !RegExMatch(inner, "is)<p\b[^>]*+>", &mP, pos)
            return liBlock
        if (mP.Pos != pos)
            return liBlock

        pEnd := HtmlNorm._FindMatchingElementEnd(inner, pos, "p")
        if !pEnd
            return liBlock

        after := HtmlNorm._SkipHtmlWhitespace(inner, pEnd + 1)
        if (after <= StrLen(inner))
            return liBlock

        closeLen := StrLen("</p>")
        contentStart := pos + mP.Len
        contentLen := pEnd - closeLen + 1 - contentStart
        if (contentLen < 0)
            return liBlock

        content := SubStr(inner, contentStart, contentLen)
        if RegExMatch(content, "is)<(?:ul|ol|li)\b")
            return liBlock

        return Trim(content, " `t`r`n" . Chr(160)) = ""
            ? ""
            : "<li" . attrs . ">" . content . "</li>"
    }

    /**
     * Removes one or more nested `<div>` wrappers when each wrapper is the only
     * element at its level.
     * @param {string} html
     * @returns {string}
     */
    static _UnwrapOnlyNestedDivs(html) {
        unwrapped := false
        loop {
            pos := HtmlNorm._SkipHtmlWhitespace(html, 1)
            if !RegExMatch(html, "is)<div\b[^>]*+>", &mDiv, pos)
                return unwrapped ? html : ""
            if (mDiv.Pos != pos)
                return ""

            divEnd := HtmlNorm._FindMatchingElementEnd(html, pos, "div")
            if !divEnd
                return ""

            after := HtmlNorm._SkipHtmlWhitespace(html, divEnd + 1)
            if (after <= StrLen(html))
                return ""

            closeLen := StrLen("</div>")
            contentStart := pos + mDiv.Len
            contentLen := divEnd - closeLen + 1 - contentStart
            if (contentLen < 0)
                return ""

            html := SubStr(html, contentStart, contentLen)
            unwrapped := true
        }
    }

    /**
     * Unwraps solitary `<p>` wrappers inside list items.
     * Only applies to simple `<li><p>...</p></li>` shapes.
     * @param {string} html
     * @returns {string}
     */
    static _NormalizeTightListItems(html) {
        if !RegExMatch(html, "i)<li\b")
            return html
        if !RegExMatch(html, "i)<p\b")
            return html
        ; Case 1: list-item lead paragraph followed by nested list.
        html := RegExReplace(
            html,
            "is)(<li\b[^>]*+>)\s*+<p\b[^>]*+>((?:(?!</p>|<ul\b|<ol\b|<li\b).)++)</p>\s*+((?:<ul\b|<ol\b))",
            "$1$2$3"
        )
        ; Case 2: leaf list item with only a paragraph wrapper.
        html := RegExReplace(
            html,
            "is)(<li\b[^>]*+>)\s*+<p\b[^>]*+>((?:(?!</p>|<ul\b|<ol\b|<li\b).)++)</p>\s*+(</li>)",
            "$1$2$3"
        )
        return html
    }

    /**
     * Promotes the nested-span shape ChatGPT uses for bold inline text.
     *
     * Recent ChatGPT clipboard HTML can represent a bold phrase as one plain
     * outer `<span>` containing two or more plain child `<span>` nodes, with no
     * `<strong>` tag or `font-weight` style. The residual span stripper would
     * otherwise flatten that phrase to plain text.
     *
     * @param {string} html
     * @returns {string}
     */
    static _NormalizeNestedSpanBold(html) {
        if (html = "")
            return html

        pat := "is)<span\b[^>]*+>\s*+((?:<span\b[^>]*+>[^<>]*+</span>\s*+){2,})</span>"
        pos := 1
        while RegExMatch(html, pat, &m, pos) {
            inner := m[1]
            if RegExMatch(m[0], "is)<(?:strong|b|em|i|code|a|math|pre)\b") {
                pos := m.Pos + m.Len
                continue
            }

            text := RegExReplace(inner, "is)</?span\b[^>]*+>", "")
            replacement := "<strong>" text "</strong>"
            html := SubStr(html, 1, m.Pos - 1) . replacement . SubStr(html, m.Pos + m.Len)
            pos := m.Pos + StrLen(replacement)
        }
        return html
    }

    /**
     * Extracts `<details class="thinking">` blocks into ¤THINKING_N¤ placeholders.
     * The inner text (summary removed, tags stripped) is stored in `_thinkingBlocks`.
     * `PasteMd.RestoreThinkingBlocks()` restores them after pandoc.
     * @param {string} html
     * @returns {string}
     */
    static _ExtractThinkingBlocks(html) {
        pos := 1
        while RegExMatch(html, "is)<details\b[^>]*\bclass=`"[^`"]*\bthinking\b[^`"]*`"[^>]*+>(.*?)</details>", &m, pos) {
            inner := m[1]
            inner := RegExReplace(inner, "is)<summary\b[^>]*+>.*?</summary>", "")
            inner := RegExReplace(inner, "<[^>]++>", "")
            inner := HtmlNorm._DecodeBasicHtmlEntities(inner)
            inner := Trim(inner, " `t`n`r")
            HtmlNorm._thinkingBlocks.Push(inner)
            placeholder := "¤THINKING_" . HtmlNorm._thinkingBlocks.Length . "¤"
            html := SubStr(html, 1, m.Pos - 1) . placeholder . SubStr(html, m.Pos + m.Len)
            pos := m.Pos + StrLen(placeholder)
        }
        return html
    }

    /**
     * Extracts whitespace-sensitive user message text into ¤USERMSG_N¤ placeholders.
     *
     * Four container types are handled (all source-specific enough to avoid false
     * positives without explicit source gating):
     *
     * - Codex: `<div class="text-size-chat whitespace-pre-wrap">` with mixed
     *   `<span>` and `<code class="font-mono">` children.
     * - Claude Code: `<div class="content_xGDvVg">` with a single `<span>` child.
     * - Claude Web: `<p class="whitespace-pre-wrap break-words">` — plain text with
     *   embedded literal newlines; `<br>` tags possible.
     * - ChatGPT: `<div class="whitespace-pre-wrap">` (exact sole class value) —
     *   plain text with embedded literal newlines.
     *
     * `PasteMd.RestoreUserMsgBlocks()` restores the plain text after pandoc.
     * @param {string} html
     * @returns {string}
     */
    static _ExtractUserMessages(html) {
        ; Codex user messages: <div class="text-size-chat whitespace-pre-wrap">
        pos := 1
        while RegExMatch(html, "is)(<div\b[^>]*\btext-size-chat\b[^>]*\bwhitespace-pre-wrap\b[^>]*+>)(.*?)</div>", &m, pos) {
            rawContent := m[2]
            rawContent := RegExReplace(rawContent, "is)<code\b[^>]*\bfont-mono\b[^>]*+>(.*?)</code>", "``$1``")
            rawContent := RegExReplace(rawContent, "i)</?span\b[^>]*+>", "")
            rawContent := RegExReplace(rawContent, "<[^>]++>", "")
            rawContent := HtmlNorm._DecodeBasicHtmlEntities(rawContent)
            rawContent := StrReplace(rawContent, "`r", "")
            rawContent := Trim(rawContent, "`n")
            HtmlNorm._userMsgBlocks.Push(rawContent)
            placeholder := "<p>¤USERMSG_" . HtmlNorm._userMsgBlocks.Length . "¤</p>"
            newStr := m[1] . placeholder . "</div>"
            html := SubStr(html, 1, m.Pos - 1) . newStr . SubStr(html, m.Pos + m.Len)
            pos := m.Pos + StrLen(newStr)
        }
        ; Claude Code user messages: <div class="content_xGDvVg"><span>text</span>
        pos := 1
        while RegExMatch(html, "is)(<div\b[^>]*\bcontent_xGDvVg\b[^>]*+>)\s*+<span>(.*?)</span>", &m, pos) {
            rawText := HtmlNorm._DecodeBasicHtmlEntities(m[2])
            rawText := StrReplace(rawText, "`r", "")
            HtmlNorm._userMsgBlocks.Push(rawText)
            placeholder := "<p>¤USERMSG_" . HtmlNorm._userMsgBlocks.Length . "¤</p>"
            newStr := m[1] . placeholder
            html := SubStr(html, 1, m.Pos - 1) . newStr . SubStr(html, m.Pos + m.Len)
            pos := m.Pos + StrLen(newStr)
        }
        ; Claude Web user messages: <p class="whitespace-pre-wrap break-words">
        ; Replace the entire <p>...</p> with the placeholder (not nested inside the
        ; original <p>, which would produce invalid nested <p> elements).
        pos := 1
        while RegExMatch(html, "is)(<p\b[^>]*\bclass=`"whitespace-pre-wrap break-words`"[^>]*+>)(.*?)</p>", &m, pos) {
            rawContent := m[2]
            rawContent := RegExReplace(rawContent, "i)<br\b[^>]*+>", "`n")
            rawContent := RegExReplace(rawContent, "<[^>]++>", "")
            rawContent := HtmlNorm._DecodeBasicHtmlEntities(rawContent)
            rawContent := StrReplace(rawContent, "`r", "")
            rawContent := Trim(rawContent, "`n")
            HtmlNorm._userMsgBlocks.Push(rawContent)
            placeholder := "<p>¤USERMSG_" . HtmlNorm._userMsgBlocks.Length . "¤</p>"
            html := SubStr(html, 1, m.Pos - 1) . placeholder . SubStr(html, m.Pos + m.Len)
            pos := m.Pos + StrLen(placeholder)
        }
        ; ChatGPT user messages: <div class="whitespace-pre-wrap"> (exact sole class).
        ; Exact-value match avoids re-matching Codex's "text-size-chat whitespace-pre-wrap"
        ; outer tag, which still carries the class after Codex extraction above.
        ; Replace the entire <div>...</div> with the placeholder.
        pos := 1
        while RegExMatch(html, "is)(<div\b[^>]*\bclass=`"whitespace-pre-wrap`"[^>]*+>)(.*?)</div>", &m, pos) {
            rawContent := m[2]
            rawContent := RegExReplace(rawContent, "i)<br\b[^>]*+>", "`n")
            rawContent := RegExReplace(rawContent, "<[^>]++>", "")
            rawContent := HtmlNorm._DecodeBasicHtmlEntities(rawContent)
            rawContent := StrReplace(rawContent, "`r", "")
            rawContent := Trim(rawContent, "`n")
            HtmlNorm._userMsgBlocks.Push(rawContent)
            placeholder := "<p>¤USERMSG_" . HtmlNorm._userMsgBlocks.Length . "¤</p>"
            html := SubStr(html, 1, m.Pos - 1) . placeholder . SubStr(html, m.Pos + m.Len)
            pos := m.Pos + StrLen(placeholder)
        }
        return html
    }

    /**
     * Processes each `<code>` element: converts `<br>` and `</div><div>` sequences
     * to newlines, strips inner tags, and wraps multi-line content in `<pre>` if
     * not already inside one.  Preserves `class="language-xxx"` on the `<code>`
     * element while discarding other CSS utility classes.
     * @param {string} html
     * @returns {string}
     */
    static _NormalizeCodeElements(html) {
        pos := 1
        while RegExMatch(html, "is)<code\b([^>]*+)>(.*?)</code>", &m, pos) {
            content := m[2]
            attrs   := m[1]
            ; Normalize line-break representations inside the code.
            content := RegExReplace(content, "i)<br\b[^>]*+>", "`n")
            content := RegExReplace(content, "i)</div>\s*+<div\b[^>]*+>", "`n")
            content := RegExReplace(content, "<[^>]++>", "")
            content := StrReplace(content, "`r", "")
            if InStr(content, "`n") {
                content := HtmlNorm._DecodeBasicHtmlEntities(content)
                ; Extract language identifier; discard pure-CSS classes.
                langAttr := ""
                if RegExMatch(attrs, "i)language-(\w++)", &langM)
                    langAttr := ' class="language-' . langM[1] . '"'
                ; Check whether this <code> is already the direct child of a <pre>.
                beforeSnippet := SubStr(html, Max(1, m.Pos - 100), Min(100, m.Pos - 1))
                if RegExMatch(beforeSnippet, "i)<pre\b[^>]*+>\s*+$")
                    replacement := "<code" . langAttr . ">" . content . "</code>"
                else
                    replacement := "<pre><code" . langAttr . ">" . content . "</code></pre>"
            } else {
                ; Single-line: leave as inline <code>.
                replacement := "<code" . attrs . ">" . content . "</code>"
            }
            html := SubStr(html, 1, m.Pos - 1) . replacement . SubStr(html, m.Pos + m.Len)
            pos := m.Pos + StrLen(replacement)
        }
        return html
    }

    /**
     * Removes empty `<pre><code>` and `<code>` elements.
     *
     * Clipboard fragments can include UI-created empty code blocks after a text
     * selection.  Pandoc renders those as blank fenced areas, so drop them once
     * code content has been normalized and before container unwrapping.
     * @param {string} html
     * @returns {string}
     */
    static _RemoveEmptyCodeBlocks(html) {
        prev := ""
        while (html != prev) {
            prev := html
            html := RegExReplace(html, "is)<pre\b[^>]*+>\s*+<code\b[^>]*+>(?:\s|&nbsp;|&#160;)*+</code>\s*+</pre>", "")
            html := RegExReplace(html, "is)<code\b[^>]*+>(?:\s|&nbsp;|&#160;)*+</code>", "")
        }
        return html
    }

    /**
     * Unwraps redundant container elements that wrap canonical `<pre><code>` blocks.
     * Repeats until no further simplification is possible.
     * @param {string} html
     * @returns {string}
     */
    static _UnwrapNestedContainers(html) {
        prev := ""
        while (html != prev) {
            prev := html
            ; Outer <pre class="..."> wrapping an inner <pre><code>.
            html := RegExReplace(html, "is)<pre\b[^>]++>\s*+(<pre\b[^>]*+><code\b[^>]*+>.*?</code></pre>)\s*+</pre>", "$1")
            ; Claude Web: <pre class="code-block__code ..."> directly wrapping <code>.
            ; Strip the outer pre's class so pandoc uses the <code class="language-xxx">
            ; for the language identifier, not the pre's CSS utility class.
            html := RegExReplace(html, "is)<pre\b[^>]*\bcode-block__code\b[^>]*+>\s*+(<code\b[^>]*+>.*?</code>)\s*+</pre>", "<pre>$1</pre>")
            ; Claude Web copy-button overlay: <div class="sticky ..."><div ...></div></div>
            ; Strip it so the remaining structure is a simple two-div wrap around <pre><code>.
            html := RegExReplace(html, "is)<div\b[^>]*\bsticky\b[^>]*+>.*?</div>\s*+</div>", "")
            ; Two nested <div>s wrapping <pre><code>.
            html := RegExReplace(html, "is)<div\b[^>]*+>\s*+<div\b[^>]*+>\s*+(<pre><code\b[^>]*+>.*?</code></pre>)\s*+</div>\s*+</div>", "$1")
            ; Two nested <div>s wrapping an inline <code>.
            html := RegExReplace(html, "is)<div\b[^>]*+>\s*+<div\b[^>]*+>\s*+(<code\b[^>]*+>.*?</code>)\s*+</div>\s*+</div>", "$1")
        }
        return html
    }

    static _HasChatGptCodeContainerShape(html) {
        return RegExMatch(html, "is)^\s*+<pre\b[^>]++>\s*+<pre\b[^>]*+><code\b")
            || RegExMatch(html, "is)^\s*+<pre\b[^>]*\bcode-block__code\b[^>]*+>\s*+<code\b")
            || RegExMatch(html, "is)^\s*+<div\b[^>]*+>\s*+<div\b[^>]*+>\s*+<pre><code\b")
            || RegExMatch(html, "is)^\s*+<div\b[^>]*+>\s*+<div\b[^>]*+>\s*+<code\b")
    }

    /**
     * Finds the inclusive end offset of an HTML element, accounting for nested
     * elements of the same tag name.
     * @param {string} html
     * @param {integer} openPos
     * @param {string} tagName
     * @returns {integer}
     */
    static _FindMatchingElementEnd(html, openPos, tagName) {
        openPat := "is)<" . tagName . "\b[^>]*+>"
        if !RegExMatch(html, openPat, &mOpen, openPos)
            return 0
        if (mOpen.Pos != openPos)
            return 0

        tagPat := "is)</?" . tagName . "\b[^>]*+>"
        depth := 1
        pos := openPos + mOpen.Len
        while RegExMatch(html, tagPat, &mTag, pos) {
            token := mTag[0]
            if (SubStr(token, 2, 1) = "/") {
                depth -= 1
                if (depth = 0)
                    return mTag.Pos + mTag.Len - 1
            } else if !RegExMatch(token, "/\s*>$") {
                depth += 1
            }
            pos := mTag.Pos + mTag.Len
        }
        return 0
    }

    /**
     * Skips ASCII HTML whitespace from the given 1-based position.
     * @param {string} s
     * @param {integer} pos
     * @returns {integer}
     */
    static _SkipHtmlWhitespace(s, pos) {
        while (pos <= StrLen(s)) {
            ch := SubStr(s, pos, 1)
            if (ch != " " && ch != "`t" && ch != "`r" && ch != "`n")
                break
            pos += 1
        }
        return pos
    }

    ; ─────────────────────────────────────────────────────────────────────────
    ; Shared helpers
    ; ─────────────────────────────────────────────────────────────────────────

    /**
     * Decodes the HTML entities most commonly found in clipboard fragments.
     * Decodes &amp; last so that doubly-encoded entities (e.g. &amp;lt;) decode
     * only one level per call, which is the correct HTML behaviour.
     * @param {string} s
     * @returns {string}
     */
    static _DecodeBasicHtmlEntities(s) {
        s := StrReplace(s, "&nbsp;",  Chr(160))
        s := StrReplace(s, "&#160;",  Chr(160))
        s := StrReplace(s, "&quot;",  '"')
        s := StrReplace(s, "&#34;",   '"')
        s := StrReplace(s, "&apos;",  "'")
        s := StrReplace(s, "&#39;",   "'")
        s := StrReplace(s, "&lt;",    "<")
        s := StrReplace(s, "&gt;",    ">")
        s := StrReplace(s, "&amp;",   "&")
        return s
    }
}
