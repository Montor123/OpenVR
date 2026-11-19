#!/usr/bin/env bash
set -euo pipefail

here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$here/host-resources.sh"
serial=127.0.0.1:6520
boot_timeout="${AOSP_BOOT_TIMEOUT:-300}"
mode="${1:-help}"

fail() {
    printf '%s\n' "$*" >&2
    exit 1
}

check_run_path() {
    # The r75 stop fallback passes run directories through a shell command.
    [[ "$run" =~ ^/[[:alnum:]_./-]+$ ]] ||
        fail 'El directorio de ejecución de Cuttlefish r75 admite letras, números, puntos, guiones y barras.'
}

check_host() {
    [[ "$(uname -s):$(uname -m)" == Linux:x86_64 ]] || fail 'Cuttlefish requiere un anfitrión Linux x86_64.'
    (( EUID != 0 )) || fail 'Ejecuta Cuttlefish como usuario de Linux sin privilegios de root.'
    openvr_resources "$1"
    python3 - <<'PY'
import fcntl
import os
import sys

# KVM_GET_API_VERSION and KVM_CREATE_VM from Linux uapi/linux/kvm.h.
try:
    with open("/dev/kvm", "r+b", buffering=0) as device:
        if fcntl.ioctl(device, 0xAE00, 0) != 12:
            raise OSError("versión API de KVM inesperada")
        os.close(fcntl.ioctl(device, 0xAE01, 0))
except OSError as error:
    sys.exit(f"KVM no utilizable: {error}")
PY
    (( openvr_memory_kib >= 4 * 1024 * 1024 )) || fail 'OpenVR requiere 4 GiB de RAM disponibles para el invitado y el anfitrión.'
    printf '%s\n' 'KVM responde y permite crear máquinas virtuales.'
}

check_ports() {
    python3 - <<'PY'
import socket
import sys

for port in (6520, 8443):
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as endpoint:
            endpoint.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            endpoint.bind(("0.0.0.0", port))
    except OSError as error:
        sys.exit(f"El puerto {port} de Cuttlefish no está disponible: {error}")
PY
}

guest_env() (
    cd -- "$run"
    unset CUTTLEFISH_CONFIG_FILE
    export HOME="$run" ANDROID_HOST_OUT="$run" ANDROID_PRODUCT_OUT="$run/images"
    "$@"
)

stop_guest() {
    check_run_path
    [[ -f "$run/.openvr-run" && "$(cat -- "$run/.openvr-run")" == openvr-cuttlefish-r75 ]] ||
        fail 'El directorio no corresponde a una ejecución OpenVR preparada.'
    guest_env timeout --kill-after=5 25 "$run/bin/stop_cvd" --wait_for_launcher=5 \
        2>&1 | tee "$run/cuttlefish-stop.log"
}

case "$mode" in
    help|-h|--help)
        printf '%s\n' 'aosp/launch-guest.sh BUNDLE_DIR RUN_DIR' \
            'aosp/launch-guest.sh --check-bundle BUNDLE_DIR' \
            'aosp/launch-guest.sh --check-host [DIRECTORIO]' \
            'aosp/launch-guest.sh --stop RUN_DIR'
        exit
        ;;
    --check-bundle)
        [[ "$#" -eq 2 ]] || fail 'Indica el directorio del export.'
        exec python3 "$here/prepare-guest.py" "$2"
        ;;
    --check-host)
        [[ "$#" -le 2 ]] || fail 'Indica un único directorio para medir el espacio disponible.'
        check_host "${2:-.}"
        exit
        ;;
    --stop)
        [[ "$#" -eq 2 ]] || fail 'Indica el directorio de la ejecución.'
        run="$(cd -- "$2" && pwd -P)"
        stop_guest
        exit
        ;;
    --*) fail 'Usa aosp/launch-guest.sh --help.' ;;
esac

[[ "$#" -eq 2 && "$boot_timeout" =~ ^[1-9][0-9]{0,5}$ ]] ||
    fail 'Indica BUNDLE_DIR y RUN_DIR. AOSP_BOOT_TIMEOUT admite segundos enteros positivos.'
bundle="$(cd -- "$1" && pwd -P)"
parent="$(cd -- "$(dirname -- "$2")" && pwd -P)"
run="$parent/$(basename -- "$2")"
check_run_path
[[ ! -e "$run" && ! -L "$run" ]] || fail "RUN_DIR debe ser una ruta nueva: $run"
check_host "$parent"
check_ports
python3 "$here/prepare-guest.py" "$bundle" "$run"
check_ports
printf 'Registro de arranque: %s/cuttlefish-launch.log\n' "$run"

launch_started=1
cleanup_failed_launch() {
    if (( launch_started == 1 )); then
        stop_guest || true
    fi
}
trap cleanup_failed_launch EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
deadline=$((SECONDS + boot_timeout))
guest_env timeout --kill-after=10 "$boot_timeout" "$run/bin/launch_cvd" \
    --daemon=true --base_instance_num=1 --num_instances=1 --cpus=2 --memory_mb=3072 \
    --system_image_dir="$run/images" --gpu_mode=guest_swiftshader \
    --start_webrtc=true --start_webrtc_sig_server=true \
    --adb_mode=vsock_half_tunnel --run_adb_connector=false \
    --report_anonymous_usage_stats=n 2>&1 | tee "$run/cuttlefish-launch.log"

# Select the local endpoint explicitly. The auto connector uses 0.0.0.0 in r75.
unset ADB_SERVER_SOCKET ANDROID_ADB_SERVER_ADDRESS ANDROID_ADB_SERVER_PORT
adb="$run/bin/adb"
guest=("$adb" -s "$serial")
boot=""
while (( SECONDS < deadline )); do
    remaining=$((deadline - SECONDS))
    limit=$((remaining < 5 ? remaining : 5))
    timeout "$limit" "$adb" connect "$serial" >> "$run/cuttlefish-launch.log" 2>&1 || true
    remaining=$((deadline - SECONDS))
    (( remaining > 0 )) || break
    limit=$((remaining < 5 ? remaining : 5))
    boot="$(timeout "$limit" "${guest[@]}" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r' || true)"
    [[ "$boot" != 1 ]] || break
    sleep 1
done
[[ "$boot" == 1 ]] || fail 'El invitado no completó el arranque dentro del plazo.'
name="$(timeout 5 "${guest[@]}" shell getprop ro.product.product.name | tr -d '\r')"
abi="$(timeout 5 "${guest[@]}" shell getprop ro.product.cpu.abi | tr -d '\r')"
[[ "$name" == openvr_cf_x86_64_phone && "$abi" == x86_64 ]] ||
    fail "El invitado no tiene la identidad esperada: $name / $abi"
launch_started=0
printf 'ADB: %s · producto: %s · ABI: %s\n' "$serial" "$name" "$abi"
printf '%s\n' 'WebRTC configurado en https://localhost:8443'
printf 'Verificación: OPENVR_ADB=%q %q %q\n' "$adb" "$here/verify-guest.sh" "$serial"
