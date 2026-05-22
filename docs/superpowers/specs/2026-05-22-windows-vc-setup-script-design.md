# Windows Vibe Coding Setup Script — Design

**Date:** 2026-05-22
**Status:** Draft (pending user approval)

## Problem

Windows students in the Vibe Coding workshop repeatedly hit "xxx is not recognized" errors after following the handbook installs for Python, Node.js, Git, and the CLIs (gh, supabase, vercel). Root causes seen in past workshops:

1. Python installer's "Add python.exe to PATH" checkbox missed
2. Microsoft Store stub at `WindowsApps\python.exe` shadowing real Python
3. Node MSI updates System PATH but already-open PowerShell windows don't see it
4. `setx` truncating PATH at 1024 chars and silently corrupting it
5. Broken or duplicate User PATH entries from years of dev tool cruft
6. Tools installed but in a folder that never got added to PATH
7. Students never installing some tools (Git config not set, CLIs missing)

Result: ~half the workshop morning lost to per-laptop troubleshooting.

## Goals

Produce a single, distributable Windows script that:

- **Diagnoses** the state of every required tool (doctor mode, read-only)
- **Installs** missing tools via winget / npm
- **Repairs** PATH wiring — adds missing folders, removes broken entries, deduplicates, avoids `setx`
- **Verifies** every tool works in the same shell session via `--version` checks
- **Backs up** PATH before changing anything (rollback safety)
- **Logs** the full session for remote debugging when the workshop instructor helps a student over WhatsApp

Success criterion: a fresh Windows laptop with nothing installed can run the script once and have all 7 tools (Python, Node, Git, gh, supabase, vercel, Claude Code) resolvable **in the same PowerShell session that ran the script**, with no manual intervention beyond UAC clicks and a name/email prompt for git config. Opening a fresh PowerShell window is not required — the script's `Refresh-Path` from registry handles that.

## Non-goals

- **Mac support** — handbook already covers Mac; pain is Windows-only
- **Account creation** — Claude Pro, GitHub, Supabase, Vercel signups stay manual (browser flows)
- **CLI logins** — `gh auth login` / `supabase login` / `vercel login` are printed as next steps but not executed. Browser auth is awkward to script and Step 10 of the handbook (Claude Code) already handles it well.
- **Old Windows** (Win 8.1, Win 10 pre-1809 without winget) — print clear "install App Installer" message and exit, do not bootstrap winget
- **Self-elevation inside the .ps1** — the .bat wrapper handles UAC; running .ps1 directly without admin will fail loud

## Architecture

Two files shipped together, distributed as a ZIP or via the workshop guide:

| File | Role |
|---|---|
| `run-fixer.bat` | Double-click entry point. Self-elevates via `Start-Process -Verb RunAs`, then launches the PowerShell script with `-ExecutionPolicy Bypass`. |
| `fix-vibecode.ps1` | All real logic. Idempotent. Runs as Administrator. Two modes via `-DiagnoseOnly` flag. |

### Delivery

Students download both files into a folder (e.g., from a GitHub release ZIP or a Google Drive link). The workshop guide replaces the long install Steps 3–5 + Step 10 with one instruction: "Download the fixer, double-click `run-fixer.bat`, click Yes on the UAC."

Versioning: pin releases to tagged GitHub URLs so the workshop guide URL stays stable.

### Modes

| Mode | Invocation | Behavior |
|---|---|---|
| **Doctor** | `.\fix-vibecode.ps1 -DiagnoseOnly` | Reports state of every tool. Never modifies PATH, never installs anything. Safe to run anytime. |
| **Fix** *(default)* | Double-click `.bat`, or `.\fix-vibecode.ps1` | Backs up PATH, cleans PATH, installs missing tools, repairs PATH, verifies. |

## Flow (Fix mode)

```
1.  Preflight
      - .bat checks admin via `net session`; re-launches via RunAs if not
      - .ps1 verifies winget is available; if not, print MS Store App Installer link and exit
      - Start session log via `Start-Transcript -Path "$env:TEMP\fix-vibecode-<timestamp>.log"`. End with `Stop-Transcript` in a `finally` block so logs flush even on script error.

2.  Backup
      - Write User PATH and Machine PATH to %USERPROFILE%\path-backups\
        - user-path-<timestamp>.txt
        - machine-path-<timestamp>.txt

3.  Clean PATH (User PATH only — Machine PATH is backed up but not modified, to avoid breaking Windows-managed entries)
      - Read User PATH
      - Remove empty entries, dedupe (case-insensitive)
      - For each entry: if it doesn't exist on disk AND has no env var refs (%FOO%), remove it
      - Warn if total length > 1024 chars
      - Write back via [Environment]::SetEnvironmentVariable (NEVER setx)

4.  For each tool **in this exact order** — Python, Node, Git, GitHub CLI, Supabase CLI, Vercel CLI, Claude Code:
      (Node must be installed before Supabase/Vercel/Claude-via-npm because those need `npm`.)

      a. Detect: Get-Command <tool>, filter out WindowsApps stubs. For Python specifically: enumerate ALL python.exe under common install roots and pick the highest 3.14+ version (don't rely on whichever is first on PATH).
      b. If not on PATH, search known install folders (LOCALAPPDATA, Program Files, etc.)
      c. If still missing:
           - Python:   winget install -e --id Python.Python.3.14 --silent --accept-package-agreements --accept-source-agreements
           - Node:     winget install -e --id OpenJS.NodeJS.LTS  --silent --accept-package-agreements --accept-source-agreements
           - Git:      winget install -e --id Git.Git            --silent --accept-package-agreements --accept-source-agreements
           - gh:       winget install -e --id GitHub.cli         --silent --accept-package-agreements --accept-source-agreements
           - supabase: npm install -g supabase   (requires Node already present; if `%APPDATA%\npm` doesn't exist, npm creates it on first -g install)
           - vercel:   npm install -g vercel     (same prerequisite)
           - claude:   try claude.ai/install.ps1 first; fall back to npm install -g @anthropic-ai/claude-code
      d. Refresh-Path from registry into current session
      e. Re-run `Get-Command <tool>`. If still not found, add the tool's bin folder to User PATH (Refresh-Path again afterward). Most winget installs add to PATH automatically; this step is a safety net for installers that don't.
      f. Run `<tool> --version`; record result for final report

5.  Version policy
      - Python: if installed version < 3.14, warn and install 3.14 alongside. Ensure the 3.14 folder is prepended to User PATH: filter `$newDir` out of `$existingEntries` first (avoid duplicates), then `Set-UserPath (@($newDir) + ($existingEntries | Where-Object { $_ -ne $newDir }))`. This guarantees 3.14 wins PATH lookup order even if older versions remain on PATH.
      - Node:   if installed version major < 18, warn and trigger LTS install
      - Others: accept any installed version

6.  Git config
      - If `git config --global user.name` empty: Read-Host "Your full name"
      - If `git config --global user.email` empty: Read-Host "Your email"
      - Set both via git config --global

7.  Final verification table
      - For each tool: run --version one more time after Refresh-Path
      - Print table with ✅/❌, version, resolved path
      - Print path to PATH backup folder and session log

8.  Next steps printout
      - The 3 login commands the student must run:
          gh auth login
          supabase login
          vercel login
      - Note: all tools should work in THIS same PowerShell window. If anything fails, the fallback is to open a fresh PowerShell — but Refresh-Path should have made that unnecessary.
```

## Relationship to existing files

The current repo already contains `script/fix-vibecode.ps1` and `script/run-fixer.bat` — a working PATH-repair script. **Implementation will extend the existing `.ps1`**, not rewrite it. The existing helpers (`Get-UserPath`, `Set-UserPath`, `Add-UserPathEntry`, `Refresh-Path`, output helpers, PATH backup, PATH cleaning, MS Store stub detection, Claude Code install) are kept as-is. New work adds: winget installers for Python/Node/Git/gh, npm installers for supabase/vercel, git config prompt, `Start-Transcript` logging, and the final 3-login-commands printout. The Python section is rewritten to handle the "install when missing" case (currently it only repairs PATH).

## Components

The .ps1 will be organized into these named sections. Existing inline blocks may be refactored into named functions where it improves readability, but the existing inline organization is fine to preserve where simpler.

| Section | Functions | Responsibility |
|---|---|---|
| Output helpers | `Say`, `Step`, `OK`, `Warn`, `Fail`, `Info` | Colored console output, also tee'd to session log |
| PATH helpers | `Get-UserPath`, `Set-UserPath`, `Add-UserPathEntry`, `Refresh-Path` | All PATH manipulation, never uses setx |
| Backup | (inline) | Snapshot User + Machine PATH to disk |
| PATH cleaning | (inline) | Remove broken/duplicate entries |
| Tool installers | One function per tool: `Install-Python`, `Install-Node`, etc. | Detect → search → winget/npm install → PATH fix → verify |
| Git config | (inline) | Prompt and set user.name/user.email if missing |
| Final verification | (inline) | Run --version for every tool, build report |

Each tool installer follows the same contract:
- **Input:** none (uses globals)
- **Output:** sets a script-scoped `$results[<tool>]` hashtable with:
  - `Status`: one of `Installed` (newly installed this run), `AlreadyInstalled` (already present, not modified), `PathFixed` (was installed but not on PATH; we added it), `Failed` (install attempt failed), `Skipped` (e.g. -DiagnoseOnly mode)
  - `Version`: string from `--version` output, or `null` if Failed
  - `Path`: resolved path to the tool, or `null` if Failed
  - `Notes`: optional human-readable detail (e.g. "side-by-side with Python 3.13")
- **Side effects:** may install software, modify User PATH

This keeps the final verification step a pure rendering of `$results` rather than re-discovering everything.

## Failure handling

| Scenario | Behavior |
|---|---|
| Not run as admin | `.bat` self-elevates; `.ps1` aborts with clear message if launched directly without admin |
| winget missing | Print MS Store "App Installer" link, exit cleanly with non-zero code |
| Individual `winget install` fails | Record in `$results`, continue with remaining tools (don't abort the run) |
| `npm install -g` fails | Same — record and continue |
| Network failure during install | Fail loud per-tool, suggest "check internet and re-run" |
| Old Python detected | Install 3.14 alongside, warn user about coexistence |
| Re-running the script | Idempotent: already-installed tools detected and skipped; PATH cleaning is idempotent |
| User cancels mid-run | PATH backup remains; can be restored manually from `%USERPROFILE%\path-backups\` |

## Verification (definition of done)

The script run is successful when, **in the same elevated PowerShell session that ran the script**:

```
python --version    → Python 3.14.x
node --version      → v24.x.x (or current LTS major)
npm --version       → 10.x.x or 11.x.x
git --version       → 2.5x.x
gh --version        → gh version 2.x.x
supabase --version  → 2.x.x or current
vercel --version    → 40.x.x or current major
claude --version    → recent version
git config --global user.name   → non-empty
git config --global user.email  → non-empty
```

The final printed table reflects this exactly.

## Risks & open questions

| Risk | Mitigation |
|---|---|
| `OpenJS.NodeJS.LTS` is a moving target; will become Node 26 in late 2026 and may diverge from handbook | Acceptable drift for now; revisit if handbook pins a major version |
| winget silent install of Node may include Tools for Native Modules (~1 GB the handbook tells students to skip) | Verify behavior before shipping; if it does include them, use `--override` with explicit MSI ADDLOCAL flags |
| Side-by-side Python installs (3.13 + 3.14) may confuse `python` lookup | Script ensures 3.14 appears first in User PATH; if persistent issues, fall back to fail-loud "uninstall old Python first" |
| `iwr | iex`-style one-liner not used (using download + .bat instead) | Trade-off: lower iteration speed for instructor, but better UX for students (double-click vs paste-into-PowerShell) |
| Workshop guide must be updated to reference the script | Out of scope for this design; tracked separately |
| Corporate proxy / geographic restrictions blocking winget servers (common in some regions in Asia) | Print clear "winget couldn't reach servers" message; fall back to manual install instructions per tool |
| `Read-Host` for git name/email may be Ctrl+C'd by student | Wrap in try/catch; if cancelled, skip git config step and warn at end (still print as a TODO for the student) |
| Doctor mode hard for non-technical students to invoke (no dedicated `.bat`) | v1: documented PowerShell invocation. v2 candidate: ship `run-doctor.bat` if instructors want it. |

## Testing strategy

Three layers:

1. **Pre-impl verification (one-time, in the plan):**
   - Confirm winget IDs resolve: `winget show Python.Python.3.14`, `winget show OpenJS.NodeJS.LTS`, `winget show Git.Git`, `winget show GitHub.cli` — fix the spec if any ID is wrong.
   - Confirm `claude.ai/install.ps1` still serves a valid PowerShell installer (the existing script depends on it).

2. **Unit tests for pure helpers** (PowerShell + Pester):
   - PATH parsing: empty entries, duplicates, broken paths, %ENV% references
   - Version comparison: "3.13" vs "3.14", "v22.x" vs "v18.x"
   - WindowsApps stub detection

3. **Manual end-to-end on Windows VM:**
   - Fresh Windows 11 VM, nothing installed → run script → all 7 tools verified.
   - Same VM, run again → idempotency (no spurious "installed" claims).
   - VM with broken/duplicate PATH entries seeded → clean and verify.
   - VM with Python 3.13 pre-installed → 3.14 installed alongside, wins lookup order.
   - VM with no winget (uninstall App Installer) → script prints clear error and exits.

   Run via the .bat double-click flow, not directly via PowerShell, to exercise the self-elevation path.

## Distribution

- Host source in a public GitHub repo (specific URL TBD by maintainer; placeholder `github.com/<owner>/windows-vc-script`)
- Tag releases with semver (`v1.0.0`, `v1.0.1`, etc.)
- Workshop guide links to a stable release ZIP URL, not `main`
- Optional: GitHub Release page describes what each version does, in plain language for students

## Future work (out of scope for v1)

- Mac variant
- `iwr | iex` one-liner alternative (for advanced students)
- Automated CLI logins
- Uninstall / cleanup mode
- Per-tool repair commands (`fix-vibecode.ps1 repair python`)
