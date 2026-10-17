# 🚀 Termux Developer & AI Suite (ARM64 / aarch64)

[![Platform](https://img.shields.io/badge/Platform-Termux%20%7C%20Android-green.svg)](https://termux.dev)
[![Architecture](https://img.shields.io/badge/Arch-ARM64%20%2F%20aarch64-blue.svg)](https://developer.arm.com)
[![Java](https://img.shields.io/badge/Java-OpenJDK%2021%20LTS-orange.svg)](https://openjdk.org)
[![Gradle](https://img.shields.io/badge/Gradle-9.8.1-02303A.svg)](https://gradle.org)
[![Android SDK](https://img.shields.io/badge/Android%20SDK-API%2036-3DDC84.svg)](https://developer.android.com/studio)
[![Android NDK](https://img.shields.io/badge/Android%20NDK-29.0%20(Clang%2021)-brightgreen.svg)](https://developer.android.com/ndk)
[![Node.js](https://img.shields.io/badge/Node.js-24%20LTS-339933.svg)](https://nodejs.org)
[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)

Turn your Android device into a powerhouse software engineering workstation. **Termux-Dev** automates the complete setup of a full developer environment on Android ARM64 (`aarch64`)—bringing native Android SDK/NDK compilers, OpenJDK 21, Node.js 24 LTS, the 5 leading terminal AI coding assistants, and sub-second zero-Gradle APK builds directly to Termux.

---

## 📑 Table of Contents

- [Overview](#-overview)
- [Key Features](#-key-features)
- [Architecture & Design Principles](#-architecture--design-principles)
- [Quick Start](#-quick-start)
  - [Remote One-Liner Bootstrap](#1-remote-one-liner-bootstrap)
  - [Interactive TUI Launcher](#2-interactive-tui-launcher)
  - [Shell Tab-Completion](#3-shell-tab-completion-zsh--bash)
  - [Command-Line Options](#4-command-line-options)
- [Modular Provisioning Stages](#-modular-provisioning-stages)
  - [Stage 01: Base System, Repositories & Zsh](#stage-01-base-system-repositories--zsh-01-termux-basesh)
  - [Stage 02: Essentials & Developer Toolchains](#stage-02-essentials--developer-toolchains-02-termux-essentialssh)
  - [Stage 03: Node.js & Package Managers](#stage-03-nodejs--package-managers-03-termux-node-toolchainsh)
  - [Stage 04: AI Coding Assistant Suite](#stage-04-ai-coding-assistant-suite-04-termux-ai-clish)
  - [Stage 05: Private AI Environment & Credentials](#stage-05-private-ai-environment--credentials-05-ai-envsh)
  - [Stage 06: Android SDK, NDK & TermuxVoid](#stage-06-android-sdk-ndk--termuxvoid-06-termux-android-sdksh)
- [Android App Development On-Device](#-android-app-development-on-device)
  - [Global Gradle Configuration](#global-gradle-configuration)
  - [Native NDK C/C++ Compilation](#native-ndk-cc-compilation)
- [AI Assistant Hub](#-ai-assistant-hub)
- [Automated Verification & Stress Test Suite](#-automated-verification--stress-test-suite)
- [Google Antigravity Integration](#-google-antigravity-integration)
- [Troubleshooting & FAQ](#-troubleshooting--faq)
- [Repository Structure](#-repository-structure)

---

## 🌟 Overview

Stock Termux is lightweight, but turning it into a complete, professional software development machine capable of building modern Android applications, compiling native C/C++ code, running LTS Node.js engines, and driving terminal AI assistants typically requires overcoming severe platform hurdles:
1. **Android Bionic libc vs. Standard GLIBC**: Linux binaries compiled against GNU libc crash immediately on Termux unless bridged.
2. **Arch Incompatibilities in Gradle**: Google’s Gradle build tools default to downloading x86_64 host binaries for `aapt2`, breaking on ARM64 phones.
3. **Shebang Mismatches**: Standard Linux scripts expect `/usr/bin/env` or `/bin/bash` which do not exist in Termux without prefix translation.
4. **Toolchain Pollution**: Installing global npm packages into system root risks corrupting Termux package indexes.

**Termux-Dev** solves every one of these challenges in a clean, modular, and 100% idempotent framework.

---

## ⚡ Key Features

- **🎮 Dual-Mode UI**: Features both a full-screen interactive **`dialog` TUI** with arrow-key navigation and a responsive ANSI terminal menu fallback.
- **📱 True Native Android SDK & NDK**:
  - Android Build Tools **36.1.0** (`aapt`, `aapt2`, `apksigner`, `d8`, `zipalign`)
  - Android Command-Line Tools **19.0** (`sdkmanager`, `avdmanager`, `lint`)
  - Platform Tools (`adb`, `fastboot`)
  - Full **NDK 29.0.14206865** LLVM Clang 21.0.0 toolchain with cross-target sysroots
  - OpenJDK 21 LTS & Gradle 9.8.1 with automated `aapt2` maven override
- **🤖 5 AI Coding Assistants Pre-Configured**:
  - **Google Antigravity (`agy`)**: Native ARM64 binary with workspace customization support
  - **OpenCode (`opencode`)**: Termux native ARM64 runner with auto-update
  - **OpenAI Codex (`codex`)**: Bionic-optimized ARM64 release with GPT catalog support
  - **Google Gemini (`gemini`)**: Official CLI with interactive prompts
  - **GitHub Copilot (`copilot`)**: Glibc runtime-bridged binary with seamless device auth
- **🔒 Kernel Concurrency Locking**: Every stage uses kernel-managed `flock` locks, preventing race conditions or corrupted partial runs while remaining immune to stale lockfiles after crashes.
- **🛡️ Clean Shell & Secret Isolation**: Dual-shell parity for Bash and Zsh, user-global npm prefix (`~/.npm-global`), isolated private keys (`~/.ai-env` with `0600` permissions), and persistent environment profiles (`~/.android-env`).
- **🧪 Ruthless 30-Point Stress Test Suite**: Rigorously tests file locks, PATH precedence, permissions, shebang integrity, compilers, all 5 AI engines, the complete Android SDK/NDK toolchain, Android Studio project auto-detection, external JAR library synthesis, ShellCheck lint validation, and Android 15+ 16KB page-aligned APK generation.

---

## 🏗️ Architecture & Design Principles

```
  ┌────────────────────────────────────────────────────────┐
  │                 termux-suite / tsuite                  │
  │               Interactive TUI Orchestrator             │
  └───────────────────────────┬────────────────────────────┘
                              │
         ┌────────────────────┼───────────────────┐
         ▼                    ▼                   ▼
  ┌─────────────┐      ┌─────────────┐     ┌─────────────┐
  │   Base &    │      │  Compilers  │     │   Node.js   │
  │ Repositories│      │ & Essentials│     │  Toolchain  │
  │  (Stage 01) │      │  (Stage 02) │     │  (Stage 03) │
  └─────────────┘      └─────────────┘     └─────────────┘
         │                    │                   │
         ▼                    ▼                   ▼
  ┌─────────────┐      ┌─────────────┐     ┌─────────────┐
  │   AI CLI    │      │   AI Env    │     │ Android SDK │
  │    Suite    │      │ & Secrets   │     │ & NDK Suite │
  │  (Stage 04) │      │  (Stage 05) │     │  (Stage 06) │
  └─────────────┘      └─────────────┘     └─────────────┘
                              │
                              ▼
  ┌────────────────────────────────────────────────────────┐
  │        Ruthless 30-Point Automated Test Suite          │
  └────────────────────────────────────────────────────────┘
```

1. **Native over Container**: Wherever possible, binaries run directly on Termux/Bionic for maximum speed, zero proot overhead, and direct access to device hardware.
2. **GLIBC Bridging on Demand**: When a tool requires glibc (e.g., GitHub Copilot CLI), it is bridged using `termux-glibc` (`grun` or custom dynamic loader invocation) without altering system Bionic libraries.
3. **Zero Credential Exposure**: No secrets or API keys are ever committed, hard-coded, or stored in world-readable files. `~/.ai-env` is locked to mode `0600`.
4. **Idempotence**: Every script can be executed multiple times safely without duplicated lines in shell rc files or redundant package downloads.

---

## 🚀 Quick Start

### 1. Remote One-Liner Bootstrap

To set up the entire development workstation on any fresh or existing Termux installation with a single command:

```bash
pkg update -y && pkg install -y curl && bash -c "$(curl -fsSL https://raw.githubusercontent.com/00AstroGit00/Termux-Dev/main/install.sh)"
```

> [!TIP]
> **Why `pkg update && pkg install -y curl`?** Stock Termux installs do not include `curl` by default. Prepending this ensures the one-liner executes cleanly out of the box on 100% of fresh setups without halting on missing package errors.

The installer automatically verifies prerequisites, initializes your workspace, installs global `termux-suite` and `tsuite` CLI commands, and launches the interactive menu.

---

### 2. Interactive TUI Launcher

Once installed (or inside this workspace), launch the TUI anytime from anywhere:

```bash
termux-suite
# or the short alias:
tsuite
```

#### Modern TUI Interface Walkthrough:
```text
  Termux-Dev ARM64 Workstation  │  RAM: 4.8Gi Avail  │  Disk: 18.2Gi Free  │  Bat: 85%  │  Git: main (0*)
 ┌────────────────────── Termux Developer Suite ─────────────────────────┐
 │ Select an action with Up/Down and press Enter:                        │
 │                                                                       │
 │  1   ▶  Run Complete Pipeline (Stages 01 -> 06)                       │
 │  W   🧙 Custom Multi-Stage Selection Wizard                            │
 │  2   [✓] Stage 01: Base System, Repos & Zsh                           │
 │  3   [✓] Stage 02: Essentials & Dev Toolchains                        │
 │  4   [✓] Stage 03: Node.js 24 & Package Managers                      │
 │  5   [✓] Stage 04: AI CLI Suite (5 Assistants)                        │
 │  6   [✓] Stage 05: Private AI Environment (~/.ai-env)                 │
 │  7   [✓] Stage 06: Android SDK, NDK & OpenJDK 21                      │
 │  8   ⚡ Build Android APK (Sub-Second Engine)                          │
 │  9   📶 Wireless ADB Pairing & Connect (Android 11+)                  │
 │ 10   ✓  Verify All Installed Tools & CLIs                             │
 │ 11   🧪 Run Ruthless 33-Point Stress Test Suite                       │
 │ 12   🩺 System Doctor: Health & Diagnostics                           │
 │ 13   ⌨️  Configure Developer Extra-Keys                                │
 │ 14   🔋 Disable Phantom Process Killer                                │
 │ 15   ✂️  Prune Unused NDK Sysroots (Save ~600MB)                       │
 │ 16   🔒 Encrypted Developer Vault (Backup / Restore)                  │
 │ 17   🧹 Deep Clean Cache, Temp Files & Locks                           │
 │ 18   🛡️  Install Local Git Pre-Commit Hook                             │
 │  0   🚪 Exit to Shell                                                 │
 ├───────────────────────────────────────────────────────────────────────┤
 │        < Select >      < Doctor >      < Help >      < Exit >         │
 └───────────────────────────────────────────────────────────────────────┘
```

#### Responsive ANSI Card Fallback:
When running in environments where ncurses is unavailable or over serial/SSH, the suite falls back cleanly to a grouped ANSI card interface with **instant single-key touch response** and mnemonic triggers:
- `1` or `A` — Run Complete Pipeline
- `W` — Custom Multi-Stage Selection Wizard (interactive checklist)
- `2` or `B` — Stage 01: Base System & Zsh
- `8` or `K` — Build Android APK (Sub-second with AAPT2 incremental cache)
- `9` or `Y` — Android 11+ Wireless ADB Pairing & Connect
- `11` or `T` — Run 33-Point Stress Test Suite
- `12` or `H` — System Doctor & Diagnostics
- `16` or `L` — Encrypted Developer Vault (AES-256-CBC backup/restore)
- `0` or `Q` — Exit to Shell

---

### 3. Shell Tab-Completion (Zsh & Bash)

Fast, context-aware command tab-completions are provided and automatically installed into `$PREFIX/share/zsh/site-functions` and `$PREFIX/etc/bash_completion.d`:

```bash
tsuite --<TAB>
# Completes: --all, --wizard, --apk, --adb, --backup, --restore, --verify, --doctor, --test, --clean, etc.

termux-apk-build -<TAB>
# Completes: -p (--project), -m (--manifest), -s (--src), -r (--res), -j (--jars), -o (--output), --no-cache, --clean-cache
```

---

### 4. Command-Line Options

You can also run specific tasks directly without the TUI:

```bash
./setup.sh --all            # Execute all stages (01 -> 06) sequentially
./setup.sh --wizard         # Launch custom multi-stage selection wizard
./setup.sh --base           # Stage 01: Base system, repos & Zsh
./setup.sh --essentials     # Stage 02: Compilers, tools & dev utilities
./setup.sh --node           # Stage 03: Node.js 24 LTS & package managers
./setup.sh --ai             # Stage 04: AI CLI Suite provisioning
./setup.sh --ai-env         # Stage 05: Setup private ~/.ai-env template
./setup.sh --android        # Stage 06: Android SDK, NDK & TermuxVoid setup
./setup.sh --apk            # Interactive standalone APK builder (zero Gradle)
./setup.sh --adb            # Android 11+ wireless ADB pairing & connect helper
./setup.sh --backup [file]  # Export encrypted developer vault (AES-256-CBC)
./setup.sh --restore [file] # Restore developer vault from encrypted archive
./setup.sh --verify         # Inspect status of all installed tools
./setup.sh --doctor         # Run Termux system health & environment diagnostics
./setup.sh --test           # Run ruthless 33-point stress & verification suite
./setup.sh --prune-ndk      # Prune unused NDK sysroots (reclaims ~600MB)
./setup.sh --tune-device    # Disable Phantom Process Killer (root or ADB guidance)
./setup.sh --tune-keys      # Configure enhanced dual-row developer extra-keys layout
./setup.sh --install-hooks  # Install local Git pre-commit verification hook
./setup.sh --clean          # Remove locks, temp files, and apt package archives
./setup.sh --help           # Display usage information
```

---

## 📦 Modular Provisioning Stages

### Stage 01: Base System, Repositories & Zsh (`01-termux-base.sh`)
- Configures core APT mirrors (`main`, `x11`, `root`, `tur`).
- Installs base system tools: `bash-completion`, `git`, `gh`, `curl`, `rsync`, `tar`, `xz-utils`.
- Optional TermuxVoid repository integration.
- Sets up modern **Zsh** with `zsh-autosuggestions`, `zsh-syntax-highlighting`, and custom prompt profiles.
- Configures **OpenSSH (`sshd`)** with quick management aliases (`ssh-start`, `ssh-stop`, `ssh-status`).

### Stage 02: Essentials & Developer Toolchains (`02-termux-essentials.sh`)
- **Compilers**: Clang 21, GNU Make, CMake 4.4, binutils.
- **Programming Languages**: Python 3.14 (with pip and build headers), Rust 1.99 (`rustc` & `cargo`), Go, Perl.
- **Search & Productivity**: `ripgrep` (`rg`), `jq`, `tree`, `tmux`, `micro`, `vim`.
- **Databases & Networking**: SQLite 3, `nmap`, `net-tools`, `gping`, `dnsutils`.

### Stage 03: Node.js & Package Managers (`03-termux-node-toolchain.sh`)
- Installs Termux **`nodejs-lts` (v24.x)** and npm 11.
- Isolates global modules into `~/.npm-global` to keep system files clean.
- Pins **pnpm 10.x line (`10.33.4`)** to guarantee ARM64 compatibility on Android.
- Installs Yarn and runs `termux-fix-shebang` on all global CLI binaries.

### Stage 04: AI Coding Assistant Suite (`04-termux-ai-cli.sh`)
- Installs and verifies 5 AI coding assistants natively on Termux ARM64.
- Automated glibc linker wrapping for GitHub Copilot.
- Self-bootstrapping runtime configuration for OpenCode.

### Stage 05: Private AI Environment & Credentials (`05-ai-env.sh`)
- Provisions a dedicated `~/.ai-env` template locked with strict `600` permissions.
- Integrated into both `~/.bashrc` and `~/.zshrc`.
- Provides environment variable placeholders for Gemini, OpenAI, Anthropic, OpenRouter, and GitHub tokens.

### Stage 06: Android SDK, NDK & TermuxVoid (`06-termux-android-sdk.sh`)
- Connects the **TermuxVoid** repository (`tvpkg` TUI package manager).
- Installs **OpenJDK 21 LTS** and **Gradle 9.8.1**.
- Deploys **Android SDK (36.1.0)** with `aapt2`, `apksigner`, `d8`, and `sdkmanager` (v19.0).
- Deploys **Android NDK (29.0.14206865)** featuring LLVM Clang 21.0.0.
- Establishes global `~/.gradle/gradle.properties` and persistent `~/.android-env`.

---

## 📱 Android App Development On-Device

With this suite, you can build native Android applications and compile C/C++ libraries directly on your phone or tablet without needing a desktop PC.

### Global Gradle Configuration

Gradle builds automatically read [`~/.gradle/gradle.properties`](file:///data/data/com.termux/files/home/.gradle/gradle.properties):

```properties
# Native Termux ARM64 AAPT2 Override
android.aapt2FromMavenOverride=/data/data/com.termux/files/usr/opt/android-sdk/build-tools/36.1.0/aapt2

# Disable file system watching due to Termux inotify / native JNI limits
org.gradle.vfs.watch=false

# Enable parallel execution across mobile CPU cores
org.gradle.parallel=true

# JVM Memory optimization for mobile SoC
org.gradle.jvmargs=-Xmx2048m -XX:+UseG1GC -XX:MaxMetaspaceSize=512m

# Disable automatic x86_64 SDK download attempt
android.builder.sdkDownload=false
```

### In Your Android Project

In any Android application directory, configure [`android/local.properties`](file:///data/data/com.termux/files/usr/opt/android-sdk):

```properties
sdk.dir=/data/data/com.termux/files/usr/opt/android-sdk
ndk.dir=/data/data/com.termux/files/usr/opt/android-sdk/ndk/29.0.14206865
cmake.dir=/data/data/com.termux/files/usr/opt/android-sdk/cmake/4.1.2
```

Build debug APKs directly:
```bash
./gradlew assembleDebug
```

### Native NDK C/C++ Compilation

Compile native ARM64 executables directly with NDK Clang:

```bash
# C Compilation
$ANDROID_NDK_ROOT/toolchains/llvm/prebuilt/linux-arm64/bin/clang main.c -o myapp

# C++ Compilation (with static STL)
$ANDROID_NDK_ROOT/toolchains/llvm/prebuilt/linux-arm64/bin/clang++ -static-libstdc++ main.cpp -o myapp_cpp
```

Supported NDK cross-compilation targets:
- `aarch64-linux-android` (ARM64)
- `arm-linux-androideabi` (ARMv7)
- `x86_64-linux-android` (x86_64)
- `i686-linux-android` (x86)
- `riscv64-linux-android` (RISC-V 64)

### Standalone Zero-Gradle APK Builder (`termux-apk-build`)

Compile, package, 16KB-align, sign, and optionally install Android apps directly on-device in under 1 second without Gradle daemon memory overhead:

```bash
# Auto-detect standard Android Studio / Gradle project layouts:
termux-apk-build -p /path/to/android-project

# Auto-detect project, include external library JARs, and deploy via ADB:
termux-apk-build -p /path/to/android-project -i

# Manual build with custom manifest, sources, and external libraries:
termux-apk-build -m AndroidManifest.xml -s src/ -j libs/ -o app-release.apk

# Options:
#   -p, --project <dir>    Android Studio project root (auto-detects app/src/main/...)
#   -m, --manifest <file>  Path to AndroidManifest.xml
#   -s, --src <dir>        Path to Java/Kotlin source directory
#   -r, --res <dir>        Path to Android resources directory
#   -l, --lib <dir>        Path to native .so shared libraries (stored uncompressed for 16KB mmap)
#   -j, --jars <path>      Path to external JAR dependency file or libs directory
#   -i, --install          Auto-install APK onto target device via adb upon build
#   -o, --output <file>    Path for output signed APK (default: app-signed.apk)
#       --min-sdk <num>    Set minimum SDK version
#       --target-sdk <num> Set target SDK version
```

### Official Google Android CLI (`android`)

The workstation integrates Google's official Android CLI (`android`) bridged for ARM64:
- **Binary Location**: `~/.local/bin/android` (bridged to `~/.android/bin/android-cli` via `termux-glibc` and `patchelf`).
- **Official Documentation Search & Fetch**: Instant offline-indexed search across 5,300+ Google Android developer documentation guides:
  ```bash
  android docs search "Activity lifecycle"
  android docs fetch "kb://android/guide/topics/manifest/activity-element"
  ```
- **CLI Commands**:
  - `android info`: Report active Android SDK and environment parameters.
  - `android create`: Generate Android projects from official Google templates.
  - `android describe`: Analyze project targets and artifacts.

---

## 🤖 AI Assistant Hub

The suite packages and maintains 5 leading terminal AI coding assistants:

| Assistant | CLI Command | Package Source | Authentication & Setup |
| :--- | :--- | :--- | :--- |
| **Google Antigravity** | `agy` | Community Termux Native ARM64 | Run `agy` and follow browser/Google account prompt |
| **OpenCode** | `opencode` | `opencode-termux` (native ARM64 runner) | Run `opencode` -> configure preferred LLM provider |
| **OpenAI Codex** | `codex` | `@mmmbuto/codex-cli-termux` | Run `codex login` or set `OPENAI_API_KEY` in `~/.ai-env` |
| **Google Gemini** | `gemini` | `@google/gemini-cli` | Run `gemini` or set `GEMINI_API_KEY` in `~/.ai-env` |
| **GitHub Copilot** | `copilot` | `@bash0816/copilot-termux` (glibc bridge) | Run `copilot` and authenticate via device code |

---

## 🧪 Automated Verification & Stress Test Suite

Execute the full 30-point verification suite at any time:

```bash
bash test-suite.sh
# or:
termux-suite --test
```

### Test Suite Output

```
=======================================================
       RUTHLESS VERIFICATION & STRESS TEST SUITE       
=======================================================

▶ [TEST] Kernel flock lock acquisition & crash recovery ... PASS
▶ [TEST] PATH ordering (~/.local/bin precedes ~/.npm-global/bin) ... PASS
▶ [TEST] Security permissions on ~/.ai-env ... PASS (Permissions secure: 600)
▶ [TEST] Interpreter shebangs in ~/.npm-global/bin ... PASS
▶ [TEST] Clang C compiler execution ... PASS
▶ [TEST] Python 3 runtime & stdlib execution ... PASS (PYTHON_OK 3.14)
▶ [TEST] Node.js 24 LTS runtime & architecture execution ... PASS (NODE_OK v24.18.0 arm64)
▶ [TEST] pnpm ARM64 compatibility execution ... PASS (pnpm pinned version: 10.33.4)
▶ [TEST] Antigravity CLI (agy) functional execution ... PASS (1.4.0)
▶ [TEST] OpenCode (opencode) functional execution ... PASS (1.19.3)
▶ [TEST] OpenAI Codex CLI (codex) functional execution ... PASS (codex-cli 0.162.1)
▶ [TEST] Google Gemini CLI (gemini) functional execution ... PASS (0.64.0)
▶ [TEST] GitHub Copilot CLI (copilot via grun) functional execution ... PASS (1.0.97)
▶ [TEST] TermuxVoid package manager (tvpkg) ... PASS
▶ [TEST] Java OpenJDK 21 execution ... PASS (openjdk 21.0.12)
▶ [TEST] Gradle build system execution ... PASS (Gradle 9.8.1)
▶ [TEST] Android SDK & build-tools (aapt2, d8, apksigner) ... PASS
▶ [TEST] Android Debug Bridge (adb) socket protocol execution ... PASS
▶ [TEST] Android SDK Manager (sdkmanager) ... PASS (19.0)
▶ [TEST] Android NDK LLVM Clang compiler execution ... PASS (Clang 21.0.0)
▶ [TEST] AAPT2, d8 & apksigner APK synthesis and signing ... PASS
▶ [TEST] Standalone zero-Gradle APK builder (termux-apk-build) ... PASS
▶ [TEST] Android APK zipalign 4-byte & 16KB page alignment verification ... PASS
▶ [TEST] Android Studio project auto-detection build (termux-apk-build -p) ... PASS
▶ [TEST] Android NDK native C compilation (ARM64) ... PASS
▶ [TEST] Android NDK native C++20 STL compilation (ARM64) ... PASS
▶ [TEST] Android NDK target wrapper (aarch64-linux-android34-clang) ... PASS
▶ [TEST] Google Android CLI (android) operational execution ... PASS (1.0.16625370)
▶ [TEST] APK builder with external JAR dependency synthesis (termux-apk-build -j) ... PASS
▶ [TEST] Android 11+ wireless ADB helper (termux-wireless-adb) ... PASS
▶ [TEST] AAPT2 incremental build cache verification (termux-apk-build) ... PASS
▶ [TEST] Encrypted developer vault roundtrip (OpenSSL AES-256-CBC) ... PASS
▶ [TEST] ShellCheck linting validation across all repository scripts ... PASS

=== Test Suite Results ===
  Passed:   33
  Warnings: 0
  Failed:   0

✔ SYSTEM IS VERIFIED BULLETPROOF.
```

---

## 🧠 Google Antigravity Integration

This repository includes native customizations following the **Google Antigravity Customization System**:

- **Workspace Rules ([`AGENTS.md`](./AGENTS.md))**: Informs AI coding agents about Termux architecture, Bionic libc vs. glibc, npm isolation standards, and Android Gradle properties.
- **Suite Management Skill ([`.agents/skills/termux-suite/SKILL.md`](./.agents/skills/termux-suite/SKILL.md))**: Provides runbooks for managing the suite, diagnosing errors, updating AI assistants, and verifying toolchains.
- **Android Toolchain Skill ([`.agents/skills/termux-android/SKILL.md`](./.agents/skills/termux-android/SKILL.md))**: Complete guide and runbook for standalone APK packaging, AAPT2/D8/apksigner workflows, NDK C/C++ compilation, and Gradle configuration.
- **Git Review Skill ([`.agents/skills/termux-git-review/SKILL.md`](./.agents/skills/termux-git-review/SKILL.md))**: Non-destructive Git inspection, diff analysis, and commit verification workflows.
- **Security Audit Skill ([`.agents/skills/termux-security-audit/SKILL.md`](./.agents/skills/termux-security-audit/SKILL.md))**: Credential scanning, path/sandbox boundary enforcement, and destructive operation guardrails.

---

## ❓ Troubleshooting & FAQ

### 1. Bad interpreter / shebang errors (`/usr/bin/env: bad interpreter`)
Termux does not use standard `/usr/bin/env`. Run the Termux shebang fixer:
```bash
termux-fix-shebang ~/.npm-global/bin/* ~/.local/bin/* $PREFIX/bin/* 2>/dev/null || true
```

### 2. A stage script says "Another instance is already running"
If an installation was killed abruptly with `SIGKILL`:
```bash
termux-suite --clean
# or manually:
rm -rf "$PREFIX/tmp"/*.lock
```

### 3. Gradle throws `java.lang.OutOfMemoryError`
Mobile Android devices enforce memory constraints. Limit the Gradle daemon JVM heap size in `~/.gradle/gradle.properties`:
```properties
org.gradle.jvmargs=-Xmx1024m -XX:+UseG1GC
```

### 4. SDK Manager says `Could not determine SDK root`
Ensure `cmdline-tools` is placed inside `latest/bin/`. Our installer automatically applies this patch, but if you re-extract the SDK, run:
```bash
bash 06-termux-android-sdk.sh
```

### 5. ADB returns `error: protocol fault (couldn't read status): Connection reset by peer`
The generic SDK build of ADB in `$ANDROID_HOME/platform-tools/adb` is incompatible with the Termux Bionic socket sandbox. The workstation automatically symlinks the Termux-native `android-tools` package (`$PREFIX/bin/adb`) into `platform-tools/adb`. To restart cleanly:
```bash
adb kill-server
adb devices
```

---

## 📁 Repository Structure

```text
Termux-Dev/
├── .github/
│   └── workflows/
│       └── ci.yml              # Automated GitHub Actions CI workflow
├── .agents/
│   └── skills/
│       ├── termux-suite/
│       │   └── SKILL.md        # Antigravity suite management runbook
│       ├── termux-android/
│       │   └── SKILL.md        # Antigravity Android & NDK development runbook
│       ├── termux-git-review/
│       │   └── SKILL.md        # Antigravity Git inspection & review runbook
│       └── termux-security-audit/
│           └── SKILL.md        # Antigravity security & sandbox audit runbook
├── bin/
│   ├── termux-suite            # Global CLI launcher executable
│   └── termux-apk-build        # Zero-Gradle instant standalone APK builder
├── completions/
│   ├── _tsuite                 # Zsh completion for tsuite and termux-suite
│   ├── _termux-apk-build       # Zsh completion for termux-apk-build and apk-build
│   └── tsuite.bash             # Bash completion for all suite commands
├── 01-termux-base.sh           # Stage 01: System repos, core packages, Zsh, SSH
├── 02-termux-essentials.sh     # Stage 02: Compilers, Python, Rust, Go, tools
├── 03-termux-node-toolchain.sh # Stage 03: Node.js LTS, isolated npm, pnpm, Yarn
├── 04-termux-ai-cli.sh         # Stage 04: AI CLI suite (agy, opencode, codex, gemini, copilot)
├── 05-ai-env.sh                # Stage 05: Private credentials template (~/.ai-env)
├── 06-termux-android-sdk.sh    # Stage 06: Android SDK, NDK, TermuxVoid, Java
├── setup.sh                    # Master orchestrator (TUI & CLI interface)
├── install.sh                  # One-line curl bootstrap installer
├── test-suite.sh               # Ruthless 30-point stress & verification suite
├── AGENTS.md                   # Antigravity workspace rules & guidelines
├── LICENSE                     # Apache 2.0 Open Source License
├── .shellcheckrc               # ShellCheck linting configuration
├── .gitignore                  # Git ignore rules for locks, secrets, and builds
└── README.md                   # Comprehensive project documentation
```

---

## 📄 License

This project is licensed under the Apache 2.0 License. See the individual stages and tools for their respective upstream licenses.
