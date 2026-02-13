<#
.SYNOPSIS
Show the line-ending style used by one or more files.

.DESCRIPTION
Scans file bytes and classifies end-of-line style as one of:
- CRLF
- LF
- CR
- Mixed
- None

Also reports counts of each newline form found.

.PARAMETER Path
One or more file paths to inspect. Directories are rejected.

.EXAMPLE
& 'C:\Users\adria\.codex\scripts\show-eol.ps1' -Path '.\README.md'

.EXAMPLE
& 'C:\Users\adria\.codex\scripts\show-eol.ps1' -Path '.\a.txt','.\b.txt'
#>
param(
  [Parameter(Mandatory = $true)]
  [string[]]$Path
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-EolInfo {
  param([byte[]]$Bytes)

  [int]$crlfCount = 0
  [int]$lfCount = 0
  [int]$crCount = 0

  for ([int]$i = 0; $i -lt $Bytes.Length; $i++) {
    $b = $Bytes[$i]
    if ($b -eq 13) { # CR
      if (($i + 1) -lt $Bytes.Length -and $Bytes[$i + 1] -eq 10) { # LF
        $crlfCount++
        $i++ # Skip LF as part of CRLF pair.
      } else {
        $crCount++
      }
    } elseif ($b -eq 10) {
      $lfCount++
    }
  }

  $eolType = "Mixed"
  if ($crlfCount -eq 0 -and $lfCount -eq 0 -and $crCount -eq 0) {
    $eolType = "None"
  } elseif ($crlfCount -gt 0 -and $lfCount -eq 0 -and $crCount -eq 0) {
    $eolType = "CRLF"
  } elseif ($lfCount -gt 0 -and $crlfCount -eq 0 -and $crCount -eq 0) {
    $eolType = "LF"
  } elseif ($crCount -gt 0 -and $crlfCount -eq 0 -and $lfCount -eq 0) {
    $eolType = "CR"
  }

  return [PSCustomObject]@{
    EolType = $eolType
    CRLF = $crlfCount
    LF = $lfCount
    CR = $crCount
  }
}

foreach ($rawPath in $Path) {
  $resolved = Resolve-Path -LiteralPath $rawPath -ErrorAction Stop
  foreach ($entry in $resolved) {
    $item = Get-Item -LiteralPath $entry -ErrorAction Stop
    if ($item.PSIsContainer) {
      throw "Path '$($entry.Path)' is a directory; pass file paths only."
    }

    $bytes = [System.IO.File]::ReadAllBytes($entry.Path)
    $info = Get-EolInfo -Bytes $bytes

    [PSCustomObject]@{
      Path = $entry.Path
      EolType = $info.EolType
      CRLF = $info.CRLF
      LF = $info.LF
      CR = $info.CR
    }
  }
}
