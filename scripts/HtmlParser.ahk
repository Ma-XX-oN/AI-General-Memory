;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; HtmlParser - MSHTML-backed structural HTML parser
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

#Include HtmlDom.ahk

/**
 * Parses HTML fragments through MSHTML (`HTMLFILE`) and converts them into
 * `DomNode` trees consumed by HtmlNorm/PasteAsMd.
 *
 * Notes:
 * - Output remains a flat Array of top-level element DomNode roots.
 * - Text nodes are preserved as `DomNode("text", "", text)`.
 * - Comments/doctype nodes are ignored in output.
 */
class HtmlParser {
  /**
   * Parse progress for the current/most recent Parse call (0..1).
   * @type {float}
   */
  static progress := 0.0

  /** @type {integer} Input HTML length for current/most recent parse. */
  static _parseHayLen := 0
  /** @type {integer} A_TickCount at Parse start. */
  static _parseStartTick := 0
  /** @type {integer} A_TickCount of most recent node-visit update. */
  static _parseLastTick := 0
  /** @type {integer} Number of visited nodes converted to DomNode. */
  static _parseVisitedCount := 0
  /** @type {integer} Estimated total node count for progress normalization. */
  static _parseTotalCount := 0
  /** @type {integer} Last processed node position (visited-count proxy). */
  static _parseLastPos := 0
  /** @type {integer} Number of visited element nodes. */
  static _parseTagOpenCount := 0
  /** @type {integer} Number of progress-bearing events (visited nodes). */
  static _parseProgressEventCount := 0
  /** @type {integer} Next heartbeat tick for profile logging. */
  static _profileNextTick := 0

  /**
   * Enables lightweight parser heartbeat logging.
   * @type {boolean}
   */
  static PROFILE_ENABLED := true
  /** @type {integer} Heartbeat cadence in milliseconds. */
  static PROFILE_INTERVAL_MS := 500
  /** @type {string} Heartbeat log path. */
  static PROFILE_PATH := "c:\\ahk\\HtmlParser_profile.log"
  /**
   * Maximum parse time budget in milliseconds.
   * Set <= 0 to disable timeout aborts.
   * @type {integer}
   */
  static PARSE_MAX_MS := 5000

  /**
   * Known HTML void element names.
   * @type {Map}
   */
  static _voidTags := Map(
    "area",1, "base",1, "br",1,    "col",1,   "embed",1,
    "hr",1,   "img",1,  "input",1, "link",1,  "meta",1,
    "param",1, "source",1, "track",1, "wbr",1
  )

  /**
   * Throws on obvious malformed single unclosed non-void tags.
   * Keeps historical test behaviour for `<div>no closing tag`.
   * @type {boolean}
   */
  static STRICT_UNCLOSED_NONVOID_CHECK := true

  /**
   * Parses `html` and returns an array of top-level DomNode trees.
   * @param {string} html - Raw HTML fragment
   * @returns {Array} Top-level DomNode objects
   */
  static Parse(html) {
    HtmlParser._ResetMetrics(html)
    HtmlParser._WriteProfileLine("START len=" HtmlParser._parseHayLen)

    if (html = "") {
      HtmlParser.progress := 1.0
      HtmlParser._WriteProfileLine("END " HtmlParser._FormatProfileStatus())
      return []
    }

    if (HtmlParser.STRICT_UNCLOSED_NONVOID_CHECK)
      HtmlParser._ThrowIfObviouslyUnclosedNonVoid(html)

    doc := HtmlParser._CreateHtmlDocument(html)
    roots := HtmlParser._CollectFragmentRootNodes(doc)

    HtmlParser._parseTotalCount := HtmlParser._CountConvertibleNodes(roots)
    if (HtmlParser._parseTotalCount <= 0)
      HtmlParser._parseTotalCount := 1

    out := []
    for rootCom in roots {
      dom := HtmlParser._ConvertComNode(rootCom)
      if IsObject(dom)
        out.Push(dom)
    }

    HtmlParser.progress := 1.0
    HtmlParser._parseLastTick := A_TickCount
    HtmlParser._WriteProfileLine("END " HtmlParser._FormatProfileStatus())
    return out
  }

  /**
   * Returns parse-progress metrics for diagnostics/profiling.
   * @returns {Map}
   */
  static GetParseMetrics() {
    now := A_TickCount
    elapsed := (HtmlParser._parseStartTick = 0) ? 0 : (now - HtmlParser._parseStartTick)
    idle := (HtmlParser._parseLastTick = 0) ? elapsed : (now - HtmlParser._parseLastTick)
    return Map(
      "elapsedMs", elapsed,
      "hayLen", HtmlParser._parseHayLen,
      "progress", HtmlParser.progress,
      "tagOpenCount", HtmlParser._parseTagOpenCount,
      "progressEventCount", HtmlParser._parseProgressEventCount,
      "lastPos", HtmlParser._parseLastPos,
      "idleMs", idle
    )
  }

  /**
   * Resets parser metrics before each Parse() call.
   * @param {string} html
   */
  static _ResetMetrics(html) {
    HtmlParser.progress := 0.0
    HtmlParser._parseHayLen := StrLen(html)
    HtmlParser._parseStartTick := A_TickCount
    HtmlParser._parseLastTick := 0
    HtmlParser._parseVisitedCount := 0
    HtmlParser._parseTotalCount := 0
    HtmlParser._parseLastPos := 0
    HtmlParser._parseTagOpenCount := 0
    HtmlParser._parseProgressEventCount := 0
    HtmlParser._profileNextTick := HtmlParser._parseStartTick
  }

  /**
   * Creates an MSHTML document and loads fragment HTML.
   * @param {string} html
   * @returns {ComObject}
   */
  static _CreateHtmlDocument(html) {
    doc := ComObject("HTMLFILE")
    doc.write(html)
    doc.close()
    return doc
  }

  /**
   * Collects top-level fragment roots from Start/EndFragment comments when
   * available, otherwise falls back to element children of body.
   * @param {ComObject} doc
   * @returns {Array}
   */
  static _CollectFragmentRootNodes(doc) {
    roots := []
    body := ""
    try body := doc.body
    if !IsObject(body)
      return roots

    start := HtmlParser._FindFragmentBoundaryComment(body, "StartFragment")
    stop := HtmlParser._FindFragmentBoundaryComment(body, "EndFragment")
    if (IsObject(start) && IsObject(stop)) {
      node := ""
      try node := start.nextSibling
      while IsObject(node) {
        if (ObjPtr(node) = ObjPtr(stop))
          break
        try {
          if (node.nodeType = 1)
            roots.Push(node)
        }
        next := ""
        try next := node.nextSibling
        node := next
      }
      if (roots.Length > 0)
        return roots
    }

    node := ""
    try node := body.firstChild
    while IsObject(node) {
      nodeType := 0
      try nodeType := node.nodeType
      if (nodeType = 1)
        roots.Push(node)
      next := ""
      try next := node.nextSibling
      node := next
    }
    return roots
  }

  /**
   * Finds a comment node containing `label` in subtree rooted at `node`.
   * @param {ComObject} node
   * @param {string} label
   * @returns {ComObject|string}
   */
  static _FindFragmentBoundaryComment(node, label) {
    if !IsObject(node)
      return ""
    nodeType := 0
    try nodeType := node.nodeType
    if (nodeType = 8) {
      text := ""
      try text := "" node.nodeValue
      if InStr(text, label)
        return node
    }
    child := ""
    try child := node.firstChild
    while IsObject(child) {
      found := HtmlParser._FindFragmentBoundaryComment(child, label)
      if IsObject(found)
        return found
      next := ""
      try next := child.nextSibling
      child := next
    }
    return ""
  }

  /**
   * Counts convertible nodes (elements + text nodes) under root COM nodes.
   * @param {Array} roots
   * @returns {integer}
   */
  static _CountConvertibleNodes(roots) {
    count := 0
    stack := []
    for root in roots
      stack.Push(root)
    while (stack.Length > 0) {
      cur := stack.Pop()
      nodeType := 0
      try nodeType := cur.nodeType
      if (nodeType = 1 || nodeType = 3)
        count += 1
      if (nodeType = 1) {
        child := ""
        try child := cur.firstChild
        while IsObject(child) {
          stack.Push(child)
          next := ""
          try next := child.nextSibling
          child := next
        }
      }
    }
    return count
  }

  /**
   * Converts an MSHTML node into DomNode recursively.
   * @param {ComObject} comNode
   * @returns {DomNode|string}
   */
  static _ConvertComNode(comNode) {
    if !IsObject(comNode)
      return ""

    nodeType := 0
    try nodeType := comNode.nodeType

    if (nodeType != 1 && nodeType != 3)
      return ""

    HtmlParser._OnProgressEvent(nodeType = 1)

    if (nodeType = 3) {
      text := ""
      try text := "" comNode.nodeValue
      return DomNode("text", "", text)
    }

    tag := ""
    try tag := StrLower("" comNode.nodeName)
    attrs := HtmlParser._ExtractAttributes(comNode)
    node := DomNode(tag, attrs)

    kids := ""
    try kids := comNode.firstChild
    childCom := kids
    while IsObject(childCom) {
      childNode := HtmlParser._ConvertComNode(childCom)
      if IsObject(childNode)
        node.Add(childNode)
      next := ""
      try next := childCom.nextSibling
      childCom := next
    }
    return node
  }

  /**
   * Extracts element attributes into a lowercase-key Map.
   * @param {ComObject} comNode
   * @returns {Map}
   */
  static _ExtractAttributes(comNode) {
    attrs := Map()
    attrList := ""
    try attrList := comNode.attributes
    if !IsObject(attrList)
      return attrs
    attrLen := HtmlParser._CollectionLength(attrList)
    Loop attrLen {
      attr := HtmlParser._CollectionItem(attrList, A_Index - 1)
      if !IsObject(attr)
        continue
      name := ""
      try name := StrLower("" attr.nodeName)
      if (name = "")
        continue
      specified := true
      try specified := attr.specified
      if !specified
        continue
      val := ""
      try val := comNode.getAttribute(name, 2)
      if (val = "")
        try val := attr.nodeValue
      attrs[name] := (val = "" ? "" : "" val)
    }
    return attrs
  }

  /**
   * Returns COM collection length (0 when unavailable).
   * @param {ComObject} coll
   * @returns {integer}
   */
  static _CollectionLength(coll) {
    if !IsObject(coll)
      return 0
    len := 0
    try len := coll.length
    if (len = "")
      return 0
    return Integer(len)
  }

  /**
   * Returns COM collection item by 0-based index.
   * @param {ComObject} coll
   * @param {integer} idx
   * @returns {ComObject|string}
   */
  static _CollectionItem(coll, idx) {
    if !IsObject(coll)
      return ""
    item := ""
    try item := coll.item(idx)
    return item
  }

  /**
   * Updates progress counters, profile heartbeat, and timeout budget checks.
   * @param {boolean} isElement
   */
  static _OnProgressEvent(isElement) {
    HtmlParser._parseVisitedCount += 1
    HtmlParser._parseProgressEventCount += 1
    if isElement
      HtmlParser._parseTagOpenCount += 1
    HtmlParser._parseLastPos := HtmlParser._parseVisitedCount

    total := HtmlParser._parseTotalCount
    HtmlParser.progress := (total > 0) ? (HtmlParser._parseVisitedCount / total) : 0.0
    if (HtmlParser.progress < 0)
      HtmlParser.progress := 0.0
    else if (HtmlParser.progress > 1)
      HtmlParser.progress := 1.0

    now := A_TickCount
    HtmlParser._parseLastTick := now

    if (HtmlParser.PARSE_MAX_MS > 0 && (now - HtmlParser._parseStartTick) > HtmlParser.PARSE_MAX_MS) {
      status := HtmlParser._FormatProfileStatus()
      HtmlParser._WriteProfileLine("ABORT timeout(ms=" HtmlParser.PARSE_MAX_MS "): " status)
      throw Error("HtmlParser: parse timeout after " HtmlParser.PARSE_MAX_MS "ms | " status, -1)
    }
    if (HtmlParser.PROFILE_ENABLED && now >= HtmlParser._profileNextTick) {
      HtmlParser._WriteProfileLine(HtmlParser._FormatProfileStatus())
      HtmlParser._profileNextTick := now + HtmlParser.PROFILE_INTERVAL_MS
    }
  }

  /**
   * Detects simple malformed single-element input with missing close tag.
   * @param {string} html
   */
  static _ThrowIfObviouslyUnclosedNonVoid(html) {
    if !RegExMatch(html, "is)^\s*<([a-zA-Z][a-zA-Z0-9:_-]*)\b([^>]*)>(.*)$", &m)
      return
    tag := StrLower(m[1])
    attrs := m[2]
    rest := m[3]

    ; Self-closing and known voids are valid without an explicit close tag.
    if RegExMatch(attrs, "/\s*$") || HtmlParser._voidTags.Has(tag)
      return

    ; If a proper closing tag exists anywhere, this isn't the simple malformed case.
    if RegExMatch(rest, "is)</\s*" tag "\s*>")
      return

    ; Preserve historical behaviour for a simple unclosed non-void fragment.
    if !RegExMatch(rest, "is)<")
      throw Error("HtmlParser: unclosed non-void element <" tag ">", -1)
  }

  /**
   * Builds one compact parser-status line for profile logging.
   * @returns {string}
   */
  static _FormatProfileStatus() {
    m := HtmlParser.GetParseMetrics()
    pct := Round(m["progress"] * 100, 3)
    return "ms=" m["elapsedMs"]
      . " progress=" pct "%"
      . " visited=" m["lastPos"] "/" HtmlParser._parseTotalCount
      . " events=" m["progressEventCount"]
      . " tagOpen=" m["tagOpenCount"]
      . " idleMs=" m["idleMs"]
  }

  /**
   * Appends one UTF-8 line to the parser profile log.
   * @param {string} line
   */
  static _WriteProfileLine(line) {
    if !HtmlParser.PROFILE_ENABLED
      return
    try FileAppend(
      FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss") "." SubStr("000" A_MSec, -3) " " line "`n",
      HtmlParser.PROFILE_PATH,
      "UTF-8"
    )
  }
}
