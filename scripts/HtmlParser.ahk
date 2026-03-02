;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; HtmlParser — PCRE callout-based structural HTML parser
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

#Include HtmlDom.ahk

/**
 * Parses an HTML fragment into a flat array of top-level DomNode trees.
 *
 * Drives a PCRE recursive subroutine pattern with these callouts:
 *
 *   Regular tag path (first alternative of `(?<tag>...)`):
 *     `(?C:dom_snapshot_push)` — saves {dom,frames} lengths before each tag attempt
 *     `(?C:_HP_TagOpen)`       — fires after tag name, before attributes; pushes frame
 *     `(?C:_HP_Attr)`          — fires after each name=value (or boolean) attribute
 *     `(?C:_HP_Tag)`           — fires after matching `</tag>`; completes the node
 *
 *   Void-element fallback (second alternative, reached when first alt fails):
 *     `(?C:dom_reset)`          — peeks saved snapshot; restores _dom and _frames to
 *                                pre-attempt lengths, discarding side effects of the
 *                                failed first alt
 *     `(?C:_HP_TagOpen)`        — same as above; pushes a fresh frame for the bare tag
 *     `(?C:_HP_Tag_not_closed)` — completes the node; throws if tag is not a known
 *                                HTML void element
 *
 *   Both paths (fires at end of `(?<tag>...)` on any successful match):
 *     `(?C:dom_snapshot_pop)` — pops the saved snapshot
 *
 *   Text nodes:
 *     `(?C:_HP_Text)` — fires after each text chunk between tags
 *
 * Three shared stacks are maintained:
 *   `HtmlParser._dom`      — completed DomNode objects; returned when parsing finishes
 *   `HtmlParser._frames`   — one frame per open tag (name, attrs, childStart)
 *   `HtmlParser._snapshot` — {dom,frames} checkpoints pushed by `dom_snapshot_push`,
 *                            peeked+restored by `dom_reset`, popped by `dom_snapshot_pop`
 *
 * ## Pattern entry points
 *
 * The regex uses a `(?(DEFINE)...)` block to declare all subroutines without
 * matching, followed by `(?&tag)` as the sole entry point.  `RegExMatch` is
 * called in a loop so every top-level tag in the fragment is visited.
 *
 * @param {string} html - Raw HTML fragment to parse
 * @returns {Array} Flat array of top-level DomNode trees
 */
class HtmlParser {
  /** @type {Array} DomNode work-stack; top-level nodes accumulate here. */
  static _dom      := []

  /** @type {Array} Open-tag frame stack; each element is an Object. */
  static _frames   := []

  /**
   * Snapshot stack for void-element backtracking.
   * Each entry is `{dom: int, frames: int}` recording the _dom and _frames
   * lengths at the start of a `(?<tag>...)` attempt.
   * @type {Array}
   */
  static _snapshot := []

  /**
   * Known HTML void element names (elements that never have a closing tag).
   * @type {Map}
   */
  static _voidTags := Map(
    "area",1, "base",1, "br",1,    "col",1,   "embed",1,
    "hr",1,   "img",1,  "input",1, "link",1,  "meta",1,
    "param",1, "source",1, "track",1, "wbr",1
  )

  /**
   * PCRE pattern for recursive HTML tag matching.
   *
   * Subroutines (in DEFINE block):
   *   symbol   — valid XML/HTML name token (letters, digits, `_`, `-`)
   *   sq / dq  — single- or double-quoted string (including surrounding quotes)
   *   attr     — one attribute: name optionally followed by `=value`
   *   void_tag — void-element fallback: `dom_reset`, then match bare `<tag>`;
   *              captures the name into `(?<void_name>)` (distinct from
   *              `(?<tag_name>)` in `tag`) so that `\k<tag_name>` and
   *              `m["tag_name"]` in the outer `tag` call are never corrupted
   *   tag      — one element: opening tag, optional children, closing tag
   *              (or self-closing with `/>`, or delegates to `(?&void_tag)`)
   *
   * The `(?<tag>...)` subroutine opens with `< (?!/)` so that closing tags
   * (`</foo>`) never enter the pattern and never fire any callouts.
   * `dom_snapshot_push` fires after the `<` but before the tag name, so the
   * snapshot is always taken before any frame is pushed.  `dom_snapshot_pop`
   * fires at the end of the subroutine on any successful match (first or
   * second alternative); `dom_reset` peeks and restores state for the
   * `void_tag` attempt without consuming the snapshot.
   *
   * @type {string}
   */
  static _RE := "
  (
    xs)
    (?(DEFINE)

      (?<symbol>  [a-zA-Z_][a-zA-Z_\d\-]*+ )

      (?<sq>  '[^']*+' )
      (?<dq>  "[^"]*+" )

      (?<attr>
        (?<attr_name>  (?&symbol) )
        (?: \s*+ = \s*+ (?<attr_val> (?:(?&sq)|(?&dq)) ) )?+
        \s*+
        (?C:_HP_Attr)
      `)

      (?<void_tag> (?# void element fallback — entered when the first alt of tag fails )
        (?C:dom_reset)
        (?<void_name> (?&symbol) ) (?C:_HP_TagOpen) \s*+ (?&attr)*+ >
        (?C:_HP_Tag_not_closed)
      `)

      (?<tag> (?# assumes that the first character is a `<` )
        < (?!/)
        (?C:dom_snapshot_push)
        (?:
          (?<tag_name> (?&symbol) ) (?C:_HP_TagOpen) \s*+ (?&attr)*+ (?<closed>/)?+>
          (?(closed)
          | (?: (?<text_chunk>[^<]++) (?C:_HP_Text) | (?&tag) )*+
            </ \k<tag_name> >
          `)
          (?C:_HP_Tag)
        |
          (?&void_tag)
        `)
        (?C:dom_snapshot_pop)
      `)
    `)
    (?&tag)
  )"

  /**
   * Parses `html` and returns an array of top-level DomNode trees.
   * @param {string} html - Raw HTML fragment
   * @returns {Array} Top-level DomNode objects
   */
  static Parse(html) {
    HtmlParser._dom      := []
    HtmlParser._frames   := []
    HtmlParser._snapshot := []
    pos := 1
    while RegExMatch(html, HtmlParser._RE, &m, pos)
      pos := m.Pos + m.Len
    return HtmlParser._dom
  }

  /**
   * PCRE callout `(?C:_HP_TagOpen)`: fires after tag name, before attributes.
   * Pushes a new frame onto the frame stack.
   * @param {RegExMatchInfo} m - Match state at callout point
   */
  static _TagOpen(m, *) {
    HtmlParser._frames.Push({
      name:       m["void_name"] != "" ? m["void_name"] : m["tag_name"],
      attrs:      Map(),
      childStart: HtmlParser._dom.Length
    })
  }

  /**
   * PCRE callout `(?C:_HP_Attr)`: fires after each attribute (name[=value]).
   * Adds the attribute to the topmost frame.  Boolean attributes (no value)
   * are stored with an empty string value.
   * @param {RegExMatchInfo} m - Match state at callout point
   */
  static _Attr(m, *) {
    if (HtmlParser._frames.Length = 0)
      return
    frame   := HtmlParser._frames[HtmlParser._frames.Length]
    attrVal := m["attr_val"]
    ; Strip surrounding single/double quotes; empty for boolean attrs.
    if (attrVal != "")
      attrVal := SubStr(attrVal, 2, StrLen(attrVal) - 2)
    frame.attrs[m["attr_name"]] := attrVal
  }

  /**
   * PCRE callout `(?C:_HP_Text)`: fires after each raw text chunk between tags.
   * Pushes a `DomNode("text")` whose `text` field holds the matched string.
   * The node appears as a child of the enclosing element in document order.
   * @param {RegExMatchInfo} m - Match state at callout point
   */
  static _Text(m, *) {
    if (HtmlParser._frames.Length = 0)
      return
    HtmlParser._dom.Push(DomNode("text", "", m["text_chunk"]))
  }

  /**
   * PCRE callout `(?C:_HP_Tag)`: fires after tag content (or immediately for
   * self-closing tags).  Pops the current frame, harvests any DomNode children
   * that were pushed to `_dom` after the frame was opened, and pushes the
   * completed DomNode.
   * @param {RegExMatchInfo} m - Match state at callout point
   */
  static _Tag(m, *) {
    if (HtmlParser._frames.Length = 0)
      return
    frame := HtmlParser._frames.Pop()

    ; Harvest children: everything added to _dom after this frame opened.
    children := []
    while (HtmlParser._dom.Length > frame.childStart)
      children.InsertAt(1, HtmlParser._dom.Pop())

    node := DomNode(frame.name, frame.attrs)
    for child in children
      node.Add(child)
    HtmlParser._dom.Push(node)
  }

  /**
   * PCRE callout `(?C:dom_snapshot_push)`: fires after `<` (before tag name)
   * at the start of each `(?<tag>...)` attempt.  Records the current _dom and
   * _frames lengths so a failed first-alternative attempt can be rolled back.
   */
  static _DomSnapshotPush(*) {
    HtmlParser._snapshot.Push({
      dom:    HtmlParser._dom.Length,
      frames: HtmlParser._frames.Length
    })
  }

  /**
   * PCRE callout `(?C:dom_reset)`: fires at the start of the second
   * alternative when the first alternative has failed.  Peeks (does NOT pop)
   * the top snapshot and restores _dom and _frames to the lengths recorded
   * before this tag attempt began.  `dom_snapshot_pop` (at the end of
   * `(?<tag>...)`) owns the pop for successful matches; for a completely-failed
   * tag (both alts fail — only possible for `<!...>` style non-element tags
   * that pass `(?!/)`) the snapshot is left as a harmless 1-entry leak that
   * `Parse()` clears on the next call.
   */
  static _DomReset(*) {
    if (HtmlParser._snapshot.Length = 0)
      return
    s := HtmlParser._snapshot[HtmlParser._snapshot.Length]   ; peek — do NOT pop
    while (HtmlParser._dom.Length > s.dom)
      HtmlParser._dom.Pop()
    while (HtmlParser._frames.Length > s.frames)
      HtmlParser._frames.Pop()
  }

  /**
   * PCRE callout `(?C:dom_snapshot_pop)`: fires at the end of `(?<tag>...)`
   * after either alternative has matched successfully.  Pops the snapshot
   * pushed by `dom_snapshot_push`.
   */
  static _DomSnapshotPop(*) {
    if (HtmlParser._snapshot.Length > 0)
      HtmlParser._snapshot.Pop()
  }

  /**
   * PCRE callout `(?C:_HP_Tag_not_closed)`: fires after a bare `<tag>` with
   * no matching `</tag>` was matched by the second alternative.  Creates a
   * void DomNode (no children).  Throws if the tag name is not a known HTML
   * void element, since that indicates malformed HTML.
   * @param {RegExMatchInfo} m - Match state at callout point
   */
  static _TagNotClosed(m, *) {
    if (HtmlParser._frames.Length = 0)
      return
    frame := HtmlParser._frames.Pop()
    if !HtmlParser._voidTags.Has(frame.name)
      throw Error("HtmlParser: unclosed non-void element <" frame.name ">", -1)
    HtmlParser._dom.Push(DomNode(frame.name, frame.attrs))
  }
}

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Global shims — AHK resolves (?C:Name) callouts as global function lookups.
; These thin wrappers delegate to the HtmlParser static methods above.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

/** @param {RegExMatchInfo} m */
_HP_TagOpen(m, *)        => HtmlParser._TagOpen(m)
/** @param {RegExMatchInfo} m */
_HP_Attr(m, *)           => HtmlParser._Attr(m)
/** @param {RegExMatchInfo} m */
_HP_Tag(m, *)            => HtmlParser._Tag(m)
/** @param {RegExMatchInfo} m */
_HP_Text(m, *)           => HtmlParser._Text(m)
/** @param {RegExMatchInfo} m */
_HP_Tag_not_closed(m, *) => HtmlParser._TagNotClosed(m)
/** Snapshot push/reset/pop shims for void-element backtracking. */
dom_snapshot_push(m, *)  => HtmlParser._DomSnapshotPush(m)
/** @param {RegExMatchInfo} m */
dom_reset(m, *)          => HtmlParser._DomReset(m)
/** @param {RegExMatchInfo} m */
dom_snapshot_pop(m, *)   => HtmlParser._DomSnapshotPop(m)
