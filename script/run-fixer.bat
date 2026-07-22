@echo off
REM ============================================================
REM  Vibe Code Workshop - One-Click Fixer
REM  Double-click this file. That's it.
REM ============================================================

title Vibe Code Workshop Fixer
setlocal EnableExtensions

set "SCRIPT_DIR=%~dp0"
set "PS_SCRIPT=%SCRIPT_DIR%fix-vibecode.ps1"

REM --- Build a log file path (tolerant of weird date/time formats) ---
set "STAMP=%date:/=-%_%time::=-%"
set "STAMP=%STAMP: =0%"
set "STAMP=%STAMP:.=-%"
set "LOG_FILE=%TEMP%\fix-vibecode-bat-%STAMP%.log"

echo [%date% %time%] run-fixer.bat started >> "%LOG_FILE%"
echo [%date% %time%] cwd=%cd% >> "%LOG_FILE%"
echo [%date% %time%] script_dir=%SCRIPT_DIR% >> "%LOG_FILE%"

REM --- Admin check ---
REM Use fsutil (requires admin) instead of 'net session' because the Server
REM service is disabled in Windows Sandbox, which makes 'net session' fail
REM even when running as admin -> infinite elevation loop -> window flashes
REM closed. fsutil has no service dependency and works everywhere.
fsutil dirty query %systemdrive% >nul 2>&1
if errorlevel 1 goto :needs_admin

echo [%date% %time%] running as admin >> "%LOG_FILE%"
cd /d "%SCRIPT_DIR%"

echo.
echo  =================================================================
echo    Vibe Code Workshop - One-Click Fixer
echo  =================================================================
echo.
echo   This will install / verify all the workshop tools:
echo     Python 3.14, Node.js LTS, Git, GitHub CLI (gh),
echo     Supabase CLI, Vercel CLI, and Claude Code.
echo.
echo   Your current PATH is backed up first to:
echo     %USERPROFILE%\path-backups\
echo.
echo   Total time: 5-10 minutes.
echo.
echo   This window WILL stay open until you press a key at the end,
echo   even if something fails.
echo.
echo   Log file (.bat side): %LOG_FILE%
echo.
echo  =================================================================
echo.
echo  Press any key to start, or close the window to cancel.
pause >nul

if not exist "%PS_SCRIPT%" goto :ps_missing

echo [%date% %time%] launching: powershell -ExecutionPolicy Bypass -File %PS_SCRIPT% >> "%LOG_FILE%"
powershell -NoProfile -ExecutionPolicy Bypass -File "%PS_SCRIPT%"
set "EXIT_CODE=%errorLevel%"
echo [%date% %time%] PowerShell exited with code %EXIT_CODE% >> "%LOG_FILE%"

echo.
echo  =================================================================
if "%EXIT_CODE%"=="0" (echo    Fixer finished successfully.) else (echo    Fixer finished with errors. Exit code: %EXIT_CODE%)
echo  =================================================================
echo.
echo    Check the table above for the per-tool result.
echo.
echo    If everything looks green, sign in to each service:
echo        gh auth login
echo        supabase login
echo        vercel login
echo.
echo    Log files:
echo      .bat side: %LOG_FILE%
echo      .ps1 side: see "Session log:" line above in %%TEMP%%
echo.
echo  =================================================================
echo    RAISE YOUR HAND and wait for a workshop assistant to check
echo    this screen with you BEFORE you close this window.
echo  =================================================================
echo.
echo  Press any key to close this window...
pause >nul
endlocal
exit /b %EXIT_CODE%


:needs_admin
echo [%date% %time%] not admin, requesting elevation >> "%LOG_FILE%"
echo.
echo  ==================================================================
echo   This script needs Administrator access to install Node, Git, etc.
echo  ==================================================================
echo.
echo   A Windows UAC popup will appear next. CLICK YES to continue.
echo.
echo   If you don't see a popup, or you click NO, the install cannot
echo   proceed. A new Administrator window will open instead of this one.
echo.
timeout /t 4 /nobreak >nul

powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs" 2>>"%LOG_FILE%"
if errorlevel 1 goto :elevation_failed
endlocal
exit /b


:elevation_failed
echo.
echo  ==================================================================
echo   ERROR: could not start an Administrator window.
echo  ==================================================================
echo.
echo   Possible causes:
echo     - You clicked NO on the UAC popup
echo     - Your account is not allowed to run as Administrator
echo     - Your organization has restricted UAC
echo.
echo   Log file: %LOG_FILE%
echo.
echo  Press any key to close this window...
pause >nul
endlocal
exit /b 1


:ps_missing
echo [%date% %time%] PS script not found: %PS_SCRIPT% >> "%LOG_FILE%"
cls
echo.
echo  ==================================================================
echo    ERROR: fix-vibecode.ps1 is MISSING from this folder
echo  ==================================================================
echo.
echo    I looked here:
echo      %PS_SCRIPT%
echo.
echo    But this folder only contains:
echo  ------------------------------------------------------------------
dir /b "%SCRIPT_DIR%"
echo  ------------------------------------------------------------------
echo.
echo    HOW TO FIX
echo    ----------
echo    Both files MUST sit side-by-side in the SAME folder:
echo      run-fixer.bat       this file
echo      fix-vibecode.ps1    the PowerShell script
echo.
echo    Most common cause: you only copied run-fixer.bat across --
echo    for example, dragged it alone into Windows Sandbox.
echo.
echo    Easiest fix: go to GitHub, click the green Code button,
echo    pick Download ZIP, unzip it, then run THIS .bat from
echo    inside the unzipped 'script' folder.
echo.
echo      https://github.com/bigai-dev/vc-installation-script
echo.
echo    Log file: %LOG_FILE%
echo.
echo  ==================================================================
echo.
echo  Press any key to close this window...
pause >nul
endlocal
exit /b 1
