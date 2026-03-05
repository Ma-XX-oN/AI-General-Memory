;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; HtmlDom - General-purpose tree node for parsed HTML
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

/**
 * General-purpose tree node representing a parsed unit of HTML.
 *
 * Each node has a semantic tag name, an attribute map, an array of child
 * nodes (wrapped by DomNodeSiblings), and a text/HTML content string.
 * This structure is source-agnostic:
 * 
 * - per-source parsers produce DomNode trees
 * - universal transforms walk and mutate those trees.
 */
class DomNodeSiblings extends Array {
  ; Why this wrapper exists:
  ; - Enforces tree invariants at one mutation point (type safety + parent links).
  ; - Prevents stale-parent bugs when nodes move between parents.
  ; - Keeps DomNode's public API DOM-like while centralizing ownership logic.

  /** @type {DomNode|string} Parent DomNode that owns this sibling list. */
  owner := ""

  /**
   * @param {DomNode|string} owner - Parent node, or "" when unattached.
   */
  __New(owner := "") {
    this.owner := owner
  }

  /**
   * Coerces an incoming value to DomNodeSiblings.
   * Accepts Arrays (including DomNodeSiblings) and re-attaches nodes to owner.
   * @param {Array|string} value
   * @param {DomNode|string} owner
   * @returns {DomNodeSiblings}
   */
  static From(value, owner := "") {
    list := DomNodeSiblings(owner)
    if (value = "" || value = 0)
      return list
    if !(value is Array)
      throw Error("DomNode.children must be an Array of DomNode.")
    for child in value
      list.Push(child)
    return list
  }

  /**
   * @param {DomNode*} values
   * @returns {integer}
   */
  Push(values*) {
    for child in values
      this._Attach(child)
    return super.Push(values*)
  }

  /**
   * @param {integer} index
   * @param {DomNode*} values
   * @returns {integer}
   */
  InsertAt(index, values*) {
    for child in values
      this._Attach(child)
    return super.InsertAt(index, values*)
  }

  /**
   * Removes one child (when length is omitted) or a range (when provided).
   * Mirrors native Array.RemoveAt return shape:
   * - RemoveAt(index) => single removed item
   * - RemoveAt(index, length) => Array of removed items
   * @param {integer} index
   * @param {integer} length
   * @returns {DomNode|Array}
   */
  RemoveAt(index, length?) {
    removed := IsSet(length) ? super.RemoveAt(index, length) : super.RemoveAt(index)
    this._DetachRemoved(removed)
    return removed
  }

  /**
   * @returns {DomNode|string}
   */
  Pop() {
    if (this.Length = 0)
      return ""
    removed := super.Pop()
    this._Detach(removed)
    return removed
  }

  /**
   * @returns {DomNode|string}
   */
  Shift() {
    if (this.Length = 0)
      return ""
    removed := super.Shift()
    this._Detach(removed)
    return removed
  }

  /**
   * @param {DomNode} child
   */
  _Attach(child) {
    if (Type(child) != "DomNode")
      throw Error("DomNode.children entries must be DomNode objects.")
    this._DetachFromCurrentParent(child)
    if IsObject(this.owner)
      child.parent := this.owner
    else
      child.parent := ""
  }

  /**
   * Removes child from prior parent list when moving between owners.
   * @param {DomNode} child
   */
  _DetachFromCurrentParent(child) {
    if !IsObject(child.parent)
      return
    if (IsObject(this.owner) && ObjPtr(child.parent) = ObjPtr(this.owner))
      return
    siblings := child.parent.children
    idx := 1
    while (idx <= siblings.Length) {
      item := siblings[idx]
      if (Type(item) = "DomNode" && ObjPtr(item) = ObjPtr(child)) {
        siblings.RemoveAt(idx)
        break
      }
      idx += 1
    }
  }

  /**
   * @param {DomNode|Array|string} removed
   */
  _DetachRemoved(removed) {
    if (removed is Array) {
      for child in removed
        this._Detach(child)
      return
    }
    this._Detach(removed)
  }

  /**
   * @param {DomNode|string} child
   */
  _Detach(child) {
    if (Type(child) != "DomNode")
      return
    if !IsObject(this.owner)
      return
    if (IsObject(child.parent) && ObjPtr(child.parent) = ObjPtr(this.owner))
      child.parent := ""
  }
}

class DomNode {
  /** @type {string} Semantic tag name. */
  tag := ""

  /** @type {Map} Arbitrary key-value attributes. */
  attrs := Map()

  /** @type {DomNode|string} Parent DomNode, or "". */
  parent := ""

  /** @type {DomNodeSiblings} Backing storage for children property. */
  _children := 0

  /**
   * Child DomNode objects.
   * Assignments are coerced to DomNodeSiblings, preserving parent links.
   * @type {DomNodeSiblings}
   */
  children {
    get => this._children
    set => this._children := DomNodeSiblings.From(value, this)
  }

  /**
   * DOM-style alias for children.
   * @type {DomNodeSiblings}
   */
  childNodes {
    get => this.children
  }

  /**
   * First child node, or "" when none exist.
   * @type {DomNode|string}
   */
  firstChild {
    get => this.children.Length > 0 ? this.children[1] : ""
  }

  /**
   * Last child node, or "" when none exist.
   * @type {DomNode|string}
   */
  lastChild {
    get => this.children.Length > 0 ? this.children[this.children.Length] : ""
  }

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
    this._children := DomNodeSiblings(this)
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
   * DOM-style append.
   * @param {DomNode} child
   * @returns {DomNode} Appended node
   */
  appendChild(child) {
    this.children.Push(child)
    return child
  }

  /**
   * DOM-style insert-before.
   * If referenceChild is "", appends at end.
   * @param {DomNode} newChild
   * @param {DomNode|string} referenceChild
   * @returns {DomNode} Inserted node
   */
  insertBefore(newChild, referenceChild := "") {
    if (referenceChild = "") {
      this.children.Push(newChild)
      return newChild
    }
    idx := this._FindChildIndex(referenceChild)
    if (idx = 0)
      throw Error("insertBefore: referenceChild is not a child of this node.")
    this.children.InsertAt(idx, newChild)
    return newChild
  }

  /**
   * DOM-style remove-child.
   * @param {DomNode} child
   * @returns {DomNode} Removed node
   */
  removeChild(child) {
    idx := this._FindChildIndex(child)
    if (idx = 0)
      throw Error("removeChild: node is not a child of this node.")
    return this.children.RemoveAt(idx)
  }

  /**
   * DOM-style replace-child.
   * @param {DomNode} newChild
   * @param {DomNode} oldChild
   * @returns {DomNode} Replaced (old) node
   */
  replaceChild(newChild, oldChild) {
    idx := this._FindChildIndex(oldChild)
    if (idx = 0)
      throw Error("replaceChild: oldChild is not a child of this node.")
    removed := this.children.RemoveAt(idx)
    this.children.InsertAt(idx, newChild)
    return removed
  }

  /**
   * DOM-style child presence test.
   * @returns {boolean}
   */
  hasChildNodes() {
    return this.children.Length > 0
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

  /**
   * Returns 1-based child index of a direct child, or 0 when absent.
   * @param {DomNode} child
   * @returns {integer}
   */
  _FindChildIndex(child) {
    if (Type(child) != "DomNode")
      return 0
    idx := 1
    while (idx <= this.children.Length) {
      if ObjPtr(this.children[idx]) = ObjPtr(child)
        return idx
      idx += 1
    }
    return 0
  }
}
