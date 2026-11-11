#!/usr/bin/env bash
# =============================================================================
#  VIBE CODING ACADEMY - OFFICIAL SETUP
#  (c) 2026 Vibe Coding Academy. All Rights Reserved.
#  For authorised Vibe Coding Academy participants only.
#  Unauthorised redistribution, resale, rebranding, reproduction,
#  or use in third-party training is prohibited.
#  Origin ID: VCA-2026-09-A7F3C8
# =============================================================================
#  Vibe Code Workshop - macOS fixer
#  Mirror of fix-vibecode.ps1 (Windows). Installs / verifies every CLI the
#  workshop uses:
#    Python 3.14, Node.js LTS, Git, GitHub CLI (gh), Supabase CLI,
#    Vercel CLI, and Claude Code.
#
#  Per tool the script:
#    - Looks for an existing install (and upgrades Node if it's too old)
#    - Installs via Homebrew if missing (npm for Vercel; Anthropic's own
#      installer for Claude Code, which is Anthropic's recommended method)
#    - Ensures the right folder is on PATH in the user's shell rc
#    - Verifies the tool runs in this same shell and reports a real version
#
#  It also:
#    - Bootstraps Xcode Command Line Tools if missing (needed for git, brew)
#    - Bootstraps Homebrew if missing
#    - Makes plain `python3` run the workshop Python (not Apple's old 3.9)
#    - Moves npm's install folder to ~/.npm-global if the system one is locked
#    - Backs up ~/.zshrc, ~/.bash_profile and ~/.npmrc before any change
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

# ---------- Bash-only guard (must run BEFORE any bash-specific syntax) ----------
# If invoked via `sh fix-vibecode-mac.sh`, the shebang is ignored and we're in
# POSIX sh mode (BASH_VERSION still set on macOS because /bin/sh IS bash, but
# POSIXLY_CORRECT=y and process substitution `>()` fails at parse time).
# Re-exec under real bash so the user doesn't have to retry.
if [ -z "${BASH_VERSION:-}" ] || [ -n "${POSIXLY_CORRECT:-}" ]; then
    exec bash "$0" "$@"
fi

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

# ---------- Detect TTY BEFORE we redirect stdout to tee ----------
# After `exec > >(tee ...)`, `[ -t 1 ]` returns false (stdout is a pipe),
# so any TTY check has to happen here, while stdout is still the terminal.
if [ -t 1 ]; then HAS_COLOR=1; else HAS_COLOR=0; fi

# ---------- Session log (fix mode only) ----------
LOG_PATH=""
if [ "$DIAGNOSE_ONLY" -eq 0 ]; then
    LOG_PATH="/tmp/fix-vibecode-${STAMP}.log"
    # tee stdout/stderr to the log, but strip ANSI color codes from the log
    # copy so it stays readable in `cat`/`less` while users still see colors.
    ESC=$(printf '\033')
    exec > >(tee >(sed "s/${ESC}\[[0-9;]*m//g" >> "$LOG_PATH")) 2>&1

    # Print log path on any exit (clean or crash) so users know where to look.
    trap 'echo ""; echo "Session log: '"$LOG_PATH"'"' EXIT
fi

# ---------- Output helpers (ANSI colors; falls back gracefully) ----------
if [ "$HAS_COLOR" -eq 1 ]; then
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
    # ensure_path_line_in_rc <dir> [first]
    # Adds a single `export PATH="<dir>:$PATH"` line to the rc file if missing.
    # Also updates the CURRENT shell's PATH so later steps in this script see it.
    # With "first", <dir> is moved to the front even if it's already further
    # back on PATH - for when an older copy of a tool (e.g. Apple's python3)
    # would otherwise be found first.
    local dir="$1" mode="${2:-}"
    if [ ! -d "$dir" ]; then
        warn "Skip add to PATH (folder missing): $dir"
        return 1
    fi

    # If brew shellenv (or anything else) already puts this dir on the user's PATH,
    # don't add a duplicate line - would just clutter ~/.zshrc.
    if [ "$mode" != "first" ]; then
        case ":$PATH:" in
            *":$dir:"*)
                info "Already on PATH: $dir"
                return 1
                ;;
        esac
    fi

    PATH="$dir:$PATH"; export PATH

    # (No `touch` here: diagnose mode must not create files. The >> below
    # creates the rc file if it doesn't exist yet.)
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

# Run "<tool> --version" and print just the version number, or NOTHING when the
# tool runs but prints no version (an error message instead). Callers treat an
# empty result as "broken" and mark the tool Failed rather than showing green.
tool_version() {
    "$@" --version 2>&1 | extract_version
}

# "v26.13.0" -> 26 ; empty or garbage -> 0
major_of() {
    local m
    m=$(echo "${1:-}" | sed -E 's/^v?([0-9]+).*/\1/')
    case "$m" in ''|*[!0-9]*) m=0 ;; esac
    echo "$m"
}

# True if <dir> is writable, or doesn't exist yet but could be created.
can_write_dir() {
    [ -w "$1" ] || { [ ! -e "$1" ] && [ -w "$(dirname "$1")" ]; }
}

# The Node installer from nodejs.org (which the prep guide points Mac students
# to) puts npm's global folder in /usr/local, owned by the system, so
# `npm install -g` fails with "permission denied" (EACCES). npm's own
# recommended fix: point npm at a folder in the user's home. Only acts when the
# current folder really isn't writable (Homebrew and nvm Node are fine).
ensure_npm_global_writable() {
    local prefix
    prefix=$(npm config get prefix 2>/dev/null)
    [ -z "$prefix" ] && return 0
    if can_write_dir "$prefix/lib/node_modules" && can_write_dir "$prefix/bin"; then
        return 0
    fi
    warn "npm's install folder ($prefix) belongs to the system - switching npm to ~/.npm-global."
    if [ "$DIAGNOSE_ONLY" -eq 1 ]; then
        warn "WOULD run: npm config set prefix ~/.npm-global  (and add ~/.npm-global/bin to PATH)"
        return 0
    fi
    mkdir -p "$HOME/.npm-global/bin" "$HOME/.npm-global/lib"
    if npm config set prefix "$HOME/.npm-global"; then
        ok "npm now installs tools into ~/.npm-global (no password needed)"
        ensure_path_line_in_rc "$HOME/.npm-global/bin" first || true
        hash -r
    else
        fail "Could not change npm's install folder - npm installs may fail."
    fi
}

# Claude Code comes from Anthropic's own installer - their recommended method:
# no Node/npm needed, it keeps itself up to date, and it isn't hit by npm 12+
# skipping install steps. It puts `claude` in ~/.local/bin but does NOT add
# that folder to PATH itself, so we do.
install_claude_native() {
    local tmpdir rc=0
    tmpdir=$(mktemp -d 2>/dev/null || mktemp -d -t claude-install)
    if ! curl -fsSL https://claude.ai/install.sh -o "$tmpdir/install.sh"; then
        rm -rf "$tmpdir"
        return 1
    fi
    # </dev/null: the installer must never sit waiting for keyboard input.
    bash "$tmpdir/install.sh" </dev/null || rc=$?
    rm -rf "$tmpdir"
    [ "$rc" -eq 0 ] || return 1
    mkdir -p "$HOME/.local/bin"
    ensure_path_line_in_rc "$HOME/.local/bin" || true
    hash -r
    return 0
}

# True if <path> is the npm copy of Claude Code (the old install method).
is_npm_claude() {
    local target
    target=$(readlink "$1" 2>/dev/null || true)
    case "$1 $target" in
        *node_modules/@anthropic-ai/claude-code*) return 0 ;;
    esac
    return 1
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
if [ "$DIAGNOSE_ONLY" -eq 1 ]; then
    info "Diagnose only - nothing will be changed, so no backup needed."
else
    mkdir -p "$BACKUP_DIR"
    # ~/.npmrc too: the script may point npm at ~/.npm-global (see below).
    for f in "$HOME/.zshrc" "$HOME/.bash_profile" "$HOME/.profile" "$HOME/.bashrc" "$HOME/.npmrc"; do
        if [ -f "$f" ]; then
            cp "$f" "$BACKUP_DIR/$(basename "$f").$STAMP.bak"
            info "Backed up: $f -> $BACKUP_DIR/$(basename "$f").$STAMP.bak"
        fi
    done
    ok "Backups in $BACKUP_DIR"
fi

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
        for p in /opt/homebrew/bin/python3 /opt/homebrew/bin/python3.15 /opt/homebrew/bin/python3.14 /opt/homebrew/bin/python3.13 \
                 /usr/local/bin/python3 /usr/local/bin/python3.15 /usr/local/bin/python3.14 /usr/local/bin/python3.13; do
            [ -x "$p" ] && echo "$p"
        done
        # Apple's preinstalled (we'll filter out by version anyway)
        [ -x /usr/bin/python3 ] && echo /usr/bin/python3
        # python.org installer (Frameworks)
        for d in /Library/Frameworks/Python.framework/Versions/3.15/bin \
                 /Library/Frameworks/Python.framework/Versions/3.14/bin \
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

python_cmd_dir() {
    # python_cmd_dir <python exe> <version>
    # Folder to put first on PATH so plain `python3` runs this Python.
    # Since Oct 2026 Homebrew's default Python is 3.15, so a fresh python@3.14
    # only creates `python3.14` in /opt/homebrew/bin; its plain `python3` (and
    # `python`, `pip`) live in <brew prefix>/opt/python@3.14/libexec/bin.
    # Older python@3.14 installs (from when it was the default) still have
    # plain python3 next to the exe, so the exe's own folder is right for them.
    local exe="$1" ver="$2" mm prefix libexec_bin
    mm=$(echo "$ver" | cut -d. -f1-2)
    if [ -n "$BREW_BIN" ]; then
        prefix=$("$BREW_BIN" --prefix 2>/dev/null)
        libexec_bin="$prefix/opt/python@$mm/libexec/bin"
        case "$exe" in
            "$prefix"/*)
                if [ -x "$libexec_bin/python3" ]; then
                    echo "$libexec_bin"
                    return
                fi
                ;;
        esac
    fi
    dirname "$exe"
}

use_python() {
    # use_python <python exe> <version> <status>
    # Put this Python first on PATH (now and in new windows), then prove that
    # typing plain `python3` really runs it - not Apple's old built-in 3.9.
    local exe="$1" ver="$2" status="$3" dir now
    dir=$(python_cmd_dir "$exe" "$ver")
    if [ "$DIAGNOSE_ONLY" -eq 1 ]; then
        # Report what typing python3 does RIGHT NOW (nothing gets changed).
        now=$(tool_version python3)
        ensure_path_line_in_rc "$dir" || true
        if [ -n "$now" ] && ver_ge "$now" "3.14.0"; then
            set_result python "$status" "$ver" "$exe"
        else
            warn "Typing python3 currently runs ${now:-nothing}, not Python $ver."
            set_result python Skipped "$ver" "$exe" "python3 runs ${now:-nothing} - would fix PATH"
        fi
        return
    fi
    ensure_path_line_in_rc "$dir" || true
    hash -r
    now=$(tool_version python3)
    if [ -z "$now" ] || ! ver_ge "$now" "3.14.0"; then
        # An older python3 is still found first - move our folder to the front.
        ensure_path_line_in_rc "$dir" first || true
        hash -r
        now=$(tool_version python3)
    fi
    if [ -n "$now" ] && ver_ge "$now" "3.14.0"; then
        ok "Typing python3 runs Python $now"
        set_result python "$status" "$ver" "$exe"
    else
        fail "Typing python3 runs ${now:-nothing} instead of Python $ver."
        set_result python Failed "$ver" "$exe" "python3 runs ${now:-nothing}, not $ver"
    fi
}

install_python() {
    local best_path="" best_ver=""
    while IFS= read -r p; do
        [ -z "$p" ] && continue
        local v
        v=$(tool_version "$p")
        [ -z "$v" ] && continue
        if [ -z "$best_ver" ] || ver_ge "$v" "$best_ver"; then
            best_ver="$v"; best_path="$p"
        fi
    done < <(find_python_candidates)

    if [ -n "$best_path" ] && ver_ge "$best_ver" "3.14.0"; then
        ok "Python $best_ver: $best_path"
        use_python "$best_path" "$best_ver" AlreadyInstalled
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
        hash -r
        # brew links it as /opt/homebrew/bin/python3.14 (or /usr/local on Intel)
        local newp="" v=""
        for p in /opt/homebrew/bin/python3.14 /usr/local/bin/python3.14 /opt/homebrew/bin/python3 /usr/local/bin/python3; do
            if [ -x "$p" ]; then
                v=$(tool_version "$p")
                if [ -n "$v" ] && ver_ge "$v" "3.14.0"; then
                    newp="$p"; break
                fi
            fi
        done
        if [ -n "$newp" ]; then
            ok "Python $v installed: $newp"
            use_python "$newp" "$v" Installed
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

# Oldest Node the workshop tools support: Vercel CLI needs 20+, Claude Code asks
# for 22+. 23 and 25 were short-lived releases that no longer get security
# fixes. Raise NODE_MIN_MAJOR to 24 after April 2027 (Node 22's end of life).
NODE_MIN_MAJOR=22
node_too_old() {
    # node_too_old <major version number>
    [ "$1" -lt "$NODE_MIN_MAJOR" ] || [ "$1" -eq 23 ] || [ "$1" -eq 25 ]
}

install_node() {
    if command -v node >/dev/null 2>&1; then
        local nv npmv node_src
        nv=$(tool_version node)
        npmv=$(tool_version npm)
        node_src=$(command -v node)
        ok "node ${nv:-(no version)},  npm ${npmv:-(no version)}  ($node_src)"

        if node_too_old "$(major_of "$nv")"; then
            warn "Node ${nv:-(broken)} is too old or out of support (need v$NODE_MIN_MAJOR+, not 23/25)."
            if [ "$DIAGNOSE_ONLY" -eq 0 ]; then
                info "Upgrading Node via brew..."
                # `brew install` won't upgrade a Node that brew already manages.
                if "$BREW_BIN" list --versions node >/dev/null 2>&1; then
                    "$BREW_BIN" upgrade node || true
                else
                    "$BREW_BIN" install node || true
                fi
                hash -r
                local nv2 node2_src
                nv2=$(tool_version node)
                node2_src=$(command -v node 2>/dev/null || true)
                if [ -n "$nv2" ] && ! node_too_old "$(major_of "$nv2")"; then
                    ok "node upgraded: $nv2"
                    set_result node Installed "$nv2" "$node2_src"
                else
                    fail "Node is still ${nv2:-not working} after the upgrade ($node2_src)."
                    info "Another Node install (e.g. from nodejs.org or nvm) is probably found first."
                    set_result node Failed "$nv2" "$node2_src" "Still ${nv2:-not working} - remove the older Node, then re-run"
                fi
            else
                set_result node Skipped "$nv" "$node_src" "Would upgrade to the current LTS"
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
        hash -r
        local nv
        nv=$(tool_version node)
        if [ -n "$nv" ]; then
            ok "Node $nv installed: $(command -v node)"
            set_result node Installed "$nv" "$(command -v node)"
        else
            fail "brew installed node, but it doesn't run."
            set_result node Failed "" "$(command -v node 2>/dev/null || true)" "Installed, but node --version fails"
        fi
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
        local gv git_src
        gv=$(tool_version git)
        git_src=$(command -v git)
        if [ -z "$gv" ]; then
            # Typical after a macOS upgrade: Apple's git can't find its developer
            # tools and prints an "xcrun: error" instead of a version.
            fail "git is there ($git_src) but doesn't run - Apple's developer tools need repairing."
            info "Fix: run  xcode-select --install  then re-run this script."
            info "(If it says the tools are already installed, ask a workshop assistant.)"
            set_result git Failed "" "$git_src" "git doesn't run - run xcode-select --install, then re-run"
            return
        fi
        ok "git $gv  ($git_src)"
        set_result git AlreadyInstalled "$gv" "$git_src"
    else
        if [ "$DIAGNOSE_ONLY" -eq 1 ]; then
            warn "git not found. Would install via brew."
            set_result git Skipped "" "" "Would install git via brew"
            return
        fi
        info "Installing Git via brew..."
        if "$BREW_BIN" install git; then
            hash -r
            local gv
            gv=$(tool_version git)
            if [ -z "$gv" ]; then
                fail "brew installed git, but it doesn't run."
                set_result git Failed "" "$(command -v git 2>/dev/null || true)" "Installed, but git --version fails"
                return
            fi
            ok "Git installed: $gv"
            set_result git Installed "$gv" "$(command -v git)"
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
        ghv=$(tool_version gh)
        gh_src=$(command -v gh)
        if [ -n "$ghv" ]; then
            ok "gh $ghv  ($gh_src)"
            set_result gh AlreadyInstalled "$ghv" "$gh_src"
        else
            fail "gh is there ($gh_src) but doesn't run."
            set_result gh Failed "" "$gh_src" "gh doesn't run - reinstall GitHub CLI, then re-run"
        fi
        return
    fi
    if [ "$DIAGNOSE_ONLY" -eq 1 ]; then
        warn "gh not found. Would install via brew."
        set_result gh Skipped "" "" "Would install gh via brew"
        return
    fi
    info "Installing GitHub CLI via brew..."
    if "$BREW_BIN" install gh; then
        hash -r
        local ghv
        ghv=$(tool_version gh)
        if [ -n "$ghv" ]; then
            ok "GitHub CLI installed: $ghv"
            set_result gh Installed "$ghv" "$(command -v gh)"
        else
            fail "brew installed gh, but it doesn't run."
            set_result gh Failed "" "$(command -v gh 2>/dev/null || true)" "Installed, but gh --version fails"
        fi
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
        sbv=$(tool_version supabase)
        sb_src=$(command -v supabase)
        if [ -n "$sbv" ]; then
            ok "supabase $sbv  ($sb_src)"
            set_result supabase AlreadyInstalled "$sbv" "$sb_src"
        else
            fail "supabase is there ($sb_src) but doesn't run."
            set_result supabase Failed "" "$sb_src" "supabase doesn't run - reinstall it, then re-run"
        fi
        return
    fi
    if [ "$DIAGNOSE_ONLY" -eq 1 ]; then
        warn "supabase not found. Would install via brew (supabase/tap/supabase)."
        set_result supabase Skipped "" "" "Would install via brew tap"
        return
    fi
    info "Installing Supabase CLI via brew tap..."
    # Supabase's own recommended macOS method (their tap is "always up to date";
    # npm is only supported as a per-project install, not a global one).
    if "$BREW_BIN" install supabase/tap/supabase; then
        hash -r
        local sbv
        sbv=$(tool_version supabase)
        if [ -n "$sbv" ]; then
            ok "Supabase CLI installed: $sbv"
            set_result supabase Installed "$sbv" "$(command -v supabase)"
        else
            fail "brew installed supabase, but it doesn't run."
            set_result supabase Failed "" "$(command -v supabase 2>/dev/null || true)" "Installed, but supabase --version fails"
        fi
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
        vcv=$(tool_version vercel)
        vc_src=$(command -v vercel)
        if [ -n "$vcv" ]; then
            ok "vercel $vcv  ($vc_src)"
            set_result vercel AlreadyInstalled "$vcv" "$vc_src"
        else
            fail "vercel is there ($vc_src) but doesn't run."
            set_result vercel Failed "" "$vc_src" "vercel doesn't run - reinstall it (npm install -g vercel), then re-run"
        fi
        return
    fi
    if ! command -v npm >/dev/null 2>&1; then
        warn "npm not available - cannot install Vercel CLI."
        set_result vercel Failed "" "" "npm not available"
        return
    fi
    if [ "$DIAGNOSE_ONLY" -eq 1 ]; then
        ensure_npm_global_writable
        warn "vercel not found. Would install via npm."
        set_result vercel Skipped "" "" "Would install vercel via npm"
        return
    fi
    ensure_npm_global_writable
    info "Installing Vercel CLI via npm install -g vercel..."
    if npm install -g vercel; then
        hash -r
        local vcv
        if ! command -v vercel >/dev/null 2>&1; then
            fail "npm reported success but 'vercel' not on PATH."
            set_result vercel Failed "" "" "Post-install search failed"
        else
            vcv=$(tool_version vercel)
            if [ -n "$vcv" ]; then
                ok "Vercel CLI installed: $vcv"
                set_result vercel Installed "$vcv" "$(command -v vercel)"
            else
                fail "npm installed vercel, but it doesn't run."
                set_result vercel Failed "" "$(command -v vercel)" "Installed, but vercel --version fails"
            fi
        fi
    else
        fail "npm install -g vercel failed."
        set_result vercel Failed "" "" "npm install failed"
    fi
}

install_vercel

# ---------- Claude Code ----------
if [ "$SKIP_CLAUDE_CODE" -eq 0 ] && [ "$DIAGNOSE_ONLY" -eq 0 ]; then
    step "Installing Claude Code"
    # Installed earlier by Anthropic's installer but never added to PATH?
    if ! command -v claude >/dev/null 2>&1 && [ -x "$HOME/.local/bin/claude" ]; then
        ensure_path_line_in_rc "$HOME/.local/bin" || true
        hash -r
    fi
    cl_src=""; cv=""
    if command -v claude >/dev/null 2>&1; then
        cl_src=$(command -v claude)
        cv=$(tool_version claude)
    fi
    if [ -n "$cv" ]; then
        ok "Claude Code already installed: $cv  ($cl_src)"
        set_result claude AlreadyInstalled "$cv" "$cl_src"
    else
        if [ -n "$cl_src" ]; then
            warn "claude is there ($cl_src) but doesn't start - reinstalling it."
            # A broken npm copy (npm 12+ skips its setup step) would keep being
            # found first, so remove it before installing the real one.
            if is_npm_claude "$cl_src" && command -v npm >/dev/null 2>&1; then
                info "Removing the broken npm copy of Claude Code..."
                npm uninstall -g "@anthropic-ai/claude-code" || true
                hash -r
            fi
        fi
        info "Installing Claude Code with Anthropic's installer (https://claude.ai/install.sh)..."
        if install_claude_native; then
            cv=$(tool_version claude)
            if [ -z "$cv" ] && [ -x "$HOME/.local/bin/claude" ]; then
                # Something older is still found first - put ~/.local/bin in front.
                ensure_path_line_in_rc "$HOME/.local/bin" first || true
                hash -r
                cv=$(tool_version claude)
            fi
            if [ -n "$cv" ]; then
                ok "Claude Code installed: $cv  ($(command -v claude))"
                set_result claude Installed "$cv" "$(command -v claude)"
            else
                fail "Claude Code installed, but it doesn't start."
                set_result claude Failed "" "$(command -v claude 2>/dev/null || true)" "Installed, but claude --version fails - ask an assistant"
            fi
        else
            fail "Anthropic's Claude Code installer failed (no internet, or Claude isn't available in this region)."
            info "Check the internet connection, then re-run. Details: https://code.claude.com/docs/en/setup"
            set_result claude Failed "" "" "Installer failed - check the internet, then re-run"
        fi
    fi
fi

if ! has_result claude; then
    if [ "$SKIP_CLAUDE_CODE" -eq 1 ]; then
        set_result claude Skipped "" "" "Skipped via --skip-claude-code flag"
    elif [ "$DIAGNOSE_ONLY" -eq 1 ]; then
        if command -v claude >/dev/null 2>&1; then
            cv=$(tool_version claude)
            if [ -n "$cv" ]; then
                set_result claude AlreadyInstalled "$cv" "$(command -v claude)"
            else
                set_result claude Failed "" "$(command -v claude)" "claude doesn't start - a normal run reinstalls it"
            fi
        else
            set_result claude Skipped "" "" "Would install with Anthropic's installer"
        fi
    fi
fi

# ---------- Final verification (re-check every tool with --version) ----------
step "Final verification"
hash -r

reverify=(python3 node npm git gh supabase vercel)
[ "$SKIP_CLAUDE_CODE" -eq 0 ] && reverify+=(claude)

for tool in "${reverify[@]}"; do
    # Map python3 -> python in results
    key="$tool"
    [ "$tool" = "python3" ] && key="python"
    if command -v "$tool" >/dev/null 2>&1; then
        v=$(tool_version "$tool")
        if ! has_result "$key"; then
            if [ -n "$v" ]; then
                set_result "$key" AlreadyInstalled "$v" "$(command -v "$tool")"
            else
                set_result "$key" Failed "" "$(command -v "$tool")" "Found, but didn't report a version (broken install?)"
            fi
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
if [ "$DIAGNOSE_ONLY" -eq 0 ]; then
    say "  Backups: $BACKUP_DIR" "$C_GRAY"
    say "=================================================================" "$C_CYAN"
    say "  RAISE YOUR HAND and wait for a workshop assistant to check" "$C_YELLOW"
    say "  this screen with you BEFORE you close this window." "$C_YELLOW"
fi
say "=================================================================" "$C_CYAN"
echo ""
# (Session log path is printed by the EXIT trap when LOG_PATH is set.)
