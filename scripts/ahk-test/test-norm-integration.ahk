#ErrorStdOut
#Requires AutoHotkey v2.0
#Include ../HtmlNorm.ahk
#Include test-helpers.ahk

_logPath := A_ScriptDir "\test-norm-integration.log"
try FileDelete _logPath

passed := 0
failed := 0

; Integration tests derived from PasteAsMd_*.log captures (2026-03-02).
; Tests marked [BUG] currently fail — they will pass after the corresponding fix.

; ── 1: DetectSource — real cfHtml patterns ────────────────────────────────────
Log("── 1: DetectSource — real cfHtml patterns ───────────────")

; Claude Code: extensionId=Anthropic.claude-code in vscode-webview SourceURL (AI-only selection)
cfCC := "Version:0.9`r`nSourceURL:vscode-webview://x/?extensionId=Anthropic.claude-code&platform=electron`r`n"
    . "<div>"
Chk("CC: Anthropic.claude-code extensionId → claudecode (no content_xGDvVg needed)",
    DetectSource(cfCC) = "claudecode")

; Claude Code: also correct when content_xGDvVg is present (user+AI selection)
cfCC2 := "Version:0.9`r`nSourceURL:vscode-webview://x/?extensionId=Anthropic.claude-code&platform=electron`r`n"
    . "<div class=`"content_xGDvVg`">"
Chk("CC: Anthropic.claude-code + content_xGDvVg → claudecode",
    DetectSource(cfCC2) = "claudecode")

; Codex: extensionId=openai.chatgpt-0.4.79-win32-x64
cfCX := "Version:0.9`r`nSourceURL:vscode-webview://x/?extensionId=openai.chatgpt-0.4.79-win32-x64&platform=electron`r`n"
    . "<div>"
Chk("CX: extensionId=openai.chatgpt-* → codex",
    DetectSource(cfCX) = "codex")

; Claude Web (browser): no extensionId in header; detected from HTML content signals
cfCW := "Version:0.9`r`nStartHTML:0000000105`r`nEndHTML:0000017536`r`n"
    . "<html><body><!--StartFragment--><div class=`"font-claude-response`">hi</div><!--EndFragment--></body></html>"
Chk("CW: no extensionId + font-claude-response → claudeweb",
    DetectSource(cfCW) = "claudeweb")

cfCW2 := "Version:0.9`r`nStartHTML:0000000105`r`nEndHTML:0000017536`r`n"
    . "<html><body><!--StartFragment--><pre class=`"code-block__code`"></pre><!--EndFragment--></body></html>"
Chk("CW: no extensionId + code-block__code → claudeweb",
    DetectSource(cfCW2) = "claudeweb")

; ChatGPT article copy (full turn): has data-turn-id on <article>
cfGP_article := "Version:0.9`r`n<html><body><article data-turn-id=`"e7e18cd8-1234-5678-abcd-ef0123456789`">"
Chk("GP article: data-turn-id → chatgpt",
    DetectSource(cfGP_article) = "chatgpt")

; ChatGPT sub-selection (no <article>): no data-turn-id, but has overflow-visible!
; [BUG] Currently returns "unknown" — DetectSource must also check overflow-visible!
cfGP_sub := "Version:0.9`r`n<html><body>"
    . "<pre class=`"overflow-visible! px-0!`" data-start=`"175`" data-end=`"256`">"
    . "<div class=`"cm-content`">code</div></pre></body></html>"
Chk("GP sub-selection: overflow-visible! → chatgpt",
    DetectSource(cfGP_sub) = "chatgpt")

; ── 2: Claude Code code block (native pre/code with button wrapper) ───────────
Log("── 2: Claude Code code block (with button wrapper) ──────")

; Simplified from PasteAsMd_ClaudeCode.log: codeBlockWrapper div + button + pre/code
ccCode := '<div class="codeBlockWrapper_-a7MRw" style="position: relative;">'
    . '<button class="copyButton_CEmTFw" aria-label="Copy code to clipboard">Copy</button>'
    . '<pre style="overflow-x: auto; white-space: pre;">'
    . '<code class="language-python" style="font-family: monospace;">def greet(name):`n'
    . '    return f"Hello, {name}!"`n</code></pre></div>'
normCC := HtmlNorm.Normalize(ccCode, "claudecode", false, false)
Chk("CC code: language-python preserved",   InStr(normCC, "language-python"))
Chk("CC code: pre/code block present",      InStr(normCC, "<pre"))
Chk("CC code: def greet preserved",         InStr(normCC, "def greet"))
Chk("CC code: button stripped",             !InStr(normCC, "<button"))

; ── 3: Codex code block (code.whitespace-pre! with hljs spans, real structure) ─
Log("── 3: Codex code block (whitespace-pre! + hljs spans) ───")

; From PasteAsMd_Codex.log: two-div wrapper, code.whitespace-pre!, hljs-* span children.
; The <code> class is "whitespace-pre!" not "hljs" — confirmed from real log.
; No <pre> wrapper around <code> — it's inside <div class="text-size-chat p-2">.
cxCode := '<div class="bg-token-text-code-block-background relative overflow-clip rounded-lg" data-theme="dark">'
    . '<div class="text-size-chat overflow-y-auto p-2" dir="ltr">'
    . '<code class="whitespace-pre!" style="font-family: monospace;">'
    . '<span><span class="hljs-keyword">def</span></span><span> </span>'
    . '<span><span class="hljs-title function_">greet</span></span>'
    . '<span>(name):`n'
    . '    message = </span><span><span class="hljs-string">"Hello"</span></span><span>`n'
    . '`n    </span><span><span class="hljs-keyword">return</span></span><span> message`n</span>'
    . '</code></div></div>'
normCX := HtmlNorm.Normalize(cxCode, "codex", false, false)
Chk("CX code: produces pre/code block",     InStr(normCX, "<pre><code>"))
Chk("CX code: def greet preserved",         InStr(normCX, "def greet"))
Chk("CX code: return preserved",            InStr(normCX, "return"))
Chk("CX code: hljs-keyword spans stripped", !InStr(normCX, "hljs-keyword"))
Chk("CX code: div wrapper removed",         !InStr(normCX, "text-size-chat"))

; ── 4: Task list — Claude Code (input with disabled/style attrs + span child) ──
Log("── 4: Task list — Claude Code (real input attrs) ─────────")

; Exact pattern from PasteAsMd_ClaudeCode.log line 89:
;   <input type="checkbox" disabled="" checked="" style="appearance: none; ...">
;   <span> </span>Checked item
ccLiChk := '<li class="task-list-item">'
    . '<input type="checkbox" disabled="" checked="" style="appearance: none; border-color: rgb(69, 69, 69); border-style: solid;">'
    . '<span> </span>Checked item</li>'
ccLiUnchk := '<li class="task-list-item">'
    . '<input type="checkbox" disabled="" style="appearance: none; border-color: rgb(69, 69, 69); border-style: solid;">'
    . '<span> </span>Unchecked item</li>'
normCCLi := HtmlNorm._NormalizeTaskListItems(ccLiChk . ccLiUnchk)
Chk("CC tasklist: checked canonical input",
    InStr(normCCLi, '<input type="checkbox" disabled checked />'))
Chk("CC tasklist: unchecked canonical input",
    InStr(normCCLi, '<input type="checkbox" disabled />'))
Chk("CC tasklist: Checked item preserved",  InStr(normCCLi, "Checked item"))
Chk("CC tasklist: Unchecked item preserved", InStr(normCCLi, "Unchecked item"))
Chk("CC tasklist: no placeholder markers",
    !InStr(normCCLi, "¤CHK¤") && !InStr(normCCLi, "¤UNCHK¤"))
Chk("CC tasklist: no leading space in text",
    !RegExMatch(normCCLi, "i)checked>\s{2,}"))

; ── 4b: Task list — Claude Code todo tool rows (todoItem_/completed_) ──────────
Log("── 4b: Task list — Claude Code todo tool rows ───────────")

ccTodoChk := '<li class="todoItem_xheXVQ completed_xheXVQ"'
    . ' style="display: flex; opacity: 0.7;">'
    . '<input type="checkbox" class="checkbox_xheXVQ" disabled=""'
    . ' style="appearance: none;">'
    . '<div class="content_xheXVQ" style="text-decoration: line-through;">'
    . 'Fix DetectSource — ClaudeCode detected as claudeweb</div></li>'
ccTodoUnchk := '<li class="todoItem_xheXVQ" style="display: flex;">'
    . '<input type="checkbox" class="checkbox_xheXVQ" disabled=""'
    . ' style="appearance: none;">'
    . '<div class="content_xheXVQ">Fix [img] → ![alt](src)</div></li>'
normCCTodo := HtmlNorm._NormalizeTaskListItems(ccTodoChk . ccTodoUnchk)
Chk("CC todo rows: completed_* infers checked",
    InStr(normCCTodo, '<li><input type="checkbox" disabled checked /> Fix DetectSource — ClaudeCode detected as claudeweb</li>'))
Chk("CC todo rows: non-completed stays unchecked",
    InStr(normCCTodo, '<li><input type="checkbox" disabled /> Fix [img] → ![alt](src)</li>'))
Chk("CC todo rows: no placeholders",
    !InStr(normCCTodo, "¤CHK¤") && !InStr(normCCTodo, "¤UNCHK¤"))

; ── 5: Task list — ChatGPT (p-wrapped input, from real log) ───────────────────
Log("── 5: Task list — ChatGPT p-wrapped (real HTML) ──────────")

; Exact pattern from PasteAsMd_ChatGPT.log lines 136-141:
;   <li class="task-list-item" data-start="367" data-end="377">
;     <p data-start="373" data-end="377"><input disabled="" type="checkbox" checked=""> Done</p>
;   </li>
gpLiChk := '<li class="task-list-item" data-start="367" data-end="377">`n'
    . '<p data-start="373" data-end="377"><input disabled="" type="checkbox" checked=""> Done</p>`n'
    . '</li>'
gpLiUnchk := '<li class="task-list-item" data-start="378" data-end="392">`n'
    . '<p data-start="384" data-end="392"><input disabled="" type="checkbox"> Not done</p>`n'
    . '</li>'
normGPLi := HtmlNorm._NormalizeTaskListItems(gpLiChk . gpLiUnchk)
Chk("GP tasklist: p-wrapped checked canonical input",
    InStr(normGPLi, '<input type="checkbox" disabled checked />'))
Chk("GP tasklist: p-wrapped unchecked canonical input",
    InStr(normGPLi, '<input type="checkbox" disabled />'))
Chk("GP tasklist: Done text preserved",             InStr(normGPLi, "Done"))
Chk("GP tasklist: Not done text preserved",         InStr(normGPLi, "Not done"))
Chk("GP tasklist: no <p> wrapper remains",          !InStr(normGPLi, "<p"))
Chk("GP tasklist: no placeholder markers",
    !InStr(normGPLi, "¤CHK¤") && !InStr(normGPLi, "¤UNCHK¤"))

; ── 6: Footnote href — Claude Code (real vscode-webview URL) ─────────────────
Log("── 6: Footnote href stripping (Claude Code real URL) ─────")

; Full href from PasteAsMd_ClaudeCode.log line 89 (abbreviated)
ccFnHtml := '<a href="vscode-webview://0pm70dm6f6pdq82ubcl5vmtd4vl8j7343vu35t01f6njt6fk22pm/index.html'
    . '?id=c806bd70-aac3-42dd-bf5a-0dda09c96e6f&amp;extensionId=Anthropic.claude-code'
    . '#user-content-fn-1" target="_blank">1</a>'
normCCFn := RegExReplace(ccFnHtml, "i)href=`"[^`"]*#(user-content-[^`"]*)`"", "href=`"#$1`"")
Chk("CC footnote: long vscode-webview href → #user-content-fn-1",
    InStr(normCCFn, 'href="#user-content-fn-1"'))

; ── 7: Footnote href — Codex (file+.vscode-resource URL) ─────────────────────
Log("── 7: Footnote href stripping (Codex file+ URL) ───────────")

; From PasteAsMd_Codex.log
cxFnHtml := '<a href="https://file+.vscode-resource.vscode-cdn.net/c%3A/Users/adria'
    . '/.vscode/extensions/openai.chatgpt-0.4.79-win32-x64/webview/#user-content-fn-note"'
    . ' target="_blank">1</a>'
normCXFn := RegExReplace(cxFnHtml, "i)href=`"[^`"]*#(user-content-[^`"]*)`"", "href=`"#$1`"")
Chk("CX footnote: file+ URL → #user-content-fn-note",
    InStr(normCXFn, 'href="#user-content-fn-note"'))

; ── 8: ChatGPT _NormalizeChatGptCodeBlocks — <br> line-break handling ─────────
Log("── 8: ChatGPT code block — br line breaks ─────────────────")

; Real pattern from PasteAsMd_ChatGPT.log line 132:
;   <pre class="overflow-visible! px-0!">
;     <div class="cm-content q9tKkq_readonly">
;       <span class="ͼv">def</span><span> </span><span class="ͼ11">greet</span><span>(name):</span>
;       <br><span>  </span><span class="ͼv">return</span> <span class="ͼz">"hi"</span>
;     </div>
;   </pre>
gpCodeRaw := '<pre class="overflow-visible! px-0!" data-start="175">'
    . '<div class="relative w-full"><div class="cm-content q9tKkq_readonly">'
    . '<span class="ͼv">def</span><span> </span><span class="ͼ11">greet</span><span>(name):</span><br>'
    . '<span>  </span><span class="ͼv">return</span><span> </span><span class="ͼz">"hi"</span>'
    . '</div></div></pre>'
normGPCode := HtmlNorm._NormalizeChatGptCodeBlocks(gpCodeRaw)
Chk("GP code: overflow-visible! class gone",   !InStr(normGPCode, "overflow-visible"))
Chk("GP code: canonical pre/code emitted",     InStr(normGPCode, "<pre><code>"))
Chk("GP code: def greet preserved",            InStr(normGPCode, "def greet"))
Chk("GP code: return hi preserved",            InStr(normGPCode, "return") && InStr(normGPCode, "hi"))
Chk("GP code: multi-line (newline present)",
    InStr(normGPCode, "def greet(name):" . Chr(10)))

; ── 9: Claude Web code block (div wrapper around pre/code) ────────────────────
Log("── 9: Claude Web code block (div-wrapped pre/code) ────────")

; From PasteAsMd_ClaudeWeb.log htmlPrep line 282:
;   <div class="relative group/copy bg-bg-000/50 ...">
;     <div class="sticky ..."><div class="absolute ..."></div></div>
;     <div class="overflow-x-auto">
;       <pre><code class="language-python">...</code></pre>
;     </div>
;   </div>
cwCode := '<div class="relative group/copy bg-bg-000/50 border-0.5 border-border-400 rounded-lg">'
    . '<div class="sticky opacity-0 top-2 py-2 h-12 w-0 float-right">'
    . '<div class="absolute right-0 h-8 px-2 items-center inline-flex z-10"></div>'
    . '</div>'
    . '<div class="overflow-x-auto">'
    . '<pre><code class="language-python">def hello_world():`n    print("Hello, World!")`n`nhello_world()</code></pre>'
    . '</div></div>'
normCW := HtmlNorm.Normalize(cwCode, "claudeweb", false, false)
Chk("CW code: language-python preserved",   InStr(normCW, "language-python"))
Chk("CW code: def hello_world preserved",   InStr(normCW, "def hello_world"))
Chk("CW code: pre/code block present",      InStr(normCW, "<pre"))
Chk("CW code: outer wrapper div stripped",  !InStr(normCW, "group/copy"))
Chk("CW code: sticky overlay div stripped", !InStr(normCW, "sticky"))
Chk("CW code: overflow-x-auto div stripped",!InStr(normCW, "overflow-x-auto"))

; ── 10: Post-pandoc fence-space fix ──────────────────────────────────────────
Log("── 10: Post-pandoc fence-space fix ─────────────────────")

; Pandoc GFM outputs "``` python" (space between fence and language).
; The fix: RegExReplace(mdRaw, "m)^(``+) (\S)", "$1$2")
bt := Chr(96)  ; backtick — avoids AHK string-escape fights with ` chars
fence3 := bt bt bt
fence4 := bt bt bt bt

; Basic: 3-backtick fence with language
mdFence3 := fence3 " python`ndef foo():`n    pass`n" fence3
fixed3 := RegExReplace(mdFence3, "m)^(``+) (\S)", "$1$2")
Chk("fence-space 3bt: ``` python → ```python",  SubStr(fixed3, 1, 9) = fence3 "python")
Chk("fence-space 3bt: body unchanged",           InStr(fixed3, "def foo"))
Chk("fence-space 3bt: no space after fence",     !RegExMatch(fixed3, "m)^``+ \S"))

; 4-backtick fence (wider fence)
mdFence4 := fence4 " javascript`nconsole.log(1)`n" fence4
fixed4 := RegExReplace(mdFence4, "m)^(``+) (\S)", "$1$2")
Chk("fence-space 4bt: ```` javascript → ````javascript", SubStr(fixed4, 1, 14) = fence4 "javascript")

; Fence with NO language must be unchanged
mdNoLang := fence3 "`ndef foo()`n" fence3
fixedNL := RegExReplace(mdNoLang, "m)^(``+) (\S)", "$1$2")
Chk("fence-space: no-language fence unchanged",  fixedNL = mdNoLang)

; ── 11: Poster placeholder source isolation ───────────────────────────────────
Log("── 11: Poster placeholder source isolation ──────────────")

; ChatGPT articles contain inner divs with Codex-like classes.
; With source="chatgpt", only ChatGPT article patterns should fire —
; the Codex flex-col / min-w-0 patterns must NOT inject spurious markers.
gpHtml := "<article data-turn=`"assistant`"><div class=`"group min-w-0 flex-col`"><div class=`"flex-col items-end`"><p>Hello</p></div></div></article>"
    . "<article data-turn=`"user`"><div class=`"group min-w-0 flex-col`"><p>Hi</p></div></article>"
normGP := HtmlNorm._InjectPosterPlaceholders(gpHtml, "chatgpt")
; Each article should get exactly one marker
Chk("GP poster: AI article gets ¤POSTER_AI¤",       InStr(normGP, "¤POSTER_AI¤"))
Chk("GP poster: user article gets ¤POSTER_User¤",   InStr(normGP, "¤POSTER_User¤"))
; Codex class patterns must NOT fire on inner divs (would produce extra markers)
markerCount := 0
pos := 1
while (pos := InStr(normGP, "¤POSTER_", , pos)) {
    markerCount++
    pos++
}
Chk("GP poster: exactly 2 markers (no Codex leakage)", markerCount = 2)

; Conversely, Codex source with Codex-class divs should produce 2 markers
cxHtml := "<div class=`"group min-w-0 flex-col`"><p>AI reply</p></div>"
    . "<div class=`"flex-col items-end`"><p>User msg</p></div>"
normCX := HtmlNorm._InjectPosterPlaceholders(cxHtml, "codex")
Chk("CX poster: AI div gets ¤POSTER_AI¤",   InStr(normCX, "¤POSTER_AI¤"))
Chk("CX poster: user div gets ¤POSTER_User¤", InStr(normCX, "¤POSTER_User¤"))

; Claude Code source must not fire Codex or ChatGPT patterns
ccHtml := "<div data-testid=`"assistant-message`"><p>Answer</p></div>"
    . "<div class=`"message_abc userMessageContainer_xyz`"><p>Question</p></div>"
normCC := HtmlNorm._InjectPosterPlaceholders(ccHtml, "claudecode")
Chk("CC poster: AI container gets ¤POSTER_AI¤",   InStr(normCC, "¤POSTER_AI¤"))
Chk("CC poster: user container gets ¤POSTER_User¤", InStr(normCC, "¤POSTER_User¤"))
ccCount := 0
pos := 1
while (pos := InStr(normCC, "¤POSTER_", , pos)) {
    ccCount++
    pos++
}
Chk("CC poster: exactly 2 markers", ccCount = 2)

; ── 12: User message extraction — Claude Web and ChatGPT ─────────────────────
Log("── 12: User message extraction (Claude Web + ChatGPT) ───")

; Claude Web: <p class="whitespace-pre-wrap break-words"> with embedded newlines
HtmlNorm._userMsgBlocks := []
cwUserHtml := "<div data-testid=`"user-message`">"
    . "<p class=`"whitespace-pre-wrap break-words`">Line one`nLine two`nLine three</p>"
    . "</div>"
cwUserOut := HtmlNorm._ExtractUserMessages(cwUserHtml)
Chk("CW usermsg: placeholder injected",      InStr(cwUserOut, "¤USERMSG_1¤"))
Chk("CW usermsg: 1 block stored",            HtmlNorm._userMsgBlocks.Length = 1)
Chk("CW usermsg: newlines preserved",        InStr(HtmlNorm._userMsgBlocks[1], "`n"))
Chk("CW usermsg: text content correct",      HtmlNorm._userMsgBlocks[1] = "Line one`nLine two`nLine three")

; ChatGPT: <div class="whitespace-pre-wrap"> (exact sole class)
HtmlNorm._userMsgBlocks := []
gpUserHtml := "<article data-turn-id=`"abc-123`">"
    . "<div class=`"whitespace-pre-wrap`">Hello`nWorld</div>"
    . "</article>"
gpUserOut := HtmlNorm._ExtractUserMessages(gpUserHtml)
Chk("GP usermsg: placeholder injected",      InStr(gpUserOut, "¤USERMSG_1¤"))
Chk("GP usermsg: 1 block stored",            HtmlNorm._userMsgBlocks.Length = 1)
Chk("GP usermsg: newlines preserved",        InStr(HtmlNorm._userMsgBlocks[1], "`n"))
Chk("GP usermsg: text content correct",      HtmlNorm._userMsgBlocks[1] = "Hello`nWorld")

; Codex's "text-size-chat whitespace-pre-wrap" must NOT be matched by ChatGPT block
HtmlNorm._userMsgBlocks := []
cxStillHtml := "<div class=`"text-size-chat whitespace-pre-wrap`">CX msg</div>"
cxStillOut := HtmlNorm._ExtractUserMessages(cxStillHtml)
Chk("CX usermsg: not re-extracted by ChatGPT pattern after Codex extraction",
    !InStr(SubStr(cxStillOut, InStr(cxStillOut, "¤USERMSG_") + 10), "¤USERMSG_"))

; ── summary ───────────────────────────────────────────────────────────────────
Log("")
Log("Results: " passed " passed, " failed " failed")
ExitApp
