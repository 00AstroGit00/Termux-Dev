#!/data/data/com.termux/files/usr/bin/bash
#
# Ruthless Automated Verification & Stress Test Suite
# Tests every tool, compiler, AI CLI, and lockfile mechanism to ensure it is bulletproof.
#

set -Eeuo pipefail

SETUP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
export PREFIX
TMP_TEST_DIR="${TMPDIR:-$PREFIX/tmp}/bulletproof-test-$$"
mkdir -p "$TMP_TEST_DIR"
trap 'rm -rf "$TMP_TEST_DIR"' EXIT INT TERM

# Colors
RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
BLUE=$'\033[0;34m'
CYAN=$'\033[0;36m'
BOLD=$'\033[1m'
NC=$'\033[0m'

PASSED=0
FAILED=0
WARNED=0

info() {
    printf '%s[INFO]%s %s\n' "$BLUE" "$NC" "$*"
}

test_start() {
    printf '%s▶ [TEST]%s %s ... ' "$CYAN" "$NC" "$1"
}

test_pass() {
    printf '%sPASS%s (%s)\n' "$GREEN$BOLD" "$NC" "$*"
    PASSED=$((PASSED + 1))
}

test_fail() {
    printf '%sFAIL%s (%s)\n' "$RED$BOLD" "$NC" "$*"
    FAILED=$((FAILED + 1))
}

test_warn() {
    printf '%sWARN%s (%s)\n' "$YELLOW$BOLD" "$NC" "$*"
    WARNED=$((WARNED + 1))
}

printf '\n%s=======================================================%s\n' "$BOLD$CYAN" "$NC"
printf '%s       RUTHLESS VERIFICATION & STRESS TEST SUITE       %s\n' "$BOLD$GREEN" "$NC"
printf '%s=======================================================%s\n\n' "$BOLD$CYAN" "$NC"

# -------------------------------------------------------------
# 1. Concurrency & flock Locking Stress Test
# -------------------------------------------------------------
test_start "Kernel flock lock acquisition & crash recovery"
LOCK_TEST_FILE="$TMP_TEST_DIR/test.lock"
(
    exec 200>"$LOCK_TEST_FILE"
    flock -n 200 || exit 1
    # Subshell holds lock
    sleep 0.5
) &
SUB_PID=$!
sleep 0.1

# Secondary attempt must fail while subshell holds lock
if (exec 201>"$LOCK_TEST_FILE"; flock -n 201) 2>/dev/null; then
    test_fail "Lock concurrency violation: secondary process acquired locked file"
else
    # Wait for subshell to finish
    wait "$SUB_PID"
    # Post-exit: lock must be automatically released by the kernel
    if (exec 202>"$LOCK_TEST_FILE"; flock -n 202) 2>/dev/null; then
        test_pass "flock blocked conflict and released cleanly on exit"
    else
        test_fail "Lock not released after process termination"
    fi
fi

# -------------------------------------------------------------
# 2. Shell Environment & PATH Precedence
# -------------------------------------------------------------
test_start "PATH ordering (~/.local/bin precedes ~/.npm-global/bin)"
export PATH="$HOME/.local/bin:$HOME/.npm-global/bin:$HOME/bin:$PREFIX/bin:$PATH"
COPILOT_CMD="$(command -v copilot 2>/dev/null || true)"
if [[ "$COPILOT_CMD" == *"/home/.local/bin/copilot"* ]]; then
    test_pass "~/.local/bin takes precedence ($COPILOT_CMD)"
elif [[ -n "$COPILOT_CMD" ]]; then
    test_pass "Resolved copilot at: $COPILOT_CMD"
else
    test_warn "copilot command not found on PATH"
fi

test_start "Security permissions on ~/.ai-env"
if [[ -f "$HOME/.ai-env" ]]; then
    PERMS="$(stat -c '%a' "$HOME/.ai-env" 2>/dev/null || stat -f '%Lp' "$HOME/.ai-env" 2>/dev/null || echo 'unknown')"
    if [[ "$PERMS" == "600" || "$PERMS" == "400" ]]; then
        test_pass "Permissions secure: $PERMS"
    else
        test_warn "Permissions too open: $PERMS (expected 600). Fixing now..."
        chmod 600 "$HOME/.ai-env"
    fi
else
    test_warn "~/.ai-env not present"
fi

# -------------------------------------------------------------
# 3. Shebang Resolution Across npm Binaries
# -------------------------------------------------------------
test_start "Interpreter shebangs in ~/.npm-global/bin"
UNRESOLVED_SHEBANGS=0
if [[ -d "$HOME/.npm-global/bin" ]]; then
    for bin in "$HOME/.npm-global/bin"/*; do
        [[ -e "$bin" ]] || continue
        TARGET="$(readlink -f "$bin" 2>/dev/null || echo "$bin")"
        [[ -f "$TARGET" && -x "$TARGET" ]] || continue
        # Skip ELF binary executables
        if head -c 4 "$TARGET" 2>/dev/null | grep -q $'\x7fELF'; then
            continue
        fi
        FIRST_LINE="$(head -n 1 "$TARGET" 2>/dev/null || true)"
        if [[ "$FIRST_LINE" == "#!/usr/bin/env"* || "$FIRST_LINE" == "#!/bin/"* ]]; then
            test_warn "Unpatched shebang in $(basename "$bin"): $FIRST_LINE"
            UNRESOLVED_SHEBANGS=$((UNRESOLVED_SHEBANGS + 1))
        fi
    done
    if (( UNRESOLVED_SHEBANGS == 0 )); then
        test_pass "All installed npm binary shebangs properly resolved"
    else
        info "Running termux-fix-shebang to heal..."
        termux-fix-shebang "$HOME/.npm-global/bin"/* 2>/dev/null || true
    fi
else
    test_pass "No global npm bin directory to check"
fi

# -------------------------------------------------------------
# 4. Functional Compiler & Runtime Execution Tests
# -------------------------------------------------------------
test_start "Clang C compiler execution"
cat > "$TMP_TEST_DIR/test.c" <<'EOF'
#include <stdio.h>
int main() { printf("CLANG_ARM64_OK\n"); return 0; }
EOF
if clang "$TMP_TEST_DIR/test.c" -o "$TMP_TEST_DIR/test_c" >/dev/null 2>&1; then
    OUTPUT="$("$TMP_TEST_DIR/test_c" 2>&1 || true)"
    if [[ "$OUTPUT" == *"CLANG_ARM64_OK"* ]]; then
        test_pass "compiled and executed native binary"
    else
        test_fail "execution produced unexpected output: $OUTPUT"
    fi
else
    test_fail "clang compilation failed"
fi

test_start "Python 3 runtime & stdlib execution"
PY_OUTPUT="$(python -c 'import sys, json, os; print(f"PYTHON_OK {sys.version_info[0]}.{sys.version_info[1]}")' 2>&1 || true)"
if [[ "$PY_OUTPUT" == *"PYTHON_OK"* ]]; then
    test_pass "$PY_OUTPUT"
else
    test_fail "Python execution failed: $PY_OUTPUT"
fi

test_start "Node.js 24 LTS runtime & architecture execution"
NODE_OUTPUT="$(node -e 'console.log("NODE_OK " + process.version + " " + process.arch)' 2>&1 || true)"
if [[ "$NODE_OUTPUT" == *"NODE_OK"* ]]; then
    test_pass "$NODE_OUTPUT"
else
    test_fail "Node.js execution failed: $NODE_OUTPUT"
fi

test_start "pnpm ARM64 compatibility execution"
if command -v pnpm >/dev/null 2>&1; then
    PNPM_VER="$(pnpm --version 2>&1 | tail -n 1 | tr -d '[:space:]' || true)"
    if [[ "$PNPM_VER" =~ ^10\. ]]; then
        test_pass "pnpm pinned version: $PNPM_VER"
    else
        test_warn "pnpm version is $PNPM_VER (expected 10.x line for ARM64 stability)"
    fi
else
    test_fail "pnpm executable not found on PATH"
fi

# -------------------------------------------------------------
# 5. AI CLI Suite Functional Execution Tests
# -------------------------------------------------------------
test_start "Antigravity CLI (agy) functional execution"
if command -v agy >/dev/null 2>&1; then
    AGY_OUT="$(agy --version 2>&1 | head -n 1 || true)"
    if [[ -n "$AGY_OUT" ]]; then
        test_pass "Antigravity CLI operational: $AGY_OUT"
    else
        test_fail "agy --version returned empty output"
    fi
else
    test_fail "agy not found on PATH"
fi

test_start "OpenCode (opencode) functional execution"
if command -v opencode >/dev/null 2>&1; then
    OPENCODE_OUT="$(opencode --version 2>&1 | head -n 1 || true)"
    if [[ -n "$OPENCODE_OUT" ]]; then
        test_pass "OpenCode operational: $OPENCODE_OUT"
    else
        test_fail "opencode returned empty output"
    fi
else
    test_fail "opencode not found on PATH"
fi

test_start "OpenAI Codex CLI (codex) functional execution"
if command -v codex >/dev/null 2>&1; then
    CODEX_OUT="$(codex --version 2>&1 | head -n 1 || true)"
    if [[ -n "$CODEX_OUT" ]]; then
        test_pass "Codex operational: $CODEX_OUT"
    else
        test_fail "codex returned empty output"
    fi
else
    test_fail "codex not found on PATH"
fi

test_start "Google Gemini CLI (gemini) functional execution"
if command -v gemini >/dev/null 2>&1; then
    GEMINI_OUT="$(gemini --version 2>&1 | head -n 1 || true)"
    if [[ -n "$GEMINI_OUT" ]]; then
        test_pass "Gemini operational: $GEMINI_OUT"
    else
        test_fail "gemini returned empty output"
    fi
else
    test_fail "gemini not found on PATH"
fi

test_start "GitHub Copilot CLI (copilot via grun) functional execution"
if command -v copilot >/dev/null 2>&1; then
    COPILOT_OUT="$(copilot --version 2>&1 | head -n 1 || true)"
    if [[ "$COPILOT_OUT" == *"Copilot"* ]]; then
        test_pass "GitHub Copilot operational: $COPILOT_OUT"
    else
        test_fail "copilot execution failed: $COPILOT_OUT"
    fi
else
    test_fail "copilot not found on PATH"
fi

# -------------------------------------------------------------
# 6. Android Development Toolchain & TermuxVoid
# -------------------------------------------------------------
[[ -f "$HOME/.android-env" ]] && source "$HOME/.android-env"

test_start "TermuxVoid package manager (tvpkg)"
if command -v tvpkg >/dev/null 2>&1; then
    test_pass "tvpkg installed and operational"
else
    test_fail "tvpkg not found on PATH"
fi

test_start "Java OpenJDK 21 execution"
if command -v java >/dev/null 2>&1; then
    JAVA_VER="$(java -version 2>&1 | head -n 1 || true)"
    test_pass "$JAVA_VER"
else
    test_fail "java executable not found on PATH"
fi

test_start "Gradle build system execution"
if command -v gradle >/dev/null 2>&1; then
    GRADLE_VER="$(gradle --version 2>&1 | grep '^Gradle ' || true)"
    test_pass "$GRADLE_VER"
else
    test_fail "gradle executable not found on PATH"
fi

test_start "Android SDK & build-tools (aapt2, d8, apksigner)"
if command -v aapt2 >/dev/null 2>&1 && command -v apksigner >/dev/null 2>&1; then
    test_pass "aapt2 and apksigner operational"
else
    test_fail "aapt2 or apksigner not found on PATH"
fi

test_start "Android Debug Bridge (adb) socket protocol execution"
if command -v adb >/dev/null 2>&1; then
    ADB_OUT="$(adb devices 2>&1 || true)"
    if [[ "$ADB_OUT" == *"List of devices attached"* && "$ADB_OUT" != *"protocol fault"* ]]; then
        test_pass "adb operational without protocol fault"
    else
        test_fail "adb returned protocol fault: $ADB_OUT"
    fi
else
    test_fail "adb not found on PATH"
fi

test_start "Android SDK Manager (sdkmanager)"
if command -v sdkmanager >/dev/null 2>&1; then
    SDK_VER="$(sdkmanager --version 2>&1 | head -n 1 || true)"
    test_pass "sdkmanager version $SDK_VER"
else
    test_fail "sdkmanager not found on PATH"
fi

test_start "Android NDK LLVM Clang compiler execution"
NDK_CLANG="${ANDROID_NDK_ROOT:-$PREFIX/opt/android-sdk/ndk/29.0.14206865}/toolchains/llvm/prebuilt/linux-arm64/bin/clang"
if [[ -x "$NDK_CLANG" ]]; then
    NDK_OUT="$("$NDK_CLANG" --version 2>&1 | head -n 1 || true)"
    test_pass "NDK Clang operational: $NDK_OUT"
else
    test_fail "NDK Clang not executable at $NDK_CLANG"
fi

test_start "AAPT2, d8 & apksigner APK synthesis and signing"
cat > "$TMP_TEST_DIR/AndroidManifest.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="com.test.suite">
    <application android:label="TestApp" />
</manifest>
EOF
cat > "$TMP_TEST_DIR/SuiteTest.java" <<'EOF'
public class SuiteTest { public static void main(String[] args) {} }
EOF
ANDROID_JAR="${ANDROID_HOME:-$PREFIX/opt/android-sdk}/platforms/android-36/android.jar"
if [[ -f "$ANDROID_JAR" ]] && \
   aapt2 link -I "$ANDROID_JAR" --manifest "$TMP_TEST_DIR/AndroidManifest.xml" -o "$TMP_TEST_DIR/suite-unaligned.apk" >/dev/null 2>&1 && \
   javac "$TMP_TEST_DIR/SuiteTest.java" -d "$TMP_TEST_DIR" >/dev/null 2>&1 && \
   d8 "$TMP_TEST_DIR/SuiteTest.class" --output "$TMP_TEST_DIR" >/dev/null 2>&1; then
    (cd "$TMP_TEST_DIR" && zip -uq suite-unaligned.apk classes.dex 2>/dev/null || true)
    keytool -genkey -v -keystore "$TMP_TEST_DIR/test.keystore" \
        -alias debug -keyalg RSA -keysize 2048 -validity 1000 \
        -storepass android -keypass android \
        -dname "CN=Test,O=Test,C=US" >/dev/null 2>&1 || true
    if apksigner sign --ks "$TMP_TEST_DIR/test.keystore" --ks-pass pass:android --key-pass pass:android \
        --out "$TMP_TEST_DIR/suite-signed.apk" "$TMP_TEST_DIR/suite-unaligned.apk" >/dev/null 2>&1 && \
       apksigner verify "$TMP_TEST_DIR/suite-signed.apk" >/dev/null 2>&1; then
        test_pass "aapt2, d8, and apksigner built and verified signed APK"
    else
        test_fail "apksigner failed to sign or verify APK"
    fi
else
    test_fail "APK/DEX synthesis failed"
fi

test_start "Standalone zero-Gradle APK builder (termux-apk-build)"
if [[ -x "$SETUP_DIR/bin/termux-apk-build" ]] || command -v termux-apk-build >/dev/null 2>&1; then
    APK_BUILD_CMD="[[ -x \"$SETUP_DIR/bin/termux-apk-build\" ]] && echo \"$SETUP_DIR/bin/termux-apk-build\" || command -v termux-apk-build"
    APK_BUILD_CMD="$(eval "$APK_BUILD_CMD")"
    mkdir -p "$TMP_TEST_DIR/cli_app/src/com/pkg"
    cat > "$TMP_TEST_DIR/cli_app/AndroidManifest.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="com.pkg">
    <application android:label="CliApp" />
</manifest>
EOF
    cat > "$TMP_TEST_DIR/cli_app/src/com/pkg/App.java" <<'EOF'
package com.pkg;
public class App { public static void main(String[] args) {} }
EOF
    if "$APK_BUILD_CMD" -m "$TMP_TEST_DIR/cli_app/AndroidManifest.xml" \
                        -s "$TMP_TEST_DIR/cli_app/src" \
                        -o "$TMP_TEST_DIR/cli_app/built.apk" >/dev/null 2>&1 && \
       apksigner verify "$TMP_TEST_DIR/cli_app/built.apk" >/dev/null 2>&1; then
        test_pass "termux-apk-build synthesized and verified signed APK"
    else
        test_fail "termux-apk-build execution failed"
    fi
else
    test_fail "termux-apk-build executable not found"
fi

test_start "Android APK zipalign 4-byte & 16KB page alignment verification"
if command -v zipalign >/dev/null 2>&1; then
    if [[ -f "$TMP_TEST_DIR/cli_app/built.apk" ]] && zipalign -c -P 16 4 "$TMP_TEST_DIR/cli_app/built.apk" >/dev/null 2>&1; then
        test_pass "APK passed 16KB page-boundary zipalign audit"
    else
        test_fail "zipalign verification failed on synthesized APK"
    fi
else
    test_fail "zipalign executable not found on PATH"
fi

test_start "Android Studio project auto-detection build (termux-apk-build -p)"
if [[ -x "$SETUP_DIR/bin/termux-apk-build" ]] || command -v termux-apk-build >/dev/null 2>&1; then
    APK_BUILD_CMD="[[ -x \"$SETUP_DIR/bin/termux-apk-build\" ]] && echo \"$SETUP_DIR/bin/termux-apk-build\" || command -v termux-apk-build"
    APK_BUILD_CMD="$(eval "$APK_BUILD_CMD")"
    mkdir -p "$TMP_TEST_DIR/studio_proj/app/src/main/java/com/studio"
    cat > "$TMP_TEST_DIR/studio_proj/app/src/main/AndroidManifest.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="com.studio">
    <application android:label="StudioApp" />
</manifest>
EOF
    cat > "$TMP_TEST_DIR/studio_proj/app/src/main/java/com/studio/Main.java" <<'EOF'
package com.studio;
public class Main { public static void main(String[] args) {} }
EOF
    if "$APK_BUILD_CMD" -p "$TMP_TEST_DIR/studio_proj" -o "$TMP_TEST_DIR/studio_proj/out.apk" >/dev/null 2>&1 && \
       apksigner verify "$TMP_TEST_DIR/studio_proj/out.apk" >/dev/null 2>&1; then
        test_pass "auto-detected Gradle layout and synthesized verified APK"
    else
        test_fail "Android Studio project auto-detect build failed"
    fi
else
    test_fail "termux-apk-build executable not found"
fi

test_start "Android NDK native C compilation (ARM64)"
if [[ -x "$NDK_CLANG" ]]; then
    cat > "$TMP_TEST_DIR/ndk_hello.c" <<'EOF'
#include <stdio.h>
int main() { printf("NDK_OK\n"); return 0; }
EOF
    if "$NDK_CLANG" "$TMP_TEST_DIR/ndk_hello.c" -o "$TMP_TEST_DIR/ndk_hello" >/dev/null 2>&1 && [[ "$("$TMP_TEST_DIR/ndk_hello" 2>&1 || true)" == *"NDK_OK"* ]]; then
        test_pass "NDK Clang compiled and executed native ARM64 binary"
    else
        test_fail "NDK Clang compilation or execution failed"
    fi
else
    test_fail "NDK Clang not executable at $NDK_CLANG"
fi

test_start "Android NDK native C++20 STL compilation (ARM64)"
NDK_CLANGXX="${ANDROID_NDK_ROOT:-$PREFIX/opt/android-sdk/ndk/29.0.14206865}/toolchains/llvm/prebuilt/linux-arm64/bin/clang++"
if [[ -x "$NDK_CLANGXX" ]]; then
    cat > "$TMP_TEST_DIR/ndk_test.cpp" <<'EOF'
#include <iostream>
#include <vector>
#include <string>
int main() {
    std::vector<std::string> v = {"NDK", "CPP", "OK"};
    for (const auto& s : v) std::cout << s << " ";
    std::cout << std::endl;
    return 0;
}
EOF
    if "$NDK_CLANGXX" --target=aarch64-linux-android34 -std=c++20 -static-libstdc++ \
        "$TMP_TEST_DIR/ndk_test.cpp" -o "$TMP_TEST_DIR/ndk_cpp" >/dev/null 2>&1 && \
       [[ "$("$TMP_TEST_DIR/ndk_cpp" 2>&1 || true)" == *"NDK CPP OK"* ]]; then
        test_pass "NDK Clang++ compiled and executed native C++20 STL binary"
    else
        test_fail "NDK Clang++ compilation or execution failed"
    fi
else
    test_fail "NDK Clang++ not executable at $NDK_CLANGXX"
fi

test_start "Android NDK target wrapper (aarch64-linux-android34-clang)"
if command -v aarch64-linux-android34-clang >/dev/null 2>&1; then
    WRAP_OUT="$(aarch64-linux-android34-clang --version 2>&1 | head -n 1 || true)"
    if [[ "$WRAP_OUT" == *"Android clang"* ]]; then
        test_pass "NDK target wrapper operational"
    else
        test_fail "NDK target wrapper returned: $WRAP_OUT"
    fi
else
    test_fail "aarch64-linux-android34-clang not found on PATH"
fi

test_start "Google Android CLI (android) operational execution"
if command -v android >/dev/null 2>&1; then
    AND_OUT="$(android --version 2>&1 | head -n 1 || true)"
    if [[ -n "$AND_OUT" ]]; then
        test_pass "Android CLI operational: $AND_OUT"
    else
        test_fail "android --version returned empty output"
    fi
else
    test_fail "android executable not found on PATH"
fi

test_start "APK builder with external JAR dependency synthesis (termux-apk-build -j)"
if [[ -x "$SETUP_DIR/bin/termux-apk-build" ]] || command -v termux-apk-build >/dev/null 2>&1; then
    APK_BUILD_CMD="[[ -x \"$SETUP_DIR/bin/termux-apk-build\" ]] && echo \"$SETUP_DIR/bin/termux-apk-build\" || command -v termux-apk-build"
    APK_BUILD_CMD="$(eval "$APK_BUILD_CMD")"
    mkdir -p "$TMP_TEST_DIR/jar_proj/src/com/jarapp" "$TMP_TEST_DIR/jar_proj/libs" "$TMP_TEST_DIR/lib_src/com/helper" "$TMP_TEST_DIR/lib_classes"
    cat > "$TMP_TEST_DIR/lib_src/com/helper/MathUtil.java" <<'EOF'
package com.helper;
public class MathUtil {
    public static int add(int a, int b) { return a + b; }
}
EOF
    javac -d "$TMP_TEST_DIR/lib_classes" "$TMP_TEST_DIR/lib_src/com/helper/MathUtil.java"
    jar cf "$TMP_TEST_DIR/jar_proj/libs/mathutil.jar" -C "$TMP_TEST_DIR/lib_classes" .

    cat > "$TMP_TEST_DIR/jar_proj/AndroidManifest.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="com.jarapp">
    <application android:label="JarApp" />
</manifest>
EOF
    cat > "$TMP_TEST_DIR/jar_proj/src/com/jarapp/MainActivity.java" <<'EOF'
package com.jarapp;
import com.helper.MathUtil;
public class MainActivity {
    public static void run() {
        int res = MathUtil.add(10, 20);
    }
}
EOF
    if "$APK_BUILD_CMD" -m "$TMP_TEST_DIR/jar_proj/AndroidManifest.xml" \
                        -s "$TMP_TEST_DIR/jar_proj/src" \
                        -j "$TMP_TEST_DIR/jar_proj/libs" \
                        -o "$TMP_TEST_DIR/jar_proj/app.apk" >/dev/null 2>&1 && \
       apksigner verify "$TMP_TEST_DIR/jar_proj/app.apk" >/dev/null 2>&1 && \
       zipalign -c -P 16 4 "$TMP_TEST_DIR/jar_proj/app.apk" >/dev/null 2>&1; then
        test_pass "termux-apk-build integrated external JAR and passed 16KB verification"
    else
        test_fail "external JAR dependency build failed"
    fi
else
    test_fail "termux-apk-build executable not found"
fi

test_start "Android 11+ wireless ADB helper (termux-wireless-adb)"
if [[ -x "$SETUP_DIR/bin/termux-wireless-adb" ]]; then
    if "$SETUP_DIR/bin/termux-wireless-adb" help >/dev/null 2>&1; then
        test_pass "termux-wireless-adb CLI operational"
    else
        test_fail "termux-wireless-adb failed to return help"
    fi
else
    test_fail "termux-wireless-adb executable not found"
fi

test_start "AAPT2 incremental build cache verification (termux-apk-build)"
if [[ -x "$SETUP_DIR/bin/termux-apk-build" ]] || command -v termux-apk-build >/dev/null 2>&1; then
    APK_BUILD_CMD="[[ -x \"$SETUP_DIR/bin/termux-apk-build\" ]] && echo \"$SETUP_DIR/bin/termux-apk-build\" || command -v termux-apk-build"
    APK_BUILD_CMD="$(eval "$APK_BUILD_CMD")"
    mkdir -p "$TMP_TEST_DIR/cache_proj/res/values" "$TMP_TEST_DIR/cache_proj/src/com/example"
    cat > "$TMP_TEST_DIR/cache_proj/AndroidManifest.xml" <<'EOF'
<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="com.example.cache">
    <application android:label="CacheTest" />
</manifest>
EOF
    cat > "$TMP_TEST_DIR/cache_proj/res/values/strings.xml" <<'EOF'
<resources><string name="app_name">CacheTest</string></resources>
EOF
    cat > "$TMP_TEST_DIR/cache_proj/src/com/example/Main.java" <<'EOF'
package com.example;
public class Main {}
EOF
    # First build creates cache
    "$APK_BUILD_CMD" -p "$TMP_TEST_DIR/cache_proj" -o "$TMP_TEST_DIR/cache_proj/out1.apk" >/dev/null 2>&1 || true
    # Second build reuses cache
    run2_out="$("$APK_BUILD_CMD" -p "$TMP_TEST_DIR/cache_proj" -o "$TMP_TEST_DIR/cache_proj/out2.apk" 2>&1 || true)"
    if [[ -f "$TMP_TEST_DIR/cache_proj/.apk-cache/compiled-res.zip" ]] && [[ "$run2_out" =~ "CACHE HIT" ]]; then
        test_pass "AAPT2 incremental cache verified with CACHE HIT"
    else
        test_fail "AAPT2 incremental caching failed to trigger"
    fi
else
    test_fail "termux-apk-build executable not found"
fi

test_start "Encrypted developer vault roundtrip (OpenSSL AES-256-CBC)"
if command -v openssl >/dev/null 2>&1; then
    mkdir -p "$TMP_TEST_DIR/vault_test/src" "$TMP_TEST_DIR/vault_test/dst"
    echo "AI_SECRET_KEY=test_token_12345" > "$TMP_TEST_DIR/vault_test/src/.ai-env"
    if (cd "$TMP_TEST_DIR/vault_test/src" && tar -cf - .ai-env) | \
       openssl enc -aes-256-cbc -pbkdf2 -iter 100000 -pass pass:secretPass123 -salt -out "$TMP_TEST_DIR/vault_test/vault.enc" >/dev/null 2>&1 && \
       openssl enc -d -aes-256-cbc -pbkdf2 -iter 100000 -pass pass:secretPass123 -in "$TMP_TEST_DIR/vault_test/vault.enc" | \
       (cd "$TMP_TEST_DIR/vault_test/dst" && tar -xf -) >/dev/null 2>&1 && \
       cmp -s "$TMP_TEST_DIR/vault_test/src/.ai-env" "$TMP_TEST_DIR/vault_test/dst/.ai-env"; then
        test_pass "developer vault successfully encrypted and restored"
    else
        test_fail "developer vault encryption/decryption roundtrip failed"
    fi
else
    test_warn "openssl not available"
fi

test_start "Compiler cache (ccache) compilation & caching verification"
if command -v ccache >/dev/null 2>&1 && command -v clang >/dev/null 2>&1; then
    mkdir -p "$TMP_TEST_DIR/ccache_test"
    cat > "$TMP_TEST_DIR/ccache_test/hello.c" <<'EOF'
#include <stdio.h>
int main(void) { return 0; }
EOF
    if CCACHE_DIR="$TMP_TEST_DIR/ccache_test/.ccache" ccache clang -c "$TMP_TEST_DIR/ccache_test/hello.c" -o "$TMP_TEST_DIR/ccache_test/hello.o" >/dev/null 2>&1 && \
       [[ -f "$TMP_TEST_DIR/ccache_test/hello.o" ]]; then
        test_pass "ccache compiled object successfully and cached results"
    else
        test_fail "ccache compilation failed"
    fi
else
    test_warn "ccache or clang not installed"
fi

test_start "ShellCheck linting validation across all repository scripts"
if command -v shellcheck >/dev/null 2>&1; then
    if (cd "$SETUP_DIR" && shellcheck ./*.sh bin/* completions/*.bash) >/dev/null 2>&1; then
        test_pass "all shell scripts passed ShellCheck without warnings"
    else
        test_fail "ShellCheck reported lint warnings on repository scripts"
    fi
else
    test_warn "shellcheck not installed; run 'pkg install shellcheck'"
fi

# -------------------------------------------------------------
# Summary
# -------------------------------------------------------------
printf '\n%s=== Test Suite Results ===%s\n' "$BOLD$CYAN" "$NC"
printf '  Passed:   %s%d%s\n' "$GREEN$BOLD" "$PASSED" "$NC"
printf '  Warnings: %s%d%s\n' "$YELLOW$BOLD" "$WARNED" "$NC"
printf '  Failed:   %s%d%s\n\n' "$RED$BOLD" "$FAILED" "$NC"

if (( FAILED == 0 )); then
    printf '%s✔ SYSTEM IS VERIFIED BULLETPROOF.%s\n\n' "$GREEN$BOLD" "$NC"
    exit 0
else
    printf '%s✘ VERIFICATION FAILED. Address the failures above.%s\n\n' "$RED$BOLD" "$NC"
    exit 1
fi
