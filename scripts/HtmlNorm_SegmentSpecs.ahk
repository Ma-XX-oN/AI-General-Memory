class HtmlNormSegmentSpecs {
  static Build() {
    static specs := ""
    if IsObject(specs)
      return specs

    specs := [
      Map("flag", "hasChatGptCode", "detect", ObjBindMethod(HtmlNorm, "_HasChatGptCodeWork"), "apply", ObjBindMethod(HtmlNorm, "_NormalizeChatGptCodeBlocks")),
      Map("flag", "hasKatex", "detect", ObjBindMethod(HtmlNorm, "_HasKatexWork"), "apply", ObjBindMethod(HtmlNorm, "_NormalizeKatexMath")),
      Map("flag", "hasTaskList", "detect", ObjBindMethod(HtmlNorm, "_HasTaskListWork"), "apply", ObjBindMethod(HtmlNorm, "_NormalizeTaskListItems")),
      Map("flag", "hasThinking", "detect", ObjBindMethod(HtmlNorm, "_HasThinkingWork"), "apply", ObjBindMethod(HtmlNorm, "_ExtractThinkingBlocks")),
      HtmlNormSegmentSpecs._RegexTransformSpec(
        "hasInlineCode",
        "i)<span\b[^>]*\bclass\s*=\s*['`"][^'`"]*\b(?:inline-markdown|font-mono)\b",
        "is)<span\b[^>]*\bclass=`"[^`"]*\b(?:inline-markdown|font-mono)\b[^`"]*`"[^>]*>(.*?)</span>",
        "<code>$1</code>"
      ),
      Map("flag", "hasUserMsg", "detect", ObjBindMethod(HtmlNorm, "_HasUserMessageWork"), "apply", ObjBindMethod(HtmlNorm, "_ExtractUserMessages")),
      HtmlNormSegmentSpecs._RegexTransformSpec(
        "hasClaudeWebLabel",
        "i)<div\b[^>]*\bclass\s*=\s*['`"][^'`"]*\bfont-small\b[^'`"]*\bp-3",
        "is)<div\b[^>]*\bclass=`"[^`"]*\bfont-small\b[^`"]*\bp-3[^`"]*`"[^>]*>.*?</div>",
        ""
      ),
      HtmlNormSegmentSpecs._RegexTransformSpec(
        "hasFootnoteHref",
        "i)href=`"[^`"]*#user-content-[^`"]*`"",
        "i)href=`"[^`"]*#(user-content-[^`"]*)`"",
        "href=`"#$1`""
      ),
      HtmlNormSegmentSpecs._RegexTransformSpec(
        "hasFootnoteList",
        "is)<li\b[^>]*\bid=`"user-content-fn-[^`"]*`"[^>]*>\s*<p\b",
        "is)(<li\b[^>]*\bid=`"user-content-fn-[^`"]*`"[^>]*>)\s*<p\b[^>]*>(.*?)</p>\s*(</li>)",
        "$1$2$3"
      ),
      Map("flag", "hasTightList", "detect", ObjBindMethod(HtmlNorm, "_HasTightListWork"), "apply", ObjBindMethod(HtmlNorm, "_NormalizeTightListItems")),
      Map("flag", "hasCodeWork", "detect", ObjBindMethod(HtmlNorm, "_HasCodeWork"), "apply", ObjBindMethod(HtmlNorm, "_NormalizeCodeElements")),
      Map("flag", "hasCodeContainers", "detect", ObjBindMethod(HtmlNorm, "_HasCodeContainerWork"), "apply", ObjBindMethod(HtmlNorm, "_UnwrapNestedContainers")),
      HtmlNormSegmentSpecs._RegexTransformSpec(
        "hasResidualSpan",
        "i)</?+span\b",
        "i)</?+span\b[^>]*+>",
        ""
      )
    ]
    return specs
  }

  static _RegexTransformSpec(flag, detectPat, replacePat, replaceWith) {
    return Map(
      "flag", flag,
      "detectPat", detectPat,
      "replacePat", replacePat,
      "replaceWith", replaceWith
    )
  }
}

class HtmlNormNormalizeStages {
  static Build() {
    static stages := ""
    if IsObject(stages)
      return stages

    stages := [
      Map("applyCtx", ObjBindMethod(HtmlNorm, "_ApplyImgStage")),
      Map("enabled", ObjBindMethod(HtmlNorm, "_ShouldApplyPosterStage"), "applyCtx", ObjBindMethod(HtmlNorm, "_ApplyPosterStage")),
      Map("apply", ObjBindMethod(HtmlNorm, "_NormalizeSimpleDiffBlocks")),
      HtmlNormNormalizeStages._RegexStage(
        "is)<button\b(?=[^>]*\bbehavior-btn\b)(?=[^>]*\bentity-underline\b)[^>]*>(.*?)</button>",
        "<u>$1</u>"
      ),
      HtmlNormNormalizeStages._RegexStage(
        "is)<button\b[^>]*>.*?</button>",
        ""
      ),
      Map("applyCtx", ObjBindMethod(HtmlNorm, "_ApplySegmentStage")),
      Map("apply", ObjBindMethod(HtmlNorm, "_WrapBareTopLevelListItems"))
    ]
    return stages
  }

  static _RegexStage(replacePat, replaceWith) {
    return Map(
      "replacePat", replacePat,
      "replaceWith", replaceWith
    )
  }
}
