;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; HtmlDom — General-purpose tree node for parsed HTML
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

/**
 * General-purpose tree node representing a parsed unit of chat HTML.
 *
 * Each node has a semantic tag name, an attribute map, an array of child
 * nodes, and a text/HTML content string.  This structure is source-agnostic:
 * per-source parsers produce DomNode trees, universal transforms walk and
 * mutate those trees, and the emitter converts the final tree to canonical
 * HTML for pandoc.
 *
 * ## Defined tag names
 *
 * **Root**
 * - `"chat"` — root node; children are `"turn"` nodes.
 *
 * **Turn-level**
 * - `"turn"` — one message turn.
 *   - attr `role` {string} `"user"` or `"ai"`
 *   - children: block nodes
 *
 * **Block-level**
 * - `"text"` — raw HTML fragment passed through to pandoc.
 *   - `text` {string} raw HTML
 * - `"code"` — fenced code block.
 *   - attr `lang` {string} language identifier, or `""` when unknown
 *   - `text` {string} plain-text source code
 * - `"task-list"` — GFM task list.
 *   - children: `"task-item"` nodes
 * - `"task-item"` — single task-list entry.
 *   - attr `checked` {string} `"1"` if checked, `"0"` otherwise
 *   - `text` {string} plain-text item label
 * - `"user-msg"` — user message text extracted before pandoc to preserve
 *   line structure.
 *   - `text` {string} plain text (may contain backtick inline code)
 * - `"thinking"` — Claude thinking block.
 *   - `text` {string} plain text
 * - `"poster"` — speaker label placeholder (injected when SHOW_POSTER is on).
 *   - attr `role` {string} `"user"` or `"ai"`
 */
class DomNode {
  /** @type {string} Semantic tag name. */
  tag := ""

  /** @type {Map} Arbitrary key-value attributes. */
  attrs := Map()

  /** @type {Array} Child DomNode objects. */
  children := []

  /** @type {string} Text or raw HTML content of this node. */
  text := ""

  /**
   * @param {string} tag   - Semantic tag name (see class doc for defined tags).
   * @param {Map}    attrs - Attribute map; pass `""` or omit for no attrs.
   * @param {string} text  - Text/HTML content; defaults to `""`.
   */
  __New(tag, attrs := "", text := "") {
    this.tag   := tag
    this.text  := text
    this.attrs := (Type(attrs) = "Map") ? attrs : Map()
  }

  /**
   * Appends a child node and returns this node for chaining.
   * @param {DomNode} child
   * @returns {DomNode} this
   */
  Add(child) {
    this.children.Push(child)
    return this
  }

  /**
   * Returns the value of a named attribute, or `default` when absent.
   * @param {string} name
   * @param {string} default
   * @returns {string}
   */
  Attr(name, default := "") {
    return this.attrs.Has(name) ? this.attrs[name] : default
  }

  /**
   * Sets a named attribute and returns this node for chaining.
   * @param {string} name
   * @param {string} value
   * @returns {DomNode} this
   */
  SetAttr(name, value) {
    this.attrs[name] := value
    return this
  }

  /**
   * Calls `fn(node)` on this node and every descendant, pre-order
   * depth-first.  Does not support early exit; use FindFirst for that.
   * @param {Func} fn - Callback receiving each DomNode.
   */
  Walk(fn) {
    fn(this)
    for child in this.children
      child.Walk(fn)
  }

  /**
   * Returns an array of all nodes in the subtree (including self) for which
   * `pred(node)` is truthy.
   * @param {Func} pred - Predicate receiving a DomNode.
   * @returns {Array}
   */
  FindAll(pred) {
    result := []
    this.Walk((n) => pred(n) ? result.Push(n) : 0)
    return result
  }

  /**
   * Returns the first node in the subtree (including self) for which
   * `pred(node)` is truthy, or `""` when none match.
   * Uses FindAll internally; suitable for small trees.
   * @param {Func} pred - Predicate receiving a DomNode.
   * @returns {DomNode|string}
   */
  FindFirst(pred) {
    all := this.FindAll(pred)
    return (all.Length > 0) ? all[1] : ""
  }

  /**
   * Removes all children for which `pred(child)` is truthy.
   * Only examines direct children, not deeper descendants.
   * @param {Func} pred - Predicate receiving a DomNode.
   * @returns {DomNode} this
   */
  RemoveChildren(pred) {
    kept := []
    for child in this.children
      if !pred(child)
        kept.Push(child)
    this.children := kept
    return this
  }
}
