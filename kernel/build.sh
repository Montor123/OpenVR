#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C TZ=UTC

source "$(dirname -- "${BASH_SOURCE[0]}")/sources.sh"

usage() {
  echo "openvr-kernel fetch-source | fetch-tools | merge | config | dtbs | compile"
  echo "Compila fuera del visor y guarda resultados de diagnóstico. Consulta kernel/README.md."
}

case "${1:-help}" in
  help|-h|--help) usage; exit 0 ;;
  fetch-source|fetch-tools|merge|config|dtbs|compile) command=$1 ;;
  *) usage >&2; exit 2 ;;
esac

die() {
  printf '%s\n' "$*" >&2
  exit 1
}

[[ $# == 1 ]] || die "Se requiere un único subcomando."
jobs=${KERNEL_JOBS:-2}
[[ $jobs =~ ^[1-9][0-9]*$ ]] || die "KERNEL_JOBS debe ser un entero positivo."

work=${KERNEL_WORK_DIR:-/data/kernel}
report=${OPENVR_RESULTS:-/data/results}
mkdir -p -- "$work" "$report"
work=$(realpath -- "$work")
report=$(realpath -- "$report")
# Some upstream audio headers use relative links into kernel/qcom/kona.
src="$work/kernel/qcom/kona"
out=$(realpath -m -- "${KERNEL_OUT_DIR:-$work/out}")
clang="$work/clang"
gcc="$work/gcc"

exec 9>"$work/.openvr.lock"
flock 9
temporary=
trap 'if [[ -n $temporary ]]; then rm -rf -- "$temporary"; fi' EXIT

verify_source() {
  local actual changes
  actual=$(git -C "$src" rev-parse HEAD 2>/dev/null) || die "Descarga el kernel con fetch-source."
  [[ $actual == "$kernel_commit" ]] || die "Commit inesperado en $src: $actual."
  changes=$(git -C "$src" status --porcelain --untracked-files=no)
  [[ -z $changes ]] || die "El código fijado contiene cambios locales en archivos versionados."
}

fetch_source() {
  if [[ -e $src ]]; then
    verify_source
    echo "Kernel ya disponible en $src."
    return
  fi
  mkdir -p -- "$(dirname -- "$src")"
  temporary=$(mktemp -d "$work/.linux.XXXXXX")
  git -C "$temporary" init --quiet --template=
  git -C "$temporary" -c fetch.fsckObjects=true fetch --depth=1 --no-tags "$kernel_url" "$kernel_commit"
  git -C "$temporary" -c advice.detachedHead=false checkout --quiet --detach FETCH_HEAD
  [[ $(git -C "$temporary" rev-parse HEAD) == "$kernel_commit" ]] || die "La descarga del kernel no coincide."
  mv -T -- "$temporary" "$src"
  temporary=
  echo "Kernel disponible en $src."
}

fetch_archive() {
  local name=$1 url=$2 revision=$3
  local destination="$work/$name"
  if [[ -e $destination ]]; then
    [[ -f $destination/.openvr-source && $(<"$destination/.openvr-source") == "$revision" ]] ||
      die "El toolchain $destination no tiene la procedencia esperada."
    echo "Toolchain ya disponible en $destination."
    return
  fi
  temporary=$(mktemp -d "$work/.$name.XXXXXX")
  curl --fail --silent --show-error --location --connect-timeout 20 "$url" |
    tar --extract --gzip --directory "$temporary" --no-same-owner
  printf '%s\n' "$revision" > "$temporary/.openvr-source"
  mv -T -- "$temporary" "$destination"
  temporary=
}

merge_config() {
  verify_source
  mkdir -p "$out"
  local configs="$src/arch/arm64/configs/vendor"
  (
    cd -- "$out"
    KCONFIG_CONFIG="$out/hollywood.config.in" "$src/scripts/kconfig/merge_config.sh" -m -O "$out" \
      "$configs/oculus_kona_defconfig" "$configs/oculus_hollywood_defconfig"
  )
  install -m 0644 -- "$out/hollywood.config.in" "$report/hollywood.config.in"
  printf 'kernel=%s\n' "$kernel_commit" > "$report/hollywood-source.txt"
}

configure_toolchain() {
  local program
  [[ $(uname -sm) == 'Linux x86_64' ]] || die "Los compiladores fijados requieren Linux x86_64."
  [[ -f $clang/.openvr-source && $(<"$clang/.openvr-source") == "$clang_commit/$clang_release" ]] ||
    die "Falta Clang fijado. Ejecuta fetch-tools."
  [[ -f $gcc/.openvr-source && $(<"$gcc/.openvr-source") == "$gcc_commit" ]] ||
    die "Faltan las herramientas GNU fijadas. Ejecuta fetch-tools."
  for program in make flex bison bc openssl; do
    command -v "$program" >/dev/null || die "Falta $program. Usa el perfil kernel o instala los requisitos."
  done
  "$clang/bin/clang" --version > "$report/hollywood-toolchain.txt"
  "$gcc/bin/aarch64-linux-android-as" --version >> "$report/hollywood-toolchain.txt"
  printf '\nclang_source=%s/%s\ngcc_source=%s\n' "$clang_commit" "$clang_release" "$gcc_commit" >> "$report/hollywood-toolchain.txt"
  export PATH="$clang/bin:$gcc/bin:$PATH"
  export KBUILD_BUILD_USER=openvr KBUILD_BUILD_HOST=build KBUILD_BUILD_VERSION=1
  KBUILD_BUILD_TIMESTAMP=$(git -C "$src" show -s --format=%cD "$kernel_commit")
  export KBUILD_BUILD_TIMESTAMP

  kbuild=(make -C "$src" "O=$out" ARCH=arm64 "AUDIO_BLD_DIR=$src"
    CROSS_COMPILE=aarch64-linux-gnu- CROSS_COMPILE_COMPAT=arm-linux-gnueabi-
    CROSS_COMPILE_ARM32=arm-linux-androideabi- CLANG_TRIPLE=aarch64-linux-gnu-
    "REAL_CC=$clang/bin/clang" "GCC_TOOLCHAIN=$gcc" "GCC_TOOLCHAIN_DIR=$gcc/bin/"
    LLVM=1 LLVM_IAS=1
    "LD=$clang/bin/ld.lld" "AR=$clang/bin/llvm-ar" "LLVM_AR=$clang/bin/llvm-ar"
    "NM=$clang/bin/llvm-nm" "LLVM_NM=$clang/bin/llvm-nm" "OBJCOPY=$clang/bin/llvm-objcopy"
    "OBJDUMP=$clang/bin/llvm-objdump" "READELF=$clang/bin/llvm-readelf" "OBJSIZE=$clang/bin/llvm-size"
    "STRIP=$clang/bin/llvm-strip" "HOSTCC=$clang/bin/clang" "HOSTAR=$clang/bin/llvm-ar"
    "HOSTLD=$clang/bin/ld.lld" HOSTLDFLAGS=-fuse-ld=lld)
}

resolve_config() {
  install -m 0644 -- "$out/hollywood.config.in" "$out/.config"
  "${kbuild[@]}" olddefconfig
  install -m 0644 -- "$out/.config" "$report/hollywood.config"
}

record_artifacts() (
  cd -- "$out"
  local part
  for part in kona kona-v2 kona-v2.1; do
    test -s "arch/arm64/boot/dts/oculus/$part-oculus.dtb"
  done
  for part in poc2 p1.1 evt1 evt2 dvt pvt-b; do
    test -s "arch/arm64/boot/dts/oculus/hollywood/hollywood-$part-overlay.dtbo"
  done
  if [[ $command == compile ]]; then
    test -s arch/arm64/boot/Image
    test -s Module.symvers
    test -f modules.order
  fi

  {
    sha256sum .config
    find arch/arm64/boot/dts/oculus -type f \
      \( -name 'kona*-oculus.dtb' -o -name 'hollywood-*-overlay.dtbo' \) \
      -print0 | sort -z | xargs -0 -r sha256sum
    if [[ $command == compile ]]; then
      sha256sum arch/arm64/boot/Image Module.symvers modules.order
      find . -name '*.ko' -type f -print0 | sort -z | xargs -0 -r sha256sum
    fi
  } > "$report/hollywood-$command.sha256"
  cat "$report/hollywood-$command.sha256"
)

case "$command" in
  fetch-source) fetch_source ;;
  fetch-tools)
    [[ $(uname -sm) == 'Linux x86_64' ]] || die "Los compiladores fijados requieren Linux x86_64."
    fetch_archive clang "$clang_url/+archive/$clang_commit/$clang_release.tar.gz" "$clang_commit/$clang_release"
    fetch_archive gcc "$gcc_url/+archive/$gcc_commit.tar.gz" "$gcc_commit"
    ;;
  merge) merge_config 2>&1 | tee "$report/hollywood-merge.log" ;;
  config|dtbs|compile)
    if [[ $command == compile ]]; then
      command -v pahole >/dev/null || die "Instala pahole para generar BTF con la configuración de Meta."
      command -v cpio >/dev/null || die "Instala cpio para ensamblar el kernel."
    fi
    {
      merge_config
      configure_toolchain
      resolve_config
      case "$command" in
        dtbs)
          "${kbuild[@]}" -j"$jobs" dtbs
          record_artifacts
          ;;
        compile)
          "${kbuild[@]}" -j"$jobs" Image modules dtbs
          record_artifacts
          ;;
      esac
    } 2>&1 | tee "$report/hollywood-$command.log"
    ;;
esac
