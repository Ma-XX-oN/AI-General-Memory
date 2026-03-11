#ErrorStdOut
#Requires AutoHotkey v2.0
#Include ../HtmlNorm.ahk
#Include test-helpers.ahk

_logPath := A_ScriptDir "\test-norm.log"
try FileDelete _logPath

passed := 0
failed := 0

; ── 1: DetectSource ───────────────────────────────────────────────────────────
Log("── 1: DetectSource ──────────────────────────────────")

cf_cc := "Version:0.9`r`nSourceURL:vscode-webview://x`r`nextensionId=anthropic.claude-ai`r`n"
; Real Claude Web (browser) has NO extensionId in CF_HTML — detected via HTML body signals.
cf_cw := "Version:0.9`r`nStartHTML:0000000105`r`n<div class=`"font-claude-response`">hi</div>"
cf_cx := "Version:0.9`r`nSourceURL:vscode-webview://x`r`nextensionId=openai.chatgpt`r`n"
; ChatGPT web has no extensionId; uses data-turn-id attributes in the HTML.
cf_gp := "Version:0.9`r`n<article data-turn-id=`"e7e18cd8-1234-..`">"

Chk("claudecode has anthropic extensionId",
    DetectSource(cf_cc) = "claudecode")
Chk("claudeweb no extensionId, font-claude-response signal",
    DetectSource(cf_cw) = "claudeweb")
Chk("codex extensionId openai.chatgpt",
    DetectSource(cf_cx) = "codex")
Chk("chatgpt has data-turn-id",
    DetectSource(cf_gp) = "chatgpt")
Chk("unknown — no matching signals",
    DetectSource("Version:0.9`r`nSourceURL:https://example.com/`r`n") = "unknown")

; ── 2: ChatGPT code block normalization ───────────────────────────────────────
Log("── 2: ChatGPT code block normalization ──────────────")

chatgptCode := '<pre class="overflow-visible! px-0!">'
    . '<div class="relative"><div class="cm-editor">'
    . '<div class="cm-content q9tKkq_readonly">'
    . '<span class="tok-keyword">def</span> <span class="tok-name">greet</span>():'
    . '`n    return "Hello"'
    . '</div></div></div></pre>'
normCode := HtmlNorm._NormalizeChatGptCodeBlocks(chatgptCode)

Chk("no overflow-visible! class leaked",    !InStr(normCode, "overflow-visible"))
Chk("output is pre/code block",             InStr(normCode, "<pre><code>"))
Chk("def greet preserved",                  InStr(normCode, "def greet"))
Chk("return Hello preserved",               InStr(normCode, "return"))
Chk("closing /code/pre present",            InStr(normCode, "</code></pre>"))

; ── 3: ChatGPT code block — entity encoding ───────────────────────────────────
Log("── 3: ChatGPT code block entity encoding ────────────")

chatgptCodeEntities := '<pre class="overflow-visible!">'
    . '<span>x &lt; y &amp;&amp; z &gt; 0</span>'
    . '</pre>'
normEntities := HtmlNorm._NormalizeChatGptCodeBlocks(chatgptCodeEntities)

Chk("raw < encoded as &lt;",               InStr(normEntities, "&lt;"))
Chk("raw & encoded as &amp;",              InStr(normEntities, "&amp;"))
Chk("raw > encoded as &gt;",               InStr(normEntities, "&gt;"))

; ── 3b: Diff container normalization (tool output) ────────────────────────────
Log("── 3b: Diff container normalization ─────────────────")

diffHtml := '<div class="header"><button type="button">test-paste-md-fixtures.ahk</button></div>'
    . '<diffs-container class="composer-diff-simple-line"><pre><code>'
    . '<div data-line-type="context"><span data-column-content="">  if fx.withUser {</span></div>'
    . '<div data-line-type="change-deletion"><span data-column-content="">    Chk("with-user has User label", InStr(finalMd, "**User:**"))</span></div>'
    . '<div data-line-type="change-addition"><span data-column-content="">    Chk("with-user has User label", InStr(finalMd, "## User"))</span></div>'
    . '<div data-line-type="context"><span data-column-content="">  }</span></div>'
    . '</code></pre></diffs-container>'
normDiff := HtmlNorm._NormalizeSimpleDiffBlocks(diffHtml)

Chk("diff container removed", !InStr(normDiff, "<diffs-container"))
Chk("language-diff code block emitted", InStr(normDiff, '<pre><code class="language-diff">'))
Chk("edited filename retained", InStr(normDiff, "<code>test-paste-md-fixtures.ahk</code>"))
Chk("deletion line prefixed with -", InStr(normDiff, '-    Chk("with-user has User label", InStr(finalMd, "**User:**"))'))
Chk("addition line prefixed with +", InStr(normDiff, '+    Chk("with-user has User label", InStr(finalMd, "## User"))'))
Chk("context line kept with leading space", InStr(normDiff, "   if fx.withUser {"))

; ── 4: Task-list — direct <input> (Claude Code / Codex style) ─────────────────
Log("── 4: Task list — direct input ──────────────────────")

liDirect := '<li class="task-list-item"><input type="checkbox" checked> Done item</li>'
normDirect := HtmlNorm._NormalizeTaskListItems(liDirect)

Chk("checked keeps canonical input",
    InStr(normDirect, '<input type="checkbox" disabled checked />'))
Chk("text preserved",        InStr(normDirect, "Done item"))
Chk("no placeholder (checked)", !InStr(normDirect, "¤CHK¤") && !InStr(normDirect, "¤UNCHK¤"))
Chk("direct checked canonical li", normDirect = '<li><input type="checkbox" disabled checked /> Done item</li>')

liUnchecked := '<li class="task-list-item"><input type="checkbox"> Pending</li>'
normUnchecked := HtmlNorm._NormalizeTaskListItems(liUnchecked)

Chk("unchecked keeps canonical input",
    InStr(normUnchecked, '<input type="checkbox" disabled />'))
Chk("text Pending preserved", InStr(normUnchecked, "Pending"))
Chk("no placeholder (unchecked)", !InStr(normUnchecked, "¤CHK¤") && !InStr(normUnchecked, "¤UNCHK¤"))
Chk("direct unchecked canonical li", normUnchecked = '<li><input type="checkbox" disabled /> Pending</li>')

; ── 5: Task-list — <p>-wrapped <input> (ChatGPT style) ───────────────────────
Log("── 5: Task list — p-wrapped input (ChatGPT) ─────────")

liPWrapped := '<li class="task-list-item"><p><input disabled="" type="checkbox" checked=""> Done</p></li>'
normPWrapped := HtmlNorm._NormalizeTaskListItems(liPWrapped)

Chk("p-wrapped checked canonical input",
    InStr(normPWrapped, '<input type="checkbox" disabled checked />'))
Chk("p-wrapped text Done preserved", InStr(normPWrapped, "Done"))
Chk("no <p> remains",               !InStr(normPWrapped, "<p>"))
Chk("no placeholder (p-wrapped checked)", !InStr(normPWrapped, "¤CHK¤") && !InStr(normPWrapped, "¤UNCHK¤"))
Chk("p-wrapped checked canonical li", normPWrapped = '<li><input type="checkbox" disabled checked /> Done</li>')

liPUnchecked := '<li class="task-list-item"><p><input disabled="" type="checkbox"> Not done</p></li>'
normPUnchecked := HtmlNorm._NormalizeTaskListItems(liPUnchecked)

Chk("p-wrapped unchecked canonical input",
    InStr(normPUnchecked, '<input type="checkbox" disabled />'))
Chk("p-wrapped text Not done preserved", InStr(normPUnchecked, "Not done"))
Chk("no placeholder (p-wrapped unchecked)", !InStr(normPUnchecked, "¤CHK¤") && !InStr(normPUnchecked, "¤UNCHK¤"))
Chk("p-wrapped unchecked canonical li", normPUnchecked = '<li><input type="checkbox" disabled /> Not done</li>')

; ── 6: Task-list — non-task <li> not modified ─────────────────────────────────
Log("── 6: Task list — plain li not modified ────────────")

liPlain := '<li>just a list item</li>'
normPlain := HtmlNorm._NormalizeTaskListItems(liPlain)
Chk("plain li unchanged",   normPlain = liPlain)

; ── 6b: Task-list — Claude Code todoItem/completed class shape ─────────────────
Log("── 6b: Task list — Claude Code todoItem/completed ─────────")

liTodoCompleted := '<li class="todoItem_xheXVQ completed_xheXVQ">'
    . '<input type="checkbox" class="checkbox_xheXVQ" disabled="">'
    . '<div class="content_xheXVQ" style="text-decoration: line-through;">Fix DetectSource</div>'
    . '</li>'
normTodoCompleted := HtmlNorm._NormalizeTaskListItems(liTodoCompleted)
Chk("todoItem completed infers checked",
    normTodoCompleted = '<li><input type="checkbox" disabled checked /> Fix DetectSource</li>')

liTodoPending := '<li class="todoItem_xheXVQ">'
    . '<input type="checkbox" class="checkbox_xheXVQ" disabled="">'
    . '<div class="content_xheXVQ">Refactor _NormalizeTaskListItems</div>'
    . '</li>'
normTodoPending := HtmlNorm._NormalizeTaskListItems(liTodoPending)
Chk("todoItem pending stays unchecked",
    normTodoPending = '<li><input type="checkbox" disabled /> Refactor _NormalizeTaskListItems</li>')
Chk("todoItem no placeholders",
    !InStr(normTodoCompleted, "¤CHK¤") && !InStr(normTodoCompleted, "¤UNCHK¤")
    && !InStr(normTodoPending, "¤CHK¤") && !InStr(normTodoPending, "¤UNCHK¤"))

; ── 7: Thinking block extraction ──────────────────────────────────────────────
Log("── 7: Thinking block extraction ─────────────────────")

htmlThink := '<p>Before</p>'
    . '<details class="thinking"><summary>Thinking</summary><p>inner thought</p></details>'
    . '<p>After</p>'
result := HtmlNorm._ExtractThinkingBlocks(htmlThink)

Chk("thinking placeholder inserted",    InStr(result, "¤THINKING_1¤"))
Chk("<details> removed from html",      !InStr(result, "<details"))
Chk("before/after preserved",           InStr(result, "Before") && InStr(result, "After"))
Chk("one block stored",                 HtmlNorm._thinkingBlocks.Length = 1)
Chk("block text is inner thought",      HtmlNorm._thinkingBlocks.Length >= 1
    && InStr(HtmlNorm._thinkingBlocks[1], "inner thought"))

; ── 8: Footnote URL stripping ─────────────────────────────────────────────────
Log("── 8: Footnote URL stripping ────────────────────────")

htmlFn := '<a href="vscode-webview://ext/abc#user-content-fn-1">note</a>'
normFn  := RegExReplace(htmlFn, "i)href=`"[^`"]*#(user-content-[^`"]*)`"", "href=`"#$1`"")
Chk("long href stripped to fragment",  normFn = '<a href="#user-content-fn-1">note</a>')

htmlFnWeb := '<a href="https://claude.ai/chat/xyz#user-content-fn-2">2</a>'
normFnWeb  := RegExReplace(htmlFnWeb, "i)href=`"[^`"]*#(user-content-[^`"]*)`"", "href=`"#$1`"")
Chk("claude.ai href stripped",         normFnWeb = '<a href="#user-content-fn-2">2</a>')

; ── 8b: KaTeX wrapper collapse ────────────────────────────────────────────────
Log("── 8b: KaTeX wrapper collapse ───────────────────────")

katexHtml := '<p>Inline <span class="katex"><span class="katex-mathml">'
    . '<math><semantics><mi>x</mi><annotation encoding="application/x-tex">x</annotation></semantics></math>'
    . '</span><span class="katex-html" aria-hidden="true"><span class="base"><span class="mord">VISIBLE_INLINE</span></span></span></span> end</p>'
    . '<span class="katex-display"><span class="katex"><span class="katex-mathml">'
    . '<math display="block"><semantics><mi>y</mi><annotation encoding="application/x-tex">y</annotation></semantics></math>'
    . '</span><span class="katex-html" aria-hidden="true"><span class="base"><span class="mord">VISIBLE_BLOCK</span></span></span></span></span>'
normKatex := HtmlNorm.Normalize(katexHtml, "unknown", false, false)
Chk("katex inline math preserved",
    InStr(normKatex, '<math><semantics><mi>x</mi><annotation encoding="application/x-tex">x</annotation></semantics></math>'))
Chk("katex display math preserved",
    InStr(normKatex, '<math display="block"><semantics><mi>y</mi><annotation encoding="application/x-tex">y</annotation></semantics></math>'))
Chk("katex inline visual branch removed", !InStr(normKatex, "VISIBLE_INLINE"))
Chk("katex display visual branch removed", !InStr(normKatex, "VISIBLE_BLOCK"))

; ── 8c: Region-scoped mixed block normalization ───────────────────────────────
Log("── 8c: Region-scoped mixed block normalization ──────")

scopedHtml := '<p>Intro</p>'
    . '<pre class="overflow-visible! px-0!"><div class="cm-content"><span>print</span><span>(1)</span></div></pre>'
    . '<ul><li class="task-list-item"><input type="checkbox" checked> Done</li></ul>'
    . '<details class="thinking"><summary>Thinking</summary><p>inner thought</p></details>'
    . '<p>Math <span class="katex"><span class="katex-mathml">'
    . '<math><semantics><mi>x</mi><annotation encoding="application/x-tex">x</annotation></semantics></math>'
    . '</span><span class="katex-html" aria-hidden="true"><span class="base"><span class="mord">VISIBLE_INLINE</span></span></span></span></p>'
regions := HtmlNorm._DiscoverRegions(scopedHtml, "chatgpt")
HtmlNorm._thinkingBlocks := []
scopedNorm := HtmlNorm._ApplyRegionScopedTransforms(scopedHtml, "chatgpt")

Chk("scoped regions split into top-level blocks", regions.Length = 5)
Chk("scoped regions flag chatgpt code block", regions[2]["hasChatGptCode"])
Chk("scoped regions flag task list block", regions[3]["hasTaskList"])
Chk("scoped regions flag thinking block", regions[4]["hasThinking"])
Chk("scoped regions flag katex block", regions[5]["hasKatex"])
Chk("scoped code block canonicalized", InStr(scopedNorm, "<pre><code>") && InStr(scopedNorm, "print(1)"))
Chk("scoped task list canonicalized",
    InStr(scopedNorm, '<li><input type="checkbox" disabled checked /> Done</li>'))
Chk("scoped thinking placeholder inserted", InStr(scopedNorm, "¤THINKING_1¤"))
Chk("scoped thinking block stored",
    HtmlNorm._thinkingBlocks.Length = 1 && InStr(HtmlNorm._thinkingBlocks[1], "inner thought"))
Chk("scoped katex math preserved",
    InStr(scopedNorm, '<math><semantics><mi>x</mi><annotation encoding="application/x-tex">x</annotation></semantics></math>'))
Chk("scoped visual wrappers removed",
    !InStr(scopedNorm, "VISIBLE_INLINE") && !InStr(scopedNorm, "overflow-visible") && !InStr(scopedNorm, "<details"))
Chk("scoped untouched intro preserved", InStr(scopedNorm, "<p>Intro</p>"))

; ── 8d: Region-scoped inline code + user messages ─────────────────────────────
Log("── 8d: Region-scoped inline code + user messages ─")

scopedTextHtml := '<p>Say <span class="inline-markdown">hi</span></p>'
    . '<div class="whitespace-pre-wrap">Hello<br>World</div>'
regionsText := HtmlNorm._DiscoverRegions(scopedTextHtml, "chatgpt")
HtmlNorm._userMsgBlocks := []
scopedTextNorm := HtmlNorm._ApplyRegionScopedTransforms(scopedTextHtml, "chatgpt")

Chk("text regions split into inline + user blocks", regionsText.Length = 2)
Chk("text region flags inline code block", regionsText[1]["hasInlineCode"])
Chk("text region flags user message block", regionsText[2]["hasUserMsg"])
Chk("text inline code promoted", InStr(scopedTextNorm, "<code>hi</code>"))
Chk("text user message placeholder inserted", InStr(scopedTextNorm, "<p>¤USERMSG_1¤</p>"))
Chk("text user message stored with newline",
    HtmlNorm._userMsgBlocks.Length = 1 && HtmlNorm._userMsgBlocks[1] = "Hello`nWorld")

; ── 9: Full Normalize — Claude Code minimal ───────────────────────────────────
Log("── 9: Full Normalize — claudecode minimal ───────────")

simpleHtml := '<pre><code class="language-python">print("hello")</code></pre>'
normSimple  := HtmlNorm.Normalize(simpleHtml, "claudecode", false, false)
Chk("pre/code block preserved",       InStr(normSimple, "<pre>") || InStr(normSimple, "<pre><code"))
Chk("language-python preserved",      InStr(normSimple, "language-python"))
Chk("print hello preserved",          InStr(normSimple, "print"))

; ── 10: Full Normalize — ChatGPT code block ───────────────────────────────────
Log("── 10: Full Normalize — chatgpt code block ──────────")

gptHtml := '<pre class="overflow-visible! px-0!"><div class="cm-content">'
    . '<span>def</span> <span>foo</span>():`n    pass'
    . '</div></pre>'
normGpt := HtmlNorm.Normalize(gptHtml, "chatgpt", false, false)
Chk("no overflow-visible! class",     !InStr(normGpt, "overflow-visible"))
Chk("canonical pre/code emitted",     InStr(normGpt, "<pre><code>") || InStr(normGpt, "<pre><code "))
Chk("def foo preserved",              InStr(normGpt, "def") && InStr(normGpt, "foo"))

; ── summary ───────────────────────────────────────────────────────────────────
TestFinish()
