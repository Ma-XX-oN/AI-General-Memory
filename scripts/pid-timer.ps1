<#
.SYNOPSIS
Stores and reports per-PID elapsed time in a user environment variable.

.DESCRIPTION
Use `-StoreTime` to save a start timestamp for a PID, then later call
`-TimeElapsed` to compute and print elapsed time. `-TimeElapsed` clears the
stored timestamp after reporting.

If `-TimerPid` is omitted (or <= 0), the script resolves a stable caller PID
by walking the parent process chain until it exits PowerShell hosts.

Running `-StoreTime` more than once for the same PID without an intervening
`-TimeElapsed` returns an error and does not overwrite the original start time.

.PARAMETER TimerPid
Explicit PID to track. If omitted or <= 0, the script auto-resolves the caller
PID from the process tree.

.PARAMETER StoreTime
Stores the current timestamp for the target PID.

.PARAMETER TimeElapsed
Prints elapsed time since the stored timestamp for the target PID and clears it.

.EXAMPLE
PS> .\pid-timer.ps1 -StoreTime
Stores the start time for the resolved caller PID.

.EXAMPLE
PS> .\pid-timer.ps1 -TimeElapsed
Prints elapsed time for the resolved caller PID and clears stored state.

.EXAMPLE
PS> .\pid-timer.ps1 -TimerPid 12345 -StoreTime
Stores start time explicitly for PID 12345.

.EXAMPLE
PS> .\pid-timer.ps1 -TimerPid 12345 -TimeElapsed
Prints elapsed time for PID 12345 and clears stored state.
#>
param(
  [Alias("Pid")]
  [int]$TimerPid,

  [switch]$StoreTime,
  [switch]$TimeElapsed
)

$modeCount = [int]$StoreTime.IsPresent + [int]$TimeElapsed.IsPresent
if ($modeCount -ne 1) {
  Write-Error "Specify exactly one mode: -StoreTime or -TimeElapsed."
  exit 2
}

if ($TimerPid -le 0) {
  # Resolve the first non-PowerShell ancestor so repeated calls from wrappers
  # target a stable caller PID.
  $currentPid = [int]$PID
  $seen = @{}
  while ($true) {
    # Stop if we've already visited this PID to avoid infinite loops.
    if ($seen.ContainsKey($currentPid)) {
      Write-Error "Unable to resolve stable caller PID due to process loop."
      exit 1
    }
    $seen[$currentPid] = $true

    $proc = Get-CimInstance Win32_Process -Filter "ProcessId=$currentPid"
    # Fail if process metadata cannot be loaded for the current PID.
    if ($null -eq $proc) {
      Write-Error "Unable to resolve process details for PID $currentPid."
      exit 1
    }

    $name = ($proc.Name | ForEach-Object { $_.ToLowerInvariant() })
    # The first non-PowerShell process is treated as the stable caller.
    if ($name -ne "pwsh.exe" -and $name -ne "powershell.exe") {
      $TimerPid = $currentPid
      break
    }

    # Abort if the chain has no valid parent before finding a caller.
    if ($proc.ParentProcessId -le 0) {
      Write-Error "Unable to resolve stable caller PID from process tree."
      exit 1
    }
    $currentPid = [int]$proc.ParentProcessId
  }
}

$key = "CODEX_TIMER_START_$TimerPid"

if ($StoreTime) {
  # Refuse to overwrite a pending start time. Caller must consume it via
  # -TimeElapsed first.
  $existing = [Environment]::GetEnvironmentVariable($key, "User")
  if (-not [string]::IsNullOrWhiteSpace($existing)) {
    Write-Error "Time already stored for PID $TimerPid (key: $key). Run -TimeElapsed before -StoreTime."
    exit 1
  }

  $start = [datetimeoffset]::Now.ToString("o")
  [Environment]::SetEnvironmentVariable($key, $start, "User")
  Write-Output "PID=$TimerPid"
  Write-Output "KEY=$key"
  Write-Output "START=$start"
  exit 0
}

$startText = [Environment]::GetEnvironmentVariable($key, "User")
if ([string]::IsNullOrWhiteSpace($startText)) {
  Write-Error "No stored time for PID $TimerPid (key: $key)."
  exit 1
}

try {
  $start = [datetimeoffset]$startText
} catch {
  [Environment]::SetEnvironmentVariable($key, $null, "User")
  Write-Error "Stored value for key '$key' is not a valid datetime: $startText"
  exit 1
}

$end = [datetimeoffset]::Now
$elapsed = $end - $start

[Environment]::SetEnvironmentVariable($key, $null, "User")

Write-Output "PID=$TimerPid"
Write-Output "KEY=$key"
Write-Output "START=$($start.ToString('o'))"
Write-Output "END=$($end.ToString('o'))"
Write-Output ("ELAPSED_SECONDS={0:N3}" -f $elapsed.TotalSeconds)
Write-Output ("ELAPSED={0}m {1}s" -f [int]$elapsed.TotalMinutes, $elapsed.Seconds)
