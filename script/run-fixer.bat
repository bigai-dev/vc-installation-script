@echo off
REM ============================================================
REM  Vibe Code Workshop - One-Click Fixer
REM  Double-click this file. That's it.
REM ============================================================

title Vibe Code Workshop Fixer

REM --- Check if already running as Administrator ---
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo.
    echo  This script needs Administrator access.
    echo  Click YES on the popup that's about to appear...
    echo.
    timeout /t 2 /nobreak >nul

    REM Re-launch this batch file as Administrator via PowerShell
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

REM --- We're now running as Administrator ---
cd /d "%~dp0"

cls
echo.
echo  =================================================================
echo    Vibe Code Workshop - 'xxx not recognized' Fixer
echo  =================================================================
echo.
echo  This will fix Python, Node.js, and Claude Code PATH issues.
echo.
echo  It will NOT delete anything. Your current PATH is backed up
echo  to:  %USERPROFILE%\path-backups\
echo.
echo  Press any key to start, or close this window to cancel.
echo  =================================================================
pause >nul

REM --- Find the PowerShell script next to this .bat file ---
set "PS_SCRIPT=%~dp0fix-vibecode.ps1"

if not exist "%PS_SCRIPT%" (
    echo.
    echo  [ERROR] Could not find fix-vibecode.ps1 in the same folder as
    echo  this batch file.
    echo.
    echo  Make sure both files are in the same folder:
    echo    - run-fixer.bat       (this file)
    echo    - fix-vibecode.ps1    (the PowerShell script)
    echo.
    pause
    exit /b 1
)

REM --- Run the PowerShell script with execution policy bypass ---
powershell -NoProfile -ExecutionPolicy Bypass -File "%PS_SCRIPT%"
set "EXIT_CODE=%errorLevel%"

echo.
echo  =================================================================
echo    All done.
echo  =================================================================
echo.
echo    IMPORTANT: Close this window and any other PowerShell windows.
echo    Then open a FRESH PowerShell and test by typing:
echo.
echo        python --version
echo        node --version
echo        claude --version
echo.
echo    PATH changes do not reach windows that were already open.
echo.
echo  =================================================================
echo.
echo  Press any key to close this window...
pause >nul
exit /b %EXIT_CODE%
