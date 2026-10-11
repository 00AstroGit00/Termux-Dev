#!/usr/bin/env bash
#
# Termux Node.js / npm / Yarn / pnpm bootstrap
# Android/ARM64-safe design.
#
# Key design choices:
#   - Keep the npm bundled with Termux's nodejs-lts package.
#   - Do NOT replace npm 11 with an old user-local npm 9.
#   - Install global JS CLIs into ~/.npm-global without changing Termux's
#     system packages.
#   - Use pnpm 10.x on Termux until pnpm's native Android support is
#     reliably available in the npm release being consumed.
#

set -Eeuo pipefail

USER_PREFIX="${HOME}/.npm-global"
BIN_DIR="${USER_PREFIX}/bin"
MODULE_DIR="${USER_PREFIX}/lib/node_modules"

# pnpm 10 is the compatibility line for this Android/Termux installer.
# It is a normal Node.js-based pnpm release rather than the new Rust/native
# CLI line that currently fails on Android ARM64.
PNPM_VERSION="${PNPM_VERSION:-10.33.4}"

mkdir -p "$BIN_DIR" "$MODULE_DIR"

# Make the user global bin/prefix active NOW, not only after a new shell starts.
export PATH="${BIN_DIR}:${PATH}"
export npm_config_prefix="${USER_PREFIX}"

log() {
    printf '[INFO] %s\n' "$*"
}

warn() {
    printf '[WARNING] %s\n' "$*" >&2
}

error() {
    printf '[ERROR] %s\n' "$*" >&2
}

die() {
    error "$*"
    exit 1
}

on_error() {
    local rc=$?
    error "Command failed (exit ${rc}) at line ${BASH_LINENO[0]:-unknown}: ${BASH_COMMAND:-unknown}"
    exit "$rc"
}
trap on_error ERR

# -------------------------
# Concurrency Lock (flock)
# -------------------------
LOCK_FILE="${TMPDIR:-$PREFIX/tmp}/termux-node.lock"
exec 200>"$LOCK_FILE"
if ! flock -n 200; then
    die "Another instance of 03-termux-node-toolchain.sh is running."
fi

# -------------------------
# Environment validation
# -------------------------
[[ -n "${PREFIX:-}" ]] || die "PREFIX is not set. Run this script from Termux."
[[ -x "${PREFIX}/bin/pkg" ]] || die "Termux pkg was not found."
[[ -x "${PREFIX}/bin/apt" ]] || die "Termux apt was not found."

case "$(uname -m)" in
    aarch64|arm64)
        ARCH="android-arm64"
        ;;
    armv7l|armv8l|arm)
        ARCH="android-arm"
        ;;
    x86_64)
        ARCH="android-x64"
        ;;
    i686|i386)
        ARCH="android-x86"
        ;;
    *)
        ARCH="$(uname -m)"
        ;;
esac

log "Detected Termux architecture: ${ARCH}"

# -------------------------
# Node.js
# -------------------------
if ! command -v node >/dev/null 2>&1; then
    log "Node.js not found. Installing nodejs-lts via pkg..."
    pkg update
    pkg install -y nodejs-lts
fi

NODE_BIN="$(command -v node)" || die "Node.js installation failed."
NODE_VER="$("$NODE_BIN" -v)"
log "Node.js found at ${NODE_BIN} ${NODE_VER}"

# -------------------------
# npm
# -------------------------
NPM_BIN="$(command -v npm || true)"

if [[ -z "$NPM_BIN" ]]; then
    # nodejs-lts normally provides npm in current Termux packaging.
    # Reinstalling nodejs-lts is safer than downloading an arbitrary npm tarball.
    log "npm not found. Reinstalling nodejs-lts..."
    pkg install -y nodejs-lts
    NPM_BIN="$(command -v npm || true)"
fi

[[ -n "$NPM_BIN" ]] || die "npm is unavailable after installing nodejs-lts."

NPM_VER="$("$NPM_BIN" -v)"
log "Using Termux-provided npm ${NPM_VER} at ${NPM_BIN}"

# npm 11 can warn about lifecycle scripts. We intentionally do not disable
# scripts globally because many packages require them. Packages are installed
# one at a time below so a failure can be diagnosed cleanly.

# -------------------------
# Persist user-global npm
# -------------------------
ZSHRC="${HOME}/.zshrc"
BASHRC="${HOME}/.bashrc"

persist_env() {
    local file="$1"
    touch "$file"

    if ! grep -qF 'export PATH="$HOME/.local/bin:$HOME/.npm-global/bin' "$file"; then
        if ! grep -qF '.npm-global/bin' "$file"; then
            printf '%s\n' 'export PATH="$HOME/.local/bin:$HOME/.npm-global/bin:$HOME/bin:$PREFIX/bin:$PATH"' >> "$file"
        fi
    fi

    grep -qxF 'export npm_config_prefix="$HOME/.npm-global"' "$file" || \
        printf '%s\n' 'export npm_config_prefix="$HOME/.npm-global"' >> "$file"
}

persist_env "$ZSHRC"
persist_env "$BASHRC"

# Refresh command lookup in the current shell.
hash -r 2>/dev/null || true

# -------------------------
# Remove stale/broken pnpm
# -------------------------
if [[ -d "${MODULE_DIR}/pnpm" ]]; then
    log "Removing stale pnpm installation from ${MODULE_DIR}/pnpm..."
    rm -rf "${MODULE_DIR}/pnpm"
fi

if [[ -L "${BIN_DIR}/pnpm" || -f "${BIN_DIR}/pnpm" ]]; then
    rm -f "${BIN_DIR}/pnpm"
fi

# npm's own system/global installation can also contain a failed pnpm attempt.
SYSTEM_PNPM_DIR="$(npm root -g 2>/dev/null || true)"
if [[ -n "$SYSTEM_PNPM_DIR" && -d "${SYSTEM_PNPM_DIR}/pnpm" ]]; then
    warn "Removing stale pnpm from the Termux system npm global directory: ${SYSTEM_PNPM_DIR}/pnpm"
    npm uninstall -g pnpm >/dev/null 2>&1 || true
fi

# -------------------------
# Yarn
# -------------------------
if command -v yarn >/dev/null 2>&1; then
    log "Yarn already available at $(command -v yarn) $(yarn --version)"
else
    log "Installing Yarn classic into ${USER_PREFIX}..."
    npm install --global --prefix "$USER_PREFIX" --ignore-scripts yarn@1.22.22
    hash -r 2>/dev/null || true

    if command -v yarn >/dev/null 2>&1; then
        log "Yarn installed: $(command -v yarn) $(yarn --version)"
    else
        die "Yarn installation completed but the executable is not on PATH."
    fi
fi

# -------------------------
# pnpm
# -------------------------
#
# IMPORTANT:
# Do NOT use:
#   npm install -g pnpm
# without a version on current Termux.
#
# Current pnpm 12.x installation attempts to obtain a native
# android-arm64 binary. A current upstream issue documents that this
# fails on Android ARM64/Termux with:
# "pnpm does not ship a prebuilt binary for android-arm64."
#
# pnpm 10.x is kept as the Android-compatible fallback here.
#
log "Installing pnpm ${PNPM_VERSION} into ${USER_PREFIX}..."
npm install --global --prefix "$USER_PREFIX" "pnpm@${PNPM_VERSION}"

hash -r 2>/dev/null || true

command -v pnpm >/dev/null 2>&1 || die "pnpm executable was not created."
INSTALLED_PNPM="$(pnpm --version)"

if [[ "$INSTALLED_PNPM" != "$PNPM_VERSION" ]]; then
    die "pnpm version mismatch: requested ${PNPM_VERSION}, got ${INSTALLED_PNPM}"
fi

log "pnpm ${INSTALLED_PNPM} installed successfully."

# -------------------------
# Verification
# -------------------------
printf '\n'
log "Verification:"
printf 'node:  %s\n' "$(command -v node)"
printf 'npm:   %s\n' "$(command -v npm)"
printf 'yarn:  %s\n' "$(command -v yarn)"
printf 'pnpm:  %s\n' "$(command -v pnpm)"
printf 'node:  %s\n' "$(node --version)"
printf 'npm:   %s\n' "$(npm --version)"
printf 'yarn:  %s\n' "$(yarn --version)"
printf 'pnpm:  %s\n' "$(pnpm --version)"
printf 'prefix: %s\n' "$(npm config get prefix)"

# Basic Node runtime test.
node -e 'console.log("[INFO] Node runtime test: OK")'

# Basic package-manager runtime tests.
yarn --version >/dev/null
pnpm --version >/dev/null

printf '\n'
log "Node toolchain setup completed successfully."
log "Open a new Termux session or run: source ~/.zshrc"
