#Requires AutoHotkey v2.0

class ClipboardWaiter {
  ; ---------------------------------------------------------------------------
  ; Standard clipboard format IDs (WinUser.h).
  ; Use these instead of memorising / searching.
  ; ---------------------------------------------------------------------------
  static CF_TEXT            := 1
  static CF_BITMAP          := 2
  static CF_METAFILEPICT    := 3
  static CF_SYLK            := 4
  static CF_DIF             := 5
  static CF_TIFF            := 6
  static CF_OEMTEXT         := 7
  static CF_DIB             := 8
  static CF_PALETTE         := 9
  static CF_PENDATA         := 10
  static CF_RIFF            := 11
  static CF_WAVE            := 12
  static CF_UNICODETEXT     := 13
  static CF_ENHMETAFILE     := 14
  static CF_HDROP           := 15
  static CF_LOCALE          := 16
  static CF_DIBV5           := 17
  
  static HTML_SECTION_HTML      := 1
  static HTML_SECTION_FRAGMENT  := 2
  static HTML_SECTION_SELECTION := 3

  ; Named/registered formats (common ones).
  static _cfHtml            := 0  ; cached numeric id for "HTML Format"

  ; Reusable tooltip-hider callback (one object, reused).
  static _hideTip := (*) => ToolTip()

  ; ---------------------------------------------------------------------------
  ; Public helpers
  ; ---------------------------------------------------------------------------

  /**
   * Get the registered clipboard format id for "HTML Format".
   * @returns {Integer}
   */
  static HtmlFormatId() {
    if (!this._cfHtml) {
      this._cfHtml := this.RegisterFormat("HTML Format")
    }
    return this._cfHtml
  }

  /**
   * Register/resolve a named clipboard format.
   * @param {String} formatName Registered format name, e.g. "HTML Format".
   * @returns {Integer}
   * @throws {OSError}
   */
  static RegisterFormat(formatName) {
    fmt := DllCall("User32\RegisterClipboardFormatW"
      , "Str", String(formatName)
      , "UInt")
    if (!fmt)
      throw OSError("RegisterClipboardFormatW failed", -1)
    return fmt
  }

  /**
   * Resolve a format specifier to a numeric clipboard format id.
   * @param {Integer|String} formatSpec
   * Integer id (for example ClipboardWaiter.CF_UNICODETEXT),
   * enum-name string (e.g. "CF_UNICODETEXT"), or registered format name.
   * @returns {Integer}
   * @throws {ValueError}
   */
  static ResolveFormat(formatSpec) {

    if (IsInteger(formatSpec)) {
      fmt := Integer(formatSpec)
      if (fmt <= 0)
        throw ValueError("format id must be > 0")
      return fmt
    }

    name := String(formatSpec)

    ; If caller passed an enum name like "CF_UNICODETEXT", use it.
    if (this.HasOwnProp(name)) {
      fmt := this.%name%
      if (!IsInteger(fmt) || fmt <= 0)
        throw ValueError("invalid enum value for " name)
      return fmt
    }

    ; Otherwise treat it as a registered format name.
    return this.RegisterFormat(name)
  }

  /**
   * Read clipboard data for a specific format into an AHK Buffer.
   * @param {Integer|String} formatSpec
   * Integer id (for example ClipboardWaiter.CF_UNICODETEXT),
   * enum-name string, or registered format name.
   * @param {Integer} timeoutMs
   * @param {Integer} pollMs
   * @param {String} waitingMsg
   * @param {String} failMsg
   * @param {Integer} failCloseMs
   * @returns {Buffer|Integer} Buffer on success, 0 on timeout/failure.
   * @throws {ValueError}
   */
  static GetBuffer(formatSpec
    , timeoutMs := 2000
    , pollMs := 50
    , waitingMsg := "Waiting for data..."
    , failMsg := "FAILED!  Data didn't arrive."
    , failCloseMs := 2000) {

    if (timeoutMs < 0)
      throw ValueError("timeoutMs must be >= 0")
    if (pollMs <= 0)
      throw ValueError("pollMs must be > 0")
    if (failCloseMs < 0)
      throw ValueError("failCloseMs must be >= 0")

    fmt := this.ResolveFormat(formatSpec)

    ; Cancel any previously scheduled hide for this callback.
    SetTimer(this._hideTip, 0)

    ToolTip(waitingMsg)
    deadline := A_TickCount + timeoutMs

    out := 0  ; will become a Buffer on success

    try {
      while (A_TickCount < deadline) {

        ; OpenClipboard can fail if another process has it open.
        if (DllCall("User32\OpenClipboard", "Ptr", 0, "Int")) {
          try {
            ; If not available yet, keep polling until timeout.
            if (DllCall("User32\IsClipboardFormatAvailable"
              , "UInt", fmt
              , "Int")) {

              ; For delayed rendering, this can be NULL until owner provides it.
              hData := DllCall("User32\GetClipboardData"
                , "UInt", fmt
                , "Ptr")

              if (hData) {
                pData := DllCall("Kernel32\GlobalLock", "Ptr", hData, "Ptr")
                if (pData) {
                  try {
                    cb := DllCall("Kernel32\GlobalSize", "Ptr", hData, "UPtr")
                    if (cb) {
                      ; Copy bytes out of the global memory into an AHK-managed
                      ; Buffer so we don't depend on the clipboard staying open.
                      buf := Buffer(cb)
                      DllCall("Kernel32\RtlMoveMemory"
                        , "Ptr", buf.Ptr
                        , "Ptr", pData
                        , "UPtr", cb)
                      out := buf
                      break
                    }
                  } finally {
                    DllCall("Kernel32\GlobalUnlock", "Ptr", hData)
                  }
                }
              }
            }
          } finally {
            DllCall("User32\CloseClipboard")
          }
        }

        Sleep(pollMs)
      }
    } finally {
      if (out) {
        ToolTip()
      } else {
        ToolTip(failMsg)
        if (failCloseMs = 0) {
          ToolTip()
        } else {
          SetTimer(this._hideTip, -failCloseMs)
        }
      }
    }

    return out
  }

  /**
   * Get CF_UNICODETEXT from clipboard.
   * @param {Integer} timeoutMs
   * @param {Integer} pollMs
   * @returns {String} Unicode text or "".
   */
  static GetUnicodeText(timeoutMs := 2000, pollMs := 50) {
    buf := this.GetBuffer(this.CF_UNICODETEXT, timeoutMs, pollMs
      , "Waiting for Unicode text..."
      , "FAILED!  Text didn't arrive.")
    if (!buf)
      return ""

    ; CF_UNICODETEXT is UTF-16LE and NUL-terminated.  StrGet stops at NUL.
    return StrGet(buf.Ptr, "UTF-16")
  }

  /**
   * Get CF_HTML from clipboard as CP0-decoded text.
   * @param {Integer} timeoutMs
   * @param {Integer} pollMs
   * @returns {String} CF_HTML text or "".
   */
  static GetHtml(timeoutMs := 2000, pollMs := 50) {
    buf := this.GetBuffer(this.HtmlFormatId(), timeoutMs, pollMs
      , "Waiting for HTML..."
      , "FAILED!  HTML didn't arrive.")
    if (!buf)
      return ""

    ; CF_HTML is conventionally byte-oriented.  This decodes using ANSI/ACP.
    ; If you need raw bytes, call GetBuffer() and parse the Buffer yourself.
    return StrGet(buf.Ptr, buf.Size, "CP0")
  }

  /**
   * Get a selected CF_HTML section directly from clipboard.
   * @param {Integer} sectionEnum One of ClipboardWaiter.HTML_SECTION_* constants.
   * @param {Integer} timeoutMs
   * @param {Integer} pollMs
   * @returns {String} Selected HTML section or "".
   */
  static GetHtmlSection(sectionEnum := ClipboardWaiter.HTML_SECTION_FRAGMENT, timeoutMs := 2000, pollMs := 50) {
    cfHtml := this.GetHtml(timeoutMs, pollMs)
    if (cfHtml = "")
      return ""
    return this.SelectHtmlSection(cfHtml, sectionEnum)
  }

  /**
   * Composable parser that extracts a CF_HTML section from GetHtml() output.
   * @param {String} cfHtml CF_HTML text returned by GetHtml().
   * @param {Integer} sectionEnum One of ClipboardWaiter.HTML_SECTION_* constants.
   * @returns {String} Selected HTML section or "".
   */
  static SelectHtmlSection(cfHtml, sectionEnum := ClipboardWaiter.HTML_SECTION_FRAGMENT) {
    cfHtml := String(cfHtml)
    keys := this._ResolveHtmlSectionKeys(sectionEnum)

    start := this._ParseCfHtmlOffset(cfHtml, keys.startKey)
    finish := this._ParseCfHtmlOffset(cfHtml, keys.endKey)
    if (start < 0 || finish < 0 || finish <= start)
      return ""

    ; Offsets are byte-based. Re-encode to bytes for accurate slicing.
    byteCount := StrPut(cfHtml, "CP0") - 1
    if (finish > byteCount)
      return ""

    buf := Buffer(byteCount + 1, 0)
    StrPut(cfHtml, buf, "CP0")
    return this._Utf8BytesToString(buf.Ptr + start, finish - start)
  }

  /**
   * Resolve a section enum to CF_HTML offset header keys.
   * @param {Integer} sectionEnum One of ClipboardWaiter.HTML_SECTION_* constants.
   * @returns {Object} { startKey, endKey }
   */
  static _ResolveHtmlSectionKeys(sectionEnum) {
    if (!IsInteger(sectionEnum))
      throw ValueError("sectionEnum must be a ClipboardWaiter.HTML_SECTION_* integer", -1, sectionEnum)

    if (sectionEnum = this.HTML_SECTION_HTML) {
      return { startKey: "StartHTML:", endKey: "EndHTML:" }
    } else if (sectionEnum = this.HTML_SECTION_FRAGMENT) {
      return { startKey: "StartFragment:", endKey: "EndFragment:" }
    } else if (sectionEnum = this.HTML_SECTION_SELECTION) {
      return { startKey: "StartSelection:", endKey: "EndSelection:" }
    }

    throw ValueError("invalid sectionEnum", -1, sectionEnum)
  }

  /**
   * Parse an integer CF_HTML offset from header text.
   * @param {String} cf
   * @param {String} key
   * @returns {Integer} Offset or -1 when missing/invalid.
   */
  static _ParseCfHtmlOffset(cf, key) {
    pos := InStr(cf, key)
    if (!pos)
      return -1

    pos += StrLen(key)
    eol := InStr(cf, "`r`n", , pos)
    if (!eol)
      eol := InStr(cf, "`n", , pos)
    if (!eol)
      return -1

    numStr := Trim(SubStr(cf, pos, eol - pos))
    if (numStr = "")
      return -1

    return numStr + 0
  }

  /**
   * Decode a UTF-8 byte range into UTF-16 string.
   * @param {Ptr} ptr
   * @param {Integer} byteLen
   * @returns {String}
   */
  static _Utf8BytesToString(ptr, byteLen) {
    if (byteLen <= 0)
      return ""

    cpUtf8 := 65001
    wlen := DllCall("Kernel32\MultiByteToWideChar"
      , "UInt", cpUtf8
      , "UInt", 0
      , "Ptr", ptr
      , "Int", byteLen
      , "Ptr", 0
      , "Int", 0
      , "Int")
    if (wlen <= 0)
      return ""

    wbuf := Buffer((wlen + 1) * 2, 0)
    out := DllCall("Kernel32\MultiByteToWideChar"
      , "UInt", cpUtf8
      , "UInt", 0
      , "Ptr", ptr
      , "Int", byteLen
      , "Ptr", wbuf.Ptr
      , "Int", wlen
      , "Int")
    if (out != wlen)
      return ""

    return StrGet(wbuf.Ptr, wlen, "UTF-16")
  }
}
