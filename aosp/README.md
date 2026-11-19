# Producto OpenVR para Cuttlefish

OpenVR define un producto Android 14 x86_64 con identidad propia, basado en el objetivo de teléfono Cuttlefish de AOSP. El producto conserva el dispositivo de compilación `vsoc_x86_64` y sus componentes del sistema, kernel y HAL. Instala **OpenVR Launcher** en la partición product y declara su actividad HOME como preferida. Launcher3 sigue disponible para las funciones del sistema que dependen de él. [Objetivos de Cuttlefish](https://android.googlesource.com/device/google/cuttlefish/+/refs/tags/android-14.0.0_r75/AndroidProducts.mk) · [Producto base](https://android.googlesource.com/device/google/cuttlefish/+/refs/tags/android-14.0.0_r75/vsoc_x86_64/phone/aosp_cf.mk) · [Lectura de actividades preferidas en Android](https://android.googlesource.com/platform/frameworks/base/+/refs/tags/android-14.0.0_r75/services/core/java/com/android/server/pm/Settings.java).

La etiqueta anotada `android-14.0.0_r75` del repositorio de manifiestos tiene el identificador `c49a52c108f10a64f6122af27fd27f96b8d45424` y apunta al commit `e3b1a5113daede938922ed29c36806e0aac2ecb3`. El producto usa el release global `trunk_staging` de esa misma versión. [Manifiesto](https://android.googlesource.com/platform/manifest/+/refs/tags/android-14.0.0_r75) · [Configuraciones de release](https://android.googlesource.com/platform/build/release/+/refs/tags/android-14.0.0_r75/release_config_map.mk).

## Compilar en Linux x86_64

AOSP publica como referencia 400 GB libres y 64 GB de RAM. Una compilación completa puede llevar varias horas, según CPU, disco y configuración. Usa el laboratorio demo o dev en el equipo Windows de 16 GB y reserva una máquina Linux más potente para esta etapa. [Requisitos de AOSP](https://source.android.com/docs/setup/start/requirements).

```bash
docker compose --profile build build build
docker compose --profile build run --rm build preflight
docker compose --profile build run --rm build sync
docker compose --profile build run --rm build compile
```

El perfil build usa el volumen `aosp-source`. `compile` prepara `device/openvr/lab` y ejecuta `lunch openvr_cf_x86_64_phone-trunk_staging-userdebug` y `m droid`. La carpeta de preparación se genera a partir de `aosp/product/` y `aosp/launcher/`. Edita las fuentes en el repositorio, ya que cada preparación actualiza esa carpeta. `stage` copia la integración sin lanzar la compilación. La compilación de referencia sigue disponible como `compile-reference`, con salida separada en el volumen. Ajusta `AOSP_JOBS` con `docker compose run -e AOSP_JOBS=4 …` según la memoria disponible.

`preflight` muestra CPU visibles, espacio libre en el volumen y RAM disponible, teniendo en cuenta los límites de memoria de cgroup v2 que estén visibles. Las cifras de AOSP sirven para dimensionar una compilación completa. En el volumen de resultados quedan los registros, el manifiesto resuelto `aosp-manifest.xml` y los SHA-256 de las fuentes OpenVR aplicadas en `aosp-openvr-source.sha256`. El manifiesto fija las revisiones obtenidas. La compilación puede incorporar metadatos y marcas temporales del entorno.

## Exportar el invitado virtual

```bash
docker compose --profile build run --rm build export
```

`export` ejecuta los objetivos AOSP `droid updatepackage hosttar`. Copia el ZIP de imágenes y las herramientas host del mismo build a un directorio `openvr-cuttlefish.*` dentro de `/data/results`. Valida ambas estructuras y conserva sus SHA-256, tamaños, manifiesto resuelto y hashes del código OpenVR incorporado. El ZIP de r75 incluye `android-info.txt`, `boot.img`, `bootloader` y `super.img`. Usa sus herramientas host de la misma compilación. [Objetivo updatepackage](https://android.googlesource.com/platform/build/+/refs/tags/android-14.0.0_r75/core/Makefile) · [Imágenes de Cuttlefish](https://android.googlesource.com/device/google/cuttlefish/+/refs/tags/android-14.0.0_r75/shared/BoardConfig.mk) · [Objetivo hosttar](https://android.googlesource.com/device/google/cuttlefish/+/refs/tags/android-14.0.0_r75/host_package.mk).

## Arrancar y comprobar Cuttlefish

Usa un anfitrión Linux x86_64 con las dependencias de Cuttlefish, Python 3 con el filtro `tarfile.data_filter` y acceso a KVM como usuario normal. Copia al anfitrión el directorio de exportación completo. Ejecuta desde la raíz de OpenVR con un directorio de ejecución nuevo cuya ruta carezca de espacios. [Preparación del anfitrión Cuttlefish](https://source.android.com/docs/devices/cuttlefish/get-started) · [Detención en r75](https://android.googlesource.com/device/google/cuttlefish/+/refs/tags/android-14.0.0_r75/host/commands/stop/main.cc).

```bash
aosp/launch-guest.sh --check-host
aosp/launch-guest.sh --check-bundle /ruta/openvr-cuttlefish.EXPORT
aosp/launch-guest.sh /ruta/openvr-cuttlefish.EXPORT ./openvr-guest
```

El arranque comprueba que KVM permita crear una VM, que haya espacio libre para extraer el paquete más 4 GiB de trabajo y que el archivo cumpla tamaños, SHA-256 y rutas esperadas. Extrae las herramientas host y las imágenes en carpetas independientes. Arranca una instancia con dos CPU, 3 GiB para el invitado y SwiftShader. Espera a `sys.boot_completed` e identifica el producto y la ABI por ADB. `AOSP_BOOT_TIMEOUT` controla el plazo de arranque, con 300 segundos por defecto. Conserva el registro en `openvr-guest/cuttlefish-launch.log`.

Abre `https://localhost:8443` en ese anfitrión para ver el invitado. Cuttlefish abre sus propios puertos. El proxy TCP de ADB de r75 escucha en todas las interfaces y el servidor WebRTC no fija una interfaz en su código. Limita el acceso a esos puertos a través de la red del anfitrión. [Puertos y opciones de r75](https://android.googlesource.com/device/google/cuttlefish/+/refs/tags/android-14.0.0_r75/host/commands/assemble_cvd/flags.cc) · [Proxy TCP](https://android.googlesource.com/device/google/cuttlefish/+/refs/tags/android-14.0.0_r75/common/libs/fs/shared_fd.cpp) · [WebRTC](https://android.googlesource.com/device/google/cuttlefish/+/refs/tags/android-14.0.0_r75/host/libs/websocket/websocket_server.cpp).

El verificador identifica el invitado, comprueba HOME y abre Ajustes desde el lanzador. Añade la ruta a la APK de ejemplo para instalarla, buscarla en Biblioteca y comprobar que la actividad llega a primer plano y emite APP_READY. Para validar la selección inicial usa el directorio nuevo que crea el script de arranque.

```bash
OPENVR_ADB="$PWD/openvr-guest/bin/adb" aosp/verify-guest.sh 127.0.0.1:6520
OPENVR_ADB="$PWD/openvr-guest/bin/adb" aosp/verify-guest.sh 127.0.0.1:6520 /ruta/openvr-demo.apk
aosp/launch-guest.sh --stop ./openvr-guest
```

La detención conserva las imágenes y los registros en el directorio de ejecución.

## Estado

La integración del producto y del lanzador está implementada. Las pruebas con archivos de ejemplo verificaron la preparación del árbol, los objetivos de compilación y exportación y la validación de los archivos de Cuttlefish. La comprobación real de KVM del entorno de desarrollo falló porque no expone `/dev/kvm`. Siguen pendientes la compilación completa, la exportación real y el arranque del producto. Android Emulator y Cuttlefish son dos invitados diferentes. El runtime OpenXR y el compositor del sistema siguen pendientes de integración en Android.
