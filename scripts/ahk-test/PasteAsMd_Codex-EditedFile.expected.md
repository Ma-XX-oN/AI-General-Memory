> I’m patching `test-paste-md-fixtures.ahk` now so its with-user label assertions match the new `## Name` format.
>
> Edited file
>
> +2-2
>
> `test-paste-md-fixtures.ahk`
>
> ```diff
>    if fx.withUser {
> -    Chk("with-user has User label", InStr(finalMd, "**User:**"))
> -    Chk("with-user has assistant label", InStr(finalMd, "**" fx.assistantLabel ":**"))
> +    Chk("with-user has User label", InStr(finalMd, "## User"))
> +    Chk("with-user has assistant label", InStr(finalMd, "## " fx.assistantLabel))
>    }
> ```
>
> Ran & "C:/Users/adria/.codex/scripts/show-eol.ps1" -Path "C:/Users/adria/.claude/scripts/PasteAsMd.ahk"
