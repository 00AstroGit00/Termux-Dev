---
name: termux-android
description: >-
  Use this skill when developing, building, compiling, or debugging Android applications and native NDK C/C++ libraries within Termux.
---

# Android Development & Toolchain Guide (Termux ARM64)

This skill provides step-by-step procedures for building Android applications and native libraries directly on an Android device using the Termux developer workstation.

---

## 1. Toolchain Quick Reference

Tool | Path / Command | Description
:--- | :--- | :---
**Java JDK** | `java`, `javac` | OpenJDK 21 LTS (`$JAVA_HOME`)
**Build System** | `gradle` | Gradle 9.x build automation
**Android SDK** | `$ANDROID_HOME` | SDK 36.1.0 (`/data/data/com.termux/files/usr/opt/android-sdk`)
**Platform API** | `$ANDROID_HOME/platforms/android-36/android.jar` | Android 16 (API level 36)
**Asset Packager** | `aapt2` | Resource compiler & APK packager
**Dexer** | `d8` | Bytecode to Dalvik DEX converter
**APK Signer** | `apksigner` | APK v2/v3/v4 cryptographic signer
**Package Manager** | `tvpkg` | TermuxVoid package manager for SDK/NDK
**Native Compiler** | `$ANDROID_NDK_ROOT/toolchains/llvm/prebuilt/linux-arm64/bin/clang` | NDK Clang 21.0.0
**Native C++** | `$ANDROID_NDK_ROOT/toolchains/llvm/prebuilt/linux-arm64/bin/clang++` | NDK Clang++ 21.0.0
**CMake / Ninja** | `cmake`, `ninja` | Native build generators

---

## 2. Environment Activation

Ensure the Android environment is loaded in the current shell session:
```bash
[[ -f "$HOME/.android-env" ]] && source "$HOME/.android-env"
```

Verify toolchain visibility:
```bash
echo "SDK: $ANDROID_HOME"
echo "NDK: $ANDROID_NDK_ROOT"
java -version
aapt2 version
gradle --version
```

---

## 3. Fast Standalone APK Build Pipeline (Zero Gradle Overhead)

### Method A: Automated Zero-Gradle Builder (`termux-apk-build`) - Recommended
`termux-apk-build` executes the entire resource linking, Java compilation, DEX conversion, 16KB zipalign, and cryptographic signing pipeline in **< 1 second**:

```bash
# Auto-detect Android Studio / Gradle project structure:
termux-apk-build -p /path/to/project -o app-signed.apk

# With external JAR dependencies and direct ADB device installation:
termux-apk-build -p /path/to/project -j libs/ -i -o app-signed.apk

# Or specify custom components directly:
termux-apk-build -m AndroidManifest.xml -s src/ -r res/ -l lib/ -j libs/ -i -o app-signed.apk
```

Features:
- Sub-second build speed with 0 MB background JVM memory footprint.
- Full multi-DEX support (`classes*.dex`) and external `.jar` bytecode compilation.
- Bundles uncompressed native libraries (`.so`) for Android 15+ direct `mmap()`.
- Enforces strict 16KB page-boundary alignment (`zipalign -P 16 -f 4`).
- Direct on-device installation and app launching via ADB (`-i, --install`).
- Signs with v1, v2, and v3 APK Signature Schemes.

---

### Method B: Manual Underlying Step-by-Step Pipeline
For learning or custom pipeline control:

```bash
mkdir -p build/{res,src/com/example/app}

# 1. Manifest
cat > build/AndroidManifest.xml <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="com.example.app">
    <application android:label="TermuxApp" android:extractNativeLibs="false">
        <activity android:name=".MainActivity" android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>
    </application>
</manifest>
EOF

# 2. Compile resources with AAPT2
aapt2 link -I "$ANDROID_HOME/platforms/android-36/android.jar" \
    --manifest build/AndroidManifest.xml \
    --java build/src \
    -o build/app-unaligned.apk

# 3. Compile Java source
javac -cp "$ANDROID_HOME/platforms/android-36/android.jar" \
    build/src/com/example/app/*.java -d build/classes

# 4. Convert bytecode to Dalvik DEX (d8)
d8 build/classes/com/example/app/*.class \
    --lib "$ANDROID_HOME/platforms/android-36/android.jar" \
    --output build/

# 5. Package DEX into APK
(cd build && zip -uq app-unaligned.apk classes*.dex)

# 6. Page-align APK for Android 15/16 (16KB alignment)
zipalign -P 16 -f 4 build/app-unaligned.apk build/app-aligned.apk

# 7. Sign APK with apksigner (must be executed AFTER zipalign!)
apksigner sign --ks "$HOME/.android/debug.keystore" \
    --ks-key-alias debug \
    --ks-pass pass:android \
    --key-pass pass:android \
    --out build/app-signed.apk \
    build/app-aligned.apk

# 8. Verify signatures and alignment
apksigner verify -v build/app-signed.apk
zipalign -c -P 16 4 build/app-signed.apk
```

---

## 4. Native C/C++ Development with Android NDK

The Android NDK LLVM Clang toolchain is located at:
`$ANDROID_NDK_ROOT/toolchains/llvm/prebuilt/linux-arm64/bin/`

### Direct Native C Compilation
Compile a native Android ELF binary:
```bash
$ANDROID_NDK_ROOT/toolchains/llvm/prebuilt/linux-arm64/bin/clang \
    --target=aarch64-linux-android34 \
    -O2 -Wall \
    main.c -o my_native_bin
```

### Direct Native C++ Compilation
```bash
$ANDROID_NDK_ROOT/toolchains/llvm/prebuilt/linux-arm64/bin/clang++ \
    --target=aarch64-linux-android34 \
    -std=c++20 -static-libstdc++ \
    main.cpp -o my_native_cpp_bin
```

### CMake with NDK Toolchain
To build CMake projects with the NDK toolchain:
```bash
cmake -B build \
    -DCMAKE_TOOLCHAIN_FILE="$ANDROID_NDK_ROOT/build/cmake/android.toolchain.cmake" \
    -DANDROID_ABI=arm64-v8a \
    -DANDROID_PLATFORM=android-34 \
    -GNinja
ninja -C build
```

---

## 5. Gradle Project Development Rules

When building existing Gradle projects on Termux:

1. **AAPT2 Maven Override & Mobile Memory Tuning**: Always ensure `android.aapt2FromMavenOverride` and memory guards are set in `~/.gradle/gradle.properties`:
   ```properties
   android.aapt2FromMavenOverride=/data/data/com.termux/files/usr/opt/android-sdk/build-tools/36.1.0/aapt2
   android.builder.sdkDownload=false
   org.gradle.vfs.watch=false
   org.gradle.parallel=true
   org.gradle.jvmargs=-Xmx1280m -XX:+UseG1GC -XX:MaxMetaspaceSize=384m
   org.gradle.daemon.idletimeout=60000
   ```
2. **Local Properties**: In the project root, ensure `local.properties` specifies paths:
   ```properties
   sdk.dir=/data/data/com.termux/files/usr/opt/android-sdk
   ndk.dir=/data/data/com.termux/files/usr/opt/android-sdk/ndk/29.0.14206865
   cmake.dir=/data/data/com.termux/files/usr/opt/android-sdk/cmake/4.1.2
   ```
3. **Run Builds**:
   ```bash
   gradle assembleDebug --no-daemon
   ```

---

## 6. On-Device Testing & Debugging (ADB)

Termux can communicate directly with the local device or external devices using ADB:
```bash
# Connect to Android 11+ Wireless Debugging
adb connect <IP>:<PORT>

# List devices
adb devices

# Install freshly built APK
adb install -r build/app-signed.apk

# View logcat output
adb logcat -v time *:E
```

---

## 7. Google Android CLI (`android`)

The official Google Android CLI (`~/.local/bin/android`) is pre-bridged via `termux-glibc`:
```bash
# Display SDK info and environment status
android info

# Generate new Android projects from official templates
android create

# Inspect project layout and artifacts
android describe
```
