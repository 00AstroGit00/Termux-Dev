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
PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
export PREFIX

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
    local bash_comp1="${PREFIX:-/data/data/com.termux/files/usr}/etc/bash_completion.d"
    local bash_comp2="${PREFIX:-/data/data/com.termux/files/usr}/share/bash-completion/completions"
    mkdir -p "$zsh_site" "$bash_comp1" "$bash_comp2"
    if [[ -d "$SETUP_DIR/completions" ]]; then
        [[ -f "$SETUP_DIR/completions/_tsuite" ]] && cp -f "$SETUP_DIR/completions/_tsuite" "$zsh_site/_tsuite" && cp -f "$SETUP_DIR/completions/_tsuite" "$zsh_site/_termux-suite"
        [[ -f "$SETUP_DIR/completions/_termux-apk-build" ]] && cp -f "$SETUP_DIR/completions/_termux-apk-build" "$zsh_site/_termux-apk-build" && cp -f "$SETUP_DIR/completions/_termux-apk-build" "$zsh_site/_apk-build"
        [[ -f "$SETUP_DIR/completions/_termux-wireless-adb" ]] && cp -f "$SETUP_DIR/completions/_termux-wireless-adb" "$zsh_site/_termux-wireless-adb" && cp -f "$SETUP_DIR/completions/_termux-wireless-adb" "$zsh_site/_wireless-adb" && cp -f "$SETUP_DIR/completions/_termux-wireless-adb" "$zsh_site/_tw-adb"
        if [[ -f "$SETUP_DIR/completions/tsuite.bash" ]]; then
            cp -f "$SETUP_DIR/completions/tsuite.bash" "$bash_comp1/tsuite"
            cp -f "$SETUP_DIR/completions/tsuite.bash" "$bash_comp2/tsuite"
            cp -f "$SETUP_DIR/completions/tsuite.bash" "$bash_comp2/termux-suite"
            cp -f "$SETUP_DIR/completions/tsuite.bash" "$bash_comp2/termux-apk-build"
            cp -f "$SETUP_DIR/completions/tsuite.bash" "$bash_comp2/apk-build"
            cp -f "$SETUP_DIR/completions/tsuite.bash" "$bash_comp2/termux-wireless-adb"
            cp -f "$SETUP_DIR/completions/tsuite.bash" "$bash_comp2/wireless-adb"
        fi
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
    local avail_kb
    avail_kb="$(df -k "${HOME}" 2>/dev/null | awk 'NR==2 {print $4}' || echo "")"
    if [[ "$avail_kb" =~ ^[0-9]+$ ]] && (( avail_kb < 2097152 )); then
        printf '  %s[WARNING] Low storage detected (<2GB available). SDK and Gradle builds may fail.%s\n' "$YELLOW" "$NC"
    fi
    printf '\n'

    # RAM
    printf '%s[Memory (RAM)]%s\n' "$BOLD$YELLOW" "$NC"
    free -h 2>/dev/null || free -m
    local total_mem_kb
    total_mem_kb="$(grep -i MemTotal /proc/meminfo 2>/dev/null | awk '{print $2}' || echo "")"
    if [[ "$total_mem_kb" =~ ^[0-9]+$ ]] && (( total_mem_kb < 4194304 )); then
        printf '  %s[INFO] Low RAM (<4GB). Suggested in gradle.properties: org.gradle.jvmargs=-Xmx1024m%s\n' "$CYAN" "$NC"
    fi
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

    # Kernel & Android Platform
    printf '%s[Kernel Architecture & Android Storage]%s\n' "$BOLD$YELLOW" "$NC"
    local page_size
    page_size="$(grep -m1 -i "KernelPageSize" /proc/self/smaps 2>/dev/null | awk '{print $2, $3}' || echo '4 kB')"
    printf '  Kernel page size: %s%s%s (16KB Android 15+ compatible)\n' "$BOLD$GREEN" "$page_size" "$NC"
    if [[ -d "$HOME/storage" ]]; then
        printf '  Android storage:  %sConfigured (~/storage accessible)%s\n' "$GREEN" "$NC"
    else
        printf '  Android storage:  %sNot configured (run "termux-setup-storage")%s\n' "$YELLOW" "$NC"
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
    check_cmd "Wireless ADB" termux-wireless-adb

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

launch_wireless_adb() {
    local adb_helper="$SETUP_DIR/bin/termux-wireless-adb"
    if [[ ! -x "$adb_helper" ]]; then
        if command -v termux-wireless-adb >/dev/null 2>&1; then
            adb_helper="$(command -v termux-wireless-adb)"
        else
            error "termux-wireless-adb executable not found."
            return 1
        fi
    fi
    bash "$adb_helper" "$@"
}

backup_vault() {
    local target_file="${1:-}"
    if ! command -v openssl >/dev/null 2>&1; then
        error "openssl is required for encrypted backups. Install via: pkg install openssl"
        return 1
    fi

    if [[ -z "$target_file" ]]; then
        local dest_dir="$HOME"
        if [[ -d "$HOME/storage/shared" ]]; then
            dest_dir="$HOME/storage/shared"
        fi
        target_file="$dest_dir/TermuxDev-Vault-$(date +%Y%m%d_%H%M%S).enc"
    fi

    info "Preparing encrypted backup of Termux developer environment..."
    local files_to_backup=()
    [[ -f "$HOME/.ai-env" ]] && files_to_backup+=(".ai-env")
    [[ -d "$HOME/.ssh" ]] && files_to_backup+=(".ssh")
    [[ -f "$HOME/.gitconfig" ]] && files_to_backup+=(".gitconfig")
    [[ -f "$HOME/.android-env" ]] && files_to_backup+=(".android-env")
    [[ -d "$HOME/.termux" ]] && files_to_backup+=(".termux")

    if [[ ${#files_to_backup[@]} -eq 0 ]]; then
        warn "No credentials or configuration files found to back up."
        return 0
    fi

    printf 'Files included in backup archive:\n'
    local f
    for f in "${files_to_backup[@]}"; do
        printf '  • ~/%s\n' "$f"
    done
    printf '\n'

    printf '%sEnter encryption passphrase for vault:%s\n' "$BOLD$YELLOW" "$NC"
    mkdir -p "$(dirname "$target_file")"
    if (cd "$HOME" && tar -cf - "${files_to_backup[@]}") | openssl enc -aes-256-cbc -pbkdf2 -iter 100000 -salt -out "$target_file"; then
        chmod 600 "$target_file" 2>/dev/null || true
        success "Encrypted backup successfully created at: $target_file"
        info "Archive is encrypted with AES-256-CBC (PBKDF2 100,000 iterations)."
        if command -v termux-notification >/dev/null 2>&1; then
            termux-notification --id "vault-backup" --title "Backup Vault Created" --content "Saved: $(basename "$target_file")" --priority high 2>/dev/null || true
        fi
    else
        error "Backup encryption failed."
        rm -f "$target_file" 2>/dev/null || true
        return 1
    fi
}

restore_vault() {
    local target_file="${1:-}"
    if ! command -v openssl >/dev/null 2>&1; then
        error "openssl is required to restore encrypted backups."
        return 1
    fi

    if [[ -z "$target_file" ]]; then
        local default_search=()
        if [[ -d "$HOME/storage/shared" ]]; then
            mapfile -t default_search < <(find "$HOME/storage/shared" -maxdepth 1 -name "TermuxDev-Vault-*.enc" 2>/dev/null | sort -r)
        fi
        if [[ ${#default_search[@]} -gt 0 ]]; then
            target_file="${default_search[0]}"
            printf '%sFound recent vault backup: %s%s\n' "$BOLD$GREEN" "$target_file" "$NC"
            printf '%sUse this backup file? [Y/n] or enter path: %s' "$BOLD$CYAN" "$NC"
            local resp
            read -rp "" resp
            if [[ -n "$resp" && "$resp" != [yY]* ]]; then
                target_file="$resp"
            fi
        else
            printf '%sEnter path to encrypted vault archive (.enc): %s' "$BOLD$CYAN" "$NC"
            read -rp "" target_file
        fi
    fi

    target_file="$(echo "$target_file" | tr -d '[:space:]')"
    if [[ ! -f "$target_file" ]]; then
        error "Backup archive not found at: $target_file"
        return 1
    fi

    info "Restoring developer vault from: $target_file..."
    printf '%sEnter decryption passphrase:%s\n' "$BOLD$YELLOW" "$NC"
    if openssl enc -d -aes-256-cbc -pbkdf2 -iter 100000 -in "$target_file" | (cd "$HOME" && tar -xvf -); then
        [[ -f "$HOME/.ai-env" ]] && chmod 600 "$HOME/.ai-env"
        if [[ -d "$HOME/.ssh" ]]; then
            chmod 700 "$HOME/.ssh"
            find "$HOME/.ssh" -name "id_*" ! -name "*.pub" -exec chmod 600 {} + 2>/dev/null || true
            find "$HOME/.ssh" -name "*.pub" -exec chmod 644 {} + 2>/dev/null || true
            [[ -f "$HOME/.ssh/known_hosts" ]] && chmod 644 "$HOME/.ssh/known_hosts" 2>/dev/null || true
        fi
        success "Encrypted developer vault restored successfully!"
        info "Enforced secure permissions (600 on ~/.ai-env and private SSH keys)."
    else
        error "Decryption failed. Check if passphrase or archive is valid."
        return 1
    fi
}

vault_interactive() {
    local theme_file="${1:-}"
    if [[ -n "$theme_file" ]] && command -v dialog >/dev/null 2>&1; then
        local v_choice=""
        local v_exit=0
        v_choice=$(DIALOGRC="$theme_file" dialog --stdout --clear \
            --colors \
            --title " \Zb\Z6Encrypted Developer Vault\Zn " \
            --menu "Select a vault operation:" 12 65 2 \
            "1" "🔒 Backup Secrets & Config to Encrypted Archive" \
            "2" "🔓 Restore Developer Environment from Archive") || v_exit=$?
        if [[ $v_exit -ne 0 || -z "$v_choice" ]]; then
            return 0
        fi
        clear
        if [[ "$v_choice" == "1" ]]; then
            backup_vault
        elif [[ "$v_choice" == "2" ]]; then
            restore_vault
        fi
    else
        clear 2>/dev/null || true
        printf '%s=== Encrypted Developer Vault ===%s\n\n' "$BOLD$CYAN" "$NC"
        printf '1) %sBackup secrets & environment%s (~/.ai-env, ~/.ssh, ~/.gitconfig)\n' "$BOLD$GREEN" "$NC"
        printf '2) %sRestore environment%s from encrypted archive\n' "$BOLD$YELLOW" "$NC"
        printf '0) Return to main menu\n\n'
        printf '%sSelect an option [1-2, or 0]: %s' "$BOLD$CYAN" "$NC"
        local v_sel
        read -rp "" v_sel
        case "$v_sel" in
            1) backup_vault ;;
            2) restore_vault ;;
            *) info "Vault operation canceled." ;;
        esac
    fi
}

run_wizard_dialog() {
    local theme_file="$1"
    local s1_d s2_d s3_d s4_d s5_d s6_d
    get_stage_status 1 && s1_d="off" || s1_d="on"
    get_stage_status 2 && s2_d="off" || s2_d="on"
    get_stage_status 3 && s3_d="off" || s3_d="on"
    get_stage_status 4 && s4_d="off" || s4_d="on"
    get_stage_status 5 && s5_d="off" || s5_d="on"
    get_stage_status 6 && s6_d="off" || s6_d="on"

    local selections=""
    local wiz_exit=0
    selections=$(DIALOGRC="$theme_file" dialog --stdout --clear \
        --colors \
        --title " \Zb\Z6Custom Multi-Stage Selection Wizard\Zn " \
        --checklist "Toggle stages with \Zb\Z3Spacebar\Zn and press \Zb\Z3Enter\Zn to execute:\n(Uncompleted stages are pre-selected)" \
        18 72 6 \
        "1" "Stage 01: Base System, Repos & Zsh" "$s1_d" \
        "2" "Stage 02: Essentials & Dev Toolchains" "$s2_d" \
        "3" "Stage 03: Node.js 24 & Package Managers" "$s3_d" \
        "4" "Stage 04: AI CLI Suite (5 Assistants)" "$s4_d" \
        "5" "Stage 05: Private AI Environment (~/.ai-env)" "$s5_d" \
        "6" "Stage 06: Android SDK, NDK & OpenJDK 21" "$s6_d") || wiz_exit=$?

    if [[ $wiz_exit -ne 0 || -z "$selections" ]]; then
        info "Wizard canceled."
        return 0
    fi

    clear
    info "Executing selected wizard stages: $selections"
    local sel
    for sel in $selections; do
        sel="${sel//\"/}"
        case "$sel" in
            1) run_stage "01-termux-base.sh" "Stage 01: Termux Base Setup" ;;
            2) run_stage "02-termux-essentials.sh" "Stage 02: Essentials & Dev Tools" ;;
            3) run_stage "03-termux-node-toolchain.sh" "Stage 03: Node.js Toolchain" ;;
            4) run_stage "04-termux-ai-cli.sh" "Stage 04: AI CLI Suite" ;;
            5) run_stage "05-ai-env.sh" "Stage 05: AI Environment & Credentials" ;;
            6) run_stage "06-termux-android-sdk.sh" "Stage 06: Android SDK & NDK Toolchain" ;;
        esac
    done
    verify_all
}

run_wizard_ansi() {
    clear 2>/dev/null || true
    printf '%s=== Custom Multi-Stage Selection Wizard ===%s\n\n' "$BOLD$CYAN" "$NC"
    printf 'Select which stages to execute. Enter numbers separated by space or commas (e.g. 1 3 6):\n\n'

    local s1_a s2_a s3_a s4_a s5_a s6_a
    get_stage_status 1 && s1_a="${GREEN}[Installed]${NC}" || s1_a="${YELLOW}[Pending]${NC}"
    get_stage_status 2 && s2_a="${GREEN}[Installed]${NC}" || s2_a="${YELLOW}[Pending]${NC}"
    get_stage_status 3 && s3_a="${GREEN}[Installed]${NC}" || s3_a="${YELLOW}[Pending]${NC}"
    get_stage_status 4 && s4_a="${GREEN}[Installed]${NC}" || s4_a="${YELLOW}[Pending]${NC}"
    get_stage_status 5 && s5_a="${GREEN}[Installed]${NC}" || s5_a="${YELLOW}[Pending]${NC}"
    get_stage_status 6 && s6_a="${GREEN}[Installed]${NC}" || s6_a="${YELLOW}[Pending]${NC}"

    printf '  [1] Stage 01: Base System, Repositories & Zsh %s\n' "$s1_a"
    printf '  [2] Stage 02: Build Tools, Compilers & Dev Essentials %s\n' "$s2_a"
    printf '  [3] Stage 03: Node.js 24 LTS & Package Managers %s\n' "$s3_a"
    printf '  [4] Stage 04: AI Coding Assistant Suite (5 CLIs) %s\n' "$s4_a"
    printf '  [5] Stage 05: Private AI Credentials (~/.ai-env) %s\n' "$s5_a"
    printf '  [6] Stage 06: Android SDK, NDK (Clang 21) & Java %s\n\n' "$s6_a"

    local pending=()
    get_stage_status 1 || pending+=(1)
    get_stage_status 2 || pending+=(2)
    get_stage_status 3 || pending+=(3)
    get_stage_status 4 || pending+=(4)
    get_stage_status 5 || pending+=(5)
    get_stage_status 6 || pending+=(6)

    local def_str="${pending[*]:-}"
    printf '%sEnter stages to execute [default: %s, or q to cancel]: %s' "$BOLD$CYAN" "${def_str:-all}" "$NC"
    local raw_wiz
    read -rp "" raw_wiz
    raw_wiz="${raw_wiz:-$def_str}"

    if [[ "$raw_wiz" =~ ^[qQ] || -z "$raw_wiz" ]]; then
        info "Wizard canceled."
        return 0
    fi

    local cleaned
    cleaned="$(echo "$raw_wiz" | tr ',' ' ')"
    local sel
    for sel in $cleaned; do
        case "$sel" in
            1) run_stage "01-termux-base.sh" "Stage 01: Termux Base Setup" ;;
            2) run_stage "02-termux-essentials.sh" "Stage 02: Essentials & Dev Tools" ;;
            3) run_stage "03-termux-node-toolchain.sh" "Stage 03: Node.js Toolchain" ;;
            4) run_stage "04-termux-ai-cli.sh" "Stage 04: AI CLI Suite" ;;
            5) run_stage "05-ai-env.sh" "Stage 05: AI Environment & Credentials" ;;
            6) run_stage "06-termux-android-sdk.sh" "Stage 06: Android SDK & NDK Toolchain" ;;
            *) warn "Skipping unknown stage index: $sel" ;;
        esac
    done
    verify_all
}

run_wizard() {
    local theme_file="${1:-}"
    if [[ -n "$theme_file" ]] && command -v dialog >/dev/null 2>&1; then
        run_wizard_dialog "$theme_file"
    else
        run_wizard_ansi
    fi
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
  • \Zb[W] Wizard\Zn      : Multi-stage selection checklist with auto-detection\n\
  • \Zb[2-7] Stages\Zn    : Base, Tools, Node.js 24, AI CLIs, Credentials, Android\n\
  • \Zb[8] APK Builder\Zn : Zero-Gradle instant Android APK compilation (<1s)\n\
  • \Zb[9] Wireless ADB\Zn: Android 11+ on-device wireless debugging pair/connect\n\
  • \Zb[10] Verify\Zn     : Full toolchain status audit across all compilers & CLIs\n\
  • \Zb[11] 30-Pt Test\Zn : Ruthless stress & verification test suite\n\
  • \Zb[12] Doctor\Zn     : Hardware telemetry, RAM, storage & diagnostics\n\
  • \Zb[13] Keys\Zn       : Modern developer extra-keys fast touch coding bar\n\
  • \Zb[14] PPK\Zn        : Disable Android Phantom Process Killer\n\
  • \Zb[15] Prune NDK\Zn  : Reclaims ~600MB storage by removing unused sysroots\n\
  • \Zb[16] Vault\Zn      : Encrypted backup & restore (AES-256-CBC) for secrets\n\
  • \Zb[17] Clean\Zn      : Deep clean package archives, caches & locks\n\
  • \Zb[18] Pre-Commit\Zn : Install local Git security & ShellCheck hook\n\n\
\ZbGlobal CLI Commands:\Zn\n\
  • \Zbtsuite --wizard\Zn   : Custom stage selection wizard\n\
  • \Zbtsuite --backup\Zn   : Create encrypted developer vault archive\n\
  • \Zbtsuite --restore\Zn  : Restore environment from encrypted vault\n\
  • \Zbtsuite --adb\Zn      : Android 11+ wireless ADB pairing helper\n\
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
    printf '  • Type any option number %s(1-18, 0)%s or letter %s(A-Z, W, ?)%s for instant response.\n' "$CYAN" "$NC" "$CYAN" "$NC"
    printf '  • Tab-completion is available for all flags: %stsuite --<TAB>%s\n\n' "$GREEN" "$NC"

    printf '%sCore Features:%s\n' "$BOLD$YELLOW" "$NC"
    printf '  %s[1/A]%s Run Complete Pipeline    : Sequential execution of Stages 01 to 06.\n' "$BOLD$CYAN" "$NC"
    printf '  %s[W]%s   Custom Stage Wizard     : Interactive multi-stage checklist.\n' "$BOLD$CYAN" "$NC"
    printf '  %s[2-7]%s Modular Stages          : Individual provisioning stages.\n' "$BOLD$CYAN" "$NC"
    printf '  %s[8/K]%s Standalone APK Builder  : Sub-second zero-Gradle APK compilation engine.\n' "$BOLD$GREEN" "$NC"
    printf '  %s[9/Y]%s Wireless ADB Helper     : Android 11+ on-device wireless debugging.\n' "$BOLD$GREEN" "$NC"
    printf ' %s[10/V]%s Verify All Toolchains   : Status report of all compilers, SDKs, and CLIs.\n' "$BOLD$GREEN" "$NC"
    printf ' %s[11/T]%s 34-Point Stress Suite   : Full regression test verifying locks, DEX, APK, NDK, ccache.\n' "$BOLD$GREEN" "$NC"
    printf ' %s[12/H]%s System Doctor           : Real-time RAM, storage, and platform diagnostics.\n' "$BOLD$GREEN" "$NC"
    printf ' %s[13/X]%s Developer Extra-Keys    : Fast mobile coding keyboard bar in Termux.\n' "$BOLD$YELLOW" "$NC"
    printf ' %s[14/P]%s Disable PPK             : Remove 32-child-process background restriction.\n' "$BOLD$YELLOW" "$NC"
    printf ' %s[15/R]%s Prune Unused NDK        : Save ~600MB storage by removing unused sysroots.\n' "$BOLD$YELLOW" "$NC"
    printf ' %s[16/L]%s Encrypted Vault         : AES-256-CBC backup/restore of API keys & configs.\n' "$BOLD$YELLOW" "$NC"
    printf ' %s[17/C]%s Deep Clean System       : Clear caches, apt archives, and stale locks.\n' "$BOLD$YELLOW" "$NC"
    printf ' %s[18/G]%s Install Pre-Commit Hook : Non-destructive Git commit validation hook.\n\n' "$BOLD$YELLOW" "$NC"

    printf '%sGlobal Commands:%s\n' "$BOLD$YELLOW" "$NC"
    printf '  tsuite                 : Open interactive TUI from anywhere\n'
    printf '  tsuite --wizard        : Interactive multi-stage selection wizard\n'
    printf '  tsuite --backup        : Create encrypted developer vault (.enc)\n'
    printf '  tsuite --restore       : Restore environment from encrypted vault\n'
    printf '  tsuite --adb           : Android 11+ wireless ADB pairing helper\n'
    printf '  termux-apk-build -p .  : Compile current Android project into signed APK\n'
    printf '  tsuite --doctor        : Run system health diagnostics\n'
    printf '  tsuite --test          : Run 34-point stress test\n\n'
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
        local bat_str="" git_str=""
        if command -v termux-battery-status >/dev/null 2>&1; then
            local b_pct
            b_pct="$(termux-battery-status 2>/dev/null | jq -r '.percentage // empty' 2>/dev/null || true)"
            [[ -n "$b_pct" ]] && bat_str="  │  Bat: ${b_pct}%"
        fi
        if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
            local g_branch g_dirty
            g_branch="$(git branch --show-current 2>/dev/null || echo 'git')"
            g_dirty="$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
            git_str="  │  Git: ${g_branch} (${g_dirty}*)"
        fi
        backtitle="Termux-Dev ARM64 Workstation  │  RAM: ${ram_free} Avail  │  Disk: ${disk_free} Free${bat_str}${git_str}"

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
            "W"  "🧙 Custom Multi-Stage Selection Wizard" \
            "2"  "$s1_d Stage 01: Base System, Repos & Zsh" \
            "3"  "$s2_d Stage 02: Essentials & Dev Toolchains" \
            "4"  "$s3_d Stage 03: Node.js 24 & Package Managers" \
            "5"  "$s4_d Stage 04: AI CLI Suite (5 Assistants)" \
            "6"  "$s5_d Stage 05: Private AI Environment (~/.ai-env)" \
            "7"  "$s6_d Stage 06: Android SDK, NDK & OpenJDK 21" \
            "8"  "⚡ Build Android APK (Sub-Second Engine)" \
            "9"  "📶 Wireless ADB Pairing & Connect (Android 11+)" \
            "10" "✓  Verify All Installed Tools & CLIs" \
            "11" "🧪 Run Ruthless 34-Point Stress Test Suite" \
            "12" "🩺 System Doctor: Health & Diagnostics" \
            "13" "⌨️  Configure Developer Extra-Keys" \
            "14" "🔋 Disable Phantom Process Killer" \
            "15" "✂️  Prune Unused NDK Sysroots (Save ~600MB)" \
            "16" "🔒 Encrypted Developer Vault (Backup / Restore)" \
            "17" "🧹 Deep Clean Cache, Temp Files & Locks" \
            "18" "🛡️  Install Local Git Pre-Commit Hook" \
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
            w|W) run_wizard "$theme_file" ;;
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
            9) launch_wireless_adb ;;
            10) verify_all ;;
            11) bash "$SETUP_DIR/test-suite.sh" ;;
            12) doctor_system ;;
            13) tune_extra_keys ;;
            14) tune_device ;;
            15) prune_ndk ;;
            16) vault_interactive "$theme_file" ;;
            17) clean_system ;;
            18) install_git_hooks ;;
            0) break ;;
        esac

        printf '\n%sPress Enter to return to the interactive menu...%s' "$BOLD$CYAN" "$NC"
        read -r
    done
    rm -f "$theme_file" 2>/dev/null || true
    clear 2>/dev/null || true
}

show_menu_ansi() {
    local ram_free disk_free bat_pct g_branch g_dirty
    while true; do
        ram_free="$(free -h 2>/dev/null | awk '/Mem:/ {print $7}' || echo 'N/A')"
        disk_free="$(df -h "${PREFIX:-/data/data/com.termux/files/usr}" 2>/dev/null | awk 'NR==2 {print $4}' || echo 'N/A')"
        bat_pct=""
        if command -v termux-battery-status >/dev/null 2>&1; then
            bat_pct="$(termux-battery-status 2>/dev/null | jq -r '.percentage // empty' 2>/dev/null || true)"
        fi
        g_branch=""
        g_dirty=""
        if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
            g_branch="$(git branch --show-current 2>/dev/null || echo 'git')"
            g_dirty="$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
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
        if [[ -n "$g_branch" && -n "$bat_pct" ]]; then
            printf '%s│%s   Arch: \033[1;33marm64\033[0m │ RAM: \033[1;32m%-5s\033[0m │ Disk: \033[1;32m%-6s\033[0m │ Bat: \033[1;32m%-3s\033[0m │ Git: \033[1;36m%s\033[0m (%s*)  %s│%s\n' "$CYAN" "$NC" "$ram_free" "$disk_free" "${bat_pct}%" "$g_branch" "$g_dirty" "$CYAN" "$NC"
        elif [[ -n "$bat_pct" ]]; then
            printf '%s│%s   Arch: \033[1;33maarch64\033[0m │ RAM: \033[1;32m%-6s\033[0m │ Disk: \033[1;32m%-7s\033[0m │ Bat: \033[1;32m%-4s\033[0m   %s│%s\n' "$CYAN" "$NC" "$ram_free" "$disk_free" "${bat_pct}%" "$CYAN" "$NC"
        else
            printf '%s│%s   Arch: \033[1;33maarch64\033[0m │ RAM Avail: \033[1;32m%-7s\033[0m │ Free Disk: \033[1;32m%-8s\033[0m    %s│%s\n' "$CYAN" "$NC" "$ram_free" "$disk_free" "$CYAN" "$NC"
        fi
        printf '%s╰───────────────────────────────────────────────────────────────────╯%s\n\n' "$CYAN" "$NC"

        printf ' %s%s┌── [1] COMPLETE WORKSTATION PIPELINE ────────────────────────────┐%s\n' "$BOLD" "$BLUE" "$NC"
        printf ' %s│%s  %s[1/A]%s  %s▶%s  Run Complete Workstation Setup (Stages 01 -> 06)      %s│%s\n' "$BLUE" "$NC" "$BOLD$YELLOW" "$NC" "$GREEN$BOLD" "$NC" "$BLUE" "$NC"
        printf ' %s│%s  %s[W]%s    %s🧙%s  Custom Multi-Stage Selection Wizard (Checklist)        %s│%s\n' "$BLUE" "$NC" "$BOLD$CYAN" "$NC" "$CYAN$BOLD" "$NC" "$BLUE" "$NC"
        printf ' %s└─── Modular Setup Stages ─────────────────────────────────────────┘%s\n' "$BLUE" "$NC"
        printf '   %s[2/B]%s %s Stage 01: Base System, Repositories & Zsh Shell\n' "$BOLD$CYAN" "$NC" "$s1_a"
        printf '   %s[3/E]%s %s Stage 02: Build Tools, Compilers & Dev Essentials\n' "$BOLD$CYAN" "$NC" "$s2_a"
        printf '   %s[4/N]%s %s Stage 03: Node.js 24 LTS & Package Managers (ARM64)\n' "$BOLD$CYAN" "$NC" "$s3_a"
        printf '   %s[5/I]%s %s Stage 04: AI Coding Assistant Suite (5 CLIs)\n' "$BOLD$CYAN" "$NC" "$s4_a"
        printf '   %s[6/S]%s %s Stage 05: Private AI Environment & Credentials (~/.ai-env)\n' "$BOLD$CYAN" "$NC" "$s5_a"
        printf '   %s[7/D]%s %s Stage 06: Android SDK, NDK (Clang 21) & OpenJDK 21\n\n' "$BOLD$CYAN" "$NC" "$s6_a"

        printf ' %s%s┌── [2] APPLICATION COMPILATION & DEVICE TOOLS ───────────────────┐%s\n' "$BOLD" "$GREEN" "$NC"
        printf '   %s[8/K]%s  ⚡ Build Android APK (Sub-Second Zero-Gradle Engine)\n' "$BOLD$GREEN" "$NC"
        printf '   %s[9/Y]%s  📶 Wireless ADB Pairing & Connect (Android 11+)\n' "$BOLD$GREEN" "$NC"
        printf '  %s[10/V]%s  ✓  Verify All Installed Compilers, SDKs & Toolchains\n' "$BOLD$GREEN" "$NC"
        printf '  %s[11/T]%s  🧪 Run Ruthless 34-Point Stress & Verification Suite\n' "$BOLD$GREEN" "$NC"
        printf '  %s[12/H]%s  🩺 System Doctor: Hardware, RAM & Stability Diagnostics\n' "$BOLD$GREEN" "$NC"
        printf ' %s└───────────────────────────────────────────────────────────────────┘%s\n\n' "$GREEN" "$NC"

        printf ' %s%s┌── [3] SYSTEM TUNING, STORAGE & REPOSITORY HYGIENE ───────────────┐%s\n' "$BOLD" "$YELLOW" "$NC"
        printf '  %s[13/X]%s  ⌨️  Configure Developer Extra-Keys (Fast Touch Coding Bar)\n' "$BOLD$YELLOW" "$NC"
        printf '  %s[14/P]%s  🔋 Disable Phantom Process Killer (Android 14/15/16 PPK)\n' "$BOLD$YELLOW" "$NC"
        printf '  %s[15/R]%s  ✂️  Prune Unused NDK Sysroots (Frees ~600MB Storage)\n' "$BOLD$YELLOW" "$NC"
        printf '  %s[16/L]%s  🔒 Encrypted Developer Vault (Backup / Restore Secrets)\n' "$BOLD$YELLOW" "$NC"
        printf '  %s[17/C]%s  🧹 Deep Clean Cache, Temp Files & Concurrency Locks\n' "$BOLD$YELLOW" "$NC"
        printf '  %s[18/G]%s  🛡️  Install Local Git Pre-Commit Security Lint Hook\n' "$BOLD$YELLOW" "$NC"
        printf ' %s└───────────────────────────────────────────────────────────────────┘%s\n\n' "$YELLOW" "$NC"

        printf '  %s[?/U]%s  📖 Help & Documentation Guide\n' "$BOLD$CYAN" "$NC"
        printf '  %s[0/Q]%s  🚪 Exit to Shell\n\n' "$BOLD$RED" "$NC"

        printf '%sSelect an option [1-18, A-Z, ?, or 0/Q to exit]: %s' "$BOLD$CYAN" "$NC"
        local raw_choice=""
        if [[ -t 0 ]]; then
            local k1="" k2=""
            read -rsn1 k1
            if [[ "$k1" == "1" ]]; then
                if read -rsn1 -t 0.35 k2 && [[ "$k2" =~ [0-8] ]]; then
                    raw_choice="${k1}${k2}"
                else
                    raw_choice="$k1"
                fi
            elif [[ -n "$k1" ]]; then
                raw_choice="$k1"
            fi
            printf '%s\n' "$raw_choice"
        else
            read -rp "" raw_choice
        fi
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
            w|wiz|wizard) run_wizard_ansi ;;
            2|b) run_stage "01-termux-base.sh" "Stage 01: Termux Base Setup" ;;
            3|e) run_stage "02-termux-essentials.sh" "Stage 02: Essentials & Dev Tools" ;;
            4|n) run_stage "03-termux-node-toolchain.sh" "Stage 03: Node.js Toolchain" ;;
            5|i) run_stage "04-termux-ai-cli.sh" "Stage 04: AI CLI Suite" ;;
            6|s) run_stage "05-ai-env.sh" "Stage 05: AI Environment & Credentials" ;;
            7|d) run_stage "06-termux-android-sdk.sh" "Stage 06: Android SDK & NDK Toolchain" ;;
            8|k) build_apk_interactive ;;
            9|y|adb) launch_wireless_adb ;;
            10|v) verify_all ;;
            11|t) bash "$SETUP_DIR/test-suite.sh" ;;
            12|h) doctor_system ;;
            13|x) tune_extra_keys ;;
            14|p) tune_device ;;
            15|r) prune_ndk ;;
            16|l|vault) vault_interactive ;;
            17|c) clean_system ;;
            18|g) install_git_hooks ;;
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
        --wizard)
            run_wizard
            ;;
        --backup)
            backup_vault "${2:-}"
            ;;
        --restore)
            restore_vault "${2:-}"
            ;;
        --adb|--adb-pair|--adb-connect)
            shift
            launch_wireless_adb "$@"
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
            printf '  --wizard         Launch custom multi-stage selection wizard\n'
            printf '  --base           Execute Stage 01: Base & Repos\n'
            printf '  --essentials     Execute Stage 02: Essentials & Dev Tools\n'
            printf '  --node           Execute Stage 03: Node.js Toolchain\n'
            printf '  --ai             Execute Stage 04: AI CLI Suite\n'
            printf '  --ai-env         Execute Stage 05: AI Environment Setup\n'
            printf '  --android        Execute Stage 06: Android SDK & NDK Setup\n'
            printf '  --apk            Build Android APK interactively with zero Gradle\n'
            printf '  --adb [args]     Android 11+ wireless ADB pairing & connect helper\n'
            printf '  --backup [file]  Export encrypted developer vault (AES-256-CBC)\n'
            printf '  --restore [file] Restore developer vault from encrypted archive\n'
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
