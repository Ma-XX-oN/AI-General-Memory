;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Paste as md
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
#Requires AutoHotkey v2.0
#SingleInstance Force
#Include ClipHelper.ahk
#Include HtmlNorm.ahk

class PasteMd {
  static __New() {
    PasteMd.gPasteMenu.Add("Paste as &md", ObjBindMethod(PasteMd, "PasteAsMd"))
    PasteMd.gPasteMenu.Add()
    PasteMd.gPasteMenu.Add("&Quote", ObjBindMethod(PasteMd, "ToggleQuote"))
    PasteMd.gPasteMenu.Add("Show &img", ObjBindMethod(PasteMd, "ToggleShowImg"))
    PasteMd.gPasteMenu.Add()
    PasteMd.gPasteMenu.Add("Pin current &log", ObjBindMethod(PasteMd, "PinCurrentLog"))
    PasteMd.gPasteMenu.Add("&Delete pinned history", ObjBindMethod(PasteMd, "DeletePinnedHistory"))
    PasteMd.gPasteMenu.Add("Pinned &file names", ObjBindMethod(PasteMd, "PastePinnedFilenames"))
    PasteMd.gPasteMenu.Add("Pinned &full names", ObjBindMethod(PasteMd, "PastePinnedFullnames"))
    PasteMd.gPasteMenu.Check("&Quote")
    PasteMd.gPasteMenu.Disable("&Delete pinned history")
    PasteMd.gPasteMenu.Disable("Pinned &file names")
    PasteMd.gPasteMenu.Disable("Pinned &full names")
    if (PasteMd.BUSY_SPIN_INTERVAL_MS <= 0)
      throw Error("PasteMd.BUSY_SPIN_INTERVAL_MS must be > 0.")
    if (PasteMd._busySpinner.Length == 0)
      throw Error("PasteMd._busySpinner must contain at least one element.")
    PasteMd._busyTimerFn := ObjBindMethod(PasteMd, "_BusyUpdate")
    PasteMd._defaultOrderedListPromptFn := ObjBindMethod(PasteMd, "_PromptOrderedListStartDialog")
    PasteMd._orderedListPromptFn := PasteMd._defaultOrderedListPromptFn
    PasteMd._InitPinState()
  }

  ; Change this if pandoc isn't on PATH.
  static PANDOC_EXE := "C:\Users\adria\AppData\Local\Pandoc\pandoc.exe"

  static PASTE_SENTINEL_DELAY_MS := 200
  static PASTE_DELAY_MS := 500
  static BUSY_TT_SHOW_DELAY_MS := 500
  static BUSY_SPIN_INTERVAL_MS := 200

  ; Set to true to dump pipeline stages to a log file for debugging.
  static DEBUG_PASTE_MD := true
  static DEBUG_PASTE_MD_LOG := A_ScriptDir "\PasteAsMd_debug.log"
  static PROMPT_ORDERED_LIST_START_ON_AMBIGUOUS := true

  ; Number of rotated past-run logs to keep alongside the current one.
  static LOG_HISTORY_COUNT := 4

  ; Toggle: convert <img> tags to markdown image syntax; when off, use [img] placeholder.
  static SHOW_IMG := false
  ; Toggle: wrap pasted output in blockquote syntax.
  static QUOTE := true
  static CODE_FENCE := "``````"

  ; Temporary storage for thinking blocks extracted during preprocessing.
  static _thinkingBlocks := []
  ; Temporary storage for user message text blocks extracted during preprocessing.
  static _userMsgBlocks := []

  static gPasteMenu := Menu()
  static _menuX := 0
  static _menuY := 0
  ; Path of the pinned copy of the current log, or "" if not pinned.
  static _lastPinPath := ""
  static _busyStartTick := 0
  static _busyLabel := ""
  static _busyTimerFn := 0
  static _busySpinner := ["", ".", "..", "..."]
  static _defaultOrderedListPromptFn := 0
  static _orderedListPromptFn := 0
  static _shellListItemPlaceholder := "¤LI_SHELL¤"

  /**
   * Captures the current call stack for diagnostics.
   * @param {string} label - Optional tag included in the thrown probe error
   * @returns {string} Stack text
   */
  static _CaptureStack(label := "stack probe") {
    try
      throw Error(label)
    catch as e
      return e.Stack
  }

  /**
   * Overrides ordered-list prompt provider for deterministic testing.
   * @param {Func} promptFn - Callable receiving (defaultStart, expected, plain, htmlFrag)
   * @returns {Func} Previous prompt provider
   */
  static SetOrderedListPromptProvider(promptFn) {
    prev := PasteMd._orderedListPromptFn
    if !IsObject(promptFn)
      throw Error("Ordered-list prompt provider must be callable.")
    PasteMd._orderedListPromptFn := promptFn
    return prev
  }

  /**
   * Restores ordered-list prompt provider to runtime default dialog.
   */
  static ResetOrderedListPromptProvider() {
    PasteMd._orderedListPromptFn := PasteMd._defaultOrderedListPromptFn
  }

  /**
   * Shows the markdown paste menu at the current cursor position.
   * Saves the position so toggle callbacks can re-show at the same location.
   */
  static ShowPasteMenu(updatePos := true) {
    if (updatePos) {
      MouseGetPos(&x, &y)
      PasteMd._menuX := x
      PasteMd._menuY := y
    }

    ; If the pinned file was deleted externally, clear the stale pin state.
    if (PasteMd._lastPinPath != "" && !FileExist(PasteMd._lastPinPath)) {
      PasteMd._lastPinPath := ""
      PasteMd.gPasteMenu.Uncheck("Pin current &log")
    }
    ; Enable "Pin current &log" when already pinned (allow unpin) or when log exists (allow pin).
    if (PasteMd._lastPinPath != "" || FileExist(PasteMd.DEBUG_PASTE_MD_LOG))
      PasteMd.gPasteMenu.Enable("Pin current &log")
    else
      PasteMd.gPasteMenu.Disable("Pin current &log")

    ; Enable pinned-file actions only when pinned files exist.
    hasPinned := (PasteMd._PinnedLogFiles().Length > 0)
    pinnedAction := hasPinned ? "Enable" : "Disable"
    PasteMd.gPasteMenu.%pinnedAction%("&Delete pinned history")
    PasteMd.gPasteMenu.%pinnedAction%("Pinned &file names")
    PasteMd.gPasteMenu.%pinnedAction%("Pinned &full names")
    PasteMd.gPasteMenu.Show(PasteMd._menuX, PasteMd._menuY)
  }

  /**
   * Menu callback: pastes clipboard content as markdown.
   * @param {string} ItemName - Menu item label
   * @param {number} ItemPos - Menu item position
   * @param {object} MenuObj - Menu object
   */
  static PasteAsMd(ItemName, ItemPos, MenuObj) {
    PasteMd.PasteMarkdown(PasteMd.QUOTE)
  }

  /**
   * Menu callback: toggles SHOW_IMG and re-shows the menu.
   * @param {string} ItemName - Menu item label
   * @param {number} ItemPos - Menu item position
   * @param {object} MenuObj - Menu object
   */
  static ToggleShowImg(ItemName, ItemPos, MenuObj) {
    PasteMd.SHOW_IMG := !PasteMd.SHOW_IMG
    PasteMd.gPasteMenu.ToggleCheck("Show &img")
    PasteMd.gPasteMenu.Show(PasteMd._menuX, PasteMd._menuY)
  }

  /**
   * Menu callback: toggles QUOTE and re-shows the menu.
   * @param {string} ItemName - Menu item label
   * @param {number} ItemPos - Menu item position
   * @param {object} MenuObj - Menu object
   */
  static ToggleQuote(ItemName, ItemPos, MenuObj) {
    PasteMd.QUOTE := !PasteMd.QUOTE
    PasteMd.gPasteMenu.ToggleCheck("&Quote")
    PasteMd.gPasteMenu.Show(PasteMd._menuX, PasteMd._menuY)
  }

  /**
   * Menu callback: copies current debug log to a timestamped pinned file.
   * When pinning, prompts for an optional filename comment suffix.
   * @param {string} ItemName - Menu item label
   * @param {number} ItemPos - Menu item position
   * @param {object} MenuObj - Menu object
   */
  static PinCurrentLog(ItemName, ItemPos, MenuObj) {
    if (PasteMd._lastPinPath != "") {
      ; Already pinned — unpin.
      if FileExist(PasteMd._lastPinPath)
        FileDelete(PasteMd._lastPinPath)
      PasteMd._lastPinPath := ""
      PasteMd.gPasteMenu.Uncheck("Pin current &log")
      ToolTip("Unpinned")
    } else {
      ; Not pinned — pin.
      if !FileExist(PasteMd.DEBUG_PASTE_MD_LOG)
        return
      ib := InputBox(
        "Optional comment for pinned log filename.`nLeave blank for timestamp-only name.",
        "Pin current log comment",
        "w520 h160"
      )
      if (ib.Result != "OK") {
        PasteMd.ShowPasteMenu(false)
        return
      }
      pinPath := PasteMd._PinLogPath(ib.Value)
      FileCopy(PasteMd.DEBUG_PASTE_MD_LOG, pinPath)
      PasteMd._lastPinPath := pinPath
      PasteMd.gPasteMenu.Check("Pin current &log")
      SplitPath(pinPath, &name)
      ToolTip("Pinned: " name)
    }
    SetTimer(() => ToolTip(), -2000)
    PasteMd.ShowPasteMenu(false)
  }

  /**
   * Menu callback: deletes all pinned (timestamped) log files after confirmation.
   * @param {string} ItemName - Menu item label
   * @param {number} ItemPos - Menu item position
   * @param {object} MenuObj - Menu object
   */
  static DeletePinnedHistory(ItemName, ItemPos, MenuObj) {
    files := PasteMd._PinnedLogFiles()
    if (files.Length = 0)
      return
    n := files.Length
    result := MsgBox("Delete " n " pinned log file" (n = 1 ? "" : "s") "?`nThis cannot be undone."
      , "&Delete pinned history", "OKCancel Icon!")
    if (result != "OK")
      return
    for f in files
      FileDelete(f)
  }

  /**
   * Menu callback: pastes pinned log filenames (no path) as a double-quoted,
   * space-separated string into the active window.
   * @param {string} ItemName - Menu item label
   * @param {number} ItemPos - Menu item position
   * @param {object} MenuObj - Menu object
   */
  static PastePinnedFilenames(ItemName, ItemPos, MenuObj) {
    files := PasteMd._PinnedLogFiles()
    if (files.Length = 0)
      return
    out := ""
    for f in files {
      SplitPath(f, &name)
      out .= (out = "" ? "" : " ") '"' name '"'
    }
    PasteMd._PasteText(out)
  }

  /**
   * Menu callback: pastes pinned log full paths as a double-quoted,
   * space-separated string into the active window.
   * @param {string} ItemName - Menu item label
   * @param {number} ItemPos - Menu item position
   * @param {object} MenuObj - Menu object
   */
  static PastePinnedFullnames(ItemName, ItemPos, MenuObj) {
    files := PasteMd._PinnedLogFiles()
    if (files.Length = 0)
      return
    out := ""
    for f in files
      out .= (out = "" ? "" : " ") '"' f '"'
    PasteMd._PasteText(out)
  }

  /**
   * Pastes plain text into the active window, saving and restoring the clipboard.
   * @param {string} text - Text to paste
   */
  static _PasteText(text) {
    clipSaved := ClipboardAll()
    try {
      A_Clipboard := text
      Send "^v"
      Sleep PasteMd.PASTE_DELAY_MS
    } finally {
      A_Clipboard := clipSaved
    }
  }

  /**
   * Starts periodic busy tooltip updates for long-running paste operations.
   * @param {string} stage - Initial status label
   */
  static _BusyStart(stage := "Working") {
    PasteMd._busyStartTick := A_TickCount
    PasteMd._busyLabel := stage
    SetTimer(PasteMd._busyTimerFn, PasteMd.BUSY_SPIN_INTERVAL_MS)
    PasteMd._BusyUpdate(stage)
  }

  /**
   * Updates busy tooltip text/spinner while a paste is in progress.
   * @param {string} stage - Optional updated status label
   */
  static _BusyUpdate(stage := "") {
    if (PasteMd._busyStartTick = 0)
      return

    if (stage != "")
      PasteMd._busyLabel := stage

    elapsed := A_TickCount - PasteMd._busyStartTick
    if (elapsed < PasteMd.BUSY_TT_SHOW_DELAY_MS) {
      ToolTip()
      return
    }

    spinnerCount := PasteMd._busySpinner.Length
    spinInterval := PasteMd.BUSY_SPIN_INTERVAL_MS
    spinnerIndex := Mod(Floor(elapsed / spinInterval), spinnerCount) + 1
    spinner := PasteMd._busySpinner[spinnerIndex]
    ToolTip(PasteMd._busyLabel spinner)
  }

  /**
   * Stops periodic busy updates and clears tooltip state.
   */
  static _BusyEnd() {
    if PasteMd._busyTimerFn
      SetTimer(PasteMd._busyTimerFn, 0)
    PasteMd._busyStartTick := 0
    PasteMd._busyLabel := ""
    Sleep 10 ; in case _BusyUpdate() was called and interrupted
    ToolTip()
  }

  /**
   * Determines the poster of the message containing the clipboard selection
   * by scanning the CF_HTML context before StartFragment.
   * @param {string} cfHtml - Full CF_HTML payload
   * @returns {string} "AI", "User", or empty string when not detected
   */
  static _ExtractPosterFromContext(cfHtml) {
    startFragOff := PasteMd.ParseCfHtmlOffsetRaw(cfHtml, "StartFragment:")
    startHtmlOff := PasteMd.ParseCfHtmlOffsetRaw(cfHtml, "StartHTML:")
    if (startFragOff <= 0 || startHtmlOff < 0 || startFragOff <= startHtmlOff)
      return ""

    before := SubStr(cfHtml, startHtmlOff + 1, startFragOff - startHtmlOff)

    ; Find the LAST (closest) message-type marker before the fragment start.
    lastAssist := 0
    lastUser   := 0
    pos := 1
    while RegExMatch(before, "i)data-testid=`"assistant-message`"", &m, pos) {
      lastAssist := m.Pos
      pos := m.Pos + 1
    }
    ; Codex assistant messages: group + min-w-0 + flex-col classes.
    pos := 1
    while RegExMatch(before, "i)\bclass=`"[^`"]*+\bgroup\b[^`"]*+\bmin-w-0\b[^`"]*+\bflex-col\b[^`"]*+`"", &m, pos) {
      lastAssist := m.Pos
      pos := m.Pos + 1
    }
    pos := 1
    while RegExMatch(before, "i)userMessageContainer_", &m, pos) {
      lastUser := m.Pos
      pos := m.Pos + 1
    }
    ; Codex user messages: right-aligned blocks include flex-col + items-end.
    pos := 1
    while RegExMatch(before, "i)\bclass=`"[^`"]*+\bflex-col\b[^`"]*+\bitems-end\b[^`"]*+`"", &m, pos) {
      lastUser := m.Pos
      pos := m.Pos + 1
    }

    if (lastAssist = 0 && lastUser = 0)
      return ""
    return (lastAssist > lastUser) ? "AI" : "User"
  }

  /**
   * Resolves assistant label from CF_HTML source context.
   * @param {string} cfHtml - Full CF_HTML payload
   * @returns {string} Source-specific label, or "AI" fallback
   */
  static _ResolveAssistantLabel(cfHtml) {
    if (cfHtml = "")
      return "AI"

    source := DetectSource(cfHtml)
    if (source = "claudecode")
      return "Claude Code"
    if (source = "claudeweb")
      return "Claude Web"
    if (source = "codex")
      return "Codex"
    if (source = "chatgpt")
      return "ChatGPT"

    if RegExMatch(cfHtml, "i)extensionId=([^&`r`n]++)", &mExt) {
      extId := StrLower(mExt[1])
      if (InStr(extId, "openai.chatgpt"))
        return "Codex"
      if (InStr(extId, "anthropic") || InStr(extId, "claude"))
        return "Claude"
    }

    return "AI"
  }

  /**
   * Writes a labelled debug section to the log file.
   * Replaces CR/LF with visible markers so EOL issues are obvious.
   * @param {object} f - FileOpen handle (already open for writing)
   * @param {string} label - Section heading
   * @param {string} s - Raw string to dump
   */
  static _DbgSection(f, label, s) {
    f.Write("=== " label " (len=" StrLen(s) ") ===`n")
    ; Show EOL characters visibly without emitting raw CR in the log payload.
    tokCRLF := "¤CRLF¤"
    tokCR := "¤CR¤"
    tokLF := "¤LF¤"
    vis := StrReplace(s, "`r`n", tokCRLF)
    vis := StrReplace(vis, "`r", tokCR)
    vis := StrReplace(vis, "`n", tokLF)
    vis := StrReplace(vis, tokCRLF, "⏎¶`n") ; CRLF
    vis := StrReplace(vis, tokCR, "⏎`n")    ; lone CR
    vis := StrReplace(vis, tokLF, "¶`n")    ; lone LF
    f.Write(vis)
    f.Write("`n`n")
  }

  /**
   * Returns the path for rotated log history entry n (1 = most recent).
   * @param {number} n - History index (1-based)
   * @returns {string} File path with .N.log suffix
   */
  static _LogHistoryPath(n) {
    return RegExReplace(PasteMd.DEBUG_PASTE_MD_LOG, "\.log$", "." n ".log")
  }

  /**
   * Returns a timestamped path for a pinned log snapshot.
   * If comment is provided, appends a sanitized suffix:
   * PasteAsMd_debug_<timestamp>_<comment>.log
   * @param {string} comment - Optional user comment for filename suffix
   * @returns {string} Unique pinned log path
   */
  static _PinLogPath(comment := "") {
    base := RegExReplace(PasteMd.DEBUG_PASTE_MD_LOG, "\.log$", "_" FormatTime(, "yyyyMMdd_HHmmss"))
    commentToken := PasteMd._SanitizePinComment(comment)
    if (commentToken != "")
      base .= "_" commentToken
    path := base ".log"
    if !FileExist(path)
      return path
    idx := 2
    while FileExist(base "_" idx ".log")
      idx += 1
    return base "_" idx ".log"
  }

  /**
   * Sanitizes user comment for safe use in Windows filenames.
   * @param {string} comment - Raw user comment
   * @returns {string} Sanitized token, or "" when empty/invalid
   */
  static _SanitizePinComment(comment) {
    s := Trim(comment, " `t")
    if (s = "")
      return ""
    s := RegExReplace(s, "\s++", "_")
    s := RegExReplace(s, "[<>:\x22/\\|?*\x00-\x1F]++", "-")
    s := RegExReplace(s, "_{2,}", "_")
    s := RegExReplace(s, "-{2,}", "-")
    s := Trim(s, " ._-")
    return s
  }

  /**
   * Returns an array of paths for all pinned log files.
   * Matches both timestamp-only and timestamp+comment filenames.
   * @returns {Array} Absolute paths matching pinned filename pattern
   */
  static _PinnedLogFiles() {
    pattern := RegExReplace(PasteMd.DEBUG_PASTE_MD_LOG, "\.log$", "_*.log")
    files := []
    Loop Files, pattern
      files.Push(A_LoopFileFullPath)
    return files
  }

  /**
   * Rotates numbered log history files, dropping the oldest, then moves the
   * current log to the .1 slot.  Called before each new debug log is opened.
   */
  static _RotateLogFiles() {
    ; Drop the oldest entry if the rotation is full.
    oldest := PasteMd._LogHistoryPath(PasteMd.LOG_HISTORY_COUNT)
    if FileExist(oldest)
      FileDelete(oldest)
    ; Shift each slot up: .N-1 → .N, ..., .1 → .2
    n := PasteMd.LOG_HISTORY_COUNT
    Loop n - 1 {
      idx := n - A_Index   ; counts down: N-1, N-2, ..., 1
      src := PasteMd._LogHistoryPath(idx)
      dst := PasteMd._LogHistoryPath(idx + 1)
      if FileExist(src)
        FileMove(src, dst)
    }
    ; Move the current log into the .1 slot.
    if FileExist(PasteMd.DEBUG_PASTE_MD_LOG)
      FileMove(PasteMd.DEBUG_PASTE_MD_LOG, PasteMd._LogHistoryPath(1))
  }

  /**
   * Restores the pin checkmark state after a script restart by comparing the
   * current log's content against all pinned files.  If a match is found, sets
   * _lastPinPath and checks the menu item so the UI reflects the pinned state.
   */
  static _InitPinState() {
    if !FileExist(PasteMd.DEBUG_PASTE_MD_LOG)
      return
    currentContent := FileRead(PasteMd.DEBUG_PASTE_MD_LOG)
    for f in PasteMd._PinnedLogFiles() {
      if (FileRead(f) = currentContent) {
        PasteMd._lastPinPath := f
        PasteMd.gPasteMenu.Check("Pin current &log")
        return
      }
    }
  }

  /**
   * Converts already-captured plain/cfHtml inputs through the markdown pipeline.
   * No clipboard writes or paste side effects.
   * @param {string} plain - Plain clipboard text (typically A_Clipboard with CR stripped)
   * @param {string} cfHtml - Full CF_HTML payload
   * @param {boolean} asQuoted - If true, prefixes every line with blockquote syntax (>)
   * @param {boolean} showPoster - If true, resolves/replaces poster placeholders
   * @param {boolean} showImg - If true, keep <img> tags for pandoc
   * @param {boolean} promptOrderedList - If true, may prompt for ordered-list start when ambiguous
   * @returns {Map} Stage outputs for test/debug use
   */
  static _ConvertFromCaptured(plain, cfHtml, asQuoted, showPoster, showImg, promptOrderedList := false) {
    PasteMd._BusyUpdate("Inspecting clipboard data")
    plain := StrReplace(plain, "`r", "")
    source := DetectSource(cfHtml)
    PasteMd._BusyUpdate("Reading HTML fragment")
    htmlFrag := (cfHtml = "")
      ? ""
      : ClipboardWaiter.SelectHtmlSection(cfHtml, ClipboardWaiter.HTML_SECTION_FRAGMENT)

    htmlPrep := ""
    mdRaw := ""
    md := ""
    mdAfterClean := ""
    mdAfterOrderedList := ""
    mdAfterPoster := ""
    expectedListStart := 0
    aborted := false
    usedNoHtmlPath := false
    usedNoTagPlainPath := false
    prepNodes := []

    prevShowImg := PasteMd.SHOW_IMG
    prevPromptOrderedList := PasteMd.PROMPT_ORDERED_LIST_START_ON_AMBIGUOUS
    PasteMd.SHOW_IMG := showImg
    PasteMd.PROMPT_ORDERED_LIST_START_ON_AMBIGUOUS := promptOrderedList

    try {
      if (htmlFrag = "") {
        PasteMd._BusyUpdate("Using plain text path")
        md := PasteMd.CleanPlainText(plain)
        usedNoHtmlPath := true
        mdAfterClean := md
        mdAfterOrderedList := md
      } else {
        expectedListStart := PasteMd.GetExpectedOrderedListStart(htmlFrag, cfHtml, plain)
        PasteMd._BusyUpdate("Preprocessing HTML")
        htmlPrep := PasteMd._PreprocessHtml(htmlFrag, cfHtml, showPoster)
        prepNodes := HtmlNorm._domNodes
        if (prepNodes.Length > 0) {
          if PasteMd._NormalizeIncidentalListIntentDomNodes(prepNodes, htmlFrag, plain, expectedListStart)
            htmlPrep := PasteMd._SerializeDomNodes(prepNodes)
        } else {
          htmlPrep := PasteMd.NormalizeIncidentalListIntentHtml(htmlPrep, htmlFrag, plain, expectedListStart)
        }

        if (promptOrderedList) {
          promptResult := PasteMd.MaybePromptOrderedListStart(htmlPrep, plain, htmlFrag, expectedListStart)
          if (promptResult["aborted"]) {
            aborted := true
            return Map(
              "source", source,
              "htmlFrag", htmlFrag,
              "htmlPrep", htmlPrep,
              "mdRaw", mdRaw,
              "mdAfterClean", mdAfterClean,
              "mdAfterOrderedList", mdAfterOrderedList,
              "mdAfterPoster", mdAfterPoster,
              "finalMd", "",
              "expectedListStart", expectedListStart,
              "usedNoHtmlPath", usedNoHtmlPath,
              "usedNoTagPlainPath", usedNoTagPlainPath,
              "aborted", true
            )
          }
          expectedListStart := promptResult["value"]
        }

        if (prepNodes.Length > 0) {
          if PasteMd._ApplyOrderedStartAndStabilizeShellDomNodes(prepNodes, expectedListStart)
            htmlPrep := PasteMd._SerializeDomNodes(prepNodes)
        } else {
          htmlPrep := PasteMd.ApplyOrderedListStartAndStabilizeShellHtml(htmlPrep, expectedListStart)
        }

        ; If no meaningful HTML tags remain after preprocessing (only <p>/<br>
        ; wrappers around plain text), skip pandoc — plain text already has
        ; correct whitespace and indentation that pandoc would destroy.
        if !PasteMd._HasMeaningfulHtmlForPandoc(htmlPrep) {
          PasteMd._BusyUpdate("Using plain text path")
          md := PasteMd.CleanPlainText(plain)
          usedNoTagPlainPath := true
          mdAfterClean := md
        } else {
          PasteMd._BusyUpdate("Converting via pandoc")
          mdRaw := PasteMd.HtmlToGfmViaPandoc(htmlPrep, PasteMd.PANDOC_EXE)
          ; Pandoc converts inline <svg> elements to <img> tags; process them now.
          mdRaw := PasteMd._ProcessImgTags(mdRaw)
          ; Fix pandoc fence-space bug: "``` python" → "```python"
          mdRaw := RegExReplace(mdRaw, "m)^(``++) (\S++)", "$1$2")

          PasteMd._BusyUpdate("Cleaning markdown")
          md := PasteMd.CleanMarkdown(mdRaw)
          md := PasteMd.RestoreThinkingBlocks(md)
          md := PasteMd.RestoreUserMsgBlocks(md)
          md := PasteMd.RemoveListShellPlaceholders(md)
          mdAfterClean := md
          md := StrReplace(md, "`r", "")
        }

        ; Never paste empty.  If conversion failed/empty, use plain text.
        if (Trim(md, " `t`n") = "" && Trim(plain, " `t`n") != "") {
          md := PasteMd.CleanPlainText(plain)
          mdAfterClean := md
        }

        PasteMd._BusyUpdate("Finalizing list output")
        mdAfterOrderedList := md
      }

      if (showPoster) {
        PasteMd._BusyUpdate("Applying poster labels")
        assistantLabel := PasteMd._ResolveAssistantLabel(cfHtml)
        ; Collect positions of all poster placeholders in document order.
        posters := []
        pos := 1
        while RegExMatch(md, "m)^¤POSTER_(?:AI|User)¤$", &pm, pos) {
          posters.Push({type: InStr(pm[0], "AI") ? "AI" : "User", pos: pm.Pos, len: pm.Len})
          pos := pm.Pos + pm.Len
        }
        ; Remove consecutive duplicates, iterating backwards to preserve offsets.
        i := posters.Length
        while i > 1 {
          if (posters[i].type = posters[i - 1].type) {
            endPos := posters[i].pos + posters[i].len
            while (SubStr(md, endPos, 1) = "`n")
              endPos++
            md := SubStr(md, 1, posters[i].pos - 1) SubStr(md, endPos)
            posters.RemoveAt(i)
          }
          i--
        }
        ; Apply quoting BEFORE replacing poster placeholders. This way the
        ; placeholder (¤POSTER_AI¤) becomes "> ¤POSTER_AI¤" and can be
        ; distinguished from quoted source text (for example a literal
        ; heading/content line that starts with "## ...").
        if (asQuoted)
          md := PasteMd.QuoteMarkdown(md)
        ; Replace remaining placeholders with H2 heading labels.
        ; Placeholders may be prefixed with "> " if quoting is active.
        md := RegExReplace(md, "m)^(?:> )?¤POSTER_AI¤$", "## " assistantLabel)
        md := RegExReplace(md, "m)^(?:> )?¤POSTER_User¤$", "## User")
        ; Keep spacing around poster headings truly blank when quote mode is on:
        ; convert adjacent standalone ">" spacer lines back to empty lines.
        if (asQuoted)
          md := PasteMd.UnquoteBlankLinesAroundPosterHeadings(md)
        ; If no placeholders were found the fragment had no message container
        ; divs (partial selection). Fall back to the pre-fragment cfHtml context.
        if (posters.Length = 0 && cfHtml != "") {
          poster := PasteMd._ExtractPosterFromContext(cfHtml)
          if (poster = "AI")
            poster := assistantLabel
          if (poster != "")
            md := "## " poster "`n`n" md
        }
      } else if (asQuoted) {
        PasteMd._BusyUpdate("Applying quote formatting")
        md := PasteMd.QuoteMarkdown(md)
      }

      mdAfterPoster := md
      md := PasteMd.EnsureTrailingEolForList(md)

      ; Remove CR unconditionally (LF-only).
      md := StrReplace(md, "`r", "")

      return Map(
        "source", source,
        "htmlFrag", htmlFrag,
        "htmlPrep", htmlPrep,
        "mdRaw", mdRaw,
        "mdAfterClean", mdAfterClean,
        "mdAfterOrderedList", mdAfterOrderedList,
        "mdAfterPoster", mdAfterPoster,
        "finalMd", md,
        "expectedListStart", expectedListStart,
        "usedNoHtmlPath", usedNoHtmlPath,
        "usedNoTagPlainPath", usedNoTagPlainPath,
        "aborted", aborted
      )
    } finally {
      PasteMd.SHOW_IMG := prevShowImg
      PasteMd.PROMPT_ORDERED_LIST_START_ON_AMBIGUOUS := prevPromptOrderedList
    }
  }

  /**
   * Converts clipboard content to markdown (or quoted markdown) and pastes it.
   * Prefers CF_HTML → pandoc conversion, with plain-text fallback.
   * @param {boolean} asQuoted - If true, prefixes every line with blockquote syntax (>).
   */
  static PasteMarkdown(asQuoted) {
    PasteMd._BusyStart("Reading clipboard")
    dbg := PasteMd.DEBUG_PASTE_MD
    if (dbg) {
      ; New paste — clear any pin state so the checkmark doesn't carry over.
      if (PasteMd._lastPinPath != "") {
        PasteMd._lastPinPath := ""
        PasteMd.gPasteMenu.Uncheck("Pin current &log")
      }
      PasteMd._RotateLogFiles()
      dbgOpenStack := PasteMd._CaptureStack("PasteMd.PasteMarkdown debug-log open")
      dbgF := FileOpen(PasteMd.DEBUG_PASTE_MD_LOG, "w", "UTF-8")
      dbgF.Write("PasteAsMd debug — " FormatTime(, "yyyy-MM-dd HH:mm:ss") "`n`n")
      PasteMd._DbgSection(dbgF, "0. debug stack (log-open caller)", dbgOpenStack)
    }

    clipSaved := ClipboardAll()
    plain := StrReplace(A_Clipboard, "`r", "")
    try {
      PasteMd._BusyUpdate()
      cfHtml := ClipboardWaiter.GetHtml()
      PasteMd._BusyUpdate("Converting content")
      converted := PasteMd._ConvertFromCaptured(
        plain,
        cfHtml,
        asQuoted,
        asQuoted,
        PasteMd.SHOW_IMG,
        PasteMd.PROMPT_ORDERED_LIST_START_ON_AMBIGUOUS
      )
      md := converted["finalMd"]
      PasteMd._BusyUpdate("Preparing paste")

      if (dbg) {
        PasteMd._DbgSection(dbgF, "1. plain (A_Clipboard minus CR)", plain)
        PasteMd._DbgSection(dbgF, "2. cfHtml (raw full payload)", cfHtml)
        PasteMd._DbgSection(dbgF, "3. htmlFrag (CF_HTML fragment)", converted["htmlFrag"])
        dbgF.Write("=== 2b. cfHtml offsets ===`n")
        dbgF.Write("StartHTML: " PasteMd.ParseCfHtmlOffsetRaw(cfHtml, "StartHTML:") "`n")
        dbgF.Write("EndHTML: " PasteMd.ParseCfHtmlOffsetRaw(cfHtml, "EndHTML:") "`n")
        dbgF.Write("StartFragment: " PasteMd.ParseCfHtmlOffsetRaw(cfHtml, "StartFragment:") "`n")
        dbgF.Write("EndFragment: " PasteMd.ParseCfHtmlOffsetRaw(cfHtml, "EndFragment:") "`n`n")

        if (converted["htmlFrag"] = "") {
          PasteMd._DbgSection(dbgF, "3. md (CleanPlainText – no HTML path)", converted["mdAfterClean"])
        } else {
          PasteMd._DbgSection(dbgF, "3. htmlPrep (after _PreprocessHtml)", converted["htmlPrep"])
          if (converted["usedNoTagPlainPath"]) {
            PasteMd._DbgSection(dbgF, "3b. md (no HTML tags → plain text path)", converted["mdAfterClean"])
          } else {
            PasteMd._DbgSection(dbgF, "4. mdRaw (pandoc output)", converted["mdRaw"])
            PasteMd._DbgSection(dbgF, "5. md (after CleanMarkdown)", converted["mdAfterClean"])
          }
          PasteMd._DbgSection(dbgF, "5c. expected list start (ordered-list fix)", "" converted["expectedListStart"])
          PasteMd._DbgSection(dbgF, "5d. md (after RestoreOrderedListStart)", converted["mdAfterOrderedList"])
        }

        if (asQuoted)
          PasteMd._DbgSection(dbgF, "5e. md (after SHOW_POSTER replacement)", converted["mdAfterPoster"])

        PasteMd._DbgSection(dbgF, "6. FINAL md (pasted)", md)
        dbgF.Close()
      }

      if (converted["aborted"])
        return

      pastePayload := md
      pasteWithSentinel := false
      ; Text boxes vary on terminal newline handling (CRLF-aware vs LF-aware),
      ; and some also normalize/filter trailing spaces during paste. Use "."
      ; as a non-space sentinel, then backspace it after paste.
      if (RegExMatch(md, "\n$")) {
        pastePayload .= "."
        pasteWithSentinel := true
      }

      PasteMd._BusyUpdate("Pasting")
      A_Clipboard := pastePayload
      Send "^v"
      if (pasteWithSentinel) {
        Sleep PasteMd.PASTE_SENTINEL_DELAY_MS
        Send "{BS}"
      }
      Sleep PasteMd.PASTE_DELAY_MS
    } catch as e {
      if (dbg) {
        try {
          dbgF.Write("!!! EXCEPTION: " e.File ":" e.Line " — " e.Message "`n")
          dbgF.Write("!!! EXCEPTION STACK:`n" e.Stack "`n")
          dbgF.Close()
        }
      }
      MsgBox "Paste-as-markdown " e.File ":" e.Line " failed:`n`n" e.Message
    } finally {
      PasteMd._BusyEnd()
      A_Clipboard := clipSaved
    }
  }

  /**
   * Runs pandoc to convert HTML content to GitHub-flavored markdown.
   * @param {string} html - HTML content to convert
   * @param {string} pandocExe - Path to pandoc executable
   * @returns {string} Markdown text, or empty string on conversion/read failure
   */
  static HtmlToGfmViaPandoc(html, pandocExe) {
    tmpBase := A_Temp "\chatgpt_md_" A_TickCount
    tmpHtml := tmpBase ".html"
    tmpMd := tmpBase ".md"

    try FileDelete tmpHtml
    try FileDelete tmpMd

    ; Write UTF-8 without BOM.
    f := FileOpen(tmpHtml, "w", "UTF-8-RAW")
    f.Write(html)
    f.Close()

    ; No wrapping, LF-only.
    cmd := '"' pandocExe '" -f html -t gfm --wrap=none --eol=lf "' tmpHtml '"'
    cmd .= ' -o "' tmpMd '"'

    PasteMd._BusyUpdate("Converting via pandoc")
    exitCode := RunWait(cmd, , "Hide")
    if (exitCode != 0) {
      try FileDelete tmpHtml
      try FileDelete tmpMd
      return ""
    }

    PasteMd._BusyUpdate("Reading conversion output")
    md := ""
    try {
      md := FileRead(tmpMd, "UTF-8")
    } catch {
      md := ""
    }

    try FileDelete tmpHtml
    try FileDelete tmpMd

    return md
  }

  /**
   * Normalizes plain text for markdown-safe paste.
   * Removes CR, trims trailing whitespace, and removes edge blank lines.
   * @param {string} s - Text to normalize
   * @returns {string} Normalized text
   */
  static CleanPlainText(s) {
    s := StrReplace(s, "`r", "")
    lines := StrSplit(s, "`n")
    out := ""
    for i, line in lines {
      line := RTrim(line, " `t")
      out .= (i = 1 ? "" : "`n") line
    }
    return Trim(out, "`n")
  }

  /**
   * Normalizes markdown lines and simplifies inline HTML.
   * Preserves fenced code blocks. Removes empty headings.
   * @param {string} md - Markdown text to clean
   * @returns {string} Cleaned markdown
   */
  static CleanMarkdown(md) {
    md := StrReplace(md, "`r", "")
    hadTrailingBreak := RegExMatch(md, "\n$")

    ; Strip <span> tags (presentational wrappers that cause backtick accumulation).
    md := RegExReplace(md, "i)</?span\b[^>]*+>", "")

    ; Convert <br> tags to newlines so line breaks are preserved.
    md := RegExReplace(md, "i)<br\b[^>]*+>", "`n")

    ; Convert block-level <code> elements (multi-line) to fenced code blocks.
    pos := 1
    while RegExMatch(md, "s)<code\b([^>]*+)>(.*?)</code>", &m, pos) {
      if InStr(m[2], "`n") {
        ; Extract language identifier from class="language-xxx" if present.
        lang := RegExMatch(m[1], "i)language-(\w++)", &langM) ? langM[1] : ""
        inner := RegExReplace(m[2], "<[^>]++>", "")
        inner := PasteMd.DecodeBasicHtmlEntities(inner)
        inner := Trim(inner, " `t`n")
        replacement := PasteMd.CODE_FENCE lang "`n" inner "`n" PasteMd.CODE_FENCE
        md := SubStr(md, 1, m.Pos - 1) replacement SubStr(md, m.Pos + m.Len)
        pos := m.Pos + StrLen(replacement)
      } else {
        pos := m.Pos + m.Len
      }
    }

    lines := StrSplit(md, "`n")

    out := ""
    inFence := false

    for i, line in lines {
      t := LTrim(line, " `t")

      ; Fence detection without regex (avoids backtick-escape problems).
      if (SubStr(t, 1, StrLen(PasteMd.CODE_FENCE)) = PasteMd.CODE_FENCE) {
        inFence := !inFence
        outLine := line
        out .= (out = "" ? "" : "`n") outLine
        continue
      }

      if (inFence) {
        out .= (out = "" ? "" : "`n") line
        continue
      }

      rawLine := line
      outLine := rawLine

      ; Drop empty headings like "###" or "### ".
      if RegExMatch(outLine, "^[#]{1,6}+[ \t]*+$") {
        continue
      }

      outLine := PasteMd.SimplifyMarkdownInlineHtml(outLine)
      ; Unescape literal details/summary tags and [img: ...] placeholders.
      outLine := RegExReplace(outLine, "\\(<\/?(?:details|summary)\b[^>]*+>)", "$1")
      outLine := RegExReplace(outLine, "\\\[(img(?::[^\]]*+)?)\\\]", "[$1]")
      out .= (out = "" ? "" : "`n") outLine
    }

    ; Collapse runs of 3+ newlines to 2 (at most one blank line).
    out := RegExReplace(out, "\n{3,}+", "`n`n")
    if (hadTrailingBreak && out != "")
      out .= "`n"
    return out
  }

  /**
   * PCRE regex subroutine library for HTML parsing and backtick code spans.
   * Includes recursive subroutines for robust HTML tag matching,
   * plus a generic backtick code span pattern for any delimiter length.
   */
  static RE_HTML_LIB := "
(
  |(?x)(?!)
  (?<quoted_string> (?<quote>["'])(?:[^"'\\]*+|\\.|(?!\k<quote>).)++\k<quote>)
  (?<inside_htag>
    (?:
        [^<>\\'"]++                            (?# non-tag marker )
      | \\.                                    (?# non-escape marker )
      | (?&quoted_string)
      | < (?!/) (?<inner_id>[a-z]++) (?: [^>'"]++ | (?=['"])(?&quoted_string) )*+
        (?:
            (?<= / ) >                         (?# open/close tag so nothing inside )
          | > (?&inside_htag) </ \k<inner_id>\b >
        `)
    `)*+
  `)
  (?<codespan>(?<bt_open>``++)(?:[^``]++|(?!\k<bt_open>).)++\k<bt_open>)
  )"

  /**
   * Converts common inline HTML constructs to markdown equivalents.
   * Strips residual non-escaped tags that reduce readability.
   * Handles <code>, <strong>, <b>, <em>, <i>, and <a> tags.
   * @param {string} line - Text line containing HTML
   * @returns {string} Line with HTML converted to markdown
   */
  static SimplifyMarkdownInlineHtml(line) {
    line := PasteMd.DecodeBasicHtmlEntities(line)

    while RegExMatch(line, "<code\b[^>]*+>((?&inside_htag))</code>" PasteMd.RE_HTML_LIB, &m) {
      inner := PasteMd.DecodeBasicHtmlEntities(m[1])
      inner := StrReplace(inner, "`r", "")
      inner := StrReplace(inner, "`n", " ")
      replacement := (inner = "") ? "" : ("``" inner "``")
      line := SubStr(line, 1, m.Pos - 1) replacement SubStr(line, m.Pos + m.Len)
    }

    ; Convert semantic emphasis tags before fallback stripping.
    while RegExMatch(line, "<(strong|b)\b[^>]*+>((?&inside_htag))</\1>" PasteMd.RE_HTML_LIB, &m) {
      replacement := (m[2] = "") ? "" : ("**" m[2] "**")
      line := SubStr(line, 1, m.Pos - 1) replacement SubStr(line, m.Pos + m.Len)
    }
    while RegExMatch(line, "<(em|i)\b[^>]*+>((?&inside_htag))</\1>" PasteMd.RE_HTML_LIB, &m) {
      replacement := (m[2] = "") ? "" : ("*" m[2] "*")
      line := SubStr(line, 1, m.Pos - 1) replacement SubStr(line, m.Pos + m.Len)
    }

    ; Convert HTML links to markdown links for readable output.
    while RegExMatch(line, "<a\b[^>]*\bhref\s*+=\s*+(['`"])(.*?)\1[^>]*+>((?&inside_htag))</a>" PasteMd.RE_HTML_LIB, &m) {
      href := PasteMd.DecodeBasicHtmlEntities(m[2])
      text := PasteMd.DecodeBasicHtmlEntities(m[3])

      ; Convert semantic emphasis inside link text before stripping residual tags.
      while RegExMatch(text, "<(strong|b)\b[^>]*+>((?&inside_htag))</\1>" PasteMd.RE_HTML_LIB, &inner) {
        replacement := (inner[2] = "") ? "" : ("**" inner[2] "**")
        text := SubStr(text, 1, inner.Pos - 1) replacement SubStr(text, inner.Pos + inner.Len)
      }
      while RegExMatch(text, "<(em|i)\b[^>]*+>((?&inside_htag))</\1>" PasteMd.RE_HTML_LIB, &inner) {
        replacement := (inner[2] = "") ? "" : ("*" inner[2] "*")
        text := SubStr(text, 1, inner.Pos - 1) replacement SubStr(text, inner.Pos + inner.Len)
      }

      ; Remove any unknown tags that are not escaped
      text := RegExReplace(text, "((?&inside_htag))<[^>]++>" PasteMd.RE_HTML_LIB, "$1")
      if (text = "") {
        text := href
      }
      replacement := "[" text "](" href ")"
      line := SubStr(line, 1, m.Pos - 1) replacement SubStr(line, m.Pos + m.Len)
    }

    ; Protect backtick code spans from tag stripping.
    _codeSpans := []
    pos := 1
    while RegExMatch(line, "(?&codespan)" PasteMd.RE_HTML_LIB, &m, pos) {
      _codeSpans.Push(m[0])
      placeholder := "¤CSPAN_" _codeSpans.Length "¤"
      line := SubStr(line, 1, m.Pos - 1) placeholder SubStr(line, m.Pos + m.Len)
      pos := m.Pos + StrLen(placeholder)
    }

    ; Remove any unknown tags that are not escaped
    line := RegExReplace(line, "\G((?&inside_htag))(?<!\\)<(?:[^>'`"]++|(?&quoted_string))*+>" PasteMd.RE_HTML_LIB, "$1")
    line := RegExReplace(line, "((?:[^\\]|\\[^<>])++)\\([<>])" PasteMd.RE_HTML_LIB, "$1$2")

    ; Restore backtick code spans.
    for i, span in _codeSpans {
      line := StrReplace(line, "¤CSPAN_" i "¤", span)
    }

    return line
  }

  /**
   * Decodes common HTML entities used in clipboard fragments.
   * Handles &nbsp;, &quot;, &apos;, &lt;, &gt;, &amp;, and numeric entity references.
   * @param {string} s - Text containing HTML entities
   * @returns {string} Text with entities decoded
   */
  static DecodeBasicHtmlEntities(s) {
    s := StrReplace(s, "&nbsp;", Chr(160))
    s := StrReplace(s, "&#160;", Chr(160))
    s := StrReplace(s, "&quot;", '"')
    s := StrReplace(s, "&#34;", '"')
    s := StrReplace(s, "&apos;", "'")
    s := StrReplace(s, "&#39;", "'")
    s := StrReplace(s, "&lt;", "<")
    s := StrReplace(s, "&gt;", ">")
    s := StrReplace(s, "&amp;", "&")
    return s
  }

  /**
   * Replaces `<img>` and `<svg>` elements in a string according to SHOW_IMG.
   *
   * When SHOW_IMG is off:
   *   - No accessible text (alt / title / aria-label / SVG `<title>`): dropped.
   *   - Has accessible text: replaced with `(img: <text>)`.
   *
   * When SHOW_IMG is on, leaves elements in place.
   * Called on both the pre-pandoc HTML and the post-pandoc markdown.
   *
   * @param {string} str - HTML or markdown string to process
   * @returns {string}
   */
  static _ProcessImgTags(str) {
    ; <img> tags (self-closing).
    pos := 1
    while RegExMatch(str, "i)<img\b([^>]*+)>", &m, pos) {
      if (PasteMd.SHOW_IMG) {
        pos := m.Pos + m.Len
      } else {
        attrs := m[1]
        accessText := ""
        if (RegExMatch(attrs, "i)\balt\s*+=\s*+['`"]([^'`"]*+)['`"]", &mA) && mA[1] != "")
          accessText := mA[1]
        else if (RegExMatch(attrs, "i)\btitle\s*+=\s*+['`"]([^'`"]*+)['`"]", &mT) && mT[1] != "")
          accessText := mT[1]
        else if (RegExMatch(attrs, "i)\baria-label\s*+=\s*+['`"]([^'`"]*+)['`"]", &mL) && mL[1] != "")
          accessText := mL[1]
        replacement := (accessText = "") ? "" : "(img: " accessText ")"
        str := SubStr(str, 1, m.Pos - 1) replacement SubStr(str, m.Pos + m.Len)
        pos := m.Pos + StrLen(replacement)
      }
    }
    ; <svg>…</svg> elements — same rule (aria-label, title attr, or <title> child).
    pos := 1
    while RegExMatch(str, "is)<svg\b([^>]*+)>.*?</svg>", &m, pos) {
      if (PasteMd.SHOW_IMG) {
        pos := m.Pos + m.Len
      } else {
        attrs := m[1]
        full  := m[0]
        accessText := ""
        if (RegExMatch(attrs, "i)\baria-label\s*+=\s*+['`"]([^'`"]*+)['`"]", &mL) && mL[1] != "")
          accessText := mL[1]
        else if (RegExMatch(attrs, "i)\btitle\s*+=\s*+['`"]([^'`"]*+)['`"]", &mT) && mT[1] != "")
          accessText := mT[1]
        else if (RegExMatch(full, "i)<title\b[^>]*+>(.*?)</title>", &mTc) && mTc[1] != "")
          accessText := mTc[1]
        replacement := (accessText = "") ? "" : "(img: " accessText ")"
        str := SubStr(str, 1, m.Pos - 1) replacement SubStr(str, m.Pos + m.Len)
        pos := m.Pos + StrLen(replacement)
      }
    }
    return str
  }

  /**
   * Preprocesses HTML via HtmlNorm.Normalize(), then copies the resulting
   * _thinkingBlocks / _userMsgBlocks arrays into PasteMd so that
   * RestoreThinkingBlocks / RestoreUserMsgBlocks work unchanged.
   *
   * @param {string} htmlFrag - HTML fragment from the CF_HTML clipboard
   * @param {string} cfHtml   - Full CF_HTML payload (for source detection)
   * @param {boolean} showPoster - If true, keep poster placeholders for label replacement
   * @returns {string} Preprocessed HTML ready for pandoc
   */
  static _PreprocessHtml(htmlFrag, cfHtml, showPoster) {
    html := HtmlNorm.Normalize(htmlFrag, DetectSource(cfHtml), showPoster, PasteMd.SHOW_IMG)
    PasteMd._thinkingBlocks := HtmlNorm._thinkingBlocks
    PasteMd._userMsgBlocks  := HtmlNorm._userMsgBlocks
    return html
  }

  /**
   * Normalizes implicit list intent before pandoc conversion.
   *
   * Some sources emit bare top-level <li> fragments with no explicit <ol>/<ul>
   * container. HtmlNorm wraps these in <ol> to keep valid structure for pandoc,
   * but for incidental unordered selections this creates false numbering.
   *
   * This method converts the synthetic outer <ol> to <ul> for multi-item bare
   * <li> fragments when ordered intent is not inferred from clipboard context.
   *
   * @param {string} htmlPrep - Preprocessed HTML sent to pandoc
   * @param {string} htmlFrag - StartFragment HTML
   * @param {string} plain - Plain clipboard text
   * @param {number} expected - Inferred ordered-list start from context
   * @returns {string} HTML with corrected outer list intent
   */
  static NormalizeIncidentalListIntentHtml(htmlPrep, htmlFrag, plain, expected := 0) {
    nodes := PasteMd._TryParseDomNodes(htmlPrep)
    if (nodes.Length = 0)
      return htmlPrep
    return PasteMd._NormalizeIncidentalListIntentDomNodes(nodes, htmlFrag, plain, expected)
      ? PasteMd._SerializeDomNodes(nodes)
      : htmlPrep
  }

  /**
   * Replaces ¤THINKING_N¤ placeholders with clean <details> HTML blocks.
   * @param {string} md - Markdown text containing placeholders
   * @returns {string} Markdown with thinking blocks restored as raw HTML
   */
  static RestoreThinkingBlocks(md) {
    for i, content in this._thinkingBlocks {
      placeholder := "¤THINKING_" i "¤"
      if (content = "") {
        details := "<details>`n<summary>Thinking</summary>`n</details>"
      } else {
        details := "<details>`n<summary>Thinking</summary>`n`n" content "`n</details>"
      }
      md := StrReplace(md, placeholder, details)
    }
    return md
  }

  /**
   * Replaces ¤USERMSG_N¤ placeholders with the raw user message text extracted
   * by HtmlNorm.  This content bypasses pandoc to preserve line
   * structure of markdown-like text (blockquotes, bold labels, etc.) the user
   * typed or pasted into the chat input.
   * @param {string} md - Markdown text containing placeholders
   * @returns {string} Markdown with user message content restored
   */
  static RestoreUserMsgBlocks(md) {
    for i, content in this._userMsgBlocks {
      placeholder := "¤USERMSG_" i "¤"
      md := StrReplace(md, placeholder, content)
    }
    return md
  }

  /**
   * Applies ordered-list start to the first ordered-list container in HTML.
   * Used pre-pandoc so numbering comes from HTML intent, not post-markdown rewrites.
   * @param {string} htmlPrep - Preprocessed HTML sent to pandoc
   * @param {number} startNum - Desired ordered-list start index
   * @returns {string} HTML with first <ol> start set when applicable
   */
  static ApplyOrderedListStartToHtml(htmlPrep, startNum) {
    if (htmlPrep = "" || startNum <= 1)
      return htmlPrep

    nodes := PasteMd._TryParseDomNodes(htmlPrep)
    if (nodes.Length = 0)
      return htmlPrep

    return PasteMd._ApplyOrderedStartDomNodes(nodes, startNum)
      ? PasteMd._SerializeDomNodes(nodes)
      : htmlPrep
  }

  /**
   * Inserts a shell marker into list items that contain only a nested list.
   * This prevents pandoc from collapsing them into malformed mixed list markers.
   * @param {string} html - HTML prior to pandoc conversion
   * @returns {string} HTML with shell markers inserted
   */
  static StabilizeShellOnlyListItemsHtml(html) {
    if (html = "")
      return html

    nodes := PasteMd._TryParseDomNodes(html)
    if (nodes.Length = 0)
      return html

    return PasteMd._StabilizeShellOnlyListItemsDomNodes(nodes)
      ? PasteMd._SerializeDomNodes(nodes)
      : html
  }

  /**
   * Applies ordered-list start and shell-list-item stabilization in one DOM pass.
   * This avoids reparsing between two sequential pre-pandoc rewrites.
   * @param {string} html - HTML prior to pandoc conversion
   * @param {number} startNum - Ordered-list start index (<=1 means no start rewrite)
   * @returns {string} Rewritten HTML
   */
  static ApplyOrderedListStartAndStabilizeShellHtml(html, startNum) {
    if (html = "")
      return html

    nodes := PasteMd._TryParseDomNodes(html)
    if (nodes.Length = 0)
      return html
    return PasteMd._ApplyOrderedStartAndStabilizeShellDomNodes(nodes, startNum)
      ? PasteMd._SerializeDomNodes(nodes)
      : html
  }

  /**
   * Node-level worker for incidental list-intent normalization.
   * Converts synthetic top-level <ol> wrappers to <ul> for multi-item bare-<li>
   * fragments when ordered intent cannot be inferred.
   * @param {Array} nodes
   * @param {string} htmlFrag
   * @param {string} plain
   * @param {number} expected
   * @returns {boolean} True when DOM was changed
   */
  static _NormalizeIncidentalListIntentDomNodes(nodes, htmlFrag, plain, expected := 0) {
    if (htmlFrag = "")
      return false
    if (expected > 1)
      return false
    if (PasteMd._FirstMeaningfulTopTagName(htmlFrag) != "li")
      return false
    if (this.CountListItemsInFragment(htmlFrag) < 2)
      return false
    if RegExMatch(plain, "m)^[ \t]*+\d++[.)](?:[ \t]++|$)")
      return false

    top := PasteMd._TopLevelMeaningfulNodes(nodes)
    if (top.Length != 1 || !PasteMd._IsTag(top[1], "ol"))
      return false

    list := top[1]
    list.tag := "ul"
    changed := true

    ; Drop trailing empty list items produced by selection-range clipping.
    idx := list.children.Length
    while (idx >= 1) {
      child := list.children[idx]
      if (!PasteMd._IsTag(child, "li") || !PasteMd._IsEmptyListItemNode(child))
        break
      list.children.RemoveAt(idx)
      idx -= 1
    }
    return changed
  }

  /**
   * Node-level worker for ordered-list start and shell-list-item stabilization.
   * @param {Array} nodes
   * @param {number} startNum
   * @returns {boolean} True when DOM was changed
   */
  static _ApplyOrderedStartAndStabilizeShellDomNodes(nodes, startNum) {
    changed := PasteMd._ApplyOrderedStartDomNodes(nodes, startNum)
    if PasteMd._StabilizeShellOnlyListItemsDomNodes(nodes)
      changed := true
    return changed
  }

  /**
   * Node-level worker that applies ordered-list start to first <ol>.
   * @param {Array} nodes
   * @param {number} startNum
   * @returns {boolean}
   */
  static _ApplyOrderedStartDomNodes(nodes, startNum) {
    if (startNum <= 1)
      return false
    ol := PasteMd._FindFirstByTag(nodes, "ol")
    if !IsObject(ol)
      return false
    PasteMd._SetAttrCI(ol, "start", "" startNum)
    return true
  }

  /**
   * Node-level worker that inserts shell markers for list items with nested lists.
   * @param {Array} nodes
   * @returns {boolean}
   */
  static _StabilizeShellOnlyListItemsDomNodes(nodes) {
    marker := PasteMd._shellListItemPlaceholder
    listItems := []
    PasteMd._CollectNodesByTag(nodes, "li", &listItems)
    changed := false
    for li in listItems {
      idx := PasteMd._FirstMeaningfulChildIndex(li)
      if (idx < 1)
        continue
      first := li.children[idx]
      if !(PasteMd._IsTag(first, "ol") || PasteMd._IsTag(first, "ul"))
        continue
      if (PasteMd._LeadingListShellHasMarker(li, idx, marker))
        continue
      li.children.InsertAt(idx, DomNode("text", "", marker))
      changed := true
    }
    return changed
  }

  /**
   * Parses HTML into DOM nodes for pre-pandoc HTML rewrites.
   * @param {string} html
   * @returns {Array}
   */
  static _TryParseDomNodes(html) {
    if (html = "")
      return []
    try {
      return HtmlParser.Parse(html)
    } catch {
      return []
    }
  }

  /**
   * Serializes DOM nodes back to HTML.
   * @param {Array} nodes
   * @returns {string}
   */
  static _SerializeDomNodes(nodes) {
    return HtmlNorm._SerializeDomNodes(nodes)
  }

  /**
   * Returns meaningful top-level nodes (ignoring whitespace-only text nodes).
   * @param {Array} nodes
   * @returns {Array}
   */
  static _TopLevelMeaningfulNodes(nodes) {
    out := []
    for node in nodes
      if !PasteMd._IsWhitespaceTextNode(node)
        out.Push(node)
    return out
  }

  /**
   * True when node is a tag with the given case-insensitive name.
   * @param {DomNode} node
   * @param {string} tagName
   * @returns {boolean}
   */
  static _IsTag(node, tagName) {
    return IsObject(node)
      && (Type(node) = "DomNode")
      && (StrLower(node.tag) = StrLower(tagName))
  }

  /**
   * True when text node contains only horizontal/vertical whitespace.
   * @param {DomNode} node
   * @returns {boolean}
   */
  static _IsWhitespaceTextNode(node) {
    return IsObject(node)
      && (Type(node) = "DomNode")
      && (node.tag = "text")
      && (Trim(node.text, " `t`r`n") = "")
  }

  /**
   * Finds the first node by tag name in pre-order depth-first traversal.
   * @param {Array} nodes
   * @param {string} tagName
   * @returns {DomNode|string}
   */
  static _FindFirstByTag(nodes, tagName) {
    for node in nodes {
      if PasteMd._IsTag(node, tagName)
        return node
      if (node.children.Length > 0) {
        found := PasteMd._FindFirstByTag(node.children, tagName)
        if IsObject(found)
          return found
      }
    }
    return ""
  }

  /**
   * Sets/overwrites an attribute case-insensitively while preserving key casing.
   * @param {DomNode} node
   * @param {string} name
   * @param {string} value
   */
  static _SetAttrCI(node, name, value) {
    lower := StrLower(name)
    for k in node.attrs {
      if (StrLower(k) = lower) {
        node.attrs[k] := value
        return
      }
    }
    node.attrs[name] := value
  }

  /**
   * Gets an attribute value case-insensitively, or "" when absent.
   * @param {DomNode} node
   * @param {string} name
   * @returns {string}
   */
  static _GetAttrCI(node, name) {
    lower := StrLower(name)
    for k, v in node.attrs
      if (StrLower(k) = lower)
        return v
    return ""
  }

  /**
   * Returns positive integer from attribute value, or 0 when absent/invalid.
   * @param {DomNode} node
   * @param {string} name
   * @returns {integer}
   */
  static _GetNumericAttr(node, name) {
    value := Trim(PasteMd._GetAttrCI(node, name), " `t`r`n")
    if RegExMatch(value, "^\d++$")
      return Integer(value)
    return 0
  }

  /**
   * Finds first node with matching tag and a numeric attribute.
   * @param {Array} nodes
   * @param {string} tagName
   * @param {string} attrName
   * @returns {DomNode|string}
   */
  static _FindFirstByTagWithNumericAttr(nodes, tagName, attrName) {
    for node in nodes {
      if PasteMd._IsTag(node, tagName) {
        if (PasteMd._GetNumericAttr(node, attrName) > 0)
          return node
      }
      if (node.children.Length > 0) {
        found := PasteMd._FindFirstByTagWithNumericAttr(node.children, tagName, attrName)
        if IsObject(found)
          return found
      }
    }
    return ""
  }

  /**
   * Collects all descendant nodes matching a tag name.
   * @param {Array} nodes
   * @param {string} tagName
   * @param {Array} out
   */
  static _CollectNodesByTag(nodes, tagName, &out) {
    for node in nodes {
      if PasteMd._IsTag(node, tagName)
        out.Push(node)
      if (node.children.Length > 0)
        PasteMd._CollectNodesByTag(node.children, tagName, &out)
    }
  }

  /**
   * Returns first direct-child index that is not whitespace text, or 0.
   * @param {DomNode} node
   * @returns {integer}
   */
  static _FirstMeaningfulChildIndex(node) {
    idx := 1
    while (idx <= node.children.Length) {
      if !PasteMd._IsWhitespaceTextNode(node.children[idx])
        return idx
      idx += 1
    }
    return 0
  }

  /**
   * Detects whether the leading shell area already contains the placeholder marker.
   * @param {DomNode} li
   * @param {integer} firstMeaningfulIdx
   * @param {string} marker
   * @returns {boolean}
   */
  static _LeadingListShellHasMarker(li, firstMeaningfulIdx, marker) {
    idx := 1
    while (idx < firstMeaningfulIdx) {
      child := li.children[idx]
      if ((child.tag = "text") && InStr(child.text, marker))
        return true
      idx += 1
    }
    return false
  }

  /**
   * True when a list item is effectively empty:
   * - only whitespace text children, or
   * - a single empty <p> child with optional surrounding whitespace text.
   * @param {DomNode} li
   * @returns {boolean}
   */
  static _IsEmptyListItemNode(li) {
    if !PasteMd._IsTag(li, "li")
      return false

    meaningful := []
    for child in li.children
      if !PasteMd._IsWhitespaceTextNode(child)
        meaningful.Push(child)

    if (meaningful.Length = 0)
      return true

    if (meaningful.Length = 1 && PasteMd._IsTag(meaningful[1], "p"))
      return PasteMd._NodeTextRecursive(meaningful[1]) = ""

    return false
  }

  /**
   * Collects plain text recursively from a subtree.
   * @param {DomNode} node
   * @returns {string}
   */
  static _NodeTextRecursive(node) {
    if (node.tag = "text")
      return node.text
    out := ""
    for child in node.children
      out .= PasteMd._NodeTextRecursive(child)
    return out
  }

  /**
   * True when HTML contains tags beyond plain-text wrappers (<p>/<br>).
   * Used to decide whether pandoc conversion is necessary.
   * @param {string} html
   * @returns {boolean}
   */
  static _HasMeaningfulHtmlForPandoc(html) {
    nodes := PasteMd._TryParseDomNodes(html)
    if (nodes.Length = 0) {
      ; Keep legacy behavior when parsing fails.
      stripped := RegExReplace(html, "i)<br\b[^>]*+>", "")
      stripped := RegExReplace(stripped, "i)</?p\b[^>]*+>", "")
      return RegExMatch(stripped, "<[^>]++>")
    }
    return PasteMd._HasMeaningfulHtmlNode(nodes)
  }

  /**
   * Recursive worker for _HasMeaningfulHtmlForPandoc.
   * @param {Array|DomNode} nodeOrNodes
   * @returns {boolean}
   */
  static _HasMeaningfulHtmlNode(nodeOrNodes) {
    if (nodeOrNodes is Array) {
      for node in nodeOrNodes
        if PasteMd._HasMeaningfulHtmlNode(node)
          return true
      return false
    }

    node := nodeOrNodes
    if (node.tag = "text")
      return false
    if (PasteMd._IsTag(node, "br"))
      return false
    if PasteMd._IsTag(node, "p")
      return PasteMd._HasMeaningfulHtmlNode(node.children)
    return true
  }

  /**
   * Removes shell list-item markers inserted pre-pandoc.
   * @param {string} md - Markdown text after cleanup stages
   * @returns {string} Markdown with shell markers removed
   */
  static RemoveListShellPlaceholders(md) {
    marker := PasteMd._shellListItemPlaceholder
    if !InStr(md, marker)
      return md

    md := StrReplace(md, marker, "")
    return md
  }

  /**
   * Prompts for ordered-list start when list intent is ordered but start is ambiguous.
   * @param {string} htmlPrep - Preprocessed HTML (after list-intent normalization)
   * @param {string} plain - Plain clipboard text
   * @param {string} htmlFrag - StartFragment HTML
   * @param {number} expected - Inferred start index from available context
   * @returns {Map} {aborted:boolean, value:number}
   */
  static MaybePromptOrderedListStart(htmlPrep, plain, htmlFrag, expected) {
    if !this.ShouldPromptOrderedListStart(htmlPrep, htmlFrag, expected)
      return Map("aborted", false, "value", expected)

    defaultStart := 2
    if RegExMatch(plain, "m)^[ \t]*+(\d++)[.)](?:[ \t]++|$)", &mPlain) {
      nPlain := Integer(mPlain[1])
      if (nPlain >= 1)
        defaultStart := nPlain
    }

    promptFn := PasteMd._orderedListPromptFn
    if !IsObject(promptFn)
      promptFn := PasteMd._defaultOrderedListPromptFn

    rawResponse := promptFn.Call(defaultStart, expected, plain, htmlFrag)
    parsed := PasteMd.ParseOrderedListPromptResponse(rawResponse)
    if (parsed["status"] = "cancel")
      return Map("aborted", true, "value", expected)
    if (parsed["status"] != "ok")
      throw Error("Invalid ordered-list prompt response: " rawResponse)
    return Map("aborted", false, "value", parsed["value"])
  }

  /**
   * Determines whether ordered-list start prompt should run pre-pandoc.
   * @param {string} htmlPrep - Preprocessed HTML (after list-intent normalization)
   * @param {string} htmlFrag - StartFragment HTML
   * @param {number} expected - Inferred start index from available context
   * @returns {boolean} True when prompt should be shown
   */
  static ShouldPromptOrderedListStart(htmlPrep, htmlFrag, expected) {
    if (expected > 1)
      return false

    if (htmlPrep = "" || htmlFrag = "")
      return false

    prepTop := PasteMd._FirstMeaningfulTopTagName(htmlPrep)
    fragTop := PasteMd._FirstMeaningfulTopTagName(htmlFrag)

    ; Explicit unordered fragments are never prompted.
    if (prepTop = "ul")
      return false
    if (fragTop = "ul")
      return false

    ; Prompt for explicit ordered containers when start could not be inferred.
    if (prepTop = "ol")
      return true
    if (fragTop = "ol")
      return true

    ; Bare top-level <li> fragments remain ambiguous.
    if (fragTop = "li")
      return true

    return false
  }

  /**
   * Parses ordered-list prompt responses.
   * Accepted responses are integer >= 1, or CANCEL.
   * @param {any} response - Prompt callback return value
   * @returns {Map} {status:"ok|cancel|invalid", value:number}
   */
  static ParseOrderedListPromptResponse(response) {
    value := Trim("" response, " `t")
    if (StrUpper(value) = "CANCEL")
      return Map("status", "cancel", "value", 0)

    if RegExMatch(value, "^\d++$") {
      n := Integer(value)
      if (n >= 1)
        return Map("status", "ok", "value", n)
    }

    return Map("status", "invalid", "value", 0)
  }

  /**
   * Runtime ordered-list prompt dialog with inline validation feedback.
   * @param {number} defaultStart - Default list-start value shown in the input
   * @returns {string|number} Integer >=1, or "CANCEL"
   */
  static _PromptOrderedListStartDialog(defaultStart, expected := 0, plain := "", htmlFrag := "") {
    isDark := PasteMd._IsDarkModeEnabled()
    state := { status: "cancel", value: 0 }

    gui := Gui("+AlwaysOnTop +OwnDialogs", "Paste as md: list start")
    gui.MarginX := 14
    gui.MarginY := 12
    if (isDark)
      gui.BackColor := "202020"

    gui.SetFont("s9", "Segoe UI")
    if (isDark)
      gui.SetFont("cE6E6E6")

    gui.AddText("xm w460"
      , "Original ordered-list index is missing from clipboard context."
      . "`nEnter starting number (>= 1), or Cancel to abort paste.")
    edit := gui.AddEdit("xm w140", "" defaultStart)

    errOpts := "xm w460 Hidden "
    errOpts .= isDark ? "cFF8A8A" : "cCC0000"
    err := gui.AddText(errOpts, "Enter a whole number greater than or equal to 1.")

    okBtn := gui.AddButton("xm w90 Default", "OK")
    cancelBtn := gui.AddButton("x+8 w90", "Cancel")

    if (isDark) {
      edit.Opt("Background2B2B2B cF0F0F0")
      okBtn.Opt("Background3A3A3A cF0F0F0")
      cancelBtn.Opt("Background3A3A3A cF0F0F0")
    }

    okHandler := ObjBindMethod(PasteMd, "_PromptOrderedListSubmit", gui, edit, err, state)
    cancelHandler := ObjBindMethod(PasteMd, "_PromptOrderedListCancel", gui, state)
    okBtn.OnEvent("Click", okHandler)
    cancelBtn.OnEvent("Click", cancelHandler)
    gui.OnEvent("Close", cancelHandler)
    gui.OnEvent("Escape", cancelHandler)

    gui.Show("AutoSize")
    PasteMd._TrySetDarkTitleBar(gui.Hwnd, isDark)
    edit.Focus()
    edit.Select()

    WinWaitClose("ahk_id " gui.Hwnd)
    return (state.status = "ok") ? state.value : "CANCEL"
  }

  /**
   * Handles ordered-list prompt submission click.
   */
  static _PromptOrderedListSubmit(gui, edit, err, state, *) {
    value := Trim(edit.Text, " `t")
    if !RegExMatch(value, "^\d++$") || Integer(value) < 1 {
      err.Visible := true
      err.Redraw()
      edit.Focus()
      edit.Select()
      return
    }

    state.status := "ok"
    state.value := Integer(value)
    if WinExist("ahk_id " gui.Hwnd)
      gui.Destroy()
  }

  /**
   * Handles ordered-list prompt cancellation events.
   */
  static _PromptOrderedListCancel(gui, state, *) {
    state.status := "cancel"
    if WinExist("ahk_id " gui.Hwnd)
      gui.Destroy()
  }

  /**
   * Returns true when Windows app theme is dark.
   */
  static _IsDarkModeEnabled() {
    try {
      val := RegRead(
        "HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize",
        "AppsUseLightTheme",
        1
      )
    } catch {
      return false
    }
    return ((val + 0) = 0)
  }

  /**
   * Attempts to apply dark/light titlebar styling on Windows.
   */
  static _TrySetDarkTitleBar(hwnd, enableDark) {
    value := enableDark ? 1 : 0
    for attr in [20, 19] {
      try {
        hr := DllCall("dwmapi\DwmSetWindowAttribute"
          , "ptr", hwnd
          , "int", attr
          , "int*", value
          , "int", 4
          , "int")
        if (hr = 0)
          return true
      } catch {
        return false
      }
    }
    return false
  }

  /**
   * Counts <li> elements present in an HTML fragment.
   * @param {string} htmlFrag - StartFragment HTML
   * @returns {number} Number of <li> tags in fragment
   */
  static CountListItemsInFragment(htmlFrag) {
    if (htmlFrag = "")
      return 0

    nodes := PasteMd._TryParseDomNodes(htmlFrag)
    if (nodes.Length = 0) {
      count := 0
      pos := 1
      while RegExMatch(htmlFrag, "is)<li\b", , pos) {
        count += 1
        pos += 3
      }
      return count
    }

    out := []
    PasteMd._CollectNodesByTag(nodes, "li", &out)
    return out.Length
  }

  /**
   * Returns the first meaningful top-level tag name, or "".
   * @param {string} html
   * @returns {string}
   */
  static _FirstMeaningfulTopTagName(html) {
    nodes := PasteMd._TryParseDomNodes(html)
    if (nodes.Length = 0)
      return ""
    top := PasteMd._TopLevelMeaningfulNodes(nodes)
    if (top.Length = 0)
      return ""
    return StrLower(top[1].tag)
  }

  /**
   * Determines expected start index for selected ordered-list fragment.
   * Priority:
   * 1) <li value="N"> on fragment
   * 2) parent <ol start="N"> + preceding sibling <li> count from CF_HTML
   * 3) fragment <ol start="N">
   * 4) leading plain-text list number
   * Fragment-shape note:
   * CF_HTML StartFragment is tag-aligned valid HTML. For partial selection
   * inside list-item text, many sources still supply a full <li> node, so
   * partial list-item extent is not supplied in fragment payload.
   * @param {string} htmlFrag - StartFragment HTML
   * @param {string} cfHtml - Full CF_HTML payload
   * @param {string} plain - Plain clipboard text
   * @returns {number} Expected list index, or 0 when unknown
   */
  static GetExpectedOrderedListStart(htmlFrag, cfHtml, plain) {
    fragNodes := PasteMd._TryParseDomNodes(htmlFrag)
    if (fragNodes.Length > 0) {
      firstLiWithValue := PasteMd._FindFirstByTagWithNumericAttr(fragNodes, "li", "value")
      if IsObject(firstLiWithValue) {
        nValue := PasteMd._GetNumericAttr(firstLiWithValue, "value")
        if (nValue > 0)
          return nValue
      }
    }

    n := this.GetListStartFromHtmlContext(cfHtml, htmlFrag)
    if (n > 0)
      return n

    if (fragNodes.Length > 0) {
      top := PasteMd._TopLevelMeaningfulNodes(fragNodes)
      if (top.Length > 0 && PasteMd._IsTag(top[1], "ol")) {
        nStart := PasteMd._GetNumericAttr(top[1], "start")
        if (nStart > 0)
          return nStart
      }
    }

    if RegExMatch(plain, "^[ \t]*+(\d++)[.)](?:[ \t]++|$)", &mPlain) {
      return Integer(mPlain[1])
    }

    return 0
  }

  /**
   * Infers ordered-list index at StartFragment from full CF_HTML context.
   * Tracks nested list containers and counts immediate preceding <li> siblings.
   * @param {string} cfHtml - Full CF_HTML payload
   * @param {string} htmlFrag - StartFragment HTML
   * @returns {number} Inferred index, or 0 when not inside an ordered list
   */
  static GetListStartFromHtmlContext(cfHtml, htmlFrag := "") {
    if (cfHtml = "")
      return 0

    before := ""
    startFragOff := this.ParseCfHtmlOffsetRaw(cfHtml, "StartFragment:")
    startHtmlOff := this.ParseCfHtmlOffsetRaw(cfHtml, "StartHTML:")

    if (startFragOff > 0 && startHtmlOff >= 0 && startFragOff > startHtmlOff) {
      ; Prefer raw-offset slicing: this preserves exact upstream context even
      ; when marker text or fragment string matching is unreliable.
      before := SubStr(cfHtml, startHtmlOff + 1, startFragOff - startHtmlOff)
    } else {
      htmlAll := ClipboardWaiter.SelectHtmlSection(cfHtml, ClipboardWaiter.HTML_SECTION_HTML)
      if (htmlAll = "")
        return 0

      if RegExMatch(htmlAll, "is)<!--[ \t\r\n]*+StartFragment[ \t\r\n]*+-->", &mStartFragment) {
        before := SubStr(htmlAll, 1, mStartFragment.Pos - 1)
      } else {
        fragLookup := Trim(htmlFrag, " `t`r`n")
        if (fragLookup = "")
          return 0
        fragPos := InStr(htmlAll, fragLookup)
        if (fragPos = 0)
          return 0
        before := SubStr(htmlAll, 1, fragPos - 1)
      }
    }

    listStack := []
    pos := 1

    while RegExMatch(before, "is)<(/?)(ol|ul|li)\b([^>]*+)>", &mTag, pos) {
      isClose := (mTag[1] = "/")
      tagName := StrLower(mTag[2])
      attrs := mTag[3]

      if (!isClose) {
        if (tagName = "ol" || tagName = "ul") {
          ctx := { tag: tagName, start: 1, childLi: 0 }
          if (tagName = "ol" && RegExMatch(attrs, "i)\bstart\s*+=\s*+['`"]?(\d++)", &mStart)) {
            ctx.start := Integer(mStart[1])
          }
          listStack.Push(ctx)
        } else if (tagName = "li") {
          if (listStack.Length > 0) {
            listStack[listStack.Length].childLi += 1
          }
        }
      } else {
        if (tagName = "ol" || tagName = "ul") {
          idx := listStack.Length
          while (idx > 0 && listStack[idx].tag != tagName) {
            idx -= 1
          }
          if (idx > 0) {
            removeCount := listStack.Length - idx + 1
            Loop removeCount {
              listStack.Pop()
            }
          }
        }
      }

      pos := mTag.Pos + mTag.Len
    }

    idx := listStack.Length
    while (idx > 0 && listStack[idx].tag != "ol") {
      idx -= 1
    }
    if (idx = 0)
      return 0

    return listStack[idx].start + listStack[idx].childLi
  }

  /**
   * Parses numeric CF_HTML header offsets from raw CF_HTML text.
   * @param {string} cfHtml - Raw CF_HTML payload string
   * @param {string} key - Header key, e.g. StartFragment:
   * @returns {number} Parsed offset, or -1 when missing/invalid
   */
  static ParseCfHtmlOffsetRaw(cfHtml, key) {
    pos := InStr(cfHtml, key)
    if (!pos)
      return -1

    pos += StrLen(key)
    eol := InStr(cfHtml, "`r`n", , pos)
    if (!eol)
      eol := InStr(cfHtml, "`n", , pos)
    if (!eol)
      return -1

    numStr := Trim(SubStr(cfHtml, pos, eol - pos))
    if (numStr = "")
      return -1

    return numStr + 0
  }

  /**
   * Converts markdown to blockquote form by prefixing each line with ">".
   * Blank lines become ">" with no trailing space.
   * @param {string} md - Markdown text to quote
   * @returns {string} Quoted markdown
   */
  static QuoteMarkdown(md) {
    ; Prefix each line.  Blank lines become ">" (no trailing space).
    md := StrReplace(md, "`r", "")
    hadTrailingBreak := RegExMatch(md, "\n$")
    lines := StrSplit(md, "`n")
    if (lines.Length = 0)
      return ""

    out := ""
    firstOut := true
    Loop lines.Length {
      i := A_Index
      rawLine := lines[i]
      line := rawLine

      q := (line = "") ? ">" : ("> " line)
      out .= (firstOut ? "" : "`n") q
      firstOut := false
    }

    if (hadTrailingBreak && out != "")
      out .= "`n"
    return out
  }

  /**
   * Converts quoted blank spacer lines (">") adjacent to poster headings
   * back into truly blank lines.
   * @param {string} md - Markdown text after poster placeholder replacement
   * @returns {string} Markdown with unquoted blank lines around poster headings
   */
  static UnquoteBlankLinesAroundPosterHeadings(md) {
    md := StrReplace(md, "`r", "")
    if (md = "")
      return md

    lines := StrSplit(md, "`n")
    Loop lines.Length {
      i := A_Index
      if (Trim(lines[i], " `t") != ">")
        continue

      prevIsPosterHeading := (i > 1) && RegExMatch(RTrim(lines[i - 1], " `t"), "^##[ \t]++\S++")
      nextIsPosterHeading := (i < lines.Length) && RegExMatch(RTrim(lines[i + 1], " `t"), "^##[ \t]++\S++")
      if (prevIsPosterHeading || nextIsPosterHeading)
        lines[i] := ""
    }

    out := ""
    firstOut := true
    Loop lines.Length {
      out .= (firstOut ? "" : "`n") lines[A_Index]
      firstOut := false
    }
    return out
  }

  /**
   * Ensures list output ends with a single trailing LF.
   * Applies to ordered/unordered markdown lists, including blockquoted lists.
   * @param {string} md - Markdown text
   * @returns {string} Markdown with guaranteed trailing LF for list output
   */
  static EnsureTrailingEolForList(md) {
    md := StrReplace(md, "`r", "")
    if (md = "")
      return md

    tail := RTrim(md, "`n")
    if (tail = "")
      return md

    lines := StrSplit(tail, "`n")
    lastLine := RTrim(lines[lines.Length], " `t")
    if !RegExMatch(lastLine, "^[ \t]*+(?:>[ \t]*+)?+(?:\d++[.)]|[-+*])(?:[ \t]++|$)")
      return md

    return tail "`n"
  }
}

; Ctrl+Alt+Shift+V
^!+v::{
    KeyWait "Alt"   ; wait until Alt is actually released
    Sleep 10        ; let menu-mode clear
    PasteMd.ShowPasteMenu()
}
