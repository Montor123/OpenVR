#!/usr/bin/env bash
set -Eeuo pipefail

pids=()
cleanup() {
  if (( ${#pids[@]} )); then
    kill "${pids[@]}" 2>/dev/null || true
    wait || true
  fi
}
trap cleanup EXIT
trap 'exit 0' TERM INT

Xvfb "$DISPLAY" -screen 0 1280x800x24 -nolisten tcp &
pids+=("$!")
for (( attempt = 0; attempt < 50; attempt++ )); do
  if xdpyinfo -display "$DISPLAY" >/dev/null 2>&1; then
    break
  fi
  sleep 0.1
done
xdpyinfo -display "$DISPLAY" >/dev/null
openbox &
pids+=("$!")
x11vnc -display "$DISPLAY" -localhost -nopw -forever -shared -rfbport 5900 &
pids+=("$!")
websockify --web /usr/share/novnc 0.0.0.0:6080 127.0.0.1:5900 &
pids+=("$!")
openvr &
pids+=("$!")
wait -n "${pids[@]}"
