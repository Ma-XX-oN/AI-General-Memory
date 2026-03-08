/**
 * ## CopyClip
 * 
 * By Adrian Hawryluk
 * 
 *  This is used to inform the user that the clipboard has been filled with
 *  something after pressing standard copy key sequences like Ctrl-c, Ctrl-x,
 *  Ctrl-Insert, Ctrl-PrtSc, or Alt-PrtScr, as well as some specific ones for
 *  specific applications.
 *
 *  The reason for this utility is that there are times when the clipboard
 *  doesn't have the contents that was expected because either the user
 *  accidentally didn't press the right keys or sometimes it takes some time for
 *  the copy command to be registered by the application and then be filled but
 *  the user is too fast.
 *
 *  This clears the clipboard, sends the same command that was pressed to the
 *  active window, waits for 4 seconds for the clipboard to fill, and if it
 *  hasn't, it gives up and restores the clipboard contents back.  If it has
 *  something, it reports what types are now available in the clipboard.
 *
 *  Types people are mainly interested in are TEXT, HTML and graphic objects
 */

#Requires AutoHotkey v2.0
#include TT_Simple.ahk

WinActiveRegEx(title) {
  prevMode := SetTitleMatchMode("regex")
  result := WinActive(title)
  SetTitleMatchMode(prevMode)
  return result
}

#HotIf WinActiveRegex("ahk_exe i)gimp.*\.exe")
; Copy all layers
$^+c::          CopyToClipboard
#HotIf WinActiveRegex("ahk_exe i)explorer.exe")
; Copy file name
$^+c::          CopyToClipboard
#HotIf WinActiveRegex("ahk_exe i)code.exe")
; Copy file name
$!+c::          CopyToClipboard
#HotIf

$^c::           CopyToClipboard
$^x::           CopyToClipboard
$^Insert::      CopyToClipboard
$^PrintScreen:: CopyToClipboard
$!PrintScreen:: CopyToClipboard

/**
 * Class used as namespace and callable.
 */
class CopyToClipboard {
  static Call(*) {
    tt_simple.showAfter(0)
    tt_simple.on("Waiting for clipboard...")
    
    ; Remove leading $
    ThisHotkey := SubStr(A_ThisHotkey, 2)
    
    ; Special keys need to be surrounded by {}
    ThisHotKey := RegExReplace(ThisHotKey, "([a-zA-Z0-9]{2,})", "{$1}")
    
    lastClip := ClipboardAll()
    A_Clipboard := ""
    Send(ThisHotkey)
    if (!ClipWait(4, 1)) {
      tt_simple.on("CLIPBOARD TIMED OUT!", 2)
      A_Clipboard := lastClip
      return
    }
    contents := this.GetClipboardFormats()
    tt_simple.on("Clipboard now contains:`n" contents, 1, 200)

  }
  
  /**
   * Generates a list of clipboard type names stored in clipboard, with each
   * name on it's own line indented by two spaces.
   * 
   * CF_UNICODETEXT, CF_OEMTEXT and CF_TEXT are combined into just TEXT and
   * CF_LOCALE is ignored as it's used to specify the locale ID (LCID) used to
   * interpret CF_TEXT content.
   * 
   * It can sometimes state some esoteric clipboard format types.
   */
  static GetClipboardFormats() {
    ; Common built-ins (GetClipboardFormatNameW returns empty for these).
    static standard := Map(
      1, "TEXT",
      2, "BITMAP",
      3, "METAFILEPICT",
      4, "SYLK",
      5, "DIF",
      6, "TIFF",
      7, "TEXT", ;"OEMTEXT",
      8, "DIB",
      9, "PALETTE",
      10, "PENDATA",
      11, "RIFF",
      12, "WAVE",
      13, "TEXT", ;"UNICODETEXT",
      14, "ENHMETAFILE",
      15, "HDROP",
      16, "LOCALE", ; Ignored
      17, "DIBV5",
    )

    while ((failed := !DllCall("User32\OpenClipboard", "Ptr", 0, "Int"))
        && A_Index < 4) {
      Sleep 500
    }
    
    if (failed) {
      return "  Failed to open the clipboard"
    }

    try {
      text := ""
      DllCall("Kernel32\SetLastError", "UInt", 0)

      fmt := 0
      outputText := true
      while (fmt := DllCall("User32\EnumClipboardFormats", "UInt", fmt, "UInt")) {
        name := ""
        if standard.Has(fmt) {
          t_fmt := standard[fmt]
          if t_fmt == "LOCALE" {
            ; do nothing
          } else if t_fmt == "TEXT" {
            if outputText {
              name := "  " standard[fmt]
              outputText := false
            }
          } else {
            name := "  " standard[fmt]
          }
        } else {
          ; 256 UTF-16 chars
          buf := Buffer(512, 0)
          len := DllCall("User32\GetClipboardFormatNameW"
            , "UInt", fmt
            , "Ptr",  buf.Ptr
            , "Int",  256
            , "Int")
          name := "  " (len ? StrGet(buf.Ptr, len, "UTF-16") : "CF_UNKNOWN_" fmt)
        }

        if name {
          text .= name "`n"
        }
      }

      if (A_LastError != 0)
        throw OSError("EnumClipboardFormats failed", -1, A_LastError)

      return RTrim(text, "`n")
    } finally {
      DllCall("User32\CloseClipboard")
    }
  }
}