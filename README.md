# Vibe Coding Workshop — Setup Scripts

One-click installers that get a student's laptop ready for class. Installs **Python 3.14, Node.js, Git, GitHub CLI, Supabase CLI, Vercel CLI, and Claude Code.**

For workshop **assistants**. Student-facing prep guide: [VIBE_CODING_WORKSHOP_GUIDE.md](VIBE_CODING_WORKSHOP_GUIDE.md).

---

## TL;DR

| OS | Student does this |
|---|---|
| **Windows** | Right-click `script/run-fixer.bat` → **Run as administrator** → click Yes on UAC |
| **macOS** | Double-click `script/run-fixer.command` |

Takes 5–10 min. Final table should be all green. Then run the 5 commands the script prints (3 logins, 2 git configs). Close window. Done.

---

## Assistant prep (do once, before workshop day)

- **Test on a real laptop** of each OS you'll see. Don't trust "it worked on mine".
- **Tell students to tether to their phone hotspot** for the install. Switch back to venue Wi-Fi only after the final table is all green. Venue Wi-Fi gets overwhelmed when 30 laptops download Homebrew/npm at once.
- **Silent for >10 min = stuck.** Ctrl+C, check the log, re-run. <3 min = patience, it's downloading something big.

---

## How students get the files

**Do not say `git clone`** — they don't have git yet and won't know terminal commands.

1. Open <https://github.com/bigai-dev/windows-vc-script> in their browser
2. Green **"Code"** button → **"Download ZIP"**
3. Find `windows-vc-script-main.zip` in Downloads
4. **Windows:** right-click → **Extract All**. **macOS:** double-click.
5. Open the unzipped folder → open the `script` subfolder
6. Double-click the launcher (`run-fixer.bat` on Windows, `run-fixer.command` on macOS)

---

## Windows specifics

`run-fixer.bat` handles **both** UAC elevation **and** the PowerShell execution-policy bypass — students never type a command.

**No UAC popup?** Their account isn't an admin. Need IT help.

**Fallback (assistant or RDP):** open PowerShell as admin, run:
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\path\to\script\fix-vibecode.ps1"
```

Flags: `-DiagnoseOnly` (check only, no install), `-SkipClaudeCode`.

---

## macOS specifics

**Gatekeeper blocks `.command`?** Send them to:
- Ventura (13)+: **System Settings** → **Privacy & Security** → scroll down → **Open Anyway**
- Monterey (12): **System Preferences** → **Security & Privacy** → **General** → **Open Anyway**

**Double-click opens it in a text editor?** Run in Terminal: `chmod +x ` then drag `run-fixer.command` onto the Terminal window → Enter.

**Xcode Command Line Tools** prompts a GUI installer the first time — 5–15 min typical, longer on slow Wi-Fi. After it finishes, re-run the script.

**Homebrew install** asks for the student's macOS login password once. Cursor doesn't move while typing — normal.

Flags: `--diagnose-only`, `--skip-claude-code`.

---

## After the script — the 5 commands

```
gh auth login          # pick GitHub.com → HTTPS → Login with web browser, paste 8-char code
supabase login         # opens browser, click Authorize
vercel login           # opens browser, pick GitHub auth
git config --global user.name  "Their Name"
git config --global user.email "their.email@gmail.com"
```

Smoke test (paste in same window — all 8 must print a version):

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

On macOS, use `python3 --version` for the first line.

---

## Final table — what to look for

| Status | Color | Means |
|---|---|---|
| `Installed` / `AlreadyInstalled` / `PathFixed` | green | Good |
| `Skipped` | yellow | Diagnose mode or `--skip-claude-code` |
| `Failed` | red | Read the `note:` line under the row |

---

## Top issues

| Symptom | Fix |
|---|---|
| Smoke test says "command not found" | Close window, open a fresh one. PATH didn't refresh. |
| Red row for `claude` | Claude Code needs Node 18+. Re-run from a fresh shell. |
| Red row for `supabase` / `vercel` after npm "succeeded" | Same — fresh shell, re-run. |
| Windows: garbled chars (`σ┐█µë┘`) | Old bug, already fixed. Re-pull the latest scripts. |
| macOS: "no formula python@3.14" | `brew update` then re-run. |
| Either OS: corporate firewall blocking installs | Switch to phone hotspot, re-run. |
| Anything else weird | Close everything, fresh window, re-run. Scripts are safe to re-run. |

**Logs:**
- Windows: `%TEMP%\fix-vibecode-*.log` (paste in File Explorer address bar)
- macOS: `/tmp/fix-vibecode-*.log` (run `open /tmp` in Terminal)

**PATH backups** (in case something gets mangled):
- Windows: `%USERPROFILE%\path-backups\`
- macOS: `~/dotfile-backups/`

---

## Manual fallback

If the script genuinely can't run, install each tool from its official site, then run the smoke test. Order matters — Node before npm-installed tools.

| Tool | Where |
|---|---|
| Python 3.14 | <https://www.python.org/downloads/> (Windows: tick "Add to PATH") |
| Node.js LTS | <https://nodejs.org/en/download> |
| Git | <https://git-scm.com/downloads> |
| GitHub CLI | <https://cli.github.com/> |
| Supabase | macOS: `brew install supabase/tap/supabase`. Windows: `npm install -g supabase` |
| Vercel | `npm install -g vercel` |
| Claude Code | `npm install -g @anthropic-ai/claude-code` |

---

## Before each cohort

Run [docs/MANUAL-VM-TEST.md](docs/MANUAL-VM-TEST.md) on a clean VM. ~30 min, has caught real bugs.

**Reporting bugs:** open an issue at <https://github.com/bigai-dev/windows-vc-script/issues> with the session log, a screenshot of the final table, and the OS version.
