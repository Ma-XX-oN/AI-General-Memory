@echo off
setlocal EnableDelayedExpansion
set "BAT_FILE=%~nx0"
set "BAT=%~f0"
set CLAUDE="c:\Users\adria\.vscode\extensions\anthropic.claude-code-2.1.49-win32-x64\resources\native-binary\claude.exe"

for /f "delims=" %%A in ('
  cd
') do set "WD=%%A"

:NEXT_PARAM
if "%~1" == "-h" (
  for /f "delims=" %%A in ('
    powershell -NoProfile -Command "(Get-Culture).DateTimeFormat.ShortDatePattern"
  ') do set "SHORT_DATE_PATTERN=%%A"
  echo %BAT_FILE% [-t time] [-d date] [--wd project-dir] [-h] conversation-UUID
  echo.
  echo Defer execution of continue prompt to Claude Code to a specified date/time
  echo in the future.
  echo.
  echo time - hh:mm - must be 2 digit hour and 2 digit minute.
  echo date - !SHORT_DATE_PATTERN!
  goto :eof
)
if "%~1" == "-t" (
  set "RUN_TIME=/st %~2"
  shift
  shift
  goto NEXT_PARAM
)
if "%~1" == "-d" (
  set "RUN_DATE=/sd %~2"
  shift
  shift
  goto NEXT_PARAM
)
if "%~1" == "--wd" (
  set "WD=%~2"
  shift
  shift
  goto NEXT_PARAM
)
if "%~1" == "-D" (
  CALL :DELETE
  if ERRORLEVEL 1 (
    echo ERROR: Failed to delete task "ClaudeScheduledPrompt".
  ) else (
    echo SUCCESS: Task "ClaudeScheduledPrompt" deleted.
  )
  goto :eof
)

set "UUID=%~1"

if "%UUID%" == "" (
  echo ERROR: Require conversation UUID.
  goto :eof
)
if not "%RUN_TIME%%RUN_DATE%" == "" goto DEFER

:EXECUTE
@echo on
cd /d "%WD%"
%CLAUDE% --resume %UUID% -p "continue"
pause
goto :eof

:DELETE
schtasks /delete /tn "ClaudeScheduledPrompt" /f >NUL 2>&1
goto :eof

:DEFER
if "%RUN_TIME%" == "" set "RUN_TIME=/st 00:00"

call :DELETE
set CMD="\"%BAT%\" --wd \"%WD%\" %UUID%"

schtasks /create /f /sc once %RUN_DATE% %RUN_TIME% /tn "ClaudeScheduledPrompt" /tr %CMD%
if ERRORLEVEL 1 (
  echo ERROR: Task not created. Command failed.
  echo.
  echo schtasks /create /f /sc once %RUN_DATE% %RUN_TIME% /tn "ClaudeScheduledPrompt" /tr %CMD%
)
goto :eof
