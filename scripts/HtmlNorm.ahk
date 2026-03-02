;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; HtmlNorm — Source detection and HTML normalization for PasteAsMd
;
; Replaces PreprocessHtmlCodeBlocks in PasteAsMd.ahk with a more accurate
; normalizer that handles Codex, Claude Code, Claude Web, and ChatGPT web.
;
; No dependencies — does not require HtmlParser.ahk.
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
 * - "chatgpt"     no extensionId; HTML fragment contains `data-turn-id=` attribute
 *                 (ChatGPT web — no SourceURL header in its CF_HTML payload)
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
 *   - `HtmlNorm._thinkingBlocks` — inner texts of thinking blocks (¤THINKING_N¤)
 *   - `HtmlNorm._userMsgBlocks`  — user message raw text (¤USERMSG_N¤)
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
     * Normalizes an HTML fragment for pandoc processing.
     *
     * Transforms are applied in order:
     *   1.  Image/SVG handling: drop if no accessible text, else (img: text); leave when showImg
     *   2.  Poster-label placeholder injection (when showPoster)
     *   3.  Button stripping
     *   4.  ChatGPT code block extraction (pre.overflow-visible! → pre/code)
     *   5.  Task-list checkbox normalization (→ ¤CHK¤/¤UNCHK¤)
     *   6.  Thinking block extraction (→ ¤THINKING_N¤)
     *   7.  Inline-code span promotion (inline-markdown/font-mono → <code>)
     *   8.  User message extraction (→ ¤USERMSG_N¤)
     *   9.  Claude Web language-label div removal
     *   10. Footnote URL stripping (long URLs → #fragment)
     *   11. Residual span tag removal
     *   12. Bare <li> list wrapping in <ol>
     *   13. <code> element normalization (line-break conversion, pre-wrapping)
     *   14. Nested container unwrapping
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
        html := htmlFrag

        ; 1. Handle <img> tags.
        html := HtmlNorm._ProcessImgTags(html, showImg)

        ; 2. Inject poster-label placeholders.
        if showPoster
            html := HtmlNorm._InjectPosterPlaceholders(html, source)

        ; 3. Strip UI buttons.
        html := RegExReplace(html, "is)<button\b[^>]*>.*?</button>", "")

        ; 4. ChatGPT: normalize CodeMirror code blocks before any span stripping.
        if (source = "chatgpt")
            html := HtmlNorm._NormalizeChatGptCodeBlocks(html)

        ; 5. Normalize task-list checkboxes.
        html := HtmlNorm._NormalizeTaskListItems(html)

        ; 6. Extract thinking blocks.
        html := HtmlNorm._ExtractThinkingBlocks(html)

        ; 7. Promote inline-code spans.
        html := RegExReplace(html, "is)<span\b[^>]*\bclass=`"[^`"]*\b(?:inline-markdown|font-mono)\b[^`"]*`"[^>]*>(.*?)</span>", "<code>$1</code>")

        ; 8. Extract whitespace-sensitive user message text.
        html := HtmlNorm._ExtractUserMessages(html)

        ; 9. Strip Claude Web language-label divs (font-small p-3.5 pb-0).
        html := RegExReplace(html, "is)<div\b[^>]*\bclass=`"[^`"]*\bfont-small\b[^`"]*\bp-3[^`"]*`"[^>]*>.*?</div>", "")

        ; 10. Strip long footnote hrefs, keeping only the #fragment.
        html := RegExReplace(html, "i)href=`"[^`"]*#(user-content-[^`"]*)`"", "href=`"#$1`"")

        ; 10b. Strip <p> wrapper inside footnote definition <li> elements.
        ;      <li id="user-content-fn-N"><p>text</p></li> → <li id="...">text</li>
        ;      Without this, pandoc renders footnote lists in loose format (number on
        ;      its own line, content indented), instead of tight (number + content inline).
        html := RegExReplace(html, "is)(<li\b[^>]*\bid=`"user-content-fn-[^`"]*`"[^>]*>)\s*<p\b[^>]*>(.*?)</p>\s*(</li>)", "$1$2$3")

        ; 11. Strip residual <span> tags.
        html := RegExReplace(html, "i)</?span\b[^>]*>", "")

        ; 12. Wrap bare top-level <li> siblings in <ol>.
        htmlNoTrailingBr := RegExReplace(html, "is)(?:<br\b[^>]*>\s*)+$", "")
        trimmed := Trim(htmlNoTrailingBr, " `t`r`n")
        if (trimmed != "" && RegExMatch(trimmed, "is)^(?:<li\b[^>]*>.*?</li>\s*)+$"))
            html := "<ol>" . trimmed . "</ol>"

        ; 13. Normalize <code> elements.
        html := HtmlNorm._NormalizeCodeElements(html)

        ; 14. Unwrap nested containers that obscure code blocks.
        html := HtmlNorm._UnwrapNestedContainers(html)

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
     * @param {string} html
     * @param {boolean} showImg
     * @returns {string}
     */
    static _ProcessImgTags(html, showImg) {
        if showImg
            return html
        ; <img> tags (self-closing).
        pos := 1
        while RegExMatch(html, "i)<img\b([^>]*?)>", &m, pos) {
            attrs := m[1]
            accessText := ""
            if (RegExMatch(attrs, "i)\balt\s*=\s*['`"]([^'`"]*)[`"']", &mA) && mA[1] != "")
                accessText := mA[1]
            else if (RegExMatch(attrs, "i)\btitle\s*=\s*['`"]([^'`"]*)[`"']", &mT) && mT[1] != "")
                accessText := mT[1]
            else if (RegExMatch(attrs, "i)\baria-label\s*=\s*['`"]([^'`"]*)[`"']", &mL) && mL[1] != "")
                accessText := mL[1]
            replacement := (accessText = "") ? "" : "(img: " . accessText . ")"
            html := SubStr(html, 1, m.Pos - 1) . replacement . SubStr(html, m.Pos + m.Len)
            pos := m.Pos + StrLen(replacement)
        }
        ; <svg>…</svg> elements — same rule, checking aria-label, title attr, or <title> child.
        pos := 1
        while RegExMatch(html, "is)<svg\b([^>]*)>.*?</svg>", &m, pos) {
            attrs := m[1]
            full  := m[0]
            accessText := ""
            if (RegExMatch(attrs, "i)\baria-label\s*=\s*['`"]([^'`"]*)[`"']", &mL) && mL[1] != "")
                accessText := mL[1]
            else if (RegExMatch(attrs, "i)\btitle\s*=\s*['`"]([^'`"]*)[`"']", &mT) && mT[1] != "")
                accessText := mT[1]
            else if (RegExMatch(full, "i)<title\b[^>]*>(.*?)</title>", &mTc) && mTc[1] != "")
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
            html := RegExReplace(html, "i)(<div\b[^>]*\bdata-testid=`"assistant-message`"[^>]*>)", "$1<p>¤POSTER_AI¤</p>")
            ; user turn (class has both message_* and userMessageContainer_*)
            html := RegExReplace(html, "i)(<div\b[^>]*\bclass=`"[^`"]*\bmessage_\w+\s+[^`"]*\buserMessageContainer_[^>]*>)", "$1<p>¤POSTER_User¤</p>")
        } else if (source = "codex") {
            ; AI turn (group min-w-0 flex-col)
            html := RegExReplace(html, "i)(<div\b[^>]*\bclass=`"[^`"]*\bgroup\b[^`"]*\bmin-w-0\b[^`"]*\bflex-col\b[^`"]*`"[^>]*>)", "$1<p>¤POSTER_AI¤</p>")
            ; user turn (flex-col items-end)
            html := RegExReplace(html, "i)(<div\b[^>]*\bclass=`"[^`"]*\bflex-col\b[^`"]*\bitems-end\b[^`"]*`"[^>]*>)", "$1<p>¤POSTER_User¤</p>")
        } else if (source = "claudeweb") {
            ; AI turn (data-is-streaming or font-claude-response)
            html := RegExReplace(html, "i)(<div\b[^>]*(?:\bdata-is-streaming\b|\bclass=`"[^`"]*\bfont-claude-response\b[^`"]*`")[^>]*>)", "$1<p>¤POSTER_AI¤</p>")
            ; user turn (data-testid="user-message")
            html := RegExReplace(html, "i)(<div\b[^>]*\bdata-testid=`"user-message`"[^>]*>)", "$1<p>¤POSTER_User¤</p>")
        } else if (source = "chatgpt") {
            ; AI turn (article with data-turn-id="request-WEB:...")
            html := RegExReplace(html, "i)(<article\b[^>]*\bdata-turn-id=`"request-WEB:[^`"]*`"[^>]*>)", "$1<p>¤POSTER_AI¤</p>")
            ; user turn (article with plain UUID data-turn-id)
            html := RegExReplace(html, "i)(<article\b[^>]*\bdata-turn-id=`"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}`"[^>]*>)", "$1<p>¤POSTER_User¤</p>")
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
        pos := 1
        while RegExMatch(html, "is)<pre\b[^>]*\boverflow-visible\b[^>]*>(.*?)</pre>", &m, pos) {
            inner := m[1]
            ; Convert <br> to newlines before stripping all other tags.
            inner := RegExReplace(inner, "i)<br\b[^>]*>", "`n")
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
     * Normalizes task-list `<li>` elements to `<li>¤CHK¤ text</li>` form.
     *
     * Processes any `<li class="task-list-item">` that contains
     * `<input type="checkbox">`, regardless of whether the input is a direct
     * child or wrapped in a `<p>` tag (as ChatGPT does).
     *
     * Uses ¤CHK¤/¤UNCHK¤ placeholders instead of `[x]`/`[ ]` so that pandoc
     * does not escape the brackets.  `CleanMarkdown()` restores them afterward.
     *
     * @param {string} html
     * @returns {string}
     */
    static _NormalizeTaskListItems(html) {
        pos := 1
        while RegExMatch(html, "is)<li\b([^>]*)>(.*?)</li>", &mTask, pos) {
            liAttrs := mTask[1]
            liInner := mTask[2]
            ; Require task-list-item class on the <li>.
            if !RegExMatch(liAttrs, "i)\btask-list-item\b") {
                pos := mTask.Pos + mTask.Len
                continue
            }
            ; Find <input type="checkbox"> anywhere inside the item
            ; (direct child OR inside a <p> wrapper, as ChatGPT does).
            if !RegExMatch(liInner, "is)<input\b[^>]*\btype\s*=\s*['`"]checkbox['`"][^>]*>", &mInput) {
                pos := mTask.Pos + mTask.Len
                continue
            }
            checked := RegExMatch(liInner, "i)\bchecked\b")
            ; Capture text that follows the <input> tag.
            text := SubStr(liInner, mInput.Pos + mInput.Len)
            text := RegExReplace(text, "is)<span\b[^>]*>\s*</span>", "")
            text := RegExReplace(text, "<[^>]++>", "")
            text := HtmlNorm._DecodeBasicHtmlEntities(text)
            text := Trim(text, " `t`r`n" . Chr(160))
            ; Re-encode for HTML context.
            text := StrReplace(text, "&", "&amp;")
            text := StrReplace(text, "<", "&lt;")
            text := StrReplace(text, ">", "&gt;")
            marker := checked ? "¤CHK¤ " : "¤UNCHK¤ "
            replacement := "<li>" . marker . text . "</li>"
            html := SubStr(html, 1, mTask.Pos - 1) . replacement . SubStr(html, mTask.Pos + mTask.Len)
            pos := mTask.Pos + StrLen(replacement)
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
        while RegExMatch(html, "is)<details\b[^>]*\bclass=`"[^`"]*\bthinking\b[^`"]*`"[^>]*>(.*?)</details>", &m, pos) {
            inner := m[1]
            inner := RegExReplace(inner, "is)<summary\b[^>]*>.*?</summary>", "")
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
        while RegExMatch(html, "is)(<div\b[^>]*\btext-size-chat\b[^>]*\bwhitespace-pre-wrap\b[^>]*>)(.*?)</div>", &m, pos) {
            rawContent := m[2]
            rawContent := RegExReplace(rawContent, "is)<code\b[^>]*\bfont-mono\b[^>]*>(.*?)</code>", "``$1``")
            rawContent := RegExReplace(rawContent, "i)</?span\b[^>]*>", "")
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
        while RegExMatch(html, "is)(<div\b[^>]*\bcontent_xGDvVg\b[^>]*>)\s*<span>(.*?)</span>", &m, pos) {
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
        while RegExMatch(html, "is)(<p\b[^>]*\bclass=`"whitespace-pre-wrap break-words`"[^>]*>)(.*?)</p>", &m, pos) {
            rawContent := m[2]
            rawContent := RegExReplace(rawContent, "i)<br\b[^>]*>", "`n")
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
        while RegExMatch(html, "is)(<div\b[^>]*\bclass=`"whitespace-pre-wrap`"[^>]*>)(.*?)</div>", &m, pos) {
            rawContent := m[2]
            rawContent := RegExReplace(rawContent, "i)<br\b[^>]*>", "`n")
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
        while RegExMatch(html, "is)<code\b([^>]*)>(.*?)</code>", &m, pos) {
            content := m[2]
            attrs   := m[1]
            ; Normalize line-break representations inside the code.
            content := RegExReplace(content, "i)<br\b[^>]*>", "`n")
            content := RegExReplace(content, "i)</div>\s*<div\b[^>]*>", "`n")
            content := RegExReplace(content, "<[^>]++>", "")
            content := StrReplace(content, "`r", "")
            if InStr(content, "`n") {
                content := HtmlNorm._DecodeBasicHtmlEntities(content)
                ; Extract language identifier; discard pure-CSS classes.
                langAttr := ""
                if RegExMatch(attrs, "i)language-(\w+)", &langM)
                    langAttr := ' class="language-' . langM[1] . '"'
                ; Check whether this <code> is already the direct child of a <pre>.
                beforeSnippet := SubStr(html, Max(1, m.Pos - 100), Min(100, m.Pos - 1))
                if RegExMatch(beforeSnippet, "i)<pre\b[^>]*>\s*$")
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
            html := RegExReplace(html, "is)<pre\b[^>]+>\s*(<pre\b[^>]*><code\b[^>]*>.*?</code></pre>)\s*</pre>", "$1")
            ; Claude Web: <pre class="code-block__code ..."> directly wrapping <code>.
            ; Strip the outer pre's class so pandoc uses the <code class="language-xxx">
            ; for the language identifier, not the pre's CSS utility class.
            html := RegExReplace(html, "is)<pre\b[^>]*\bcode-block__code\b[^>]*>\s*(<code\b[^>]*>.*?</code>)\s*</pre>", "<pre>$1</pre>")
            ; Claude Web copy-button overlay: <div class="sticky ..."><div ...></div></div>
            ; Strip it so the remaining structure is a simple two-div wrap around <pre><code>.
            html := RegExReplace(html, "is)<div\b[^>]*\bsticky\b[^>]*>.*?</div>\s*</div>", "")
            ; Two nested <div>s wrapping <pre><code>.
            html := RegExReplace(html, "is)<div\b[^>]*>\s*<div\b[^>]*>\s*(<pre><code\b[^>]*>.*?</code></pre>)\s*</div>\s*</div>", "$1")
            ; Two nested <div>s wrapping an inline <code>.
            html := RegExReplace(html, "is)<div\b[^>]*>\s*<div\b[^>]*>\s*(<code\b[^>]*>.*?</code>)\s*</div>\s*</div>", "$1")
        }
        return html
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
