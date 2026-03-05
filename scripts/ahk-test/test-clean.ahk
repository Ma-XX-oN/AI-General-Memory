#ErrorStdOut
#Requires AutoHotkey v2.0

deleted := 0
failed := 0

patterns := [
  A_ScriptDir "\test-*.log",
  A_ScriptDir "\PasteAsMd_*.actual.md",
  A_ScriptDir "\PasteAsMd_*.fixture.log",
]

FileAppend "Cleaning generated test logs in " A_ScriptDir "`n", "**", "UTF-8"
for pattern in patterns {
  stats := DeleteMatchingPattern(pattern)
  deleted += stats["deleted"]
  failed += stats["failed"]
  FileAppend "  " pattern ": deleted=" stats["deleted"] ", failed=" stats["failed"] "`n", "**", "UTF-8"
}

FileAppend "Cleanup summary: deleted=" deleted ", failed=" failed "`n", "**", "UTF-8"
ExitApp(failed = 0 ? 0 : 1)

DeleteMatchingPattern(pattern) {
  deleted := 0
  failed := 0
  Loop Files, pattern {
    try {
      FileDelete(A_LoopFileFullPath)
      deleted += 1
    } catch {
      failed += 1
    }
  }
  return Map("deleted", deleted, "failed", failed)
}
