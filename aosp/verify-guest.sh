#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -lt 1 || "$#" -gt 2 ]]; then
    printf '%s\n' 'Uso: aosp/verify-guest.sh SERIAL_CUTTLEFISH [openvr-demo.apk]' >&2
    exit 2
fi
adb="${OPENVR_ADB:-adb}"
device=("$adb" -s "$1")
apk="${2:-}"
results="${OPENVR_RESULTS:-./results/cuttlefish}"
seconds="${AOSP_BOOT_TIMEOUT:-300}"
if ! command -v "$adb" >/dev/null || [[ ! "$seconds" =~ ^[1-9][0-9]{0,5}$ ]]; then
    printf '%s\n' 'Comprueba OPENVR_ADB y AOSP_BOOT_TIMEOUT.' >&2
    exit 2
fi
if [[ -n "$apk" && ! -r "$apk" ]]; then
    printf 'No se puede leer %s\n' "$apk" >&2
    exit 2
fi
mkdir -p -- "$results"
exec > >(tee "$results/cuttlefish-guest.log") 2>&1

property() {
    timeout 8 "${device[@]}" shell getprop "$1" | tr -d '\r'
}

deadline=$((SECONDS + seconds))
boot=""
while (( SECONDS < deadline )); do
    boot="$(property sys.boot_completed 2>/dev/null || true)"
    [[ "$boot" != 1 ]] || break
    sleep 3
done
[[ "$boot" == 1 ]] || { echo 'El invitado no completó el arranque.' >&2; exit 1; }
name="$(property ro.product.product.name)"
abi="$(property ro.product.cpu.abi)"
printf 'Producto %s · ABI %s\n' "$name" "$abi"
if [[ "$name" != openvr_cf_x86_64_phone || "$abi" != x86_64 ]]; then
    echo 'El serial corresponde a otro producto o ABI.' >&2
    exit 1
fi
trap 'timeout 30 "${device[@]}" logcat -d -v threadtime > "$results/cuttlefish-logcat.txt" 2>&1 || true' EXIT

timeout 15 "${device[@]}" shell pm path org.openvr.launcher | tr -d '\r' | grep '^package:'
home="$(timeout 15 "${device[@]}" shell cmd package resolve-activity --brief \
    --user 0 -a android.intent.action.MAIN -c android.intent.category.HOME | tr -d '\r')"
printf '%s\n' "$home"
if ! grep -Fxq 'org.openvr.launcher/.MainActivity' <<< "$home"; then
    echo 'OpenVR Launcher no resolvió la actividad HOME predeterminada.' >&2
    exit 1
fi
launch="$(timeout 30 "${device[@]}" shell am start -W \
    --user 0 -a android.intent.action.MAIN -c android.intent.category.HOME | tr -d '\r')"
printf '%s\n' "$launch"
grep -Fxq 'Status: ok' <<< "$launch"

if [[ -n "$apk" ]]; then
    timeout 120 "${device[@]}" install -r "$apk"
    demo="$(timeout 30 "${device[@]}" shell am start -W \
        -n org.openvr.demo/.MainActivity | tr -d '\r')"
    printf '%s\n' "$demo"
    grep -Fxq 'Status: ok' <<< "$demo"
fi
printf '%s\n' 'Verificación del invitado Cuttlefish completada.'
