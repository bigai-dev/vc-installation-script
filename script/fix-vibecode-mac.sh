#!/usr/bin/env bash
# =============================================================================
#  Vibe Code Workshop - macOS fixer
#  Mirror of fix-vibecode.ps1 (Windows). Installs / verifies every CLI the
#  workshop uses:
#    Python 3.14, Node.js LTS, Git, GitHub CLI (gh), Supabase CLI,
#    Vercel CLI, and Claude Code.
#
#  Per tool the script:
#    - Looks for an existing install
#    - Installs via Homebrew (npm for vercel / claude code) if missing
#    - Ensures the right folder is on PATH in the user's shell rc
#    - Verifies the tool runs in this same shell
#
#  It also:
#    - Bootstraps Xcode Command Line Tools if missing (needed for git, brew)
#    - Bootstraps Homebrew if missing
#    - Backs up ~/.zshrc and ~/.bash_profile before any change
#    - Writes a full session log to /tmp/
#    - Prints a final OK/FAIL table per tool, plus the login commands
#
#  USAGE
#    Easiest: double-click run-fixer.command (opens Terminal automatically).
#
#    From Terminal:
#      bash fix-vibecode-mac.sh                # full install + repair
#      bash fix-vibecode-mac.sh --diagnose-only   # read-only — show what would change
#      bash fix-vibecode-mac.sh --skip-claude-code
# =============================================================================

set -u   # error on unset vars; we deliberately handle command failures by hand.

# ---------- Flag parsing ----------
DIAGNOSE_ONLY=0
SKIP_CLAUDE_CODE=0
for arg in "$@"; do
    case "$arg" in
        --diagnose-only|-d) DIAGNOSE_ONLY=1 ;;
        --skip-claude-code) SKIP_CLAUDE_CODE=1 ;;
        -h|--help)
            grep '^#' "$0" | sed 's/^# \{0,1\}//'
            exit 0 ;;
        *)
            echo "Unknown flag: $arg" >&2
            exit 2 ;;
    esac
done

START_EPOCH=$(date +%s)
STAMP=$(date +%Y%m%d-%H%M%S)

# ---------- Session log (fix mode only) ----------
LOG_PATH=""
if [ "$DIAGNOSE_ONLY" -eq 0 ]; then
    LOG_PATH="/tmp/fix-vibecode-${STAMP}.log"
    # tee everything from here on out to the log file
    exec > >(tee -a "$LOG_PATH") 2>&1
fi

# ---------- Output helpers (ANSI colors; falls back gracefully) ----------
if [ -t 1 ]; then
    C_CYAN=$'\033[36m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'
    C_RED=$'\033[31m'; C_GRAY=$'\033[90m'; C_RESET=$'\033[0m'
else
    C_CYAN=""; C_GREEN=""; C_YELLOW=""; C_RED=""; C_GRAY=""; C_RESET=""
fi
say()  { printf '%s%s%s\n' "${2:-}" "$1" "$C_RESET"; }
step() { printf '\n%s==> %s%s\n' "$C_CYAN" "$1" "$C_RESET"; }
ok()   { printf '%s    [OK] %s%s\n' "$C_GREEN" "$1" "$C_RESET"; }
warn() { printf '%s    [!]  %s%s\n' "$C_YELLOW" "$1" "$C_RESET"; }
fail() { printf '%s    [X]  %s%s\n' "$C_RED" "$1" "$C_RESET"; }
info() { printf '%s         %s%s\n' "$C_GRAY" "$1" "$C_RESET"; }

echo ""
say "=================================================================" "$C_CYAN"
say "  Vibe Code Workshop - macOS fixer" "$C_CYAN"
say "=================================================================" "$C_CYAN"
say "  This installs and verifies Python, Node, Git, gh, Supabase," "$C_GRAY"
say "  Vercel CLI, and Claude Code." "$C_GRAY"
say "  After it finishes, CLOSE this window and open a fresh one." "$C_GRAY"
echo ""

# ---------- Results tracking (final report renders from here) ----------
# bash 3.2 (default on macOS) has no associative arrays. Use parallel arrays.
RES_TOOLS=()
RES_STATUS=()
RES_VERSION=()
RES_PATH=()
RES_NOTES=()

set_result() {
    # set_result <tool> <status> [<version> [<path> [<notes>]]]
    local tool="$1" status="$2" ver="${3:-}" pth="${4:-}" notes="${5:-}"
    local i=0
    while [ $i -lt ${#RES_TOOLS[@]} ]; do
        if [ "${RES_TOOLS[$i]}" = "$tool" ]; then
            RES_STATUS[$i]="$status"
            RES_VERSION[$i]="$ver"
            RES_PATH[$i]="$pth"
            RES_NOTES[$i]="$notes"
            return
        fi
        i=$((i + 1))
    done
    RES_TOOLS+=("$tool")
    RES_STATUS+=("$status")
    RES_VERSION+=("$ver")
    RES_PATH+=("$pth")
    RES_NOTES+=("$notes")
}

has_result() {
    local tool="$1" i=0
    while [ $i -lt ${#RES_TOOLS[@]} ]; do
        if [ "${RES_TOOLS[$i]}" = "$tool" ]; then return 0; fi
        i=$((i + 1))
    done
    return 1
}

# ---------- Detect shell + rc file ----------
# macOS 10.15+ defaults to zsh; bash users predate that. Respect $SHELL.
USER_SHELL_NAME=$(basename "${SHELL:-/bin/zsh}")
case "$USER_SHELL_NAME" in
    zsh)  RC_FILE="$HOME/.zshrc" ;;
    bash) RC_FILE="$HOME/.bash_profile" ;;
    *)    RC_FILE="$HOME/.profile" ;;
esac
info "Detected shell: $USER_SHELL_NAME  (rc file: $RC_FILE)"

# ---------- PATH helpers ----------
ensure_path_line_in_rc() {
    # Adds a single `export PATH="<dir>:$PATH"` line to the rc file if missing.
    # Also updates the CURRENT shell's PATH so later steps in this script see it.
    local dir="$1"
    if [ ! -d "$dir" ]; then
        warn "Skip add to PATH (folder missing): $dir"
        return 1
    fi

    # If brew shellenv (or anything else) already puts this dir on the user's PATH,
    # don't add a duplicate line — would just clutter ~/.zshrc.
    case ":$PATH:" in
        *":$dir:"*)
            info "Already on PATH: $dir"
            return 1
            ;;
    esac

    PATH="$dir:$PATH"; export PATH

    if [ ! -f "$RC_FILE" ]; then touch "$RC_FILE"; fi
    local needle="export PATH=\"$dir:\$PATH\""
    if grep -qsF "$needle" "$RC_FILE"; then
        info "Already in $RC_FILE: $dir"
        return 1
    fi

    if [ "$DIAGNOSE_ONLY" -eq 1 ]; then
        warn "WOULD add to $RC_FILE: $dir  (run without --diagnose-only to apply)"
        return 1
    fi

    {
        echo ""
        echo "# Added by fix-vibecode-mac.sh on $(date '+%Y-%m-%d %H:%M:%S')"
        echo "$needle"
    } >> "$RC_FILE"
    ok "Added to $RC_FILE: $dir"
    return 0
}

# Extract a clean version string (e.g. "2.98.2") from noisy tool output.
# Some tools (notably supabase) print update-available banners to stderr/stdout
# that would otherwise wreck the final results table.
extract_version() {
    # Reads stdin, returns first thing that looks like a semver or vN.N.N
    grep -Eo 'v?[0-9]+\.[0-9]+(\.[0-9]+)?' | head -n 1
}

# ---------- Preflight: Xcode Command Line Tools (needed for brew, git) ----------
step "Checking Xcode Command Line Tools"
if xcode-select -p >/dev/null 2>&1; then
    ok "Xcode Command Line Tools present: $(xcode-select -p)"
else
    if [ "$DIAGNOSE_ONLY" -eq 1 ]; then
        warn "Xcode Command Line Tools missing. Would run: xcode-select --install"
    else
        warn "Xcode Command Line Tools missing - launching installer."
        info "A GUI dialog will appear. Click 'Install' and wait for it to finish."
        info "When it's done, re-run this script."
        xcode-select --install || true
        echo ""
        say "  Re-run this script after the CLT installer finishes." "$C_YELLOW"
        exit 2
    fi
fi

# ---------- Preflight: Homebrew ----------
step "Checking Homebrew (the macOS package manager)"

# brew might be installed but not on PATH yet (especially on Apple Silicon).
# Probe both standard prefixes before declaring it missing.
BREW_BIN=""
if command -v brew >/dev/null 2>&1; then
    BREW_BIN="$(command -v brew)"
elif [ -x /opt/homebrew/bin/brew ]; then
    BREW_BIN="/opt/homebrew/bin/brew"
    eval "$('/opt/homebrew/bin/brew' shellenv)"
elif [ -x /usr/local/bin/brew ]; then
    BREW_BIN="/usr/local/bin/brew"
    eval "$('/usr/local/bin/brew' shellenv)"
fi

if [ -n "$BREW_BIN" ]; then
    ok "Homebrew: $($BREW_BIN --version | head -n 1)  ($BREW_BIN)"
else
    if [ "$DIAGNOSE_ONLY" -eq 1 ]; then
        fail "Homebrew not found. Re-run without --diagnose-only to install it."
        exit 2
    fi
    info "Installing Homebrew (this may take a few minutes)..."
    info "You will be asked for your macOS password."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || {
        fail "Homebrew install failed. Visit https://brew.sh for manual instructions."
        exit 2
    }
    if [ -x /opt/homebrew/bin/brew ]; then
        BREW_BIN="/opt/homebrew/bin/brew"
    elif [ -x /usr/local/bin/brew ]; then
        BREW_BIN="/usr/local/bin/brew"
    else
        fail "Homebrew install completed but 'brew' not found in /opt/homebrew or /usr/local."
        exit 2
    fi
    eval "$("$BREW_BIN" shellenv)"
    ok "Homebrew installed: $BREW_BIN"

    # Persist the brew shellenv line in the user's rc so future shells see it
    BREW_ENV_LINE="eval \"\$($BREW_BIN shellenv)\""
    if ! grep -qsF "$BREW_ENV_LINE" "$RC_FILE"; then
        {
            echo ""
            echo "# Homebrew (added by fix-vibecode-mac.sh on $(date '+%Y-%m-%d %H:%M:%S'))"
            echo "$BREW_ENV_LINE"
        } >> "$RC_FILE"
        ok "Wrote brew shellenv to $RC_FILE"
    fi
fi

# ---------- Back up shell rc files ----------
step "Backing up your shell config"
BACKUP_DIR="$HOME/dotfile-backups"
mkdir -p "$BACKUP_DIR"
for f in "$HOME/.zshrc" "$HOME/.bash_profile" "$HOME/.profile" "$HOME/.bashrc"; do
    if [ -f "$f" ]; then
        cp "$f" "$BACKUP_DIR/$(basename "$f").$STAMP.bak"
        info "Backed up: $f -> $BACKUP_DIR/$(basename "$f").$STAMP.bak"
    fi
done
ok "Backups in $BACKUP_DIR"

# ---------- Wrapper around brew install ----------
brew_install() {
    # brew_install <formula>
    local formula="$1"
    if [ "$DIAGNOSE_ONLY" -eq 1 ]; then
        warn "WOULD: brew install $formula"
        return 1
    fi
    "$BREW_BIN" install "$formula"
}

# ---------- Python ----------
step "Checking Python"

find_python_candidates() {
    # Print one path per line. Use unique to dedupe.
    {
        # brew formulas
        for p in /opt/homebrew/bin/python3 /opt/homebrew/bin/python3.14 /opt/homebrew/bin/python3.13 \
                 /usr/local/bin/python3 /usr/local/bin/python3.14 /usr/local/bin/python3.13; do
            [ -x "$p" ] && echo "$p"
        done
        # Apple's preinstalled (we'll filter out by version anyway)
        [ -x /usr/bin/python3 ] && echo /usr/bin/python3
        # python.org installer (Frameworks)
        for d in /Library/Frameworks/Python.framework/Versions/3.14/bin \
                 /Library/Frameworks/Python.framework/Versions/3.13/bin; do
            [ -x "$d/python3" ] && echo "$d/python3"
        done
        # pyenv shims and Anaconda/Miniconda
        [ -x "$HOME/.pyenv/shims/python3" ] && echo "$HOME/.pyenv/shims/python3"
        for c in "$HOME/anaconda3/bin/python3" "$HOME/miniconda3/bin/python3" "$HOME/miniforge3/bin/python3"; do
            [ -x "$c" ] && echo "$c"
        done
    } | awk '!seen[$0]++'
}

ver_ge() {
    # ver_ge <a> <b> -> success if a >= b (semver-ish, ignores pre-release)
    [ "$(printf '%s\n%s\n' "$1" "$2" | sort -t. -k1,1n -k2,2n -k3,3n | tail -n 1)" = "$1" ]
}

install_python() {
    local best_path="" best_ver=""
    while IFS= read -r p; do
        [ -z "$p" ] && continue
        local v
        v=$("$p" --version 2>&1 | awk '{print $2}')
        [ -z "$v" ] && continue
        if [ -z "$best_ver" ] || ver_ge "$v" "$best_ver"; then
            best_ver="$v"; best_path="$p"
        fi
    done < <(find_python_candidates)

    if [ -n "$best_path" ] && ver_ge "$best_ver" "3.14.0"; then
        ok "Python $best_ver: $best_path"
        set_result python AlreadyInstalled "$best_ver" "$best_path"
        # Make sure its dir is first on PATH so workshops find it
        local pydir
        pydir=$(dirname "$best_path")
        ensure_path_line_in_rc "$pydir" || true
        return
    fi

    if [ -n "$best_path" ]; then
        warn "Found Python $best_ver, but workshop requires 3.14+. Will install via brew."
    else
        warn "No suitable Python found."
    fi

    if [ "$DIAGNOSE_ONLY" -eq 1 ]; then
        set_result python Skipped "" "" "Would install python@3.14 via brew"
        return
    fi

    info "Installing python@3.14 via brew..."
    if "$BREW_BIN" install python@3.14; then
        # brew links it as /opt/homebrew/bin/python3.14 (or /usr/local on Intel)
        local newp=""
        for p in /opt/homebrew/bin/python3.14 /usr/local/bin/python3.14 /opt/homebrew/bin/python3 /usr/local/bin/python3; do
            if [ -x "$p" ]; then
                local v
                v=$("$p" --version 2>&1 | awk '{print $2}')
                if ver_ge "$v" "3.14.0"; then
                    newp="$p"; break
                fi
            fi
        done
        if [ -n "$newp" ]; then
            local v
            v=$("$newp" --version 2>&1 | awk '{print $2}')
            ok "Python $v installed: $newp"
            set_result python Installed "$v" "$newp"
            ensure_path_line_in_rc "$(dirname "$newp")" || true
        else
            fail "Python install succeeded but python3.14 not found."
            set_result python Failed "" "" "Post-install search failed"
        fi
    else
        fail "brew install python@3.14 failed (exit $?)"
        set_result python Failed "" "" "brew install failed"
    fi
}

install_python

# ---------- Node.js ----------
step "Checking Node.js"

install_node() {
    if command -v node >/dev/null 2>&1; then
        local nv npmv node_src
        nv=$(node --version 2>&1)
        npmv=$(npm --version 2>&1)
        node_src=$(command -v node)
        ok "node $nv,  npm $npmv  ($node_src)"

        local major
        major=$(echo "$nv" | sed -E 's/^v([0-9]+).*/\1/')
        if [ "$major" -lt 18 ]; then
            warn "Node $nv is below v18. Upgrading via brew..."
            if [ "$DIAGNOSE_ONLY" -eq 0 ]; then
                "$BREW_BIN" install node || true
                local nv2
                nv2=$(node --version 2>&1)
                ok "node upgraded: $nv2"
                set_result node Installed "$nv2" "$(command -v node)"
            else
                set_result node Skipped "$nv" "$node_src" "Would upgrade"
            fi
        else
            set_result node AlreadyInstalled "$nv" "$node_src"
        fi
        return
    fi

    warn "node not on PATH."
    if [ "$DIAGNOSE_ONLY" -eq 1 ]; then
        set_result node Skipped "" "" "Would install node via brew"
        return
    fi

    info "Installing Node.js via brew..."
    if "$BREW_BIN" install node; then
        local nv
        nv=$(node --version 2>&1)
        ok "Node $nv installed: $(command -v node)"
        set_result node Installed "$nv" "$(command -v node)"
    else
        fail "brew install node failed."
        set_result node Failed "" "" "brew install failed"
    fi
}

install_node

# ---------- Git ----------
step "Checking Git"

install_git() {
    if command -v git >/dev/null 2>&1; then
        local gv git_src ver_only
        gv=$(git --version 2>&1)
        git_src=$(command -v git)
        ver_only=$(echo "$gv" | sed -E 's/^git version //')
        ok "$gv  ($git_src)"
        set_result git AlreadyInstalled "$ver_only" "$git_src"
    else
        if [ "$DIAGNOSE_ONLY" -eq 1 ]; then
            warn "git not found. Would install via brew."
            set_result git Skipped "" "" "Would install git via brew"
            return
        fi
        info "Installing Git via brew..."
        if "$BREW_BIN" install git; then
            local gv
            gv=$(git --version 2>&1)
            ok "Git installed: $gv"
            set_result git Installed "$(echo "$gv" | sed -E 's/^git version //')" "$(command -v git)"
        else
            fail "brew install git failed."
            set_result git Failed "" "" "brew install failed"
            return
        fi
    fi

    # Surface git identity status — don't prompt; students may not have a GitHub yet
    if [ "$DIAGNOSE_ONLY" -eq 0 ]; then
        local existing_name existing_email
        existing_name=$(git config --global user.name 2>/dev/null || true)
        existing_email=$(git config --global user.email 2>/dev/null || true)
        if [ -z "$existing_name" ] || [ -z "$existing_email" ]; then
            warn "git user.name / user.email not set - configure before your first commit (see end of run)."
        else
            ok "git user.name = $existing_name"
            ok "git user.email = $existing_email"
        fi
    fi
}

install_git

# ---------- GitHub CLI ----------
step "Checking GitHub CLI (gh)"

install_gh() {
    if command -v gh >/dev/null 2>&1; then
        local ghv gh_src
        ghv=$(gh --version 2>&1 | head -n 1)
        gh_src=$(command -v gh)
        ok "$ghv  ($gh_src)"
        set_result gh AlreadyInstalled "$(echo "$ghv" | awk '{print $3}')" "$gh_src"
        return
    fi
    if [ "$DIAGNOSE_ONLY" -eq 1 ]; then
        warn "gh not found. Would install via brew."
        set_result gh Skipped "" "" "Would install gh via brew"
        return
    fi
    info "Installing GitHub CLI via brew..."
    if "$BREW_BIN" install gh; then
        local ghv
        ghv=$(gh --version 2>&1 | head -n 1)
        ok "GitHub CLI installed: $ghv"
        set_result gh Installed "$(echo "$ghv" | awk '{print $3}')" "$(command -v gh)"
    else
        fail "brew install gh failed."
        set_result gh Failed "" "" "brew install failed"
    fi
}

install_gh

# ---------- Supabase CLI ----------
step "Checking Supabase CLI"

install_supabase() {
    if command -v supabase >/dev/null 2>&1; then
        local sbv sb_src
        sbv=$(supabase --version 2>&1 | extract_version)
        sb_src=$(command -v supabase)
        ok "supabase $sbv  ($sb_src)"
        set_result supabase AlreadyInstalled "$sbv" "$sb_src"
        return
    fi
    if [ "$DIAGNOSE_ONLY" -eq 1 ]; then
        warn "supabase not found. Would install via brew (supabase/tap/supabase)."
        set_result supabase Skipped "" "" "Would install via brew tap"
        return
    fi
    info "Installing Supabase CLI via brew tap..."
    # Official install method on macOS — npm install -g supabase is deprecated.
    if "$BREW_BIN" install supabase/tap/supabase; then
        local sbv
        sbv=$(supabase --version 2>&1 | extract_version)
        ok "Supabase CLI installed: $sbv"
        set_result supabase Installed "$sbv" "$(command -v supabase)"
    else
        fail "brew install supabase/tap/supabase failed."
        set_result supabase Failed "" "" "brew install failed"
    fi
}

install_supabase

# ---------- Vercel CLI ----------
step "Checking Vercel CLI"

install_vercel() {
    if command -v vercel >/dev/null 2>&1; then
        local vcv vc_src
        vcv=$(vercel --version 2>&1 | extract_version)
        vc_src=$(command -v vercel)
        ok "vercel $vcv  ($vc_src)"
        set_result vercel AlreadyInstalled "$vcv" "$vc_src"
        return
    fi
    if ! command -v npm >/dev/null 2>&1; then
        warn "npm not available - cannot install Vercel CLI."
        set_result vercel Failed "" "" "npm not available"
        return
    fi
    if [ "$DIAGNOSE_ONLY" -eq 1 ]; then
        warn "vercel not found. Would install via npm."
        set_result vercel Skipped "" "" "Would install vercel via npm"
        return
    fi
    info "Installing Vercel CLI via npm install -g vercel..."
    if npm install -g vercel; then
        local vcv
        vcv=$(vercel --version 2>&1 | extract_version)
        ok "Vercel CLI installed: $vcv"
        set_result vercel Installed "$vcv" "$(command -v vercel)"
    else
        fail "npm install -g vercel failed."
        set_result vercel Failed "" "" "npm install failed"
    fi
}

install_vercel

# ---------- Claude Code ----------
if [ "$SKIP_CLAUDE_CODE" -eq 0 ] && [ "$DIAGNOSE_ONLY" -eq 0 ]; then
    step "Installing Claude Code"
    if command -v claude >/dev/null 2>&1; then
        cv=$(claude --version 2>&1 || true)
        cl_src=$(command -v claude)
        ok "Claude Code already installed: $cv  ($cl_src)"
        set_result claude AlreadyInstalled "$cv" "$cl_src"
    else
        if ! command -v npm >/dev/null 2>&1; then
            fail "npm not available - cannot install Claude Code."
            set_result claude Failed "" "" "npm not available"
        else
            info "Installing Claude Code via npm install -g @anthropic-ai/claude-code..."
            if npm install -g "@anthropic-ai/claude-code"; then
                if command -v claude >/dev/null 2>&1; then
                    cv=$(claude --version 2>&1 || true)
                    ok "Claude Code: $cv"
                    set_result claude Installed "$cv" "$(command -v claude)"
                else
                    fail "npm reported success but 'claude' not on PATH."
                    set_result claude Failed "" "" "Post-install search failed"
                fi
            else
                fail "npm install -g @anthropic-ai/claude-code failed."
                set_result claude Failed "" "" "npm install failed"
            fi
        fi
    fi
fi

if ! has_result claude; then
    if [ "$SKIP_CLAUDE_CODE" -eq 1 ]; then
        set_result claude Skipped "" "" "Skipped via --skip-claude-code flag"
    elif [ "$DIAGNOSE_ONLY" -eq 1 ]; then
        if command -v claude >/dev/null 2>&1; then
            cv=$(claude --version 2>&1 || true)
            set_result claude AlreadyInstalled "$cv" "$(command -v claude)"
        else
            set_result claude Skipped "" "" "Would install via npm"
        fi
    fi
fi

# ---------- Final verification (re-check every tool with --version) ----------
step "Final verification"

reverify=(python3 node npm git gh supabase vercel)
[ "$SKIP_CLAUDE_CODE" -eq 0 ] && reverify+=(claude)

for tool in "${reverify[@]}"; do
    # Map python3 -> python in results
    key="$tool"
    [ "$tool" = "python3" ] && key="python"
    if command -v "$tool" >/dev/null 2>&1; then
        v=$("$tool" --version 2>&1 | extract_version)
        if ! has_result "$key"; then
            set_result "$key" AlreadyInstalled "$v" "$(command -v "$tool")"
        fi
    else
        if ! has_result "$key"; then
            set_result "$key" Failed "" "" "Not on PATH in this shell"
        fi
    fi
done

# ---------- Render the final table ----------
echo ""
say "  Tool        Status              Version                 Path" "$C_CYAN"
say "  ----------- ------------------- ----------------------- --------------------------------------------------" "$C_CYAN"
all_good=1
i=0
while [ $i -lt ${#RES_TOOLS[@]} ]; do
    t="${RES_TOOLS[$i]}"
    s="${RES_STATUS[$i]}"
    v="${RES_VERSION[$i]}"
    p="${RES_PATH[$i]}"
    n="${RES_NOTES[$i]}"
    case "$s" in
        Installed|AlreadyInstalled|PathFixed) color="$C_GREEN" ;;
        Skipped)                              color="$C_YELLOW" ;;
        Failed)                               color="$C_RED"; all_good=0 ;;
        *)                                    color="$C_GRAY" ;;
    esac
    printf '%s  %-11s %-19s %-23s %s%s\n' "$color" "$t" "$s" "$v" "$p" "$C_RESET"
    if [ -n "$n" ]; then
        printf '%s              note: %s%s\n' "$C_GRAY" "$n" "$C_RESET"
    fi
    i=$((i + 1))
done

echo ""
say "=================================================================" "$C_CYAN"
if [ "$DIAGNOSE_ONLY" -eq 1 ]; then
    say "  Diagnose-only finished. Re-run WITHOUT --diagnose-only to apply fixes." "$C_YELLOW"
elif [ "$all_good" -eq 1 ]; then
    say "  All tools are working in THIS shell." "$C_GREEN"
    echo ""
    say "  Next steps - run these in this same window:" ""
    say "      gh auth login" ""
    say "      supabase login" ""
    say "      vercel login" ""
    say "      git config --global user.name \"Your Name\"" ""
    say "      git config --global user.email \"you@example.com\"" ""
    echo ""
    say "  (The first three open a browser. The git ones set your commit identity.)" "$C_GRAY"
else
    say "  Some tools failed. See the table above." "$C_YELLOW"
    say "  Close this Terminal window, open a fresh one, and re-run this script." "$C_YELLOW"
    if [ -n "$LOG_PATH" ]; then
        say "  Log: $LOG_PATH" ""
    fi
fi
END_EPOCH=$(date +%s)
ELAPSED=$((END_EPOCH - START_EPOCH))
say "  Total time: $((ELAPSED / 60)) min $(printf '%02d' $((ELAPSED % 60))) sec" "$C_GRAY"
say "  Backups: $BACKUP_DIR" "$C_GRAY"
say "=================================================================" "$C_CYAN"
echo ""

if [ -n "$LOG_PATH" ]; then
    printf '%sSession log: %s%s\n' "$C_GRAY" "$LOG_PATH" "$C_RESET"
fi
