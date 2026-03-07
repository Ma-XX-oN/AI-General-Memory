<#
.SYNOPSIS
    Print the stable AI agent session PID.

.DESCRIPTION
    Walks up the process tree from the current shell to find the first
    non-bash ancestor.  That process is the AI agent and its PID is stable
    across all tool calls within the same session.

    Used to name per-session temp files (e.g. commit message files) so
    parallel child sessions don't collide with each other.

.OUTPUTS
    System.Int32. The Windows process ID of the AI agent process.

.EXAMPLE
    # From PowerShell (Codex) — run directly:
    $sessionPid = & "$PSScriptRoot/session-pid.ps1"

.EXAMPLE
    # From bash (Claude Code) — must be sourced via session-pid.sh, not executed:
    . ~/.claude/scripts/session-pid.sh
#>

$bashPid = (Get-CimInstance Win32_Process -Filter "ProcessId=$PID").ParentProcessId
$p = Get-CimInstance Win32_Process -Filter "ProcessId=$bashPid"
while ($p -and $p.Name -eq "bash.exe") {
    $p = Get-CimInstance Win32_Process -Filter "ProcessId=$($p.ParentProcessId)"
}
$p.ProcessId
