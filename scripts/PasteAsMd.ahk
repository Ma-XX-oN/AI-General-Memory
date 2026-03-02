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
    PasteMd.gPasteMenu.Add("Show &poster", ObjBindMethod(PasteMd, "ToggleShowPoster"))
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
    PasteMd._InitPinState()
  }

  ; Change this if pandoc isn't on PATH.
  static PANDOC_EXE := "C:\Users\adria\AppData\Local\Pandoc\pandoc.exe"

  static PASTE_SENTINEL_DELAY_MS := 10
  static PASTE_DELAY_MS := 500

  ; Set to true to dump pipeline stages to a log file for debugging.
  static DEBUG_PASTE_MD := true
  static DEBUG_PASTE_MD_LOG := A_ScriptDir "\PasteAsMd_debug.log"
  static PROMPT_ORDERED_LIST_START_ON_AMBIGUOUS := true

  ; Number of rotated past-run logs to keep alongside the current one.
  static LOG_HISTORY_COUNT := 4

  ; Toggle: prepend detected speaker label ("**User:**" / "**Codex:**" / "**Claude:**" / "**AI:**") to pasted output.
  static SHOW_POSTER := false
  ; Toggle: convert <img> tags to markdown image syntax; when off, use [img] placeholder.
  static SHOW_IMG := false
  ; Toggle: wrap pasted output in blockquote syntax.
  static QUOTE := true
  ; Toggle: use HtmlNorm.Normalize() instead of the legacy PreprocessHtmlCodeBlocks().
  static USE_HTML_NORM := true

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
   * Menu callback: toggles SHOW_POSTER and re-shows the menu.
   * @param {string} ItemName - Menu item label
   * @param {number} ItemPos - Menu item position
   * @param {object} MenuObj - Menu object
   */
  static ToggleShowPoster(ItemName, ItemPos, MenuObj) {
    PasteMd.SHOW_POSTER := !PasteMd.SHOW_POSTER
    PasteMd.gPasteMenu.ToggleCheck("Show &poster")
    PasteMd.gPasteMenu.Show(PasteMd._menuX, PasteMd._menuY)
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
   * Menu callback: immediately copies the current debug log to a timestamped
   * pinned file so rotation cannot overwrite it.
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
      pinPath := PasteMd._PinLogPath()
      FileCopy(PasteMd.DEBUG_PASTE_MD_LOG, pinPath)
      PasteMd._lastPinPath := pinPath
      PasteMd.gPasteMenu.Check("Pin current &log")
      SplitPath(pinPath, &name)
      ToolTip("Pinned: " . name)
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
    result := MsgBox("Delete " . n . " pinned log file" . (n = 1 ? "" : "s") . "?`nThis cannot be undone."
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
      out .= (out = "" ? "" : " ") . '"' . name . '"'
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
      out .= (out = "" ? "" : " ") . '"' . f . '"'
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
    while RegExMatch(before, "i)\bclass=`"[^`"]*\bgroup\b[^`"]*\bmin-w-0\b[^`"]*\bflex-col\b[^`"]*`"", &m, pos) {
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
    while RegExMatch(before, "i)\bclass=`"[^`"]*\bflex-col\b[^`"]*\bitems-end\b[^`"]*`"", &m, pos) {
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
   * @returns {string} "Codex", "Claude", or "AI"
   */
  static _ResolveAssistantLabel(cfHtml) {
    if (cfHtml = "")
      return "AI"

    if RegExMatch(cfHtml, "i)extensionId=([^&`r`n]+)", &mExt) {
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
    f.Write("=== " . label . " (len=" . StrLen(s) . ") ===`r`n")
    ; Show EOL characters visibly.
    vis := StrReplace(s, "`r`n", "⏎¶`r`n")   ; CRLF → visible + real CRLF
    vis := StrReplace(vis, "`r", "⏎`r`n")      ; lone CR
    vis := StrReplace(vis, "`n", "¶`r`n")       ; lone LF
    f.Write(vis)
    f.Write("`r`n`r`n")
  }

  /**
   * Returns the path for rotated log history entry n (1 = most recent).
   * @param {number} n - History index (1-based)
   * @returns {string} File path with .N.log suffix
   */
  static _LogHistoryPath(n) {
    return RegExReplace(PasteMd.DEBUG_PASTE_MD_LOG, "\.log$", "." . n . ".log")
  }

  /**
   * Returns a timestamped path for a pinned log snapshot.
   * @returns {string} File path with yyyyMMdd_HHmmss timestamp suffix
   */
  static _PinLogPath() {
    return RegExReplace(PasteMd.DEBUG_PASTE_MD_LOG, "\.log$", "_" . FormatTime(, "yyyyMMdd_HHmmss") . ".log")
  }

  /**
   * Returns an array of paths for all pinned (timestamped) log files.
   * @returns {Array} Absolute paths matching the timestamped filename pattern
   */
  static _PinnedLogFiles() {
    pattern := RegExReplace(PasteMd.DEBUG_PASTE_MD_LOG, "\.log$", "_????????_??????.log")
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
   * Converts clipboard content to markdown (or quoted markdown) and pastes it.
   * Prefers CF_HTML → pandoc conversion, with plain-text fallback.
   * @param {boolean} asQuoted - If true, prefixes every line with blockquote syntax (>).
   */
  static PasteMarkdown(asQuoted) {
    dbg := PasteMd.DEBUG_PASTE_MD
    if (dbg) {
      ; New paste — clear any pin state so the checkmark doesn't carry over.
      if (PasteMd._lastPinPath != "") {
        PasteMd._lastPinPath := ""
        PasteMd.gPasteMenu.Uncheck("Pin current &log")
      }
      PasteMd._RotateLogFiles()
      dbgF := FileOpen(PasteMd.DEBUG_PASTE_MD_LOG, "w", "UTF-8")
      dbgF.Write("PasteAsMd debug — " . FormatTime(, "yyyy-MM-dd HH:mm:ss") . "`r`n`r`n")
    }

    clipSaved := ClipboardAll()
    plain := StrReplace(A_Clipboard, "`r", "")
    try {
      cfHtml := ClipboardWaiter.GetHtml()
      htmlFrag := (cfHtml = "")
        ? ""
        : ClipboardWaiter.SelectHtmlSection(cfHtml, ClipboardWaiter.HTML_SECTION_FRAGMENT)

      if (dbg) {
        PasteMd._DbgSection(dbgF, "1. plain (A_Clipboard minus CR)", plain)
        PasteMd._DbgSection(dbgF, "2. cfHtml (raw full payload)", cfHtml)
        PasteMd._DbgSection(dbgF, "3. htmlFrag (CF_HTML fragment)", htmlFrag)
        dbgF.Write("=== 2b. cfHtml offsets ===`r`n")
        dbgF.Write("StartHTML: " . PasteMd.ParseCfHtmlOffsetRaw(cfHtml, "StartHTML:") . "`r`n")
        dbgF.Write("EndHTML: " . PasteMd.ParseCfHtmlOffsetRaw(cfHtml, "EndHTML:") . "`r`n")
        dbgF.Write("StartFragment: " . PasteMd.ParseCfHtmlOffsetRaw(cfHtml, "StartFragment:") . "`r`n")
        dbgF.Write("EndFragment: " . PasteMd.ParseCfHtmlOffsetRaw(cfHtml, "EndFragment:") . "`r`n`r`n")
      }

      if (htmlFrag = "") {
        md := PasteMd.CleanPlainText(plain)
        if (dbg)
          PasteMd._DbgSection(dbgF, "3. md (CleanPlainText – no HTML path)", md)
      } else {
        htmlPrep := PasteMd._PreprocessHtml(htmlFrag, cfHtml)
        if (dbg)
          PasteMd._DbgSection(dbgF, "3. htmlPrep (after _PreprocessHtml)", htmlPrep)

        ; If no meaningful HTML tags remain after preprocessing (just styled
        ; spans wrapping plain text, or <p> wrappers around plain lines as
        ; in ProseMirror/Codex), skip pandoc — plain text already has
        ; correct whitespace and indentation that pandoc would destroy.
        stripped := RegExReplace(htmlPrep, "i)<br\b[^>]*>", "")
        stripped := RegExReplace(stripped, "i)</?p\b[^>]*>", "")
        if !RegExMatch(stripped, "<[^>]++>") {
          md := PasteMd.CleanPlainText(plain)
          if (dbg)
            PasteMd._DbgSection(dbgF, "3b. md (no HTML tags → plain text path)", md)
        } else {
          mdRaw := PasteMd.HtmlToGfmViaPandoc(htmlPrep, PasteMd.PANDOC_EXE)
          ; Pandoc converts inline <svg> elements to <img> tags; process them now.
          mdRaw := PasteMd._ProcessImgTags(mdRaw)
          if (dbg)
            PasteMd._DbgSection(dbgF, "4. mdRaw (pandoc output)", mdRaw)

          md := PasteMd.CleanMarkdown(mdRaw)
          md := PasteMd.RestoreThinkingBlocks(md)
          md := PasteMd.RestoreUserMsgBlocks(md)
          if (dbg)
            PasteMd._DbgSection(dbgF, "5. md (after CleanMarkdown)", md)

          md := StrReplace(md, "`r", "")
        }

        ; Never paste empty.  If conversion failed/empty, use plain text.
        if (Trim(md, " `t`n") = "" && Trim(plain, " `t`n") != "") {
          md := PasteMd.CleanPlainText(plain)
          if (dbg)
            PasteMd._DbgSection(dbgF, "5b. md (empty→plain fallback)", md)
        }

        expectedListStart := PasteMd.GetExpectedOrderedListStart(htmlFrag, cfHtml, plain)
        if (PasteMd.PROMPT_ORDERED_LIST_START_ON_AMBIGUOUS) {
          promptedStart := PasteMd.MaybePromptOrderedListStart(md, plain, htmlFrag, expectedListStart)
          if (dbg && promptedStart != expectedListStart) {
            PasteMd._DbgSection(dbgF, "5c2. prompted list start (ordered-list fix)", "" . promptedStart)
          }
          expectedListStart := promptedStart
        }
        if (dbg) {
          PasteMd._DbgSection(dbgF, "5c. expected list start (ordered-list fix)", "" . expectedListStart)
        }

        md := PasteMd.RestoreOrderedListStart(md, plain, htmlFrag, cfHtml, expectedListStart)
        if (dbg)
          PasteMd._DbgSection(dbgF, "5d. md (after RestoreOrderedListStart)", md)
      }

      if (PasteMd.SHOW_POSTER) {
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
            md := SubStr(md, 1, posters[i].pos - 1) . SubStr(md, endPos)
            posters.RemoveAt(i)
          }
          i--
        }
        ; Apply quoting BEFORE replacing poster placeholders. This way the
        ; placeholder (¤POSTER_AI¤) becomes "> ¤POSTER_AI¤" and can be
        ; distinguished from previously-pasted "**AI:**" text, which stays
        ; quoted as "> **AI:**".
        if (asQuoted)
          md := PasteMd.QuoteMarkdown(md)
        ; Replace remaining placeholders with bold labels.
        ; Placeholders may be prefixed with "> " if quoting is active.
        md := RegExReplace(md, "m)^(?:> )?¤POSTER_AI¤$", "**" . assistantLabel . ":**")
        md := RegExReplace(md, "m)^(?:> )?¤POSTER_User¤$", "**User:**")
        ; If no placeholders were found the fragment had no message container
        ; divs (partial selection). Fall back to the pre-fragment cfHtml context.
        if (posters.Length = 0 && cfHtml != "") {
          poster := PasteMd._ExtractPosterFromContext(cfHtml)
          if (poster = "AI")
            poster := assistantLabel
          if (poster != "")
            md := "**" . poster . ":**`n`n" . md
        }
        if (dbg)
          PasteMd._DbgSection(dbgF, "5e. md (after SHOW_POSTER replacement)", md)
      } else if (asQuoted) {
        md := PasteMd.QuoteMarkdown(md)
      }

      md := PasteMd.EnsureTrailingEolForList(md)

      ; Remove CR unconditionally (LF-only).
      md := StrReplace(md, "`r", "")

      if (dbg) {
        PasteMd._DbgSection(dbgF, "6. FINAL md (pasted)", md)
        dbgF.Close()
      }

      pastePayload := md
      pasteWithSentinel := false
      ; Text boxes vary on terminal newline handling (CRLF-aware vs LF-aware),
      ; and some also normalize/filter trailing spaces during paste. Use "."
      ; as a non-space sentinel, then backspace it after paste.
      if (RegExMatch(md, "\n$")) {
        pastePayload .= "."
        pasteWithSentinel := true
      }

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
          dbgF.Write("!!! EXCEPTION: " . e.File . ":" . e.Line . " — " . e.Message . "`r`n")
          dbgF.Close()
        }
      }
      MsgBox "Paste-as-markdown " e.File ":" e.Line " failed:`n`n" e.Message
    } finally {
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
    cmd := '"' . pandocExe . '" -f html -t gfm --wrap=none --eol=lf "' . tmpHtml . '"'
    cmd .= ' -o "' . tmpMd . '"'

    exitCode := RunWait(cmd, , "Hide")
    if (exitCode != 0) {
      try FileDelete tmpHtml
      try FileDelete tmpMd
      return ""
    }

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
      out .= (i = 1 ? "" : "`n") . line
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
    md := RegExReplace(md, "i)</?span\b[^>]*>", "")

    ; Convert <br> tags to newlines so line breaks are preserved.
    md := RegExReplace(md, "i)<br\b[^>]*>", "`n")

    ; Convert block-level <code> elements (multi-line) to fenced code blocks.
    pos := 1
    while RegExMatch(md, "s)<code\b([^>]*)>(.*?)</code>", &m, pos) {
      if InStr(m[2], "`n") {
        ; Extract language identifier from class="language-xxx" if present.
        lang := RegExMatch(m[1], "i)language-(\w+)", &langM) ? langM[1] : ""
        inner := RegExReplace(m[2], "<[^>]++>", "")
        inner := PasteMd.DecodeBasicHtmlEntities(inner)
        inner := Trim(inner, " `t`n")
        replacement := PasteMd.CODE_FENCE . lang . "`n" . inner . "`n" . PasteMd.CODE_FENCE
        md := SubStr(md, 1, m.Pos - 1) . replacement . SubStr(md, m.Pos + m.Len)
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
        outLine := RTrim(line, " `t")
        out .= (out = "" ? "" : "`n") . outLine
        continue
      }

      if (inFence) {
        out .= (out = "" ? "" : "`n") . line
        continue
      }

      ; Keep markdown hard-break intent ("two spaces before newline").
      rawLine := line
      outLine := RTrim(rawLine, " `t")
      if (outLine != "" && RegExMatch(rawLine, " {2,}$"))
        outLine .= "  "

      ; Drop empty headings like "###" or "### ".
      if RegExMatch(outLine, "^[#]{1,6}\s*$") {
        continue
      }

      outLine := PasteMd.SimplifyMarkdownInlineHtml(outLine)
      ; Unescape literal details/summary tags and [img: ...] placeholders.
      outLine := RegExReplace(outLine, "\\(<\/?(?:details|summary)\b[^>]*>)", "$1")
      outLine := RegExReplace(outLine, "\\\[(img(?::[^\]]*)?)\\\]", "[$1]")
      out .= (out = "" ? "" : "`n") . outLine
    }

    ; Drop loose-list separator blanks between adjacent ordered-list items.
    outLines := StrSplit(out, "`n")
    out2 := ""
    firstOut2 := true
    Loop outLines.Length {
      idx := A_Index
      line := outLines[idx]
      if (Trim(line, " `t") = "") {
        prev := (idx > 1) ? RTrim(outLines[idx - 1], " `t") : ""
        next := (idx < outLines.Length) ? RTrim(outLines[idx + 1], " `t") : ""
        if (RegExMatch(prev, "^\s*\d+[.)](?:\s+|$)")
          && RegExMatch(next, "^\s*\d+[.)](?:\s+|$)")) {
          continue
        }
      }

      out2 .= (firstOut2 ? "" : "`n") . line
      firstOut2 := false
    }
    out := out2

    ; Collapse runs of 3+ newlines to 2 (at most one blank line).
    out := RegExReplace(out, "\n{3,}", "`n`n")

    ; Restore task-list checkbox placeholders to GFM syntax.
    ; ¤CHK¤/¤UNCHK¤ were inserted by PreprocessHtmlCodeBlocks so pandoc would not
    ; escape "[x]"/"[ ]" to "\[x\]"/"\[ \]".  Only matches at list-item line starts.
    out := RegExReplace(out, "m)^(\s*[-*+] )¤CHK¤ ", "$1[x] ")
    out := RegExReplace(out, "m)^(\s*[-*+] )¤UNCHK¤ ", "$1[ ] ")

    out := Trim(out, "`n")
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
      replacement := (inner = "") ? "" : ("``" . inner . "``")
      line := SubStr(line, 1, m.Pos - 1) . replacement . SubStr(line, m.Pos + m.Len)
    }

    ; Convert semantic emphasis tags before fallback stripping.
    while RegExMatch(line, "<(strong|b)\b[^>]*+>((?&inside_htag))</\1>" PasteMd.RE_HTML_LIB, &m) {
      replacement := (m[2] = "") ? "" : ("**" . m[2] . "**")
      line := SubStr(line, 1, m.Pos - 1) . replacement . SubStr(line, m.Pos + m.Len)
    }
    while RegExMatch(line, "<(em|i)\b[^>]*+>((?&inside_htag))</\1>" PasteMd.RE_HTML_LIB, &m) {
      replacement := (m[2] = "") ? "" : ("*" . m[2] . "*")
      line := SubStr(line, 1, m.Pos - 1) . replacement . SubStr(line, m.Pos + m.Len)
    }

    ; Convert HTML links to markdown links for readable output.
    while RegExMatch(line, "<a\b[^>]*\bhref\s*=\s*(['`"])(.*?)\1[^>]*>((?&inside_htag))</a>" PasteMd.RE_HTML_LIB, &m) {
      href := PasteMd.DecodeBasicHtmlEntities(m[2])
      text := PasteMd.DecodeBasicHtmlEntities(m[3])

      ; Convert semantic emphasis inside link text before stripping residual tags.
      while RegExMatch(text, "<(strong|b)\b[^>]*>((?&inside_htag))</\1>" PasteMd.RE_HTML_LIB, &inner) {
        replacement := (inner[2] = "") ? "" : ("**" . inner[2] . "**")
        text := SubStr(text, 1, inner.Pos - 1) . replacement . SubStr(text, inner.Pos + inner.Len)
      }
      while RegExMatch(text, "<(em|i)\b[^>]*>((?&inside_htag))</\1>" PasteMd.RE_HTML_LIB, &inner) {
        replacement := (inner[2] = "") ? "" : ("*" . inner[2] . "*")
        text := SubStr(text, 1, inner.Pos - 1) . replacement . SubStr(text, inner.Pos + inner.Len)
      }

      ; Remove any unknown tags that are not escaped
      text := RegExReplace(text, "((?&inside_htag))<[^>]++>" PasteMd.RE_HTML_LIB, "$1")
      if (text = "") {
        text := href
      }
      replacement := "[" . text . "](" . href . ")"
      line := SubStr(line, 1, m.Pos - 1) . replacement . SubStr(line, m.Pos + m.Len)
    }

    ; Protect backtick code spans from tag stripping.
    _codeSpans := []
    pos := 1
    while RegExMatch(line, "(?&codespan)" PasteMd.RE_HTML_LIB, &m, pos) {
      _codeSpans.Push(m[0])
      placeholder := "¤CSPAN_" . _codeSpans.Length . "¤"
      line := SubStr(line, 1, m.Pos - 1) . placeholder . SubStr(line, m.Pos + m.Len)
      pos := m.Pos + StrLen(placeholder)
    }

    ; Remove any unknown tags that are not escaped
    line := RegExReplace(line, "\G((?&inside_htag))(?<!\\)<(?:[^>'`"]++|(?&quoted_string))*+>" PasteMd.RE_HTML_LIB, "$1")
    line := RegExReplace(line, "((?:[^\\]|\\[^<>])++)\\([<>])" PasteMd.RE_HTML_LIB, "$1$2")

    ; Restore backtick code spans.
    for i, span in _codeSpans {
      line := StrReplace(line, "¤CSPAN_" . i . "¤", span)
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
   * Replaces <img> tags in a string according to the SHOW_IMG toggle.
   * When SHOW_IMG is off, replaces each tag with [img] or [img: text] using the
   * first non-empty alt / title / aria-label attribute as the description.
   * When SHOW_IMG is on, leaves tags in place for pandoc to convert.
   * Called on both the pre-pandoc HTML and the post-pandoc markdown, because
   * pandoc converts inline <svg> elements to <img> tags.
   * @param {string} str - HTML or markdown string to process
   * @returns {string} String with <img> tags replaced (or left intact when SHOW_IMG is on)
   */
  static _ProcessImgTags(str) {
    pos := 1
    while RegExMatch(str, "i)<img\b([^>]*?)>", &m, pos) {
      if (PasteMd.SHOW_IMG) {
        pos := m.Pos + m.Len
      } else {
        attrs := m[1]
        accessText := ""
        if (RegExMatch(attrs, "i)\balt\s*=\s*['`"]([^'`"]*)['`"]", &mA) && mA[1] != "")
          accessText := mA[1]
        else if (RegExMatch(attrs, "i)\btitle\s*=\s*['`"]([^'`"]*)['`"]", &mT) && mT[1] != "")
          accessText := mT[1]
        else if (RegExMatch(attrs, "i)\baria-label\s*=\s*['`"]([^'`"]*)['`"]", &mL) && mL[1] != "")
          accessText := mL[1]
        replacement := (accessText = "") ? "[img]" : "[img: " . accessText . "]"
        str := SubStr(str, 1, m.Pos - 1) . replacement . SubStr(str, m.Pos + m.Len)
        pos := m.Pos + StrLen(replacement)
      }
    }
    return str
  }

  /**
   * Routes HTML preprocessing through either HtmlNorm (new) or the legacy
   * PreprocessHtmlCodeBlocks, depending on the USE_HTML_NORM flag.
   *
   * When USE_HTML_NORM is true, calls HtmlNorm.Normalize() and copies the
   * resulting _thinkingBlocks / _userMsgBlocks arrays into PasteMd so that
   * RestoreThinkingBlocks / RestoreUserMsgBlocks work unchanged.
   *
   * @param {string} htmlFrag - HTML fragment from the CF_HTML clipboard
   * @param {string} cfHtml   - Full CF_HTML payload (for source detection)
   * @returns {string} Preprocessed HTML ready for pandoc
   */
  static _PreprocessHtml(htmlFrag, cfHtml) {
    if PasteMd.USE_HTML_NORM {
      html := HtmlNorm.Normalize(htmlFrag, DetectSource(cfHtml), PasteMd.SHOW_POSTER, PasteMd.SHOW_IMG)
      PasteMd._thinkingBlocks := HtmlNorm._thinkingBlocks
      PasteMd._userMsgBlocks  := HtmlNorm._userMsgBlocks
      return html
    }
    return PasteMd.PreprocessHtmlCodeBlocks(htmlFrag)
  }

  /**
   * Preprocesses HTML before pandoc conversion.
   * When SHOW_POSTER is enabled, injects ¤POSTER_AI¤ / ¤POSTER_User¤ paragraphs at
   * the start of each detected message block so per-block labels survive pandoc.
   * Strips UI artifacts (buttons, thinking blocks), converts code-like spans to <code>,
   * strips presentational spans, normalizes line breaks inside <code>,
   * and wraps multi-line code in <pre>.
   * @param {string} html - HTML fragment from clipboard
   * @returns {string} Preprocessed HTML
   */
  static PreprocessHtmlCodeBlocks(html) {
    ; Handle <img> tags.  When SHOW_IMG is off, replace with [img] / [img: alt].
    ; When on, leave in place for pandoc to convert to markdown image syntax.
    html := PasteMd._ProcessImgTags(html)

    ; Inject poster label placeholders at the start of each message block.
    ; Replaced with bold labels (e.g. "**Codex:**" / "**Claude:**") in PasteMarkdown.
    if (PasteMd.SHOW_POSTER) {
      ; AI messages: identified by data-testid="assistant-message".
      html := RegExReplace(html, "i)(<div\b[^>]*\bdata-testid=`"assistant-message`"[^>]*>)", "$1<p>¤POSTER_AI¤</p>")
      ; User messages: outer container has both message_* and userMessageContainer_* classes.
      html := RegExReplace(html, "i)(<div\b[^>]*\bclass=`"[^`"]*\bmessage_\w+\s+[^`"]*\buserMessageContainer_[^>]*>)", "$1<p>¤POSTER_User¤</p>")
      ; Codex assistant messages: group + min-w-0 + flex-col classes.
      html := RegExReplace(html, "i)(<div\b[^>]*\bclass=`"[^`"]*\bgroup\b[^`"]*\bmin-w-0\b[^`"]*\bflex-col\b[^`"]*`"[^>]*>)", "$1<p>¤POSTER_AI¤</p>")
      ; Codex user messages: right-aligned blocks include flex-col + items-end.
      html := RegExReplace(html, "i)(<div\b[^>]*\bclass=`"[^`"]*\bflex-col\b[^`"]*\bitems-end\b[^`"]*`"[^>]*>)", "$1<p>¤POSTER_User¤</p>")
    }

    ; Strip UI artifacts that don't belong in markdown output.
    html := RegExReplace(html, "is)<button\b[^>]*>.*?</button>", "")

    ; Normalize task-list items to markdown checkbox markers before pandoc.
    pos := 1
    while RegExMatch(html, "is)<li\b([^>]*)>(.*?)</li>", &mTask, pos) {
      liAttrs := mTask[1]
      liInner := mTask[2]
      if (!RegExMatch(liAttrs, "i)\btask-list-item\b")
        || !RegExMatch(liInner, "is)^\s*<input\b[^>]*\btype\s*=\s*['`"]checkbox['`"][^>]*>\s*(.*)$", &mTaskText)) {
        pos := mTask.Pos + mTask.Len
        continue
      }

      checked := RegExMatch(liInner, "i)\bchecked\b")
      text := mTaskText[1]
      text := RegExReplace(text, "is)<span\b[^>]*>\s*</span>", "")
      text := RegExReplace(text, "<[^>]++>", "")
      text := this.DecodeBasicHtmlEntities(text)
      text := Trim(text, " `t`r`n" . Chr(160))
      ; Re-encode special chars so the text is safe inside HTML that pandoc will parse.
      text := StrReplace(text, "&", "&amp;")
      text := StrReplace(text, "<", "&lt;")
      text := StrReplace(text, ">", "&gt;")

      ; Use a placeholder marker instead of "[x]" — pandoc escapes bare "[x]" to "\[x\]".
      ; CleanMarkdown restores ¤CHK¤/¤UNCHK¤ to [x]/[ ] after pandoc runs.
      marker := checked ? "¤CHK¤ " : "¤UNCHK¤ "
      replacement := "<li>" . marker . text . "</li>"
      html := SubStr(html, 1, mTask.Pos - 1) . replacement . SubStr(html, mTask.Pos + mTask.Len)
      pos := mTask.Pos + StrLen(replacement)
    }

    ; Extract Claude Code thinking blocks as placeholders so pandoc doesn't
    ; mangle them.  They get restored as raw HTML after markdown cleanup.
    this._thinkingBlocks := []
    pos := 1
    while RegExMatch(html, "is)<details\b[^>]*\bclass=`"[^`"]*\bthinking[^`"]*`"[^>]*>(.*?)</details>", &m, pos) {
      inner := m[1]
      ; Remove <summary> element.
      inner := RegExReplace(inner, "is)<summary\b[^>]*>.*?</summary>", "")
      ; Strip remaining HTML tags.
      inner := RegExReplace(inner, "<[^>]++>", "")
      inner := this.DecodeBasicHtmlEntities(inner)
      inner := Trim(inner, " `t`n`r")
      this._thinkingBlocks.Push(inner)
      placeholder := "¤THINKING_" . this._thinkingBlocks.Length . "¤"
      html := SubStr(html, 1, m.Pos - 1) . placeholder . SubStr(html, m.Pos + m.Len)
      pos := m.Pos + StrLen(placeholder)
    }

    ; Convert code-like <span> elements to <code> before stripping generic spans.
    ; Matches spans with inline-markdown/font-mono class (e.g., Codex/Claude Code).
    html := RegExReplace(html, "is)<span\b[^>]*\bclass=`"[^`"]*\b(?:inline-markdown|font-mono)\b[^`"]*`"[^>]*>(.*?)</span>", "<code>$1</code>")

    ; Extract user message text before pandoc to preserve \n line structure.
    ; Both Claude Code and Codex use whitespace-sensitive containers whose text
    ; nodes would be collapsed by pandoc's HTML whitespace rules.
    this._userMsgBlocks := []

    ; Codex user messages: text-size-chat whitespace-pre-wrap divs with mixed
    ; <span> and <code class="font-mono"> elements.
    pos := 1
    while RegExMatch(html, "is)(<div\b[^>]*\btext-size-chat\b[^>]*\bwhitespace-pre-wrap\b[^>]*>)(.*?)</div>", &m, pos) {
      rawContent := m[2]
      ; Convert font-mono <code> elements to backtick inline code.
      rawContent := RegExReplace(rawContent, "is)<code\b[^>]*\bfont-mono\b[^>]*>(.*?)</code>", "``$1``")
      ; Strip <span> wrapper tags (keep text content).
      rawContent := RegExReplace(rawContent, "i)</?span\b[^>]*>", "")
      ; Strip any remaining HTML tags.
      rawContent := RegExReplace(rawContent, "<[^>]++>", "")
      ; Decode HTML entities.
      rawContent := this.DecodeBasicHtmlEntities(rawContent)
      rawContent := StrReplace(rawContent, "`r", "")
      rawContent := Trim(rawContent, "`n")
      this._userMsgBlocks.Push(rawContent)
      placeholder := "<p>¤USERMSG_" . this._userMsgBlocks.Length . "¤</p>"
      newStr := m[1] . placeholder . "</div>"
      html := SubStr(html, 1, m.Pos - 1) . newStr . SubStr(html, m.Pos + m.Len)
      pos := m.Pos + StrLen(newStr)
    }

    ; Claude Code user messages: unattributed <span> direct children of
    ; content_xGDvVg divs contain the user's typed text.
    pos := 1
    while RegExMatch(html, "is)(<div\b[^>]*\bcontent_xGDvVg\b[^>]*>)\s*<span>(.*?)</span>", &m, pos) {
      rawText := this.DecodeBasicHtmlEntities(m[2])
      rawText := StrReplace(rawText, "`r", "")
      this._userMsgBlocks.Push(rawText)
      placeholder := "<p>¤USERMSG_" . this._userMsgBlocks.Length . "¤</p>"
      newStr := m[1] . placeholder
      html := SubStr(html, 1, m.Pos - 1) . newStr . SubStr(html, m.Pos + m.Len)
      pos := m.Pos + StrLen(newStr)
    }

    ; Strip remaining <span> tags globally (presentational wrappers).
    html := RegExReplace(html, "i)</?span\b[^>]*>", "")

    ; Some sources provide list selections as bare top-level <li> siblings.
    ; Wrap that shape in <ol> so pandoc keeps ordered-list semantics.
    htmlNoTrailingBr := RegExReplace(html, "is)(?:<br\b[^>]*>\s*)+$", "")
    trimmed := Trim(htmlNoTrailingBr, " `t`r`n")
    if (trimmed != "" && RegExMatch(trimmed, "is)^(?:<li\b[^>]*>.*?</li>\s*)+$")) {
      html := "<ol>" . trimmed . "</ol>"
    }

    ; Process <code> elements: normalize line breaks and wrap in <pre> if multi-line.
    pos := 1
    while RegExMatch(html, "is)<code\b([^>]*)>(.*?)</code>", &m, pos) {
      content := m[2]
      attrs := m[1]

      ; Convert <br> tags to newlines.
      content := RegExReplace(content, "i)<br\b[^>]*>", "`n")

      ; Convert </div><div> sequences to newlines (VS Code line rendering).
      content := RegExReplace(content, "i)</div>\s*<div\b[^>]*>", "`n")

      ; Strip remaining HTML tags inside the code block.
      content := RegExReplace(content, "<[^>]++>", "")

      ; Remove CR; preserve blank lines (they are meaningful in code).
      content := StrReplace(content, "`r", "")

      if InStr(content, "`n") {
        ; Decode entities for fenced block (markdown output, not HTML).
        content := PasteMd.DecodeBasicHtmlEntities(content)
        ; Multi-line: check if already inside <pre>.
        beforeSnippet := SubStr(html, Max(1, m.Pos - 100), Min(100, m.Pos - 1))

        ; Only preserve class="language-xxx"; drop CSS classes like "whitespace-pre!".
        langAttr := ""
        if RegExMatch(attrs, "i)language-(\w+)", &langM) {
          langAttr := ' class="language-' . langM[1] . '"'
        }

        if RegExMatch(beforeSnippet, "i)<pre\b[^>]*>\s*$") {
          replacement := "<code" . langAttr . ">" . content . "</code>"
        } else {
          replacement := "<pre><code" . langAttr . ">" . content . "</code></pre>"
        }
      } else {
        ; Single-line: leave as inline <code> for pandoc.
        replacement := "<code" . attrs . ">" . content . "</code>"
      }

      html := SubStr(html, 1, m.Pos - 1) . replacement . SubStr(html, m.Pos + m.Len)
      pos := m.Pos + StrLen(replacement)
    }

    ; Unwrap nested chat code containers so pandoc sees canonical code blocks.
    prev := ""
    while (html != prev) {
      prev := html
      ; Flatten outer <pre> with CSS attributes wrapping an inner <pre><code class="language-xxx">.
      ; Without this, pandoc picks up the outer <pre> as the fence and loses the language tag.
      html := RegExReplace(html, "is)<pre\b[^>]+>\s*(<pre\b[^>]*><code\b[^>]*>.*?</code></pre>)\s*</pre>", "$1")
      html := RegExReplace(html, "is)<div\b[^>]*>\s*<div\b[^>]*>\s*(<pre><code\b[^>]*>.*?</code></pre>)\s*</div>\s*</div>", "$1")
      html := RegExReplace(html, "is)<div\b[^>]*>\s*<div\b[^>]*>\s*(<code\b[^>]*>.*?</code>)\s*</div>\s*</div>", "$1")
    }

    return html
  }

  /**
   * Replaces ¤THINKING_N¤ placeholders with clean <details> HTML blocks.
   * @param {string} md - Markdown text containing placeholders
   * @returns {string} Markdown with thinking blocks restored as raw HTML
   */
  static RestoreThinkingBlocks(md) {
    for i, content in this._thinkingBlocks {
      placeholder := "¤THINKING_" . i . "¤"
      if (content = "") {
        details := "<details>`n<summary>Thinking</summary>`n</details>"
      } else {
        details := "<details>`n<summary>Thinking</summary>`n`n" . content . "`n</details>"
      }
      md := StrReplace(md, placeholder, details)
    }
    return md
  }

  /**
   * Replaces ¤USERMSG_N¤ placeholders with the raw user message text extracted
   * by PreprocessHtmlCodeBlocks.  This content bypasses pandoc to preserve line
   * structure of markdown-like text (blockquotes, bold labels, etc.) the user
   * typed or pasted into the chat input.
   * @param {string} md - Markdown text containing placeholders
   * @returns {string} Markdown with user message content restored
   */
  static RestoreUserMsgBlocks(md) {
    for i, content in this._userMsgBlocks {
      placeholder := "¤USERMSG_" . i . "¤"
      md := StrReplace(md, placeholder, content)
    }
    return md
  }

  /**
   * Restores ordered-list start when converting a single <li> fragment.
   * Pandoc renumbers isolated list-item fragments to 1.
   * @param {string} md - Markdown output from conversion pipeline
   * @param {string} plain - Plain clipboard text
   * @param {string} htmlFrag - StartFragment HTML
   * @param {string} cfHtml - Full CF_HTML payload
   * @returns {string} Markdown with corrected ordered-list numbering
   */
  static RestoreOrderedListStart(md, plain, htmlFrag, cfHtml, expected := -1) {
    md := StrReplace(md, "`r", "")
    if (md = "")
      return md

    ; Fragment may be wrapped in container tags (e.g., <div>...<ol>...</ol>).
    if !RegExMatch(htmlFrag, "is)<(?:li|ol)\b")
      return md

    ; Only patch markdown that starts as list item 1./1) (with or without body text).
    if !RegExMatch(md, "^\s*1[.)](?:\s|$)")
      return md

    if (expected < 0) {
      expected := this.GetExpectedOrderedListStart(htmlFrag, cfHtml, plain)
    }
    if (expected <= 1)
      return md

    return this.RenumberLeadingOrderedList(md, expected)
  }

  /**
   * Prompts user for ordered-list start when clipboard context is ambiguous.
   * @param {string} md - Markdown output from conversion pipeline
   * @param {string} plain - Plain clipboard text
   * @param {string} htmlFrag - StartFragment HTML
   * @param {number} expected - Inferred start index from available context
   * @returns {number} Selected start index, or original expected value
   */
  static MaybePromptOrderedListStart(md, plain, htmlFrag, expected) {
    if (expected > 1)
      return expected

    ; Fragment may be wrapped in container tags (e.g., <div>...<ol>...</ol>).
    ; Some sources emit bare top-level <li> items without an <ol> wrapper.
    if !RegExMatch(htmlFrag, "is)<(?:li|ol)\b")
      return expected

    if !RegExMatch(md, "^\s*1[.)](?:\s|$)")
      return expected

    defaultStart := 2
    if RegExMatch(plain, "^\s*(\d+)[.)](?:\s+|$)", &mPlain) {
      nPlain := Integer(mPlain[1])
      if (nPlain > 1)
        defaultStart := nPlain
    }

    ib := InputBox(
      "Original ordered-list index is missing from clipboard context.`nEnter starting number for this paste (Cancel keeps 1).",
      "Paste as md: list start",
      "w520 h160",
      "" . defaultStart
    )

    if (ib.Result != "OK")
      return expected

    value := Trim(ib.Value, " `t")
    if !RegExMatch(value, "^\d+$")
      return expected

    n := Integer(value)
    if (n < 1)
      return expected

    return n
  }

  /**
   * Renumbers the leading ordered-list block in markdown.
   * Starts at first non-empty numbered-list line and increments for each item.
   * @param {string} md - Markdown text
   * @param {number} startNum - Desired starting list number
   * @returns {string} Markdown with renumbered leading ordered-list block
   */
  static RenumberLeadingOrderedList(md, startNum) {
    hadTrailingBreak := RegExMatch(md, "\n$")
    lines := StrSplit(md, "`n")
    if (lines.Length = 0)
      return md

    firstIdx := 1
    while (firstIdx <= lines.Length && Trim(lines[firstIdx], " `t") = "") {
      firstIdx += 1
    }
    if (firstIdx > lines.Length)
      return md

    if !RegExMatch(lines[firstIdx], "^(\s*)\d+([.)])(?:(\s+)(.*)|\s*)$")
      return md

    current := startNum
    started := false
    drop := Map()

    Loop lines.Length {
      idx := A_Index
      if (idx < firstIdx)
        continue

      line := lines[idx]
      if RegExMatch(line, "^(\s*)\d+([.)])(?:(\s+)(.*)|\s*)$", &mLine) {
        if (mLine[4] = "") {
          drop[idx] := true
        } else {
          sep := mLine[3]
          if (sep = "")
            sep := " "
          lines[idx] := mLine[1] . current . mLine[2] . sep . mLine[4]
        }
        current += 1
        started := true
        continue
      }

      if (!started)
        break

      ; Keep blank lines and indented continuation lines within list block.
      if (Trim(line, " `t") = "" || RegExMatch(line, "^\s{2,}")) {
        continue
      }

      break
    }

    out := ""
    firstOut := true
    Loop lines.Length {
      if (drop.Has(A_Index))
        continue
      out .= (firstOut ? "" : "`n") . lines[A_Index]
      firstOut := false
    }
    if (hadTrailingBreak && out != "" && !RegExMatch(out, "\n$"))
      out .= "`n"
    return out
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
    if RegExMatch(htmlFrag, "is)<li\b[^>]*\bvalue\s*=\s*['`"]?(\d+)", &mValue) {
      return Integer(mValue[1])
    }

    n := this.GetListStartFromHtmlContext(cfHtml, htmlFrag)
    if (n > 0)
      return n

    if RegExMatch(htmlFrag, "is)^\s*<ol\b[^>]*\bstart\s*=\s*['`"]?(\d+)", &mStart) {
      return Integer(mStart[1])
    }

    if RegExMatch(plain, "^\s*(\d+)[.)](?:\s+|$)", &mPlain) {
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

      if RegExMatch(htmlAll, "is)<!--\s*StartFragment\s*-->", &mStartFragment) {
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

    while RegExMatch(before, "is)<(/?)(ol|ul|li)\b([^>]*)>", &mTag, pos) {
      isClose := (mTag[1] = "/")
      tagName := StrLower(mTag[2])
      attrs := mTag[3]

      if (!isClose) {
        if (tagName = "ol" || tagName = "ul") {
          ctx := { tag: tagName, start: 1, childLi: 0 }
          if (tagName = "ol" && RegExMatch(attrs, "i)\bstart\s*=\s*['`"]?(\d+)", &mStart)) {
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
    while (lines.Length > 0 && Trim(lines[lines.Length], " `t") = "") {
      lines.Pop()
    }
    if (lines.Length = 0)
      return ""

    out := ""
    firstOut := true
    Loop lines.Length {
      i := A_Index
      rawLine := lines[i]
      line := RTrim(rawLine, " `t")
      if (line != "" && RegExMatch(rawLine, " {2,}$"))
        line .= "  "

      ; Drop pandoc's separator blank lines between adjacent ordered-list items.
      if (line = "") {
        prev := (i > 1) ? RTrim(lines[i - 1], " `t") : ""
        next := (i < lines.Length) ? RTrim(lines[i + 1], " `t") : ""
        if (RegExMatch(prev, "^\s*\d+[.)](?:\s+|$)")
          && RegExMatch(next, "^\s*\d+[.)](?:\s+|$)")) {
          continue
        }
      }

      q := (line = "") ? ">" : ("> " . line)
      out .= (firstOut ? "" : "`n") . q
      firstOut := false
    }

    if (hadTrailingBreak && out != "")
      out .= "`n"
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
    if !RegExMatch(lastLine, "^\s*(?:>\s*)?(?:\d+[.)]|[-+*])(?:\s+|$)")
      return md

    return tail . "`n"
  }
}

; Ctrl+Alt+Shift+V
^!+v::PasteMd.ShowPasteMenu()
