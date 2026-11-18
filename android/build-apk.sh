#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/config.sh"

for command in aapt zip zipalign apksigner javac java jar keytool curl flock; do
    command -v "$command" > /dev/null || fail "Falta $command. Usa el entorno dev de OpenVR."
done
framework="${ANDROID_FRAMEWORK_RES:-/usr/share/android-framework-res/framework-res.apk}"
[[ -r "$framework" ]] || fail "Recurso Android ausente: $framework"

mkdir -p -- "$ANDROID_DATA/downloads" "$RESULTS_DIR" "$(dirname -- "$APK_PATH")"
exec 9>"$ANDROID_DATA/apk-build.lock"
flock 9
work="$(mktemp -d "$RESULTS_DIR/.build-apk.XXXXXXXX")"
trap 'rm -rf -- "$work"' EXIT
exec > >(tee "$RESULTS_DIR/android-build-apk.log") 2>&1

get_jar() {
    local url="$1" checksum="$2" archive="$3"
    if [[ ! -f "$archive" ]] || ! printf '%s  %s\n' "$checksum" "$archive" | sha256sum --check --status; then
        curl --fail --silent --show-error --location --retry 2 --output "$work/download.jar" "$url"
        printf '%s  %s\n' "$checksum" "$work/download.jar" | sha256sum --check
        mv -- "$work/download.jar" "$archive"
    fi
}

android_url="https://repo.maven.apache.org/maven2/com/google/android/android/4.1.1.4/android-4.1.1.4.jar"
d8_url="https://storage.googleapis.com/r8-releases/raw/8.3.37/r8.jar"
android_jar="$ANDROID_DATA/downloads/${android_url##*/}"
d8_jar="$ANDROID_DATA/downloads/r8-8.3.37.jar"
get_jar "$android_url" 84072541cbb711eff89f7277100ff854929a446dba7ceb1b195c340e0b4fd3cb "$android_jar"
get_jar "$d8_url" 900dfbc649519969fc5a4c7520d6b7355338e565fa1249874e0190b8d61b1199 "$d8_jar"

if command -v dpkg-query > /dev/null; then
    dpkg-query -W aapt android-framework-res zipalign apksigner
fi
javac -version
java -cp "$d8_jar" com.android.tools.r8.D8 --version
mkdir -- "$work/classes" "$work/dex" "$work/gen"
aapt package -f -m -M "$ANDROID_DIR/app/AndroidManifest.xml" -S "$ANDROID_DIR/app/res" \
    -I "$framework" -J "$work/gen" -F "$work/unsigned.apk"
javac --release 8 -encoding UTF-8 -classpath "$android_jar" -d "$work/classes" \
    "$ANDROID_DIR/app/java/org/openvr/demo/MainActivity.java" "$work/gen/org/openvr/demo/R.java"
jar cf "$work/classes.jar" -C "$work/classes" .
java -cp "$d8_jar" com.android.tools.r8.D8 --release --min-api 26 \
    --lib "$android_jar" --output "$work/dex" "$work/classes.jar"
touch -t 200001010000 "$work/dex/classes.dex"
zip -q -j -X "$work/unsigned.apk" "$work/dex/classes.dex"
zipalign -f 4 "$work/unsigned.apk" "$work/aligned.apk"

key="$ANDROID_DATA/demo-signing.p12"
if [[ ! -f "$key" ]]; then
    (umask 077
        keytool -genkeypair -keystore "$work/signing.p12" -storetype PKCS12 -storepass android \
            -alias openvr-demo -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=OpenVR Demo"
        mv -- "$work/signing.p12" "$key"
    )
fi
apksigner sign --ks "$key" --ks-pass pass:android --ks-key-alias openvr-demo \
    --v4-signing-enabled false --out "$work/openvr-demo.apk" "$work/aligned.apk"
apksigner verify --verbose --print-certs "$work/openvr-demo.apk"
zipalign -c 4 "$work/openvr-demo.apk"
aapt dump badging "$work/openvr-demo.apk"
mv -f -- "$work/openvr-demo.apk" "$APK_PATH"
sha256sum "$APK_PATH"
