#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/config.sh"

if [[ "$*" != "--accept" ]]; then
    cat >&2 <<'EOF'
El emulador, ADB y la imagen Android se descargan de Google.
Revisa la licencia del SDK en https://developer.android.com/studio/terms
Si la aceptas, ejecuta android/setup.sh --accept.
EOF
    exit 2
fi
[[ "$(uname -s):$(uname -m)" == "Linux:x86_64" ]] || fail "Usa un entorno Linux amd64."
for command in curl unzip sha1sum flock; do
    command -v "$command" > /dev/null || fail "Falta $command. Usa el entorno dev de OpenVR."
done

mkdir -p -- "$ANDROID_DATA/downloads" "$RESULTS_DIR" "$ANDROID_HOME"
exec 9>"$ANDROID_DATA/sdk-setup.lock"
flock 9
exec > >(tee "$RESULTS_DIR/android-setup.log") 2>&1
scratch=""
partial=""
cleanup() {
    [[ -z "$scratch" ]] || rm -rf -- "$scratch"
    [[ -z "$partial" ]] || rm -f -- "$partial"
}
trap cleanup EXIT

install_archive() {
    local url="$1" checksum="$2" bytes="$3" destination="$4" required="$5"
    local cache="$ANDROID_DATA/downloads/${1##*/}" payload candidate
    if [[ -f "$destination/$required" && -f "$destination/.openvr-archive-sha1" ]] &&
        [[ "$(cat -- "$destination/.openvr-archive-sha1")" == "$checksum" ]]; then
        printf 'Disponible: %s\n' "$destination"
        return
    fi
    [[ ! -e "$destination" ]] || fail "Ruta ocupada: $destination. Usa un ANDROID_HOME dedicado."
    if [[ ! -f "$cache" ]] || ! printf '%s  %s\n' "$checksum" "$cache" | sha1sum --check --status; then
        partial="$(mktemp "$ANDROID_DATA/downloads/.sdk.XXXXXXXX")"
        printf 'Descargando %s (%s bytes)\n' "$url" "$bytes"
        curl --fail --silent --show-error --location --retry 2 --output "$partial" "$url"
        [[ "$(wc -c < "$partial")" -eq "$bytes" ]] || fail "Tamaño inesperado para $url"
        printf '%s  %s\n' "$checksum" "$partial" | sha1sum --check
        mv -- "$partial" "$cache"
        partial=""
    fi

    mkdir -p -- "$(dirname -- "$destination")"
    scratch="$(mktemp -d "$(dirname -- "$destination")/.extract.XXXXXXXX")"
    unzip -q -- "$cache" -d "$scratch"
    payload="$scratch"
    if [[ ! -f "$payload/$required" ]]; then
        for candidate in "$scratch"/*; do
            if [[ -f "$candidate/$required" ]]; then
                payload="$candidate"
                break
            fi
        done
    fi
    [[ -f "$payload/$required" ]] || fail "Estructura inesperada para $url"
    printf '%s\n' "$checksum" > "$payload/.openvr-archive-sha1"
    mv -- "$payload" "$destination"
    rm -rf -- "$scratch"
    scratch=""
}

origin="https://dl.google.com/android/repository"
# Revisión estable para Linux x86_64 de los catálogos oficiales de Google.
install_archive "$origin/platform-tools_r37.0.1-linux.zip" \
    477254aa5f903c15cf51001717bdf347fb6b53e0 9054187 "$ANDROID_HOME/platform-tools" adb
install_archive "$origin/emulator-linux_x64-16740729.zip" \
    f41f9e31eb5ca64926603c03265c50bbc0ff4172 349658551 "$ANDROID_HOME/emulator" emulator
install_archive "$origin/sys-img/android/x86_64-34_r04.zip" \
    5f6a249f9bc3b1b4c459b13ce2eb646c9680bed1 720747116 "$SYSTEM_IMAGE" system.img

"$ADB" version
"$EMULATOR" -version
