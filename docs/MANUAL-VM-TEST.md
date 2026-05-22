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
