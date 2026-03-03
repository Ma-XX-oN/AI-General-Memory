#ErrorStdOut
#Requires AutoHotkey v2.0
#Include ../HtmlParser.ahk
#Include test-helpers.ahk

_logPath := A_ScriptDir "\test-parser.log"
try FileDelete _logPath

passed := 0
failed := 0

; ── 1: single bare element ───────────────────────────────────────────────────
Log("── 1: single bare element ──────────────────────────")
n := HtmlParser.Parse("<p></p>")
Chk("length=1",     n.Length = 1)
Chk("tag=p",        n.Length > 0 && n[1].tag = "p")
Chk("attrs empty",  n.Length > 0 && n[1].attrs.Count = 0)

; ── 2: element with attrs ────────────────────────────────────────────────────
Log("── 2: element with attrs ───────────────────────────")
n := HtmlParser.Parse('<div class="foo" id="bar"></div>')
Chk("length=1",       n.Length = 1)
Chk("class=foo",      n.Length > 0 && n[1].Attr("class") = "foo",  n.Length > 0 ? n[1].Attr("class") : "")
Chk("id=bar",         n.Length > 0 && n[1].Attr("id")    = "bar",  n.Length > 0 ? n[1].Attr("id")    : "")

; ── 3: self-closing ──────────────────────────────────────────────────────────
Log("── 3: self-closing ─────────────────────────────────")
n := HtmlParser.Parse("<br/>")
Chk("length=1",       n.Length = 1)
Chk("tag=br",         n.Length > 0 && n[1].tag = "br")
Chk("no children",    n.Length > 0 && n[1].children.Length = 0)

; ── 4: nested elements ───────────────────────────────────────────────────────
Log("── 4: nested elements ──────────────────────────────")
n := HtmlParser.Parse("<div><p></p><span></span></div>")
Chk("1 root",         n.Length = 1)
Chk("2 children",     n.Length > 0 && n[1].children.Length = 2,   n.Length > 0 ? n[1].children.Length : "")
Chk("child1=p",       n.Length > 0 && n[1].children.Length >= 1 && n[1].children[1].tag = "p")
Chk("child2=span",    n.Length > 0 && n[1].children.Length >= 2 && n[1].children[2].tag = "span")

; ── 5: multiple roots ────────────────────────────────────────────────────────
Log("── 5: multiple roots ───────────────────────────────")
n := HtmlParser.Parse("<p></p><div></div>")
Chk("length=2",       n.Length = 2)
Chk("first=p",        n.Length >= 1 && n[1].tag = "p")
Chk("second=div",     n.Length >= 2 && n[2].tag = "div")

; ── 6: boolean attr ──────────────────────────────────────────────────────────
Log("── 6: boolean attr ─────────────────────────────────")
n := HtmlParser.Parse("<input type='checkbox' checked>")
Chk("length=1",       n.Length = 1)
Chk("type=checkbox",  n.Length > 0 && n[1].Attr("type") = "checkbox",  n.Length > 0 ? n[1].Attr("type") : "")
Chk("checked present",n.Length > 0 && n[1].attrs.Has("checked"))

; ── 7: data-* attr ───────────────────────────────────────────────────────────
Log("── 7: data-* attr ──────────────────────────────────")
n := HtmlParser.Parse('<div data-testid="msg"></div>')
Chk("length=1",       n.Length = 1)
Chk("data-testid=msg",n.Length > 0 && n[1].Attr("data-testid") = "msg",  n.Length > 0 ? n[1].Attr("data-testid") : "")

; ── 8: self-closing with attrs ───────────────────────────────────────────────
Log("── 8: self-closing with attrs ──────────────────────")
n := HtmlParser.Parse('<img src="x.png" alt="pic"/>')
Chk("length=1",       n.Length = 1)
Chk("tag=img",        n.Length > 0 && n[1].tag = "img")
Chk("src=x.png",      n.Length > 0 && n[1].Attr("src") = "x.png")
Chk("alt=pic",        n.Length > 0 && n[1].Attr("alt") = "pic")

; ── 9: deep nesting ──────────────────────────────────────────────────────────
Log("── 9: deep nesting ─────────────────────────────────")
n := HtmlParser.Parse("<a><b><c></c></b></a>")
Chk("root=a",         n.Length > 0 && n[1].tag = "a")
Chk("child=b",        n.Length > 0 && n[1].children.Length > 0 && n[1].children[1].tag = "b")
Chk("grandchild=c",   n.Length > 0 && n[1].children.Length > 0 && n[1].children[1].children.Length > 0 && n[1].children[1].children[1].tag = "c")

; ── 10: mixed text and elements ──────────────────────────────────────────────
Log("── 10: mixed text and elements ─────────────────────")
n := HtmlParser.Parse("<div>hello<p>world</p>end</div>")
Chk("1 root",         n.Length = 1)
Chk("3 children",     n.Length > 0 && n[1].children.Length = 3,   n.Length > 0 ? n[1].children.Length : "")
Chk("child1=text",    n.Length > 0 && n[1].children.Length >= 1 && n[1].children[1].tag = "text")
Chk("text=hello",     n.Length > 0 && n[1].children.Length >= 1 && n[1].children[1].text = "hello")
Chk("child2=p",       n.Length > 0 && n[1].children.Length >= 2 && n[1].children[2].tag = "p")
Chk("child3=text",    n.Length > 0 && n[1].children.Length >= 3 && n[1].children[3].tag = "text")
Chk("text=end",       n.Length > 0 && n[1].children.Length >= 3 && n[1].children[3].text = "end")

; ── 11: mismatched close tag throws ──────────────────────────────────────────
Log("── 11: mismatched close tag throws ─────────────────")
threw := false
try HtmlParser.Parse("<div></span>")
catch Error as e
  threw := true
Chk("throws Error",    threw)

; ── 12: unquoted attributes are parsed ───────────────────────────────────────
Log("── 12: unquoted attributes ─────────────────────────")
n := HtmlParser.Parse("<input type=checkbox value=foo-bar checked>")
Chk("length=1",        n.Length = 1)
Chk("tag=input",       n.Length > 0 && n[1].tag = "input")
Chk("type=checkbox",   n.Length > 0 && n[1].Attr("type") = "checkbox", n.Length > 0 ? n[1].Attr("type") : "")
Chk("value=foo-bar",   n.Length > 0 && n[1].Attr("value") = "foo-bar", n.Length > 0 ? n[1].Attr("value") : "")
Chk("checked present", n.Length > 0 && n[1].attrs.Has("checked"))

; ── 13: unquoted attributes on normal tag ────────────────────────────────────
Log("── 13: unquoted attributes on normal tag ───────────")
n := HtmlParser.Parse("<div class=foo data-id=abc123></div>")
Chk("length=1",        n.Length = 1)
Chk("tag=div",         n.Length > 0 && n[1].tag = "div")
Chk("class=foo",       n.Length > 0 && n[1].Attr("class") = "foo", n.Length > 0 ? n[1].Attr("class") : "")
Chk("data-id=abc123",  n.Length > 0 && n[1].Attr("data-id") = "abc123", n.Length > 0 ? n[1].Attr("data-id") : "")

; ── summary ──────────────────────────────────────────────────────────────────
Log("")
Log("Results: " passed " passed, " failed " failed")
ExitApp
