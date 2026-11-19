# Verificación del lanzador

Comprobación de compilación ejecutada en Linux amd64 el 19 de noviembre de 2026. Se usaron el SDK público API 34 de AOSP r75, AAPT2 2.19-12006047, javac 21.0.13 y D8 8.3.37. [SDK público API 34](https://android.googlesource.com/platform/prebuilts/sdk/+/refs/tags/android-14.0.0_r75/34/public/android.jar)

Las herramientas y el SDK se ubicaron en un directorio de trabajo temporal. La variable `launcher` apunta al código del módulo.

```bash
mkdir -p gen classes dex
./aapt2 compile --dir "$launcher/res" -o resources.zip
./aapt2 link -I android-34.jar --manifest "$launcher/AndroidManifest.xml" \
  --java gen -o resources.apk resources.zip
java com.sun.tools.javac.Main -source 8 -target 8 -Xlint:all,-options \
  -encoding UTF-8 -classpath android-34.jar -d classes \
  "$launcher"/src/org/openvr/launcher/*.java gen/org/openvr/launcher/R.java
(cd classes && python3 -m zipfile -c ../classes.jar org)
java -cp r8-8.3.37.jar com.android.tools.r8.D8 --release --min-api 26 \
  --lib android-34.jar --output dex classes.jar
./aapt2 dump badging resources.apk
./aapt2 dump xmltree resources.apk --file AndroidManifest.xml
./aapt2 dump resources resources.apk
file dex/classes.dex
```

Resultado de la inspección.

```text
package: name='org.openvr.launcher'
minSdkVersion:'26'
targetSdkVersion:'34'
uses-permission: name='android.permission.ACCESS_NETWORK_STATE'
application-label:'OpenVR'
provides-component:'launcher'
android:name=".MainActivity"
android:exported=true
android.intent.action.MAIN
android.intent.category.HOME
android.intent.category.DEFAULT
id/tab_home
id/tab_library
id/library_search
id/app_open
id/app_label
id/app_favorite
id/tab_settings
id/settings_android
dex/classes.dex: Dalvik dex file version 038
```

El SHA-256 de `android-34.jar` fue `802de40af3f2967e56c4d1e9b75a19963815bf4b6c73ce2bbd24ecd9f7561e10`. El SHA-256 del JAR Linux de AAPT2 fue `028916a040b58f34c9c89984e1bc48f8da6581662014f2b66391860def8b9c36`. El SHA-256 del JAR de D8 fue `900dfbc649519969fc5a4c7520d6b7355338e565fa1249874e0190b8d61b1199`.

## Recorrido en el invitado

Para automatizar Ajustes y la apertura de la APK de ejemplo, el verificador selecciona `org.openvr.launcher:id/tab_settings`, `org.openvr.launcher:id/settings_android`, `org.openvr.launcher:id/tab_library` y después `org.openvr.launcher:id/library_search`. Cada elemento pulsable de la biblioteca usa `org.openvr.launcher:id/app_open` y una descripción accesible con su componente, por ejemplo `OpenVR Demo (org.openvr.demo/.MainActivity)`.

Tras arrancar el invitado, comprueba también que la estrella persiste al reiniciar el lanzador y que un lanzamiento queda en Recientes. Usa la cruceta y el botón de confirmación para recorrer las tres pestañas y accionar una tarjeta. Las comprobaciones de ejecución quedan pendientes en Cuttlefish.
