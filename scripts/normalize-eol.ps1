<#
.SYNOPSIS
Normalize one or more files to a specified end-of-line style.

.DESCRIPTION
Reads each target file, normalizes all line breaks to LF internally, then writes
them back using the requested EOL style (`CRLF` or `LF`).

The script preserves BOM for UTF-8/UTF-16 files and defaults to UTF-8 without
BOM when no BOM is present.

.PARAMETER Path
One or more file paths to normalize. Directories are rejected.

.PARAMETER Eol
Target line ending style. Accepted values: `CRLF` or `LF`.

.EXAMPLE
& 'C:\Users\adria\.codex\scripts\normalize-eol.ps1' -Path '.\README.md' -Eol CRLF

.EXAMPLE
& 'C:\Users\adria\.codex\scripts\normalize-eol.ps1' -Path '.\a.txt','.\b.txt' -Eol LF
#>
param(
  [Parameter(Mandatory = $true)]
  [string[]]$Path,

  [ValidateSet("CRLF", "LF")]
  [string]$Eol = "CRLF"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-FileEncoding {
  param([byte[]]$Bytes)

  # Preserve known BOM encodings.
  if ($Bytes.Length -ge 3 -and $Bytes[0] -eq 0xEF -and $Bytes[1] -eq 0xBB -and $Bytes[2] -eq 0xBF) {
    return [System.Text.UTF8Encoding]::new($true)
  }
  if ($Bytes.Length -ge 2 -and $Bytes[0] -eq 0xFF -and $Bytes[1] -eq 0xFE) {
    return [System.Text.UnicodeEncoding]::new($false, $true)
  }
  if ($Bytes.Length -ge 2 -and $Bytes[0] -eq 0xFE -and $Bytes[1] -eq 0xFF) {
    return [System.Text.UnicodeEncoding]::new($true, $true)
  }

  # Default to UTF-8 without BOM for BOM-less files.
  return [System.Text.UTF8Encoding]::new($false)
}

$targetNewline = if ($Eol -eq "CRLF") { "`r`n" } else { "`n" }

foreach ($rawPath in $Path) {
  # Resolve globs and literal file paths.
  $resolved = Resolve-Path -LiteralPath $rawPath -ErrorAction Stop
  foreach ($entry in $resolved) {
    if ((Get-Item -LiteralPath $entry).PSIsContainer) {
      throw "Path '$entry' is a directory; pass file paths only."
    }

    $fullPath = $entry.Path
    $bytes = [System.IO.File]::ReadAllBytes($fullPath)
    $encoding = Get-FileEncoding -Bytes $bytes

    # Canonicalize all line endings through LF, then re-expand to target EOL.
    $text = $encoding.GetString($bytes)
    $normalized = $text -replace "`r`n", "`n" -replace "`r", "`n"
    $converted = if ($targetNewline -eq "`n") { $normalized } else { $normalized -replace "`n", "`r`n" }

    if ($converted -ceq $text) {
      continue
    }

    # Write using original encoding and BOM policy.
    $preamble = $encoding.GetPreamble()
    $payload = $encoding.GetBytes($converted)
    $out = New-Object byte[] ($preamble.Length + $payload.Length)
    [System.Buffer]::BlockCopy($preamble, 0, $out, 0, $preamble.Length)
    [System.Buffer]::BlockCopy($payload, 0, $out, $preamble.Length, $payload.Length)
    [System.IO.File]::WriteAllBytes($fullPath, $out)
  }
}
