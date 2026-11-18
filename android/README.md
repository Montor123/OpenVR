# OpenVR en Android

El entorno usa Android 14 AOSP de referencia en una máquina virtual x86_64. Chrome o Edge muestran el escritorio Linux del laboratorio y su ventana de Android por noVNC. ADB instala APK en el invitado. El visor y los mandos de OpenXR se prueban por separado en el entorno Linux.

## Ejecutar en el entorno dev

Desde el directorio del proyecto dentro del contenedor dev:

```bash
android/build-apk.sh
```

El resultado predeterminado es `/data/results/openvr-demo.apk`. La actividad `org.openvr.demo/.MainActivity` muestra la versión de Android, el nivel API y la ABI del invitado. El botón **Comprobar ejecución** registra `DIAGNOSTIC_PRESSED` con la etiqueta `OpenVRDemo`.

Para descargar las herramientas de Google, revisa primero la [licencia del SDK de Android](https://developer.android.com/studio/terms). Si la aceptas, ejecuta el instalador explícitamente:

```bash
android/setup.sh --accept
```

En una terminal del contenedor, inicia el emulador y déjalo en ejecución. Si trabajas sin escritorio, añade `ANDROID_HEADLESS=1` antes del comando.

```bash
android/start.sh
```

En una segunda terminal, usa la prueba de instalación, lanzamiento y captura:

```bash
android/smoke.sh
```

La prueba espera a `sys.boot_completed`, registra la versión y la ABI del invitado, instala la APK, inicia su actividad, verifica `APP_READY` en logcat y guarda una captura PNG. Los resultados se conservan en `/data/results`.

| Archivo | Contenido |
| --- | --- |
| `android-build-apk.log` | Compilador, firma, manifiesto y SHA-256 |
| `android-setup.log` | Versiones de ADB y emulador |
| `android-emulator.log` | Arranque y modo de aceleración |
| `android-smoke.log` | Instalación, actividad y marcador de ejecución |
| `android-logcat.txt` | Registro del invitado al finalizar la prueba |
| `android-smoke.png` | Captura real obtenida por ADB si la prueba termina |

Para instalar una APK propia autorizada, cópiala a la carpeta montada de descargas o usa la interfaz de OpenVR. Desde el contenedor, utiliza ADB con el serial del invitado:

```bash
/data/android/sdk/platform-tools/adb -s emulator-5554 install -r /ruta/para/mi.apk
/data/android/sdk/platform-tools/adb -s emulator-5554 logcat
/data/android/sdk/platform-tools/adb -s emulator-5554 emu kill
```

La clave de desarrollo de la APK de ejemplo se genera la primera vez y queda en el volumen de datos. Conservarla permite que `adb install -r` actualice la app sin borrar sus datos.

## Aceleración y alcance

`ANDROID_ACCEL=auto` comprueba si `/dev/kvm` se puede abrir y si el emulador informa que KVM está disponible. `ANDROID_ACCEL=kvm` requiere que ambas comprobaciones pasen. `ANDROID_ACCEL=software` solicita `-accel off`. SwiftShader procesa los gráficos por software en los tres modos. La exposición efectiva de KVM depende del anfitrión, de WSL2 y de Docker Desktop. Si está ausente, el arranque por software puede ser lento o fallar. `ANDROID_BOOT_TIMEOUT` ajusta la espera de la prueba, con 900 segundos por defecto. [Documentación de aceleración](https://developer.android.com/studio/run/emulator-acceleration) · [Opciones del emulador](https://developer.android.com/studio/run/emulator-commandline).

Las descargas suman 1 079 459 854 bytes antes de extraerlas. Reserva en torno a 8 GB libres para SDK, descargas, AVD y margen operativo. El invitado solicita 2 GB de RAM y dos núcleos. En un equipo Windows de 16 GB, se puede empezar reservando unos 6–8 GB para WSL2 y ejecutando un invitado a la vez; el tiempo de arranque depende sobre todo de KVM.

La APK de ejemplo es Java y carece de bibliotecas nativas. Una APK con bibliotecas JNI solo funciona si el invitado admite una de las ABI incluidas. Esta ruta ejecuta x86_64. La ejecución ARM64, el soporte de OpenXR en el invitado y los servicios propietarios de Meta y Google Play quedan fuera de la prueba. [ABI Android](https://developer.android.com/ndk/guides/abis).

## Versiones y fuentes

| Componente | Versión | Origen y licencia |
| --- | --- | --- |
| AOSP del invitado | Android 14, API 34, x86_64, revisión 4 | Catálogo de [imágenes de Google](https://dl.google.com/android/repository/sys-img/android/sys-img2-3.xml). La descarga está sujeta a la licencia del SDK y permanece en el volumen local. |
| Android Emulator y ADB | 37.2.13 y Platform-Tools 37.0.1 | [Catálogo de Google](https://dl.google.com/android/repository/repository2-3.xml), canal estable. El instalador valida el tamaño y el SHA-1 que publica Google. |
| API Java para compilar la muestra | `com.google.android:android:4.1.1.4` | [Artefacto Apache-2.0 de Maven Central](https://repo.maven.apache.org/maven2/com/google/android/android/4.1.1.4/android-4.1.1.4.pom). Incluye la API que usa el código. El manifiesto declara compatibilidad a partir de API 26 y destino 34. |
| D8 | 8.3.37 | [R8, BSD-3-Clause](https://r8.googlesource.com/r8/+/refs/heads/main/LICENSE). La compilación verifica el SHA-256 del JAR y de la API Java antes de usarlos. |
| JDK y herramientas de APK | OpenJDK 17, aapt y android-framework-res `1:10.0.0+r36-10`, Zipalign `1:10.0.0+r36-1`, ApkSigner `31.0.2-1` | [Paquetes Debian Bookworm](https://packages.debian.org/bookworm/aapt). Cada paquete incluye su licencia en `/usr/share/doc`. |

La APK que compila el proyecto incluye sus propios recursos y código Java compilado. El SDK de Google, las imágenes de sistema, las dependencias de compilación y la clave de firma permanecen fuera de la APK.
