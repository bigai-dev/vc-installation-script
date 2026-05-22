<#
.SYNOPSIS
    Vibe Code Workshop — fix "xxx is not recognized" errors after following the handbook.

.DESCRIPTION
    The handbook tells you to install Python and Node.js via .exe/.msi installers.
    This is fine, but it produces the "not recognized" error in several common ways:

      1. Python: missing the "Add python.exe to PATH" checkbox during install.
      2. Node:   PATH update didn't reach your already-open PowerShell window.
      3. Either: corrupted PATH (>1024 chars, broken entries, duplicates).
      4. Either: install succeeded but in a folder that never got added to PATH.

    This script:
      - Finds python.exe and node.exe even if they're not on PATH
      - Adds the correct folders to your User PATH (no admin needed, no setx)
      - Backs up your PATH before changing anything
      - Cleans broken entries and duplicates
      - Installs Claude Code via the official native installer
      - Tells you EXACTLY which command is broken and why

.USAGE
    1. Right-click PowerShell -> Run as Administrator (or regular user works too)
    2. Run:  Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
    3. Run:  .\fix-vibecode.ps1
    4. CLOSE this PowerShell window and open a fresh one
    5. Type:  python --version    node --version    claude --version

.PARAMETER DiagnoseOnly
    Don't change anything, just show what's wrong.

.PARAMETER SkipClaudeCode
    Don't install Claude Code (only fix Python/Node PATH).
#>

[CmdletBinding()]
param(
    [switch]$DiagnoseOnly,
    [switch]$SkipClaudeCode
)

$ErrorActionPreference = "Continue"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

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

# ---------- Preflight: check winget is available ----------
Step "Checking winget availability"
$wingetCmd = Get-Command winget -ErrorAction SilentlyContinue
if (-not $wingetCmd) {
    Fail "winget is not installed."
    Info "Install 'App Installer' from the Microsoft Store, then re-run this script:"
    Info "  https://apps.microsoft.com/detail/9NBLGGH4NNS1"
    Info ""
    Info "After install, close PowerShell, open a fresh window, and run this script again."
    if ($script:LogPath) { try { Stop-Transcript | Out-Null } catch { } }
    exit 2
} else {
    try {
        $wv = (& winget --version) 2>&1
        OK "winget $wv"
    } catch {
        Warn "winget found but did not respond to --version: $_"
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

$pythonExe = $null
$pyCmd = Get-Command python -ErrorAction SilentlyContinue
if ($pyCmd -and $pyCmd.Source -notmatch "WindowsApps\\python\.exe$") {
    # Beware of the Microsoft Store stub at WindowsApps\python.exe — it launches the store
    $pythonExe = $pyCmd.Source
    OK "python found: $pythonExe"
} else {
    if ($pyCmd) {
        Warn "Only the Microsoft Store stub is on PATH (not a real Python). Searching for the real one..."
    } else {
        Warn "python not on PATH. Searching for the install..."
    }

    # Common Python install locations (handbook uses standalone installer to LocalAppData by default)
    $pyCandidates = @()
    $pyCandidates += Get-ChildItem -Path "$env:LOCALAPPDATA\Programs\Python" -Filter "python.exe" -Recurse -ErrorAction SilentlyContinue
    $pyCandidates += Get-ChildItem -Path "$env:ProgramFiles\Python*" -Filter "python.exe" -ErrorAction SilentlyContinue
    $pyCandidates += Get-ChildItem -Path "${env:ProgramFiles(x86)}\Python*" -Filter "python.exe" -ErrorAction SilentlyContinue

    # Prefer the highest version found
    $pyCandidates = $pyCandidates | Where-Object { $_.FullName -notmatch "WindowsApps" } | Sort-Object FullName -Descending

    if ($pyCandidates.Count -gt 0) {
        $pythonExe = $pyCandidates[0].FullName
        $pyDir = Split-Path $pythonExe -Parent
        $scriptsDir = Join-Path $pyDir "Scripts"

        OK "Found Python at: $pythonExe"
        Info "(The handbook's 'Add python.exe to PATH' checkbox was probably missed)"

        # Add both python folder and Scripts folder (for pip-installed tools)
        Add-UserPathEntry $pyDir | Out-Null
        if (Test-Path $scriptsDir) { Add-UserPathEntry $scriptsDir | Out-Null }
    } else {
        Fail "No Python install found anywhere."
        Info "Re-run the handbook's Python steps, and THIS TIME tick"
        Info "'Add python.exe to PATH' on the first installer screen."
    }
}

# Verify python works now
if ($pythonExe) {
    Refresh-Path
    try {
        $v = & $pythonExe --version 2>&1
        OK "Python version: $v"
    } catch {
        Fail "Could not run python: $_"
    }
}

# ---------- Find and fix Node.js ----------
Step "Checking Node.js"
Refresh-Path

$nodeExe = $null
$nodeCmd = Get-Command node -ErrorAction SilentlyContinue
if ($nodeCmd) {
    $nodeExe = $nodeCmd.Source
    OK "node found: $nodeExe"
} else {
    Warn "node not on PATH. Searching..."
    $nodeCandidates = @(
        "$env:ProgramFiles\nodejs\node.exe",
        "${env:ProgramFiles(x86)}\nodejs\node.exe",
        "$env:LOCALAPPDATA\Programs\nodejs\node.exe"
    )
    $found = $nodeCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
    if ($found) {
        $nodeExe = $found
        $nodeDir = Split-Path $found -Parent
        OK "Found Node at: $nodeExe"
        Info "(The .msi added it to System PATH, but your shell hasn't seen the update)"
        Add-UserPathEntry $nodeDir | Out-Null
    } else {
        Fail "No Node.js install found."
        Info "Re-run the handbook's Node.js steps (Windows Installer .msi)."
    }
}

# Verify node + npm
if ($nodeExe) {
    Refresh-Path
    try {
        $nv = & node --version 2>&1
        $npmv = & npm --version 2>&1
        OK "node $nv,  npm $npmv"

        # Check Node version meets Claude Code's minimum (18+)
        $major = [int]($nv -replace '^v(\d+)\..*','$1')
        if ($major -lt 18) {
            Warn "Node $nv is below v18, which Claude Code requires."
            Info "Re-download the LTS .msi from nodejs.org (currently v20 or v22)."
        }
    } catch {
        Fail "Could not run node/npm: $_"
    }

    # Make sure the npm global folder is on PATH (this is where 'claude' lives if installed via npm)
    $npmGlobal = "$env:APPDATA\npm"
    if (Test-Path $npmGlobal) {
        Add-UserPathEntry $npmGlobal | Out-Null
    }
}

# ---------- Install Claude Code ----------
if (-not $SkipClaudeCode -and -not $DiagnoseOnly) {
    Step "Installing Claude Code"
    Refresh-Path

    $existing = Get-Command claude -ErrorAction SilentlyContinue
    if ($existing) {
        try {
            $cv = & claude --version 2>&1
            OK "Claude Code already installed: $cv  ($($existing.Source))"
        } catch {
            Warn "claude on PATH but doesn't run cleanly: $_"
        }
    } else {
        $installed = $false

        # Method 1: Anthropic's native Windows installer (bundles its own runtime, no Node needed)
        Info "Trying official native installer..."
        try {
            $script = Invoke-RestMethod -Uri "https://claude.ai/install.ps1" -UseBasicParsing
            Invoke-Expression $script
            $installed = $true
            OK "Claude Code installed via native installer"
        } catch {
            Warn "Native installer failed: $($_.Exception.Message)"
        }

        # Method 2: npm fallback
        if (-not $installed -and $nodeExe) {
            Info "Falling back to npm install -g @anthropic-ai/claude-code"
            try {
                & npm install -g "@anthropic-ai/claude-code" 2>&1 | Out-Host
                $installed = $true
                OK "Claude Code installed via npm"
            } catch {
                Fail "npm install also failed: $_"
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
                OK "Claude Code binary: $claudeFound"
            }
        }
    }
}

# ---------- Final verification ----------
Step "Final check"
Refresh-Path
$tools = @("python","node","npm")
if (-not $SkipClaudeCode) { $tools += "claude" }

$allGood = $true
foreach ($t in $tools) {
    $cmd = Get-Command $t -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.Source -notmatch "WindowsApps\\$t\.exe$") {
        OK "$t -> $($cmd.Source)"
    } else {
        Warn "$t still not resolvable in THIS shell (probably fine in a fresh one)"
        $allGood = $false
    }
}

Write-Host ""
Say "=================================================================" Cyan
if ($DiagnoseOnly) {
    Say "  Diagnose mode finished. Re-run WITHOUT -DiagnoseOnly to apply fixes." Yellow
} elseif ($allGood) {
    Say "  Done. Close this window, open a fresh PowerShell, then test:" Green
    Say "      python --version" White
    Say "      node --version" White
    Say "      npm --version" White
    if (-not $SkipClaudeCode) { Say "      claude --version" White }
} else {
    Say "  Almost done. Now CLOSE this window and open a fresh PowerShell." Yellow
    Say "  PATH changes don't apply to terminals that were already open." Yellow
    Say "  In the new window, test:" Gray
    Say "      python --version" White
    Say "      node --version" White
    if (-not $SkipClaudeCode) { Say "      claude --version" White }
    Say "" Gray
    Say "  If it still fails, re-run this script with -DiagnoseOnly to see why." Gray
}
Say "  PATH backups saved in: $backupDir" Gray
Say "=================================================================" Cyan
Write-Host ""

# --- Stop transcript ---
if ($script:LogPath) {
    try { Stop-Transcript | Out-Null } catch { }
    Write-Host "Session log: $($script:LogPath)" -ForegroundColor Gray
}
