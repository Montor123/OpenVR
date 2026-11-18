#!/usr/bin/env bash
set -euo pipefail

ref=android-14.0.0_r75
manifest_tag=c49a52c108f10a64f6122af27fd27f96b8d45424
manifest_commit=e3b1a5113daede938922ed29c36806e0aac2ecb3
manifest_url=https://android.googlesource.com/platform/manifest
product=openvr_cf_x86_64_phone
target="$product-trunk_staging-userdebug"
reference_target=aosp_cf_x86_64_phone-trunk_staging-userdebug
results="${OPENVR_RESULTS:-/data/results}"
jobs="${AOSP_JOBS:-8}"
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

fail() {
    printf '%s\n' "$*" >&2
    exit 1
}

stage_product() {
    local overlay="${OPENVR_AOSP_OVERLAY:-/opt/openvr/aosp}"
    local destination=device/openvr/lab
    if [[ ! -d "$overlay" && -z "${OPENVR_AOSP_OVERLAY:-}" ]]; then
        overlay="$script_dir"
    fi
    [[ -f "$overlay/product/AndroidProducts.mk" && -f "$overlay/launcher/Android.bp" ]] ||
        fail "Faltan el producto o el lanzador en $overlay."
    [[ -f device/google/cuttlefish/vsoc_x86_64/phone/aosp_cf.mk ]] ||
        fail 'Falta el producto base de Cuttlefish. Ejecuta openvr-aosp sync.'
    if [[ -L device/openvr || -L "$destination" || -L "$destination/launcher" ||
        -L "$destination/.openvr-generated" ||
        ( -e "$destination" && ! -f "$destination/.openvr-generated" ) ]]; then
        fail "El árbol $destination ya está ocupado por contenido externo."
    fi
    mkdir -p -- "$destination"
    printf '%s\n' 'Producto generado por openvr-aosp stage' > "$destination/.openvr-generated"
    rsync -a --delete --exclude='/.openvr-generated' --exclude='/launcher/' -- \
        "$overlay/product/" "$destination/"
    rsync -a --delete -- "$overlay/launcher/" "$destination/launcher/"
    printf 'Producto preparado en %s\n' "$destination"
}

build_product() (
    local lunch_target="$1" mode="$2"
    export OUT_DIR="$3"
    # envsetup.sh inspects variables that may be unset.
    set +u
    source build/envsetup.sh
    lunch "$lunch_target"
    if [[ "$mode" != export ]]; then
        m -j"$jobs" droid
        exit
    fi

    m -j"$jobs" droid updatepackage hosttar
    guest="$ANDROID_PRODUCT_OUT/$product-img.zip"
    host="$ANDROID_HOST_OUT/cvd-host_package.tar.gz"
    [[ -s "$guest" && -s "$host" ]] || fail "No se encontraron ambos artefactos Cuttlefish: $guest y $host."
    bundle="$(mktemp -d "$results/openvr-cuttlefish.XXXXXXXX")"
    cp -- "$guest" "$host" "$bundle/"
    (
        cd -- "$bundle"
        sha256sum -- "${guest##*/}" "${host##*/}" > SHA256SUMS
        stat -c '%s %n' -- "${guest##*/}" "${host##*/}" > SIZE-BYTES
        printf '%s\n' "$ref" "$manifest_commit" "$lunch_target" > BUILD-INFO
    )
    if [[ -s "$results/aosp-manifest.xml" ]]; then
        cp -- "$results/aosp-manifest.xml" "$bundle/"
    fi
    printf 'Archivos de Cuttlefish: %s\n' "$bundle"
)

action="${1:-help}"
case "$action" in
    help|-h|--help)
        printf '%s\n' 'openvr-aosp sync | stage | compile | compile-reference | export' \
            "AOSP $ref, objetivo $target. AOSP_JOBS fija los trabajos en paralelo."
        exit
        ;;
    sync|stage|compile|compile-reference|export) ;;
    *) fail "Subcomando desconocido: $action" ;;
esac
[[ "$#" -eq 1 ]] || fail 'Usa openvr-aosp help.'
[[ "$jobs" =~ ^[1-9][0-9]*$ ]] || fail 'AOSP_JOBS debe ser un entero positivo.'

if [[ -n "${OPENVR_AOSP_ROOT:-}" ]]; then
    cd -- "$OPENVR_AOSP_ROOT"
fi
mkdir -p -- "$results"
results="$(cd -- "$results" && pwd)"
exec 9>".openvr-aosp.lock"
flock -n 9 || fail 'El árbol AOSP ya está en uso.'

if [[ "$action" == sync ]]; then
    remote="$(git ls-remote --exit-code "$manifest_url" "refs/tags/$ref" "refs/tags/$ref^{}")"
    if ! grep -Fxq "$manifest_tag"$'\t'"refs/tags/$ref" <<< "$remote" ||
        ! grep -Fxq "$manifest_commit"$'\t'"refs/tags/$ref^{}" <<< "$remote"; then
        fail "El identificador del manifiesto no coincide con $ref."
    fi
    repo init -u "$manifest_url" -b "refs/tags/$ref" \
        --repo-url=file:///opt/git-repo --repo-rev=v2.54 \
        --partial-clone --no-clone-bundle
    repo sync -c --no-clone-bundle --fail-fast -j "$jobs" 2>&1 | tee "$results/aosp-sync.log"
    repo manifest -r -o "$results/aosp-manifest.xml"
    exit
fi

[[ -f build/envsetup.sh ]] || fail 'Primero ejecuta openvr-aosp sync.'
if [[ -d .repo/manifests ]]; then
    [[ "$(git -C .repo/manifests rev-parse HEAD)" == "$manifest_commit" ]] ||
        fail "El árbol no usa el manifiesto fijado en $ref."
fi

case "$action" in
    stage)
        stage_product
        ;;
    compile|export)
        stage_product
        build_product "$target" "$action" "${AOSP_OUT_DIR:-out-openvr}" 2>&1 |
            tee "$results/aosp-$action.log"
        ;;
    compile-reference)
        build_product "$reference_target" compile "${AOSP_REFERENCE_OUT_DIR:-out-reference}" 2>&1 |
            tee "$results/aosp-reference.log"
        ;;
esac
