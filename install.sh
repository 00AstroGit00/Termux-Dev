#!/data/data/com.termux/files/usr/bin/bash
#
# ==============================================================================
# Termux Developer & AI Suite - One-Line Installer & TUI Launcher
# ==============================================================================
# Usage (One-Liner):
#   pkg update -y && pkg install -y curl && bash -c "$(curl -fsSL https://raw.githubusercontent.com/00AstroGit00/Termux-Dev/main/install.sh)"
#
# Or locally:
#   chmod +x install.sh && ./install.sh
# ==============================================================================

set -Eeuo pipefail

REPO_URL="https://github.com/00AstroGit00/Termux-Dev.git"
INSTALL_DIR="${HOME}/.termux-suite"
BIN_DIR="${PREFIX:-/data/data/com.termux/files/usr}/bin"
LOCAL_BIN="${HOME}/.local/bin"

# Colors
CYAN=$'\033[0;36m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
RED=$'\033[0;31m'
BOLD=$'\033[1m'
NC=$'\033[0m'

info()    { printf '%s[INFO]%s %s\n' "$CYAN" "$NC" "$*"; }
success() { printf '%s[SUCCESS]%s %s\n' "$GREEN" "$NC" "$*"; }
warn()    { printf '%s[WARNING]%s %s\n' "$YELLOW" "$NC" "$*" >&2; }
die()     { printf '%s[ERROR]%s %s\n' "$RED" "$NC" "$*" >&2; exit 1; }

# Termux sanity check
[[ -n "${PREFIX:-}" ]] || die "PREFIX not found. Please run this inside Termux on Android."

NO_LAUNCH=0
for arg in "$@"; do
    case "$arg" in
        --no-launch|--install-only)
            NO_LAUNCH=1
            ;;
    esac
done

printf '\n%s=======================================================%s\n' "$BOLD$CYAN" "$NC"
printf '%s   Termux Developer & AI Suite: Bootstrap Installer    %s\n' "$BOLD$GREEN" "$NC"
printf '%s=======================================================%s\n\n' "$BOLD$CYAN" "$NC"

# Ensure core prerequisites are present
info "Checking core prerequisites (git, curl, dialog)..."
for pkg_name in git curl dialog; do
    if ! command -v "$pkg_name" >/dev/null 2>&1; then
        info "Installing $pkg_name..."
        pkg install -y "$pkg_name" || true
    fi
done

# Resolve suite repository directory
SUITE_DIR=""
if [[ -f "./setup.sh" && -f "./test-suite.sh" ]]; then
    SUITE_DIR="$(pwd)"
    info "Running from existing local workspace: $SUITE_DIR"
elif [[ -d "$HOME/Termux-Dev" && -f "$HOME/Termux-Dev/setup.sh" ]]; then
    SUITE_DIR="$HOME/Termux-Dev"
    info "Using existing workspace at: $SUITE_DIR"
else
    SUITE_DIR="$INSTALL_DIR"
    if [[ -d "$SUITE_DIR/.git" ]]; then
        info "Updating existing installation at $SUITE_DIR..."
        git -C "$SUITE_DIR" pull --ff-only || true
    else
        info "Cloning repository into $SUITE_DIR..."
        mkdir -p "$(dirname "$SUITE_DIR")"
        git clone --depth 1 "$REPO_URL" "$SUITE_DIR"
    fi
fi

# Install global executable launchers
info "Installing executable CLI launchers (termux-suite & tsuite)..."
mkdir -p "$BIN_DIR" "$LOCAL_BIN"

if [[ ! -f "$SUITE_DIR/bin/termux-suite" ]]; then
    mkdir -p "$SUITE_DIR/bin"
    cat > "$SUITE_DIR/bin/termux-suite" <<'EOF'
#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail
SUITE_DIR="${TERMUX_SUITE_DIR:-}"
if [[ -z "$SUITE_DIR" || ! -f "$SUITE_DIR/setup.sh" ]]; then
    SELF_PATH="$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")"
    SELF_DIR="$(cd "$(dirname "$SELF_PATH")" && pwd)"
    if [[ -f "$SELF_DIR/setup.sh" ]]; then
        SUITE_DIR="$SELF_DIR"
    elif [[ -f "$SELF_DIR/../setup.sh" ]]; then
        SUITE_DIR="$(cd "$SELF_DIR/.." && pwd)"
    elif [[ -f "$HOME/Termux-Dev/setup.sh" ]]; then
        SUITE_DIR="$HOME/Termux-Dev"
    elif [[ -f "$HOME/.termux-suite/setup.sh" ]]; then
        SUITE_DIR="$HOME/.termux-suite"
    fi
fi
if [[ -z "$SUITE_DIR" || ! -f "$SUITE_DIR/setup.sh" ]]; then
    printf '\033[0;31m[ERROR]\033[0m Could not locate Termux Suite repository.\n' >&2
    exit 1
fi
exec bash "$SUITE_DIR/setup.sh" "$@"
EOF
fi

chmod 755 "$SUITE_DIR/bin/termux-suite"
cp -f "$SUITE_DIR/bin/termux-suite" "$BIN_DIR/termux-suite"
cp -f "$SUITE_DIR/bin/termux-suite" "$BIN_DIR/tsuite"
cp -f "$SUITE_DIR/bin/termux-suite" "$LOCAL_BIN/termux-suite"
cp -f "$SUITE_DIR/bin/termux-suite" "$LOCAL_BIN/tsuite"

if [[ -f "$SUITE_DIR/bin/termux-apk-build" ]]; then
    chmod 755 "$SUITE_DIR/bin/termux-apk-build"
    cp -f "$SUITE_DIR/bin/termux-apk-build" "$BIN_DIR/termux-apk-build"
    cp -f "$SUITE_DIR/bin/termux-apk-build" "$BIN_DIR/apk-build"
    cp -f "$SUITE_DIR/bin/termux-apk-build" "$LOCAL_BIN/termux-apk-build"
    cp -f "$SUITE_DIR/bin/termux-apk-build" "$LOCAL_BIN/apk-build"
    chmod 755 "$BIN_DIR/termux-apk-build" "$BIN_DIR/apk-build" "$LOCAL_BIN/termux-apk-build" "$LOCAL_BIN/apk-build"
fi

chmod 755 "$BIN_DIR/termux-suite" "$BIN_DIR/tsuite" "$LOCAL_BIN/termux-suite" "$LOCAL_BIN/tsuite"

command -v termux-fix-shebang >/dev/null 2>&1 && {
    termux-fix-shebang "$BIN_DIR/termux-suite" "$BIN_DIR/tsuite" "$LOCAL_BIN/termux-suite" "$LOCAL_BIN/tsuite" 2>/dev/null || true
    [[ -f "$BIN_DIR/termux-apk-build" ]] && termux-fix-shebang "$BIN_DIR/termux-apk-build" "$BIN_DIR/apk-build" "$LOCAL_BIN/termux-apk-build" "$LOCAL_BIN/apk-build" 2>/dev/null || true
}

# Install shell completions for Zsh and Bash
if [[ -d "$SUITE_DIR/completions" ]]; then
    info "Installing shell completions for Zsh and Bash..."
    zsh_site="${PREFIX:-/data/data/com.termux/files/usr}/share/zsh/site-functions"
    bash_comp="${PREFIX:-/data/data/com.termux/files/usr}/etc/bash_completion.d"
    mkdir -p "$zsh_site" "$bash_comp"
    [[ -f "$SUITE_DIR/completions/_tsuite" ]] && cp -f "$SUITE_DIR/completions/_tsuite" "$zsh_site/_tsuite" && cp -f "$SUITE_DIR/completions/_tsuite" "$zsh_site/_termux-suite"
    [[ -f "$SUITE_DIR/completions/_termux-apk-build" ]] && cp -f "$SUITE_DIR/completions/_termux-apk-build" "$zsh_site/_termux-apk-build" && cp -f "$SUITE_DIR/completions/_termux-apk-build" "$zsh_site/_apk-build"
    [[ -f "$SUITE_DIR/completions/tsuite.bash" ]] && cp -f "$SUITE_DIR/completions/tsuite.bash" "$bash_comp/tsuite"
fi

success "Global CLI commands installed:"
printf '  - %s%stermux-suite%s     (opens interactive TUI)\n' "$BOLD$GREEN" "$NC" "$NC"
printf '  - %s%stsuite%s            (quick alias)\n' "$BOLD$GREEN" "$NC" "$NC"
printf '  - %s%stermux-apk-build%s  (zero-Gradle instant APK builder)\n' "$BOLD$GREEN" "$NC" "$NC"
printf '  - %s%sapk-build%s         (quick alias)\n\n' "$BOLD$GREEN" "$NC" "$NC"

# Launch interactive TUI immediately if running in an interactive terminal and not disabled
if [[ "$NO_LAUNCH" -eq 0 && -t 0 ]]; then
    info "Launching Termux Suite Interactive TUI..."
    exec "$BIN_DIR/termux-suite" "$@"
fi


