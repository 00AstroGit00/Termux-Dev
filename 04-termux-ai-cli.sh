#!/data/data/com.termux/files/usr/bin/bash
#
# AI CLI Suite for Termux / Android ARM64 (aarch64)
#
# Installs and validates:
#   - Google Antigravity CLI (community Termux port; command: agy)
#   - OpenCode (community Android/aarch64 Termux build)
#   - OpenAI Codex CLI (Termux ARM64 package)
#   - Google Gemini CLI (official npm package)
#   - GitHub Copilot CLI (official npm package)
#
# Runtime strategy:
#   * Termux-native packages wherever possible.
#   * User-global npm prefix for JS CLIs.
#   * No Bun/pnpm dependency for the core AI CLI suite.
#   * No automatic API keys or credentials are stored.
#   * Idempotent and safe to re-run.
#
# This script targets ONLY aarch64/ARM64 Termux.
#
# Usage:
#   chmod +x ai-cli-suite-termux-aarch64.sh
#   ./ai-cli-suite-termux-aarch64.sh
#
# Disable an individual component:
#   INSTALL_ANTIGRAVITY=0
#   INSTALL_OPENCODE=0
#   INSTALL_CODEX=0
#   INSTALL_GEMINI=0
#   INSTALL_COPILOT=0
#
# Set all in one invocation, for example:
#   INSTALL_ANTIGRAVITY=0 ./ai-cli-suite-termux-aarch64.sh
#

set -Eeuo pipefail
IFS=$'\n\t'

# -----------------------------
# Configuration
# -----------------------------
INSTALL_ANTIGRAVITY="${INSTALL_ANTIGRAVITY:-1}"
INSTALL_OPENCODE="${INSTALL_OPENCODE:-1}"
INSTALL_CODEX="${INSTALL_CODEX:-1}"
INSTALL_GEMINI="${INSTALL_GEMINI:-1}"
INSTALL_COPILOT="${INSTALL_COPILOT:-1}"

NPM_PREFIX="${NPM_PREFIX:-$HOME/.npm-global}"
NPM_BIN="$NPM_PREFIX/bin"
NPM_MODULES="$NPM_PREFIX/lib/node_modules"

# Codex Termux ARM64 package
CODEX_PACKAGE="${CODEX_PACKAGE:-@mmmbuto/codex-cli-termux}"

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
    error "Command failed with exit ${rc} at line ${BASH_LINENO[0]:-unknown}: ${BASH_COMMAND:-unknown}"
    exit "$rc"
}
trap on_error ERR

# -----------------------------
# Basic validation
# -----------------------------
[[ -n "${PREFIX:-}" ]] || die "PREFIX is not set. Run this from Termux."
[[ -x "$PREFIX/bin/pkg" ]] || die "Termux pkg was not found."
[[ -x "$PREFIX/bin/apt" ]] || die "Termux apt was not found."

DPKG_ARCH="$(dpkg --print-architecture 2>/dev/null || true)"
MACHINE_ARCH="$(uname -m 2>/dev/null || true)"

if [[ "$DPKG_ARCH" != "aarch64" && "$MACHINE_ARCH" != "aarch64" ]]; then
    die "This installer is intentionally restricted to ARM64/aarch64. Detected dpkg=${DPKG_ARCH:-unknown}, uname=${MACHINE_ARCH:-unknown}."
fi

ANDROID_API="$(getprop ro.build.version.sdk 2>/dev/null || true)"
ANDROID_ABI="$(getprop ro.product.cpu.abi 2>/dev/null || true)"

info "Termux: ARM64/aarch64 confirmed."
[[ -n "$ANDROID_API" ]] && info "Android API level: $ANDROID_API"
[[ -n "$ANDROID_ABI" ]] && info "Android ABI: $ANDROID_ABI"

# -----------------------------
# Concurrency Lock (flock: kernel-managed, immune to stale locks)
# -----------------------------
LOCK_FILE="${TMPDIR:-$PREFIX/tmp}/ai-cli-suite-aarch64.lock"
exec 200>"$LOCK_FILE"
if ! flock -n 200; then
    die "Another instance of 04-termux-ai-cli.sh is already running."
fi

cleanup() {
    rm -rf "${WORK_DIR:-}" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

WORK_DIR="$(mktemp -d "${TMPDIR:-$PREFIX/tmp}/ai-cli-suite.XXXXXX")"

# -----------------------------
# Prerequisite packages
# -----------------------------
info "Refreshing Termux package indexes..."
pkg update

info "Installing native prerequisites..."
pkg install -y \
    ca-certificates \
    curl \
    wget \
    git \
    tar \
    gzip \
    unzip \
    zip \
    jq \
    file \
    openssl-tool \
    clang \
    pkg-config \
    ripgrep \
    nodejs-lts

# Keep the npm toolchain in the separate user prefix used by npm_fixed.sh.
mkdir -p "$NPM_BIN" "$NPM_MODULES"
export PATH="$HOME/.local/bin:$NPM_BIN:$HOME/bin:$PREFIX/bin:$PATH"
export npm_config_prefix="$NPM_PREFIX"

# Persist without duplicating lines.
persist_shell_env() {
    local rc="$1"
    touch "$rc"

    grep -qxF 'export PATH="$HOME/.local/bin:$HOME/.npm-global/bin:$HOME/bin:$PREFIX/bin:$PATH"' "$rc" ||
        printf '%s\n' 'export PATH="$HOME/.local/bin:$HOME/.npm-global/bin:$HOME/bin:$PREFIX/bin:$PATH"' >> "$rc"

    grep -qxF 'export npm_config_prefix="$HOME/.npm-global"' "$rc" ||
        printf '%s\n' 'export npm_config_prefix="$HOME/.npm-global"' >> "$rc"
}

persist_shell_env "$HOME/.bashrc"
persist_shell_env "$HOME/.zshrc"

hash -r 2>/dev/null || true

NODE_VERSION="$(node --version)"
NPM_VERSION="$(npm --version)"

info "Node.js: $NODE_VERSION"
info "npm:     $NPM_VERSION"
info "npm prefix: $(npm config get prefix)"

# -----------------------------
# Generic helpers
# -----------------------------
npm_install_user() {
    local package_spec="$1"
    info "Installing npm package: $package_spec"
    if npm install --global --prefix "$NPM_PREFIX" "$package_spec"; then
        command -v termux-fix-shebang >/dev/null 2>&1 && termux-fix-shebang "$NPM_BIN"/* 2>/dev/null || true
        hash -r 2>/dev/null || true
        return 0
    fi
    warn "npm installation failed for: $package_spec"
    return 1
}

verify_command() {
    local label="$1"
    local cmd="$2"

    if command -v "$cmd" >/dev/null 2>&1; then
        printf '%-18s %s -> ' "$label" "$cmd"
        "$cmd" --version 2>/dev/null | head -n 1 || true
        return 0
    fi

    warn "$label command '$cmd' is not available."
    return 1
}

# -----------------------------
# 1. Google Antigravity CLI
# -----------------------------
if [[ "$INSTALL_ANTIGRAVITY" == "1" ]]; then
    if command -v agy >/dev/null 2>&1; then
        success "Antigravity CLI is already installed: $(command -v agy)"
        agy --version 2>/dev/null | head -n 1 || true
    else
        info "Installing Google Antigravity CLI for Termux ARM64."

        cat <<'WARNING'
[WARNING] Antigravity on native Termux currently relies on community
Termux compatibility work rather than a standard Google Android package.
The selected installer is:
  wallentx/antigravity-cli-termux

It downloads and installs a patched ARM64-compatible Antigravity CLI.
Review Google's terms/privacy requirements for your own use before
authenticating the service.
WARNING

        AGY_INSTALLER="$WORK_DIR/antigravity-install.sh"
        AGY_URL="https://raw.githubusercontent.com/wallentx/antigravity-cli-termux/dev/install.sh"

        if curl -fL --retry 3 --retry-delay 2 \
            --proto '=https' --tlsv1.2 \
            "$AGY_URL" -o "$AGY_INSTALLER" && [[ -s "$AGY_INSTALLER" ]]; then

            if head -n 1 "$AGY_INSTALLER" | grep -qE '^#!.*(bash|sh)'; then
                chmod 700 "$AGY_INSTALLER"
                bash "$AGY_INSTALLER" || warn "Antigravity installer reported an issue."
            else
                warn "Downloaded Antigravity installer is not a valid shell script."
            fi
        else
            warn "Failed to download Antigravity installer."
        fi

        hash -r 2>/dev/null || true
        if command -v agy >/dev/null 2>&1; then
            success "Antigravity CLI: $(command -v agy)"
        else
            warn "Antigravity installer finished, but 'agy' is not currently on PATH."
        fi
    fi
fi

# -----------------------------
# 2. OpenCode for Termux ARM64
# -----------------------------
if [[ "$INSTALL_OPENCODE" == "1" ]]; then
    if command -v opencode >/dev/null 2>&1; then
        success "OpenCode is already installed: $(command -v opencode)"
        opencode --version 2>/dev/null | head -n 1 || true
    else
        info "Installing OpenCode Android/aarch64 Termux build."
        pkg install -y ripgrep

        # Primary approach: opencode-termux npm package (Termux ARM64 native)
        if npm_install_user "opencode-termux@latest"; then
            hash -r 2>/dev/null || true
            opencode --version 2>/dev/null || true
        fi

        if ! command -v opencode >/dev/null 2>&1; then
            OPENCODE_DEB="$WORK_DIR/opencode-aarch64.deb"

            info "Resolving OpenCode release package..."
            OPENCODE_URL=""
            if command -v jq >/dev/null 2>&1; then
                OPENCODE_URL="$(curl -sL --retry 3 --retry-delay 2 "https://api.github.com/repos/guysoft/opencode-termux/releases/latest" 2>/dev/null | jq -r '.assets[]? | select(.name | test("opencode.*_aarch64\\.deb$")) | .browser_download_url' 2>/dev/null | head -n 1 || true)"
            fi

        # Fallback to verified package if API query fails or is rate-limited
        if [[ -z "$OPENCODE_URL" || "$OPENCODE_URL" == "null" ]]; then
            OPENCODE_URL="https://github.com/guysoft/opencode-termux/releases/download/v0.2.1/opencode_1.17.9_aarch64.deb"
        fi

        info "Downloading OpenCode from: $OPENCODE_URL"
        if curl -fL --retry 3 --retry-delay 2 --proto '=https' --tlsv1.2 "$OPENCODE_URL" -o "$OPENCODE_DEB" && [[ -s "$OPENCODE_DEB" ]]; then
            if file "$OPENCODE_DEB" | grep -qiE 'Debian|ar archive'; then
                dpkg -i "$OPENCODE_DEB" || {
                    warn "OpenCode package reported dependency issues; attempting APT repair..."
                    apt-get -f install -y
                    dpkg -i "$OPENCODE_DEB" || warn "OpenCode dpkg installation failed."
                }
            else
                warn "Downloaded OpenCode file is not recognized as a Debian package."
            fi
        else
            warn "OpenCode download failed from $OPENCODE_URL."
        fi
        fi

        hash -r 2>/dev/null || true

        if command -v opencode >/dev/null 2>&1; then
            success "OpenCode: $(command -v opencode)"
            opencode --version 2>/dev/null | head -n 1 || true
        else
            warn "OpenCode package installed but 'opencode' is not on PATH."
        fi
    fi
fi

# -----------------------------
# 3. OpenAI Codex CLI for Termux ARM64
# -----------------------------
if [[ "$INSTALL_CODEX" == "1" ]]; then
    if command -v codex >/dev/null 2>&1; then
        success "Codex is already installed: $(command -v codex)"
        codex --version 2>/dev/null | head -n 1 || true
    else
        info "Installing the ARM64 Termux Codex package: $CODEX_PACKAGE"
        if npm_install_user "${CODEX_PACKAGE}@latest"; then
            hash -r 2>/dev/null || true
            if command -v codex >/dev/null 2>&1; then
                success "Codex: $(command -v codex)"
                codex --version 2>/dev/null | head -n 1 || true
            else
                warn "Codex package installed but 'codex' was not found on PATH."
            fi
        else
            warn "Codex installation failed."
        fi
    fi
fi

# -----------------------------
# 4. Google Gemini CLI
# -----------------------------
if [[ "$INSTALL_GEMINI" == "1" ]]; then
    if command -v gemini >/dev/null 2>&1; then
        success "Gemini CLI is already installed: $(command -v gemini)"
        gemini --version 2>/dev/null | head -n 1 || true
    else
        info "Installing official Google Gemini CLI via npm."
        if npm_install_user "@google/gemini-cli@latest"; then
            hash -r 2>/dev/null || true
            if command -v gemini >/dev/null 2>&1; then
                success "Gemini CLI: $(command -v gemini)"
                gemini --version 2>/dev/null | head -n 1 || true
            else
                warn "Gemini package installed but 'gemini' was not found on PATH."
            fi
        else
            warn "Google Gemini CLI installation failed."
        fi
    fi
fi

# -----------------------------
# 5. GitHub Copilot CLI
# -----------------------------
if [[ "$INSTALL_COPILOT" == "1" ]]; then
    if command -v copilot >/dev/null 2>&1 && copilot --version >/dev/null 2>&1; then
        success "GitHub Copilot CLI is already installed and verified: $(command -v copilot)"
        copilot --version 2>/dev/null | head -n 1 || true
    else
        info "Setting up GitHub Copilot CLI for Termux ARM64..."
        pkg install -y glibc-repo glibc termux-glibc ca-certificates || true

        # Primary method: @bash0816/copilot-termux (handles glibc wrap & symlinks cleanly)
        if npm_install_user "@bash0816/copilot-termux@latest"; then
            copilot-termux setup 2>/dev/null || true
            hash -r 2>/dev/null || true
        fi

        # Fallback method: manual grun launcher
        if ! command -v copilot >/dev/null 2>&1 || ! copilot --version >/dev/null 2>&1; then
            if ! command -v grun >/dev/null 2>&1; then
                warn "grun (termux-glibc) is required for GitHub Copilot native binary. Skipping."
            else
            COPILOT_OPT="$PREFIX/opt/copilot"
            mkdir -p "$COPILOT_OPT" "$NPM_BIN"

            if [[ ! -x "$COPILOT_OPT/copilot" ]]; then
                info "Fetching Copilot Linux ARM64 binary package from npm..."
                COPILOT_PKG_URL="$(npm view @github/copilot-linux-arm64 dist.tarball 2>/dev/null || echo "https://registry.npmjs.org/@github/copilot-linux-arm64/-/copilot-linux-arm64-1.0.83.tgz")"
                COPILOT_TMP="$WORK_DIR/copilot-pkg"
                mkdir -p "$COPILOT_TMP"

                if curl -fL --retry 3 --retry-delay 2 "$COPILOT_PKG_URL" -o "$COPILOT_TMP/copilot.tgz" && [[ -s "$COPILOT_TMP/copilot.tgz" ]]; then
                    tar -xzf "$COPILOT_TMP/copilot.tgz" -C "$COPILOT_TMP"
                    if [[ -f "$COPILOT_TMP/package/copilot" ]]; then
                        cp -f "$COPILOT_TMP/package/copilot" "$COPILOT_OPT/copilot"
                        chmod 755 "$COPILOT_OPT/copilot"
                    fi
                fi
            fi

            if [[ -x "$COPILOT_OPT/copilot" ]]; then
                mkdir -p "$HOME/.local/bin" "$NPM_BIN"
                for target_dir in "$HOME/.local/bin" "$NPM_BIN"; do
                    cat > "$target_dir/copilot" <<LAUNCHER
#!/data/data/com.termux/files/usr/bin/bash
exec grun "$COPILOT_OPT/copilot" "\$@"
LAUNCHER
                    chmod 755 "$target_dir/copilot"
                done
                hash -r 2>/dev/null || true
            fi

            if command -v copilot >/dev/null 2>&1 && copilot --version >/dev/null 2>&1; then
                success "GitHub Copilot CLI: $(command -v copilot)"
                copilot --version 2>/dev/null | head -n 1 || true
            else
                warn "Copilot package installation completed but 'copilot --version' did not run cleanly."
            fi
        fi
        fi
    fi
fi

# -----------------------------
# Optional convenience: common
# AI/agent ecosystem tools
# -----------------------------
# These remain disabled by default because they are not required for the
# core suite and some use platform-specific runtimes.
#
# Example manual installations:
#   npm install -g @google/gemini-cli@latest
#   npm install -g @github/copilot@latest
#
# Do not install unpinned pnpm here. On Android ARM64 the newest pnpm line
# can attempt to use a native android-arm64 binary and fail, as encountered
# in the preceding bootstrap work.

# -----------------------------
# Unified verification
# -----------------------------
printf '\n'
info "=== AI CLI Suite Verification ==="

verify_command "Antigravity" agy || true
verify_command "OpenCode" opencode || true
verify_command "Codex" codex || true
verify_command "Gemini" gemini || true
verify_command "Copilot" copilot || true

printf '\n'
info "Runtime:"
printf '  Node.js:      %s\n' "$(node --version)"
printf '  npm:          %s\n' "$(npm --version)"
printf '  npm prefix:   %s\n' "$(npm config get prefix)"
printf '  architecture: %s\n' "$DPKG_ARCH"

printf '\n'
cat <<'EOF'
[INFO] Authentication is intentionally NOT performed automatically.

Authenticate each service separately when you are ready:
  agy
  opencode
  codex
  gemini
  copilot

Typical first-run actions:
  Codex:       codex login
  Copilot:     copilot -> /login
  Gemini:      gemini -> follow the Google authentication prompt
  OpenCode:    configure an LLM provider/API key
  Antigravity: agy -> follow the Google authentication prompt

For provider secrets, prefer environment variables or each tool's
credential store; do not hard-code API keys into this installer.
EOF

printf '\n'
success "AI CLI suite provisioning completed for Termux ARM64."
