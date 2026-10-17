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

# Enforce canonical PATH ordering
export PATH="$HOME/.local/bin:$HOME/.npm-global/bin:$HOME/bin:$PREFIX/bin:$PATH"

# Prevent CPU doze/sleep during long-running toolchain setups
if command -v termux-wake-lock >/dev/null 2>&1; then
    termux-wake-lock 2>/dev/null || true
    trap 'termux-wake-unlock 2>/dev/null || true' EXIT INT TERM
fi

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
die()     { error "$*"; exit 1; }

notify_user() {
    local title="$1"
    local message="$2"
    if command -v termux-notification >/dev/null 2>&1; then
        termux-notification \
            --id "termux-dev" \
            --title "$title" \
            --content "$message" \
            --priority high \
            2>/dev/null || true
    fi
}

prune_ndk() {
    local ndk_lib="${PREFIX:-/data/data/com.termux/files/usr}/opt/android-sdk/ndk/29.0.14206865/toolchains/llvm/prebuilt/linux-arm64/sysroot/usr/lib"
    if [[ -d "$ndk_lib" ]]; then
        info "Pruning unused cross-compilation sysroots (i686, x86_64, riscv64)..."
        local before
        before="$(du -sh "${PREFIX:-/data/data/com.termux/files/usr}/opt/android-sdk/ndk" 2>/dev/null | cut -f1)"
        rm -rf "$ndk_lib"/i686-* "$ndk_lib"/x86_64-* "$ndk_lib"/riscv64-*
        local after
        after="$(du -sh "${PREFIX:-/data/data/com.termux/files/usr}/opt/android-sdk/ndk" 2>/dev/null | cut -f1)"
        success "NDK storage pruned: before=$before, after=$after."
    else
        warn "NDK sysroot directory not found at $ndk_lib"
    fi
}

tune_device() {
    printf '\n%s=== Android Device Tuning: Phantom Process Killer ===%s\n\n' "$BOLD$CYAN" "$NC"
    if su -c true >/dev/null 2>&1; then
        info "Root detected. Applying system configuration to disable Phantom Process Killer..."
        if su -c '
            settings put global settings_enable_monitor_phantom_procs false && \
            /system/bin/device_config set_sync_disabled_for_tests persistent && \
            /system/bin/device_config put activity_manager max_phantom_processes 2147483647
        ' 2>/dev/null; then
            success "Phantom Process Killer successfully disabled via root."
            return 0
        fi
    fi

    printf '%s[Android 12+ Background Stability Notice]%s\n' "$BOLD$YELLOW" "$NC"
    printf 'Android 12/13/14+ terminates heavy builds/compilers when exceeding 32 child processes.\n'
    printf 'To permanently neutralize the Phantom Process Killer, connect via ADB and run:\n\n'
    printf '  %sadb shell "/system/bin/device_config set_sync_disabled_for_tests persistent"%s\n' "$BOLD$GREEN" "$NC"
    printf '  %sadb shell "/system/bin/device_config put activity_manager max_phantom_processes 2147483647"%s\n' "$BOLD$GREEN" "$NC"
    printf '  %sadb shell "settings put global settings_enable_monitor_phantom_procs false"%s\n\n' "$BOLD$GREEN" "$NC"
    printf 'On Android 14+, you can also enable:\n'
    printf '  Settings -> System -> Developer Options -> "Disable child process restrictions"\n\n'
}

install_git_hooks() {
    printf '\n%s=== Git Pre-Commit Hook Installation ===%s\n\n' "$BOLD$CYAN" "$NC"
    local hook_dir="$SETUP_DIR/.git/hooks"
    if [[ ! -d "$hook_dir" ]]; then
        warn "Git hooks directory not found at $hook_dir"
        return 1
    fi

    cat > "$hook_dir/pre-commit" <<'HOOK_EOF'
#!/data/data/com.termux/files/usr/bin/bash
set -e
echo "Running pre-commit validation..."
for script in *.sh bin/*; do
    if [[ -f "$script" ]]; then
        bash -n "$script" || { echo "[ERROR] Syntax validation failed: $script"; exit 1; }
        if command -v shellcheck >/dev/null 2>&1; then
            shellcheck "$script" || { echo "[ERROR] ShellCheck linting failed: $script"; exit 1; }
        fi
        if [[ ! -x "$script" ]]; then
            chmod +x "$script"
        fi
    fi
done
echo "Pre-commit checks passed cleanly."
HOOK_EOF
    chmod +x "$hook_dir/pre-commit"
    success "Pre-commit hook installed at $hook_dir/pre-commit."

    # Install/refresh shell completions
    local zsh_site="${PREFIX:-/data/data/com.termux/files/usr}/share/zsh/site-functions"
    local bash_comp="${PREFIX:-/data/data/com.termux/files/usr}/etc/bash_completion.d"
    mkdir -p "$zsh_site" "$bash_comp"
    if [[ -d "$SETUP_DIR/completions" ]]; then
        [[ -f "$SETUP_DIR/completions/_tsuite" ]] && cp -f "$SETUP_DIR/completions/_tsuite" "$zsh_site/_tsuite" && cp -f "$SETUP_DIR/completions/_tsuite" "$zsh_site/_termux-suite"
        [[ -f "$SETUP_DIR/completions/_termux-apk-build" ]] && cp -f "$SETUP_DIR/completions/_termux-apk-build" "$zsh_site/_termux-apk-build" && cp -f "$SETUP_DIR/completions/_termux-apk-build" "$zsh_site/_apk-build"
        [[ -f "$SETUP_DIR/completions/tsuite.bash" ]] && cp -f "$SETUP_DIR/completions/tsuite.bash" "$bash_comp/tsuite"
        success "Shell completions refreshed for Zsh and Bash."
    fi
}

clean_system() {
    info "Clearing temporary files, stale locks, and package cache..."
    rm -rf "${TMPDIR:-$PREFIX/tmp}"/*.lock \
           "${TMPDIR:-$PREFIX/tmp}"/ai-cli-suite* \
           "${TMPDIR:-$PREFIX/tmp}"/apk-build-* \
           "${TMPDIR:-$PREFIX/tmp}"/test-suite-* 2>/dev/null || true

    if command -v apt-get >/dev/null 2>&1; then
        info "Cleaning apt package cache archives..."
        apt-get clean >/dev/null 2>&1 || true
        rm -rf /data/data/com.termux/cache/apt/archives/*.deb 2>/dev/null || true
    fi

    success "Temporary locks and package cache cleared."
}

doctor_system() {
    printf '\n%s=== Termux System Health & Environment Diagnostics ===%s\n\n' "$BOLD$CYAN" "$NC"

    # Disk Space
    printf '%s[Storage]%s\n' "$BOLD$YELLOW" "$NC"
    df -h "${PREFIX:-/data/data/com.termux/files/usr}" "${HOME}" 2>/dev/null | awk 'NR==1 || /data/'
    printf '\n'

    # RAM
    printf '%s[Memory (RAM)]%s\n' "$BOLD$YELLOW" "$NC"
    free -h 2>/dev/null || free -m
    printf '\n'

    # Phantom Process Killer
    printf '%s[Process Management & Android 12+ Stability]%s\n' "$BOLD$YELLOW" "$NC"
    if su -c true >/dev/null 2>&1; then
        local max_phantom
        max_phantom="$(su -c '/system/bin/device_config get activity_manager max_phantom_processes' 2>/dev/null || echo 'unknown')"
        printf '  Root access: %sAvailable%s\n' "$GREEN" "$NC"
        printf '  Phantom Process Killer max_phantom_processes: %s%s%s\n' "$BOLD" "$max_phantom" "$NC"
    else
        printf '  Root access: %sNot detected (check Wireless ADB tuning instructions)%s\n' "$YELLOW" "$NC"
    fi
    printf '\n'

    # Battery & Power Telemetry
    printf '%s[Battery & Power Telemetry]%s\n' "$BOLD$YELLOW" "$NC"
    if command -v termux-battery-status >/dev/null 2>&1; then
        local bat_json
        bat_json="$(termux-battery-status 2>/dev/null || true)"
        if [[ -n "$bat_json" ]]; then
            local pct temp status health
            pct="$(echo "$bat_json" | jq -r '.percentage // empty' 2>/dev/null || true)"
            temp="$(echo "$bat_json" | jq -r '.temperature // empty' 2>/dev/null || true)"
            status="$(echo "$bat_json" | jq -r '.status // empty' 2>/dev/null || true)"
            health="$(echo "$bat_json" | jq -r '.health // empty' 2>/dev/null || true)"
            printf '  Battery Level: %s%s%%%s (Status: %s, Temp: %s°C, Health: %s)\n' "$BOLD$GREEN" "$pct" "$NC" "$status" "$temp" "$health"
        fi
    fi
    if command -v termux-wake-lock >/dev/null 2>&1; then
        printf '  Wake-lock utility: %sAvailable%s\n' "$GREEN" "$NC"
    else
        printf '  Wake-lock utility: %sNot found (install termux-api)%s\n' "$YELLOW" "$NC"
    fi
    printf '\n'

    # Canonical PATH
    printf '%s[PATH Order Verification]%s\n' "$BOLD$YELLOW" "$NC"
    printf '  PATH: %s\n' "$PATH"
    if [[ "$PATH" == "$HOME/.local/bin:$HOME/.npm-global/bin:"* ]]; then
        printf '  Order: %sCanonical (~/.local/bin precedes ~/.npm-global/bin)%s\n' "$GREEN" "$NC"
    else
        printf '  Order: %sNon-canonical PATH detected%s\n' "$YELLOW" "$NC"
    fi
    printf '\n'

    # Keyboard Extra-Keys Layout
    printf '%s[Keyboard & Terminal Configuration]%s\n' "$BOLD$YELLOW" "$NC"
    if [[ -f "$HOME/.termux/termux.properties" ]] && grep -qF "extra-keys" "$HOME/.termux/termux.properties"; then
        printf '  Extra keys: %sConfigured in ~/.termux/termux.properties%s\n' "$GREEN" "$NC"
    else
        printf '  Extra keys: %sDefault (run setup.sh --tune-keys to enhance)%s\n' "$YELLOW" "$NC"
    fi
    printf '\n'
}

tune_extra_keys() {
    printf '\n%s=== Termux Developer Extra-Keys & Keyboard Layout ===%s\n\n' "$BOLD$CYAN" "$NC"
    local prop_dir="$HOME/.termux"
    local prop_file="$prop_dir/termux.properties"
    mkdir -p "$prop_dir"

    if [[ -f "$prop_file" ]]; then
        local stamp
        stamp="$(date +%s)"
        cp -p "$prop_file" "$prop_file.bak.$stamp"
        info "Existing termux.properties backed up to $prop_file.bak.$stamp"
    fi

    cat > "$prop_file" <<'PROP_EOF'
### Termux Developer Suite: Enhanced Extra-Keys Layout
extra-keys = [ \
  [ \
    {key: 'ESC', popup: 'PASTE'}, \
    {key: '/', popup: 'BACKSLASH'}, \
    {key: '-', popup: '|'}, \
    'CTRL', \
    {key: 'UP', display: '▲'}, \
    'ALT', \
    {key: 'PGUP', popup: '$'}, \
    {key: KEYBOARD, popup: {macro: "CTRL d", display: '⌧'}} \
  ], \
  [ \
    {key: 'HOME', display: '⇤'}, \
    'END', \
    'TAB', \
    {key: 'LEFT', display: '◀'}, \
    {key: 'DOWN', display: '▼'}, \
    {key: 'RIGHT', display: '▶'}, \
    {key: 'PGDN', popup: '~'}, \
    'DEL' \
  ] \
]
terminal-transcript-rows = 5000
terminal-cursor-style = bar
PROP_EOF

    if command -v termux-reload-settings >/dev/null 2>&1; then
        termux-reload-settings 2>/dev/null || true
    fi
    success "Developer extra-keys layout installed into $prop_file and reloaded."
}

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
    check_cmd "Zipalign" zipalign
    check_cmd "DEX Compiler (d8)" d8
    check_cmd "SDK Manager" sdkmanager
    check_cmd "Android CLI" android
    check_cmd "APK Builder" termux-apk-build

    printf '\n'
}

build_apk_interactive() {
    printf '\n%s=======================================================%s\n' "$BOLD$CYAN" "$NC"
    printf '%s   ⚡ Standalone Android APK Builder (Zero-Gradle)     %s\n' "$BOLD$GREEN" "$NC"
    printf '%s=======================================================%s\n\n' "$BOLD$CYAN" "$NC"

    local apk_cmd="$SETUP_DIR/bin/termux-apk-build"
    if [[ ! -x "$apk_cmd" ]]; then
        if command -v termux-apk-build >/dev/null 2>&1; then
            apk_cmd="$(command -v termux-apk-build)"
        else
            error "termux-apk-build executable not found."
            return 1
        fi
    fi

    printf 'Enter project or source directory [default: current (%s)]:\n' "$(pwd)"
    read -rp "Project directory: " input_proj
    local proj_dir="${input_proj:-$(pwd)}"

    if [[ ! -d "$proj_dir" ]]; then
        error "Directory does not exist: $proj_dir"
        return 1
    fi

    printf 'Enter output APK filename [default: app-signed.apk]:\n'
    read -rp "Output APK: " input_out
    local out_apk="${input_out:-app-signed.apk}"

    printf 'Install to connected device via ADB after compilation? [y/N]: '
    read -rp "" input_install
    local install_args=()
    if [[ "$input_install" =~ ^[Yy] ]]; then
        install_args+=("-i")
    fi

    if command -v termux-share >/dev/null 2>&1; then
        printf 'Open / install APK via Android Package Installer? [y/N]: '
        read -rp "" input_share
        if [[ "$input_share" =~ ^[Yy] ]]; then
            install_args+=("-u")
        fi
    fi

    info "Starting APK synthesis with termux-apk-build..."
    "$apk_cmd" -p "$proj_dir" -o "$out_apk" "${install_args[@]}"
}

get_stage_status() {
    local stage_num="$1"
    case "$stage_num" in
        1) command -v zsh >/dev/null 2>&1 ;;
        2) command -v clang >/dev/null 2>&1 && command -v git >/dev/null 2>&1 ;;
        3) command -v node >/dev/null 2>&1 && command -v pnpm >/dev/null 2>&1 ;;
        4) command -v agy >/dev/null 2>&1 && command -v opencode >/dev/null 2>&1 ;;
        5) [[ -s "$HOME/.ai-env" ]] ;;
        6) [[ -d "${PREFIX:-/data/data/com.termux/files/usr}/opt/android-sdk" ]] && command -v java >/dev/null 2>&1 ;;
        *) return 1 ;;
    esac
}

show_quick_help_dialog() {
    local theme_file="$1"
    local help_text="\Zb\Z6Termux Developer Suite\Zn - Quick Reference Guide\n\n\
\ZbNavigation Controls:\Zn\n\
  • \ZbUp/Down\Zn    : Highlight menu items\n\
  • \ZbEnter\Zn      : Select and run the highlighted item\n\
  • \ZbTab\Zn        : Switch focus between Select, Doctor, Help, and Exit buttons\n\
  • \ZbEsc\Zn        : Exit / Return to Shell\n\n\
\ZbKey Capabilities:\Zn\n\
  • \Zb[1] Pipeline\Zn    : Complete workstation setup (Stages 01 -> 06)\n\
  • \Zb[2-7] Stages\Zn    : Base, Tools, Node.js 24, AI CLIs, Credentials, Android\n\
  • \Zb[8] APK Builder\Zn : Zero-Gradle instant Android APK compilation (<1s)\n\
  • \Zb[9] Verify\Zn      : Full toolchain status audit across all compilers & CLIs\n\
  • \Zb[10] 30-Pt Test\Zn : Ruthless stress & verification test suite\n\
  • \Zb[11] Doctor\Zn     : Hardware telemetry, RAM, storage & diagnostics\n\
  • \Zb[12] Keys\Zn       : Modern developer extra-keys fast touch coding bar\n\
  • \Zb[13] PPK\Zn        : Disable Android Phantom Process Killer\n\
  • \Zb[14] Prune NDK\Zn  : Reclaims ~600MB storage by removing unused sysroots\n\
  • \Zb[15] Clean\Zn      : Deep clean package archives, caches & locks\n\
  • \Zb[16] Pre-Commit\Zn : Install local Git security & ShellCheck hook\n\n\
\ZbGlobal CLI Commands:\Zn\n\
  • \Zbtsuite --apk\Zn      : Build APK directly from command line\n\
  • \Zbtsuite --verify\Zn   : Run toolchain verification\n\
  • \Zbtsuite --test\Zn     : Run 30-point test suite\n\
  • \Zbtsuite --doctor\Zn   : System diagnostics\n\
  • \Zbtsuite --clean\Zn    : Release locks & purge temp caches"

    DIALOGRC="$theme_file" dialog --colors \
        --title " \Zb\Z6Help & Quick Reference\Zn " \
        --msgbox "$help_text" 0 0 || true
}

show_quick_help_ansi() {
    clear 2>/dev/null || true
    printf '%s╭───────────────────────────────────────────────────────────────────╮%s\n' "$CYAN" "$NC"
    printf '%s│%s   📖 \033[1;37mTermux Developer Suite - Quick Reference Guide\033[0m              %s│%s\n' "$CYAN" "$BOLD" "$CYAN" "$NC"
    printf '%s╰───────────────────────────────────────────────────────────────────╯%s\n\n' "$CYAN" "$NC"

    printf '%sNavigation & Shortcuts:%s\n' "$BOLD$YELLOW" "$NC"
    printf '  • Type any option number %s(1-16, 0)%s or mnemonic letter %s(A-Z)%s and press Enter.\n' "$CYAN" "$NC" "$CYAN" "$NC"
    printf '  • Tab-completion is available for all flags: %stsuite --<TAB>%s\n\n' "$GREEN" "$NC"

    printf '%sCore Features:%s\n' "$BOLD$YELLOW" "$NC"
    printf '  %s[1/A]%s Run Complete Pipeline    : Sequential execution of Stages 01 to 06.\n' "$BOLD$CYAN" "$NC"
    printf '  %s[2-7]%s Modular Stages          : Individual provisioning stages.\n' "$BOLD$CYAN" "$NC"
    printf '  %s[8/K]%s Standalone APK Builder  : Sub-second zero-Gradle APK compilation engine.\n' "$BOLD$GREEN" "$NC"
    printf '  %s[9/V]%s Verify All Toolchains   : Status report of all compilers, SDKs, and CLIs.\n' "$BOLD$GREEN" "$NC"
    printf ' %s[10/T]%s 30-Point Stress Suite   : Full regression test verifying locks, DEX, APK, NDK.\n' "$BOLD$GREEN" "$NC"
    printf ' %s[11/H]%s System Doctor           : Real-time RAM, storage, and platform diagnostics.\n' "$BOLD$GREEN" "$NC"
    printf ' %s[12/X]%s Developer Extra-Keys    : Fast mobile coding keyboard bar in Termux.\n' "$BOLD$YELLOW" "$NC"
    printf ' %s[13/P]%s Disable PPK             : Remove 32-child-process background restriction.\n' "$BOLD$YELLOW" "$NC"
    printf ' %s[14/R]%s Prune Unused NDK        : Save ~600MB storage by removing unused sysroots.\n' "$BOLD$YELLOW" "$NC"
    printf ' %s[15/C]%s Deep Clean System       : Clear caches, apt archives, and stale locks.\n' "$BOLD$YELLOW" "$NC"
    printf ' %s[16/G]%s Install Pre-Commit Hook : Non-destructive Git commit validation hook.\n\n' "$BOLD$YELLOW" "$NC"

    printf '%sGlobal Commands:%s\n' "$BOLD$YELLOW" "$NC"
    printf '  tsuite                 : Open interactive TUI from anywhere\n'
    printf '  termux-apk-build -p .  : Compile current Android project into signed APK\n'
    printf '  tsuite --doctor        : Run system health diagnostics\n'
    printf '  tsuite --test          : Run 30-point stress test\n\n'
    printf '%sPress Enter to return to the interactive menu...%s' "$BOLD$CYAN" "$NC"
    read -r
}

show_dialog_tui() {
    local choice exit_code
    local ram_free disk_free backtitle

    # Generate modern Obsidian / Neon dialog theme
    local theme_file="${TMPDIR:-$PREFIX/tmp}/dialogrc.$$"
    cat > "$theme_file" <<'THEME_EOF'
use_shadow = OFF
use_colors = ON
screen_color = (CYAN,BLACK,ON)
dialog_color = (WHITE,BLACK,OFF)
title_color = (CYAN,BLACK,ON)
border_color = (CYAN,BLACK,ON)
button_active_color = (BLACK,CYAN,ON)
button_inactive_color = (WHITE,BLACK,OFF)
button_key_active_color = (BLACK,YELLOW,ON)
button_key_inactive_color = (YELLOW,BLACK,OFF)
button_label_active_color = (BLACK,CYAN,ON)
button_label_inactive_color = (WHITE,BLACK,OFF)
inputbox_color = (WHITE,BLACK,OFF)
inputbox_border_color = (CYAN,BLACK,ON)
menubox_color = (WHITE,BLACK,OFF)
menubox_border_color = (BLUE,BLACK,ON)
item_color = (WHITE,BLACK,OFF)
item_selected_color = (BLACK,CYAN,ON)
tag_color = (YELLOW,BLACK,ON)
tag_selected_color = (BLACK,YELLOW,ON)
tag_key_color = (YELLOW,BLACK,ON)
tag_key_selected_color = (BLACK,YELLOW,ON)
check_color = (WHITE,BLACK,OFF)
check_selected_color = (BLACK,CYAN,ON)
uarrow_color = (GREEN,BLACK,ON)
darrow_color = (GREEN,BLACK,ON)
THEME_EOF

    # Validate that dialog can initialize on this terminal; fallback to ANSI menu if not
    if ! DIALOGRC="$theme_file" dialog --colors --print-maxsize >/dev/null 2>&1; then
        rm -f "$theme_file" 2>/dev/null || true
        show_menu_ansi
        return
    fi

    while true; do
        ram_free="$(free -h 2>/dev/null | awk '/Mem:/ {print $7}' || echo 'N/A')"
        disk_free="$(df -h "${PREFIX:-/data/data/com.termux/files/usr}" 2>/dev/null | awk 'NR==2 {print $4}' || echo 'N/A')"
        local bat_str=""
        if command -v termux-battery-status >/dev/null 2>&1; then
            local b_pct
            b_pct="$(termux-battery-status 2>/dev/null | jq -r '.percentage // empty' 2>/dev/null || true)"
            [[ -n "$b_pct" ]] && bat_str="  │  Bat: ${b_pct}%"
        fi
        backtitle="Termux-Dev ARM64 Workstation  │  RAM: ${ram_free} Avail  │  Disk: ${disk_free} Free${bat_str}"

        local s1_d s2_d s3_d s4_d s5_d s6_d
        get_stage_status 1 && s1_d="\Zb\Z2[✓]\Zn" || s1_d="\Zb\Z1[○]\Zn"
        get_stage_status 2 && s2_d="\Zb\Z2[✓]\Zn" || s2_d="\Zb\Z1[○]\Zn"
        get_stage_status 3 && s3_d="\Zb\Z2[✓]\Zn" || s3_d="\Zb\Z1[○]\Zn"
        get_stage_status 4 && s4_d="\Zb\Z2[✓]\Zn" || s4_d="\Zb\Z1[○]\Zn"
        get_stage_status 5 && s5_d="\Zb\Z2[✓]\Zn" || s5_d="\Zb\Z1[○]\Zn"
        get_stage_status 6 && s6_d="\Zb\Z2[✓]\Zn" || s6_d="\Zb\Z1[○]\Zn"

        exit_code=0
        choice=$(DIALOGRC="$theme_file" dialog --stdout --clear \
            --colors \
            --backtitle "$backtitle" \
            --title " \Zb\Z6Termux Developer Suite\Zn " \
            --ok-label "Select" \
            --extra-button --extra-label "Doctor" \
            --help-button --help-label "Help" \
            --cancel-label "Exit" \
            --menu "Select an action with \Zb\Z3Up/Down\Zn and press \Zb\Z3Enter\Zn:" \
            0 0 0 \
            "1"  "▶  Run Complete Pipeline (Stages 01 -> 06)" \
            "2"  "$s1_d Stage 01: Base System, Repos & Zsh" \
            "3"  "$s2_d Stage 02: Essentials & Dev Toolchains" \
            "4"  "$s3_d Stage 03: Node.js 24 & Package Managers" \
            "5"  "$s4_d Stage 04: AI CLI Suite (5 Assistants)" \
            "6"  "$s5_d Stage 05: Private AI Environment (~/.ai-env)" \
            "7"  "$s6_d Stage 06: Android SDK, NDK & OpenJDK 21" \
            "8"  "⚡ Build Android APK (Sub-Second Engine)" \
            "9"  "✓  Verify All Installed Tools & CLIs" \
            "10" "🧪 Run Ruthless 30-Point Stress Test Suite" \
            "11" "🩺 System Doctor: Health & Diagnostics" \
            "12" "⌨️  Configure Developer Extra-Keys" \
            "13" "🔋 Disable Phantom Process Killer" \
            "14" "✂️  Prune Unused NDK Sysroots (Save ~600MB)" \
            "15" "🧹 Deep Clean Cache, Temp Files & Locks" \
            "16" "🛡️  Install Local Git Pre-Commit Hook" \
            "0"  "🚪 Exit to Shell") || exit_code=$?

        # Handle Help and Doctor buttons
        if [[ $exit_code -eq 2 ]]; then
            show_quick_help_dialog "$theme_file"
            continue
        elif [[ $exit_code -eq 3 ]]; then
            clear
            doctor_system
            printf '\n%sPress Enter to return to the interactive menu...%s' "$BOLD$CYAN" "$NC"
            read -r
            continue
        elif [[ $exit_code -ne 0 ]]; then
            break
        fi

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
            8)
                local p_dir o_apk
                p_dir=$(DIALOGRC="$theme_file" dialog --stdout --clear --title " Project Directory " \
                    --inputbox "Enter path to Android project / directory:" 10 60 "$(pwd)") || p_dir=""
                if [[ -n "$p_dir" ]]; then
                    o_apk=$(DIALOGRC="$theme_file" dialog --stdout --clear --title " Output APK " \
                        --inputbox "Enter output APK filename:" 10 60 "app-signed.apk") || o_apk="app-signed.apk"
                    local extra_opts=()
                    if command -v termux-share >/dev/null 2>&1; then
                        if DIALOGRC="$theme_file" dialog --title " Install APK " \
                            --yesno "Open generated APK with Android Package Installer upon completion?" 7 60; then
                            extra_opts+=("-u")
                        fi
                    fi
                    clear
                    "$SETUP_DIR/bin/termux-apk-build" -p "$p_dir" -o "${o_apk:-app-signed.apk}" "${extra_opts[@]}"
                fi
                ;;
            9) verify_all ;;
            10) bash "$SETUP_DIR/test-suite.sh" ;;
            11) doctor_system ;;
            12) tune_extra_keys ;;
            13) tune_device ;;
            14) prune_ndk ;;
            15) clean_system ;;
            16) install_git_hooks ;;
            0) break ;;
        esac

        printf '\n%sPress Enter to return to the interactive menu...%s' "$BOLD$CYAN" "$NC"
        read -r
    done
    rm -f "$theme_file" 2>/dev/null || true
    clear 2>/dev/null || true
}

show_menu_ansi() {
    local ram_free disk_free bat_pct
    while true; do
        ram_free="$(free -h 2>/dev/null | awk '/Mem:/ {print $7}' || echo 'N/A')"
        disk_free="$(df -h "${PREFIX:-/data/data/com.termux/files/usr}" 2>/dev/null | awk 'NR==2 {print $4}' || echo 'N/A')"
        bat_pct=""
        if command -v termux-battery-status >/dev/null 2>&1; then
            bat_pct="$(termux-battery-status 2>/dev/null | jq -r '.percentage // empty' 2>/dev/null || true)"
        fi

        local s1_a s2_a s3_a s4_a s5_a s6_a
        get_stage_status 1 && s1_a="${GREEN}${BOLD}[✓]${NC}" || s1_a="${YELLOW}[○]${NC}"
        get_stage_status 2 && s2_a="${GREEN}${BOLD}[✓]${NC}" || s2_a="${YELLOW}[○]${NC}"
        get_stage_status 3 && s3_a="${GREEN}${BOLD}[✓]${NC}" || s3_a="${YELLOW}[○]${NC}"
        get_stage_status 4 && s4_a="${GREEN}${BOLD}[✓]${NC}" || s4_a="${YELLOW}[○]${NC}"
        get_stage_status 5 && s5_a="${GREEN}${BOLD}[✓]${NC}" || s5_a="${YELLOW}[○]${NC}"
        get_stage_status 6 && s6_a="${GREEN}${BOLD}[✓]${NC}" || s6_a="${YELLOW}[○]${NC}"

        clear 2>/dev/null || true
        printf '%s╭───────────────────────────────────────────────────────────────────╮%s\n' "$CYAN" "$NC"
        printf '%s│%s   🚀 \033[1;37mTermux Developer & AI Suite\033[0m \033[1;36m(ARM64 / aarch64)\033[0m              %s│%s\n' "$CYAN" "$BOLD" "$CYAN" "$NC"
        if [[ -n "$bat_pct" ]]; then
            printf '%s│%s   Arch: \033[1;33maarch64\033[0m │ RAM: \033[1;32m%-6s\033[0m │ Disk: \033[1;32m%-7s\033[0m │ Bat: \033[1;32m%-4s\033[0m   %s│%s\n' "$CYAN" "$NC" "$ram_free" "$disk_free" "${bat_pct}%" "$CYAN" "$NC"
        else
            printf '%s│%s   Arch: \033[1;33maarch64\033[0m │ RAM Avail: \033[1;32m%-7s\033[0m │ Free Disk: \033[1;32m%-8s\033[0m    %s│%s\n' "$CYAN" "$NC" "$ram_free" "$disk_free" "$CYAN" "$NC"
        fi
        printf '%s╰───────────────────────────────────────────────────────────────────╯%s\n\n' "$CYAN" "$NC"

        printf ' %s%s┌── [1] COMPLETE WORKSTATION PIPELINE ────────────────────────────┐%s\n' "$BOLD" "$BLUE" "$NC"
        printf ' %s│%s  %s[1/A]%s  %s▶%s  Run Complete Workstation Setup (Stages 01 -> 06)      %s│%s\n' "$BLUE" "$NC" "$BOLD$YELLOW" "$NC" "$GREEN$BOLD" "$NC" "$BLUE" "$NC"
        printf ' %s└─── Modular Setup Stages ─────────────────────────────────────────┘%s\n' "$BLUE" "$NC"
        printf '   %s[2/B]%s %s Stage 01: Base System, Repositories & Zsh Shell\n' "$BOLD$CYAN" "$NC" "$s1_a"
        printf '   %s[3/E]%s %s Stage 02: Build Tools, Compilers & Dev Essentials\n' "$BOLD$CYAN" "$NC" "$s2_a"
        printf '   %s[4/N]%s %s Stage 03: Node.js 24 LTS & Package Managers (ARM64)\n' "$BOLD$CYAN" "$NC" "$s3_a"
        printf '   %s[5/I]%s %s Stage 04: AI Coding Assistant Suite (5 CLIs)\n' "$BOLD$CYAN" "$NC" "$s4_a"
        printf '   %s[6/S]%s %s Stage 05: Private AI Environment & Credentials (~/.ai-env)\n' "$BOLD$CYAN" "$NC" "$s5_a"
        printf '   %s[7/D]%s %s Stage 06: Android SDK, NDK (Clang 21) & OpenJDK 21\n\n' "$BOLD$CYAN" "$NC" "$s6_a"

        printf ' %s%s┌── [2] APPLICATION COMPILATION & VERIFICATION ───────────────────┐%s\n' "$BOLD" "$GREEN" "$NC"
        printf '   %s[8/K]%s  ⚡ Build Android APK (Sub-Second Zero-Gradle Engine)\n' "$BOLD$GREEN" "$NC"
        printf '   %s[9/V]%s  ✓  Verify All Installed Compilers, SDKs & Toolchains\n' "$BOLD$GREEN" "$NC"
        printf '  %s[10/T]%s  🧪 Run Ruthless 30-Point Stress & Verification Suite\n' "$BOLD$GREEN" "$NC"
        printf '  %s[11/H]%s  🩺 System Doctor: Hardware, RAM & Stability Diagnostics\n' "$BOLD$GREEN" "$NC"
        printf ' %s└───────────────────────────────────────────────────────────────────┘%s\n\n' "$GREEN" "$NC"

        printf ' %s%s┌── [3] SYSTEM TUNING, STORAGE & REPOSITORY HYGIENE ───────────────┐%s\n' "$BOLD" "$YELLOW" "$NC"
        printf '  %s[12/X]%s  ⌨️  Configure Developer Extra-Keys (Fast Touch Coding Bar)\n' "$BOLD$YELLOW" "$NC"
        printf '  %s[13/P]%s  🔋 Disable Phantom Process Killer (Android 14/15/16 PPK)\n' "$BOLD$YELLOW" "$NC"
        printf '  %s[14/R]%s  ✂️  Prune Unused NDK Sysroots (Frees ~600MB Storage)\n' "$BOLD$YELLOW" "$NC"
        printf '  %s[15/C]%s  🧹 Deep Clean Cache, Temp Files & Concurrency Locks\n' "$BOLD$YELLOW" "$NC"
        printf '  %s[16/G]%s  🛡️  Install Local Git Pre-Commit Security Lint Hook\n' "$BOLD$YELLOW" "$NC"
        printf ' %s└───────────────────────────────────────────────────────────────────┘%s\n\n' "$YELLOW" "$NC"

        printf '  %s[?/U]%s  📖 Help & Documentation Guide\n' "$BOLD$CYAN" "$NC"
        printf '  %s[0/Q]%s  🚪 Exit to Shell\n\n' "$BOLD$RED" "$NC"

        printf '%sSelect an option [1-16, A-Z, ?, or 0/Q to exit]: %s' "$BOLD$CYAN" "$NC"
        read -rp "" raw_choice
        local choice
        choice="$(echo "${raw_choice:-}" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"

        case "$choice" in
            1|a)
                run_stage "01-termux-base.sh" "Stage 01: Termux Base Setup"
                run_stage "02-termux-essentials.sh" "Stage 02: Essentials & Dev Tools"
                run_stage "03-termux-node-toolchain.sh" "Stage 03: Node.js Toolchain"
                run_stage "04-termux-ai-cli.sh" "Stage 04: AI CLI Suite"
                run_stage "05-ai-env.sh" "Stage 05: AI Environment & Credentials"
                run_stage "06-termux-android-sdk.sh" "Stage 06: Android SDK & NDK Toolchain"
                verify_all
                ;;
            2|b) run_stage "01-termux-base.sh" "Stage 01: Termux Base Setup" ;;
            3|e) run_stage "02-termux-essentials.sh" "Stage 02: Essentials & Dev Tools" ;;
            4|n) run_stage "03-termux-node-toolchain.sh" "Stage 03: Node.js Toolchain" ;;
            5|i) run_stage "04-termux-ai-cli.sh" "Stage 04: AI CLI Suite" ;;
            6|s) run_stage "05-ai-env.sh" "Stage 05: AI Environment & Credentials" ;;
            7|d) run_stage "06-termux-android-sdk.sh" "Stage 06: Android SDK & NDK Toolchain" ;;
            8|k) build_apk_interactive ;;
            9|v) verify_all ;;
            10|t) bash "$SETUP_DIR/test-suite.sh" ;;
            11|h) doctor_system ;;
            12|x) tune_extra_keys ;;
            13|p) tune_device ;;
            14|r) prune_ndk ;;
            15|c) clean_system ;;
            16|g) install_git_hooks ;;
            \?|u|help)
                show_quick_help_ansi
                ;;
            0|q)
                info "Exiting."
                exit 0
                ;;
            *)
                warn "Invalid selection: $raw_choice"
                ;;
        esac

        printf '\n%sPress Enter to return to the interactive menu...%s' "$BOLD$CYAN" "$NC"
        read -r
    done
}

show_menu() {
    if command -v dialog >/dev/null 2>&1 && [[ -t 0 && -t 1 ]] && [[ "${USE_TUI:-1}" != "0" ]]; then
        show_dialog_tui
        return
    fi
    show_menu_ansi
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
        --apk|--build-apk)
            build_apk_interactive
            ;;
        --verify)
            verify_all
            ;;
        --doctor|--health)
            doctor_system
            ;;
        --test|--smoke-test)
            bash "$SETUP_DIR/test-suite.sh"
            ;;
        --clean)
            clean_system
            ;;
        --prune-ndk)
            prune_ndk
            ;;
        --tune-device)
            tune_device
            ;;
        --tune-keys)
            tune_extra_keys
            ;;
        --install-hooks)
            install_git_hooks
            ;;
        --help|-h)
            printf 'Usage: %s [OPTION]\n\n' "$(basename "$0")"
            printf 'Options:\n'
            printf '  --all            Execute all setup stages (01 -> 06)\n'
            printf '  --base           Execute Stage 01: Base & Repos\n'
            printf '  --essentials     Execute Stage 02: Essentials & Dev Tools\n'
            printf '  --node           Execute Stage 03: Node.js Toolchain\n'
            printf '  --ai             Execute Stage 04: AI CLI Suite\n'
            printf '  --ai-env         Execute Stage 05: AI Environment Setup\n'
            printf '  --android        Execute Stage 06: Android SDK & NDK Setup\n'
            printf '  --apk            Build Android APK interactively with zero Gradle\n'
            printf '  --verify         Verify all installed tools\n'
            printf '  --doctor         Run Termux system health & environment diagnostics\n'
            printf '  --test           Run ruthless stress & verification test suite\n'
            printf '  --prune-ndk      Prune unused NDK sysroots (saves ~600MB storage)\n'
            printf '  --tune-device    Disable Phantom Process Killer (root or ADB guidance)\n'
            printf '  --tune-keys      Configure enhanced dual-row developer extra-keys layout\n'
            printf '  --install-hooks  Install local Git pre-commit verification hook\n'
            printf '  --clean          Remove locks, temp files, and apt package archives\n'
            printf '  --help           Display this help message\n'
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
