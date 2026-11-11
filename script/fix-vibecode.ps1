# =============================================================================
#  VIBE CODING ACADEMY - OFFICIAL SETUP
#  (c) 2026 Vibe Coding Academy. All Rights Reserved.
#  For authorised Vibe Coding Academy participants only.
#  Unauthorised redistribution, resale, rebranding, reproduction,
#  or use in third-party training is prohibited.
#  Origin ID: VCA-2026-09-A7F3C8
# =============================================================================
<#
.SYNOPSIS
    Vibe Code Workshop - install and verify every tool the workshop needs.

.DESCRIPTION
    Diagnoses, installs, and repairs every CLI the workshop uses on Windows:
    Python 3.14, Node.js LTS, Git, GitHub CLI (gh), Supabase CLI, Vercel CLI,
    and Claude Code.

    For each tool the script:
      - Looks for an existing install (filters out the Microsoft Store stub)
      - Installs via winget (or Chocolatey if winget is unavailable) if missing;
        Supabase/Vercel come from npm, Claude Code from winget/Chocolatey
      - Adds the right folder to User PATH if needed (no setx - uses .NET API)
      - Verifies the tool runs in the same PowerShell window

    It also:
      - Backs up User and Machine PATH before changes (rollback safety)
      - Cleans broken/duplicate User PATH entries
      - Reminds you to set git user.name / user.email if unset (no prompt)
      - Upgrades Node.js if it's too old for the workshop tools
      - Writes a full session log to %TEMP%
      - Prints a final OK/Failed table per tool, plus the login commands to run next

    Keep this file plain ASCII: Windows PowerShell 5.1 reads scripts without a
    byte-order mark in the system code page, so emoji or accented letters can
    be garbled (or even break the script) on e.g. Chinese-language Windows.

.USAGE
    Easiest: double-click run-fixer.bat (handles UAC and execution policy).

    From an Administrator PowerShell:
      .\fix-vibecode.ps1            # full install + repair
      .\fix-vibecode.ps1 -DiagnoseOnly   # read-only - show what would change

.PARAMETER DiagnoseOnly
    Don't change anything, just show what's wrong.

.PARAMETER SkipClaudeCode
    Don't install Claude Code (only fix the rest).
#>

[CmdletBinding()]
param(
    [switch]$DiagnoseOnly,
    [switch]$SkipClaudeCode
)

$ErrorActionPreference = "Continue"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$script:StartTime = Get-Date

# Force the console into UTF-8 so winget/npm output (which is UTF-8) renders
# correctly on systems with a non-Latin OEM code page (e.g. CP936 Chinese).
# Without this, output appears as garbled characters (mojibake).
try {
    $null = & chcp.com 65001
    [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
    [Console]::InputEncoding  = [System.Text.UTF8Encoding]::new()
    $OutputEncoding           = [System.Text.UTF8Encoding]::new()
} catch {
    Write-Host "Could not switch console to UTF-8: $($_.Exception.Message)" -ForegroundColor Yellow
}

# --- Session log (only in fix mode; transcript adds noise to diagnose output) ---
$script:LogPath = $null
if (-not $DiagnoseOnly) {
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $script:LogPath = Join-Path $env:TEMP "fix-vibecode-$stamp.log"
    try {
        Start-Transcript -Path $script:LogPath -Force | Out-Null
    } catch {
        Write-Host "Could not start transcript: $($_.Exception.Message)" -ForegroundColor Yellow
        $script:LogPath = $null
    }
}

# ---------- Results tracking (final report renders from here) ----------
$script:results = [ordered]@{}

function Set-Result {
    param(
        [Parameter(Mandatory)][string]$Tool,
        [Parameter(Mandatory)][ValidateSet('Installed','AlreadyInstalled','PathFixed','Failed','Skipped')][string]$Status,
        [string]$Version,
        [string]$Path,
        [string]$Notes
    )
    $script:results[$Tool] = [PSCustomObject]@{
        Tool    = $Tool
        Status  = $Status
        Version = $Version
        Path    = $Path
        Notes   = $Notes
    }
}

# ---------- Output helpers ----------
function Say($msg, $color = "White") { Write-Host $msg -ForegroundColor $color }
function Step($msg)  { Write-Host ""; Write-Host "==> $msg" -ForegroundColor Cyan }
function OK($msg)    { Write-Host "    [OK] $msg" -ForegroundColor Green }
function Warn($msg)  { Write-Host "    [!]  $msg" -ForegroundColor Yellow }
function Fail($msg)  { Write-Host "    [X]  $msg" -ForegroundColor Red }
function Info($msg)  { Write-Host "         $msg" -ForegroundColor Gray }

# ---------- Version helpers ----------
# Runs "<tool> --version" and returns just the version number (e.g. "26.13.0"),
# or $null when the tool runs but prints no version (an error message instead).
# Callers treat $null as "broken" and mark the tool Failed instead of green.
function Get-ToolVersion([string]$Exe) {
    try {
        $out = (& $Exe --version 2>&1 | ForEach-Object { "$_" }) -join "`n"
    } catch {
        return $null
    }
    if ($out -match '(\d+\.\d+(\.\d+)?)') { return $Matches[1] }
    return $null
}

# "26.13.0" -> 26 ; $null or garbage -> 0
function Get-MajorVersion([string]$Version) {
    if ($Version -match '^(\d+)\.') { return [int]$Matches[1] }
    return 0
}

# Oldest Node the workshop tools support: Vercel CLI needs 20+, Claude Code asks
# for 22+. 23 and 25 were short-lived releases that no longer get security fixes.
# Raise NodeMinMajor to 24 after April 2027, when Node 22 reaches end of life.
$script:NodeMinMajor = 22
function Test-NodeTooOld([int]$Major) {
    return ($Major -lt $script:NodeMinMajor -or $Major -eq 23 -or $Major -eq 25)
}

# Printed when Claude Code can't be installed or won't start. Anthropic's own
# installer, run by hand in a fresh window, is the most reliable fallback; the
# next run of this script then finds it and puts it on PATH.
function Show-ClaudeFixHint {
    Info "Fix: open a NEW PowerShell window and run Anthropic's installer:"
    Info "     irm https://claude.ai/install.ps1 | iex"
    Info "     then run this fixer again (it adds Claude Code to PATH)."
}

Write-Host ""
Say "=================================================================" Cyan
Say "  Vibe Code Workshop - 'xxx not recognized' fixer" Cyan
Say "=================================================================" Cyan
Say "  This installs and checks Python, Node.js, Git, GitHub CLI," Gray
Say "  Supabase CLI, Vercel CLI and Claude Code." Gray
Say "  After it finishes, CLOSE this window and open a fresh one." Gray
Write-Host ""

# ---------- PATH helpers ----------
function Get-UserPath {
    $raw = [Environment]::GetEnvironmentVariable("Path","User")
    if (-not $raw) { return @() }
    return @($raw -split ';' | Where-Object { $_ -ne "" })
}
function Set-UserPath($entries) {
    # Use .NET API, NOT setx. setx truncates at 1024 chars and corrupts PATH.
    [Environment]::SetEnvironmentVariable("Path", ($entries -join ';'), "User")
}
function Add-UserPathEntry($folder) {
    if (-not (Test-Path $folder)) {
        Warn "Skip add to PATH (folder missing): $folder"
        return $false
    }
    $entries = Get-UserPath
    if ($entries -contains $folder) {
        Info "Already on User PATH: $folder"
        return $false
    }
    if ($DiagnoseOnly) {
        Warn "WOULD ADD to PATH: $folder  (run without -DiagnoseOnly to apply)"
        return $false
    }
    Set-UserPath ($entries + $folder)
    $env:Path = "$env:Path;$folder"
    OK "Added to PATH: $folder"
    return $true
}
function Refresh-Path {
    $env:Path = (
        [Environment]::GetEnvironmentVariable("Path","Machine") + ";" +
        [Environment]::GetEnvironmentVariable("Path","User")
    )
}

# ---------- Bootstrap Chocolatey (fallback when winget is missing) ----------
function Install-Chocolatey {
    if (Get-Command choco -ErrorAction SilentlyContinue) {
        OK "Chocolatey already installed"
        return $true
    }
    Info "Installing Chocolatey package manager (~5 MB, much faster than bootstrapping winget)..."
    try {
        Set-ExecutionPolicy Bypass -Scope Process -Force
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
        Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
        Refresh-Path
        if (Get-Command choco -ErrorAction SilentlyContinue) {
            OK "Chocolatey bootstrap succeeded"
            return $true
        }
        Fail "Chocolatey install completed but 'choco' not on PATH"
        return $false
    } catch {
        Fail "Could not bootstrap Chocolatey: $($_.Exception.Message)"
        return $false
    }
}

# Wraps a package install across winget and choco so the per-tool functions
# don't need to branch. Sets $LASTEXITCODE; returns $true on success.
function Invoke-PackageInstall {
    param(
        [Parameter(Mandatory)][string]$WingetId,
        [Parameter(Mandatory)][string]$ChocoId,
        [string[]]$ChocoExtraArgs = @()
    )
    if ($script:PackageManager -eq 'winget') {
        # --disable-interactivity suppresses the spinner that prints as garbled
        # / \ | - columns in classic Windows PowerShell when stdout is piped.
        # --source winget skips the Microsoft Store source, which can fail or
        # stall on some networks and isn't needed for any of these packages.
        & winget install -e --id $WingetId --source winget --silent --disable-interactivity --accept-package-agreements --accept-source-agreements | Out-Host
    } elseif ($script:PackageManager -eq 'choco') {
        # "upgrade" installs the package if it's missing AND upgrades it if an
        # older version is there ("install" would just skip it).
        $chocoArgs = @('upgrade', $ChocoId, '-y', '--no-progress') + $ChocoExtraArgs
        & choco @chocoArgs | Out-Host
    } else {
        return $false
    }
    return ($LASTEXITCODE -eq 0)
}

# ---------- Preflight: pick a package manager ----------
Step "Choosing a package manager (winget preferred, Chocolatey fallback)"
$script:PackageManager = $null

$wingetCmd = Get-Command winget -ErrorAction SilentlyContinue
if ($wingetCmd) {
    try {
        $wv = (& winget --version) 2>&1
        OK "winget $wv (using winget)"
        $script:PackageManager = 'winget'
    } catch {
        Warn "winget found but did not respond to --version: $_"
    }
}

if (-not $script:PackageManager) {
    if (Get-Command choco -ErrorAction SilentlyContinue) {
        # Chocolatey is already here (e.g. from an earlier run) - just use it.
        Warn "winget is not available - using Chocolatey (already installed)."
        $script:PackageManager = 'choco'
    } elseif ($DiagnoseOnly) {
        Fail "winget not available, and Chocolatey bootstrap is skipped in -DiagnoseOnly mode."
        Info "Re-run without -DiagnoseOnly to install Chocolatey + the workshop tools."
        if ($script:LogPath) { try { Stop-Transcript | Out-Null } catch { } }
        exit 2
    } else {
        Warn "winget is not available - falling back to Chocolatey."
        if (Install-Chocolatey) {
            $script:PackageManager = 'choco'
            OK "Using Chocolatey"
        } else {
            Fail "No package manager available (winget missing, Chocolatey bootstrap failed)."
            Info "Install winget (App Installer from Microsoft Store) or run Chocolatey's installer manually:"
            Info "  https://chocolatey.org/install"
            if ($script:LogPath) { try { Stop-Transcript | Out-Null } catch { } }
            exit 2
        }
    }
}

# ---------- Back up PATH ----------
Step "Backing up your current PATH"
$backupDir = "$env:USERPROFILE\path-backups"
if ($DiagnoseOnly) {
    Info "Diagnose only - nothing will be changed, so no backup needed."
} else {
    New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    [Environment]::GetEnvironmentVariable("Path","User")    | Out-File "$backupDir\user-path-$stamp.txt"    -Encoding UTF8
    [Environment]::GetEnvironmentVariable("Path","Machine") | Out-File "$backupDir\machine-path-$stamp.txt" -Encoding UTF8
    OK "Backed up to $backupDir"
}

# ---------- Clean broken/duplicate PATH entries ----------
Step "Cleaning broken and duplicate PATH entries"
$userEntries = Get-UserPath
$cleaned = @()
$seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
$brokenCount = 0
$dupCount = 0

foreach ($e in $userEntries) {
    $trimmed = $e.Trim()
    if ($trimmed -eq "") { continue }
    if (-not $seen.Add($trimmed)) { $dupCount++; continue }
    $expanded = [Environment]::ExpandEnvironmentVariables($trimmed)
    if ($trimmed -match '%[^%]+%' -or (Test-Path -LiteralPath $expanded)) {
        $cleaned += $trimmed
    } else {
        $brokenCount++
        Info "Broken entry removed: $trimmed"
    }
}

if (-not $DiagnoseOnly -and ($brokenCount -gt 0 -or $dupCount -gt 0)) {
    Set-UserPath $cleaned
    OK "Cleaned User PATH: removed $brokenCount broken, $dupCount duplicate"
} elseif ($brokenCount -gt 0 -or $dupCount -gt 0) {
    Warn "Found $brokenCount broken and $dupCount duplicate entries (diagnose only)"
} else {
    OK "User PATH looks clean"
}

$totalLen = ($cleaned -join ';').Length
if ($totalLen -gt 1024) {
    Warn "User PATH is $totalLen chars (>1024). NEVER use setx to edit PATH."
}

# ---------- PowerShell execution policy (CurrentUser scope) ----------
# Without this, npm/supabase/vercel/etc. fail in every new PowerShell session
# with "running scripts is disabled" because they're installed as .ps1 shims.
# The .bat wrapper sets Bypass for THIS process only; we need a persistent
# setting for the student's future PowerShell windows (e.g. Claude Desktop's
# terminal). RemoteSigned is the standard dev setting - local scripts run,
# downloaded ones still need a signature.
Step "Setting PowerShell execution policy for CurrentUser"
if (-not $DiagnoseOnly) {
    $okPolicies = @('RemoteSigned', 'Unrestricted', 'Bypass')
    $setErr = $null
    try {
        Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force -ErrorAction Stop
    } catch {
        # Set-ExecutionPolicy can throw "Security error" even when the registry
        # write succeeds (e.g. in Windows Sandbox or under some lockdown configs).
        # Don't fail outright - check the actual policy below and decide from there.
        $setErr = $_.Exception.Message
    }

    $currentUserPolicy = Get-ExecutionPolicy -Scope CurrentUser
    $resolved = Get-ExecutionPolicy
    if ($currentUserPolicy -in $okPolicies -and $resolved -in $okPolicies) {
        OK "CurrentUser execution policy = $currentUserPolicy (effective: $resolved)"
    } elseif ($currentUserPolicy -in $okPolicies) {
        Warn "CurrentUser is '$currentUserPolicy' but effective policy is '$resolved' (Group Policy override)."
        Warn "npm/supabase/vercel may still fail in fresh shells. Contact your IT admin."
    } else {
        if ($setErr) {
            Fail "Could not set execution policy: $setErr"
        } else {
            Fail "Execution policy is '$currentUserPolicy', expected one of: $($okPolicies -join ', ')"
        }
        Warn "Students will hit 'running scripts is disabled' when using npm/supabase/vercel."
    }
} else {
    $current = Get-ExecutionPolicy -Scope CurrentUser
    Info "CurrentUser policy is currently '$current'. Would set to RemoteSigned."
}

# ---------- Find and fix Python ----------
Step "Checking Python"
Refresh-Path

# Enumerate every python.exe under the install roots winget AND choco use.
# Choco installs to C:\Python314\, winget to %LOCALAPPDATA%\Programs\Python\Python314\.
# Use a literal "...\python.exe" in the path (with a wildcard segment in between)
# rather than -Filter: with a wildcard *directory* path, -Filter checks the matched
# directory's NAME, not its contents, so it always returns nothing.
function Find-PythonInstalls {
    $found = @()
    $found += Get-ChildItem -Path "$env:LOCALAPPDATA\Programs\Python\*\python.exe" -ErrorAction SilentlyContinue
    $found += Get-ChildItem -Path "$env:ProgramFiles\Python*\python.exe" -ErrorAction SilentlyContinue
    $found += Get-ChildItem -Path "${env:ProgramFiles(x86)}\Python*\python.exe" -ErrorAction SilentlyContinue
    $found += Get-ChildItem -Path "C:\Python*\python.exe" -ErrorAction SilentlyContinue

    # Targeted alternates: Scoop, Anaconda/Miniconda, D:/E: drive installs.
    # Cheap Test-Path checks - safe when drives or folders don't exist.
    $found += Get-ChildItem -Path "$env:USERPROFILE\scoop\apps\python*\current\python.exe" -ErrorAction SilentlyContinue
    foreach ($conda in @("$env:USERPROFILE\anaconda3\python.exe", "$env:USERPROFILE\miniconda3\python.exe")) {
        if (Test-Path $conda) { $found += Get-Item $conda }
    }
    foreach ($drive in @('D:','E:')) {
        $found += Get-ChildItem -Path "$drive\Python*\python.exe" -ErrorAction SilentlyContinue
    }

    return @($found | Where-Object { $_.FullName -notmatch '\\WindowsApps\\' })
}

# Returns a python.exe's version as [version] (e.g. 3.14.10), or $null.
function Get-PythonVersion([string]$Exe) {
    $v = Get-ToolVersion $Exe
    if (-not $v) { return $null }
    try { return [version]$v } catch { return $null }
}

# Highest-version python.exe at or above $Minimum among the known install
# folders, as @{ Path; Version } - or $null if there is none.
function Find-BestPython([version]$Minimum = [version]'0.0') {
    $best = $null
    foreach ($c in (Find-PythonInstalls)) {
        $v = Get-PythonVersion $c.FullName
        if ($v -and $v -ge $Minimum -and (-not $best -or $best.Version -lt $v)) {
            $best = [PSCustomObject]@{ Path = $c.FullName; Version = $v }
        }
    }
    return $best
}

function Install-Python {
    $pythonExe = $null

    # Enumerate ALL python.exe under common install roots (don't trust
    # Get-Command order) and pick the highest version.
    $best = Find-BestPython

    if ($best -and ($best.Version -ge [version]'3.14')) {
        $pythonExe = $best.Path
        OK "Python $($best.Version) found: $pythonExe"

        $pyDir = Split-Path $pythonExe -Parent
        $scriptsDir = Join-Path $pyDir "Scripts"
        $userEntries = Get-UserPath
        if ($userEntries -notcontains $pyDir) {
            # Prepend so this Python wins lookup order
            if (-not $DiagnoseOnly) {
                $filtered = $userEntries | Where-Object { $_ -ne $pyDir }
                Set-UserPath (@($pyDir, $scriptsDir) + $filtered)
                $env:Path = "$pyDir;$scriptsDir;$env:Path"
                OK "Prepended to User PATH: $pyDir"
                Set-Result -Tool 'python' -Status 'PathFixed' -Version "$($best.Version)" -Path $pythonExe
            } else {
                Warn "WOULD prepend Python to PATH (diagnose only)"
                Set-Result -Tool 'python' -Status 'Skipped' -Version "$($best.Version)" -Path $pythonExe -Notes "PATH fix pending"
            }
        } else {
            Set-Result -Tool 'python' -Status 'AlreadyInstalled' -Version "$($best.Version)" -Path $pythonExe
        }
        return
    }

    if ($best) {
        Warn "Found Python $($best.Version), but workshop requires 3.14+. Will install 3.14 alongside."
    } else {
        Warn "No Python install found."
    }

    if ($DiagnoseOnly) {
        Set-Result -Tool 'python' -Status 'Skipped' -Notes "Would install Python 3.14 via $($script:PackageManager)"
        return
    }

    Info "Installing Python 3.14 via $($script:PackageManager)..."
    # python314 (not python3) on Chocolatey: python3 now gives 3.15, and both
    # package managers should hand out the same version.
    if (-not (Invoke-PackageInstall -WingetId 'Python.Python.3.14' -ChocoId 'python314')) {
        Fail "Install of Python failed via $($script:PackageManager) (exit code $LASTEXITCODE)"
        Set-Result -Tool 'python' -Status 'Failed' -Notes "$($script:PackageManager) exit $LASTEXITCODE"
        return
    }
    Refresh-Path

    # Re-find after install (re-enumerate roots so we catch both winget AND choco
    # paths). Accept 3.14 OR NEWER - not exactly 3.14 - so a newer Python is
    # never reported as "Failed".
    $newBest = Find-BestPython -Minimum ([version]'3.14')
    if ($newBest) {
        $pyDir = Split-Path $newBest.Path -Parent
        $scriptsDir = Join-Path $pyDir "Scripts"
        $userEntries = Get-UserPath
        $filtered = $userEntries | Where-Object { $_ -ne $pyDir -and $_ -ne $scriptsDir }
        Set-UserPath (@($pyDir, $scriptsDir) + $filtered)
        $env:Path = "$pyDir;$scriptsDir;$env:Path"
        OK "Python $($newBest.Version) installed and on PATH: $($newBest.Path)"
        Set-Result -Tool 'python' -Status 'Installed' -Version "$($newBest.Version)" -Path $newBest.Path
    } else {
        Fail "Python install reported success but python.exe not found in expected location"
        Set-Result -Tool 'python' -Status 'Failed' -Notes "Post-install search failed"
    }
}

Install-Python

# ---------- Find and fix Node.js ----------
Step "Checking Node.js"
Refresh-Path

function Install-Node {
    $nodeCmd = Get-Command node -ErrorAction SilentlyContinue
    $pathFixed = $false

    if (-not $nodeCmd) {
        Warn "node not on PATH. Searching for existing install..."
        $nodeCandidates = @(
            "$env:ProgramFiles\nodejs\node.exe",
            "${env:ProgramFiles(x86)}\nodejs\node.exe",
            "$env:LOCALAPPDATA\Programs\nodejs\node.exe",
            # Targeted alternates: Scoop and D:/E: drive installs.
            "$env:USERPROFILE\scoop\apps\nodejs\current\node.exe",
            "$env:USERPROFILE\scoop\apps\nodejs-lts\current\node.exe",
            "D:\nodejs\node.exe",
            "E:\nodejs\node.exe"
        )
        $found = $nodeCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
        if ($found) {
            $nodeDir = Split-Path $found -Parent
            if ($DiagnoseOnly) {
                Add-UserPathEntry $nodeDir | Out-Null
                $foundVer = Get-ToolVersion $found
                $foundShow = if ($foundVer) { "v$foundVer" } else { '' }
                Set-Result -Tool 'node' -Status 'Skipped' -Version $foundShow -Path $found -Notes "Found but not on PATH - would add $nodeDir"
                return
            }
            Add-UserPathEntry $nodeDir | Out-Null
            Refresh-Path
            $nodeCmd = Get-Command node -ErrorAction SilentlyContinue
            if ($nodeCmd) {
                OK "Found existing Node at: $found (PATH fixed)"
                $pathFixed = $true
            }
        }
    }

    if ($nodeCmd) {
        # npm.cmd, not bare "npm": npm 11.x ships an npm.ps1 shim that mangles
        # args when invoked as `& npm` from another .ps1 ("Unknown command: pm").
        $nv   = Get-ToolVersion 'node'
        $npmv = Get-ToolVersion 'npm.cmd'
        $nvShow = if ($nv) { "v$nv" } else { '(no version)' }
        OK "node $nvShow,  npm $npmv  ($($nodeCmd.Source))"

        if (Test-NodeTooOld (Get-MajorVersion $nv)) {
            Warn "Node $nvShow is too old or out of support (need v$($script:NodeMinMajor)+, not 23/25)."
            if (-not $DiagnoseOnly) {
                Info "Upgrading to the current LTS via $($script:PackageManager)..."
                Invoke-PackageInstall -WingetId 'OpenJS.NodeJS.LTS' -ChocoId 'nodejs-lts' | Out-Null
                Refresh-Path
                $nv2 = Get-ToolVersion 'node'
                $node2 = Get-Command node -ErrorAction SilentlyContinue
                $node2Path = if ($node2) { $node2.Source } else { '' }
                if ($nv2 -and -not (Test-NodeTooOld (Get-MajorVersion $nv2))) {
                    OK "node upgraded: v$nv2"
                    Set-Result -Tool 'node' -Status 'Installed' -Version "v$nv2" -Path $node2Path
                } else {
                    $stillShow = if ($nv2) { "v$nv2" } else { 'not working' }
                    Fail "Node is still $stillShow after the upgrade ($node2Path)."
                    Set-Result -Tool 'node' -Status 'Failed' -Version $stillShow -Path $node2Path -Notes "Upgrade didn't take - uninstall Node.js in Settings > Apps, then re-run"
                }
            } else {
                Set-Result -Tool 'node' -Status 'Skipped' -Version $nvShow -Path $nodeCmd.Source -Notes "Would upgrade to the current LTS"
            }
        } elseif ($pathFixed) {
            Set-Result -Tool 'node' -Status 'PathFixed' -Version $nvShow -Path $nodeCmd.Source
        } else {
            Set-Result -Tool 'node' -Status 'AlreadyInstalled' -Version $nvShow -Path $nodeCmd.Source
        }

        # Always make sure npm-global folder is on PATH (it's where supabase/vercel land)
        $npmGlobal = "$env:APPDATA\npm"
        if (Test-Path $npmGlobal) {
            Add-UserPathEntry $npmGlobal | Out-Null
        }
        return
    }

    if ($DiagnoseOnly) {
        Set-Result -Tool 'node' -Status 'Skipped' -Notes "Would install Node LTS via $($script:PackageManager)"
        return
    }

    Info "Installing Node.js LTS via $($script:PackageManager)..."
    if (-not (Invoke-PackageInstall -WingetId 'OpenJS.NodeJS.LTS' -ChocoId 'nodejs-lts')) {
        Fail "Install of Node failed via $($script:PackageManager) (exit code $LASTEXITCODE)"
        Set-Result -Tool 'node' -Status 'Failed' -Notes "$($script:PackageManager) exit $LASTEXITCODE"
        return
    }
    Refresh-Path
    $nodeCmd = Get-Command node -ErrorAction SilentlyContinue
    $nv = if ($nodeCmd) { Get-ToolVersion 'node' } else { $null }
    if ($nv) {
        OK "Node v$nv installed: $($nodeCmd.Source)"
        Set-Result -Tool 'node' -Status 'Installed' -Version "v$nv" -Path $nodeCmd.Source

        # Add npm-global folder
        $npmGlobal = "$env:APPDATA\npm"
        if (-not (Test-Path $npmGlobal)) { New-Item -ItemType Directory -Path $npmGlobal -Force | Out-Null }
        Add-UserPathEntry $npmGlobal | Out-Null
    } else {
        Fail "Node install reported success but node.exe was not found or doesn't run"
        Set-Result -Tool 'node' -Status 'Failed' -Notes "Post-install check failed"
    }
}

Install-Node

# ---------- Find and fix Git ----------
Step "Checking Git"
Refresh-Path

function Install-Git {
    $gitCmd = Get-Command git -ErrorAction SilentlyContinue
    if ($gitCmd) {
        $gv = Get-ToolVersion 'git'
        if (-not $gv) {
            Fail "git is on PATH ($($gitCmd.Source)) but doesn't run."
            Set-Result -Tool 'git' -Status 'Failed' -Path $gitCmd.Source -Notes "git doesn't run - reinstall Git, then re-run"
            return
        }
        OK "git $gv  ($($gitCmd.Source))"
        Set-Result -Tool 'git' -Status 'AlreadyInstalled' -Version $gv -Path $gitCmd.Source
    } else {
        if ($DiagnoseOnly) {
            Warn "git not found. Would install via $($script:PackageManager)."
            Set-Result -Tool 'git' -Status 'Skipped' -Notes "Would install Git via $($script:PackageManager)"
            return
        }
        Info "Installing Git via $($script:PackageManager)..."
        if (-not (Invoke-PackageInstall -WingetId 'Git.Git' -ChocoId 'git')) {
            Fail "Install of Git failed via $($script:PackageManager) (exit code $LASTEXITCODE)"
            Set-Result -Tool 'git' -Status 'Failed' -Notes "$($script:PackageManager) exit $LASTEXITCODE"
            return
        }
        Refresh-Path
        $gitCmd = Get-Command git -ErrorAction SilentlyContinue
        $gv = if ($gitCmd) { Get-ToolVersion 'git' } else { $null }
        if ($gv) {
            OK "Git installed: $gv"
            Set-Result -Tool 'git' -Status 'Installed' -Version $gv -Path $gitCmd.Source
        } else {
            Fail "Git install reported success but git is not on PATH or doesn't run"
            Set-Result -Tool 'git' -Status 'Failed' -Notes "Post-install check failed"
            return
        }
    }

    # Check git user.name / user.email but don't prompt: students at install time
    # often don't have a GitHub account yet and shouldn't be forced to invent values
    # they'll later want to change. Surfaced as a "do this later" reminder instead.
    if (-not $DiagnoseOnly) {
        $existingName  = (& git config --global user.name 2>$null)
        $existingEmail = (& git config --global user.email 2>$null)
        if ([string]::IsNullOrWhiteSpace($existingName) -or [string]::IsNullOrWhiteSpace($existingEmail)) {
            Warn "git user.name / user.email not set - configure before your first commit (see end of run)."
        } else {
            OK "git user.name = $existingName"
            OK "git user.email = $existingEmail"
        }
    }
}

Install-Git

# ---------- Find and install GitHub CLI ----------
Step "Checking GitHub CLI (gh)"
Refresh-Path

function Install-GitHubCLI {
    $ghCmd = Get-Command gh -ErrorAction SilentlyContinue
    if ($ghCmd) {
        $ghv = Get-ToolVersion 'gh'
        if ($ghv) {
            OK "gh $ghv  ($($ghCmd.Source))"
            Set-Result -Tool 'gh' -Status 'AlreadyInstalled' -Version $ghv -Path $ghCmd.Source
        } else {
            Fail "gh is on PATH ($($ghCmd.Source)) but doesn't run."
            Set-Result -Tool 'gh' -Status 'Failed' -Path $ghCmd.Source -Notes "gh doesn't run - reinstall GitHub CLI, then re-run"
        }
        return
    }

    if ($DiagnoseOnly) {
        Warn "gh not found. Would install via $($script:PackageManager)."
        Set-Result -Tool 'gh' -Status 'Skipped' -Notes "Would install GitHub CLI via $($script:PackageManager)"
        return
    }

    Info "Installing GitHub CLI via $($script:PackageManager)..."
    if (-not (Invoke-PackageInstall -WingetId 'GitHub.cli' -ChocoId 'gh')) {
        Fail "Install of gh failed via $($script:PackageManager) (exit code $LASTEXITCODE)"
        Set-Result -Tool 'gh' -Status 'Failed' -Notes "$($script:PackageManager) exit $LASTEXITCODE"
        return
    }
    Refresh-Path
    $ghCmd = Get-Command gh -ErrorAction SilentlyContinue
    $ghv = if ($ghCmd) { Get-ToolVersion 'gh' } else { $null }
    if ($ghv) {
        OK "GitHub CLI installed: $ghv"
        Set-Result -Tool 'gh' -Status 'Installed' -Version $ghv -Path $ghCmd.Source
    } else {
        Fail "gh install reported success but gh is not on PATH or doesn't run"
        Set-Result -Tool 'gh' -Status 'Failed' -Notes "Post-install check failed"
    }
}

Install-GitHubCLI

# ---------- Find and install Supabase CLI ----------
Step "Checking Supabase CLI"
Refresh-Path

function Install-SupabaseCLI {
    $sbCmd = Get-Command supabase -ErrorAction SilentlyContinue
    if ($sbCmd) {
        $sbv = Get-ToolVersion 'supabase'
        if ($sbv) {
            OK "supabase $sbv  ($($sbCmd.Source))"
            Set-Result -Tool 'supabase' -Status 'AlreadyInstalled' -Version $sbv -Path $sbCmd.Source
        } else {
            Fail "supabase is on PATH ($($sbCmd.Source)) but doesn't run."
            Set-Result -Tool 'supabase' -Status 'Failed' -Path $sbCmd.Source -Notes "supabase doesn't run - reinstall it (npm install -g supabase), then re-run"
        }
        return
    }

    if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
        Warn "npm not available - cannot install Supabase CLI. Make sure Node was installed first."
        Set-Result -Tool 'supabase' -Status 'Failed' -Notes "npm not available"
        return
    }

    if ($DiagnoseOnly) {
        Warn "supabase not found. Would install via npm."
        Set-Result -Tool 'supabase' -Status 'Skipped' -Notes "Would install Supabase CLI via npm"
        return
    }

    Info "Installing Supabase CLI via npm install -g supabase..."
    # Supabase only lists Scoop for Windows, but a global npm install works with
    # CLI v2.100+ (May 2026) and v3; older versions refused it outright. If this
    # starts failing again, switch to Scoop.
    # No 2>&1: PS 5.1 wraps native stderr in ErrorRecord, making npm warnings look
    # like fatal PowerShell errors. Stderr still prints to console without it.
    & npm.cmd install -g supabase | Out-Host
    if ($LASTEXITCODE -ne 0) {
        Fail "npm install -g supabase failed (exit code $LASTEXITCODE)"
        Set-Result -Tool 'supabase' -Status 'Failed' -Notes "npm exit $LASTEXITCODE"
        return
    }
    Refresh-Path
    $sbCmd = Get-Command supabase -ErrorAction SilentlyContinue
    $sbv = if ($sbCmd) { Get-ToolVersion 'supabase' } else { $null }
    if ($sbv) {
        OK "Supabase CLI installed: $sbv"
        Set-Result -Tool 'supabase' -Status 'Installed' -Version $sbv -Path $sbCmd.Source
    } else {
        Fail "Supabase install reported success but supabase is not on PATH or doesn't run"
        Set-Result -Tool 'supabase' -Status 'Failed' -Notes "Post-install check failed"
    }
}

Install-SupabaseCLI

# ---------- Find and install Vercel CLI ----------
Step "Checking Vercel CLI"
Refresh-Path

function Install-VercelCLI {
    $vcCmd = Get-Command vercel -ErrorAction SilentlyContinue
    if ($vcCmd) {
        $vcv = Get-ToolVersion 'vercel'
        if ($vcv) {
            OK "vercel $vcv  ($($vcCmd.Source))"
            Set-Result -Tool 'vercel' -Status 'AlreadyInstalled' -Version $vcv -Path $vcCmd.Source
        } else {
            Fail "vercel is on PATH ($($vcCmd.Source)) but doesn't run."
            Set-Result -Tool 'vercel' -Status 'Failed' -Path $vcCmd.Source -Notes "vercel doesn't run - reinstall it (npm install -g vercel), then re-run"
        }
        return
    }

    if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
        Warn "npm not available - cannot install Vercel CLI."
        Set-Result -Tool 'vercel' -Status 'Failed' -Notes "npm not available"
        return
    }

    if ($DiagnoseOnly) {
        Warn "vercel not found. Would install via npm."
        Set-Result -Tool 'vercel' -Status 'Skipped' -Notes "Would install Vercel CLI via npm"
        return
    }

    Info "Installing Vercel CLI via npm install -g vercel..."
    & npm.cmd install -g vercel | Out-Host
    if ($LASTEXITCODE -ne 0) {
        Fail "npm install -g vercel failed (exit code $LASTEXITCODE)"
        Set-Result -Tool 'vercel' -Status 'Failed' -Notes "npm exit $LASTEXITCODE"
        return
    }
    Refresh-Path
    $vcCmd = Get-Command vercel -ErrorAction SilentlyContinue
    $vcv = if ($vcCmd) { Get-ToolVersion 'vercel' } else { $null }
    if ($vcv) {
        OK "Vercel CLI installed: $vcv"
        Set-Result -Tool 'vercel' -Status 'Installed' -Version $vcv -Path $vcCmd.Source
    } else {
        Fail "Vercel install reported success but vercel is not on PATH or doesn't run"
        Set-Result -Tool 'vercel' -Status 'Failed' -Notes "Post-install check failed"
    }
}

Install-VercelCLI

# ---------- Install Claude Code ----------
# Installed the way Anthropic recommends: winget (Anthropic.ClaudeCode), or on
# PCs without winget, Chocolatey (claude-code). npm is only a last resort -
# npm 12+ skips the setup step its Claude Code package needs. Anthropic's own
# install.ps1 is NOT run from inside this script: it ends with `exit`, which
# would close this whole script when run via Invoke-Expression.
# Where the different installers put claude (used to fix PATH if needed):
$claudeCandidates = @(
    "$env:LOCALAPPDATA\Microsoft\WinGet\Links\claude.exe",
    "$env:ProgramFiles\WinGet\Links\claude.exe",
    "$env:ProgramData\chocolatey\bin\claude.exe",
    "$env:USERPROFILE\.local\bin\claude.exe",
    "$env:APPDATA\npm\claude.cmd"
)

if (-not $SkipClaudeCode -and -not $DiagnoseOnly) {
    Step "Installing Claude Code"
    Refresh-Path

    $existing = Get-Command claude -ErrorAction SilentlyContinue
    if (-not $existing) {
        # Installed earlier (e.g. Anthropic's installer run by hand) but not on PATH?
        $known = $claudeCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
        if ($known) {
            Add-UserPathEntry (Split-Path $known -Parent) | Out-Null
            Refresh-Path
            $existing = Get-Command claude -ErrorAction SilentlyContinue
        }
    }
    $cv = if ($existing) { Get-ToolVersion 'claude' } else { $null }

    if ($cv) {
        OK "Claude Code already installed: $cv  ($($existing.Source))"
        Set-Result -Tool 'claude' -Status 'AlreadyInstalled' -Version $cv -Path $existing.Source
    } else {
        if ($existing) {
            Warn "claude is on PATH ($($existing.Source)) but doesn't start - reinstalling it."
            # A broken npm copy would keep being found first, so remove it.
            if ($existing.Source -like "$env:APPDATA\npm\*" -and (Get-Command npm.cmd -ErrorAction SilentlyContinue)) {
                Info "Removing the broken npm copy of Claude Code..."
                & npm.cmd uninstall -g "@anthropic-ai/claude-code" | Out-Host
                Refresh-Path
            }
        }

        Info "Installing Claude Code via $($script:PackageManager)..."
        $installed = Invoke-PackageInstall -WingetId 'Anthropic.ClaudeCode' -ChocoId 'claude-code'
        if (-not $installed -and (Get-Command npm.cmd -ErrorAction SilentlyContinue)) {
            Warn "$($script:PackageManager) could not install Claude Code (exit code $LASTEXITCODE) - trying npm instead."
            & npm.cmd install -g "@anthropic-ai/claude-code" | Out-Host
            $installed = ($LASTEXITCODE -eq 0)
        }
        Refresh-Path

        $claudeCmd = Get-Command claude -ErrorAction SilentlyContinue
        if ($installed -and -not $claudeCmd) {
            # Not found yet - look where the installers put it and add that folder.
            $claudeFound = $claudeCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
            if ($claudeFound) {
                Add-UserPathEntry (Split-Path $claudeFound -Parent) | Out-Null
                Refresh-Path
                $claudeCmd = Get-Command claude -ErrorAction SilentlyContinue
            }
        }

        $cv = if ($claudeCmd) { Get-ToolVersion 'claude' } else { $null }
        if ($cv) {
            OK "Claude Code installed: $cv  ($($claudeCmd.Source))"
            Set-Result -Tool 'claude' -Status 'Installed' -Version $cv -Path $claudeCmd.Source
        } elseif (-not $installed) {
            Fail "Could not install Claude Code."
            Show-ClaudeFixHint
            Set-Result -Tool 'claude' -Status 'Failed' -Notes "All install methods failed - see the fix printed above"
        } elseif ($claudeCmd) {
            Fail "Claude Code installed, but it doesn't start."
            Show-ClaudeFixHint
            Set-Result -Tool 'claude' -Status 'Failed' -Path $claudeCmd.Source -Notes "Installed, but doesn't start - see the fix printed above"
        } else {
            Fail "Claude Code install reported success, but claude was not found."
            Show-ClaudeFixHint
            Set-Result -Tool 'claude' -Status 'Failed' -Notes "Post-install search failed - see the fix printed above"
        }
    }
}

if (-not $script:results.Contains('claude')) {
    if ($SkipClaudeCode) {
        Set-Result -Tool 'claude' -Status 'Skipped' -Notes "Skipped via -SkipClaudeCode flag"
    } elseif ($DiagnoseOnly) {
        $existing = Get-Command claude -ErrorAction SilentlyContinue
        if ($existing) {
            $cv = Get-ToolVersion 'claude'
            if ($cv) {
                Set-Result -Tool 'claude' -Status 'AlreadyInstalled' -Version $cv -Path $existing.Source
            } else {
                Set-Result -Tool 'claude' -Status 'Failed' -Path $existing.Source -Notes "claude doesn't start - a normal run reinstalls it"
            }
        } else {
            Set-Result -Tool 'claude' -Status 'Skipped' -Notes "Would install via $($script:PackageManager)"
        }
    }
}

# ---------- Final verification (renders $script:results) ----------
Step "Final verification"
Refresh-Path

# Re-verify every tool with --version one more time (catches PATH drift edge cases)
$reverify = @('python','node','npm','git','gh','supabase','vercel')
if (-not $SkipClaudeCode) { $reverify += 'claude' }

foreach ($tool in $reverify) {
    $cmd = Get-Command $tool -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.Source -notmatch '\\WindowsApps\\') {
        $exe = if ($tool -eq 'npm') { 'npm.cmd' } else { $tool }
        $v = Get-ToolVersion $exe
        # Only update if we don't already have a richer entry
        if (-not $script:results.Contains($tool)) {
            if ($v) {
                Set-Result -Tool $tool -Status 'AlreadyInstalled' -Version $v -Path $cmd.Source
            } else {
                Set-Result -Tool $tool -Status 'Failed' -Path $cmd.Source -Notes "Found, but didn't report a version (broken install?)"
            }
        }
    } else {
        if (-not $script:results.Contains($tool)) {
            Set-Result -Tool $tool -Status 'Failed' -Notes "Not on PATH in this shell"
        }
    }
}

# Render the table
Write-Host ""
Say "  Tool        Status              Version                 Path" Cyan
Say "  ----------- ------------------- ----------------------- --------------------------------------------------" Cyan
$allGood = $true
foreach ($r in $script:results.Values) {
    $statusColor = switch ($r.Status) {
        'Installed'        { 'Green' }
        'AlreadyInstalled' { 'Green' }
        'PathFixed'        { 'Green' }
        'Skipped'          { 'Yellow' }
        'Failed'           { 'Red' }
        default            { 'Gray' }
    }
    if ($r.Status -eq 'Failed') { $allGood = $false }
    $verStr  = if ($r.Version) { $r.Version } else { '' }
    $pathStr = if ($r.Path)    { $r.Path }    else { '' }
    $line = "  {0,-11} {1,-19} {2,-23} {3}" -f $r.Tool, $r.Status, $verStr, $pathStr
    Write-Host $line -ForegroundColor $statusColor
    if ($r.Notes) {
        Write-Host "              note: $($r.Notes)" -ForegroundColor Gray
    }
}

Write-Host ""
Say "=================================================================" Cyan
if ($DiagnoseOnly) {
    Say "  Diagnose-only finished. Re-run WITHOUT -DiagnoseOnly to apply fixes." Yellow
} elseif ($allGood) {
    Say "  All tools are working in THIS PowerShell window." Green
    Write-Host ""
    Say "  Next steps - run these in this same window:" White
    Say "      gh auth login" White
    Say "      supabase login" White
    Say "      vercel login" White
    Say "      git config --global user.name `"Your Name`"" White
    Say "      git config --global user.email `"you@example.com`"" White
    Write-Host ""
    Say "  (The first three open a browser. The git ones set your commit identity.)" Gray
} else {
    Say "  Some tools failed. See the table above." Yellow
    Say "  Try closing this window and opening a fresh PowerShell as Administrator," Yellow
    Say "  then re-run this script. If the same tools fail again, share the log:" Yellow
    if ($script:LogPath) { Say "      $($script:LogPath)" White }
    Write-Host ""
    Say "  Next steps once all tools are working:" Gray
    Say "      gh auth login" Gray
    Say "      supabase login" Gray
    Say "      vercel login" Gray
    Say "      git config --global user.name `"Your Name`"" Gray
    Say "      git config --global user.email `"you@example.com`"" Gray
}
$elapsed = (Get-Date) - $script:StartTime
Say ("  Total time: {0} min {1:D2} sec" -f [int]$elapsed.TotalMinutes, $elapsed.Seconds) Gray
if (-not $DiagnoseOnly) { Say "  PATH backups: $backupDir" Gray }
Say "=================================================================" Cyan
Write-Host ""

# --- Stop transcript ---
if ($script:LogPath) {
    try { Stop-Transcript | Out-Null } catch { }
    Write-Host "Session log: $($script:LogPath)" -ForegroundColor Gray
}
