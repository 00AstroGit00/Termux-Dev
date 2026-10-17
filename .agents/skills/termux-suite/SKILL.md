---
name: termux-suite
description: >-
  Use this skill when developing, testing, verifying, or provisioning the Termux developer environment, toolchains, or AI CLI suite (agy, opencode, codex, gemini, copilot).
---

# Termux Provisioning & AI Suite Runbook

This skill provides step-by-step procedures for managing, testing, and troubleshooting the modular Termux developer environment.

## Quick Actions

### 1. Verify Toolchain Status
Inspect the status and versions of all system packages, compilers, Node.js toolchains, AI CLIs, and Android tools:
```bash
bash setup.sh --verify
```

### 2. Run Stress & Verification Suite
Execute the automated 33-point test suite (testing kernel flock locks, PATH precedence, shebang integrity, compilers, all 5 AI CLI engines, Android Studio project auto-detect, external JAR library synthesis, ShellCheck lint validation, 16KB zipalign, AAPT2 incremental build caching, Wireless ADB helper, Encrypted Developer Vault, and the complete Android SDK/NDK stack):
```bash
bash test-suite.sh
# or:
tsuite --test
```

### 3. Custom Multi-Stage Selection Wizard
Launch the interactive checklist wizard to choose custom combinations of setup stages:
```bash
bash setup.sh --wizard
# or:
tsuite --wizard
```

### 4. Encrypted Developer Vault (Backup / Restore)
Securely backup or restore sensitive credentials (`~/.ai-env`, `~/.ssh/`, `~/.gitconfig`) with OpenSSL AES-256-CBC:
```bash
# Export encrypted vault:
tsuite --backup [output_file.enc]

# Restore from encrypted vault:
tsuite --restore [input_file.enc]
```

### 5. Wireless ADB Pairing & Connect (Android 11+)
Pair and connect to on-device wireless debugging without a PC or USB cable:
```bash
# Interactive helper:
termux-wireless-adb

# Or direct commands:
termux-wireless-adb pair <port> <code>
termux-wireless-adb connect <port>
termux-wireless-adb reconnect
```

### 6. Clear Stale Concurrency Locks
If a script was interrupted abruptly:
```bash
bash setup.sh --clean
```

### 7. Prune Unused NDK Sysroots (Save ~600MB)
Remove unused x86, x86_64, and RISC-V cross-compilation sysroots:
```bash
bash setup.sh --prune-ndk
```

### 8. Tune Device (Disable Android 12+ Phantom Process Killer)
Neutralize the 32-child-process background restriction:
```bash
bash setup.sh --tune-device
```

### 9. Install Local Git Pre-Commit Hook
Ensure invalid shell scripts or unexecutable files can never be committed:
```bash
bash setup.sh --install-hooks
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
- **Standalone APK Engine (`termux-apk-build`)**:
  - Rapid zero-Gradle compilation in < 1 second.
  - Auto-detects Android Studio / Gradle project layouts: `termux-apk-build -p <project-dir>`
  - Incremental AAPT2 resource cache (`.apk-cache`) dropping rebuilds to sub-300ms.
  - Bundles uncompressed native libraries with 16KB page alignment: `termux-apk-build -l <lib-dir>`
  - Aligns to 16KB boundaries via `zipalign -P 16 -f 4` and signs with `apksigner`.
  - 1-tap package installation via Android Sharesheet (`-u, --share`).

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

