#!/usr/bin/env bash
# Common paths for the Android lab.
ANDROID_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ANDROID_DATA="${OPENVR_ANDROID_DATA:-/data/android}"
export ANDROID_HOME="${ANDROID_HOME:-$ANDROID_DATA/sdk}"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export ANDROID_USER_HOME="${ANDROID_USER_HOME:-$ANDROID_DATA/user}"
export ANDROID_EMULATOR_HOME="${ANDROID_EMULATOR_HOME:-$ANDROID_USER_HOME}"
export ANDROID_AVD_HOME="${ANDROID_AVD_HOME:-$ANDROID_DATA/avd}"
RESULTS_DIR="${OPENVR_RESULTS_DIR:-/data/results}"
APK_PATH="${OPENVR_APK_PATH:-$RESULTS_DIR/openvr-demo.apk}"
ADB="$ANDROID_HOME/platform-tools/adb"
EMULATOR="$ANDROID_HOME/emulator/emulator"
SYSTEM_REL="system-images/android-34/default/x86_64"
SYSTEM_IMAGE="$ANDROID_HOME/$SYSTEM_REL"
AVD_NAME="openvr_api34"
EMULATOR_PORT=5554
SERIAL="emulator-$EMULATOR_PORT"
ACTIVITY="org.openvr.demo/.MainActivity"

fail() {
    printf '%s\n' "$*" >&2
    exit 1
}
