#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/config.sh"

[[ -x "$EMULATOR" && -x "$ADB" && -f "$SYSTEM_IMAGE/system.img" ]] ||
    fail "Falta el SDK o la imagen Android. Ejecuta android/setup.sh --accept después de revisar la licencia."
headless="${ANDROID_HEADLESS:-0}"
if [[ "$headless" != 0 && "$headless" != 1 ]]; then
    fail 'ANDROID_HEADLESS admite 0 o 1.'
fi
if [[ "$headless" == 0 && -z "${DISPLAY:-}" ]]; then
    fail "Falta DISPLAY. Usa el escritorio OpenVR o ANDROID_HEADLESS=1."
fi

mkdir -p -- "$ANDROID_USER_HOME" "$ANDROID_AVD_HOME" "$RESULTS_DIR"
exec 9>"$ANDROID_AVD_HOME/$AVD_NAME.lock"
flock -n 9 || fail "El AVD $AVD_NAME ya está en ejecución."
exec > >(tee "$RESULTS_DIR/android-emulator.log") 2>&1

if [[ "${ANDROID_ACCEL:-auto}" == software ]]; then
    acceleration=off
elif [[ "${ANDROID_ACCEL:-auto}" == auto || "${ANDROID_ACCEL:-auto}" == kvm ]]; then
    if [[ -r /dev/kvm && -w /dev/kvm ]] && "$EMULATOR" -accel-check; then
        acceleration=on
    elif [[ "${ANDROID_ACCEL:-auto}" == kvm ]]; then
        fail 'KVM solicitado y no utilizable en este contenedor.'
    else
        acceleration=off
    fi
else
    fail 'ANDROID_ACCEL admite auto, kvm o software.'
fi
printf 'Emulador %s · aceleración CPU %s · gráficos SwiftShader\n' "$SERIAL" "$acceleration"

avd="$ANDROID_AVD_HOME/$AVD_NAME.avd"
mkdir -p -- "$avd"
cat > "$ANDROID_AVD_HOME/$AVD_NAME.ini" <<AVD
avd.ini.encoding=UTF-8
path=$avd
target=android-34
AVD
cat > "$avd/config.ini" <<CONFIG
AvdId=$AVD_NAME
avd.ini.displayname=OpenVR Android 14
avd.ini.encoding=UTF-8
abi.type=x86_64
tag.id=default
tag.display=Default
image.sysdir.1=$SYSTEM_REL/
hw.cpu.arch=x86_64
hw.cpu.ncore=2
hw.ramSize=2048
hw.gpu.enabled=yes
hw.gpu.mode=swiftshader
hw.lcd.width=540
hw.lcd.height=960
hw.lcd.density=240
hw.keyboard=yes
hw.mainKeys=no
hw.dPad=no
hw.trackBall=no
hw.sdCard=no
disk.dataPartition.size=2G
PlayStore.enabled=false
showDeviceFrame=no
CONFIG

"$ADB" start-server 9>&-
window_args=()
if [[ "$headless" == 1 ]]; then
    window_args=(-no-window)
fi
exec "$EMULATOR" -avd "$AVD_NAME" -port "$EMULATOR_PORT" -accel "$acceleration" -gpu swiftshader \
    -no-boot-anim -no-snapshot -no-audio -camera-back none -camera-front none "${window_args[@]}"
