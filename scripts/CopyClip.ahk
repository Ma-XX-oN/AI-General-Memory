/**
 * ## CopyClip
 * 
 * By Adrian Hawryluk
 * 
 * This is used to let the user know that the clipboard has been filled with
 * something when pressing Ctrl-C or Ctrl-Insert, in case of missing key press
 * or just a long delay while the clipboard is filled.  This waits for 4 seconds
 * before giving up, at which time, it restores the clipboard to what it was
 * before the copy was initiated and informs the user that it timed out.
 * 
 * Since it was going to say something was copied, I figured that it would be
 * nice to know what types of clipboard formats were available for pasting.
 */

#Requires AutoHotkey v2.0
#include TT_Simple.ahk

$^c::           CopyToClipboard
$^Insert::      CopyToClipboard
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