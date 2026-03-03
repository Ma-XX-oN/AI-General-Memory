;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; test-helpers — shared utilities for HtmlParser/HtmlDom test scripts
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; Suppress error dialogs: route all unhandled exceptions to stderr and exit.
OnError _TestFatalHandler

/**
 * Global OnError handler for test scripts.
 * Writes the error message and AHK call-stack to stderr, then exits cleanly.
 * @param {Error} e    - The thrown error object.
 * @param {string} mode - AHK error mode string (unused here).
 * @returns {integer} -1 to suppress the error dialog.
 */
_TestFatalHandler(e, mode) {
  FileAppend "FATAL: " e.Message "`nStack:`n" e.Stack "`n", "**"
  return -1
}

/**
 * Appends a line to the test log file.
 * Callers must declare `_logPath` as a global before including this file.
 * Falls back to stderr if the log file cannot be written.
 * @param {string} s - Line to append (newline is added automatically).
 */
Log(s) {
  global _logPath
  try
    FileAppend s "`n", _logPath
  catch as e
    FileAppend "Log write error: " e.Message " — " s "`n", "**"
}

/**
 * Recursively prints a DomNode tree to the log.
 * @param {DomNode} node   - Node to dump.
 * @param {string}  indent - Current indentation prefix (default "").
 */
DumpNode(node, indent := "") {
  if node.tag = "text"
    Log(indent "TEXT: " node.text)
  else {
    Log(indent node.tag)
    for child in node.children
      DumpNode(child, indent "  ")
  }
}

/**
 * Dumps an array of top-level DomNode trees to the log.
 * @param {Array} nodes - Array returned by HtmlParser.Parse().
 */
DumpTree(nodes) {
  for node in nodes
    DumpNode(node)
}

/**
 * Records a test result.
 * Callers must declare `passed` and `failed` as globals.
 * @param {string}  label  - Short description of the assertion.
 * @param {boolean} cond   - True if the assertion passed.
 * @param {string}  detail - Optional extra info shown on failure.
 */
Chk(label, cond, detail := "") {
  global passed, failed
  if cond {
    Log("  ok  " label)
    passed++
  } else {
    Log("  FAIL " label (detail != "" ? " — " detail : ""))
    failed++
  }
}
