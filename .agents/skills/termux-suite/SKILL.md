---
name: termux-suite
description: >-
  Use this skill when developing, testing, verifying, or provisioning the Termux developer environment, toolchains, or AI CLI suite (agy, opencode, codex, gemini, copilot).
---

# Termux Provisioning & AI Suite Runbook

This skill provides step-by-step procedures for managing, testing, and troubleshooting the modular Termux developer environment.

## Quick Actions

### 1. Verify Toolchain Status
Inspect the status and versions of all system packages, compilers, Node.js toolchains, and AI CLIs:
```bash
bash setup.sh --verify
```

### 2. Run Stress & Verification Suite
Execute the automated 19-point test suite (testing kernel flock locks, PATH precedence, shebang integrity, compilers, all 5 AI CLI engines, and the complete Android SDK/NDK stack):
```bash
bash test-suite.sh
```

### 3. Clear Stale Concurrency Locks
If a script was interrupted abruptly:
```bash
bash setup.sh --clean
```

## Android Development Toolchain (TermuxVoid)

- **TermuxVoid Package Manager**: `tvpkg` (TUI tool for TermuxVoid packages).
- **Environment**: Automatically sourced via `~/.android-env` (`ANDROID_HOME`, `ANDROID_NDK_ROOT`, `JAVA_HOME`, and `PATH`).
- **SDK Tools**:
  - `sdkmanager`: `sdkmanager --list_installed`
  - `aapt2`: `aapt2 version`
  - `apksigner`: `apksigner --version`
  - `d8`: `d8 --version`
  - `adb`: `adb --version`
- **NDK Compilers**:
  - Clang: `$ANDROID_NDK_ROOT/toolchains/llvm/prebuilt/linux-arm64/bin/clang`
  - Clang++: `$ANDROID_NDK_ROOT/toolchains/llvm/prebuilt/linux-arm64/bin/clang++`
  - Supported Targets: `aarch64-linux-android`, `arm-linux-androideabi`, `i686-linux-android`, `x86_64-linux-android`, `riscv64-linux-android`.

## Adding or Updating AI Assistants

- **OpenCode**: Installed via `npm install -g opencode-termux@latest`. On first launch, it self-initializes the ARM64 runner.
- **OpenAI Codex**: Installed via `npm install -g @mmmbuto/codex-cli-termux@latest`.
- **Google Gemini**: Installed via `npm install -g @google/gemini-cli@latest`.
- **GitHub Copilot**: Installed via `npm install -g @bash0816/copilot-termux@latest && copilot-termux setup`.
- **Always run**: `termux-fix-shebang ~/.npm-global/bin/*` after any global npm install.

## Secrets & Authentication
Configuration and API keys are stored in `~/.ai-env` (mode 0600).
Authenticate each tool interactively:
- `agy`
- `opencode`
- `codex login`
- `gemini`
- `copilot`

