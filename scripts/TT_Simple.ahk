/**
 * ## TT_Simple
 * 
 * By Adrian Hawryluk
 * 
 * A somewhat simple Tooltip wrapper, allowing for delayed displaying, updating,
 * and auto closing.
 */

/**
 * Class used as namespace to show tooltip.
 */
class tt_simple {
  static _text       := "" ; Text to show.  String or function.
  static _offTime    := "" ; A_TickCount shutoff time.
  static _updateI_ms := 0  ; Update timer interval (ms).
  static _showTime   := 0  ; A_TickCount show time.
  static _timer      := ObjBindMethod(this, "timer") ; Timer function.

  /**
   * Shuts off tooltip and then sets delay when to show tooltip.
   * 
   * @param {number} delay_ms
   *   Number of ms to wait before showing any tooltip.
   */
  static showAfter(delay_ms) {
    this.off()
    this._showTime := A_TickCount + delay_ms
  }
  
  /**
   * Turn tooltip on.
   * 
   * @param {text|function} text
   *   String or function to get string to display.
   * @param {number} [offIn_s = 1000]
   *   How many seconds till tooltip is shut off.
   * @param {number} [updateI_ms = 100]
   *   How many ms till it redisplays tooltip.
   */
  static on(text, offIn_s := 1000, updateI_ms := 100) {
    this._offTime := A_TickCount + 1000 * offIn_s
    this._updateI_ms := updateI_ms
    this.update(text)
    SetTimer(this._timer, updateI_ms)
  }

  /**
   * Turns off tooltip and update timer.
   */
  static off() {
    SetTimer(this._timer, 0)
    Sleep(10) ; in case tt_simple.update() was called and interrupted
    ToolTip()
  }

  /**
   * Updates the tooltip text.
   * 
   * @param {text|function} text
   *   String or function to get string to display.
   */
  static update(text := "") {
    if text != "" {
      this._text := text
    }
    if A_TickCount < this._showTime {
      return
    }
    ToolTip(Type(this._text) = "string"
            ? this._text
            : (this._text)())
  }

  /**
   * Function that is attached to timer.
   */
  static timer() {
    if A_TickCount >= this._offTime {
      this.off()
    } else {
      this.update()
    }
  }
}
