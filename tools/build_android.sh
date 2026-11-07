#!/usr/bin/env bash
#
# Headless Android debug-APK build for Waifu World.
#
# This is the exact recipe that produced build/WaifuWorld.apk on Godot
# 4.3.stable (Linux x86_64), with no graphical editor involved.
#
# Prerequisites (paths below can be overridden with environment variables):
#   ANDROID_HOME  Android SDK containing build-tools/ and platform-tools/
#   JAVA_HOME     JDK 17
#   KEYSTORE      debug keystore (a throwaway one is fine for debug builds)
#
# Usage:
#   ANDROID_HOME=/opt/android-sdk JAVA_HOME=/opt/jdk-17 KEYSTORE=~/debug.keystore \
#     ./tools/build_android.sh [output.apk]
#
set -euo pipefail

GODOT="${GODOT:-godot}"
ANDROID_HOME="${ANDROID_HOME:?set ANDROID_HOME to your Android SDK}"
JAVA_HOME="${JAVA_HOME:?set JAVA_HOME to a JDK 17}"
KEYSTORE="${KEYSTORE:?set KEYSTORE to a debug keystore path}"
OUT="${1:-build/WaifuWorld.apk}"

export JAVA_HOME
# Godot shells out to apksigner, which is a shell script that needs `java`.
export PATH="$JAVA_HOME/bin:$PATH"

# apksigner is a JVM app. In a container with a small memory cgroup the default
# heap reservation fails with "Failed to reserve memory for metaspace" and the
# exporter silently produces an UNSIGNED apk. Cap the heap and it signs fine.
export _JAVA_OPTIONS="${_JAVA_OPTIONS:--Xmx384m -XX:MaxMetaspaceSize=192m -XX:ReservedCodeCacheSize=32m}"

# Godot reads these three from its editor settings, not from the export preset.
SETTINGS="${XDG_CONFIG_HOME:-$HOME/.config}/godot/editor_settings-4.3.tres"
mkdir -p "$(dirname "$SETTINGS")"
touch "$SETTINGS"

set_setting() {
	local key="$1" value="$2"
	if grep -q "^${key} = " "$SETTINGS"; then
		# escape backslashes for sed
		sed -i "s|^${key} = .*|${key} = \"${value//\\/\\\\}\"|" "$SETTINGS"
	else
		printf '%s = "%s"\n' "$key" "$value" >> "$SETTINGS"
	fi
}

set_setting "export/android/android_sdk_path" "$ANDROID_HOME"
set_setting "export/android/java_sdk_path" "$JAVA_HOME"
set_setting "export/android/debug_keystore" "$KEYSTORE"
set_setting "export/android/debug_keystore_user" "androiddebugkey"
set_setting "export/android/debug_keystore_pass" "android"

echo "==> importing project"
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true

echo "==> exporting $OUT"
mkdir -p "$(dirname "$OUT")"
"$GODOT" --headless --path . --export-debug "Android" "$OUT"

echo "==> verifying signature"
APKSIGNER="$(ls -d "$ANDROID_HOME"/build-tools/*/apksigner | sort -V | tail -1)"
"$APKSIGNER" verify --print-certs "$OUT"

echo "==> done: $OUT"
