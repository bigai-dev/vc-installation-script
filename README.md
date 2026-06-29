# Vibe Coding Workshop — Setup Scripts

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
| `Failed` | read the `note:` line under the row |

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
- Scripts are **safe to re-run** anytime.

</details>

<details>
<summary><b>When it breaks</b> — quick fixes + where the logs are</summary>

<br>

| Symptom | Fix |
|---|---|
| "command not found" in smoke test | Close the window, open a fresh one. |
| Red `claude` / `supabase` / `vercel` | Fresh window, re-run. |
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

**Still missing after a fresh window?** Add the folder by hand, then open a new window:

_Windows — PowerShell (swap in the real folder if it's somewhere else):_
```powershell
[Environment]::SetEnvironmentVariable("Path", $env:Path + ";C:\Path\To\Tool", "User")
```

_macOS — Terminal (this is the usual Homebrew location):_
```bash
echo 'export PATH="/opt/homebrew/bin:$PATH"' >> ~/.zshrc && source ~/.zshrc
```

</details>

<details>
<summary><b>Options &amp; fallbacks</b> — diagnose mode, manual run</summary>

<br>

**Check only, no install:** macOS — add `-- --diagnose-only` to the end of the one-liner. Windows — `-DiagnoseOnly`. (Skip Claude Code: `--skip-claude-code` / `-SkipClaudeCode`.)

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
```
```powershell
npm i -g supabase vercel @anthropic-ai/claude-code
```
> If the Python line can't find `3.14`, change it to `3.13` and run that one line again.

_macOS — Terminal. Block 1 installs Homebrew + the base tools, block 2 finishes:_
```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
brew install python@3.14 node git gh supabase/tap/supabase
```
```bash
npm i -g vercel @anthropic-ai/claude-code
```

If antivirus also blocks the `npm i -g` line, tell it to **Allow** once (or pause protection for 10 min), then re-run that line.

**Method 2 — download the installers yourself** (install Node before the npm tools)

| Tool | Where |
|---|---|
| Python 3.14 | <https://www.python.org/downloads/> (Windows: tick "Add to PATH") |
| Node.js LTS | <https://nodejs.org/en/download> |
| Git | <https://git-scm.com/downloads> |
| GitHub CLI | <https://cli.github.com/> |
| Supabase | macOS `brew install supabase/tap/supabase` · Windows `npm i -g supabase` |
| Vercel | `npm i -g vercel` |
| Claude Code | `npm i -g @anthropic-ai/claude-code` |

Sign in with the commands under **Done = all green** above.

</details>

<details>
<summary><b>Before each cohort</b> — clean-VM test</summary>

<br>

Run [docs/MANUAL-VM-TEST.md](docs/MANUAL-VM-TEST.md) on a clean VM (~30 min — has caught real bugs). Found a bug? [Open an issue](https://github.com/bigai-dev/vc-installation-script/issues) with the log, a screenshot of the final table, and the OS version.

</details>
