# Verificación del lanzador

Prueba ejecutada en Linux amd64 el 18 de noviembre de 2026. Se usaron el SDK público API 34 de AOSP r75, AAPT2 2.19-12006047, javac 21.0.13 y D8 8.3.37. [SDK público API 34](https://android.googlesource.com/platform/prebuilts/sdk/+/refs/tags/android-14.0.0_r75/34/public/android.jar)

Las herramientas y el SDK se ubicaron en un directorio de trabajo temporal, con `launcher` apuntando al código del módulo.

```bash
mkdir -p gen classes dex
./aapt2 compile --dir "$launcher/res" -o resources.zip
./aapt2 link -I android-34.jar --manifest "$launcher/AndroidManifest.xml" \
  --java gen -o resources.apk resources.zip
java com.sun.tools.javac.Main -source 8 -target 8 -Xlint:all,-options \
  -encoding UTF-8 -classpath android-34.jar -d classes \
  "$launcher/src/org/openvr/launcher/MainActivity.java" gen/org/openvr/launcher/R.java
(cd classes && python3 -m zipfile -c ../classes.jar org)
java -cp r8-8.3.37.jar com.android.tools.r8.D8 --release --min-api 26 \
  --lib android-34.jar --output dex classes.jar
./aapt2 dump badging resources.apk
./aapt2 dump xmltree resources.apk --file AndroidManifest.xml
file dex/classes.dex
```

Resultado de la inspección.

```text
package: name='org.openvr.launcher'
minSdkVersion:'26'
targetSdkVersion:'34'
application-label:'OpenVR'
provides-component:'launcher'
android:name=".MainActivity"
android:exported=true
android.intent.action.MAIN
android.intent.category.HOME
android.intent.category.DEFAULT
dex/classes.dex: Dalvik dex file version 038
```

El SHA-256 de `android-34.jar` es `802de40af3f2967e56c4d1e9b75a19963815bf4b6c73ce2bbd24ecd9f7561e10`. El SHA-256 del JAR Linux de AAPT2 es `028916a040b58f34c9c89984e1bc48f8da6581662014f2b66391860def8b9c36`. El SHA-256 del JAR de D8 es `900dfbc649519969fc5a4c7520d6b7355338e565fa1249874e0190b8d61b1199`.

Queda pendiente validar el recorrido de inicio y lanzamiento de aplicaciones en Cuttlefish con la imagen de AOSP compilada.
