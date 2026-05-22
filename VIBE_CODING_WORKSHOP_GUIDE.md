# Vibe Coding Workshop — Preparation Guide

Welcome! Finish every step below **before** workshop day. Don't wait until the morning of — install problems can take hours to fix.

Steps marked **★ Must have** are the absolute baseline to attend. The rest are still required.

---

## Step 1 — Gmail Account

You'll need a Gmail account to sign up for the workshop tools: Claude AI, GitHub, Supabase, and Vercel.

**What to do**
1. Go to Google's signup page: <https://accounts.google.com/signup>
2. Make a new account. You can also use an old one if it sounds professional.
3. Is your current email something like `cuteprincess88@gmail.com` or `xX_darkkiller_Xx@gmail.com`? Please make a new one. This email will stay with your developer accounts for years.

**Verify:** Can you log into Gmail?

**Tip:** Pick something like `firstname.lastname@gmail.com`. Clean, professional, and easy to remember.

---

## Step 2 — Claude Pro + Desktop App ★ Must have

Claude is our main AI coding helper, made by Anthropic. You need two things: a paid plan — **Pro ($20/month USD)** or higher (Max) — and the **Claude desktop app**. The free plan runs out too fast for the workshop. Pro is enough for most students; pick Max only if you want a lot more usage. We'll run Claude Code from inside the desktop app during class.

### A. New sign up
1. Go to Claude: <https://claude.ai>
2. Click **"Sign up"**.
3. Click **"Continue with Google"** and pick your Gmail from Step 1. That's the easiest way. You can also type your Gmail address and use the login link Claude sends you.
4. Type your **name** and what you want Claude to call you.
5. Read and **accept** the Terms of Service, Usage Policy, and Privacy Policy.
6. Confirm you're **18 or older** when asked.
7. If Claude asks for your phone number, type your Malaysian number (like `+60 12 345 6789`). You'll get an SMS code to enter. This only happens in some places.
   - **SMS arrived?** Enter the 6-digit code and continue.
   - **SMS never came, or verification keeps failing?** Sign up through the **Claude mobile app** instead — download it from the **App Store** (iPhone) or **Google Play** (Android), create your account there, then come back to `claude.ai` on your computer and sign in with the same account.
8. After signing up, you'll reach the **"Plans that grow with you"** page in one of two ways:
   - **The plans page opens by itself** (three cards: Max, Pro, Free). You're already there. Skip to the next step.
   - **Claude opens the chat page instead.** Click your **initials or name** in the **lower-left corner** of the sidebar. Then pick **Settings → Billing → Upgrade plan**. This opens the same plans page.
9. On the plans page, pick **Pro** (recommended, $20/month USD) or **Max** if you want more usage. Click **"Get Pro plan"** or **"Get Max plan"**.
10. At the top of the card, pick **Monthly** or **Yearly** (cheaper if you stay longer).
11. Type in your **credit or debit card** details. Most Malaysian cards work. Click to confirm.
12. Look for the **"Pro"** or **"Max"** badge next to your name. Refresh if you don't see it.
13. Now install the **Claude desktop app**: <https://claude.ai/download>
14. On the downloads page, click the button for **your operating system** and run the installer:
    - **Mac:** open the `.dmg` file you downloaded. Drag **Claude** into the **Applications** folder. Then eject the disk image.
    - **Windows:** open the `.exe` file you downloaded and follow the steps.
15. Open the **Claude** app and sign in with the **same account** you upgraded. You should see your name and the **Pro** (or **Max**) badge in the app.

### B. Already have an account
1. Go to <https://claude.ai> and click **"Log in"**.
2. Click your **initials or name** in the **lower-left corner** of the sidebar.
3. Pick **Settings → Billing → Upgrade plan**.
4. Click **"Get Pro plan"** (recommended) or **"Get Max plan"**.
5. Pick **Monthly** or **Annual** (saves money long-term). Pro is $20/month USD; Max is more.
6. Type in your **credit or debit card** details. Most Malaysian cards work. Click to confirm.
7. Look for the **"Pro"** or **"Max"** badge next to your name.
8. Install the **Claude desktop app**: <https://claude.ai/download> (same install steps as above).
9. Sign in to the app with the **same account** you upgraded.

**Verify:** Can you see the 'Pro' or 'Max' badge inside the Claude desktop app?

> ⚠️ **Warning:** The free plan will NOT be enough for the workshop. You need an active **Pro or Max** plan before class.

**Tips**
- **Pro is $20/month USD**. Max costs more — pick it only if you want a lot more usage. Both take credit and debit cards, including Malaysian ones.
- **Cancel anytime** from Settings → Billing. Takes 10 seconds.
- Unlocks **Opus 4.7**, the most powerful Claude model.
- About **5× more usage** than free, plus Claude Code for AI coding.

---

## Step 3 — Install Python ★ Must have

Python runs backend scripts and tools. The newest version is **Python 3.14**.

### Windows
1. Go to the Python downloads page: <https://www.python.org/downloads/>
2. In the **Windows** section, **ignore** the "Download Python install manager" button. Right below it, click the link **"Or get the standalone installer for Python 3.14.x"**. This downloads the `.exe` file right away.
3. Open the `.exe` file from your Downloads folder.
4. **Important: tick the "Add python.exe to PATH" checkbox** at the bottom of the installer window. If you skip this, Python won't work in PowerShell.
5. The big main button says one of two things:
   - **"Install Now"** — first-time install
   - **"Upgrade Now"** — you already have Python 3.14
6. **Click whichever one you see.**
7. If Windows asks "Do you want to allow this app to make changes?", click **Yes**.
8. Wait for the progress bar. When you see **"Setup was successful"**, click **Close**.

### Mac
1. Download Python for Mac: <https://www.python.org/downloads/macos/>
2. Click the **"Download Python 3.14.x"** button at the top of the page.
3. Open the `.pkg` file from your Downloads folder.
4. Click **Continue → Continue → Agree → Install**.
5. Type your Mac password when it asks. Wait for the install to finish.
6. Click **Close** when you see "The installation was successful".
7. **One more step.** Open **Finder**, go to **Applications → Python 3.14**, and double-click **Install Certificates.command**. A Terminal window opens for a moment and says "Process completed". Close it.

### Verify
Open your terminal:
- **Windows:** Press **Windows Key + R**, type `powershell`, press **Enter**.
- **Mac:** Press **Cmd + Space**, type `terminal`, press **Enter**.

**First-time PowerShell setup (Windows only).** Run this once to allow scripts. Type `Y` and press Enter when asked:
```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

Then run:
- **Windows:** `python --version`
- **Mac:** `python3 --version`

**Expected output:** `Python 3.14.x`

### Troubleshooting

**Windows — 'python' is not recognized**
- *Close PowerShell and open a brand new window.* PATH changes only reach new windows. Fixes about half of all 'not recognized' errors.
- *Re-run the installer with the PATH checkbox ticked.* Open the `.exe` again, tick "Add python.exe to PATH" at the bottom, click Modify (or Install).
- *Restart your computer.* Forces every program to pick up the new PATH.

**Mac — 'python3: command not found'**
- *Quit Terminal and open a new window.* Cmd + Q, reopen from Spotlight.
- *Make sure you typed `python3`, with the 3.* Plain `python` either points to nothing or to old Python 2.
- *Reinstall Python.* Download the `.pkg` from python.org/downloads/macos and run again.

---

## Step 4 — Install Node.js ★ Must have

Node.js runs JavaScript tools and frameworks. We need the **LTS (Long Term Support)** version, which is **Node.js 24**.

### Windows
1. Go to <https://nodejs.org> and click **"Get Node.js®"**.
2. The download page opens. **Skip the top section** (commands like `nvm install 24` — that's for advanced users).
3. **Scroll down** until you see: *"Or get a prebuilt Node.js® for Windows running a x64 architecture."*
4. Click the **"Windows Installer (.msi)"** button.
5. **Not sure if your PC is x64 or ARM64?** The default (x64) works for almost everyone. To check: press **Windows Key + Pause/Break** (or open **Settings → System → About**). Look at **"System type"**.
6. Open the `.msi` file.
7. Click **Next** through each screen: Welcome → License (check **"I accept"**) → Destination → Custom Setup (keep all defaults).
8. ⚠️ At the **"Tools for Native Modules"** screen, **LEAVE the checkbox UNCHECKED** and click Next. (Saves ~1 GB; we don't need it.)
9. Click **Install**. If Windows asks for permission, click **Yes**.
10. Click **Finish**.
11. **Close any open PowerShell windows and open a new one.** PATH only updates in brand-new windows.

### Mac
1. Go to <https://nodejs.org> and click **"Get Node.js®"**.
2. **Skip the top section** (`curl ... nvm.sh | bash` or `brew install node`).
3. **Scroll down** until you see: *"Or get a prebuilt Node.js® for macOS running a x64 architecture."* (or arm64 on Apple Silicon).
4. Click the **"macOS Installer (.pkg)"** button.
5. **Not sure if your Mac is arm64 or x64?** Click **Apple menu → About This Mac**. Look at **"Chip"**: Apple M1/M2/M3/M4 → arm64. Intel Core → x64.
6. Open the `.pkg` file.
7. Click **Continue → Continue → Agree → Install**.
8. Type your Mac password. Wait for the install to finish.
9. Click **Close**.
10. **Close any open Terminal windows (Cmd + Q) and open a new one.**

### Verify
Open a **NEW** terminal window and run **both**:

| OS | Command 1 | Expected | Command 2 | Expected |
|----|-----------|----------|-----------|----------|
| Windows | `node -v` | `v24.x.x` | `npm -v` | `11.x.x` |
| Mac | `node -v` | `v24.x.x` | `npm -v` | `11.x.x` |

### Troubleshooting

**Windows — 'node' or 'npm' is not recognized**
- *Close PowerShell and open a brand new window.*
- *Add Node.js to PATH with a command.* Paste into PowerShell:
  ```powershell
  [Environment]::SetEnvironmentVariable("Path", [Environment]::GetEnvironmentVariable("Path", "User") + ";C:\Program Files\nodejs", "User")
  ```
  Then close PowerShell, open a new one, and try again.
- *Reinstall Node.js* from nodejs.org. Make sure "Add to PATH" is on in the Custom Setup screen.
- *Restart your computer.*

**Mac — 'node' or 'npm' command not found**
- *Quit Terminal and open a new window.*
- *Update your PATH:*
  - Run `echo $SHELL`
  - If it says `/bin/zsh`, run: `echo 'export PATH="/usr/local/bin:$PATH"' >> ~/.zshrc`
  - Then run: `source ~/.zshrc`
  - If it says `/bin/bash`, use `~/.bash_profile` instead of `~/.zshrc`
- *Reinstall Node.js* from nodejs.org.

---

## Step 5 — Install Git

Git tracks changes in your code and sends it to GitHub. The newest version is **Git 2.53**.

### Windows
1. Download Git for Windows: <https://git-scm.com/downloads>
2. On the Install page, click the **Windows** tab.
3. Click the **"Click here to download"** link at the top of the Windows panel. This gets the newest **x64** build.
4. Open the `.exe` installer.
5. Click **Install**. Wait, then click **Finish**.

### Mac
- **Option A:** Download from <https://git-scm.com/downloads>. Click "Download for macOS" and install the `.dmg`.
- **Option B:** Open Terminal and type `git --version`. If Git isn't installed, Mac will ask you to install **Xcode Command Line Tools**. Click Install.

### Verify
Open a new terminal window and run:
```bash
git --version
```
**Expected output:** `git version 2.53.x`

### One more thing — tell Git who you are
Git needs your name and email. When you save changes later, they'll be tagged with your name. You only do this once, ever.

```bash
git config --global user.name "Your Name"
git config --global user.email "your@email.com"
```
Replace with **your real name** and Gmail address.

**Check it worked:**
```bash
git config --global user.name
git config --global user.email
```
Each should print exactly what you set above.

### Troubleshooting

**Windows — 'git' is not recognized**
- *Close PowerShell and open a brand new window.*
- *Re-run the Git installer with the right PATH option.* On the "Adjusting your PATH environment" screen, pick the middle option: **"Git from the command line and also from 3rd-party software"**. The top option hides Git from PowerShell.
- *Restart your computer.*

**Mac — 'git: command not found'**
- *Quit Terminal (Cmd + Q) and open a new window.*
- *Install Xcode Command Line Tools:*
  ```bash
  xcode-select --install
  ```
  A dialog pops up — click Install and wait (10–30 min). If it says "command line tools are already installed", that's fine — close Terminal, open a new one, and try again.
- *Reinstall Git* from git-scm.com.

---

## Step 6 — Create GitHub Account

GitHub is where your code will live online. You'll also use your GitHub account to sign in to Supabase and Vercel.

**What to do**
1. Go to GitHub: <https://github.com/>
2. Click **"Sign up"**.
3. Use your **Gmail address**. This account may stay with you for 10+ years.
4. Pick a **professional username** (e.g. `jaytan`, `tanjay-dev`, `tan-consulting`).
5. ❌ Avoid names like: `xX_darkkiller_Xx`, `bossking123`, `cuteprincess88`.
6. Set a strong password (12+ characters with upper case, lower case, and numbers).
7. Check your Gmail for the verification link and click it.
8. Pick the **Free** plan. You don't need paid for this class.
9. If GitHub asks you to set up **two-factor authentication (2FA)**, you can do it now with an app on your phone, or skip for later. Both are fine for the workshop.

**Verify:** Can you log into GitHub and see your dashboard?

> ⚠️ **Warning:** Your username becomes your public developer name and portfolio URL (`github.com/yourusername`). Keep it clean and professional!

---

## Step 7 — Sign Up for Supabase

*Requires Step 6 (GitHub account).*

Supabase gives us the database, login, and APIs for the apps we'll build. It has a big free plan. **No credit card needed.**

**What to do**
1. Go to Supabase: <https://supabase.com/>
2. Click **"Start your project"** or **"Sign Up"**.
3. Click **"Continue with GitHub"**.
4. GitHub will open. Click **Authorize**.
5. You'll go back to the Supabase dashboard.
6. If Supabase asks for an **organization name**, use your GitHub username. You can change it later.

**Verify:** Can you see the Supabase dashboard with your GitHub username?

> ⚠️ **Warning:** Do NOT make a project yet. We'll do that together in the workshop. Just make sure you can log in and see the dashboard.

---

## Step 8 — Sign Up for Vercel

*Requires Step 6 (GitHub account).*

Vercel puts your app online with a live URL in seconds. It connects to GitHub and deploys on its own when you push code. **Free Hobby plan. No credit card needed.**

**What to do**
1. Go to Vercel: <https://vercel.com/>
2. Click **"Sign Up"**.
3. Click **"Continue with GitHub"**.
4. GitHub will open. Click **Authorize**.
5. When it asks about your plan, pick **"Hobby"** (Free).
6. If Vercel asks for a **team name**, use your GitHub username. You can change it later.
7. You might see a screen that says **"Let's import a repository"**. Just close it or click back. You don't need to import anything.

**Verify:** Can you see the Vercel dashboard with the 'Hobby' plan shown?

> ⚠️ **Warning:** Do NOT deploy anything yet. We'll do that together in the workshop. Just make sure you can log in and see the dashboard.

---

## Step 10 — Install Developer CLIs with Claude Code ★ Must have

*Requires Step 8 (Vercel).*

We'll let **Claude Code** (the Code tab in your Claude Desktop App) install the GitHub, Supabase, and Vercel CLIs for you. You paste a prompt, approve a few commands, and handle browser logins when they pop up. **No terminal commands needed.**

**What to do**
1. **Open the Claude Desktop App** you installed in Step 2.
2. **Click the "Code" tab** at the top center of the app. If clicking it asks you to upgrade, you need an active Pro or Max plan (Step 2).
3. **Pick "Local" as the environment**, then click **"Select folder"**. Pick any folder you don't mind Claude working in — your `Documents` folder is fine. Click **Open**.
4. **Check the model dropdown** next to the send button. **Opus 4.7** works best; Sonnet 4.6 also works.
5. **Paste this prompt** into the chat box and press **Enter**:

   ```
   Please install three CLIs on my computer and sign me in to each one:

   1. GitHub CLI (gh) — winget on Windows, or .pkg from github.com/cli/cli/releases on Mac
   2. Supabase CLI — npm install -g supabase
   3. Vercel CLI — npm install -g vercel

   After each install, run its login command (gh auth login, supabase login, vercel login) and walk me through any browser auth that pops up.

   When all three are installed and signed in, run --version on each and report the versions to me.
   ```

6. **Approve each command Claude proposes.** Click **Accept** on every command. Claude shows you what it's about to run before running it.
7. **When a browser window opens** (for gh, supabase, or vercel auth), complete the sign-in in the browser, then come back to the Claude app. For GitHub CLI specifically, copy the one-time code Claude shows you and paste it in the browser.
8. **Wait for Claude to finish** and report all three version numbers. If a step fails, just ask Claude to fix it — that's what Claude Code is for.

**Verify:** Did Claude report version numbers for all three CLIs (gh, supabase, vercel)?

> ⚠️ **Warning:** If Claude can't run shell commands, check that the **permission mode** in the Code tab is set to **"Ask permissions"** (the default) and that you've clicked **Accept** on the proposed commands.

**Tip:** These three CLIs are how you'll talk to GitHub, Supabase, and Vercel from your terminal. After the workshop you can use them on your own projects too.

---

## Step 9 — Final Preparation

You're almost there! Just a few last things to make sure you're ready for the workshop weekend.

**Bring with you**
- 💻 **Laptop.** Fully charged and working.
- 🔌 **Charger.** Don't forget it!
- 💧 **Water bottle.** Stay hydrated during the long sessions.
- 🧥 **Jacket.** The room might be cold from air-con.

**Verify:** Are you packed and ready?

> ⚠️ **Warning:** Don't wait until workshop morning to finish setup. Install problems can take hours to fix. If anything went wrong in an earlier step, message us on WhatsApp now so we can help you before class.

**Tip:** Come ready to learn. Expect fast work, real building, some confusion (that's normal!), and breakthrough moments. **Build, don't just watch.**

---

## Quick Checklist

- [ ] Step 1 — Gmail account ready
- [ ] Step 2 — ★ Claude Pro/Max + desktop app signed in
- [ ] Step 3 — ★ Python 3.14 installed and verified
- [ ] Step 4 — ★ Node.js 24 (with npm) installed and verified
- [ ] Step 5 — Git 2.53 installed; name + email configured
- [ ] Step 6 — GitHub account created (professional username)
- [ ] Step 7 — Supabase signed in via GitHub
- [ ] Step 8 — Vercel signed in via GitHub (Hobby plan)
- [ ] Step 10 — ★ GitHub CLI, Supabase CLI, Vercel CLI installed & signed in
- [ ] Step 9 — Laptop, charger, water bottle, jacket packed

See you at the workshop! 🚀
