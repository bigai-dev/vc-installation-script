# Windows Vibe Coding Setup Script Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend the existing `script/fix-vibecode.ps1` so it not only repairs PATH but also installs missing tools (Python, Node, Git, gh, supabase, vercel) via winget/npm, prompts for git config, logs the session, and produces a final verification table — all from a single double-click of `run-fixer.bat`.

**Architecture:** Single PowerShell script (extends existing one). Two modes: `-DiagnoseOnly` (read-only) and default (install + repair + verify). A `.bat` wrapper self-elevates to admin. All tool installers follow a shared contract that writes results to a `$script:results` hashtable; the final report is a pure render of that hashtable. Pure helpers (version compare, stub detection, PATH parsing) are unit-tested with Pester; install paths are smoke-tested on a Windows VM.

**Tech Stack:** PowerShell 5.1+ (built into Windows), winget, npm (after Node install), Pester 5 for unit tests. No external packages beyond what's being installed.

---

## File Structure

```
windows-vc-script/
├── script/
│   ├── fix-vibecode.ps1            (MODIFY — extend with install logic, transcript, results, install funcs)
│   └── run-fixer.bat                (unchanged — already handles self-elevation)
├── tests/
│   ├── Helpers.psm1                 (NEW — extract pure helpers as a module for testing)
│   ├── Compare-Version.Tests.ps1    (NEW)
│   ├── PathHelpers.Tests.ps1        (NEW)
│   └── StubDetection.Tests.ps1      (NEW)
├── docs/
│   ├── superpowers/specs/2026-05-22-windows-vc-setup-script-design.md  (existing)
│   ├── superpowers/plans/2026-05-22-windows-vc-setup-script.md         (this file)
│   └── MANUAL-VM-TEST.md            (NEW — manual end-to-end test checklist)
└── VIBE_CODING_WORKSHOP_GUIDE.md   (existing — out of scope; will be updated separately)
```

Key boundary: pure helpers live in `tests/Helpers.psm1` (testable in isolation); side-effect-having code (winget calls, registry writes) stays in `fix-vibecode.ps1` and is exercised only by the manual VM test.

---

## Pre-flight verification

### Task 0: Verify external assumptions before coding

**Files:** None — this is research.

- [ ] **Step 1: Confirm winget package IDs resolve**

On any Windows machine (your laptop, a VM, or a workshop student's machine you're helping), run:

```powershell
winget show Python.Python.3.14
winget show OpenJS.NodeJS.LTS
winget show Git.Git
winget show GitHub.cli
```

Expected: each prints "Found ..." and a version. If any returns "No package found matching input criteria", update the spec and this plan to use the correct ID before continuing.

- [ ] **Step 2: Confirm Claude Code native installer URL still works**

```powershell
(Invoke-WebRequest -Uri "https://claude.ai/install.ps1" -UseBasicParsing).StatusCode
```

Expected: `200`. If it returns 404 or redirects somewhere unexpected, update Task 13 to use only the npm fallback.

- [ ] **Step 3: Initialize git in the workspace if not already**

Run from `/Users/jayte/windows-vc-script`:

```bash
git status 2>&1 | head -1
```

If output starts with `fatal: not a git repository`, run:

```bash
git init && git add -A && git commit -m "chore: initial state before plan execution"
```

If it's already a repo, leave it alone.

---

## Helpers extraction & unit tests

### Task 1: Extract Compare-Version helper to a testable module

**Files:**
- Create: `tests/Helpers.psm1`
- Create: `tests/Compare-Version.Tests.ps1`

- [ ] **Step 1: Write the failing test**

Create `tests/Compare-Version.Tests.ps1`:

```powershell
BeforeAll {
    Import-Module "$PSScriptRoot/Helpers.psm1" -Force
}

Describe "Compare-Version" {
    It "returns 0 for equal versions" {
        Compare-Version "3.14.0" "3.14.0" | Should -Be 0
    }
    It "returns 1 when left is newer (patch)" {
        Compare-Version "3.14.1" "3.14.0" | Should -Be 1
    }
    It "returns -1 when left is older (minor)" {
        Compare-Version "3.13.5" "3.14.0" | Should -Be -1
    }
    It "handles 'v' prefix on Node-style versions" {
        Compare-Version "v24.0.0" "v18.0.0" | Should -Be 1
    }
    It "treats missing patch as 0" {
        Compare-Version "3.14" "3.14.0" | Should -Be 0
    }
    It "returns 1 when left has more components and they're nonzero" {
        Compare-Version "3.14.0.1" "3.14.0" | Should -Be 1
    }
}
```

- [ ] **Step 2: Run the test and verify it fails**

On a machine with Pester installed (`Install-Module Pester -Scope CurrentUser` on Windows, or `pwsh` + Pester on Mac):

```powershell
Invoke-Pester tests/Compare-Version.Tests.ps1 -Output Detailed
```

Expected: all tests fail with "module not found" or "command not found: Compare-Version".

- [ ] **Step 3: Implement Compare-Version in Helpers.psm1**

Create `tests/Helpers.psm1`:

```powershell
function Compare-Version {
    param(
        [Parameter(Mandatory)][string]$Left,
        [Parameter(Mandatory)][string]$Right
    )
    $normalize = {
        param($v)
        ($v -replace '^v','').Split('.') | ForEach-Object { [int]$_ }
    }
    $l = & $normalize $Left
    $r = & $normalize $Right
    $max = [Math]::Max($l.Count, $r.Count)
    for ($i = 0; $i -lt $max; $i++) {
        $lv = if ($i -lt $l.Count) { $l[$i] } else { 0 }
        $rv = if ($i -lt $r.Count) { $r[$i] } else { 0 }
        if ($lv -gt $rv) { return 1 }
        if ($lv -lt $rv) { return -1 }
    }
    return 0
}

Export-ModuleMember -Function Compare-Version
```

- [ ] **Step 4: Run the test and verify all pass**

```powershell
Invoke-Pester tests/Compare-Version.Tests.ps1 -Output Detailed
```

Expected: 6 passed, 0 failed.

- [ ] **Step 5: Commit**

```bash
git add tests/Helpers.psm1 tests/Compare-Version.Tests.ps1
git commit -m "test: add Compare-Version helper with Pester tests"
```

---

### Task 2: Add Is-WindowsAppsStub helper

**Files:**
- Modify: `tests/Helpers.psm1`
- Create: `tests/StubDetection.Tests.ps1`

- [ ] **Step 1: Write the failing test**

Create `tests/StubDetection.Tests.ps1`:

```powershell
BeforeAll {
    Import-Module "$PSScriptRoot/Helpers.psm1" -Force
}

Describe "Is-WindowsAppsStub" {
    It "detects the MS Store python stub path" {
        Is-WindowsAppsStub "C:\Users\test\AppData\Local\Microsoft\WindowsApps\python.exe" | Should -BeTrue
    }
    It "detects the stub regardless of executable name" {
        Is-WindowsAppsStub "C:\Users\test\AppData\Local\Microsoft\WindowsApps\python3.exe" | Should -BeTrue
    }
    It "returns false for a real Python install" {
        Is-WindowsAppsStub "C:\Users\test\AppData\Local\Programs\Python\Python314\python.exe" | Should -BeFalse
    }
    It "returns false for null or empty input" {
        Is-WindowsAppsStub $null  | Should -BeFalse
        Is-WindowsAppsStub ""     | Should -BeFalse
    }
}
```

- [ ] **Step 2: Run the test and verify it fails**

```powershell
Invoke-Pester tests/StubDetection.Tests.ps1 -Output Detailed
```

Expected: 4 tests fail with "command not found: Is-WindowsAppsStub".

- [ ] **Step 3: Implement Is-WindowsAppsStub**

Append to `tests/Helpers.psm1`:

```powershell
function Is-WindowsAppsStub {
    param([string]$Path)
    if ([string]::IsNullOrEmpty($Path)) { return $false }
    return $Path -match '\\WindowsApps\\[^\\]+\.exe$'
}

Export-ModuleMember -Function Is-WindowsAppsStub
```

Make sure the existing `Export-ModuleMember -Function Compare-Version` line is updated to also export the new function, or add a separate `Export-ModuleMember` line as above.

- [ ] **Step 4: Run the test and verify all pass**

```powershell
Invoke-Pester tests/StubDetection.Tests.ps1 -Output Detailed
```

Expected: 4 passed, 0 failed.

- [ ] **Step 5: Run all tests to confirm no regressions**

```powershell
Invoke-Pester tests/ -Output Detailed
```

Expected: 10 passed, 0 failed.

- [ ] **Step 6: Commit**

```bash
git add tests/Helpers.psm1 tests/StubDetection.Tests.ps1
git commit -m "test: add Is-WindowsAppsStub helper with Pester tests"
```

---

### Task 3: Add Get-CleanedPath helper (pure version of existing PATH cleaning logic)

**Files:**
- Modify: `tests/Helpers.psm1`
- Create: `tests/PathHelpers.Tests.ps1`

- [ ] **Step 1: Write the failing test**

Create `tests/PathHelpers.Tests.ps1`:

```powershell
BeforeAll {
    Import-Module "$PSScriptRoot/Helpers.psm1" -Force
}

Describe "Get-CleanedPath" {
    It "removes empty entries" {
        $result = Get-CleanedPath @("C:\foo", "", "C:\bar", $null)
        $result.Entries | Should -Be @("C:\foo", "C:\bar")
    }
    It "deduplicates case-insensitively" {
        $result = Get-CleanedPath @("C:\foo", "c:\FOO", "C:\bar")
        $result.Entries | Should -Be @("C:\foo", "C:\bar")
        $result.DuplicatesRemoved | Should -Be 1
    }
    It "preserves env-var entries even if path does not currently exist" {
        $result = Get-CleanedPath @("%JAVA_HOME%\bin", "C:\nonexistent-zzz")
        $result.Entries | Should -Contain "%JAVA_HOME%\bin"
    }
    It "removes entries pointing to nonexistent disk paths" {
        $result = Get-CleanedPath @("C:\foo", "C:\does-not-exist-xyz-zzz")
        # Only C:\foo if it exists, otherwise empty — we assert by checking BrokenRemoved
        $result.BrokenRemoved | Should -BeGreaterOrEqual 1
    }
}
```

- [ ] **Step 2: Run the test and verify it fails**

```powershell
Invoke-Pester tests/PathHelpers.Tests.ps1 -Output Detailed
```

Expected: 4 tests fail with "command not found: Get-CleanedPath".

- [ ] **Step 3: Implement Get-CleanedPath**

Append to `tests/Helpers.psm1`:

```powershell
function Get-CleanedPath {
    param([string[]]$Entries)
    $cleaned = @()
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $broken = 0
    $dups = 0
    foreach ($e in $Entries) {
        if ([string]::IsNullOrWhiteSpace($e)) { continue }
        $trimmed = $e.Trim()
        if (-not $seen.Add($trimmed)) { $dups++; continue }
        $expanded = [Environment]::ExpandEnvironmentVariables($trimmed)
        if ($trimmed -match '%[^%]+%' -or (Test-Path -LiteralPath $expanded -ErrorAction SilentlyContinue)) {
            $cleaned += $trimmed
        } else {
            $broken++
        }
    }
    return [PSCustomObject]@{
        Entries           = $cleaned
        BrokenRemoved     = $broken
        DuplicatesRemoved = $dups
    }
}

Export-ModuleMember -Function Get-CleanedPath
```

- [ ] **Step 4: Run all tests to verify**

```powershell
Invoke-Pester tests/ -Output Detailed
```

Expected: 14 passed, 0 failed.

- [ ] **Step 5: Commit**

```bash
git add tests/Helpers.psm1 tests/PathHelpers.Tests.ps1
git commit -m "test: add Get-CleanedPath helper with Pester tests"
```

---

## Extend fix-vibecode.ps1: infrastructure first

### Task 4: Add Start-Transcript session logging

**Files:**
- Modify: `script/fix-vibecode.ps1` (insert after the param block, before output helpers)

- [ ] **Step 1: Insert transcript start near the top of the script**

Open `script/fix-vibecode.ps1`. Find the line:

```powershell
$ErrorActionPreference = "Continue"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
```

Add immediately after:

```powershell
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
```

- [ ] **Step 2: Add Stop-Transcript at the very end of the script**

At the absolute bottom of `fix-vibecode.ps1` (after the last `Write-Host`), add:

```powershell
# --- Stop transcript ---
if ($script:LogPath) {
    try { Stop-Transcript | Out-Null } catch { }
    Write-Host "Session log: $($script:LogPath)" -ForegroundColor Gray
}
```

- [ ] **Step 3: Smoke-test on a Windows machine**

On Windows, run:

```powershell
.\script\fix-vibecode.ps1 -DiagnoseOnly
```

Expected: runs without errors. No transcript started (because `-DiagnoseOnly`).

Then run (non-diagnose mode):

```powershell
.\script\fix-vibecode.ps1
```

Expected: at the bottom of output, `Session log: C:\...\Temp\fix-vibecode-<timestamp>.log`. Verify the file exists and contains the output you saw.

- [ ] **Step 4: Commit**

```bash
git add script/fix-vibecode.ps1
git commit -m "feat(script): add Start-Transcript session logging in fix mode"
```

---

### Task 5: Add winget preflight check

**Files:**
- Modify: `script/fix-vibecode.ps1`

- [ ] **Step 1: Add winget detection helper and call it early**

In `script/fix-vibecode.ps1`, find the line:

```powershell
# ---------- Back up PATH ----------
Step "Backing up your current PATH"
```

Insert immediately before that block:

```powershell
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
```

- [ ] **Step 2: Smoke-test the missing-winget path**

Hard to fully test without uninstalling winget. Instead, temporarily rename the `Get-Command winget` call to `Get-Command winget-NOTHERE` and re-run:

```powershell
.\script\fix-vibecode.ps1 -DiagnoseOnly
```

Expected: prints "winget is not installed" with the Microsoft Store link, exits with code 2.

Revert the rename.

- [ ] **Step 3: Smoke-test the happy path**

```powershell
.\script\fix-vibecode.ps1 -DiagnoseOnly
```

Expected: prints `[OK] winget <version>` and continues to other checks.

- [ ] **Step 4: Commit**

```bash
git add script/fix-vibecode.ps1
git commit -m "feat(script): add winget preflight check"
```

---

### Task 6: Initialize $script:results hashtable

**Files:**
- Modify: `script/fix-vibecode.ps1`

- [ ] **Step 1: Add the results scaffolding near the top**

In `script/fix-vibecode.ps1`, find:

```powershell
# ---------- Output helpers ----------
function Say($msg, $color = "White") { Write-Host $msg -ForegroundColor $color }
```

Insert immediately before that block:

```powershell
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
```

- [ ] **Step 2: Smoke-test (syntax check)**

```powershell
.\script\fix-vibecode.ps1 -DiagnoseOnly
```

Expected: runs without errors. No visible new output (we haven't wired it up to anything yet).

- [ ] **Step 3: Commit**

```bash
git add script/fix-vibecode.ps1
git commit -m "feat(script): add results hashtable and Set-Result helper"
```

---

## Wire existing tool checks into $script:results

### Task 7: Wire existing Python section into results + add install-when-missing

**Files:**
- Modify: `script/fix-vibecode.ps1`

- [ ] **Step 1: Replace the existing Python section**

Find the block starting with `# ---------- Find and fix Python ----------` and ending just before `# ---------- Find and fix Node.js ----------`. Replace the entire block with:

```powershell
# ---------- Find and fix Python ----------
Step "Checking Python"
Refresh-Path

function Install-Python {
    $pythonExe = $null
    $alreadyOk = $false

    # 1. Enumerate ALL python.exe under common install roots (don't trust Get-Command order)
    $pyCandidates = @()
    $pyCandidates += Get-ChildItem -Path "$env:LOCALAPPDATA\Programs\Python" -Filter "python.exe" -Recurse -ErrorAction SilentlyContinue
    $pyCandidates += Get-ChildItem -Path "$env:ProgramFiles\Python*" -Filter "python.exe" -ErrorAction SilentlyContinue
    $pyCandidates += Get-ChildItem -Path "${env:ProgramFiles(x86)}\Python*" -Filter "python.exe" -ErrorAction SilentlyContinue
    $pyCandidates = $pyCandidates | Where-Object { $_.FullName -notmatch '\\WindowsApps\\' }

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
        Set-Result -Tool 'python' -Status 'Skipped' -Notes "Would install Python 3.14 via winget"
        return
    }

    Info "Installing Python 3.14 via winget..."
    & winget install -e --id Python.Python.3.14 --silent --accept-package-agreements --accept-source-agreements | Out-Host
    if ($LASTEXITCODE -ne 0) {
        Fail "winget install of Python failed (exit code $LASTEXITCODE)"
        Set-Result -Tool 'python' -Status 'Failed' -Notes "winget exit $LASTEXITCODE"
        return
    }
    Refresh-Path

    # Re-find after install
    $newPath = Get-ChildItem -Path "$env:LOCALAPPDATA\Programs\Python\Python314" -Filter "python.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
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
```

- [ ] **Step 2: Smoke-test on Windows**

Run on a Windows machine that already has Python 3.14:

```powershell
.\script\fix-vibecode.ps1 -DiagnoseOnly
```

Expected: `[OK] Python 3.14.x found: <path>`. Either `AlreadyInstalled` or `Skipped` in results.

Run on a Windows machine WITHOUT Python:

```powershell
.\script\fix-vibecode.ps1
```

Expected: winget install runs, then `[OK] Python 3.14.x installed and on PATH: <path>`.

- [ ] **Step 3: Commit**

```bash
git add script/fix-vibecode.ps1
git commit -m "feat(script): install Python 3.14 via winget when missing, enumerate all installs"
```

---

### Task 8: Wire Node.js section into results + install via winget when missing

**Files:**
- Modify: `script/fix-vibecode.ps1`

- [ ] **Step 1: Replace the existing Node section**

Find the block starting with `# ---------- Find and fix Node.js ----------` and ending just before `# ---------- Install Claude Code ----------`. Replace with:

```powershell
# ---------- Find and fix Node.js ----------
Step "Checking Node.js"
Refresh-Path

function Install-Node {
    $nodeCmd = Get-Command node -ErrorAction SilentlyContinue
    if ($nodeCmd) {
        $nv = (& node --version 2>&1).Trim()
        $npmv = (& npm --version 2>&1).Trim()
        OK "node $nv,  npm $npmv  ($($nodeCmd.Source))"

        $major = [int]($nv -replace '^v(\d+)\..*','$1')
        if ($major -lt 18) {
            Warn "Node $nv is below v18. Upgrading via winget..."
            if (-not $DiagnoseOnly) {
                & winget install -e --id OpenJS.NodeJS.LTS --silent --accept-package-agreements --accept-source-agreements | Out-Host
                Refresh-Path
                $nv2 = (& node --version 2>&1).Trim()
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
        $nv = (& node --version 2>&1).Trim()
        OK "Found existing Node $nv at: $found (PATH fixed)"
        Set-Result -Tool 'node' -Status 'PathFixed' -Version $nv -Path $found
        return
    }

    if ($DiagnoseOnly) {
        Set-Result -Tool 'node' -Status 'Skipped' -Notes "Would install Node LTS via winget"
        return
    }

    Info "Installing Node.js LTS via winget..."
    & winget install -e --id OpenJS.NodeJS.LTS --silent --accept-package-agreements --accept-source-agreements | Out-Host
    if ($LASTEXITCODE -ne 0) {
        Fail "winget install of Node failed (exit code $LASTEXITCODE)"
        Set-Result -Tool 'node' -Status 'Failed' -Notes "winget exit $LASTEXITCODE"
        return
    }
    Refresh-Path
    $nodeCmd = Get-Command node -ErrorAction SilentlyContinue
    if ($nodeCmd) {
        $nv = (& node --version 2>&1).Trim()
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
```

- [ ] **Step 2: Smoke-test on Windows**

On a machine with Node already installed:

```powershell
.\script\fix-vibecode.ps1 -DiagnoseOnly
```

Expected: `[OK] node vX.X.X, npm X.X.X (<path>)` and `AlreadyInstalled` status.

On a machine without Node (or in a fresh VM), run the script without `-DiagnoseOnly` and verify `node --version` works in the same session afterward.

- [ ] **Step 3: Commit**

```bash
git add script/fix-vibecode.ps1
git commit -m "feat(script): install Node LTS via winget when missing"
```

---

### Task 9: Add Git installer + interactive name/email config

**Files:**
- Modify: `script/fix-vibecode.ps1`

- [ ] **Step 1: Insert the Git section after Node, before Claude Code**

Find this line (which appears between Node and Claude Code in the current script):

```powershell
# ---------- Install Claude Code ----------
```

Immediately before it, insert:

```powershell
# ---------- Find and fix Git ----------
Step "Checking Git"
Refresh-Path

function Install-Git {
    $gitCmd = Get-Command git -ErrorAction SilentlyContinue
    if ($gitCmd) {
        $gv = (& git --version 2>&1).Trim()
        OK "$gv  ($($gitCmd.Source))"
        Set-Result -Tool 'git' -Status 'AlreadyInstalled' -Version ($gv -replace '^git version\s+','') -Path $gitCmd.Source
    } else {
        if ($DiagnoseOnly) {
            Warn "git not found. Would install via winget."
            Set-Result -Tool 'git' -Status 'Skipped' -Notes "Would install Git via winget"
            return
        }
        Info "Installing Git via winget..."
        & winget install -e --id Git.Git --silent --accept-package-agreements --accept-source-agreements | Out-Host
        if ($LASTEXITCODE -ne 0) {
            Fail "winget install of Git failed (exit code $LASTEXITCODE)"
            Set-Result -Tool 'git' -Status 'Failed' -Notes "winget exit $LASTEXITCODE"
            return
        }
        Refresh-Path
        $gitCmd = Get-Command git -ErrorAction SilentlyContinue
        if ($gitCmd) {
            $gv = (& git --version 2>&1).Trim()
            OK "Git installed: $gv"
            Set-Result -Tool 'git' -Status 'Installed' -Version ($gv -replace '^git version\s+','') -Path $gitCmd.Source
        } else {
            Fail "Git install reported success but git not on PATH"
            Set-Result -Tool 'git' -Status 'Failed' -Notes "Post-install search failed"
            return
        }
    }

    # Configure user.name / user.email if missing
    if (-not $DiagnoseOnly) {
        $existingName  = (& git config --global user.name 2>$null)
        $existingEmail = (& git config --global user.email 2>$null)
        if ([string]::IsNullOrWhiteSpace($existingName) -or [string]::IsNullOrWhiteSpace($existingEmail)) {
            Info "Git needs your name and email for commits (one-time setup)."
            try {
                if ([string]::IsNullOrWhiteSpace($existingName)) {
                    $name = Read-Host "  Your full name (e.g. Jay Tan)"
                    if (-not [string]::IsNullOrWhiteSpace($name)) {
                        & git config --global user.name $name.Trim()
                        OK "git user.name set"
                    } else {
                        Warn "Skipped: no name entered. Run 'git config --global user.name \"Your Name\"' later."
                    }
                }
                if ([string]::IsNullOrWhiteSpace($existingEmail)) {
                    $email = Read-Host "  Your email (your gmail address)"
                    if (-not [string]::IsNullOrWhiteSpace($email)) {
                        & git config --global user.email $email.Trim()
                        OK "git user.email set"
                    } else {
                        Warn "Skipped: no email entered. Run 'git config --global user.email \"you@gmail.com\"' later."
                    }
                }
            } catch {
                Warn "Git config prompt was cancelled or failed: $($_.Exception.Message)"
                Info "You can set these later:"
                Info "  git config --global user.name \"Your Name\""
                Info "  git config --global user.email \"you@gmail.com\""
            }
        } else {
            OK "git user.name = $existingName"
            OK "git user.email = $existingEmail"
        }
    }
}

Install-Git

```

- [ ] **Step 2: Smoke-test on Windows**

Test on a machine with git already installed and configured:

```powershell
.\script\fix-vibecode.ps1 -DiagnoseOnly
```

Expected: `git version X.Y.Z`, then user.name and user.email printed.

Test on a machine where git is installed but user.email is missing (`git config --global --unset user.email`):

```powershell
.\script\fix-vibecode.ps1
```

Expected: prompted for email; after entering, `git config --global user.email` returns what you entered.

- [ ] **Step 3: Commit**

```bash
git add script/fix-vibecode.ps1
git commit -m "feat(script): install Git via winget and prompt for user.name/email"
```

---

### Task 10: Add GitHub CLI installer

**Files:**
- Modify: `script/fix-vibecode.ps1`

- [ ] **Step 1: Insert the gh section after Git, before Claude Code**

Right after `Install-Git` is called, before the `# ---------- Install Claude Code ----------` line, insert:

```powershell
# ---------- Find and install GitHub CLI ----------
Step "Checking GitHub CLI (gh)"
Refresh-Path

function Install-GitHubCLI {
    $ghCmd = Get-Command gh -ErrorAction SilentlyContinue
    if ($ghCmd) {
        try {
            $ghv = (& gh --version 2>&1 | Select-Object -First 1).Trim()
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
        Warn "gh not found. Would install via winget."
        Set-Result -Tool 'gh' -Status 'Skipped' -Notes "Would install GitHub CLI via winget"
        return
    }

    Info "Installing GitHub CLI via winget..."
    & winget install -e --id GitHub.cli --silent --accept-package-agreements --accept-source-agreements | Out-Host
    if ($LASTEXITCODE -ne 0) {
        Fail "winget install of gh failed (exit code $LASTEXITCODE)"
        Set-Result -Tool 'gh' -Status 'Failed' -Notes "winget exit $LASTEXITCODE"
        return
    }
    Refresh-Path
    $ghCmd = Get-Command gh -ErrorAction SilentlyContinue
    if ($ghCmd) {
        $ghv = (& gh --version 2>&1 | Select-Object -First 1).Trim()
        OK "GitHub CLI installed: $ghv"
        Set-Result -Tool 'gh' -Status 'Installed' -Version ($ghv -replace '^gh version\s+(\S+).*','$1') -Path $ghCmd.Source
    } else {
        Fail "gh install reported success but gh not on PATH"
        Set-Result -Tool 'gh' -Status 'Failed' -Notes "Post-install search failed"
    }
}

Install-GitHubCLI

```

- [ ] **Step 2: Smoke-test on Windows**

```powershell
.\script\fix-vibecode.ps1 -DiagnoseOnly
```

Expected: detects gh if installed; says "Would install" if not.

- [ ] **Step 3: Commit**

```bash
git add script/fix-vibecode.ps1
git commit -m "feat(script): install GitHub CLI via winget when missing"
```

---

### Task 11: Add Supabase CLI installer (via npm)

**Files:**
- Modify: `script/fix-vibecode.ps1`

- [ ] **Step 1: Insert the supabase section after gh**

Immediately after the `Install-GitHubCLI` call, insert:

```powershell
# ---------- Find and install Supabase CLI ----------
Step "Checking Supabase CLI"
Refresh-Path

function Install-SupabaseCLI {
    $sbCmd = Get-Command supabase -ErrorAction SilentlyContinue
    if ($sbCmd) {
        try {
            $sbv = (& supabase --version 2>&1).Trim()
            OK "supabase $sbv  ($($sbCmd.Source))"
            Set-Result -Tool 'supabase' -Status 'AlreadyInstalled' -Version $sbv -Path $sbCmd.Source
        } catch {
            Warn "supabase found but --version failed: $_"
            Set-Result -Tool 'supabase' -Status 'Failed' -Path $sbCmd.Source -Notes $_.Exception.Message
        }
        return
    }

    if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
        Warn "npm not available — cannot install Supabase CLI. Make sure Node was installed first."
        Set-Result -Tool 'supabase' -Status 'Failed' -Notes "npm not available"
        return
    }

    if ($DiagnoseOnly) {
        Warn "supabase not found. Would install via npm."
        Set-Result -Tool 'supabase' -Status 'Skipped' -Notes "Would install Supabase CLI via npm"
        return
    }

    Info "Installing Supabase CLI via npm install -g supabase..."
    & npm install -g supabase 2>&1 | Out-Host
    if ($LASTEXITCODE -ne 0) {
        Fail "npm install -g supabase failed (exit code $LASTEXITCODE)"
        Set-Result -Tool 'supabase' -Status 'Failed' -Notes "npm exit $LASTEXITCODE"
        return
    }
    Refresh-Path
    $sbCmd = Get-Command supabase -ErrorAction SilentlyContinue
    if ($sbCmd) {
        $sbv = (& supabase --version 2>&1).Trim()
        OK "Supabase CLI installed: $sbv"
        Set-Result -Tool 'supabase' -Status 'Installed' -Version $sbv -Path $sbCmd.Source
    } else {
        Fail "Supabase install reported success but supabase not on PATH"
        Set-Result -Tool 'supabase' -Status 'Failed' -Notes "Post-install search failed"
    }
}

Install-SupabaseCLI

```

- [ ] **Step 2: Smoke-test on Windows**

```powershell
.\script\fix-vibecode.ps1 -DiagnoseOnly
```

Expected: detects supabase if installed; reports "Would install" if not.

- [ ] **Step 3: Commit**

```bash
git add script/fix-vibecode.ps1
git commit -m "feat(script): install Supabase CLI via npm when missing"
```

---

### Task 12: Add Vercel CLI installer (via npm)

**Files:**
- Modify: `script/fix-vibecode.ps1`

- [ ] **Step 1: Insert the vercel section after supabase**

Immediately after the `Install-SupabaseCLI` call, insert:

```powershell
# ---------- Find and install Vercel CLI ----------
Step "Checking Vercel CLI"
Refresh-Path

function Install-VercelCLI {
    $vcCmd = Get-Command vercel -ErrorAction SilentlyContinue
    if ($vcCmd) {
        try {
            $vcv = (& vercel --version 2>&1).Trim()
            OK "vercel $vcv  ($($vcCmd.Source))"
            Set-Result -Tool 'vercel' -Status 'AlreadyInstalled' -Version $vcv -Path $vcCmd.Source
        } catch {
            Warn "vercel found but --version failed: $_"
            Set-Result -Tool 'vercel' -Status 'Failed' -Path $vcCmd.Source -Notes $_.Exception.Message
        }
        return
    }

    if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
        Warn "npm not available — cannot install Vercel CLI."
        Set-Result -Tool 'vercel' -Status 'Failed' -Notes "npm not available"
        return
    }

    if ($DiagnoseOnly) {
        Warn "vercel not found. Would install via npm."
        Set-Result -Tool 'vercel' -Status 'Skipped' -Notes "Would install Vercel CLI via npm"
        return
    }

    Info "Installing Vercel CLI via npm install -g vercel..."
    & npm install -g vercel 2>&1 | Out-Host
    if ($LASTEXITCODE -ne 0) {
        Fail "npm install -g vercel failed (exit code $LASTEXITCODE)"
        Set-Result -Tool 'vercel' -Status 'Failed' -Notes "npm exit $LASTEXITCODE"
        return
    }
    Refresh-Path
    $vcCmd = Get-Command vercel -ErrorAction SilentlyContinue
    if ($vcCmd) {
        $vcv = (& vercel --version 2>&1).Trim()
        OK "Vercel CLI installed: $vcv"
        Set-Result -Tool 'vercel' -Status 'Installed' -Version $vcv -Path $vcCmd.Source
    } else {
        Fail "Vercel install reported success but vercel not on PATH"
        Set-Result -Tool 'vercel' -Status 'Failed' -Notes "Post-install search failed"
    }
}

Install-VercelCLI

```

- [ ] **Step 2: Smoke-test on Windows**

```powershell
.\script\fix-vibecode.ps1 -DiagnoseOnly
```

Expected: detects vercel if installed; reports "Would install" if not.

- [ ] **Step 3: Commit**

```bash
git add script/fix-vibecode.ps1
git commit -m "feat(script): install Vercel CLI via npm when missing"
```

---

### Task 13: Wire existing Claude Code section into $script:results

**Files:**
- Modify: `script/fix-vibecode.ps1`

- [ ] **Step 1: Add Set-Result calls to the existing Claude Code section**

Find the existing `# ---------- Install Claude Code ----------` block. It already handles install attempts; we just need to record results.

Locate the line:

```powershell
        try {
            $cv = & claude --version 2>&1
            OK "Claude Code already installed: $cv  ($($existing.Source))"
        } catch {
            Warn "claude on PATH but doesn't run cleanly: $_"
        }
```

Replace with:

```powershell
        try {
            $cv = (& claude --version 2>&1).Trim()
            OK "Claude Code already installed: $cv  ($($existing.Source))"
            Set-Result -Tool 'claude' -Status 'AlreadyInstalled' -Version $cv -Path $existing.Source
        } catch {
            Warn "claude on PATH but doesn't run cleanly: $_"
            Set-Result -Tool 'claude' -Status 'Failed' -Path $existing.Source -Notes $_.Exception.Message
        }
```

Then find the block:

```powershell
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
```

Replace with:

```powershell
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
                    $cv = (& claude --version 2>&1).Trim()
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
```

Also add a Set-Result for the SkipClaudeCode case. Find:

```powershell
if (-not $SkipClaudeCode -and -not $DiagnoseOnly) {
```

The whole `if` block runs only when neither flag is set. If `$SkipClaudeCode` is true OR `$DiagnoseOnly` is true, no result is recorded. To fix, immediately AFTER the closing brace `}` of that whole `if` block, add:

```powershell
if (-not $script:results.Contains('claude')) {
    if ($SkipClaudeCode) {
        Set-Result -Tool 'claude' -Status 'Skipped' -Notes "Skipped via -SkipClaudeCode flag"
    } elseif ($DiagnoseOnly) {
        $existing = Get-Command claude -ErrorAction SilentlyContinue
        if ($existing) {
            try {
                $cv = (& claude --version 2>&1).Trim()
                Set-Result -Tool 'claude' -Status 'AlreadyInstalled' -Version $cv -Path $existing.Source
            } catch {
                Set-Result -Tool 'claude' -Status 'Failed' -Path $existing.Source -Notes "Found but --version failed"
            }
        } else {
            Set-Result -Tool 'claude' -Status 'Skipped' -Notes "Would install via native installer or npm"
        }
    }
}
```

- [ ] **Step 2: Smoke-test on Windows**

```powershell
.\script\fix-vibecode.ps1 -DiagnoseOnly
```

Expected: at the end, `$script:results['claude']` is populated (you can verify by adding a temporary `$script:results | Format-Table` at the bottom).

- [ ] **Step 3: Commit**

```bash
git add script/fix-vibecode.ps1
git commit -m "feat(script): wire Claude Code install into results tracking"
```

---

## Final report + login instructions

### Task 14: Replace existing "Final check" block with $results-driven table

**Files:**
- Modify: `script/fix-vibecode.ps1`

- [ ] **Step 1: Replace the existing final-check block**

Find the section starting with:

```powershell
# ---------- Final verification ----------
Step "Final check"
```

…and ending just before the closing summary block. Replace with:

```powershell
# ---------- Final verification (renders $script:results) ----------
Step "Final verification"
Refresh-Path

# Re-verify every tool with --version one more time (catches PATH drift edge cases)
$reverify = @{
    python   = 'python --version'
    node     = 'node --version'
    npm      = 'npm --version'
    git      = 'git --version'
    gh       = 'gh --version'
    supabase = 'supabase --version'
    vercel   = 'vercel --version'
}
if (-not $SkipClaudeCode) { $reverify['claude'] = 'claude --version' }

foreach ($tool in $reverify.Keys) {
    $cmd = Get-Command $tool -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.Source -notmatch '\\WindowsApps\\') {
        try {
            $v = (& $tool --version 2>&1 | Select-Object -First 1).Trim()
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
$allGreen = $true
foreach ($r in $script:results.Values) {
    $statusColor = switch ($r.Status) {
        'Installed'        { 'Green' }
        'AlreadyInstalled' { 'Green' }
        'PathFixed'        { 'Green' }
        'Skipped'          { 'Yellow' }
        'Failed'           { 'Red'; $allGreen = $false }
        default            { 'Gray' }
    }
    $verStr  = if ($r.Version) { $r.Version } else { '' }
    $pathStr = if ($r.Path)    { $r.Path }    else { '' }
    $line = "  {0,-11} {1,-19} {2,-23} {3}" -f $r.Tool, $r.Status, $verStr, $pathStr
    Write-Host $line -ForegroundColor $statusColor
    if ($r.Notes) {
        Write-Host "              note: $($r.Notes)" -ForegroundColor Gray
    }
}
```

(Uses `if ($x) { $x } else { '' }` instead of the PS 7+ `??` operator so this runs on Windows PowerShell 5.1, which is the default on Windows 10/11.)

- [ ] **Step 2: Smoke-test on Windows**

```powershell
.\script\fix-vibecode.ps1 -DiagnoseOnly
```

Expected: at the end, a clean table showing each tool, its status (Green/Yellow/Red), version, and path. Tools that weren't checked yet should still be `Failed: Not on PATH in this shell`.

- [ ] **Step 3: Commit**

```bash
git add script/fix-vibecode.ps1
git commit -m "feat(script): render final verification table from results hashtable"
```

---

### Task 15: Replace closing summary with 3-login-commands printout

**Files:**
- Modify: `script/fix-vibecode.ps1`

- [ ] **Step 1: Replace the closing summary block**

Find the block starting with:

```powershell
Write-Host ""
Say "=================================================================" Cyan
if ($DiagnoseOnly) {
```

…through the end of the file (just before any Stop-Transcript block you added in Task 4). Replace the entire summary block with:

```powershell
Write-Host ""
Say "=================================================================" Cyan
if ($DiagnoseOnly) {
    Say "  Diagnose-only finished. Re-run WITHOUT -DiagnoseOnly to apply fixes." Yellow
} elseif ($allGreen) {
    Say "  All tools are working in THIS PowerShell window." Green
    Write-Host ""
    Say "  Next steps - sign in to each CLI (run these in this same window):" White
    Say "      gh auth login" White
    Say "      supabase login" White
    Say "      vercel login" White
    Write-Host ""
    Say "  (Each will open a browser. Follow the prompts.)" Gray
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
}
Say "  PATH backups: $backupDir" Gray
Say "=================================================================" Cyan
Write-Host ""
```

- [ ] **Step 2: Smoke-test on Windows**

Run on a fully working machine:

```powershell
.\script\fix-vibecode.ps1
```

Expected: at the end, green "All tools working" message followed by the 3 login commands.

- [ ] **Step 3: Commit**

```bash
git add script/fix-vibecode.ps1
git commit -m "feat(script): print 3 login commands at end and tighten summary"
```

---

## Documentation

### Task 16: Write manual VM test checklist

**Files:**
- Create: `docs/MANUAL-VM-TEST.md`

- [ ] **Step 1: Create the file**

Create `docs/MANUAL-VM-TEST.md` with the following content:

```markdown
# Manual VM Test Checklist for fix-vibecode.ps1

Run these scenarios on a Windows 11 VM (or a spare laptop) before each workshop. The script is too side-effect-heavy to fully unit-test; this is the gating quality check.

## Setup

- Snapshot the VM in a "clean" state with: Windows 11, English locale, default updates, no dev tools installed.
- Have a second snapshot with Python 3.13, Node 22, no Git, no CLIs (mid-state).

## Scenario 1: Clean machine, full install

Restore clean snapshot.

1. Open PowerShell normally (NOT as admin)
2. Double-click `run-fixer.bat`
3. Click "Yes" on the UAC prompt
4. Wait for completion (5-10 min on slow connection)
5. **Expected:**
   - Final table shows 7 rows, all Green (Installed)
   - 3 login commands printed
   - PATH backups saved to `C:\Users\<user>\path-backups\`
   - Session log at `C:\Users\<user>\AppData\Local\Temp\fix-vibecode-*.log`

6. In the SAME PowerShell window opened by the .bat:
   ```
   python --version
   node --version
   npm --version
   git --version
   gh --version
   supabase --version
   vercel --version
   claude --version
   ```
   **Expected:** all succeed.

## Scenario 2: Re-run on already-fixed machine (idempotency)

Don't restore; just run the .bat again.

**Expected:**
- Final table shows all Green, mostly `AlreadyInstalled`
- No spurious "installing X" messages
- No new PATH entries duplicated (check User PATH in Environment Variables)

## Scenario 3: Old Python coexistence

Restore mid-state snapshot (Python 3.13 already installed).

1. Run the .bat
2. **Expected:**
   - Script detects Python 3.13, warns, installs 3.14 alongside
   - `python --version` returns `Python 3.14.x` (3.14 won PATH order)
   - Manually check User PATH: 3.14 folder appears BEFORE 3.13 folder

## Scenario 4: Diagnose mode

Restore clean snapshot. Open PowerShell as Administrator manually.

```powershell
cd <script-folder>
.\fix-vibecode.ps1 -DiagnoseOnly
```

**Expected:**
- Nothing is installed
- Table shows all `Skipped` (or `Failed: Not on PATH in this shell`)
- No PATH changes
- No transcript file created

## Scenario 5: Broken PATH

Restore clean snapshot. Then deliberately corrupt PATH:

```powershell
$broken = "C:\does-not-exist;C:\nope;C:\foo;;;C:\foo"
[Environment]::SetEnvironmentVariable("Path", $broken, "User")
```

Run the .bat.

**Expected:**
- Script reports "Cleaned User PATH: removed N broken, M duplicate"
- PATH backup saved before cleanup
- Final table all Green

## Scenario 6: No winget

Restore clean snapshot. Uninstall "App Installer" (Settings → Apps).

Run the .bat.

**Expected:**
- Fail "winget is not installed" with Microsoft Store link
- Script exits cleanly (no crash, exit code 2)
- No PATH modifications

## Scenario 7: No internet

Restore clean snapshot. Disconnect network.

Run the .bat.

**Expected:**
- Each `winget install` fails with a clear error
- Script continues to next tool
- Final table shows multiple Red `Failed: winget exit ...`
- Session log captures the errors

---

## Bug-report template

If a scenario fails, capture and share:
- Output of `winver`
- The session log from `%TEMP%\fix-vibecode-*.log`
- The PATH backup files from `%USERPROFILE%\path-backups\`
- Screenshot of the final table
```

- [ ] **Step 2: Commit**

```bash
git add docs/MANUAL-VM-TEST.md
git commit -m "docs: add manual VM test checklist for fix-vibecode.ps1"
```

---

### Task 17: Run all Pester tests one final time

**Files:** none (test execution only)

- [ ] **Step 1: Run the full Pester suite**

```powershell
Invoke-Pester tests/ -Output Detailed
```

Expected: 14 tests passed, 0 failed.

- [ ] **Step 2: If anything fails, fix the helper or the test and re-run until green**

(No commit needed for a green run; if a fix is required, commit it with `fix: ...`.)

---

## Done criteria

- All 14 Pester tests pass.
- All 7 manual VM scenarios documented in `docs/MANUAL-VM-TEST.md` have been executed at least once with the expected outcomes.
- A double-click of `run-fixer.bat` on a clean Windows 11 VM produces 7 green rows in the final table within ~10 minutes.
- `python --version`, `node --version`, `git --version`, `gh --version`, `supabase --version`, `vercel --version`, and `claude --version` all succeed in the same PowerShell window that ran the script.

Once these are true, tag a v1.0.0 release on GitHub and update `VIBE_CODING_WORKSHOP_GUIDE.md` to reference the release ZIP.
