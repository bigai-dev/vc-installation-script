<#
.SYNOPSIS
    Vibe Code Workshop — install and verify every tool the workshop needs.

.DESCRIPTION
    Diagnoses, installs, and repairs every CLI the workshop uses on Windows:
    Python 3.14, Node.js LTS, Git, GitHub CLI (gh), Supabase CLI, Vercel CLI,
    and Claude Code.

    For each tool the script:
      - Looks for an existing install (filters out the Microsoft Store stub)
      - Installs via winget (or Chocolatey if winget is unavailable; npm for supabase/vercel) if missing
      - Adds the right folder to User PATH if needed (no setx — uses .NET API)
      - Verifies the tool runs in the same PowerShell window

    It also:
      - Backs up User and Machine PATH before changes (rollback safety)
      - Cleans broken/duplicate User PATH entries
      - Prompts for git user.name / user.email if unset
      - Writes a full session log to %TEMP%
      - Prints a final ✅/❌ table per tool, plus the 3 login commands to run next

.USAGE
    Easiest: double-click run-fixer.bat (handles UAC and execution policy).

    From an Administrator PowerShell:
      .\fix-vibecode.ps1            # full install + repair
      .\fix-vibecode.ps1 -DiagnoseOnly   # read-only — show what would change

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

Write-Host ""
Say "=================================================================" Cyan
Say "  Vibe Code Workshop - 'xxx not recognized' fixer" Cyan
Say "=================================================================" Cyan
Say "  This fixes Python, Node.js, and Claude Code PATH issues." Gray
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
        & winget install -e --id $WingetId --silent --accept-package-agreements --accept-source-agreements | Out-Host
    } elseif ($script:PackageManager -eq 'choco') {
        $chocoArgs = @('install', $ChocoId, '-y', '--no-progress') + $ChocoExtraArgs
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
    if ($DiagnoseOnly) {
        Fail "winget not available, and Chocolatey bootstrap is skipped in -DiagnoseOnly mode."
        Info "Re-run without -DiagnoseOnly to install Chocolatey + the workshop tools."
        if ($script:LogPath) { try { Stop-Transcript | Out-Null } catch { } }
        exit 2
    }
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

# ---------- Back up PATH ----------
Step "Backing up your current PATH"
$backupDir = "$env:USERPROFILE\path-backups"
New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
[Environment]::GetEnvironmentVariable("Path","User")    | Out-File "$backupDir\user-path-$stamp.txt"    -Encoding UTF8
[Environment]::GetEnvironmentVariable("Path","Machine") | Out-File "$backupDir\machine-path-$stamp.txt" -Encoding UTF8
OK "Backed up to $backupDir"

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

# ---------- Find and fix Python ----------
Step "Checking Python"
Refresh-Path

# Enumerate every python.exe under the install roots winget AND choco use.
# Choco installs to C:\Python314\, winget to %LOCALAPPDATA%\Programs\Python\Python314\.
function Find-PythonInstalls {
    $found = @()
    $found += Get-ChildItem -Path "$env:LOCALAPPDATA\Programs\Python" -Filter "python.exe" -Recurse -ErrorAction SilentlyContinue
    $found += Get-ChildItem -Path "$env:ProgramFiles\Python*" -Filter "python.exe" -ErrorAction SilentlyContinue
    $found += Get-ChildItem -Path "${env:ProgramFiles(x86)}\Python*" -Filter "python.exe" -ErrorAction SilentlyContinue
    $found += Get-ChildItem -Path "C:\Python*" -Filter "python.exe" -ErrorAction SilentlyContinue
    return @($found | Where-Object { $_.FullName -notmatch '\\WindowsApps\\' })
}

function Install-Python {
    $pythonExe = $null

    # 1. Enumerate ALL python.exe under common install roots (don't trust Get-Command order)
    $pyCandidates = Find-PythonInstalls

    # 2. Pick the highest-version install
    $best = $null
    foreach ($c in $pyCandidates) {
        try {
            $v = (& $c.FullName --version 2>&1) -replace '^Python\s+',''
            if ($v -match '^\d+\.\d+') {
                if (-not $best -or [version]$best.Version -lt [version]$v) {
                    $best = [PSCustomObject]@{ Path = $c.FullName; Version = $v }
                }
            }
        } catch { }
    }

    if ($best -and ([version]$best.Version -ge [version]"3.14")) {
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
                Set-Result -Tool 'python' -Status 'PathFixed' -Version $best.Version -Path $pythonExe
            } else {
                Warn "WOULD prepend Python to PATH (diagnose only)"
                Set-Result -Tool 'python' -Status 'Skipped' -Version $best.Version -Path $pythonExe -Notes "PATH fix pending"
            }
        } else {
            Set-Result -Tool 'python' -Status 'AlreadyInstalled' -Version $best.Version -Path $pythonExe
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
    if (-not (Invoke-PackageInstall -WingetId 'Python.Python.3.14' -ChocoId 'python3')) {
        Fail "Install of Python failed via $($script:PackageManager) (exit code $LASTEXITCODE)"
        Set-Result -Tool 'python' -Status 'Failed' -Notes "$($script:PackageManager) exit $LASTEXITCODE"
        return
    }
    Refresh-Path

    # Re-find after install. Re-enumerate roots so we catch both winget AND choco paths.
    $newPath = Find-PythonInstalls |
        Where-Object { ((& $_.FullName --version 2>&1) -replace '^Python\s+','') -match '^3\.14' } |
        Select-Object -First 1
    if ($newPath) {
        $pyDir = Split-Path $newPath.FullName -Parent
        $scriptsDir = Join-Path $pyDir "Scripts"
        $userEntries = Get-UserPath
        $filtered = $userEntries | Where-Object { $_ -ne $pyDir -and $_ -ne $scriptsDir }
        Set-UserPath (@($pyDir, $scriptsDir) + $filtered)
        $env:Path = "$pyDir;$scriptsDir;$env:Path"
        $v = (& $newPath.FullName --version 2>&1) -replace '^Python\s+',''
        OK "Python $v installed and on PATH: $($newPath.FullName)"
        Set-Result -Tool 'python' -Status 'Installed' -Version $v -Path $newPath.FullName
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
    if ($nodeCmd) {
        $nv = "$(& node --version 2>&1)".Trim()
        # npm.cmd, not bare "npm": npm 11.x ships an npm.ps1 shim that mangles
        # args when invoked as `& npm` from another .ps1 ("Unknown command: pm").
        $npmv = "$(& npm.cmd --version 2>&1)".Trim()
        OK "node $nv,  npm $npmv  ($($nodeCmd.Source))"

        $major = [int]($nv -replace '^v(\d+)\..*','$1')
        if ($major -lt 18) {
            Warn "Node $nv is below v18. Upgrading via $($script:PackageManager)..."
            if (-not $DiagnoseOnly) {
                Invoke-PackageInstall -WingetId 'OpenJS.NodeJS.LTS' -ChocoId 'nodejs-lts' | Out-Null
                Refresh-Path
                $nv2 = "$(& node --version 2>&1)".Trim()
                OK "node upgraded: $nv2"
                Set-Result -Tool 'node' -Status 'Installed' -Version $nv2 -Path (Get-Command node).Source
            } else {
                Set-Result -Tool 'node' -Status 'Skipped' -Version $nv -Path $nodeCmd.Source -Notes "Would upgrade to LTS"
            }
        } else {
            Set-Result -Tool 'node' -Status 'AlreadyInstalled' -Version $nv -Path $nodeCmd.Source
        }

        # Always make sure npm-global folder is on PATH (it's where supabase/vercel land)
        $npmGlobal = "$env:APPDATA\npm"
        if (Test-Path $npmGlobal) {
            Add-UserPathEntry $npmGlobal | Out-Null
        }
        return
    }

    Warn "node not on PATH. Searching for existing install..."
    $nodeCandidates = @(
        "$env:ProgramFiles\nodejs\node.exe",
        "${env:ProgramFiles(x86)}\nodejs\node.exe",
        "$env:LOCALAPPDATA\Programs\nodejs\node.exe"
    )
    $found = $nodeCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
    if ($found) {
        $nodeDir = Split-Path $found -Parent
        Add-UserPathEntry $nodeDir | Out-Null
        Refresh-Path
        $nv = "$(& node --version 2>&1)".Trim()
        OK "Found existing Node $nv at: $found (PATH fixed)"
        Set-Result -Tool 'node' -Status 'PathFixed' -Version $nv -Path $found
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
    if ($nodeCmd) {
        $nv = "$(& node --version 2>&1)".Trim()
        OK "Node $nv installed: $($nodeCmd.Source)"
        Set-Result -Tool 'node' -Status 'Installed' -Version $nv -Path $nodeCmd.Source

        # Add npm-global folder
        $npmGlobal = "$env:APPDATA\npm"
        if (-not (Test-Path $npmGlobal)) { New-Item -ItemType Directory -Path $npmGlobal -Force | Out-Null }
        Add-UserPathEntry $npmGlobal | Out-Null
    } else {
        Fail "Node install reported success but node.exe not found"
        Set-Result -Tool 'node' -Status 'Failed' -Notes "Post-install search failed"
    }
}

Install-Node

# ---------- Find and fix Git ----------
Step "Checking Git"
Refresh-Path

function Install-Git {
    $gitCmd = Get-Command git -ErrorAction SilentlyContinue
    if ($gitCmd) {
        $gv = "$(& git --version 2>&1)".Trim()
        OK "$gv  ($($gitCmd.Source))"
        Set-Result -Tool 'git' -Status 'AlreadyInstalled' -Version ($gv -replace '^git version\s+','') -Path $gitCmd.Source
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
        if ($gitCmd) {
            $gv = "$(& git --version 2>&1)".Trim()
            OK "Git installed: $gv"
            Set-Result -Tool 'git' -Status 'Installed' -Version ($gv -replace '^git version\s+','') -Path $gitCmd.Source
        } else {
            Fail "Git install reported success but git not on PATH"
            Set-Result -Tool 'git' -Status 'Failed' -Notes "Post-install search failed"
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
            $script:GitIdentityMissing = $true
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
        try {
            $ghv = "$(& gh --version 2>&1 | Select-Object -First 1)".Trim()
            OK "$ghv  ($($ghCmd.Source))"
            $verOnly = $ghv -replace '^gh version\s+(\S+).*','$1'
            Set-Result -Tool 'gh' -Status 'AlreadyInstalled' -Version $verOnly -Path $ghCmd.Source
        } catch {
            Warn "gh found but --version failed: $_"
            Set-Result -Tool 'gh' -Status 'Failed' -Path $ghCmd.Source -Notes $_.Exception.Message
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
    if ($ghCmd) {
        $ghv = "$(& gh --version 2>&1 | Select-Object -First 1)".Trim()
        OK "GitHub CLI installed: $ghv"
        Set-Result -Tool 'gh' -Status 'Installed' -Version ($ghv -replace '^gh version\s+(\S+).*','$1') -Path $ghCmd.Source
    } else {
        Fail "gh install reported success but gh not on PATH"
        Set-Result -Tool 'gh' -Status 'Failed' -Notes "Post-install search failed"
    }
}

Install-GitHubCLI

# ---------- Find and install Supabase CLI ----------
Step "Checking Supabase CLI"
Refresh-Path

function Install-SupabaseCLI {
    $sbCmd = Get-Command supabase -ErrorAction SilentlyContinue
    if ($sbCmd) {
        try {
            $sbv = "$(& supabase --version 2>&1)".Trim()
            OK "supabase $sbv  ($($sbCmd.Source))"
            Set-Result -Tool 'supabase' -Status 'AlreadyInstalled' -Version $sbv -Path $sbCmd.Source
        } catch {
            Warn "supabase found but --version failed: $_"
            Set-Result -Tool 'supabase' -Status 'Failed' -Path $sbCmd.Source -Notes $_.Exception.Message
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
    if ($sbCmd) {
        $sbv = "$(& supabase --version 2>&1)".Trim()
        OK "Supabase CLI installed: $sbv"
        Set-Result -Tool 'supabase' -Status 'Installed' -Version $sbv -Path $sbCmd.Source
    } else {
        Fail "Supabase install reported success but supabase not on PATH"
        Set-Result -Tool 'supabase' -Status 'Failed' -Notes "Post-install search failed"
    }
}

Install-SupabaseCLI

# ---------- Find and install Vercel CLI ----------
Step "Checking Vercel CLI"
Refresh-Path

function Install-VercelCLI {
    $vcCmd = Get-Command vercel -ErrorAction SilentlyContinue
    if ($vcCmd) {
        try {
            $vcv = "$(& vercel --version 2>&1 | Select-Object -First 1)".Trim()
            OK "vercel $vcv  ($($vcCmd.Source))"
            Set-Result -Tool 'vercel' -Status 'AlreadyInstalled' -Version $vcv -Path $vcCmd.Source
        } catch {
            Warn "vercel found but --version failed: $_"
            Set-Result -Tool 'vercel' -Status 'Failed' -Path $vcCmd.Source -Notes $_.Exception.Message
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
    if ($vcCmd) {
        $vcv = "$(& vercel --version 2>&1 | Select-Object -First 1)".Trim()
        OK "Vercel CLI installed: $vcv"
        Set-Result -Tool 'vercel' -Status 'Installed' -Version $vcv -Path $vcCmd.Source
    } else {
        Fail "Vercel install reported success but vercel not on PATH"
        Set-Result -Tool 'vercel' -Status 'Failed' -Notes "Post-install search failed"
    }
}

Install-VercelCLI

# ---------- Install Claude Code ----------
if (-not $SkipClaudeCode -and -not $DiagnoseOnly) {
    Step "Installing Claude Code"
    Refresh-Path

    $existing = Get-Command claude -ErrorAction SilentlyContinue
    if ($existing) {
        try {
            $cv = "$(& claude --version 2>&1)".Trim()
            OK "Claude Code already installed: $cv  ($($existing.Source))"
            Set-Result -Tool 'claude' -Status 'AlreadyInstalled' -Version $cv -Path $existing.Source
        } catch {
            Warn "claude on PATH but doesn't run cleanly: $_"
            Set-Result -Tool 'claude' -Status 'Failed' -Path $existing.Source -Notes $_.Exception.Message
        }
    } else {
        $installed = $false

        # npm only: the native installer (claude.ai/install.ps1) runs `claude install`
        # interactively for shell integration, which silently hangs when invoked via
        # Invoke-Expression. npm install is non-interactive and gives the same CLI.
        if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
            Fail "npm not available - cannot install Claude Code. Node should have been installed earlier."
        } else {
            Info "Installing Claude Code via npm install -g @anthropic-ai/claude-code..."
            & npm.cmd install -g "@anthropic-ai/claude-code" | Out-Host
            if ($LASTEXITCODE -eq 0) {
                $installed = $true
                OK "Claude Code installed via npm"
            } else {
                Fail "npm install failed (exit code $LASTEXITCODE)"
            }
        }

        Refresh-Path

        # Find where it landed and ensure it's on PATH
        if ($installed) {
            $claudeCandidates = @(
                "$env:LOCALAPPDATA\Programs\claude\claude.exe",
                "$env:LOCALAPPDATA\AnthropicClaude\claude.exe",
                "$env:USERPROFILE\.local\bin\claude.exe",
                "$env:APPDATA\npm\claude.cmd",
                "$env:APPDATA\npm\claude.ps1"
            )
            $claudeFound = $claudeCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
            if ($claudeFound) {
                $cdir = Split-Path $claudeFound -Parent
                Add-UserPathEntry $cdir | Out-Null
                Refresh-Path
                OK "Claude Code binary: $claudeFound"
                try {
                    $cv = "$(& claude --version 2>&1)".Trim()
                    Set-Result -Tool 'claude' -Status 'Installed' -Version $cv -Path $claudeFound
                } catch {
                    Set-Result -Tool 'claude' -Status 'Installed' -Path $claudeFound -Notes "Installed but --version failed: $_"
                }
            } else {
                Set-Result -Tool 'claude' -Status 'Failed' -Notes "Install reported success but binary not found in known locations"
            }
        } else {
            Set-Result -Tool 'claude' -Status 'Failed' -Notes "All install methods failed"
        }
    }
}

if (-not $script:results.Contains('claude')) {
    if ($SkipClaudeCode) {
        Set-Result -Tool 'claude' -Status 'Skipped' -Notes "Skipped via -SkipClaudeCode flag"
    } elseif ($DiagnoseOnly) {
        $existing = Get-Command claude -ErrorAction SilentlyContinue
        if ($existing) {
            try {
                $cv = "$(& claude --version 2>&1)".Trim()
                Set-Result -Tool 'claude' -Status 'AlreadyInstalled' -Version $cv -Path $existing.Source
            } catch {
                Set-Result -Tool 'claude' -Status 'Failed' -Path $existing.Source -Notes "Found but --version failed"
            }
        } else {
            Set-Result -Tool 'claude' -Status 'Skipped' -Notes "Would install via npm"
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
        try {
            $exe = if ($tool -eq 'npm') { 'npm.cmd' } else { $tool }
            $v = "$(& $exe --version 2>&1 | Select-Object -First 1)".Trim()
            # Only update if we don't already have a richer entry
            if (-not $script:results.Contains($tool)) {
                Set-Result -Tool $tool -Status 'AlreadyInstalled' -Version $v -Path $cmd.Source
            }
        } catch {
            if (-not $script:results.Contains($tool)) {
                Set-Result -Tool $tool -Status 'Failed' -Path $cmd.Source -Notes "$_"
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
    Say "  Next steps - sign in to each CLI (run these in this same window):" White
    Say "      gh auth login" White
    Say "      supabase login" White
    Say "      vercel login" White
    Write-Host ""
    Say "  (Each will open a browser. Follow the prompts.)" Gray
    if ($script:GitIdentityMissing) {
        Write-Host ""
        Say "  Before your first git commit, set your identity:" Yellow
        Say "      git config --global user.name `"Your Name`"" White
        Say "      git config --global user.email `"you@example.com`"" White
    }
} else {
    Say "  Some tools failed. See the table above." Yellow
    Say "  Try closing this window and opening a fresh PowerShell as Administrator," Yellow
    Say "  then re-run this script. If the same tools fail again, share the log:" Yellow
    if ($script:LogPath) { Say "      $($script:LogPath)" White }
    Write-Host ""
    Say "  Next steps once all tools are working - sign in to each CLI:" Gray
    Say "      gh auth login" Gray
    Say "      supabase login" Gray
    Say "      vercel login" Gray
    if ($script:GitIdentityMissing) {
        Say "  Before your first git commit:" Gray
        Say "      git config --global user.name `"Your Name`"" Gray
        Say "      git config --global user.email `"you@example.com`"" Gray
    }
}
$elapsed = (Get-Date) - $script:StartTime
Say ("  Total time: {0} min {1:D2} sec" -f [int]$elapsed.TotalMinutes, $elapsed.Seconds) Gray
Say "  PATH backups: $backupDir" Gray
Say "=================================================================" Cyan
Write-Host ""

# --- Stop transcript ---
if ($script:LogPath) {
    try { Stop-Transcript | Out-Null } catch { }
    Write-Host "Session log: $($script:LogPath)" -ForegroundColor Gray
}
