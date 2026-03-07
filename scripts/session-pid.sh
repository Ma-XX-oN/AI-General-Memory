#!/usr/bin/env bash
# session-pid.sh — print the stable session PID (the AI agent process).
#
# IMPORTANT: must be sourced, not executed:
#   . ~/.claude/scripts/session-pid.sh
#
# Executing it creates a subshell whose parent bash has already exited,
# breaking the process chain.  Sourcing runs in the current shell's
# context so the full parent chain to the agent process is visible.
#
# Walks up the process tree from the current bash shell to find the first
# non-bash ancestor.  That process is stable across all bash tool calls
# within the same agent session and can be used to name temp files so
# parallel child sessions don't collide.
#
# Requires PowerShell (pwsh or powershell).  If neither is available,
# prints an error to stderr and exits 1 so the caller can fall back to
# a fixed path.

_ps_cmd() {
    if command -v powershell >/dev/null 2>&1; then echo powershell
    elif command -v pwsh     >/dev/null 2>&1; then echo pwsh
    fi
}

PS=$(_ps_cmd)

if [ -z "$PS" ]; then
    echo "session-pid: PowerShell not available; cannot determine stable session PID" >&2
    exit 1
fi

_SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
if command -v cygpath >/dev/null 2>&1; then
    _PS1_PATH="$(cygpath -w "$_SCRIPT_DIR/session-pid.ps1")"
else
    _PS1_PATH="$_SCRIPT_DIR/session-pid.ps1"
fi

"$PS" -File "$_PS1_PATH"
