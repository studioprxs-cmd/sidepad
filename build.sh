#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
if [ -n "${PAD_DISPLAY_TOOLCHAIN:-}" ]; then
  pd_java="${JAVA_HOME:-$PAD_DISPLAY_TOOLCHAIN/jdk/jdk-17.0.20.1+1/Contents/Home}"
  pd_bt="$PAD_DISPLAY_TOOLCHAIN/build-tools/android-15"
  pd_platform="$PAD_DISPLAY_TOOLCHAIN/platform/android-35/android.jar"
else
  pd_sdk="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-$HOME/Library/Android/sdk}}"
  pd_java="${JAVA_HOME:-$(/usr/libexec/java_home -v 17)}"
  pd_bt="$pd_sdk/build-tools/${ANDROID_BUILD_TOOLS_VERSION:-35.0.0}"
  pd_platform="$pd_sdk/platforms/android-35/android.jar"
fi
export JAVA_HOME="$pd_java"
export PATH="$JAVA_HOME/bin:$PATH"
for pd_required in "$pd_java/bin/javac" "$pd_bt/aapt2" "$pd_platform"; do
  if [ ! -e "$pd_required" ]; then printf 'Missing build dependency: %s\nSee README.md for setup.\n' "$pd_required" >&2; exit 1; fi
done
pd_out="${PAD_DISPLAY_OUTPUT:-$PWD/build}"
mkdir -p "$pd_out" build/classes build/dex private
chmod 700 private
if [ ! -f private/signing.keystore ]; then
  openssl rand -hex 24 > private/key-password
  chmod 600 private/key-password
  keytool -genkeypair -keystore private/signing.keystore -alias paddisplay -keyalg RSA -keysize 3072 -validity 10000 -storepass:file private/key-password -keypass:file private/key-password -dname 'CN=Pad Display Local'
  chmod 600 private/signing.keystore
fi
"$pd_bt/aapt2" compile --dir android/res -o build/resources.zip
"$pd_bt/aapt2" link -I "$pd_platform" --manifest android/AndroidManifest.xml -o build/base.apk build/resources.zip
javac -source 11 -target 11 -classpath "$pd_platform" -d build/classes android/src/studio/prxs/paddisplay/*.java
find build/classes -name '*.class' > build/classes.list
"$pd_bt/d8" --lib "$pd_platform" --min-api 28 --output build/dex @build/classes.list
cp build/base.apk build/unsigned.apk
(cd build/dex && zip -q ../unsigned.apk classes.dex)
"$pd_bt/zipalign" -f 4 build/unsigned.apk build/aligned.apk
"$pd_bt/apksigner" sign --v4-signing-enabled false --ks private/signing.keystore --ks-key-alias paddisplay --ks-pass file:private/key-password --out "$pd_out/PadDisplay.apk" build/aligned.apk
"$pd_bt/apksigner" verify "$pd_out/PadDisplay.apk"
pd_app="$pd_out/Pad Display.app"
mkdir -p "$pd_app/Contents/MacOS" "$pd_app/Contents/Resources"
clang -fobjc-arc -fmodules -O2 -mmacosx-version-min=14.0 mac/main.m -o "$pd_app/Contents/MacOS/PadDisplay" -framework Cocoa -framework CoreGraphics -framework ScreenCaptureKit -framework VideoToolbox -framework CoreMedia -framework CoreVideo -framework Security -framework ApplicationServices
cp "$pd_out/PadDisplay.apk" "$pd_app/Contents/Resources/PadDisplay.apk"
cp mac/Info.plist "$pd_app/Contents/Info.plist"
cp assets/PadDisplay.icns "$pd_app/Contents/Resources/PadDisplayRounded.icns"
# Keep this local development app's identity stable across rebuilds for TCC.
codesign --force --sign - --identifier studio.prxs.paddisplay.mac --requirements '=designated => identifier "studio.prxs.paddisplay.mac"' "$pd_app"
codesign --verify --strict "$pd_app"
printf 'Built: %s\n' "$pd_app"
