# Vibe Coding Workshop — Setup Scripts

[![Setup scripts tested on Windows and Mac](https://github.com/bigai-dev/vc-installation-script/actions/workflows/test-setup-scripts.yml/badge.svg)](https://github.com/bigai-dev/vc-installation-script/actions/workflows/test-setup-scripts.yml)

For workshop **assistants.** One script installs everything a student needs:
**Python 3.14 · Node.js · Git · GitHub CLI · Supabase CLI · Vercel CLI · Claude Code.**

Student prep guide → [VIBE_CODING_WORKSHOP_GUIDE.md](VIBE_CODING_WORKSHOP_GUIDE.md)

---

## Run it

**macOS** — open Terminal (Cmd+Space → type `Terminal` → Enter), paste this one line, press Enter:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/bigai-dev/vc-installation-script/main/script/fix-vibecode-mac.sh)"
```

**Windows** — on GitHub, green **Code** button → **Download ZIP** → **Extract All**. Open the `script` folder, right-click `run-fixer.bat` → **Run as administrator** → **Yes**.

Takes 5–10 min. When the final table is all green, the student runs the 5 commands it prints, then closes the window.

---

<details>
<summary><b>Done = all green</b> — what the table means + sign-in steps</summary>

<br>

| Row says | Means |
|---|---|
| `Installed` / `AlreadyInstalled` / `PathFixed` | good |
| `Skipped` | diagnose mode or skipped Claude Code |
| `Failed` | read the `note:` line under the row, and any `Fix:` lines printed just above the table |

Then the student signs in and sets their name:

```
gh auth login          # GitHub.com → HTTPS → web browser, paste the code
supabase login         # browser → Authorize
vercel login           # browser → GitHub
git config --global user.name  "Their Name"
git config --global user.email "their.email@gmail.com"
```

Smoke test — every line must print a version (paste in the same window):

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

macOS: use `python3 --version` for the first line.

</details>

<details>
<summary><b>On the day</b> — Wi-Fi, timing, and what's normal</summary>

<br>

- **Use a phone hotspot,** not venue Wi-Fi. 30 laptops downloading at once kills venue Wi-Fi. Switch back once the table is green.
- **Silent for >10 min = stuck** → Ctrl+C, re-run. Under 3 min = it's just downloading, wait.
- **Mac, first run:** an Xcode installer may pop up (5–15 min) and Homebrew asks for the Mac password once — both normal. The cursor won't move while typing the password.
- **Intel Macs, or Macs on macOS 13–14:** the script skips Homebrew (it no longer has ready-made packages for them) and downloads each tool directly from its official site — it says so near the top. It asks for the Mac password once, to install Python. Normal; takes about 5–10 min.
- **Macs older than macOS 13.5:** the script stops at the start with a plain message. A free Software Update fixes it if one is offered; if not, that laptop is too old for the workshop tools.
- Scripts are **safe to re-run** anytime.

</details>

<details>
<summary><b>When it breaks</b> — quick fixes + where the logs are</summary>

<br>

| Symptom | Fix |
|---|---|
| "command not found" in smoke test | Close the window, open a fresh one. |
| Red row with a `Fix:` line printed above the table | Do what the `Fix:` line says, then re-run. |
| Red `node`: "Still v20…" (or another old version) | An older Node is in the way. Windows: Settings → Apps → uninstall **Node.js**, then re-run. Mac: ask the lead assistant. |
| Mac: red `git` — "doesn't run" | Apple's developer tools broke (common after a macOS update). Run `xcode-select --install`, let it finish, re-run. |
| Red `claude` / `supabase` / `vercel` | Fresh window, re-run. |
| Mac: "This Mac runs macOS … need macOS 13.5 or newer" | System Settings → General → Software Update, install what's offered, re-run. If nothing newer is offered, the laptop is too old — borrow one. |
| Mac: blocked / "unidentified developer" | Use the one-line method above — it never gets blocked. |
| Mac: "no formula python@3.14" | `brew update`, then re-run. |
| Windows: no admin popup | Their account isn't an admin — needs IT. |
| Anything else | Close everything, open a fresh window, re-run. |

**Logs:** Windows `%TEMP%\fix-vibecode-*.log` · macOS `/tmp/fix-vibecode-*.log`
**PATH backups:** Windows `%USERPROFILE%\path-backups\` · macOS `~/dotfile-backups/`

</details>

<details>
<summary><b>"command not found" even after it installed</b> — what PATH does + manual fix</summary>

<br>

**Plain version:** PATH is the list of folders the computer searches when you type a command. A tool can install perfectly but not be on that list yet — so the terminal says "command not found." The script fixes this for you, but the change only kicks in in a **brand-new** window.

**The fix 9 times out of 10:** close the terminal completely, open a fresh one, run the smoke test again.

**What the script does automatically:**

- Finds where each tool actually landed and adds that folder to your PATH.
- On Windows it edits PATH the safe way — never `setx`, which silently corrupts a long PATH.
- Skips folders that don't exist and removes duplicate entries.
- Backs up your PATH first, so it's always reversible (locations above).

**Still missing after a fresh window?** Two hands-off options:

**Easiest — re-run the script.** It finds every tool, fixes PATH, and backs it up first. Nothing to type.

**Or paste this one block** — it finds all the tool folders for you, adds the missing ones to PATH (yours only, no duplicates), and tells you what it added. Then close the window and open a fresh one.

_Windows — PowerShell (this is one single line — paste it and press Enter):_
```powershell
$add=@(); $py=(Get-ChildItem "$env:LOCALAPPDATA\Programs\Python\Python31*","C:\Python31*","C:\Program Files\Python31*" -Directory -EA 0 | Sort-Object Name | Select-Object -Last 1).FullName; if ($py) { $add += $py, "$py\Scripts" }; $add += "C:\Program Files\nodejs","C:\Program Files\Git\cmd","C:\Program Files\GitHub CLI","$env:APPDATA\npm","$env:LOCALAPPDATA\Microsoft\WinGet\Links","$env:USERPROFILE\.local\bin"; $u=[Environment]::GetEnvironmentVariable("Path","User"); foreach ($f in $add) { if ((Test-Path $f) -and (($u -split ';') -notcontains $f)) { $u="$u;$f"; Write-Host "Added: $f" } }; [Environment]::SetEnvironmentVariable("Path",$u,"User"); Write-Host "Done - close this window and open a fresh one."
```

_macOS — Terminal:_
```bash
for d in /usr/local/bin /opt/homebrew/bin /Library/Frameworks/Python.framework/Versions/3.14/bin /opt/homebrew/opt/python@3.14/libexec/bin "$HOME/.npm-global/bin" "$HOME/.local/bin"; do
  [ -d "$d" ] && ! grep -qF "export PATH=\"$d:\$PATH\"" ~/.zshrc && echo "export PATH=\"$d:\$PATH\"" >> ~/.zshrc && echo "Added: $d"
done
source ~/.zshrc
echo "Done - close this window and open a fresh one."
```

</details>

<details>
<summary><b>Options &amp; fallbacks</b> — diagnose mode, manual run</summary>

<br>

**Check only, no install:** macOS — add `-- --diagnose-only` to the end of the one-liner. Windows — `-DiagnoseOnly`. (Skip Claude Code: `--skip-claude-code` / `-SkipClaudeCode`.)

**Mac, never use Homebrew:** add `-- --no-homebrew` to the end of the one-liner — every missing tool is downloaded directly from its official site instead. This already happens automatically on Intel Macs and macOS 13–14.

**Mac, prefer double-click:** double-click `script/run-fixer.command`. First time macOS blocks it → **System Settings → Privacy & Security →** scroll down → **Open Anyway** (Monterey: **System Preferences → Security & Privacy → General**). Once per Mac.

**Windows manual run:** PowerShell as admin →
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\path\to\script\fix-vibecode.ps1"
```

</details>

<details>
<summary><b>Script won't run / antivirus deleted it</b> — install everything by hand</summary>

<br>

Two ways to put the 7 tools on a machine without the script. **Try the paste method first** — there's no file on disk for antivirus to quarantine.

**Method 1 — paste the commands** (dodges antivirus)

_Windows — PowerShell as administrator. Run block 1, then **close the window and open a fresh one**, then run block 2:_
```powershell
winget install -e --id Python.Python.3.14
winget install -e --id OpenJS.NodeJS.LTS
winget install -e --id Git.Git
winget install -e --id GitHub.cli
winget install -e --id Anthropic.ClaudeCode
```
```powershell
npm i -g supabase vercel
```
> If a winget line says no package was found, run `winget source update`, then run that line again.

_macOS — Terminal. Block 1 installs Homebrew + the base tools, block 2 finishes. Then close Terminal and open a new one:_
```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
[ -x /opt/homebrew/bin/brew ] && echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile && eval "$(/opt/homebrew/bin/brew shellenv)"
brew install python@3.14 node git gh supabase/tap/supabase
```
```bash
npm i -g vercel
curl -fsSL https://claude.ai/install.sh | bash
echo 'export PATH="$HOME/.local/bin:/opt/homebrew/opt/python@3.14/libexec/bin:$PATH"' >> ~/.zshrc
```
> The last line makes `claude` and `python3` (3.14, not Apple's old 3.9) work in new windows.

If antivirus also blocks the `npm i -g` line, tell it to **Allow** once (or pause protection for 10 min), then re-run that line.

**Method 2 — download the installers yourself** (install Node before the npm tools)

| Tool | Where |
|---|---|
| Python 3.14 or newer | <https://www.python.org/downloads/> (Windows: tick "Add to PATH") |
| Node.js LTS | <https://nodejs.org/en/download> |
| Git | <https://git-scm.com/downloads> |
| GitHub CLI | <https://cli.github.com/> |
| Supabase | macOS `brew install supabase/tap/supabase` · Windows `npm i -g supabase` |
| Vercel | `npm i -g vercel` |
| Claude Code | macOS `curl -fsSL https://claude.ai/install.sh \| bash` · Windows `winget install Anthropic.ClaudeCode` |

Sign in with the commands under **Done = all green** above.

</details>

<details>
<summary><b>Before each cohort</b> — automatic cloud test + clean-VM test</summary>

<br>

**Automatic (no Windows device needed):** every change to the scripts is run for real on GitHub's free cloud computers — Windows Server 2025, Windows 11 (ARM), Apple-chip Macs on macOS 15 and 26 (the Homebrew route), plus an Intel Mac and a macOS 14 Mac with their tools removed first (the older-Mac direct-download route). It also runs every Monday, to catch outside changes (like a new Python or Node release) early. The badge at the top of this page shows the latest result; a green tick means every tool installed and worked in a fresh window. To run it on demand: **Actions** tab → **Test setup scripts** → **Run workflow**.

**By hand:** run [docs/MANUAL-VM-TEST.md](docs/MANUAL-VM-TEST.md) on a clean VM (~30 min — has caught real bugs). Found a bug? [Open an issue](https://github.com/bigai-dev/vc-installation-script/issues) with the log, a screenshot of the final table, and the OS version.

</details>

---

**VIBE CODING ACADEMY — OFFICIAL SETUP**  
© 2026 Vibe Coding Academy. All Rights Reserved.  
For authorised Vibe Coding Academy participants only.  
Unauthorised redistribution, resale, rebranding, reproduction,  
or use in third-party training is prohibited.  
Origin ID: VCA-2026-09-A7F3C8
