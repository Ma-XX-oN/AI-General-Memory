;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; HtmlNorm - Source detection and HTML normalization for PasteAsMd
;
; Replaces PreprocessHtmlCodeBlocks in PasteAsMd.ahk with a more accurate
; normalizer that handles Codex, Claude Code, Claude Web, and ChatGPT web.
;
; Depends on HtmlParser.ahk for DOM parse artifacts used downstream by PasteAsMd.
;
; FUCKING CLAUDE!!!!  YOU THINK WE DID THAT WORK FOR SHITS AND GIGGLES?!?!?
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

#Include HtmlParser.ahk
/*
 * Moved from HtmlDom.ahk as that was generic for all DOMs and this is specific
 * for chat HTML.  Not sure if this will stay here though.
 * 
 * ## Defined tag names
 *
 * **Root**
 * - `"chat"` - root node; children are `"turn"` nodes.
 *
 * **Turn-level**
 * - `"turn"` - one message turn.
 *   - attr `role` {string} `"user"` or `"ai"`
 *   - children: block nodes
 *
 * **Block-level**
 * - `"text"` - raw HTML fragment passed through to pandoc.
 *   - `text` {string} raw HTML
 * - `"code"` - fenced code block.
 *   - attr `lang` {string} language identifier, or `""` when unknown
 *   - `text` {string} plain-text source code
 * - `"task-list"` - GFM task list.
 *   - children: `"task-item"` nodes
 * - `"task-item"` - single task-list entry.
 *   - attr `checked` {string} `"1"` if checked, `"0"` otherwise
 *   - `text` {string} plain-text item label
 * - `"user-msg"` - user message text extracted before pandoc to preserve
 *   line structure.
 *   - `text` {string} plain text (may contain backtick inline code)
 * - `"thinking"` - Claude thinking block.
 *   - `text` {string} plain text
 * - `"poster"` - speaker label placeholder (injected when SHOW_POSTER is on).
 *   - attr `role` {string} `"user"` or `"ai"`
 */
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
 * - "chatgpt"     no extensionId; HTML fragment contains `data-turn-id=` attribute
 *                 (ChatGPT web - no SourceURL header in its CF_HTML payload)
 * - "unknown"     none of the above
 *
 * @param {string} cfHtml - Full CF_HTML clipboard payload (not just the fragment)
 * @returns {string} Source identifier string
 */
DetectSource(cfHtml) {
    if RegExMatch(cfHtml, "i)extensionId=([^&`r`n]+)", &m) {
        extId := StrLower(m[1])
        if InStr(extId, "openai.chatgpt")
            return "codex"
        if InStr(extId, "anthropic") || InStr(extId, "claude")
            return "claudecode"   ; real Claude Web (browser) never has extensionId
    }
    ; Claude Web (browser): no extensionId in header; detect from HTML content.
    if InStr(cfHtml, "font-claude-response") || InStr(cfHtml, "data-is-streaming") || InStr(cfHtml, "code-block__code")
        return "claudeweb"
    ; ChatGPT web: no extensionId.  Full-turn copies have data-turn-id on <article>;
    ; sub-selection copies omit the article but keep CodeMirror overflow-visible! <pre>.
    if InStr(cfHtml, "data-turn-id=") || InStr(cfHtml, "overflow-visible!")
        return "chatgpt"
    return "unknown"
}

/**
 * Normalizes an HTML fragment from clipboard for downstream pandoc conversion.
 *
 * Populated arrays after `Normalize()` returns:
 *   - `HtmlNorm._thinkingBlocks` - inner texts of thinking blocks (¤THINKING_N¤)
 *   - `HtmlNorm._userMsgBlocks`  - user message raw text (¤USERMSG_N¤)
 *
 * These must be copied into `PasteMd._thinkingBlocks` / `_userMsgBlocks` by
 * the caller before invoking `RestoreThinkingBlocks` / `RestoreUserMsgBlocks`.
 */
class HtmlNorm {
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
     * Parsed DOM nodes for the most recent Normalize() result.
     * This is consumed by PasteAsMd for post-normalization structural edits.
     * @type {Array}
     */
    static _domNodes := []

    /**
     * Normalizes an HTML fragment for pandoc processing.
     *
     * Transforms are applied in order:
     *   1.  Image/SVG handling: drop if no accessible text, else (img: text); leave when showImg
     *   2.  Poster-label placeholder injection (when showPoster)
     *   3.  Diff-block normalization (diffs-container → pre/code language-diff)
     *   4.  Button stripping
     *   5.  ChatGPT code block extraction (pre.overflow-visible! → pre/code)
     *   6.  Task-list checkbox normalization (canonical <input type="checkbox">)
     *   7.  Thinking block extraction (→ ¤THINKING_N¤)
     *   8.  Inline-code span promotion (inline-markdown/font-mono → <code>)
     *   9.  User message extraction (→ ¤USERMSG_N¤)
     *   10. Claude Web language-label div removal
     *   11. Footnote URL stripping (long URLs → #fragment)
     *   12. Residual span tag removal
     *   13. Bare <li> list wrapping in <ol>
     *   14. <code> element normalization (line-break conversion, pre-wrapping)
     *   15. Nested container unwrapping
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
        HtmlNorm._domNodes       := []
        html := htmlFrag

        ; 1..5. Lead + early code/widget cleanup in one DOM parse/serialize cycle:
        ;   - Handle <img>/<svg> replacement when showImg is off.
        ;   - Inject poster-label placeholders when showPoster is on.
        ;   - Convert tool diff containers into canonical language-diff code blocks.
        ;   - Strip UI buttons.
        ;   - ChatGPT: normalize CodeMirror code blocks before any span stripping.
        html := HtmlNorm._NormalizeLeadAndEarlyDom(html, source, showPoster, showImg)

        ; 6..13. Mid + late DOM cleanup in one parse/serialize cycle:
        ;   - Normalize task-list checkboxes.
        ;   - Extract thinking blocks.
        ;   - Promote inline-code spans.
        ;   - Extract whitespace-sensitive user message text.
        ;   - Strip Claude Web language-label divs (font-small + p-3*).
        ;   - Strip long footnote hrefs, keeping only #user-content-...
        ;   - Unwrap <p> inside footnote definition <li id="user-content-fn-*">.
        ;   - Strip residual <span> wrappers while preserving child order/content.
        ;   - Wrap bare top-level <li> siblings in <ol>.
        html := HtmlNorm._NormalizeMidAndLateDom(html)

        ; 14 + 15. Code normalization and nested-container unwrapping in one
        ; DOM pass, while capturing final DOM nodes for downstream consumers.
        html := HtmlNorm._NormalizeCodeUnwrapAndCaptureDom(html)

        return html
    }

    ; ─────────────────────────────────────────────────────────────────────────
    ; Phase methods
    ; ─────────────────────────────────────────────────────────────────────────

    /**
     * Replaces `<img>` and `<svg>` elements according to the showImg flag.
     *
     * When showImg is false:
     *   - No accessible text (alt / title / aria-label / SVG `<title>`): dropped.
     *   - Has accessible text: replaced with `(img: <text>)`.
     *
     * When showImg is true, leaves elements in place for pandoc.
     *
     * DOM parse failures are non-fatal and return the original html unchanged.
     *
     * @param {string} html
     * @param {boolean} showImg
     * @returns {string}
     */
    static _ProcessImgTags(html, showImg) {
        if showImg
            return html
        ; Keep HTML byte-stable when no image-like elements exist.
        if !RegExMatch(html, "i)<(?:img|svg)\b")
            return html
        rootNodes := HtmlNorm._TryParseDomNodes(html)
        wrapped := false
        if (rootNodes.Length = 0) {
            rootNodes := HtmlNorm._TryParseDomNodes("<ul>" . html . "</ul>")
            if (rootNodes.Length = 1 && HtmlNorm._IsTag(rootNodes[1], "ul"))
                wrapped := true
            else
                return html
        }
        nodes := wrapped ? rootNodes[1].children : rootNodes
        nodes := HtmlNorm._ProcessImgTagsDomNodes(nodes)
        return HtmlNorm._SerializeDomNodes(nodes)
    }

    /**
     * Runs shared early DOM stages with one parse/serialize cycle.
     * @param {string} html
     * @param {string} source
     * @param {boolean} showPoster
     * @param {boolean} showImg
     * @returns {string}
     */
    static _NormalizeLeadDom(html, source, showPoster, showImg) {
        needImg := !showImg && RegExMatch(html, "i)<(?:img|svg)\b")
        needPoster := showPoster
        if !(needImg || needPoster)
            return html

        nodes := HtmlNorm._TryParseDomNodes(html)
        if (nodes.Length = 0)
            return html

        if needImg
            nodes := HtmlNorm._ProcessImgTagsDomNodes(nodes)
        if needPoster
            HtmlNorm._InjectPosterPlaceholdersDomNodes(nodes, source)
        return HtmlNorm._SerializeDomNodes(nodes)
    }

    /**
     * Runs stages 3, 4, and 5 in one DOM parse/serialize cycle.
     *
     * - diff widget normalization
     * - button stripping
     * - ChatGPT overflow-visible <pre> normalization
     *
     * @param {string} html
     * @param {string} source
     * @returns {string}
     */
    static _NormalizeDiffButtonCodeDom(html, source) {
        needDiff := RegExMatch(html, "i)<diffs-container\b")
        needButton := RegExMatch(html, "i)</?button\b")
        needChatPre := (source = "chatgpt")
            && RegExMatch(html, "i)<pre\b[^>]*\boverflow-visible\b[^>]*>")
        if !(needDiff || needButton || needChatPre)
            return html

        nodes := HtmlNorm._TryParseDomNodes(html)
        if (nodes.Length = 0)
            return html

        changed := false

        if needDiff {
            lastButton := ""
            nodes := HtmlNorm._NormalizeSimpleDiffBlocksDomNodes(nodes, &lastButton, &changed)
        }

        if needButton {
            btnNodes := []
            HtmlNorm._CollectMatchingNodes(nodes, (n) => HtmlNorm._IsTag(n, "button"), &btnNodes)
            if (btnNodes.Length > 0) {
                nodes := HtmlNorm._RemoveMatchingDomNodes(nodes, (n) => HtmlNorm._IsTag(n, "button"))
                changed := true
            }
        }

        if needChatPre
            nodes := HtmlNorm._NormalizeChatGptCodeBlocksDomNodes(nodes, &changed)

        return changed ? HtmlNorm._SerializeDomNodes(nodes) : html
    }

    /**
     * Runs stages 1 through 5 in one DOM parse/serialize cycle.
     *
     * - image/svg normalization
     * - poster placeholder injection
     * - diff widget normalization
     * - button stripping
     * - ChatGPT overflow-visible <pre> normalization
     *
     * @param {string} html
     * @param {string} source
     * @param {boolean} showPoster
     * @param {boolean} showImg
     * @returns {string}
     */
    static _NormalizeLeadAndEarlyDom(html, source, showPoster, showImg) {
        needImg := !showImg && RegExMatch(html, "i)<(?:img|svg)\b")
        needPoster := showPoster
        needDiff := RegExMatch(html, "i)<diffs-container\b")
        needButton := RegExMatch(html, "i)</?button\b")
        needChatPre := (source = "chatgpt")
            && RegExMatch(html, "i)<pre\b[^>]*\boverflow-visible\b[^>]*>")
        if !(needImg || needPoster || needDiff || needButton || needChatPre)
            return html

        nodes := HtmlNorm._TryParseDomNodes(html)
        if (nodes.Length = 0)
            return html

        changed := false
        if needImg {
            nodes := HtmlNorm._ProcessImgTagsDomNodes(nodes)
            changed := true
        }
        if needPoster {
            HtmlNorm._InjectPosterPlaceholdersDomNodes(nodes, source)
            changed := true
        }
        if needDiff {
            lastButton := ""
            nodes := HtmlNorm._NormalizeSimpleDiffBlocksDomNodes(nodes, &lastButton, &changed)
        }
        if needButton {
            btnNodes := []
            HtmlNorm._CollectMatchingNodes(nodes, (n) => HtmlNorm._IsTag(n, "button"), &btnNodes)
            if (btnNodes.Length > 0) {
                nodes := HtmlNorm._RemoveMatchingDomNodes(nodes, (n) => HtmlNorm._IsTag(n, "button"))
                changed := true
            }
        }
        if needChatPre
            nodes := HtmlNorm._NormalizeChatGptCodeBlocksDomNodes(nodes, &changed)

        return changed ? HtmlNorm._SerializeDomNodes(nodes) : html
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
        nodes := HtmlNorm._TryParseDomNodes(html)
        if (nodes.Length = 0)
            return html
        HtmlNorm._InjectPosterPlaceholdersDomNodes(nodes, source)
        return HtmlNorm._SerializeDomNodes(nodes)
    }

    /**
     * Injects poster placeholders in parsed DOM nodes by source-specific selectors.
     * @param {Array} nodes
     * @param {string} source
     */
    static _InjectPosterPlaceholdersDomNodes(nodes, source) {
        if (source = "claudecode") {
            HtmlNorm._InjectPosterForMatches(nodes, (n) => HtmlNorm._IsTag(n, "div")
                && (HtmlNorm._GetAttrCI(n, "data-testid") = "assistant-message"), "¤POSTER_AI¤")
            HtmlNorm._InjectPosterForMatches(nodes, (n) => HtmlNorm._IsTag(n, "div")
                && HtmlNorm._ClassHasPrefix(n, "message_")
                && HtmlNorm._ClassHasPrefix(n, "userMessageContainer_"), "¤POSTER_User¤")
        } else if (source = "codex") {
            HtmlNorm._InjectPosterForMatches(nodes, (n) => HtmlNorm._IsTag(n, "div")
                && HtmlNorm._ClassHasToken(n, "group") && HtmlNorm._ClassHasToken(n, "min-w-0") && HtmlNorm._ClassHasToken(n, "flex-col"), "¤POSTER_AI¤")
            HtmlNorm._InjectPosterForMatches(nodes, (n) => HtmlNorm._IsTag(n, "div")
                && HtmlNorm._ClassHasToken(n, "flex-col") && HtmlNorm._ClassHasToken(n, "items-end"), "¤POSTER_User¤")
        } else if (source = "claudeweb") {
            HtmlNorm._InjectPosterForMatches(nodes, (n) => HtmlNorm._IsTag(n, "div")
                && (HtmlNorm._HasAttrCI(n, "data-is-streaming") || HtmlNorm._ClassHasToken(n, "font-claude-response")), "¤POSTER_AI¤")
            HtmlNorm._InjectPosterForMatches(nodes, (n) => HtmlNorm._IsTag(n, "div")
                && (HtmlNorm._GetAttrCI(n, "data-testid") = "user-message"), "¤POSTER_User¤")
        } else if (source = "chatgpt") {
            ; Keep legacy behavior: assistant may be injected by either matcher.
            HtmlNorm._InjectPosterForMatches(nodes, (n) => HtmlNorm._IsTag(n, "article")
                && (HtmlNorm._GetAttrCI(n, "data-turn") = "assistant"), "¤POSTER_AI¤")
            HtmlNorm._InjectPosterForMatches(nodes, (n) => HtmlNorm._IsTag(n, "article")
                && HtmlNorm._StartsWithCI(HtmlNorm._GetAttrCI(n, "data-turn-id"), "request-WEB:"), "¤POSTER_AI¤")
            HtmlNorm._InjectPosterForMatches(nodes, (n) => HtmlNorm._IsTag(n, "article")
                && (HtmlNorm._GetAttrCI(n, "data-turn") = "user"), "¤POSTER_User¤")
        }
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
        if !RegExMatch(html, "i)<diffs-container\b")
            return html

        nodes := HtmlNorm._TryParseDomNodes(html)
        if (nodes.Length = 0)
            return html

        changed := false
        lastButton := ""
        nodes := HtmlNorm._NormalizeSimpleDiffBlocksDomNodes(nodes, &lastButton, &changed)
        return changed ? HtmlNorm._SerializeDomNodes(nodes) : html
    }

    /**
     * Recursive worker entry for simple diff-block normalization.
     * Tracks last non-empty button label seen in document order.
     * @param {Array} nodes
     * @param {string} lastButton
     * @param {boolean} changed
     * @returns {Array}
     */
    static _NormalizeSimpleDiffBlocksDomNodes(nodes, &lastButton, &changed) {
        out := []
        for node in nodes {
            converted := HtmlNorm._NormalizeSimpleDiffBlocksDomNode(node, &lastButton, &changed)
            for item in converted
                out.Push(item)
        }
        return out
    }

    /**
     * Node-level worker for _NormalizeSimpleDiffBlocksDomNodes.
     * @param {DomNode} node
     * @param {string} lastButton
     * @param {boolean} changed
     * @returns {Array}
     */
    static _NormalizeSimpleDiffBlocksDomNode(node, &lastButton, &changed) {
        if HtmlNorm._IsTag(node, "button") {
            btnText := HtmlNorm._DecodeBasicHtmlEntities(HtmlNorm._NodeTextRecursive(node))
            btnText := Trim(btnText, " `t`r`n")
            if (btnText != "")
                lastButton := btnText
        }

        if HtmlNorm._IsTag(node, "diffs-container") {
            rows := []
            HtmlNorm._CollectMatchingNodes(node.children
                , (n) => HtmlNorm._IsTag(n, "div")
                    && HtmlNorm._HasAttrCI(n, "data-line-type")
                , &rows)

            diffLines := []
            for row in rows {
                lineType := StrLower(HtmlNorm._GetAttrCI(row, "data-line-type"))
                lineText := HtmlNorm._DecodeBasicHtmlEntities(HtmlNorm._NodeTextRecursive(row))
                lineText := StrReplace(lineText, "`r", "")
                lineText := Trim(lineText, "`n")
                prefix := " "
                if InStr(lineType, "deletion")
                    prefix := "-"
                else if InStr(lineType, "addition")
                    prefix := "+"
                diffLines.Push(prefix . lineText)
            }

            if (diffLines.Length = 0)
                return [node]

            diffText := ""
            for line in diffLines
                diffText .= (diffText = "" ? "" : "`n") . line
            diffText := StrReplace(diffText, "&", "&amp;")
            diffText := StrReplace(diffText, "<", "&lt;")
            diffText := StrReplace(diffText, ">", "&gt;")

            outNodes := []
            if (lastButton != "") {
                fileNameEsc := StrReplace(lastButton, "&", "&amp;")
                fileNameEsc := StrReplace(fileNameEsc, "<", "&lt;")
                fileNameEsc := StrReplace(fileNameEsc, ">", "&gt;")
                p := DomNode("p")
                c := DomNode("code")
                c.Add(DomNode("text", "", fileNameEsc))
                p.Add(c)
                outNodes.Push(p)
            }

            pre := DomNode("pre")
            code := DomNode("code", Map("class", "language-diff"))
            code.Add(DomNode("text", "", diffText))
            pre.Add(code)
            outNodes.Push(pre)
            changed := true
            return outNodes
        }

        if (node.children.Length > 0)
            node.children := HtmlNorm._NormalizeSimpleDiffBlocksDomNodes(node.children, &lastButton, &changed)
        return [node]
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
        if !RegExMatch(html, "i)<pre\b[^>]*\boverflow-visible\b[^>]*>")
            return html

        nodes := HtmlNorm._TryParseDomNodes(html)
        if (nodes.Length = 0)
            return html

        changed := false
        nodes := HtmlNorm._NormalizeChatGptCodeBlocksDomNodes(nodes, &changed)
        return changed ? HtmlNorm._SerializeDomNodes(nodes) : html
    }

    /**
     * Recursive worker entry for ChatGPT CodeMirror <pre> normalization.
     * @param {Array} nodes
     * @param {boolean} changed
     * @returns {Array}
     */
    static _NormalizeChatGptCodeBlocksDomNodes(nodes, &changed) {
        out := []
        for node in nodes {
            converted := HtmlNorm._NormalizeChatGptCodeBlocksDomNode(node, &changed)
            for item in converted
                out.Push(item)
        }
        return out
    }

    /**
     * Node-level worker for _NormalizeChatGptCodeBlocksDomNodes.
     * Converts <pre class="... overflow-visible ...">...</pre> to
     * <pre><code>escaped-text</code></pre>.
     * @param {DomNode} node
     * @param {boolean} changed
     * @returns {Array}
     */
    static _NormalizeChatGptCodeBlocksDomNode(node, &changed) {
        if HtmlNorm._IsTag(node, "pre") && InStr(HtmlNorm._GetAttrCI(node, "class"), "overflow-visible") {
            codeText := HtmlNorm._NodeTextWithBr(node)
            codeText := StrReplace(codeText, "`r", "")
            codeText := Trim(codeText, " `t`n")
            if (codeText = "")
                return [node]
            codeText := HtmlNorm._DecodeBasicHtmlEntities(codeText)
            codeText := StrReplace(codeText, "&", "&amp;")
            codeText := StrReplace(codeText, "<", "&lt;")
            codeText := StrReplace(codeText, ">", "&gt;")
            preOut := DomNode("pre")
            codeOut := DomNode("code")
            codeOut.Add(DomNode("text", "", codeText))
            preOut.Add(codeOut)
            changed := true
            return [preOut]
        }

        if (node.children.Length > 0) {
            newChildren := []
            for child in node.children {
                converted := HtmlNorm._NormalizeChatGptCodeBlocksDomNode(child, &changed)
                for item in converted
                    newChildren.Push(item)
            }
            node.children := newChildren
        }
        return [node]
    }

    /**
     * Runs stages 6, 7, and 8 in one DOM parse/serialize cycle.
     *
     * - Task-list checkbox normalization
     * - Thinking block extraction
     * - Inline-code span promotion
     *
     * @param {string} html
     * @returns {string}
     */
    static _NormalizeTaskThinkingInlineDom(html) {
        if !RegExMatch(
            html,
            "i)(<li\b|<details\b[^>]*+\bclass=`"[^`"]*+\bthinking\b[^`"]*+`"|<span\b[^>]*+\bclass=`"[^`"]*+\b(?:inline-markdown|font-mono)\b[^`"]*+`")"
        )
            return html

        nodes := HtmlNorm._TryParseDomNodes(html)
        if (nodes.Length = 0)
            return html

        changed := false

        if (HtmlNorm._NormalizeTaskListItemsDomNodes(nodes))
            changed := true

        thinkCount := HtmlNorm._thinkingBlocks.Length
        nodes := HtmlNorm._ExtractThinkingBlocksDomNodes(nodes)
        if (HtmlNorm._thinkingBlocks.Length != thinkCount)
            changed := true

        if (HtmlNorm._PromoteInlineCodeSpansDomNodes(nodes))
            changed := true

        return changed ? HtmlNorm._SerializeDomNodes(nodes) : html
    }

    /**
     * Runs stages 6 through 13 in one DOM parse/serialize cycle.
     *
     * Operation order is preserved:
     * 6) task list normalize
     * 7) thinking extraction
     * 8) inline code span promotion
     * 9) user message extraction
     * 10..13) late cleanup + bare-li wrapping
     *
     * @param {string} html
     * @returns {string}
     */
    static _NormalizeMidAndLateDom(html) {
        needMid := RegExMatch(
            html,
            "i)(<li\b|<details\b[^>]*+\bclass=`"[^`"]*+\bthinking\b[^`"]*+`"|<span\b[^>]*+\bclass=`"[^`"]*+\b(?:inline-markdown|font-mono)\b[^`"]*+`")"
        )
        needUser := RegExMatch(html, "i)<(?:p|div)\b[^>]*\b(?:text-size-chat|content_xGDvVg|whitespace-pre-wrap)\b")
        needLate := RegExMatch(html, "i)(<li\b|<div\b[^>]*\bclass=`"[^`"]*\bfont-small\b[^`"]*\bp-3[^`"]*`"|href=`"[^`"]*#user-content-|<li\b[^>]*\bid=`"user-content-fn-|</?span\b)")
        if !(needMid || needUser || needLate)
            return html

        nodes := HtmlNorm._TryParseDomNodes(html)
        if (nodes.Length = 0)
            return html

        changed := false
        if needMid {
            if (HtmlNorm._NormalizeTaskListItemsDomNodes(nodes))
                changed := true
            thinkCount := HtmlNorm._thinkingBlocks.Length
            nodes := HtmlNorm._ExtractThinkingBlocksDomNodes(nodes)
            if (HtmlNorm._thinkingBlocks.Length != thinkCount)
                changed := true
            if (HtmlNorm._PromoteInlineCodeSpansDomNodes(nodes))
                changed := true
        }

        if needUser {
            nodes := HtmlNorm._ExtractUserMessagesInlineContainerDomNodes(nodes, &changed)
            nodes := HtmlNorm._ExtractUserMessagesFullNodeDomNodes(nodes, &changed)
        }

        if needLate {
            if (HtmlNorm._NormalizeFootnoteAndSpanDomNodes(&nodes))
                changed := true
            nodes := HtmlNorm._WrapBareTopLevelLiDomNodes(nodes, &wrapped)
            if wrapped
                changed := true
        }

        return changed ? HtmlNorm._SerializeDomNodes(nodes) : html
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
        if !RegExMatch(html, "i)<li\b")
            return html

        nodes := HtmlNorm._TryParseDomNodes(html)
        if (nodes.Length = 0)
            return html

        if !HtmlNorm._NormalizeTaskListItemsDomNodes(nodes)
            return html

        return HtmlNorm._SerializeDomNodes(nodes)
    }

    /**
     * Normalizes task-list `<li>` nodes in parsed DOM.
     * @param {Array} nodes
     * @returns {boolean} True when any task-list item was rewritten
     */
    static _NormalizeTaskListItemsDomNodes(nodes) {
        taskLis := []
        HtmlNorm._CollectMatchingNodes(nodes
            , (n) => HtmlNorm._IsTag(n, "li")
                && (HtmlNorm._ClassHasToken(n, "task-list-item")
                    || HtmlNorm._ClassHasPrefix(n, "todoItem_"))
            , &taskLis)
        if (taskLis.Length = 0)
            return false

        changed := false
        for li in taskLis {
            checkbox := li.FindFirst((n) => HtmlNorm._IsTag(n, "input")
                && (StrLower(HtmlNorm._GetAttrCI(n, "type")) = "checkbox"))
            if !IsObject(checkbox)
                continue

            checked := HtmlNorm._HasAttrCI(checkbox, "checked")
            if !checked {
                if HtmlNorm._ClassHasPrefix(li, "completed_")
                    checked := true
                else if HtmlNorm._SubtreeHasLineThroughStyle(li)
                    checked := true
            }

            text := HtmlNorm._CollectTextAfterFirstCheckbox(li)
            text := HtmlNorm._DecodeBasicHtmlEntities(text)
            text := Trim(text, " `t`r`n" . Chr(160))
            text := StrReplace(text, "&", "&amp;")
            text := StrReplace(text, "<", "&lt;")
            text := StrReplace(text, ">", "&gt;")

            inputHtml := checked
                ? '<input type="checkbox" disabled checked />'
                : '<input type="checkbox" disabled />'

            newChildren := [DomNode("text", "", inputHtml)]
            if (text != "")
                newChildren.Push(DomNode("text", "", " " . text))

            li.attrs := Map()
            li.children := newChildren
            changed := true
        }
        return changed
    }

    /**
     * Extracts `<details class="thinking">` blocks into ¤THINKING_N¤ placeholders.
     * The inner text (summary removed, tags stripped) is stored in `_thinkingBlocks`.
     * `PasteMd.RestoreThinkingBlocks()` restores them after pandoc.
     * @param {string} html
     * @returns {string}
     */
    static _ExtractThinkingBlocks(html) {
        if !RegExMatch(html, "i)<details\b[^>]*\bclass=`"[^`"]*\bthinking\b[^`"]*`"")
            return html

        nodes := HtmlNorm._TryParseDomNodes(html)
        if (nodes.Length = 0)
            return html

        nodes := HtmlNorm._ExtractThinkingBlocksDomNodes(nodes)
        return HtmlNorm._SerializeDomNodes(nodes)
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
     * - Claude Web: `<p class="whitespace-pre-wrap break-words">` - plain text with
     *   embedded literal newlines; `<br>` tags possible.
     * - ChatGPT: `<div class="whitespace-pre-wrap">` (exact sole class value) -
     *   plain text with embedded literal newlines.
     *
     * `PasteMd.RestoreUserMsgBlocks()` restores the plain text after pandoc.
     * @param {string} html
     * @returns {string}
     */
    static _ExtractUserMessages(html) {
        if !RegExMatch(html, "i)<(?:p|div)\b[^>]*\b(?:text-size-chat|content_xGDvVg|whitespace-pre-wrap)\b")
            return html

        nodes := HtmlNorm._TryParseDomNodes(html)
        if (nodes.Length = 0)
            return html

        changed := false

        ; Codex + Claude Code inline-container user messages:
        ; - Codex: keep outer div, replace children with placeholder.
        ; - Claude Code: replace first leading <span> with placeholder.
        nodes := HtmlNorm._ExtractUserMessagesInlineContainerDomNodes(nodes, &changed)

        ; Claude Web + ChatGPT full-node user messages:
        ; - <p class="whitespace-pre-wrap break-words">...</p>
        ; - <div class="whitespace-pre-wrap">...</div> (exact class match)
        ; Replace whole nodes with placeholder <p>¤USERMSG_N¤</p>.
        nodes := HtmlNorm._ExtractUserMessagesFullNodeDomNodes(nodes, &changed)

        return changed ? HtmlNorm._SerializeDomNodes(nodes) : html
    }

    /**
     * Runs stages 9/10/11/11b/12/13 in one DOM parse/serialize cycle.
     *
     * - user message placeholder extraction
     * - Claude Web language-label div stripping
     * - footnote href normalization
     * - footnote <li><p>...</p></li> unwrap
     * - residual span unwrap
     * - bare top-level <li> wrapping
     *
     * @param {string} html
     * @returns {string}
     */
    static _NormalizeUserMessagesAndLateCleanupDom(html) {
        needUser := RegExMatch(html, "i)<(?:p|div)\b[^>]*\b(?:text-size-chat|content_xGDvVg|whitespace-pre-wrap)\b")
        needLate := RegExMatch(html, "i)(<li\b|<div\b[^>]*\bclass=`"[^`"]*\bfont-small\b[^`"]*\bp-3[^`"]*`"|href=`"[^`"]*#user-content-|<li\b[^>]*\bid=`"user-content-fn-|</?span\b)")
        if !(needUser || needLate)
            return html

        nodes := HtmlNorm._TryParseDomNodes(html)
        if (nodes.Length = 0)
            return html

        changed := false
        if needUser {
            nodes := HtmlNorm._ExtractUserMessagesInlineContainerDomNodes(nodes, &changed)
            nodes := HtmlNorm._ExtractUserMessagesFullNodeDomNodes(nodes, &changed)
        }
        if needLate {
            if (HtmlNorm._NormalizeFootnoteAndSpanDomNodes(&nodes))
                changed := true
            nodes := HtmlNorm._WrapBareTopLevelLiDomNodes(nodes, &wrapped)
            if wrapped
                changed := true
        }

        return changed ? HtmlNorm._SerializeDomNodes(nodes) : html
    }

    /**
     * Extracts user message text from inline-container variants (Codex / Claude Code)
     * using DOM traversal while preserving source-specific replacement shape.
     *
     * @param {string} html
     * @returns {string}
     */
    static _ExtractUserMessagesInlineContainerDom(html) {
        if !RegExMatch(html, "i)<div\b[^>]*\b(?:text-size-chat|content_xGDvVg)\b")
            return html

        nodes := HtmlNorm._TryParseDomNodes(html)
        if (nodes.Length = 0)
            return html

        changed := false
        nodes := HtmlNorm._ExtractUserMessagesInlineContainerDomNodes(nodes, &changed)
        return changed ? HtmlNorm._SerializeDomNodes(nodes) : html
    }

    /**
     * Recursive worker entry for inline-container user message extraction.
     * @param {Array} nodes
     * @param {boolean} changed
     * @returns {Array}
     */
    static _ExtractUserMessagesInlineContainerDomNodes(nodes, &changed) {
        out := []
        for node in nodes {
            converted := HtmlNorm._ExtractUserMessagesInlineContainerDomNode(node, &changed)
            for item in converted
                out.Push(item)
        }
        return out
    }

    /**
     * Node-level worker for inline-container user message extraction.
     * @param {DomNode} node
     * @param {boolean} changed
     * @returns {Array}
     */
    static _ExtractUserMessagesInlineContainerDomNode(node, &changed) {
        ; Codex: <div class="text-size-chat whitespace-pre-wrap">...</div>
        if HtmlNorm._IsTag(node, "div")
            && HtmlNorm._ClassHasToken(node, "text-size-chat")
            && HtmlNorm._ClassHasToken(node, "whitespace-pre-wrap") {
            rawContent := HtmlNorm._CodexUserMsgRawText(node)
            rawContent := HtmlNorm._DecodeBasicHtmlEntities(rawContent)
            rawContent := StrReplace(rawContent, "`r", "")
            rawContent := Trim(rawContent, "`n")
            HtmlNorm._userMsgBlocks.Push(rawContent)
            node.children := [HtmlNorm._MakeUserMsgPlaceholderParagraph(HtmlNorm._userMsgBlocks.Length)]
            changed := true
            return [node]
        }

        ; Claude Code: <div class="content_xGDvVg"><span>text</span>...</div>
        if HtmlNorm._IsTag(node, "div") && HtmlNorm._ClassHasPrefix(node, "content_xGDvVg") {
            first := HtmlNorm._FirstNonWhitespaceChild(node)
            if IsObject(first) && HtmlNorm._IsTag(first, "span") {
                rawText := HtmlNorm._DecodeBasicHtmlEntities(HtmlNorm._NodeTextRecursive(first))
                rawText := StrReplace(rawText, "`r", "")
                HtmlNorm._userMsgBlocks.Push(rawText)
                placeholder := HtmlNorm._MakeUserMsgPlaceholderParagraph(HtmlNorm._userMsgBlocks.Length)

                newChildren := [placeholder]
                for child in node.children {
                    if (ObjPtr(child) = ObjPtr(first))
                        continue
                    ; Match prior regex behavior: drop leading whitespace before first span.
                    if (newChildren.Length = 1 && HtmlNorm._IsWhitespaceTextNode(child))
                        continue
                    newChildren.Push(child)
                }
                node.children := newChildren
                changed := true
                return [node]
            }
        }

        if (node.children.Length > 0) {
            newChildren := []
            for child in node.children {
                converted := HtmlNorm._ExtractUserMessagesInlineContainerDomNode(child, &changed)
                for item in converted
                    newChildren.Push(item)
            }
            node.children := newChildren
        }
        return [node]
    }

    /**
     * Builds raw user-message text for Codex containers.
     * - wraps <code class="font-mono">...</code> as ``...``
     * - strips all other tags while preserving text order
     * @param {DomNode} node
     * @returns {string}
     */
    static _CodexUserMsgRawText(node) {
        if (node.tag = "text")
            return node.text
        if HtmlNorm._IsTag(node, "code") && HtmlNorm._ClassHasToken(node, "font-mono")
            return "``" . HtmlNorm._NodeTextRecursive(node) . "``"
        out := ""
        for child in node.children
            out .= HtmlNorm._CodexUserMsgRawText(child)
        return out
    }

    /**
     * Extracts and replaces full-node user message containers (Claude Web /
     * ChatGPT) via DOM traversal.
     *
     * Targets:
     * - <p class="whitespace-pre-wrap break-words">...</p>
     * - <div class="whitespace-pre-wrap">...</div>
     *
     * @param {string} html
     * @returns {string}
     */
    static _ExtractUserMessagesFullNodeDom(html) {
        if !RegExMatch(html, "i)<(?:p|div)\b[^>]*\bclass=`"(?:whitespace-pre-wrap break-words|whitespace-pre-wrap)`"")
            return html

        nodes := HtmlNorm._TryParseDomNodes(html)
        if (nodes.Length = 0)
            return html

        changed := false
        nodes := HtmlNorm._ExtractUserMessagesFullNodeDomNodes(nodes, &changed)
        return changed ? HtmlNorm._SerializeDomNodes(nodes) : html
    }

    /**
     * Recursive worker entry for full-node user message extraction.
     * @param {Array} nodes
     * @param {boolean} changed
     * @returns {Array}
     */
    static _ExtractUserMessagesFullNodeDomNodes(nodes, &changed) {
        out := []
        for node in nodes {
            converted := HtmlNorm._ExtractUserMessagesFullNodeDomNode(node, &changed)
            for item in converted
                out.Push(item)
        }
        return out
    }

    /**
     * Node-level worker for full-node user message extraction.
     * @param {DomNode} node
     * @param {boolean} changed
     * @returns {Array}
     */
    static _ExtractUserMessagesFullNodeDomNode(node, &changed) {
        if HtmlNorm._IsFullNodeUserMsgTarget(node) {
            rawContent := HtmlNorm._NodeTextWithBr(node)
            rawContent := HtmlNorm._DecodeBasicHtmlEntities(rawContent)
            rawContent := StrReplace(rawContent, "`r", "")
            rawContent := Trim(rawContent, "`n")
            HtmlNorm._userMsgBlocks.Push(rawContent)
            marker := "¤USERMSG_" . HtmlNorm._userMsgBlocks.Length . "¤"
            p := DomNode("p")
            p.Add(DomNode("text", "", marker))
            changed := true
            return [p]
        }

        if (node.children.Length > 0) {
            newChildren := []
            for child in node.children {
                converted := HtmlNorm._ExtractUserMessagesFullNodeDomNode(child, &changed)
                for item in converted
                    newChildren.Push(item)
            }
            node.children := newChildren
        }
        return [node]
    }

    /**
     * True when node is a full-node user message container we replace directly.
     * @param {DomNode} node
     * @returns {boolean}
     */
    static _IsFullNodeUserMsgTarget(node) {
        if HtmlNorm._IsTag(node, "p")
            return HtmlNorm._GetAttrCI(node, "class") = "whitespace-pre-wrap break-words"
        if HtmlNorm._IsTag(node, "div")
            return HtmlNorm._GetAttrCI(node, "class") = "whitespace-pre-wrap"
        return false
    }

    /**
     * Returns first non-whitespace direct child, or "" if none.
     * @param {DomNode} node
     * @returns {DomNode|string}
     */
    static _FirstNonWhitespaceChild(node) {
        for child in node.children {
            if !HtmlNorm._IsWhitespaceTextNode(child)
                return child
        }
        return ""
    }

    /**
     * Returns direct children excluding whitespace-only text nodes.
     * @param {DomNode} node
     * @returns {Array}
     */
    static _MeaningfulChildren(node) {
        out := []
        for child in node.children
            if !HtmlNorm._IsWhitespaceTextNode(child)
                out.Push(child)
        return out
    }

    /**
     * Creates <p>¤USERMSG_N¤</p> placeholder node.
     * @param {integer} idx
     * @returns {DomNode}
     */
    static _MakeUserMsgPlaceholderParagraph(idx) {
        p := DomNode("p")
        p.Add(DomNode("text", "", "¤USERMSG_" . idx . "¤"))
        return p
    }

    /**
     * Collects visible text from a subtree, converting <br> tags to newlines.
     * @param {DomNode} node
     * @returns {string}
     */
    static _NodeTextWithBr(node) {
        if (node.tag = "text")
            return node.text
        if HtmlNorm._IsTag(node, "br")
            return "`n"
        out := ""
        for child in node.children
            out .= HtmlNorm._NodeTextWithBr(child)
        return out
    }

    /**
     * Removes all nodes with the given tag name from the DOM tree.
     *
     * @param {string} html
     * @param {string} tagName
     * @returns {string}
     */
    static _StripTagDom(html, tagName) {
        if !RegExMatch(html, "i)</?" . tagName . "\b")
            return html

        nodes := HtmlNorm._TryParseDomNodes(html)
        if (nodes.Length = 0)
            return html

        matches := []
        HtmlNorm._CollectMatchingNodes(nodes, (n) => HtmlNorm._IsTag(n, tagName), &matches)
        if (matches.Length = 0)
            return html

        nodes := HtmlNorm._RemoveMatchingDomNodes(nodes, (n) => HtmlNorm._IsTag(n, tagName))
        return HtmlNorm._SerializeDomNodes(nodes)
    }

    /**
     * Runs stages 10/11/11b/12/13 in one DOM parse/serialize cycle.
     * @param {string} html
     * @returns {string}
     */
    static _NormalizeLateCleanupAndListWrapDom(html) {
        if !RegExMatch(html, "i)(<li\b|<div\b[^>]*\bclass=`"[^`"]*\bfont-small\b[^`"]*\bp-3[^`"]*`"|href=`"[^`"]*#user-content-|<li\b[^>]*\bid=`"user-content-fn-|</?span\b)")
            return html

        nodes := HtmlNorm._TryParseDomNodes(html)
        if (nodes.Length = 0)
            return html

        changed := false
        if (HtmlNorm._NormalizeFootnoteAndSpanDomNodes(&nodes))
            changed := true
        nodes := HtmlNorm._WrapBareTopLevelLiDomNodes(nodes, &wrapped)
        if wrapped
            changed := true

        return changed ? HtmlNorm._SerializeDomNodes(nodes) : html
    }

    /**
     * Wraps bare top-level <li> siblings in an <ol> container.
     *
     * Mirrors the prior regex behavior:
     * - allows whitespace text nodes between/around top-level <li> nodes
     * - ignores trailing top-level <br> and whitespace-only text nodes
     * - does nothing when any non-<li> meaningful top-level node exists
     *
     * @param {string} html
     * @returns {string}
     */
    static _WrapBareTopLevelLiDom(html) {
        if !RegExMatch(html, "i)<li\b")
            return html

        nodes := HtmlNorm._TryParseDomNodes(html)
        if (nodes.Length = 0)
            return html

        nodes := HtmlNorm._WrapBareTopLevelLiDomNodes(nodes, &wrapped)
        if !wrapped
            return html
        return HtmlNorm._SerializeDomNodes(nodes)
    }

    /**
     * Wraps bare top-level <li> siblings in parsed DOM nodes.
     *
     * Matches legacy behavior without mutating input when wrapping does not apply.
     *
     * @param {Array} nodes
     * @param {boolean} changed
     * @returns {Array}
     */
    static _WrapBareTopLevelLiDomNodes(nodes, &changed := false) {
        changed := false
        if (nodes.Length = 0)
            return nodes

        ; Ignore trailing <br> and trailing whitespace text nodes for matching.
        endIdx := nodes.Length
        while (endIdx >= 1) {
            tail := nodes[endIdx]
            if (HtmlNorm._IsTag(tail, "br") || HtmlNorm._IsWhitespaceTextNode(tail))
                endIdx -= 1
            else
                break
        }
        if (endIdx < 1)
            return nodes

        liNodes := []
        Loop endIdx {
            node := nodes[A_Index]
            if HtmlNorm._IsWhitespaceTextNode(node)
                continue
            if !HtmlNorm._IsTag(node, "li")
                return nodes
            liNodes.Push(node)
        }
        if (liNodes.Length = 0)
            return nodes

        wrapper := DomNode("ol")
        for li in liNodes
            wrapper.Add(li)
        changed := true
        return [wrapper]
    }

    /**
     * Promotes styled inline-code spans to semantic <code> tags.
     *
     * Converts:
     *   <span class="... inline-markdown ...">...</span>
     *   <span class="... font-mono ...">...</span>
     * to:
     *   <code>...</code>
     *
     * All attributes are dropped, while child content/order is preserved.
     *
     * @param {string} html
     * @returns {string}
     */
    static _PromoteInlineCodeSpansDom(html) {
        if !RegExMatch(html, "i)<span\b[^>]*\bclass=`"[^`"]*\b(?:inline-markdown|font-mono)\b[^`"]*`"")
            return html

        nodes := HtmlNorm._TryParseDomNodes(html)
        if (nodes.Length = 0)
            return html

        if !HtmlNorm._PromoteInlineCodeSpansDomNodes(nodes)
            return html

        return HtmlNorm._SerializeDomNodes(nodes)
    }

    /**
     * Promotes inline-code span nodes to semantic `<code>` in parsed DOM.
     * @param {Array} nodes
     * @returns {boolean} True when any span was promoted
     */
    static _PromoteInlineCodeSpansDomNodes(nodes) {
        matches := []
        HtmlNorm._CollectMatchingNodes(nodes
            , (n) => HtmlNorm._IsTag(n, "span")
                && (HtmlNorm._ClassHasToken(n, "inline-markdown")
                    || HtmlNorm._ClassHasToken(n, "font-mono"))
            , &matches)
        if (matches.Length = 0)
            return false

        for node in matches {
            node.tag := "code"
            node.attrs := Map()
        }
        return true
    }

    /**
     * Runs stages 14 and 15 in one DOM parse/serialize cycle.
     *
     * - Normalize <code> elements
     * - Unwrap nested containers that obscure code blocks
     *
     * @param {string} html
     * @returns {string}
     */
    static _NormalizeCodeAndUnwrapDom(html) {
        nodes := HtmlNorm._TryParseDomNodes(html)
        if (nodes.Length = 0)
            return html

        hadCode := RegExMatch(html, "i)<code\b")
        if hadCode
            nodes := HtmlNorm._NormalizeCodeElementsDomNodes(nodes, false)

        changedAny := false
        Loop 10 {
            changed := false
            nodes := HtmlNorm._UnwrapNestedContainersDomNodes(nodes, &changed)
            if !changed
                break
            changedAny := true
        }

        if (hadCode || changedAny)
            return HtmlNorm._SerializeDomNodes(nodes)
        return html
    }

    /**
     * Runs stages 14 and 15 and captures final parsed DOM for callers that need
     * both canonical HTML and a reusable DOM snapshot.
     *
     * @param {string} html
     * @returns {string}
     */
    static _NormalizeCodeUnwrapAndCaptureDom(html) {
        nodes := HtmlNorm._TryParseDomNodes(html)
        if (nodes.Length = 0) {
            HtmlNorm._domNodes := []
            return html
        }

        hadCode := RegExMatch(html, "i)<code\b")
        if hadCode
            nodes := HtmlNorm._NormalizeCodeElementsDomNodes(nodes, false)

        changedAny := false
        Loop 10 {
            changed := false
            nodes := HtmlNorm._UnwrapNestedContainersDomNodes(nodes, &changed)
            if !changed
                break
            changedAny := true
        }

        HtmlNorm._domNodes := nodes
        if (hadCode || changedAny)
            return HtmlNorm._SerializeDomNodes(nodes)
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
        if !RegExMatch(html, "i)<code\b")
            return html

        nodes := HtmlNorm._TryParseDomNodes(html)
        if (nodes.Length = 0)
            return html

        nodes := HtmlNorm._NormalizeCodeElementsDomNodes(nodes, false)
        return HtmlNorm._SerializeDomNodes(nodes)
    }

    /**
     * Recursively normalizes <code> nodes in parsed DOM.
     * @param {Array} nodes
     * @param {boolean} insidePre
     * @returns {Array}
     */
    static _NormalizeCodeElementsDomNodes(nodes, insidePre) {
        out := []
        for node in nodes {
            converted := HtmlNorm._NormalizeCodeElementsDomNode(node, insidePre)
            for item in converted
                out.Push(item)
        }
        return out
    }

    /**
     * Node-level worker for _NormalizeCodeElementsDomNodes.
     * @param {DomNode} node
     * @param {boolean} insidePre
     * @returns {Array}
     */
    static _NormalizeCodeElementsDomNode(node, insidePre) {
        if HtmlNorm._IsTag(node, "code") {
            content := HtmlNorm._CodeNodeNormalizedText(node)
            if InStr(content, "`n") {
                content := HtmlNorm._DecodeBasicHtmlEntities(content)
                codeOut := DomNode("code")
                lang := HtmlNorm._CodeNodeLanguage(node)
                if (lang != "")
                    codeOut.attrs["class"] := "language-" . lang
                codeOut.Add(DomNode("text", "", content))
                if insidePre
                    return [codeOut]
                preOut := DomNode("pre")
                preOut.Add(codeOut)
                return [preOut]
            }
            ; Single-line: keep inline <code> and existing attrs.
            node.children := [DomNode("text", "", content)]
            return [node]
        }

        if (node.children.Length > 0) {
            childInsidePre := insidePre || HtmlNorm._IsTag(node, "pre")
            node.children := HtmlNorm._NormalizeCodeElementsDomNodes(node.children, childInsidePre)
        }
        return [node]
    }

    /**
     * Produces normalized text content for one <code> node.
     * Converts <br> and </div><div> boundaries to newlines, strips tags.
     * @param {DomNode} codeNode
     * @returns {string}
     */
    static _CodeNodeNormalizedText(codeNode) {
        out := HtmlNorm._CodeChildrenToText(codeNode.children)
        out := StrReplace(out, "`r", "")
        return out
    }

    /**
     * Converts child nodes to code text, preserving code-line boundaries:
     * - <br> => newline
     * - adjacent sibling <div> blocks => newline between blocks
     * @param {Array} children
     * @returns {string}
     */
    static _CodeChildrenToText(children) {
        out := ""
        prevWasDiv := false
        for child in children {
            if HtmlNorm._IsTag(child, "br") {
                out .= "`n"
                prevWasDiv := false
                continue
            }
            isDiv := HtmlNorm._IsTag(child, "div")
            if (isDiv && prevWasDiv)
                out .= "`n"
            out .= HtmlNorm._CodeNodeToText(child)
            prevWasDiv := isDiv
        }
        return out
    }

    /**
     * Recursive worker for _CodeChildrenToText.
     * @param {DomNode} node
     * @returns {string}
     */
    static _CodeNodeToText(node) {
        if (node.tag = "text")
            return node.text
        if HtmlNorm._IsTag(node, "br")
            return "`n"
        return HtmlNorm._CodeChildrenToText(node.children)
    }

    /**
     * Extracts language id from class="language-xxx" on a <code> node.
     * @param {DomNode} codeNode
     * @returns {string}
     */
    static _CodeNodeLanguage(codeNode) {
        classAttr := HtmlNorm._GetAttrCI(codeNode, "class")
        for token in StrSplit(classAttr, " ") {
            t := Trim(token, " `t`r`n")
            if (t = "")
                continue
            if HtmlNorm._StartsWithCI(t, "language-")
                return SubStr(t, StrLen("language-") + 1)
        }
        return ""
    }

    /**
     * Unwraps redundant container elements that wrap canonical `<pre><code>` blocks.
     * Repeats until no further simplification is possible.
     * @param {string} html
     * @returns {string}
     */
    static _UnwrapNestedContainers(html) {
        return HtmlNorm._UnwrapNestedContainersDom(html)
    }

    /**
     * DOM-first container simplifier for code-block wrapper patterns.
     * @param {string} html
     * @returns {string}
     */
    static _UnwrapNestedContainersDom(html) {
        nodes := HtmlNorm._TryParseDomNodes(html)
        if (nodes.Length = 0)
            return html

        changedAny := false
        Loop 10 {
            changed := false
            nodes := HtmlNorm._UnwrapNestedContainersDomNodes(nodes, &changed)
            if !changed
                break
            changedAny := true
        }
        return changedAny ? HtmlNorm._SerializeDomNodes(nodes) : html
    }

    /**
     * Recursive worker entry for DOM container simplification.
     * @param {Array} nodes
     * @param {boolean} changed
     * @returns {Array}
     */
    static _UnwrapNestedContainersDomNodes(nodes, &changed) {
        out := []
        for node in nodes {
            converted := HtmlNorm._UnwrapNestedContainersDomNode(node, &changed)
            for item in converted
                out.Push(item)
        }
        return out
    }

    /**
     * Node-level worker for _UnwrapNestedContainersDomNodes.
     * @param {DomNode} node
     * @param {boolean} changed
     * @returns {Array}
     */
    static _UnwrapNestedContainersDomNode(node, &changed) {
        if (node.children.Length > 0)
            node.children := HtmlNorm._UnwrapNestedContainersDomNodes(node.children, &changed)

        if HtmlNorm._IsTag(node, "pre") {
            if InStr(HtmlNorm._GetAttrCI(node, "class"), "code-block__code") {
                node.attrs := Map()
                changed := true
            }
            kids := HtmlNorm._MeaningfulChildren(node)
            if (kids.Length = 1 && HtmlNorm._IsTag(kids[1], "pre")) {
                changed := true
                return [kids[1]]
            }
            return [node]
        }

        if HtmlNorm._IsTag(node, "div") {
            if HtmlNorm._ClassHasToken(node, "sticky") {
                changed := true
                return []
            }
            kids := HtmlNorm._MeaningfulChildren(node)
            if (kids.Length = 1 && HtmlNorm._IsTag(kids[1], "div")) {
                inner := kids[1]
                gkids := HtmlNorm._MeaningfulChildren(inner)
                if (gkids.Length = 1) {
                    target := gkids[1]
                    if HtmlNorm._IsTag(target, "code") {
                        changed := true
                        return [target]
                    }
                    if HtmlNorm._IsTag(target, "pre") {
                        tKids := HtmlNorm._MeaningfulChildren(target)
                        if (tKids.Length = 1 && HtmlNorm._IsTag(tKids[1], "code")) {
                            changed := true
                            return [target]
                        }
                    }
                }
            }
        }

        return [node]
    }

    /**
     * Normalizes footnote-specific HTML constructs via DOM traversal.
     *
     * - Removes Claude Web language-label containers:
     *   <div class="... font-small ... p-3* ...">...</div>
     * - Rewrites long hrefs to fragment-only form:
     *   "...#user-content-foo" -> "#user-content-foo"
     * - Unwraps single <p> wrappers in footnote definition list items:
     *   <li id="user-content-fn-N"><p>...</p></li> -> <li id="...">...</li>
     *
     * @param {string} html
     * @returns {string}
     */
    static _NormalizeFootnoteAndSpanDom(html) {
        if !RegExMatch(html, "i)(<div\b[^>]*\bclass=`"[^`"]*\bfont-small\b[^`"]*\bp-3[^`"]*`"|href=`"[^`"]*#user-content-|<li\b[^>]*\bid=`"user-content-fn-|</?span\b)")
            return html

        nodes := HtmlNorm._TryParseDomNodes(html)
        if (nodes.Length = 0)
            return html

        if !HtmlNorm._NormalizeFootnoteAndSpanDomNodes(&nodes)
            return html
        return HtmlNorm._SerializeDomNodes(nodes)
    }

    /**
     * Normalizes footnote/span constructs in parsed DOM nodes.
     * @param {Array} nodes
     * @returns {boolean} True when any node/attribute was changed
     */
    static _NormalizeFootnoteAndSpanDomNodes(&nodes) {
        changed := false

        labelDivs := []
        HtmlNorm._CollectMatchingNodes(nodes
            , (n) => HtmlNorm._IsTag(n, "div")
                && HtmlNorm._ClassHasToken(n, "font-small")
                && HtmlNorm._ClassHasPrefix(n, "p-3")
            , &labelDivs)
        if (labelDivs.Length > 0) {
            nodes := HtmlNorm._RemoveMatchingDomNodes(nodes
                , (n) => HtmlNorm._IsTag(n, "div")
                    && HtmlNorm._ClassHasToken(n, "font-small")
                    && HtmlNorm._ClassHasPrefix(n, "p-3"))
            changed := true
        }

        anchors := []
        HtmlNorm._CollectMatchingNodes(nodes, (n) => HtmlNorm._IsTag(n, "a"), &anchors)
        for anchor in anchors {
            for key, value in anchor.attrs {
                if (StrLower(key) != "href")
                    continue
                newValue := HtmlNorm._NormalizeFootnoteHref(value)
                if (newValue = "")
                    continue
                if (value != newValue) {
                    anchor.attrs[key] := newValue
                    changed := true
                }
            }
        }

        footnoteLis := []
        HtmlNorm._CollectMatchingNodes(nodes
            , (n) => HtmlNorm._IsTag(n, "li")
                && HtmlNorm._StartsWithCI(HtmlNorm._GetAttrCI(n, "id"), "user-content-fn-")
            , &footnoteLis)

        for li in footnoteLis {
            contentCount := 0
            onlyContent := ""
            for child in li.children {
                if HtmlNorm._IsWhitespaceTextNode(child)
                    continue
                contentCount += 1
                if (contentCount = 1)
                    onlyContent := child
            }
            if (contentCount != 1)
                continue
            if !IsObject(onlyContent) || !HtmlNorm._IsTag(onlyContent, "p")
                continue
            li.children := onlyContent.children
            changed := true
        }

        spanNodes := []
        HtmlNorm._CollectMatchingNodes(nodes, (n) => HtmlNorm._IsTag(n, "span"), &spanNodes)
        if (spanNodes.Length > 0) {
            nodes := HtmlNorm._UnwrapTagDomNodes(nodes, "span")
            changed := true
        }

        return changed
    }

    ; ─────────────────────────────────────────────────────────────────────────
    ; Shared helpers
    ; ─────────────────────────────────────────────────────────────────────────

    /**
     * Applies image/SVG replacement on parsed DOM nodes.
     * @param {Array} nodes
     * @returns {Array}
     */
    static _ProcessImgTagsDomNodes(nodes) {
        out := []
        for node in nodes {
            converted := HtmlNorm._ProcessImgTagsDomNode(node)
            for item in converted
                out.Push(item)
        }
        return out
    }

    /**
     * DOM recursive worker for image/SVG replacement.
     * Returns 0..n nodes to support drop/replace behavior.
     * @param {DomNode} node
     * @returns {Array}
     */
    static _ProcessImgTagsDomNode(node) {
        tag := StrLower(node.tag)

        if (tag = "img") {
            accessText := HtmlNorm._GetAttrCI(node, "alt")
            if (accessText = "")
                accessText := HtmlNorm._GetAttrCI(node, "title")
            if (accessText = "")
                accessText := HtmlNorm._GetAttrCI(node, "aria-label")
            return (accessText = "") ? [] : [DomNode("text", "", "(img: " . accessText . ")")]
        }

        if (tag = "svg") {
            accessText := HtmlNorm._GetAttrCI(node, "aria-label")
            if (accessText = "")
                accessText := HtmlNorm._GetAttrCI(node, "title")
            if (accessText = "") {
                titleNode := HtmlNorm._FirstDescendantByTag(node, "title")
                if IsObject(titleNode)
                    accessText := HtmlNorm._DecodeBasicHtmlEntities(HtmlNorm._NodeTextRecursive(titleNode))
            }
            return (accessText = "") ? [] : [DomNode("text", "", "(img: " . accessText . ")")]
        }

        if (node.children.Length > 0) {
            newChildren := []
            for child in node.children {
                converted := HtmlNorm._ProcessImgTagsDomNode(child)
                for item in converted
                    newChildren.Push(item)
            }
            node.children := newChildren
        }
        return [node]
    }

    /**
     * Recursively extracts thinking <details> blocks into placeholders.
     * @param {Array} nodes
     * @returns {Array}
     */
    static _ExtractThinkingBlocksDomNodes(nodes) {
        out := []
        for node in nodes {
            converted := HtmlNorm._ExtractThinkingBlocksDomNode(node)
            for item in converted
                out.Push(item)
        }
        return out
    }

    /**
     * Node-level worker for _ExtractThinkingBlocksDomNodes.
     * @param {DomNode} node
     * @returns {Array}
     */
    static _ExtractThinkingBlocksDomNode(node) {
        if HtmlNorm._IsTag(node, "details") && HtmlNorm._ClassHasToken(node, "thinking") {
            inner := ""
            for child in node.children {
                if HtmlNorm._IsTag(child, "summary")
                    continue
                inner .= HtmlNorm._NodeTextRecursive(child)
            }
            inner := HtmlNorm._DecodeBasicHtmlEntities(inner)
            inner := Trim(inner, " `t`n`r")
            HtmlNorm._thinkingBlocks.Push(inner)
            marker := "¤THINKING_" . HtmlNorm._thinkingBlocks.Length . "¤"
            return [DomNode("text", "", marker)]
        }

        if (node.children.Length > 0) {
            newChildren := []
            for child in node.children {
                converted := HtmlNorm._ExtractThinkingBlocksDomNode(child)
                for item in converted
                    newChildren.Push(item)
            }
            node.children := newChildren
        }
        return [node]
    }

    /**
     * True when any node in subtree has text-decoration: line-through style.
     * @param {DomNode} root
     * @returns {boolean}
     */
    static _SubtreeHasLineThroughStyle(root) {
        hit := root.FindFirst((n) => HtmlNorm._StyleHasLineThrough(n))
        return IsObject(hit)
    }

    /**
     * Collects text occurring after the first checkbox input in subtree order.
     * @param {DomNode} root
     * @returns {string}
     */
    static _CollectTextAfterFirstCheckbox(root) {
        found := false
        out := ""
        HtmlNorm._CollectTextAfterFirstCheckboxNode(root, &found, &out)
        return out
    }

    /**
     * Recursive worker for _CollectTextAfterFirstCheckbox.
     * @param {DomNode} node
     * @param {boolean} found
     * @param {string} out
     */
    static _CollectTextAfterFirstCheckboxNode(node, &found, &out) {
        if (node.tag = "text") {
            if found
                out .= node.text
            return
        }

        if HtmlNorm._IsTag(node, "input")
            && (StrLower(HtmlNorm._GetAttrCI(node, "type")) = "checkbox") {
            if !found
                found := true
            return
        }

        for child in node.children
            HtmlNorm._CollectTextAfterFirstCheckboxNode(child, &found, &out)
    }

    /**
     * Recursively unwraps matching tag nodes while keeping child content/order.
     * @param {Array} nodes
     * @param {string} tagName
     * @returns {Array}
     */
    static _UnwrapTagDomNodes(nodes, tagName) {
        out := []
        for node in nodes {
            converted := HtmlNorm._UnwrapTagDomNode(node, tagName)
            for item in converted
                out.Push(item)
        }
        return out
    }

    /**
     * Node-level worker for _UnwrapTagDomNodes.
     * Returns 0..n nodes so wrappers can be removed in-place.
     * @param {DomNode} node
     * @param {string} tagName
     * @returns {Array}
     */
    static _UnwrapTagDomNode(node, tagName) {
        if (StrLower(node.tag) = tagName) {
            unwrapped := []
            for child in node.children {
                converted := HtmlNorm._UnwrapTagDomNode(child, tagName)
                for item in converted
                    unwrapped.Push(item)
            }
            return unwrapped
        }
        if (node.children.Length > 0) {
            newChildren := []
            for child in node.children {
                converted := HtmlNorm._UnwrapTagDomNode(child, tagName)
                for item in converted
                    newChildren.Push(item)
            }
            node.children := newChildren
        }
        return [node]
    }

    /**
     * Recursively removes nodes matching a predicate.
     * Matching nodes are dropped entirely with their subtrees.
     * @param {Array} nodes
     * @param {Func} pred
     * @returns {Array}
     */
    static _RemoveMatchingDomNodes(nodes, pred) {
        out := []
        for node in nodes {
            converted := HtmlNorm._RemoveMatchingDomNode(node, pred)
            for item in converted
                out.Push(item)
        }
        return out
    }

    /**
     * Node-level worker for _RemoveMatchingDomNodes.
     * Returns 0..n nodes to allow removing current node in-place.
     * @param {DomNode} node
     * @param {Func} pred
     * @returns {Array}
     */
    static _RemoveMatchingDomNode(node, pred) {
        if pred.Call(node)
            return []
        if (node.children.Length > 0) {
            newChildren := []
            for child in node.children {
                converted := HtmlNorm._RemoveMatchingDomNode(child, pred)
                for item in converted
                    newChildren.Push(item)
            }
            node.children := newChildren
        }
        return [node]
    }

    /**
     * Inserts poster placeholder paragraphs into all nodes matching predicate.
     * @param {Array} nodes
     * @param {Func} pred
     * @param {string} marker
     */
    static _InjectPosterForMatches(nodes, pred, marker) {
        matches := []
        HtmlNorm._CollectMatchingNodes(nodes, pred, &matches)
        for node in matches
            HtmlNorm._InjectPosterIntoNode(node, marker)
    }

    /**
     * Recursively collects nodes matching predicate.
     * @param {Array} nodes
     * @param {Func} pred
     * @param {Array} out
     */
    static _CollectMatchingNodes(nodes, pred, &out) {
        for node in nodes {
            if pred.Call(node)
                out.Push(node)
            if (node.children.Length > 0)
                HtmlNorm._CollectMatchingNodes(node.children, pred, &out)
        }
    }

    /**
     * Inserts <p>marker</p> as the first child of a node.
     * @param {DomNode} node
     * @param {string} marker
     */
    static _InjectPosterIntoNode(node, marker) {
        p := DomNode("p")
        p.Add(DomNode("text", "", marker))
        node.children.InsertAt(1, p)
    }

    /**
     * Returns first descendant node with tag, including self.
     * @param {DomNode} node
     * @param {string} tagName
     * @returns {DomNode|string}
     */
    static _FirstDescendantByTag(node, tagName) {
        if (StrLower(node.tag) = tagName)
            return node
        for child in node.children {
            hit := HtmlNorm._FirstDescendantByTag(child, tagName)
            if IsObject(hit)
                return hit
        }
        return ""
    }

    /**
     * Concatenates all text-node content in a subtree.
     * @param {DomNode} node
     * @returns {string}
     */
    static _NodeTextRecursive(node) {
        if (node.tag = "text")
            return node.text
        out := ""
        for child in node.children
            out .= HtmlNorm._NodeTextRecursive(child)
        return out
    }

    /**
     * True when node is a whitespace-only text node.
     * @param {DomNode} node
     * @returns {boolean}
     */
    static _IsWhitespaceTextNode(node) {
        return (node.tag = "text" && Trim(node.text, " `t`r`n") = "")
    }

    /**
     * Gets a case-insensitive attribute value.
     * @param {DomNode} node
     * @param {string} attrName
     * @returns {string}
     */
    static _GetAttrCI(node, attrName) {
        keyLower := StrLower(attrName)
        for key, value in node.attrs
            if (StrLower(key) = keyLower)
                return value
        return ""
    }

    /**
     * True when an attribute exists, case-insensitive.
     * @param {DomNode} node
     * @param {string} attrName
     * @returns {boolean}
     */
    static _HasAttrCI(node, attrName) {
        keyLower := StrLower(attrName)
        for key, _ in node.attrs
            if (StrLower(key) = keyLower)
                return true
        return false
    }

    /**
     * True when node tag matches tagName (case-insensitive).
     * @param {DomNode} node
     * @param {string} tagName
     * @returns {boolean}
     */
    static _IsTag(node, tagName) {
        return (StrLower(node.tag) = tagName)
    }

    /**
     * True when class attribute contains exact token.
     * @param {DomNode} node
     * @param {string} token
     * @returns {boolean}
     */
    static _ClassHasToken(node, token) {
        classAttr := HtmlNorm._GetAttrCI(node, "class")
        if (classAttr = "")
            return false
        for item in StrSplit(classAttr, " ") {
            t := Trim(item, " `t`r`n")
            if (t = "")
                continue
            if (t = token)
                return true
        }
        return false
    }

    /**
     * True when any class token starts with the given prefix.
     * @param {DomNode} node
     * @param {string} prefix
     * @returns {boolean}
     */
    static _ClassHasPrefix(node, prefix) {
        classAttr := HtmlNorm._GetAttrCI(node, "class")
        if (classAttr = "")
            return false
        for item in StrSplit(classAttr, " ") {
            t := Trim(item, " `t`r`n")
            if (t = "")
                continue
            if (SubStr(t, 1, StrLen(prefix)) = prefix)
                return true
        }
        return false
    }

    /**
     * Case-insensitive starts-with.
     * @param {string} s
     * @param {string} prefix
     * @returns {boolean}
     */
    static _StartsWithCI(s, prefix) {
        return (StrLower(SubStr(s, 1, StrLen(prefix))) = StrLower(prefix))
    }

    /**
     * Returns canonical "#user-content-..." href when value contains it,
     * else returns "".
     * @param {string} href
     * @returns {string}
     */
    static _NormalizeFootnoteHref(href) {
        marker := "#user-content-"
        pos := InStr(StrLower(href), marker)
        if (pos < 1)
            return ""
        tail := SubStr(href, pos + 1) ; keep without leading '#'
        qPos := InStr(tail, "?")
        if (qPos > 0)
            tail := SubStr(tail, 1, qPos - 1)
        hashPos := InStr(tail, "#")
        if (hashPos > 0)
            tail := SubStr(tail, 1, hashPos - 1)
        tail := Trim(tail, " `t`r`n")
        return (tail = "") ? "" : ("#" . tail)
    }

    /**
     * True when node style contains text-decoration: line-through.
     * @param {DomNode} node
     * @returns {boolean}
     */
    static _StyleHasLineThrough(node) {
        style := StrLower(HtmlNorm._GetAttrCI(node, "style"))
        return (InStr(style, "text-decoration") > 0 && InStr(style, "line-through") > 0)
    }

    /**
     * Serializes parsed DOM nodes back to HTML.
     * @param {Array} nodes
     * @returns {string}
     */
    static _SerializeDomNodes(nodes) {
        out := ""
        for node in nodes
            out .= HtmlNorm._SerializeDomNode(node)
        return out
    }

    /**
     * Serializes one DOM node subtree to HTML.
     * @param {DomNode} node
     * @returns {string}
     */
    static _SerializeDomNode(node) {
        if (node.tag = "text")
            return node.text

        attrs := ""
        for key, value in node.attrs {
            if (value = "")
                attrs .= " " . key
            else
                attrs .= " " . key . '="' . HtmlNorm._EscapeAttr(value) . '"'
        }

        tag := node.tag
        if (HtmlNorm._IsVoidTag(tag))
            return "<" . tag . attrs . ">"

        inner := ""
        for child in node.children
            inner .= HtmlNorm._SerializeDomNode(child)
        return "<" . tag . attrs . ">" . inner . "</" . tag . ">"
    }

    /**
     * Escapes text for use in HTML attribute values.
     * @param {string} value
     * @returns {string}
     */
    static _EscapeAttr(value) {
        s := "" . value
        s := StrReplace(s, "&", "&amp;")
        s := StrReplace(s, '"', "&quot;")
        s := StrReplace(s, "<", "&lt;")
        s := StrReplace(s, ">", "&gt;")
        return s
    }

    /**
     * True when tag is a void HTML element.
     * @param {string} tag
     * @returns {boolean}
     */
    static _IsVoidTag(tag) {
        tag := StrLower(tag)
        return (tag = "area"
            || tag = "base"
            || tag = "br"
            || tag = "col"
            || tag = "embed"
            || tag = "hr"
            || tag = "img"
            || tag = "input"
            || tag = "link"
            || tag = "meta"
            || tag = "param"
            || tag = "source"
            || tag = "track"
            || tag = "wbr")
    }

    /**
     * Parses HTML into DomNode trees.
     * Returns [] when parsing fails.
     * @param {string} html
     * @returns {Array}
     */
    static _TryParseDomNodes(html) {
        if (html = "")
            return []
        try {
            return HtmlParser.Parse(html)
        } catch {
            return []
        }
    }

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
