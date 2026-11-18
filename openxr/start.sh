#!/bin/bash
set -euo pipefail

results=${OPENVR_XR_RESULTS:-/data/results}
mkdir -p "$results"
dpkg-query -W -f='${binary:Package}\t${Version}\n' >"$results/packages.tsv"

export XDG_RUNTIME_DIR
XDG_RUNTIME_DIR=$(mktemp -d)
children=()
cleanup() {
    for ((index = ${#children[@]} - 1; index >= 0; index--)); do
        kill "${children[index]}" 2>/dev/null || true
    done
    wait || true
    rm -rf -- "$XDG_RUNTIME_DIR"
}
trap cleanup EXIT
trap 'exit 143' TERM
trap 'exit 130' INT

Xvfb "$DISPLAY" -screen 0 1440x900x24 -nolisten tcp >"$results/xvfb.log" 2>&1 &
children+=("$!")
for _ in {1..100}; do
    if xdpyinfo >/dev/null 2>&1; then
        break
    fi
    sleep 0.1
done
xdpyinfo >/dev/null

if ! vulkaninfo --summary >"$results/vulkan.log" 2>&1; then
    cat "$results/vulkan.log" >&2
    exit 1
fi
fluxbox >"$results/fluxbox.log" 2>&1 &
children+=("$!")
x11vnc -localhost -rfbport 5901 -forever -shared -nopw -display "$DISPLAY" >"$results/vnc.log" 2>&1 &
children+=("$!")
websockify --web /usr/share/novnc 6081 127.0.0.1:5901 >"$results/novnc.log" 2>&1 &
children+=("$!")

# Monado watches stdin with epoll. A FIFO stays pollable in detached containers.
mkfifo "$XDG_RUNTIME_DIR/monado.stdin"
exec 3<>"$XDG_RUNTIME_DIR/monado.stdin"
monado-service <&3 >"$results/monado.log" 2>&1 &
monado_pid=$!
children+=("$monado_pid")
connected=false
for _ in {1..100}; do
    if ! kill -0 "$monado_pid" 2>/dev/null; then
        cat "$results/monado.log" >&2
        exit 1
    fi
    if find "$XDG_RUNTIME_DIR" -maxdepth 1 -type s -print -quit | grep -q .; then
        connected=true
        break
    fi
    sleep 0.2
done
if [[ "$connected" != true ]]; then
    echo "Monado no abrió su socket. Consulta $results/monado.log." >&2
    exit 1
fi

echo "OpenXR local. Registros en $results"
mkfifo "$XDG_RUNTIME_DIR/hello-xr.stdin"
exec 4<>"$XDG_RUNTIME_DIR/hello-xr.stdin"
stdbuf -oL -eL hello_xr -g Vulkan2 -s Local <&4 >"$results/hello-xr.log" 2>&1 &
sample_pid=$!
children+=("$sample_pid")
wait -n "${children[@]}" || {
    cat "$results/hello-xr.log" "$results/monado.log" >&2
    exit 1
}
