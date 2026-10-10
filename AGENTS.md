# Termux Environment & Project Rules

Guidelines and architectural constraints for development and automation within this Termux environment.

## 1. Environment Architecture & Constraints
- **Platform**: Termux on Android ARM64 (`aarch64`).
- **C Library**: Android Bionic libc is standard. GLIBC-dependent binaries must run via `termux-glibc` (`grun` or direct loader invocation `ld-linux-aarch64.so.1 --library-path $PREFIX/glibc/lib`).
- **Paths**:
  - Termux Prefix: `$PREFIX` (`/data/data/com.termux/files/usr`).
  - User Home: `$HOME` (`/data/data/com.termux/files/home`).
  - Standard Linux root paths (`/bin`, `/etc`, `/lib`) do not exist natively; always respect `$PREFIX`.

## 2. JavaScript & Node.js Toolchain Rules
- **Node.js**: Use Termux `nodejs-lts` package.
- **npm Global Prefix**: User-isolated prefix at `~/.npm-global`. Do NOT install global npm packages into system `/data/data/com.termux/files/usr/lib/node_modules`.
- **PATH Ordering**:
  ```bash
  export PATH="$HOME/.local/bin:$HOME/.npm-global/bin:$HOME/bin:$PREFIX/bin:$PATH"
  ```
- **Shebangs**: Every executable installed via npm or shell must have Termux-compatible shebangs (`#!/data/data/com.termux/files/usr/bin/...`). Always run `termux-fix-shebang` on new scripts in `~/.npm-global/bin/` or `~/.local/bin/`.
- **Package Managers**: Keep `pnpm` pinned to the 10.x line (`10.33.4`) for native ARM64 compatibility.

## 3. AI CLI Suite Standards
The project manages 5 primary AI coding assistants:
1. **Google Antigravity (`agy`)**: Native Termux ARM64 binary (`/data/data/com.termux/files/usr/bin/agy`).
2. **OpenCode (`opencode`)**: Termux native ARM64 runner via `opencode-termux`.
3. **OpenAI Codex (`codex`)**: Packaged for Termux ARM64 via `@mmmbuto/codex-cli-termux`.
4. **Google Gemini (`gemini`)**: Official CLI via `@google/gemini-cli`.
5. **GitHub Copilot (`copilot`)**: Linux-arm64 binary bridged with glibc runtime wrapper via `@bash0816/copilot-termux`.

## 4. Android Development & TermuxVoid
- **Repository**: TermuxVoid repository (`deb [arch=all] https://termuxvoid.github.io/repo termuxvoid main`) with `tvpkg`.
- **SDK Path**: `$PREFIX/opt/android-sdk` (build-tools 36.1.0, cmdline-tools 19.0, platforms android-36).
- **NDK Path**: `$PREFIX/opt/android-sdk/ndk/29.0.14206865` with LLVM Clang 21.0.0.
- **Java**: OpenJDK 21 LTS (`$PREFIX/lib/jvm/java-21-openjdk`).
- **Environment**: Configured in `~/.android-env` and loaded by `~/.bashrc` and `~/.zshrc`.
- **Gradle Properties**:
  ```properties
  # In android/gradle.properties
  android.aapt2FromMavenOverride=/data/data/com.termux/files/usr/opt/android-sdk/build-tools/36.1.0/aapt2
  
  # In android/local.properties
  sdk.dir=/data/data/com.termux/files/usr/opt/android-sdk
  ndk.dir=/data/data/com.termux/files/usr/opt/android-sdk/ndk/29.0.14206865
  cmake.dir=/data/data/com.termux/files/usr/opt/android-sdk/cmake/4.1.2
  ```

## 5. Security & Credentials
- Private environment variables and API keys reside in `~/.ai-env` with `600` permissions.
- Never hard-code API tokens or secrets into any scripts or commit them to version control.

## 6. Verification & Testing
- Run `bash setup.sh --verify` to inspect all tools across System, Compilers, Node.js, AI CLIs, and Android toolchains.
- Run `bash test-suite.sh` to execute the full 21-point stress and verification test suite (including functional APK, DEX, and NDK Clang synthesis).

## 7. Antigravity Skills & Customizations
- **`termux-suite`**: General management, verification, lock clearance, and troubleshooting.
- **`termux-android`**: Dedicated workflows for standalone APK builds, AAPT2/D8/apksigner pipelines, NDK C/C++, and Gradle configuration.

