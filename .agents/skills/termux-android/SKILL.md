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

## 3. Minimal Standalone APK Build Pipeline (Zero Gradle Overhead)

For lightweight utilities, tests, or learning, you can build a signed APK without the heavy Gradle overhead:

### Step 1: Prepare Manifest & Resources
```bash
mkdir -p build/{res,src/com/example/app}

cat > build/AndroidManifest.xml <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    package="com.example.app"
    android:versionCode="1"
    android:versionName="1.0">
    <uses-sdk android:minSdkVersion="26" android:targetSdkVersion="36" />
    <application android:label="TermuxApp" android:hasCode="true">
        <activity android:name=".MainActivity" android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>
    </application>
</manifest>
EOF
```

### Step 2: Compile Resources with AAPT2
```bash
aapt2 link \
    -I "$ANDROID_HOME/platforms/android-36/android.jar" \
    --manifest build/AndroidManifest.xml \
    --java build/src \
    -o build/app-unaligned.apk
```

### Step 3: Compile Java Source
```bash
cat > build/src/com/example/app/MainActivity.java <<'EOF'
package com.example.app;
import android.app.Activity;
import android.os.Bundle;
import android.widget.TextView;

public class MainActivity extends Activity {
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        TextView tv = new TextView(this);
        tv.setText("Hello from Termux Native Android!");
        setContentView(tv);
    }
}
EOF

javac -cp "$ANDROID_HOME/platforms/android-36/android.jar" \
    build/src/com/example/app/*.java \
    -d build/classes
```

### Step 4: Convert Bytecode to DEX (`d8`)
```bash
d8 build/classes/com/example/app/*.class \
    --lib "$ANDROID_HOME/platforms/android-36/android.jar" \
    --output build/
```

### Step 5: Package DEX into APK
```bash
cd build
zip -u app-unaligned.apk classes.dex
cd ..
```

### Step 6: Sign APK with `apksigner`
```bash
# Generate a keystore if one doesn't exist
if [ ! -f build/debug.keystore ]; then
    keytool -genkey -v -keystore build/debug.keystore \
        -alias debug -keyalg RSA -keysize 2048 -validity 10000 \
        -storepass android -keypass android \
        -dname "CN=Android Debug,O=Android,C=US"
fi

apksigner sign --ks build/debug.keystore \
    --ks-key-alias debug \
    --ks-pass pass:android \
    --key-pass pass:android \
    --out build/app-signed.apk \
    build/app-unaligned.apk

# Verify signature
apksigner verify build/app-signed.apk
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

1. **AAPT2 Maven Override**: Always ensure `android.aapt2FromMavenOverride` is set in `~/.gradle/gradle.properties`:
   ```properties
   android.aapt2FromMavenOverride=/data/data/com.termux/files/usr/opt/android-sdk/build-tools/36.1.0/aapt2
   android.builder.sdkDownload=false
   org.gradle.jvmargs=-Xmx2048m -XX:+UseG1GC
   ```
2. **Local Properties**: In the project root, ensure `local.properties` specifies paths:
   ```properties
   sdk.dir=/data/data/com.termux/files/usr/opt/android-sdk
   ndk.dir=/data/data/com.termux/files/usr/opt/android-sdk/ndk/29.0.14206865
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
