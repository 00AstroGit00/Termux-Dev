#!/data/data/com.termux/files/usr/bin/bash
#
# Master Orchestrator for Termux Setup Suite
# Coordinates execution of modular setup stages:
#   01-termux-base.sh           - System repositories, core packages, Zsh, SSH
#   02-termux-essentials.sh     - Developer toolchains, compilers, databases, services
#   03-termux-node-toolchain.sh - Node.js LTS, npm, Yarn, pnpm (ARM64 safe)
#   04-termux-ai-cli.sh         - AI CLI Suite (agy, opencode, codex, gemini, copilot)
#   05-ai-env.sh                - AI environment variables and API keys template
#   06-termux-android-sdk.sh    - Android SDK, NDK, TermuxVoid & Java toolchain
#

set -Eeuo pipefail

SETUP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
BLUE=$'\033[0;34m'
CYAN=$'\033[0;36m'
BOLD=$'\033[1m'
NC=$'\033[0m'

info()    { printf '%s[INFO]%s %s\n' "$BLUE" "$NC" "$*"; }
success() { printf '%s[SUCCESS]%s %s\n' "$GREEN" "$NC" "$*"; }
warn()    { printf '%s[WARNING]%s %s\n' "$YELLOW" "$NC" "$*" >&2; }
error()   { printf '%s[ERROR]%s %s\n' "$RED" "$NC" "$*" >&2; }
die()     { error "$*"; exit 1; }

run_stage() {
    local stage_file="$1"
    local stage_title="$2"

    printf '\n%s=======================================================%s\n' "$BOLD$CYAN" "$NC"
    printf '%s▶ Starting: %s%s\n' "$BOLD$GREEN" "$stage_title" "$NC"
    printf '%s=======================================================%s\n\n' "$BOLD$CYAN" "$NC"

    if [[ ! -x "$SETUP_DIR/$stage_file" ]]; then
        chmod +x "$SETUP_DIR/$stage_file" 2>/dev/null || true
    fi

    if [[ -f "$SETUP_DIR/$stage_file" ]]; then
        bash "$SETUP_DIR/$stage_file"
        success "Stage finished: $stage_title"
    else
        die "Stage script not found: $SETUP_DIR/$stage_file"
    fi
}

check_cmd() {
    local label="$1"
    local cmd="$2"
    local path
    if path="$(command -v "$cmd" 2>/dev/null)"; then
        local ver
        ver="$("$cmd" --version 2>/dev/null | head -n 1 || echo 'active')"
        printf '  %-20s %s[%s✓%s] %s (%s)\n' "$label" "$GREEN" "$BOLD" "$NC" "$path" "$ver"
    else
        printf '  %-20s %s[✗ Missing]%s\n' "$label" "$RED" "$NC"
    fi
}

verify_all() {
    printf '\n%s=== Termux Toolchain Status & Verification ===%s\n\n' "$BOLD$CYAN" "$NC"

    printf '%s[System & Shell]%s\n' "$BOLD$YELLOW" "$NC"
    check_cmd "Bash" bash
    check_cmd "Zsh" zsh
    check_cmd "Git" git
    check_cmd "GitHub CLI" gh
    check_cmd "OpenSSH" sshd

    printf '\n%s[Compilers & Core Tools]%s\n' "$BOLD$YELLOW" "$NC"
    check_cmd "Clang" clang
    check_cmd "Make" make
    check_cmd "CMake" cmake
    check_cmd "Python" python
    check_cmd "Rust" rustc
    check_cmd "Go" go
    check_cmd "Ripgrep" rg
    check_cmd "jq" jq

    printf '\n%s[JavaScript & Node.js Toolchain]%s\n' "$BOLD$YELLOW" "$NC"
    check_cmd "Node.js" node
    check_cmd "npm" npm
    check_cmd "Yarn" yarn
    check_cmd "pnpm" pnpm

    printf '\n%s[AI Assistant & CLI Suite]%s\n' "$BOLD$YELLOW" "$NC"
    check_cmd "Antigravity (agy)" agy
    check_cmd "OpenCode" opencode
    check_cmd "OpenAI Codex" codex
    check_cmd "Google Gemini" gemini
    check_cmd "GitHub Copilot" copilot

    printf '\n%s[Android Development Toolchain & TermuxVoid]%s\n' "$BOLD$YELLOW" "$NC"
    [[ -f "$HOME/.android-env" ]] && source "$HOME/.android-env"
    check_cmd "TermuxVoid (tvpkg)" tvpkg
    check_cmd "Java OpenJDK" java
    check_cmd "Gradle" gradle
    check_cmd "Android ADB" adb
    check_cmd "AAPT2" aapt2
    check_cmd "APK Signer" apksigner
    check_cmd "DEX Compiler (d8)" d8
    check_cmd "SDK Manager" sdkmanager
    check_cmd "Android CLI" android

    printf '\n'
}

show_dialog_tui() {
    local choice
    while true; do
        choice=$(dialog --clear \
            --backtitle "Termux Provisioning & AI Suite Manager (ARM64)" \
            --title " Main Interactive Menu " \
            --cancel-label "Exit" \
            --menu "Select a stage or action using Up/Down arrow keys and Enter:" 22 72 11 \
            "1" "Run Full Suite (Stages 01 -> 06)" \
            "2" "Stage 01: Base System, Repos & Zsh" \
            "3" "Stage 02: Essentials & Dev Toolchains" \
            "4" "Stage 03: Node.js & Package Managers (ARM64)" \
            "5" "Stage 04: AI CLI Suite (agy, opencode, codex, gemini, copilot)" \
            "6" "Stage 05: AI Environment & Keys Template (~/.ai-env)" \
            "7" "Stage 06: Android SDK, NDK & TermuxVoid Toolchains" \
            "8" "Verify All Installed Tools" \
            "9" "Run Ruthless Stress & Verification Test Suite" \
            "10" "Clean Locks & Temporary Files" \
            "0" "Exit" \
            2>&1 >/dev/tty) || break

        clear
        case "$choice" in
            1)
                run_stage "01-termux-base.sh" "Stage 01: Termux Base Setup"
                run_stage "02-termux-essentials.sh" "Stage 02: Essentials & Dev Tools"
                run_stage "03-termux-node-toolchain.sh" "Stage 03: Node.js Toolchain"
                run_stage "04-termux-ai-cli.sh" "Stage 04: AI CLI Suite"
                run_stage "05-ai-env.sh" "Stage 05: AI Environment & Credentials"
                run_stage "06-termux-android-sdk.sh" "Stage 06: Android SDK & NDK Toolchain"
                verify_all
                ;;
            2) run_stage "01-termux-base.sh" "Stage 01: Termux Base Setup" ;;
            3) run_stage "02-termux-essentials.sh" "Stage 02: Essentials & Dev Tools" ;;
            4) run_stage "03-termux-node-toolchain.sh" "Stage 03: Node.js Toolchain" ;;
            5) run_stage "04-termux-ai-cli.sh" "Stage 04: AI CLI Suite" ;;
            6) run_stage "05-ai-env.sh" "Stage 05: AI Environment & Credentials" ;;
            7) run_stage "06-termux-android-sdk.sh" "Stage 06: Android SDK & NDK Toolchain" ;;
            8) verify_all ;;
            9) bash "$SETUP_DIR/test-suite.sh" ;;
            10)
                rm -rf "${TMPDIR:-$PREFIX/tmp}"/*.lock "${TMPDIR:-$PREFIX/tmp}"/ai-cli-suite* 2>/dev/null || true
                success "Temporary locks cleared."
                ;;
            0) break ;;
        esac

        printf '\n%sPress Enter to return to the interactive menu...%s' "$BOLD$CYAN" "$NC"
        read -r
    done
    clear 2>/dev/null || true
}

show_menu() {
    if command -v dialog >/dev/null 2>&1 && [[ -t 0 && -t 1 ]] && [[ "${USE_TUI:-1}" != "0" ]]; then
        show_dialog_tui
        return
    fi

    clear 2>/dev/null || true
    printf '%s=======================================================%s\n' "$BOLD$CYAN" "$NC"
    printf '%s       Termux Provisioning & AI Suite Manager          %s\n' "$BOLD$GREEN" "$NC"
    printf '%s=======================================================%s\n\n' "$BOLD$CYAN" "$NC"
    printf '  1) Run Full Suite (Stages 01 -> 06)\n'
    printf '  2) Stage 01: Base System, Repos & Zsh\n'
    printf '  3) Stage 02: Essentials & Dev Toolchains\n'
    printf '  4) Stage 03: Node.js & Package Managers (ARM64)\n'
    printf '  5) Stage 04: AI CLI Suite (agy, opencode, codex, gemini, copilot)\n'
    printf '  6) Stage 05: AI Environment & Keys Configuration (~/.ai-env)\n'
    printf '  7) Stage 06: Android SDK, NDK & TermuxVoid Toolchains\n'
    printf '  8) Verify All Installed Tools\n'
    printf '  9) Run Ruthless Stress & Verification Test Suite\n'
    printf ' 10) Clean Locks & Temporary Files\n'
    printf '  0) Exit\n\n'

    read -rp "Select an option [0-10]: " choice
    case "$choice" in
        1)
            run_stage "01-termux-base.sh" "Stage 01: Termux Base Setup"
            run_stage "02-termux-essentials.sh" "Stage 02: Essentials & Dev Tools"
            run_stage "03-termux-node-toolchain.sh" "Stage 03: Node.js Toolchain"
            run_stage "04-termux-ai-cli.sh" "Stage 04: AI CLI Suite"
            run_stage "05-ai-env.sh" "Stage 05: AI Environment & Credentials"
            run_stage "06-termux-android-sdk.sh" "Stage 06: Android SDK & NDK Toolchain"
            verify_all
            ;;
        2) run_stage "01-termux-base.sh" "Stage 01: Termux Base Setup" ;;
        3) run_stage "02-termux-essentials.sh" "Stage 02: Essentials & Dev Tools" ;;
        4) run_stage "03-termux-node-toolchain.sh" "Stage 03: Node.js Toolchain" ;;
        5) run_stage "04-termux-ai-cli.sh" "Stage 04: AI CLI Suite" ;;
        6) run_stage "05-ai-env.sh" "Stage 05: AI Environment & Credentials" ;;
        7) run_stage "06-termux-android-sdk.sh" "Stage 06: Android SDK & NDK Toolchain" ;;
        8) verify_all ;;
        9)
            bash "$SETUP_DIR/test-suite.sh"
            ;;
        10)
            rm -rf "${TMPDIR:-$PREFIX/tmp}"/*.lock "${TMPDIR:-$PREFIX/tmp}"/ai-cli-suite* 2>/dev/null || true
            success "Temporary locks cleared."
            ;;
        0|q|Q)
            info "Exiting."
            exit 0
            ;;
        *)
            warn "Invalid selection: $choice"
            ;;
    esac
}

# CLI Argument parsing
if [[ $# -gt 0 ]]; then
    case "$1" in
        --all)
            run_stage "01-termux-base.sh" "Stage 01: Termux Base Setup"
            run_stage "02-termux-essentials.sh" "Stage 02: Essentials & Dev Tools"
            run_stage "03-termux-node-toolchain.sh" "Stage 03: Node.js Toolchain"
            run_stage "04-termux-ai-cli.sh" "Stage 04: AI CLI Suite"
            run_stage "05-ai-env.sh" "Stage 05: AI Environment & Credentials"
            run_stage "06-termux-android-sdk.sh" "Stage 06: Android SDK & NDK Toolchain"
            verify_all
            ;;
        --base)
            run_stage "01-termux-base.sh" "Stage 01: Termux Base Setup"
            ;;
        --essentials)
            run_stage "02-termux-essentials.sh" "Stage 02: Essentials & Dev Tools"
            ;;
        --node)
            run_stage "03-termux-node-toolchain.sh" "Stage 03: Node.js Toolchain"
            ;;
        --ai)
            run_stage "04-termux-ai-cli.sh" "Stage 04: AI CLI Suite"
            ;;
        --ai-env)
            run_stage "05-ai-env.sh" "Stage 05: AI Environment & Credentials"
            ;;
        --android)
            run_stage "06-termux-android-sdk.sh" "Stage 06: Android SDK & NDK Toolchain"
            ;;
        --verify)
            verify_all
            ;;
        --test|--smoke-test)
            bash "$SETUP_DIR/test-suite.sh"
            ;;
        --clean)
            rm -rf "${TMPDIR:-$PREFIX/tmp}"/*.lock "${TMPDIR:-$PREFIX/tmp}"/ai-cli-suite* 2>/dev/null || true
            success "Temporary locks cleared."
            ;;
        --help|-h)
            printf 'Usage: %s [OPTION]\n\n' "$(basename "$0")"
            printf 'Options:\n'
            printf '  --all         Execute all setup stages (01 -> 06)\n'
            printf '  --base        Execute Stage 01: Base & Repos\n'
            printf '  --essentials  Execute Stage 02: Essentials & Dev Tools\n'
            printf '  --node        Execute Stage 03: Node.js Toolchain\n'
            printf '  --ai          Execute Stage 04: AI CLI Suite\n'
            printf '  --ai-env      Execute Stage 05: AI Environment Setup\n'
            printf '  --android     Execute Stage 06: Android SDK & NDK Setup\n'
            printf '  --verify      Verify all installed tools\n'
            printf '  --test        Run ruthless stress & verification test suite\n'
            printf '  --clean       Remove locks and temporary files\n'
            printf '  --help        Display this help message\n'
            exit 0
            ;;
        *)
            error "Unknown argument: $1"
            printf 'Run "%s --help" for available options.\n' "$(basename "$0")"
            exit 1
            ;;
    esac
else
    show_menu
fi
