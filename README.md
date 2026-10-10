# Termux Developer & AI Suite (ARM64 / aarch64)

An enterprise-grade, modular, and hardened developer environment bootstrap and AI CLI suite for Termux on Android ARM64 (`aarch64`).

---

## Overview

This repository provides an automated, modular, and idempotent provisioning framework designed to turn a stock Termux installation into a full-stack mobile developer workstation equipped with native compilers, modern runtimes, Android SDK/NDK toolchains, and leading AI terminal coding assistants.

### Key Architecture Highlights
- **Architecture**: Exclusively optimized for native ARM64 / `aarch64`.
- **Concurrency Protection**: Kernel-managed `flock` file locking ensures safe, non-conflicting stage execution without stale lock risks.
- **Node.js Isolation**: Keeps Termux's system packages intact by installing all global JavaScript tooling under `~/.npm-global`.
- **Shebang Healing**: Automatic Termux shebang normalization (`termux-fix-shebang`) for all global binaries and SDK tools.
- **Full Android Toolchain**: Native Android SDK (36.1.0), NDK (29.0.14206865 LLVM Clang), OpenJDK 21 LTS, Gradle 9.x, and TermuxVoid repository integration (`tvpkg`).
- **AI CLI Suite**: Out-of-the-box integration for 5 major AI coding agents.

---

## Modular Stages

| Stage Script | Component | Description |
| :--- | :--- | :--- |
| **`01-termux-base.sh`** | Base System & Repos | Repositories (main, x11, root, tur), core utilities, Zsh with plugins, SSH daemon |
| **`02-termux-essentials.sh`** | Developer Toolchains | Clang 21, Make, CMake, Python 3.14, Rust 1.99, Go, databases, media & network tools |
| **`03-termux-node-toolchain.sh`** | JavaScript Runtimes | Node.js 24 LTS, npm 11, Yarn, pnpm (pinned 10.x line for native ARM64 compatibility) |
| **`04-termux-ai-cli.sh`** | AI Assistant Suite | Google Antigravity (`agy`), OpenCode (`opencode`), OpenAI Codex (`codex`), Google Gemini (`gemini`), GitHub Copilot (`copilot`) |
| **`05-ai-env.sh`** | Credentials & Secrets | Secure `~/.ai-env` configuration template (mode `0600`) loaded by Bash and Zsh |
| **`06-termux-android-sdk.sh`** | Android SDK & NDK | TermuxVoid repo, Android SDK 36.1.0, NDK 29.0, OpenJDK 21, Gradle, global `aapt2` overrides |

---

## Quick Start

### 1. Single Command Interactive TUI Launch
Launch the interactive TUI directly from anywhere in your terminal:
```bash
termux-suite
# or quick alias:
tsuite
```

### 2. Remote One-Line Bootstrap Installer
On a fresh Termux device or new installation, clone and open the TUI in a single command:
```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/00AstroGit00/Termux-Dev/main/install.sh)"
```

### 3. Command-Line Options
Execute specific stages or run full provisioning directly:
```bash
./setup.sh --all         # Run Stages 01 through 06 sequentially
./setup.sh --base        # Stage 01: Base system & repos
./setup.sh --essentials  # Stage 02: Compilers & dev tools
./setup.sh --node        # Stage 03: Node.js & package managers
./setup.sh --ai          # Stage 04: AI CLI Suite
./setup.sh --ai-env      # Stage 05: Private AI environment template
./setup.sh --android     # Stage 06: Android SDK, NDK & TermuxVoid
./setup.sh --verify      # Inspect status of all installed tools
./setup.sh --test        # Run ruthless 19-point stress & verification test suite
./setup.sh --clean       # Clean concurrency locks and temporary files
```

---

## AI Assistant Suite

| Assistant | CLI Command | Package Source | Authentication |
| :--- | :--- | :--- | :--- |
| **Google Antigravity** | `agy` | Native Termux ARM64 binary | Run `agy` (Google developer login) |
| **OpenCode** | `opencode` | `opencode-termux` (native ARM64 runner) | Interactive / `~/.config/opencode/` |
| **OpenAI Codex** | `codex` | `@mmmbuto/codex-cli-termux` | `codex login` or `OPENAI_API_KEY` |
| **Google Gemini** | `gemini` | `@google/gemini-cli` | Run `gemini` or `GEMINI_API_KEY` |
| **GitHub Copilot** | `copilot` | `@bash0816/copilot-termux` (glibc bridged) | Run `copilot` (browser/device code) |

---

## Android Development Setup

- **SDK Location**: `$PREFIX/opt/android-sdk`
- **NDK Location**: `$PREFIX/opt/android-sdk/ndk/29.0.14206865`
- **Java Home**: `$PREFIX/lib/jvm/java-21-openjdk`
- **Shell Exports**: Persistent configuration managed via `~/.android-env`.
- **Global Gradle Configuration (`~/.gradle/gradle.properties`)**:
  ```properties
  android.aapt2FromMavenOverride=/data/data/com.termux/files/usr/opt/android-sdk/build-tools/36.1.0/aapt2
  org.gradle.jvmargs=-Xmx2048m -XX:+UseG1GC
  android.builder.sdkDownload=false
  ```

---

## Verification & Test Suite

Run the 19-point automated stress and functional test suite:
```bash
bash test-suite.sh
```

### Coverage
- Kernel `flock` lock concurrency & crash recovery
- `$PATH` ordering precedence (`~/.local/bin` > `~/.npm-global/bin`)
- Security permissions on credential files (`~/.ai-env` mode 600)
- Interpreter shebang resolution across all npm global binaries
- Functional compiler execution: Clang C (ARM64 native binary generation), Python 3.14, Node.js 24 LTS, pnpm 10.x
- Functional execution of all 5 AI CLI engines (`agy`, `opencode`, `codex`, `gemini`, `copilot`)
- Android toolchain verification: `tvpkg`, OpenJDK 21, Gradle 9.x, `aapt2`, `apksigner`, `d8`, `sdkmanager`, and NDK Clang 21.0.0
