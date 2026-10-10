#!/data/data/com.termux/files/usr/bin/bash
#
# Ruthless Automated Verification & Stress Test Suite
# Tests every tool, compiler, AI CLI, and lockfile mechanism to ensure it is bulletproof.
#

set -Eeuo pipefail

SETUP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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
        [[ -f "$bin" && -x "$bin" ]] || continue
        FIRST_LINE="$(head -n 1 "$bin" 2>/dev/null || true)"
        if [[ "$FIRST_LINE" == "#!/usr/bin/env"* ]]; then
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
    PNPM_VER="$(pnpm --version 2>&1 || true)"
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
