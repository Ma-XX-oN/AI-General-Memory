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
normCode := HtmlNorm.Normalize(chatgptCode, "chatgpt", false, false)

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
normEntities := HtmlNorm.Normalize(chatgptCodeEntities, "chatgpt", false, false)

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
normDiff := HtmlNorm.Normalize(diffHtml, "codex", false, false)

Chk("diff container removed", !InStr(normDiff, "<diffs-container"))
Chk("language-diff code block emitted", InStr(normDiff, '<pre><code class="language-diff">'))
Chk("edited filename retained", InStr(normDiff, "<code>test-paste-md-fixtures.ahk</code>"))
Chk("deletion line prefixed with -", InStr(normDiff, '-    Chk("with-user has User label", InStr(finalMd, "**User:**"))'))
Chk("addition line prefixed with +", InStr(normDiff, '+    Chk("with-user has User label", InStr(finalMd, "## User"))'))
Chk("context line kept with leading space", InStr(normDiff, "   if fx.withUser {"))

; ── 4: Task-list — direct <input> (Claude Code / Codex style) ─────────────────
Log("── 4: Task list — direct input ──────────────────────")

liDirect := '<ul><li class="task-list-item"><input type="checkbox" checked> Done item</li></ul>'
normDirect := HtmlNorm.Normalize(liDirect, "claudecode", false, false)

Chk("checked keeps canonical input",
    InStr(normDirect, '<input type="checkbox" disabled checked />'))
Chk("text preserved",        InStr(normDirect, "Done item"))
Chk("no placeholder (checked)", !InStr(normDirect, "¤CHK¤") && !InStr(normDirect, "¤UNCHK¤"))
Chk("direct checked canonical li", normDirect = '<ul><li><input type="checkbox" disabled checked /> Done item</li></ul>')

liUnchecked := '<ul><li class="task-list-item"><input type="checkbox"> Pending</li></ul>'
normUnchecked := HtmlNorm.Normalize(liUnchecked, "claudecode", false, false)

Chk("unchecked keeps canonical input",
    InStr(normUnchecked, '<input type="checkbox" disabled />'))
Chk("text Pending preserved", InStr(normUnchecked, "Pending"))
Chk("no placeholder (unchecked)", !InStr(normUnchecked, "¤CHK¤") && !InStr(normUnchecked, "¤UNCHK¤"))
Chk("direct unchecked canonical li", normUnchecked = '<ul><li><input type="checkbox" disabled /> Pending</li></ul>')

; ── 5: Task-list — <p>-wrapped <input> (ChatGPT style) ───────────────────────
Log("── 5: Task list — p-wrapped input (ChatGPT) ─────────")

liPWrapped := '<ul><li class="task-list-item"><p><input disabled="" type="checkbox" checked=""> Done</p></li></ul>'
normPWrapped := HtmlNorm.Normalize(liPWrapped, "chatgpt", false, false)

Chk("p-wrapped checked canonical input",
    InStr(normPWrapped, '<input type="checkbox" disabled checked />'))
Chk("p-wrapped text Done preserved", InStr(normPWrapped, "Done"))
Chk("no <p> remains",               !InStr(normPWrapped, "<p>"))
Chk("no placeholder (p-wrapped checked)", !InStr(normPWrapped, "¤CHK¤") && !InStr(normPWrapped, "¤UNCHK¤"))
Chk("p-wrapped checked canonical li", normPWrapped = '<ul><li><input type="checkbox" disabled checked /> Done</li></ul>')

liPUnchecked := '<ul><li class="task-list-item"><p><input disabled="" type="checkbox"> Not done</p></li></ul>'
normPUnchecked := HtmlNorm.Normalize(liPUnchecked, "chatgpt", false, false)

Chk("p-wrapped unchecked canonical input",
    InStr(normPUnchecked, '<input type="checkbox" disabled />'))
Chk("p-wrapped text Not done preserved", InStr(normPUnchecked, "Not done"))
Chk("no placeholder (p-wrapped unchecked)", !InStr(normPUnchecked, "¤CHK¤") && !InStr(normPUnchecked, "¤UNCHK¤"))
Chk("p-wrapped unchecked canonical li", normPUnchecked = '<ul><li><input type="checkbox" disabled /> Not done</li></ul>')

; ── 6: Task-list — non-task <li> not modified ─────────────────────────────────
Log("── 6: Task list — plain li not modified ────────────")

liPlain := '<ul><li>just a list item</li></ul>'
normPlain := HtmlNorm.Normalize(liPlain, "claudecode", false, false)
Chk("plain li unchanged",   normPlain = liPlain)

; ── 6b: Task-list — Claude Code todoItem/completed class shape ─────────────────
Log("── 6b: Task list — Claude Code todoItem/completed ─────────")

liTodoCompleted := '<ul><li class="todoItem_xheXVQ completed_xheXVQ">'
    . '<input type="checkbox" class="checkbox_xheXVQ" disabled="">'
    . '<div class="content_xheXVQ" style="text-decoration: line-through;">Fix DetectSource</div>'
    . '</li></ul>'
normTodoCompleted := HtmlNorm.Normalize(liTodoCompleted, "claudecode", false, false)
Chk("todoItem completed infers checked",
    normTodoCompleted = '<ul><li><input type="checkbox" disabled checked /> Fix DetectSource</li></ul>')

liTodoPending := '<ul><li class="todoItem_xheXVQ">'
    . '<input type="checkbox" class="checkbox_xheXVQ" disabled="">'
    . '<div class="content_xheXVQ">Refactor _NormalizeTaskListItems</div>'
    . '</li></ul>'
normTodoPending := HtmlNorm.Normalize(liTodoPending, "claudecode", false, false)
Chk("todoItem pending stays unchecked",
    normTodoPending = '<ul><li><input type="checkbox" disabled /> Refactor _NormalizeTaskListItems</li></ul>')
Chk("todoItem no placeholders",
    !InStr(normTodoCompleted, "¤CHK¤") && !InStr(normTodoCompleted, "¤UNCHK¤")
    && !InStr(normTodoPending, "¤CHK¤") && !InStr(normTodoPending, "¤UNCHK¤"))

; ── 7: Thinking block extraction ──────────────────────────────────────────────
Log("── 7: Thinking block extraction ─────────────────────")

htmlThink := '<p>Before</p>'
    . '<details class="thinking"><summary>Thinking</summary><p>inner thought</p></details>'
    . '<p>After</p>'
result := HtmlNorm.Normalize(htmlThink, "unknown", false, false)

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
Log("")
Log("Results: " passed " passed, " failed " failed")
ExitApp
