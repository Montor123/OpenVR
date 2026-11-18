#!/usr/bin/env bash
set -euo pipefail

ref=android-14.0.0_r75
manifest_tag=c49a52c108f10a64f6122af27fd27f96b8d45424
target=aosp_cf_x86_64_phone-trunk_staging-userdebug
results=${OPENVR_RESULTS:-/data/results}
jobs=${AOSP_JOBS:-8}

case "${1:-help}" in
  sync)
    # Check the annotated manifest tag before allowing repo to fetch the tree.
    remote=$(git ls-remote https://android.googlesource.com/platform/manifest "refs/tags/$ref")
    read -r tag_hash _ <<< "$remote"
    if [[ $tag_hash != "$manifest_tag" ]]; then
      echo "El identificador del manifiesto no coincide con $ref." >&2
      exit 1
    fi
    repo init -u https://android.googlesource.com/platform/manifest -b "refs/tags/$ref" \
      --repo-url=file:///opt/git-repo --repo-rev=v2.54 \
      --partial-clone --no-clone-bundle
    repo sync -c --no-clone-bundle --fail-fast -j "$jobs" 2>&1 | tee "$results/aosp-sync.log"
    repo manifest -r -o "$results/aosp-manifest.xml"
    ;;
  compile)
    test -f build/envsetup.sh || { echo "Ejecuta primero openvr-aosp sync." >&2; exit 1; }
    (
      # envsetup.sh inspects variables that may be unset.
      set +u
      source build/envsetup.sh
      lunch "$target"
      m -j"$jobs"
    ) 2>&1 | tee "$results/aosp-build.log"
    ;;
  help|-h|--help)
    echo "openvr-aosp sync | compile"
    echo "AOSP $ref, objetivo $target. AOSP_JOBS controla los procesos paralelos."
    ;;
  *)
    echo "Subcomando desconocido: $1" >&2
    exit 2
    ;;
esac
