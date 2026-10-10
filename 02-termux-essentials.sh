#!/data/data/com.termux/files/usr/bin/bash
#
# Termux Essentials / Developer Environment Bootstrap
# Optimized for modern Termux on Android, including ARM64.
#
# Design goals:
#   - idempotent
#   - fast/batched package installation
#   - no obsolete packages
#   - repository-aware
#   - architecture-aware
#   - separates essentials from heavyweight/optional stacks
#   - never aborts merely because one optional package is unavailable
#
# Usage:
#   bash termux_essentials_optimized.sh
#   PROFILE=full bash termux_essentials_optimized.sh
#   PROFILE=server bash termux_essentials_optimized.sh
#   INSTALL_ROOT=1 bash termux_essentials_optimized.sh
#

set -Eeuo pipefail
IFS=$'\n\t'

# -----------------------------
# Configuration
# -----------------------------
PROFILE="${PROFILE:-essentials}"

INSTALL_X11="${INSTALL_X11:-1}"
INSTALL_ROOT="${INSTALL_ROOT:-0}"
INSTALL_TSU="${INSTALL_TSU:-auto}"
INSTALL_API="${INSTALL_API:-1}"
INSTALL_SERVICES="${INSTALL_SERVICES:-1}"
INSTALL_HEAVY="${INSTALL_HEAVY:-0}"
UPGRADE_SYSTEM="${UPGRADE_SYSTEM:-1}"

# -----------------------------
# Logging
# -----------------------------
RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
BLUE=$'\033[0;34m'
CYAN=$'\033[0;36m'
NC=$'\033[0m'

info()    { printf '%s[INFO]%s %s\n' "$BLUE" "$NC" "$*"; }
success() { printf '%s[SUCCESS]%s %s\n' "$GREEN" "$NC" "$*"; }
warn()    { printf '%s[WARNING]%s %s\n' "$YELLOW" "$NC" "$*" >&2; }
error()   { printf '%s[ERROR]%s %s\n' "$RED" "$NC" "$*" >&2; }
die()     { error "$*"; exit 1; }

on_error() {
    local rc=$?
    error "Command failed (exit ${rc}) at line ${BASH_LINENO[0]:-unknown}: ${BASH_COMMAND:-unknown}"
    exit "$rc"
}
trap on_error ERR

# -----------------------------
# Termux validation
# -----------------------------
[[ -n "${PREFIX:-}" ]] || die "PREFIX is not set. Run this script inside Termux."
[[ -x "$PREFIX/bin/pkg" ]] || die "Termux pkg was not found."
[[ -x "$PREFIX/bin/apt" ]] || die "Termux apt was not found."

ARCH="$(dpkg --print-architecture 2>/dev/null || uname -m)"
ANDROID_ABI="$(getprop ro.product.cpu.abi 2>/dev/null || true)"
TERMUX_VERSION="${TERMUX_VERSION:-unknown}"

info "Termux version: ${TERMUX_VERSION}"
info "dpkg architecture: ${ARCH}"
[[ -n "$ANDROID_ABI" ]] && info "Android ABI: ${ANDROID_ABI}"

# -----------------------------
# Lock to one running instance (flock: kernel-managed, immune to stale locks)
# -----------------------------
LOCK_FILE="${TMPDIR:-$PREFIX/tmp}/termux-essentials.lock"
exec 200>"$LOCK_FILE"
if ! flock -n 200; then
    die "Another instance of 02-termux-essentials.sh appears to be running (locked by flock on $LOCK_FILE)."
fi

# -----------------------------
# Package groups
# -----------------------------
# These are deliberately grouped by purpose instead of being one giant list.
# Duplicate packages from the original script have been removed.

CORE_PKGS=(
    bash
    bash-completion
    coreutils
    file
    findutils
    grep
    sed
    gawk
    tar
    gzip
    xz-utils
    zstd
    unzip
    zip
    less
    man
    tree
    rsync
    wget
    curl
    openssl-tool
    ca-certificates
    jq
    vim
    micro
    nano
    tmux
)

DEV_PKGS=(
    git
    gh
    binutils
    clang
    make
    cmake
    pkg-config
    rust
    golang
    perl
    python
    python-pip
    sqlite
)

NETWORK_PKGS=(
    dnsutils
    nmap
    net-tools
    gping
    wireguard-tools
    rclone
    gnupg
    torsocks
    tor
)

MEDIA_DOC_PKGS=(
    ffmpeg
    ghostscript
    exiftool
    qpdf
    html2text
    tidy
    icoutils
    html-xml-utils
    recode
    mpg123
    mpv
    wget2
    axel
    pv
    moreutils
    pastebinit
)

SHELL_TOOLS_PKGS=(
    fish
    lf
    expect
)

WEB_PKGS=(
    nginx
    php
    php-fpm
    apache2
    hugo
    httrack
)

DATABASE_PKGS=(
    mariadb
    postgresql
)

SERVICE_PKGS=(
    termux-services
    cronie
)

OPTIONAL_PKGS=(
    ncdu
    cpulimit
    secure-delete
    busybox
    proot
    proot-distro
    links
    irssi
    newsboat
    tigervnc
    openbox
)

# Legacy/redundant entries intentionally removed from the original:
#   python2      -> obsolete/undesirable alongside current Python
#   neofetch     -> use fastfetch
#   htop-legacy  -> use htop
#   nmap-ncat    -> replaced/provided by nmap in current Termux packaging
#   duplicated tsu
#   duplicated package/repository entries
#
# X11/root repositories are handled separately because they ADD repositories;
# they are not ordinary application packages.

# -----------------------------
# Repository management
# -----------------------------
ensure_repo() {
    local repo_pkg="$1"
    if dpkg-query -W -f='${Status}' "$repo_pkg" 2>/dev/null | grep -q 'install ok installed'; then
        info "${repo_pkg} already installed."
        return 0
    fi

    info "Installing repository package: ${repo_pkg}"
    pkg install -y "$repo_pkg"
    success "${repo_pkg} installed."
}

pkg update

if [[ "$INSTALL_X11" == "1" ]]; then
    ensure_repo x11-repo
fi

if [[ "$INSTALL_ROOT" == "1" ]]; then
    ensure_repo root-repo
fi

# Repository packages change APT sources, so refresh once afterward.
pkg update

if [[ "$UPGRADE_SYSTEM" == "1" ]]; then
    info "Upgrading currently installed Termux packages..."
    pkg upgrade -y
fi

# -----------------------------
# Package availability filtering
# -----------------------------
declare -a AVAILABLE=()
declare -a SKIPPED=()

package_available() {
    local pkg="$1"
    local candidate

    # apt-cache show can still return package metadata for packages that are
    # no longer installable. Check the actual APT candidate instead.
    candidate="$(apt-cache policy "$pkg" 2>/dev/null | awk '/^[[:space:]]*Candidate:/ {print $2; exit}')"

    [[ -n "$candidate" && "$candidate" != "(none)" ]]
}

add_available() {
    local pkg
    for pkg in "$@"; do
        if package_available "$pkg"; then
            AVAILABLE+=("$pkg")
        else
            SKIPPED+=("$pkg")
        fi
    done
}

install_group() {
    local group_name="$1"
    shift
    local -a packages=("$@")
    local -a old_available=("${AVAILABLE[@]}")
    AVAILABLE=()

    add_available "${packages[@]}"

    if (( ${#AVAILABLE[@]} == 0 )); then
        warn "No currently available packages from group: ${group_name}"
        AVAILABLE=("${old_available[@]}")
        return 0
    fi

    info "Installing ${group_name}: ${#AVAILABLE[@]} packages..."
    pkg install -y "${AVAILABLE[@]}"
    success "${group_name} installed."

    # Preserve previous availability list if needed by callers.
    AVAILABLE=("${old_available[@]}")
}

# -----------------------------
# Essentials profile
# -----------------------------
install_group "core CLI tools" "${CORE_PKGS[@]}"
install_group "developer toolchain" "${DEV_PKGS[@]}"

# Modern device-friendly monitoring/system-info tools.
# htop/neofetch are not forced if unavailable; fastfetch is preferred.
MONITOR_PKGS=(htop fastfetch)
install_group "system monitoring and information tools" "${MONITOR_PKGS[@]}"

install_group "networking tools" "${NETWORK_PKGS[@]}"

# Current Termux packages build ncat/ncat-like functionality as part of the
# nmap package. The former standalone nmap-ncat package is replaced by nmap.
if command -v nmap >/dev/null 2>&1; then
    success "nmap installed: $(nmap --version 2>/dev/null | head -n 1)"
    if command -v ncat >/dev/null 2>&1; then
        success "ncat installed: $(command -v ncat)"
    elif command -v netcat-nmap >/dev/null 2>&1; then
        success "netcat-nmap installed: $(command -v netcat-nmap)"
    else
        warn "nmap is installed but ncat/netcat-nmap was not found; check the package contents."
    fi
fi

install_group "media/document tools" "${MEDIA_DOC_PKGS[@]}"
install_group "shell/terminal tools" "${SHELL_TOOLS_PKGS[@]}"
install_group "general optional utilities" "${OPTIONAL_PKGS[@]}"

# -----------------------------
# Node.js: Handled exclusively by 03-termux-node-toolchain.sh to prevent version/prefix collision
# -----------------------------

# -----------------------------
# Termux API
# -----------------------------
if [[ "$INSTALL_API" == "1" ]]; then
    if package_available termux-api; then
        pkg install -y termux-api
        success "Termux:API command package installed."
    else
        warn "termux-api package is not available from the current repositories."
    fi

    if command -v cmd >/dev/null 2>&1 && \
       cmd package list packages 2>/dev/null | grep -q '^package:com.termux.api$'; then
        success "Termux:API Android companion app detected."
    else
        warn "Termux:API Android companion app was not detected. The CLI package alone cannot access Android APIs."
    fi
fi

# -----------------------------
# Root tooling
# -----------------------------
if [[ "$INSTALL_TSU" == "1" || "$INSTALL_TSU" == "auto" ]]; then
    if [[ "$INSTALL_TSU" == "auto" ]]; then
        if command -v su >/dev/null 2>&1; then
            INSTALL_TSU=1
        else
            INSTALL_TSU=0
        fi
    fi

    if [[ "$INSTALL_TSU" == "1" ]]; then
        if package_available tsu; then
            pkg install -y tsu
            success "tsu installed."
        else
            warn "tsu is not available in the currently configured repositories."
        fi
    else
        info "Skipping tsu because no su binary was detected."
    fi
fi

# -----------------------------
# Services
# -----------------------------
if [[ "$INSTALL_SERVICES" == "1" ]]; then
    install_group "Termux service management" "${SERVICE_PKGS[@]}"

    if command -v sv >/dev/null 2>&1; then
        info "termux-services is installed. Restart Termux to start its service daemon."
        info "Use 'sv-enable <service>' or 'sv up <service>' for individual services."
    fi
fi

# -----------------------------
# Full profile
# -----------------------------
if [[ "$PROFILE" == "full" || "$PROFILE" == "server" || "$INSTALL_HEAVY" == "1" ]]; then
    install_group "web/server stack" "${WEB_PKGS[@]}"
    install_group "database stack" "${DATABASE_PKGS[@]}"
fi

# -----------------------------
# Architecture-specific QEMU
# -----------------------------
#
# qemu-system-x86-64-headless has known issues on some 32-bit ARM Termux
# installations. Do not attempt it on ARM32.
#
if [[ "$PROFILE" == "full" || "$INSTALL_HEAVY" == "1" ]]; then
    case "$ARCH" in
        arm64|aarch64)
            QEMU_PKGS=(qemu-utils qemu-common qemu-system-x86-64-headless)
            install_group "QEMU virtualization tools (ARM64)" "${QEMU_PKGS[@]}"
            ;;
        amd64|x86_64)
            QEMU_PKGS=(qemu-utils qemu-common qemu-system-x86-64-headless)
            install_group "QEMU virtualization tools (x86-64)" "${QEMU_PKGS[@]}"
            ;;
        *)
            warn "Skipping qemu-system-x86-64-headless on architecture '${ARCH}'."
            ;;
    esac
fi

# -----------------------------
# Post-install cleanup
# -----------------------------
info "Cleaning downloaded package archives..."
apt-get clean || true

# Remove package lists that are not needed beyond the current cache operation.
# Do NOT delete Termux's package lists themselves; APT needs them for later use.

# -----------------------------
# PATH / shell conveniences
# -----------------------------
ZSHRC="$HOME/.zshrc"
BASHRC="$HOME/.bashrc"

for rc in "$ZSHRC" "$BASHRC"; do
    touch "$rc"

    line='export PATH="$HOME/.local/bin:$HOME/bin:$PATH"'
    grep -qxF "$line" "$rc" || printf '%s\n' "$line" >> "$rc"

    line='export PIP_REQUIRE_VIRTUALENV=false'
    grep -qxF "$line" "$rc" || printf '%s\n' "$line" >> "$rc"
done

# User-local executable directories.
mkdir -p "$HOME/bin" "$HOME/.local/bin"

# -----------------------------
# Verification
# -----------------------------
printf '\n'
info "Verification"

verify_cmd() {
    local cmd="$1"
    if command -v "$cmd" >/dev/null 2>&1; then
        printf '  %-16s %s\n' "$cmd" "$(command -v "$cmd")"
    else
        printf '  %-16s %s\n' "$cmd" "NOT FOUND"
    fi
}

for cmd in pkg apt git python node npm clang rustc go zsh bash tmux ffmpeg htop fastfetch sshd; do
    verify_cmd "$cmd"
done

printf '\n'
if (( ${#SKIPPED[@]} > 0 )); then
    warn "Packages unavailable from the currently configured repositories:"
    printf '  %s\n' "${SKIPPED[@]}" | sort -u
fi

printf '\n'
success "Termux environment provisioning completed."

cat <<EOF

Profile:
  ${PROFILE}

Useful next steps:
  source ~/.bashrc
  source ~/.zshrc

Termux services:
  restart Termux after installation
  sv-enable <service>
  sv up <service>

Node:
  node --version
  npm --version

Termux API:
  termux-battery-status

Full/server profile:
  PROFILE=full bash $(basename "$0")

Root tooling:
  INSTALL_ROOT=1 INSTALL_TSU=1 bash $(basename "$0")
EOF
