#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/config.sh"

[[ -x "$ADB" ]] || fail "ADB no está instalado. Consulta android/README.md."
boot_timeout="${ANDROID_BOOT_TIMEOUT:-900}"
[[ "$boot_timeout" =~ ^[1-9][0-9]{0,5}$ ]] || fail "ANDROID_BOOT_TIMEOUT debe indicar segundos enteros positivos."
if [[ ! -f "$APK_PATH" ]]; then
    "$ANDROID_DIR/build-apk.sh"
fi

mkdir -p -- "$RESULTS_DIR"
exec 9>"$RESULTS_DIR/android-smoke.lock"
flock -n 9 || fail 'Ya hay otra prueba Android en ejecución.'
exec > >(tee "$RESULTS_DIR/android-smoke.log") 2>&1
rm -f -- "$RESULTS_DIR/android-smoke.png"
adb_device=("$ADB" -s "$SERIAL")
save_logcat() {
    timeout 30 "${adb_device[@]}" logcat -d -v threadtime > "$RESULTS_DIR/android-logcat.txt" 2>&1 || true
}
trap save_logcat EXIT

"$ADB" version
printf 'Esperando arranque de %s (máximo %s segundos).\n' "$SERIAL" "$boot_timeout"
deadline=$((SECONDS + boot_timeout))
while (( SECONDS < deadline )); do
    booted="$(timeout 5 "${adb_device[@]}" shell getprop sys.boot_completed 2>/dev/null || true)"
    if [[ "${booted//$'\r'/}" == 1 ]]; then
        break
    fi
    sleep 3
done
[[ "${booted:-}" == 1 || "${booted:-}" == $'1\r' ]] ||
    fail "El arranque no terminó. Consulta $RESULTS_DIR/android-emulator.log."

for property in ro.build.fingerprint ro.build.version.sdk ro.product.cpu.abi; do
    printf '%s=' "$property"
    timeout 10 "${adb_device[@]}" shell getprop "$property"
done
sha256sum "$APK_PATH"
timeout 120 "${adb_device[@]}" install -r "$APK_PATH"
timeout 15 "${adb_device[@]}" shell pm path org.openvr.demo | tr -d '\r' | grep '^package:'
timeout 15 "${adb_device[@]}" shell wm dismiss-keyguard
launch="$(timeout 60 "${adb_device[@]}" shell am start -W -S -n "$ACTIVITY" | tr -d '\r')"
printf '%s\n' "$launch"
grep -qx 'Status: ok' <<< "$launch" || fail 'Android no confirmó el arranque de la actividad.'

pid="$(timeout 10 "${adb_device[@]}" shell pidof -s org.openvr.demo | tr -d '\r')"
[[ "$pid" =~ ^[0-9]+$ ]] || fail 'No se encontró el proceso de la aplicación.'
ready="$(timeout 15 "${adb_device[@]}" logcat -d --pid="$pid" -s OpenVRDemo:I)"
grep 'APP_READY' <<< "$ready" || fail 'Falta el marcador APP_READY en logcat.'

screenshot="$(mktemp "$RESULTS_DIR/.android-smoke.XXXXXXXX")"
trap 'rm -f -- "$screenshot"; save_logcat' EXIT
timeout 30 "${adb_device[@]}" exec-out screencap -p > "$screenshot"
[[ "$(od -An -tx1 -N8 "$screenshot" | tr -d '[:space:]')" == 89504e470d0a1a0a ]] ||
    fail 'La captura Android no contiene un PNG.'
mv -- "$screenshot" "$RESULTS_DIR/android-smoke.png"
printf 'Prueba Android completada. Captura: %s/android-smoke.png\n' "$RESULTS_DIR"
