# Producto OpenVR para Cuttlefish

OpenVR define un producto Android 14 x86_64 con identidad propia, basado en el objetivo de teléfono Cuttlefish de AOSP. El producto conserva el dispositivo de compilación `vsoc_x86_64` y sus componentes del sistema, kernel y HAL. Instala **OpenVR Launcher** en la partición product y declara su actividad HOME como preferida. Launcher3 sigue disponible para las funciones del sistema que dependen de él. [Objetivos de Cuttlefish](https://android.googlesource.com/device/google/cuttlefish/+/refs/tags/android-14.0.0_r75/AndroidProducts.mk) · [Producto base](https://android.googlesource.com/device/google/cuttlefish/+/refs/tags/android-14.0.0_r75/vsoc_x86_64/phone/aosp_cf.mk) · [Lectura de actividades preferidas en Android](https://android.googlesource.com/platform/frameworks/base/+/refs/tags/android-14.0.0_r75/services/core/java/com/android/server/pm/Settings.java).

La etiqueta anotada `android-14.0.0_r75` del repositorio de manifiestos tiene el identificador `c49a52c108f10a64f6122af27fd27f96b8d45424` y apunta al commit `e3b1a5113daede938922ed29c36806e0aac2ecb3`. El producto usa el release global `trunk_staging` de esa misma versión. [Manifiesto](https://android.googlesource.com/platform/manifest/+/refs/tags/android-14.0.0_r75) · [Configuraciones de release](https://android.googlesource.com/platform/build/release/+/refs/tags/android-14.0.0_r75/release_config_map.mk).

## Compilar en Linux x86_64

AOSP publica como referencia 400 GB libres y 64 GB de RAM. Una compilación completa puede llevar varias horas, según CPU, disco y configuración. Usa el laboratorio demo o dev en el equipo Windows de 16 GB y reserva una máquina Linux más potente para esta etapa. [Requisitos de AOSP](https://source.android.com/docs/setup/start/requirements).

```bash
docker compose --profile build build build
docker compose --profile build run --rm build sync
docker compose --profile build run --rm build compile
```

El perfil build usa el volumen `aosp-source`. `compile` prepara `device/openvr/lab` y ejecuta `lunch openvr_cf_x86_64_phone-trunk_staging-userdebug` y `m droid`. La carpeta de preparación se genera a partir de `aosp/product/` y `aosp/launcher/`. Edita las fuentes en el repositorio, ya que cada preparación actualiza esa carpeta. `stage` copia la integración sin lanzar la compilación. La compilación de referencia sigue disponible como `compile-reference`, con salida separada en el volumen. Ajusta `AOSP_JOBS` con `docker compose run -e AOSP_JOBS=4 …` según la memoria disponible.

En el volumen de resultados quedan el manifiesto resuelto en `aosp-manifest.xml` y los registros de la sincronización y compilación. El manifiesto fija las revisiones obtenidas, aunque la compilación completa puede incorporar metadatos y marcas temporales del entorno.

## Exportar el invitado virtual

```bash
docker compose --profile build run --rm build export
```

`export` ejecuta los objetivos AOSP `droid updatepackage hosttar`. Copia el ZIP de imágenes y las herramientas host del mismo build a un directorio `openvr-cuttlefish.*` dentro de `/data/results`. Conserva los SHA-256, el tamaño en bytes y el manifiesto resuelto. Los artefactos contienen el software del invitado Cuttlefish y se usan con sus herramientas host. [Objetivo updatepackage](https://android.googlesource.com/platform/build/+/refs/tags/android-14.0.0_r75/core/Makefile) · [Objetivo hosttar](https://android.googlesource.com/device/google/cuttlefish/+/refs/tags/android-14.0.0_r75/host_package.mk).

## Arrancar y comprobar Cuttlefish

En un anfitrión Linux x86_64 con acceso a KVM, instala las dependencias host indicadas por AOSP. Copia los dos artefactos y `SHA256SUMS` a una carpeta nueva de ese anfitrión. [Preparación del anfitrión Cuttlefish](https://source.android.com/docs/devices/cuttlefish/get-started).

```bash
sha256sum -c SHA256SUMS
tar -xzf cvd-host_package.tar.gz
unzip openvr_cf_x86_64_phone-img.zip
HOME="$PWD" ./bin/launch_cvd --daemon
./bin/adb devices -l
```

Ejecuta el verificador desde el anfitrión con el serial exacto que ha mostrado ADB. Añade la ruta a la APK de ejemplo como segundo argumento para probar su instalación y apertura en el producto.

```bash
OPENVR_ADB="$PWD/bin/adb" /ruta/OpenVR/aosp/verify-guest.sh SERIAL_CUTTLEFISH
```

El verificador espera el arranque, identifica el producto OpenVR y la ABI x86_64, comprueba el paquete del lanzador, resuelve el intent HOME y abre la actividad. Guarda ambas salidas en `results/cuttlefish/`. Si una instancia con datos previos ya tiene otro HOME elegido, puedes seleccionar OpenVR en **Aplicaciones predeterminadas** o con `./bin/adb -s SERIAL_CUTTLEFISH shell cmd package set-home-activity --user 0 org.openvr.launcher/.MainActivity`. Para verificar la selección inicial usa una instancia Cuttlefish nueva. [Comando set-home-activity en Android 14](https://android.googlesource.com/platform/frameworks/base/+/refs/tags/android-14.0.0_r75/services/core/java/com/android/server/pm/PackageManagerShellCommand.java).

Detén la instancia con `HOME="$PWD" ./bin/stop_cvd` desde la misma carpeta.

## Estado

La integración del producto y del lanzador está implementada. Las pruebas con datos simulados verificaron stage, los objetivos de compilación y exportación, los SHA‑256 de salida y la selección del invitado antes de instalar la APK. La compilación completa, la exportación real y el arranque de este producto requieren una máquina con los recursos indicados. La instalación de la APK del laboratorio en Android Emulator usa otro invitado. Para validar la APK en este producto, hay que ejecutar el verificador en el Cuttlefish construido. El runtime OpenXR y el compositor del sistema siguen pendientes de integración en Android.
