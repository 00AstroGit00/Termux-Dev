#!/data/data/com.termux/files/usr/bin/bash
#
# Termux setup / enhancement script
# Hardened and made idempotent for current apt/dpkg-based Termux.
#

set -Eeuo pipefail
IFS=$'\n\t'

# -----------------------------
# Configuration
# -----------------------------
INSTALL_ROOT_REPO="${INSTALL_ROOT_REPO:-1}"
INSTALL_X11_REPO="${INSTALL_X11_REPO:-1}"
INSTALL_TUR_REPO="${INSTALL_TUR_REPO:-1}"
INSTALL_TERMUXVOID="${INSTALL_TERMUXVOID:-1}"
INSTALL_ZSH="${INSTALL_ZSH:-1}"
INSTALL_SSH="${INSTALL_SSH:-1}"
AUTO_CHANGE_REPO="${AUTO_CHANGE_REPO:-0}"

# Kernel-managed concurrency lock (immune to stale locks on crash/kill)
LOCK_FILE="${TMPDIR:-${PREFIX:-/data/data/com.termux/files/usr}/tmp}/termux-base.lock"
exec 200>"$LOCK_FILE"
if ! flock -n 200; then
    printf '\033[0;31m[ERROR]\033[0m Another instance of 01-termux-base.sh is already running.\n' >&2
    exit 1
fi

SCRIPT_NAME="$(basename "$0")"
WORKDIR="${TMPDIR:-${PREFIX:-/data/data/com.termux/files/usr}/tmp}/${SCRIPT_NAME%.*}-$$"
mkdir -p "$WORKDIR"
trap 'rm -rf "$WORKDIR"' EXIT INT TERM

# -----------------------------
# Colors / logging
# -----------------------------
RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
BLUE=$'\033[0;34m'
CYAN=$'\033[0;36m'
NC=$'\033[0m'

info()    { printf '%s[INFO]%s %s\n' "$BLUE" "$NC" "$*"; }
success() { printf '%s[SUCCESS]%s %s\n' "$GREEN" "$NC" "$*"; }
warn()    { printf '%s[WARNING]%s %s\n' "$YELLOW" "$NC" "$*"; }
error()   { printf '%s[ERROR]%s %s\n' "$RED" "$NC" "$*" >&2; }
die()     { error "$*"; exit 1; }

run_optional() {
    local description="$1"
    shift
    info "$description"
    if "$@"; then
        success "$description completed."
        return 0
    fi
    warn "$description failed; continuing."
    return 0
}

run_required() {
    local description="$1"
    shift
    info "$description"
    "$@" || die "$description failed."
    success "$description completed."
}

# -----------------------------
# Error diagnostics
# -----------------------------
on_error() {
    local rc=$?
    local line="${BASH_LINENO[0]:-unknown}"
    error "Setup stopped at line ${line} with exit code ${rc}."
    error "Command: ${BASH_COMMAND:-unknown}"
    error "Review the output immediately above this message."
    exit "$rc"
}
trap on_error ERR

# -----------------------------
# Termux validation
# -----------------------------
[[ -n "${PREFIX:-}" ]] || die "PREFIX is not set. This does not look like a Termux environment."
TERMUX_VERSION="${TERMUX_VERSION:-unknown}"
[[ -x "$PREFIX/bin/pkg" ]] || die "Termux package manager was not found at $PREFIX/bin/pkg."

# Current Termux is apt/dpkg based in the normal setup.
if [[ "${TERMUX_APP_PACKAGE_MANAGER:-apt}" != "apt" ]]; then
    die "This script expects the standard apt/dpkg Termux package manager."
fi

info "Detected Termux ${TERMUX_VERSION}."
info "Architecture: $(dpkg --print-architecture 2>/dev/null || printf 'unknown')"

# -----------------------------
# Prerequisites
# -----------------------------
run_required "Refreshing the Termux package index" pkg update
run_required "Upgrading existing Termux packages" pkg upgrade -y
run_required "Installing bootstrap tools" pkg install -y \
    termux-tools \
    apt \
    bash \
    ca-certificates \
    curl \
    wget \
    git

# -----------------------------
# Repository handling
# -----------------------------
if command -v termux-change-repo >/dev/null 2>&1; then
    if [[ "$AUTO_CHANGE_REPO" == "1" ]]; then
        info "Opening Termux mirror selector..."
        termux-change-repo || warn "Mirror selection was cancelled or failed."
    else
        info "Skipping interactive mirror selection (AUTO_CHANGE_REPO=0)."
        info "Run 'termux-change-repo' manually when you need to change mirrors."
    fi
fi

# Official additional repositories. "unstable-repo" is intentionally not used:
# it was retired/merged into the main repository years ago.
if [[ "$INSTALL_ROOT_REPO" == "1" ]]; then
    run_optional "Installing official Termux root repository" pkg install -y root-repo
fi

if [[ "$INSTALL_X11_REPO" == "1" ]]; then
    run_optional "Installing official Termux X11 repository" pkg install -y x11-repo
fi

# TUR is a community repository, not an official Termux repository.
if [[ "$INSTALL_TUR_REPO" == "1" ]]; then
    run_optional "Installing the Termux User Repository (TUR)" pkg install -y tur-repo
fi

# termux-apt-repo is a repository-building/publishing tool, NOT a repository
# subscription package. It is deliberately not installed here.
#
# Final index refresh after optional repositories.
run_required "Refreshing package indexes after repository changes" pkg update

# -----------------------------
# Storage
# -----------------------------
info "Requesting shared-storage permission..."
if command -v termux-setup-storage >/dev/null 2>&1; then
    termux-setup-storage || warn "Storage setup returned a non-zero status. If this is the first run, complete Android's permission prompt."
else
    warn "termux-setup-storage is unavailable."
fi

# -----------------------------
# Core developer / CLI packages
# -----------------------------
run_required "Installing core development and CLI packages" pkg install -y \
    build-essential \
    clang \
    cmake \
    make \
    pkg-config \
    openssl \
    git \
    gh \
    python \
    python-numpy \
    zsh \
    nano \
    vim \
    less \
    tree \
    jq \
    ripgrep \
    fd \
    unzip \
    zip \
    tar \
    gzip \
    xz-utils \
    rsync

# -----------------------------
# Optional TermuxVoid
# -----------------------------
install_termuxvoid() {
    local list_file="${PREFIX:-/data/data/com.termux/files/usr}/etc/apt/sources.list.d/termuxvoid.list"
    if [[ -f "$list_file" ]] && command -v tvpkg >/dev/null 2>&1; then
        info "TermuxVoid repository and tvpkg are already configured; skipping remote installer."
        return 0
    fi

    local url="https://raw.githubusercontent.com/termuxvoid/repo/main/install.sh"
    local installer="$WORKDIR/termuxvoid-install.sh"

    info "Downloading the current TermuxVoid installer..."
    curl -fL --retry 3 --retry-delay 2 --proto '=https' --tlsv1.2 "$url" -o "$installer"

    [[ -s "$installer" ]] || {
        error "Downloaded TermuxVoid installer is empty."
        return 1
    }

    # Basic sanity checks prevent accidentally feeding an HTML error page to bash.
    grep -qE '^#!.*(bash|sh)' "$installer" || {
        error "TermuxVoid installer does not look like a shell script."
        return 1
    }

    chmod 700 "$installer"
    bash "$installer" -s
}

if [[ "$INSTALL_TERMUXVOID" == "1" ]]; then
    run_optional "Installing the current TermuxVoid repository" install_termuxvoid
else
    info "TermuxVoid installation disabled (INSTALL_TERMUXVOID=0)."
fi

# Refresh package indexes after TermuxVoid if it was added.
run_optional "Refreshing package indexes after optional repositories" pkg update

# -----------------------------
# Zsh / Termux-zsh
# -----------------------------
install_termux_zsh() {
    local repo="https://github.com/Sohil876/Termux-zsh.git"
    local clone_dir="$WORKDIR/Termux-zsh"

    git clone --depth 1 "$repo" "$clone_dir"
    [[ -f "$clone_dir/setup.sh" ]] || {
        error "Termux-zsh repository was cloned, but setup.sh is missing."
        return 1
    }

    # The upstream installer expects menu choice 1 for installation.
    printf '1\n' | bash "$clone_dir/setup.sh"
}

if [[ "$INSTALL_ZSH" == "1" ]]; then
    run_optional "Installing/configuring Termux-zsh" install_termux_zsh
else
    info "Termux-zsh installation disabled (INSTALL_ZSH=0)."
fi

# -----------------------------
# SSH (native Termux OpenSSH)
# -----------------------------
if [[ "$INSTALL_SSH" == "1" ]]; then
    run_required "Installing OpenSSH" pkg install -y openssh

    SSHD_CONFIG="$PREFIX/etc/ssh/sshd_config"
    if [[ -f "$SSHD_CONFIG" ]]; then
        cp -f "$SSHD_CONFIG" "$SSHD_CONFIG.backup.$(date +%Y%m%d%H%M%S)"
    fi

    # Termux's common default SSH port is 8022.
    if [[ -f "$SSHD_CONFIG" ]]; then
        sed -i -E 's/^[#[:space:]]*Port[[:space:]]+[0-9]+/Port 8022/' "$SSHD_CONFIG"
        if ! grep -qE '^[[:space:]]*Port[[:space:]]+8022([[:space:]]|$)' "$SSHD_CONFIG"; then
            printf '\nPort 8022\n' >> "$SSHD_CONFIG"
        fi
    fi

    if command -v ssh-keygen >/dev/null 2>&1; then
        mkdir -p "$HOME/.ssh"
        chmod 700 "$HOME/.ssh"
    fi

    success "OpenSSH installed. Run 'passwd' once to set the SSH password, then use 'sshd' to start the server."
else
    info "SSH installation disabled (INSTALL_SSH=0)."
fi

# -----------------------------
# Shell rc enhancements (.zshrc & .bashrc)
# -----------------------------
BACKUP_DIR="$HOME/.config/termux-setup/backups"
mkdir -p "$BACKUP_DIR"

BEGIN_MARKER="# >>> TERMUX-SETUP ENHANCEMENTS >>>"
END_MARKER="# <<< TERMUX-SETUP ENHANCEMENTS <<<"

apply_shell_enhancements() {
    local rc="$1"
    local shell_name="$2"
    local backup_name
    backup_name="$(basename "$rc")"

    if [[ -f "$rc" ]]; then
        cp -f "$rc" "$BACKUP_DIR/${backup_name}.$(date +%Y%m%d%H%M%S).bak"
        success "Backed up existing $rc to $BACKUP_DIR."
    else
        touch "$rc"
    fi

    # Remove previous generated block cleanly.
    if grep -qF "$BEGIN_MARKER" "$rc"; then
        awk -v begin="$BEGIN_MARKER" -v end="$END_MARKER" '
            $0 == begin {skip=1; next}
            $0 == end   {skip=0; next}
            !skip       {print}
        ' "$rc" > "$WORKDIR/${backup_name}.clean"
        mv "$WORKDIR/${backup_name}.clean" "$rc"
    fi

    cat >> "$rc" <<EOF

# >>> TERMUX-SETUP ENHANCEMENTS >>>

# PATH & Environment
export PATH="\$HOME/.local/bin:\$HOME/.npm-global/bin:\$HOME/bin:\$PREFIX/bin:\$PATH"
export npm_config_prefix="\$HOME/.npm-global"
export PIP_REQUIRE_VIRTUALENV=false

# Editors
export EDITOR="nano"
export VISUAL="nano"

# Navigation
alias ..='cd ..'
alias ...='cd ../..'
alias home='cd "\$HOME"'
alias root='cd "\$PREFIX/../.."'
alias download='cd "\$HOME/storage/downloads" 2>/dev/null || cd "\$HOME/storage/shared/Download"'

# Listing
alias ll='ls -alF --color=auto'
alias la='ls -A --color=auto'
alias l='ls -CF --color=auto'

# Package management
alias repo='termux-change-repo'
alias update='pkg update && pkg upgrade -y'
alias i='pkg install -y'
alias r='pkg uninstall -y'
alias search='pkg search'
alias clean='pkg clean'
alias c='clear'
alias q='exit'

# Git
alias gs='git status'
alias ga='git add'
alias gc='git commit -m'
alias gp='git push'
alias gl='git log --oneline --decorate -20'
alias gcl='git clone'
alias gd='git diff'

# SSH
alias ssh-start='sshd'
alias ssh-stop='pkill sshd'
alias ssh-status="pgrep -x sshd >/dev/null && echo 'SSH server is running' || echo 'SSH server is not running'"

backup() {
    if [[ -z "\${1:-}" ]]; then
        echo "Usage: backup <file_or_directory>"
        return 1
    fi
    local stamp
    stamp="\$(date +%Y%m%d%H%M%S)"
    cp -a -- "\$1" "\${1}_backup_\${stamp}"
    echo "Backup created: \${1}_backup_\${stamp}"
}

extract() {
    if [[ -z "\${1:-}" ]]; then
        echo "Usage: extract <archive_file>"
        return 1
    fi

    local file="\$1"
    if [[ ! -f "\$file" ]]; then
        echo "\$file is not a valid file"
        return 1
    fi

    case "\$file" in
        *.tar.bz2|*.tbz2) tar xjf "\$file" ;;
        *.tar.gz|*.tgz)   tar xzf "\$file" ;;
        *.tar.xz)         tar xJf "\$file" ;;
        *.tar)            tar xf "\$file" ;;
        *.zip)            unzip "\$file" ;;
        *.rar)            command -v unrar >/dev/null && unrar x "\$file" || echo "Install unrar first." ;;
        *.7z)             command -v 7z >/dev/null && 7z x "\$file" || echo "Install p7zip first." ;;
        *) echo "Cannot extract \$file - unknown format"; return 1 ;;
    esac
}

pkg-search() {
    if [[ -z "\${1:-}" ]]; then
        echo "Usage: pkg-search <package_name>"
        return 1
    fi
    pkg search "\$1"
}

mkcd() {
    if [[ -z "\${1:-}" ]]; then
        echo "Usage: mkcd <directory_name>"
        return 1
    fi
    mkdir -p -- "\$1" && cd -- "\$1"
}

# Optional bat integration
if command -v bat >/dev/null 2>&1; then
    alias cat='bat --style=plain'
fi
EOF

    if [[ "$shell_name" == "zsh" ]]; then
        cat >> "$rc" <<'EOF'
alias zshrc='nano "$HOME/.zshrc"'

# Plugin integration when installed by a zsh framework.
if [[ -f "$PREFIX/share/zsh-autosuggestions/zsh-autosuggestions.zsh" ]]; then
    source "$PREFIX/share/zsh-autosuggestions/zsh-autosuggestions.zsh"
fi

if [[ -f "$PREFIX/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" ]]; then
    source "$PREFIX/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
fi

HISTSIZE=10000
SAVEHIST=10000
HISTFILE="$HOME/.zsh_history"
EOF
    else
        cat >> "$rc" <<'EOF'
alias bashrc='nano "$HOME/.bashrc"'
HISTSIZE=10000
HISTFILESIZE=20000
HISTFILE="$HOME/.bash_history"
EOF
    fi

    cat >> "$rc" <<'EOF'

# <<< TERMUX-SETUP ENHANCEMENTS <<<
EOF

    success "Termux enhancements have been integrated into $rc."
}

apply_shell_enhancements "$HOME/.zshrc" "zsh"
apply_shell_enhancements "$HOME/.bashrc" "bash"

# -----------------------------
# Final validation
# -----------------------------
info "Validating generated shell configuration syntax..."
if command -v zsh >/dev/null 2>&1 && [[ -f "$HOME/.zshrc" ]]; then
    zsh -n "$HOME/.zshrc" || die ".zshrc syntax validation failed."
    success ".zshrc syntax validation passed."
fi
if [[ -f "$HOME/.bashrc" ]]; then
    bash -n "$HOME/.bashrc" || die ".bashrc syntax validation failed."
    success ".bashrc syntax validation passed."
fi

# Test critical commands exist.
for cmd in pkg git curl zsh sshd; do
    if command -v "$cmd" >/dev/null 2>&1; then
        success "Verified command: $cmd"
    else
        warn "Command not found after setup: $cmd"
    fi
done

echo
success "Termux setup completed."
printf '%s\n' \
    "Next steps:" \
    "  1. Restart Termux." \
    "  2. Run: source ~/.zshrc" \
    "  3. Run: passwd" \
    "  4. Run: sshd" \
    "  5. Check: ssh-status" \
    "" \
    "Optional:" \
    "  AUTO_CHANGE_REPO=1 bash $SCRIPT_NAME" \
    "  INSTALL_TERMUXVOID=0 bash $SCRIPT_NAME" \
    "  INSTALL_TUR_REPO=0 bash $SCRIPT_NAME"
