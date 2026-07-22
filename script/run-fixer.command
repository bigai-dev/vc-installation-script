#!/usr/bin/env bash
# =============================================================================
#  Vibe Code Workshop - macOS one-click fixer
#  Double-click this file in Finder. Terminal opens automatically.
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PS_EQUIV="$SCRIPT_DIR/fix-vibecode-mac.sh"

STAMP=$(date +%Y%m%d-%H%M%S)
LOG_FILE="/tmp/run-fixer-${STAMP}.log"

clear
cat <<BANNER

 =================================================================
   Vibe Code Workshop - One-Click Fixer (macOS)
 =================================================================

   This will install / verify all the workshop tools:
     Python 3.14, Node.js LTS, Git, GitHub CLI (gh),
     Supabase CLI, Vercel CLI, and Claude Code.

   It uses Homebrew (https://brew.sh) under the hood, and will
   install Homebrew first if you don't have it.

   Your shell config (~/.zshrc / ~/.bash_profile) is backed up to:
     ~/dotfile-backups/

   Total time: 5-10 minutes (longer if Homebrew is being installed
   for the first time).

   You may be asked for your macOS password to install Homebrew.

   Log file: $LOG_FILE

 =================================================================

BANNER

read -r -p " Press Enter to start, or Ctrl-C to cancel: " _

if [ ! -f "$PS_EQUIV" ]; then
    cat <<EOF

 ==================================================================
   ERROR: Could not find fix-vibecode-mac.sh
 ==================================================================

   Expected location:
     $PS_EQUIV

   Make sure both files are in the same folder:
     - run-fixer.command       (this file)
     - fix-vibecode-mac.sh     (the main script)

EOF
    read -r -p " Press Enter to close..." _
    exit 1
fi

bash "$PS_EQUIV" "$@"
EXIT_CODE=$?

cat <<EOF

 =================================================================
   Fixer exit code: $EXIT_CODE
 =================================================================

   Check the table above for the per-tool result.

   If everything looks green, sign in to each service:
       gh auth login
       supabase login
       vercel login

 =================================================================
   RAISE YOUR HAND and wait for a workshop assistant to check
   this screen with you BEFORE you close this window.
 =================================================================

EOF

read -r -p " Press Enter to close this window..." _
exit $EXIT_CODE
