#ErrorStdOut
#Requires AutoHotkey v2.0
#Include ../HtmlParser.ahk
#Include test-helpers.ahk

_logPath := A_ScriptDir "\test-dom.log"
try FileDelete _logPath

passed := 0
failed := 0

; ── helpers ───────────────────────────────────────────────────────────────────

; Parse html, return root node (first top-level element).
Root(html) {
  nodes := HtmlParser.Parse(html)
  return nodes.Length > 0 ? nodes[1] : ""
}

; Collect tag names visited by Walk in order.
WalkTags(node) {
  tags := []
  node.Walk((n) => tags.Push(n.tag))
  return tags
}

; ── 1: Walk — pre-order depth-first ──────────────────────────────────────────
Log("── 1: Walk pre-order ───────────────────────────────")
r := Root("<a><b><c></c></b><d></d></a>")
tags := WalkTags(r)
Chk("visits 4 nodes",   tags.Length = 4,              tags.Length)
Chk("first = a",        tags.Length >= 1 && tags[1] = "a")
Chk("second = b",       tags.Length >= 2 && tags[2] = "b")
Chk("third = c",        tags.Length >= 3 && tags[3] = "c")
Chk("fourth = d",       tags.Length >= 4 && tags[4] = "d")

; ── 2: Walk — includes text nodes ────────────────────────────────────────────
Log("── 2: Walk includes text nodes ─────────────────────")
r := Root("<div>hello<span>world</span></div>")
tags := WalkTags(r)
; div → text("hello") → span → text("world") = 4 nodes
Chk("visits 4 nodes",   tags.Length = 4,              tags.Length)
Chk("first = div",      tags.Length >= 1 && tags[1] = "div")
Chk("second = text",    tags.Length >= 2 && tags[2] = "text")
Chk("third = span",     tags.Length >= 3 && tags[3] = "span")
Chk("fourth = text",    tags.Length >= 4 && tags[4] = "text")

; ── 3: FindAll — no match returns empty array ─────────────────────────────────
Log("── 3: FindAll no match ─────────────────────────────")
r := Root("<div><p></p></div>")
hits := r.FindAll((n) => n.tag = "span")
Chk("empty array",      hits.Length = 0,              hits.Length)

; ── 4: FindAll — returns all matching nodes ───────────────────────────────────
Log("── 4: FindAll multiple matches ─────────────────────")
r := Root("<ul><li></li><li></li><li></li></ul>")
hits := r.FindAll((n) => n.tag = "li")
Chk("3 matches",        hits.Length = 3,              hits.Length)

; ── 5: FindAll — includes self when self matches ──────────────────────────────
Log("── 5: FindAll includes self ────────────────────────")
r := Root("<p></p>")
hits := r.FindAll((n) => n.tag = "p")
Chk("length=1",         hits.Length = 1,              hits.Length)
Chk("is self",          hits.Length > 0 && hits[1].tag = "p")

; ── 6: FindFirst — no match returns "" ───────────────────────────────────────
Log("── 6: FindFirst no match ───────────────────────────")
r := Root("<div></div>")
hit := r.FindFirst((n) => n.tag = "span")
Chk("returns empty string", hit = "")

; ── 7: FindFirst — returns first match ───────────────────────────────────────
Log("── 7: FindFirst returns first ──────────────────────")
r := Root("<div><p id='a'></p><p id='b'></p></div>")
hit := r.FindFirst((n) => n.tag = "p")
Chk("found",            hit != "")
Chk("first p (id=a)",   hit != "" && hit.Attr("id") = "a",  hit != "" ? hit.Attr("id") : "")

; ── 8: RemoveChildren — removes matching direct children only ─────────────────
Log("── 8: RemoveChildren ───────────────────────────────")
r := Root("<div><p></p><span></span><p></p></div>")
r.RemoveChildren((n) => n.tag = "p")
Chk("1 child remains",  r.children.Length = 1,        r.children.Length)
Chk("kept span",        r.children.Length > 0 && r.children[1].tag = "span")

; ── 9: RemoveChildren — does not descend into children ───────────────────────
Log("── 9: RemoveChildren no recursion ─────────────────")
r := Root("<div><ul><li></li></ul></div>")
r.RemoveChildren((n) => n.tag = "li")   ; li is a grandchild, not direct child
Chk("ul preserved",     r.children.Length = 1 && r.children[1].tag = "ul")
Chk("li still inside",  r.children[1].children.Length = 1)

; ── 10: RemoveChildren — returns this for chaining ───────────────────────────
Log("── 10: RemoveChildren chaining ────────────────────")
r := Root("<div><p></p></div>")
ret := r.RemoveChildren((n) => n.tag = "p")
Chk("returns self",     ret = r)

; ── 11: Attr — default when absent ───────────────────────────────────────────
Log("── 11: Attr default ────────────────────────────────")
r := Root("<div></div>")
Chk("default empty",    r.Attr("class") = "")
Chk("custom default",   r.Attr("class", "fallback") = "fallback")

; ── 12: Attr — returns value when present ────────────────────────────────────
Log("── 12: Attr present ────────────────────────────────")
r := Root('<div class="foo" id="bar"></div>')
Chk("class=foo",        r.Attr("class") = "foo",      r.Attr("class"))
Chk("id=bar",           r.Attr("id")    = "bar",       r.Attr("id"))

; ── 13: SetAttr — sets value and returns this ────────────────────────────────
Log("── 13: SetAttr ─────────────────────────────────────")
r := Root("<div></div>")
ret := r.SetAttr("role", "main")
Chk("value set",        r.Attr("role") = "main",      r.Attr("role"))
Chk("returns self",     ret = r)

; ── 14: Void elements — bare <br> parsed as leaf node ────────────────────────
Log("── 14: Void element bare <br> ──────────────────────")
nodes := HtmlParser.Parse("<br>")
Chk("1 top-level node",  nodes.Length = 1,              nodes.Length)
Chk("tag = br",          nodes.Length >= 1 && nodes[1].tag = "br")
Chk("no children",       nodes.Length >= 1 && nodes[1].children.Length = 0)

; ── 15: Void elements — <br/> self-closing still works ───────────────────────
Log("── 15: Void element self-closing <br/> ─────────────")
nodes := HtmlParser.Parse("<br/>")
Chk("1 top-level node",  nodes.Length = 1,              nodes.Length)
Chk("tag = br",          nodes.Length >= 1 && nodes[1].tag = "br")

; ── 16: Void element inside container — siblings preserved ───────────────────
Log("── 16: <br> inside container ───────────────────────")
r := Root("<p>line1<br>line2</p>")
Chk("tag = p",           r != "" && r.tag = "p")
; p → text("line1") → br → text("line2")
Chk("3 children",        r != "" && r.children.Length = 3,   r != "" ? r.children.Length : "")
Chk("child[1] = text",   r.children.Length >= 1 && r.children[1].tag = "text")
Chk("child[2] = br",     r.children.Length >= 2 && r.children[2].tag = "br")
Chk("child[3] = text",   r.children.Length >= 3 && r.children[3].tag = "text")
Chk("text before br",    r.children.Length >= 1 && r.children[1].text = "line1")
Chk("text after br",     r.children.Length >= 3 && r.children[3].text = "line2")

; ── 17: Void element with attributes — attrs preserved ───────────────────────
Log("── 17: <img> with attributes ───────────────────────")
nodes := HtmlParser.Parse('<img src="cat.png" alt="a cat">')
Chk("1 top-level node",  nodes.Length = 1,              nodes.Length)
Chk("tag = img",         nodes.Length >= 1 && nodes[1].tag = "img")
Chk("src attr",          nodes.Length >= 1 && nodes[1].Attr("src") = "cat.png",  nodes.Length >= 1 ? nodes[1].Attr("src") : "")
Chk("alt attr",          nodes.Length >= 1 && nodes[1].Attr("alt") = "a cat",    nodes.Length >= 1 ? nodes[1].Attr("alt") : "")
Chk("no children",       nodes.Length >= 1 && nodes[1].children.Length = 0)

; ── 18: Void element — boolean attr (input[checked]) ─────────────────────────
Log("── 18: <input checked> boolean attr ───────────────")
nodes := HtmlParser.Parse('<input type="checkbox" checked>')
Chk("1 top-level node",  nodes.Length = 1,              nodes.Length)
Chk("tag = input",       nodes.Length >= 1 && nodes[1].tag = "input")
Chk("type attr",         nodes.Length >= 1 && nodes[1].Attr("type") = "checkbox")
Chk("checked attr",      nodes.Length >= 1 && nodes[1].attrs.Has("checked"))

; ── 19: Void element — snapshot stack survives multiple siblings ──────────────
Log("── 19: Multiple <br> siblings ──────────────────────")
r := Root("<div><br><br><br></div>")
Chk("tag = div",         r != "" && r.tag = "div")
Chk("3 children",        r != "" && r.children.Length = 3,   r != "" ? r.children.Length : "")
Chk("all br",            r.children.Length = 3
  && r.children[1].tag = "br"
  && r.children[2].tag = "br"
  && r.children[3].tag = "br")

; ── 20: Unknown unclosed tag throws ──────────────────────────────────────────
Log("── 20: Unclosed non-void throws ────────────────────")
threw := false
try HtmlParser.Parse("<div>no closing tag")
catch Error as e
  threw := true
Chk("throws Error",      threw)

; ── 21: DOM API — appendChild sets parent and returns appended node ───────────
Log("── 21: appendChild ─────────────────────────────────")
r := Root("<div></div>")
c := DomNode("p")
ret := r.appendChild(c)
Chk("returns appended node", ret = c)
Chk("child count",           r.children.Length = 1, r.children.Length)
Chk("child parent set",      IsObject(c.parent) && ObjPtr(c.parent) = ObjPtr(r))

; ── 22: DOM API — insertBefore and append fallback ────────────────────────────
Log("── 22: insertBefore ────────────────────────────────")
r := Root("<div><a></a><c></c></div>")
b := DomNode("b")
r.insertBefore(b, r.children[2])
Chk("order a,b,c",           r.children.Length = 3
  && r.children[1].tag = "a"
  && r.children[2].tag = "b"
  && r.children[3].tag = "c")
d := DomNode("d")
r.insertBefore(d) ; no reference => append
Chk("append on no ref",      r.children.Length = 4 && r.children[4].tag = "d")
Chk("insert parent set",     IsObject(b.parent) && ObjPtr(b.parent) = ObjPtr(r))

; ── 23: DOM API — removeChild detaches and returns removed node ───────────────
Log("── 23: removeChild ────────────────────────────────")
removed := r.removeChild(b)
Chk("returns removed node",  removed = b)
Chk("removed parent cleared", b.parent = "")
Chk("order after remove",    r.children.Length = 3
  && r.children[1].tag = "a"
  && r.children[2].tag = "c"
  && r.children[3].tag = "d")

; ── 24: DOM API — replaceChild swaps node and detaches old ────────────────────
Log("── 24: replaceChild ───────────────────────────────")
x := DomNode("x")
old := r.replaceChild(x, r.children[1])
Chk("returns old child",     old.tag = "a")
Chk("old parent cleared",    old.parent = "")
Chk("new parent set",        IsObject(x.parent) && ObjPtr(x.parent) = ObjPtr(r))
Chk("first is replacement",  r.children[1].tag = "x")

; ── 25: DOM API — childNodes/firstChild/lastChild/hasChildNodes ───────────────
Log("── 25: childNodes + first/last + hasChildNodes ─────")
Chk("childNodes alias",      ObjPtr(r.childNodes) = ObjPtr(r.children))
Chk("firstChild",            r.firstChild != "" && r.firstChild.tag = "x")
Chk("lastChild",             r.lastChild  != "" && r.lastChild.tag = "d")
Chk("hasChildNodes true",    r.hasChildNodes())
r.RemoveChildren((n) => true)
Chk("hasChildNodes false",   !r.hasChildNodes())
Chk("firstChild empty",      r.firstChild = "")
Chk("lastChild empty",       r.lastChild = "")

; ── summary ───────────────────────────────────────────────────────────────────
Log("")
Log("Results: " passed " passed, " failed " failed")
ExitApp
