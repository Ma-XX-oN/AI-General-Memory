/**
 * Simple logger with the following features:
 * 1. Timestamps each entry.
 * 2. Allows the tooltip to be moved by clicking and dragging.
 * 3. Allows the contents to be copied by double-clicking.
 * 4. Supports Format()-style argument list.
 * 5. Indents all but the first line of multiline text.
 * @param {String} text
 *   Text to log.
 * @param {...Primitive} [args]
 *   Arguments for Format(). If omitted, `text` is treated as a plain string.
 */
 Logger(text, args*) {
    if 0 ; set to 1 if you want to shutoff the logger
      return
  
    static logText := "", lastTtHwnd := 0, indent := "              "
    static x := 0, y := 0
    if args.Length {
      logText .= TimeNowMSec() ": " indentAllButFirstLine(
        Format(text, args*), indent) "`n"
    } else {
      logText .= TimeNowMSec() ": " indentAllButFirstLine(text, indent) "`n"
    }
    cm := CoordMode("ToolTip")
    ttHwnd := ToolTip(logText, x, y, 10)
    CoordMode("ToolTip", cm)
  
    GWL_WNDPROC := -4
    proc := DllCall("GetWindowLongPtr", "Ptr", ttHwnd, "Int", GWL_WNDPROC, "Ptr")
    ; MsgBox Format("AHK v{} WndProc: 0x{:X}", A_AhkVersion, proc)
        
    WM_LBUTTONDBLCLK := 0x203, WM_LBUTTONDOWN := 0x201, WM_NCLBUTTONDOWN := 0xA1
    if lastTtHwnd != ttHwnd {
      lastTtHwnd := ttHwnd
      OnMessage(WM_LBUTTONDBLCLK, doubleClickCopy)
      OnMessage(WM_LBUTTONDOWN, drag)
    }
  
    drag(wParam, lParam, msg, hwnd) {
      if hwnd == ttHwnd {
        result := SendMessage(WM_NCLBUTTONDOWN, 2, , hwnd)
        WinGetPos(&x, &y,,, hwnd)
        return result
      }
    }
  
    doubleClickCopy(wParam, lParam, msg, hwnd) {
      if hwnd == ttHwnd {
        A_Clipboard := logText
        ToolTip("Copied!", 0, 0, 10)
        SetTimer () => ToolTip(logText, 0, 0, 10), -500
      }
    }
  
    indentAllButFirstLine(text, indent) {
      return RegExReplace(text, "(?<=\n)", indent)
    }
  
    TimeNowMSec(vOpt:="")
    {
      SYSTEMTIME := Buffer(16, 0)  ; Allocate 16 bytes initialized to 0
  
      if (vOpt = "UTC")
        DllCall("kernel32\GetSystemTime", "Ptr", SYSTEMTIME.Ptr)
      else
        DllCall("kernel32\GetLocalTime", "Ptr", SYSTEMTIME.Ptr)
      vHour := NumGet(SYSTEMTIME, 8, "UShort") ;wHour
      vMin  := NumGet(SYSTEMTIME, 10, "UShort") ;wMinute
      vSec  := NumGet(SYSTEMTIME, 12, "UShort") ;wSecond
      vMSec := NumGet(SYSTEMTIME, 14, "UShort") ;wMilliseconds
      return format("{:02}:{:02}:{:02}.{:03}", vHour, vMin, vSec, vMSec)
    }
  }
  
  ; These can help other figure out is the problem is due to some version issue.
  ; Logger("AHK v" A_AhkVersion)
  ; Logger("OS v" A_OSVersion)
  
  ; When you make modifications, change this so that you know what log you are looking at.
  ; Logger("my code v0.1")
  