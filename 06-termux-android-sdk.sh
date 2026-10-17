#!/data/data/com.termux/files/usr/bin/bash
#
# Stage 06: Android SDK, NDK & Development Toolchain Bootstrap
# Installs and configures:
#   - TermuxVoid repository & tvpkg package manager
#   - OpenJDK 21 LTS Java Development Kit
#   - Gradle 9.x build system
#   - Android SDK (build-tools 36.1.0, cmdline-tools 19.0, platforms android-36)
#   - Android NDK (29.0.14206865 LLVM Clang toolchain for ARM64)
#   - Platform tools (adb, fastboot) & build tools (aapt, aapt2, apksigner, d8)
#   - Environment variables (~/.android-env) and global Gradle settings (~/.gradle/gradle.properties)
#

set -Eeuo pipefail
IFS=$'\n\t'

# -----------------------------
# Configuration
# -----------------------------
ANDROID_HOME="${PREFIX:-/data/data/com.termux/files/usr}/opt/android-sdk"
NDK_VERSION="29.0.14206865"
BUILD_TOOLS_VERSION="36.1.0"
JAVA_HOME="${PREFIX:-/data/data/com.termux/files/usr}/lib/jvm/java-21-openjdk"

# -----------------------------
# Colors & Logging
# -----------------------------
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

on_error() {
    local rc=$?
    error "Command failed with exit ${rc} at line ${BASH_LINENO[0]:-unknown}: ${BASH_COMMAND:-unknown}"
    exit "$rc"
}
trap on_error ERR

# -----------------------------
# Basic validation
# -----------------------------
[[ -n "${PREFIX:-}" ]] || die "PREFIX is not set. Run this inside Termux."
[[ -x "$PREFIX/bin/pkg" ]] || die "Termux pkg was not found."

ARCH="$(dpkg --print-architecture 2>/dev/null || uname -m)"
if [[ "$ARCH" != "aarch64" ]]; then
    die "This installer is optimized for ARM64/aarch64 Termux. Detected: $ARCH"
fi

# -----------------------------
# Concurrency Lock (flock)
# -----------------------------
LOCK_FILE="${TMPDIR:-$PREFIX/tmp}/android-sdk-setup.lock"
exec 200>"$LOCK_FILE"
if ! flock -n 200; then
    die "Another instance of 06-termux-android-sdk.sh is already running."
fi

# -----------------------------
# 1. TermuxVoid Repository
# -----------------------------
info "Configuring TermuxVoid repository..."
for repo_pkg in x11-repo glibc-repo; do
    if ! dpkg -s "$repo_pkg" >/dev/null 2>&1; then
        apt-get install -y "$repo_pkg" || warn "Could not install $repo_pkg immediately."
    fi
done

if [[ ! -f "$PREFIX/etc/apt/sources.list.d/termuxvoid.list" ]]; then
    mkdir -p "$PREFIX/etc/apt/sources.list.d" "$PREFIX/etc/apt/trusted.gpg.d"
    echo 'deb [arch=all] https://termuxvoid.github.io/repo termuxvoid main' > "$PREFIX/etc/apt/sources.list.d/termuxvoid.list"
    curl -fsSL https://github.com/termuxvoid/repo/raw/main/assets/termuxvoid.gpg -o "$PREFIX/etc/apt/trusted.gpg.d/termuxvoid.gpg"
    apt-get update -y
fi

if ! command -v tvpkg >/dev/null 2>&1; then
    apt-get install -y tvpkg || warn "tvpkg package could not be installed immediately."
fi
success "TermuxVoid repository and tvpkg configured."

# -----------------------------
# 2. Prerequisites & Build Tools
# -----------------------------
info "Installing Java OpenJDK, Gradle, and Android build packages..."
apt-get install -y \
    openjdk-21 \
    gradle \
    android-tools \
    aapt \
    aapt2 \
    apksigner \
    d8 \
    7zip \
    axel \
    cmake \
    ninja

# -----------------------------
# 3. Android SDK & NDK Package
# -----------------------------
if [[ ! -d "$ANDROID_HOME" ]]; then
    info "Installing android-sdk package from TermuxVoid..."
    apt-get install -y android-sdk
    success "android-sdk package installation complete."
else
    success "Android SDK directory already exists at: $ANDROID_HOME"
fi

# -----------------------------
# 4. Post-Installation Patches
# -----------------------------
info "Applying Termux architecture and shebang patches..."

# Patch cmdline-tools structure for automatic SDK root detection
CMDLINE_ROOT="$ANDROID_HOME/cmdline-tools"
if [[ -d "$CMDLINE_ROOT" ]]; then
    mkdir -p "$CMDLINE_ROOT/latest/bin"
    if [[ -d "$CMDLINE_ROOT/bin" ]]; then
        for b in "$CMDLINE_ROOT/bin"/*; do
            [[ -f "$b" ]] && cp -pf "$b" "$CMDLINE_ROOT/latest/bin/"
        done
    fi
    for tool in apkanalyzer avdmanager d8 lint profgen r8 resourceshrinker retrace screenshot2 sdkmanager; do
        if [[ -f "$CMDLINE_ROOT/latest/$tool" ]]; then
            mv -f "$CMDLINE_ROOT/latest/$tool" "$CMDLINE_ROOT/latest/bin/"
        elif [[ -f "$CMDLINE_ROOT/$tool" ]]; then
            mv -f "$CMDLINE_ROOT/$tool" "$CMDLINE_ROOT/latest/bin/"
        fi
    done
    [[ -d "$CMDLINE_ROOT/lib" && ! -d "$CMDLINE_ROOT/latest/lib" ]] && cp -rpf "$CMDLINE_ROOT/lib" "$CMDLINE_ROOT/latest/"
fi

# Shebang fixes for Termux prefix
command -v termux-fix-shebang >/dev/null 2>&1 && {
    [[ -d "$CMDLINE_ROOT/latest/bin" ]] && termux-fix-shebang "$CMDLINE_ROOT/latest/bin"/* 2>/dev/null || true
    [[ -d "$CMDLINE_ROOT/bin" ]] && termux-fix-shebang "$CMDLINE_ROOT/bin"/* 2>/dev/null || true
    [[ -d "$ANDROID_HOME/build-tools/$BUILD_TOOLS_VERSION" ]] && termux-fix-shebang "$ANDROID_HOME/build-tools/$BUILD_TOOLS_VERSION"/* 2>/dev/null || true
}

# Restore NDK clang++ symlink if ignored by 7z during extraction
NDK_BIN="$ANDROID_HOME/ndk/$NDK_VERSION/toolchains/llvm/prebuilt/linux-arm64/bin"
if [[ -d "$NDK_BIN" ]]; then
    if [[ ! -s "$NDK_BIN/clang++" ]]; then
        info "Restoring NDK clang++ symlink..."
        ln -sf clang "$NDK_BIN/clang++"
    fi
fi

# Link Termux-native adb and fastboot into platform-tools to avoid socket protocol faults
if [[ -d "$ANDROID_HOME/platform-tools" ]]; then
    info "Linking Termux native adb and fastboot into platform-tools..."
    [[ -x "$PREFIX/bin/adb" ]] && ln -sf "$PREFIX/bin/adb" "$ANDROID_HOME/platform-tools/adb"
    [[ -x "$PREFIX/bin/fastboot" ]] && ln -sf "$PREFIX/bin/fastboot" "$ANDROID_HOME/platform-tools/fastboot"
fi

# Fix Termux shebangs across NDK target compilers and toolchain binaries
if [[ -d "$ANDROID_HOME/ndk/$NDK_VERSION/toolchains/llvm/prebuilt/linux-arm64/bin" ]]; then
    info "Patching NDK compiler toolchain shebangs..."
    command -v termux-fix-shebang >/dev/null 2>&1 && {
        termux-fix-shebang "$ANDROID_HOME/ndk/$NDK_VERSION/toolchains/llvm/prebuilt/linux-arm64/bin"/* 2>/dev/null || true
    }
fi

# -----------------------------
# 5. Google Android CLI (android)
# -----------------------------
info "Configuring Google Android CLI tool..."
mkdir -p "$HOME/.local/bin" "$HOME/Android"
ln -sfn "$ANDROID_HOME" "$HOME/Android/Sdk"

ANDROID_CLI_BIN="$HOME/.android/bin/android-cli"
if [[ ! -f "$ANDROID_CLI_BIN" ]]; then
    info "Downloading Google Android CLI for ARM64..."
    TMP_DL="${TMPDIR:-$PREFIX/tmp}/android_dl_$$"
    if wget -c "https://dl.google.com/android/cli/latest/linux_arm64/android" -O "$TMP_DL" 2>/dev/null || \
       curl -fL --retry 3 --retry-delay 2 "https://dl.google.com/android/cli/latest/linux_arm64/android" -o "$TMP_DL"; then
        chmod +x "$TMP_DL"
        # First execution self-extracts payload to ~/.android/bin/android-cli
        grun "$TMP_DL" --help >/dev/null 2>&1 || true
        rm -f "$TMP_DL"
    fi
fi

if [[ -f "$ANDROID_CLI_BIN" && -f "$PREFIX/glibc/lib/ld-linux-aarch64.so.1" ]]; then
    if command -v patchelf >/dev/null 2>&1; then
        patchelf --set-interpreter "$PREFIX/glibc/lib/ld-linux-aarch64.so.1" \
                 --set-rpath "$PREFIX/glibc/lib" \
                 "$ANDROID_CLI_BIN" 2>/dev/null || true
    fi
    rm -f "$HOME/.local/bin/android"
    cat > "$HOME/.local/bin/android" <<'WRAPPER_EOF'
#!/data/data/com.termux/files/usr/bin/bash
export ANDROID_HOME="${ANDROID_HOME:-/data/data/com.termux/files/usr/opt/android-sdk}"
export ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-$ANDROID_HOME}"
exec env -u LD_PRELOAD "$HOME/.android/bin/android-cli" --no-metrics "$@"
WRAPPER_EOF
    chmod +x "$HOME/.local/bin/android"
    command -v termux-fix-shebang >/dev/null 2>&1 && termux-fix-shebang "$HOME/.local/bin/android" 2>/dev/null || true
    success "Google Android CLI configured at $HOME/.local/bin/android."
    "$HOME/.local/bin/android" init >/dev/null 2>&1 || true
fi

# -----------------------------
# 6. Environment & Shell Setup
# -----------------------------
info "Configuring environment files (~/.android-env and ~/.gradle/gradle.properties)..."

ENV_FILE="$HOME/.android-env"
cat > "$ENV_FILE" <<EOF
# ========================================================
# Android SDK, NDK & Java Development Environment
# ========================================================
export ANDROID_HOME="$ANDROID_HOME"
export ANDROID_SDK_ROOT="\$ANDROID_HOME"
export ANDROID_NDK_ROOT="\$ANDROID_HOME/ndk/$NDK_VERSION"
export NDK_HOME="\$ANDROID_NDK_ROOT"
export JAVA_HOME="$JAVA_HOME"

# Android SDK build tools, cmdline tools, platform tools, NDK compilers, and cmake
export PATH="\$ANDROID_HOME/cmdline-tools/latest/bin:\$ANDROID_HOME/platform-tools:\$ANDROID_HOME/build-tools/$BUILD_TOOLS_VERSION:\$ANDROID_HOME/cmake/4.1.2/bin:\$ANDROID_NDK_ROOT/toolchains/llvm/prebuilt/linux-arm64/bin:\$PATH"
EOF
chmod 644 "$ENV_FILE"

# Persist in shell rc files
for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
    if [[ -f "$rc" ]]; then
        if ! grep -qF 'source "$HOME/.android-env"' "$rc"; then
            printf '\n# Load Android development environment\n[[ -f "$HOME/.android-env" ]] && source "$HOME/.android-env"\n' >> "$rc"
        fi
    fi
done

# Global Gradle properties for native Termux builds
mkdir -p "$HOME/.gradle"
GRADLE_PROP="$HOME/.gradle/gradle.properties"
cat > "$GRADLE_PROP" <<EOF
# ========================================================
# Global Gradle Configuration for Android Development on Termux
# ========================================================
# Override maven x86_64 aapt2 with native Termux ARM64 binary
android.aapt2FromMavenOverride=$ANDROID_HOME/build-tools/$BUILD_TOOLS_VERSION/aapt2

# Disable file system watching due to Termux inotify / native JNI limits
org.gradle.vfs.watch=false

# Enable parallel execution across mobile CPU cores
org.gradle.parallel=true

# JVM Memory and Garbage Collection optimization for mobile ARM64 (protect against OOM killer)
org.gradle.jvmargs=-Xmx1280m -XX:+UseG1GC -XX:MaxMetaspaceSize=384m

# Automatically shut down idle daemons after 1 minute to release RAM
org.gradle.daemon.idletimeout=60000

# Disable automatic SDK download attempt (which downloads x86_64 packages)
android.builder.sdkDownload=false
EOF
chmod 644 "$GRADLE_PROP"

# -----------------------------
# 6. Verification
# -----------------------------
printf '\n'
info "=== Android Development Toolchain Verification ==="
source "$ENV_FILE"

command -v java >/dev/null 2>&1 && success "Java:       $(java -version 2>&1 | head -n 1)" || warn "Java missing"
command -v gradle >/dev/null 2>&1 && success "Gradle:     $(gradle --version 2>&1 | grep '^Gradle ' || echo 'active')" || warn "Gradle missing"
command -v adb >/dev/null 2>&1 && success "ADB:        $(adb --version 2>&1 | head -n 1)" || warn "ADB missing"
command -v aapt2 >/dev/null 2>&1 && success "AAPT2:      $(aapt2 version 2>&1 | head -n 1)" || warn "AAPT2 missing"
command -v apksigner >/dev/null 2>&1 && success "apksigner:  active" || warn "apksigner missing"
command -v d8 >/dev/null 2>&1 && success "d8:         active" || warn "d8 missing"
command -v sdkmanager >/dev/null 2>&1 && success "sdkmanager: $(sdkmanager --version 2>&1 | head -n 1)" || warn "sdkmanager missing"

if [[ -x "$NDK_BIN/clang" ]]; then
    success "NDK Clang:  $("$NDK_BIN/clang" --version 2>&1 | head -n 1)"
else
    warn "NDK Clang missing at $NDK_BIN/clang"
fi
command -v android >/dev/null 2>&1 && success "Android CLI: $(android --version 2>&1 | head -n 1)" || warn "Android CLI missing"

printf '\n'
success "Stage 06: Android SDK, NDK & Development Toolchain setup complete!"
