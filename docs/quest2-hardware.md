# Viabilidad en Meta Quest 2

Consulta de fuentes y código el **18 de noviembre de 2026**. El objetivo físico es **Quest 2, `hollywood`**. La demo de escritorio y la prueba Android virtual cubren componentes de software. El proyecto aún carece de mediciones en un visor físico.

- **A** — verificado por OpenVR en una Quest 2 física, con modelo, compilación, método y registros. Ninguna fila tiene esta calificación en esta entrega.
- **B** — documentado por el fabricante, un desmontaje o código público verificable. La función sigue sin probarse en hardware por OpenVR.
- **C** — candidato o hipótesis de integración que requiere un experimento.
- **D** — bloqueado o desconocido. La evidencia actual no permite validar la función o la ruta.

## Evaluación del arranque

**D. El arranque en frío de una imagen propia sigue bloqueado.** Meta ofrece una vía de actualización para Quest 2 y herramientas de desarrollo para instalar y depurar aplicaciones en Horizon OS. La documentación pública revisada carece de un procedimiento oficial de desbloqueo de Quest 2 o de una clave de arranque instalable por el propietario. El paquete de desbloqueo de octubre de 2021 corresponde al Oculus Go. [Actualización oficial de Quest][update] · [Desarrollo y ADB][adb-meta] · [Anuncio para Oculus Go][go-unlock]

El modo desarrollador permite autorizar ADB e instalar APK en el sistema existente. Root concede privilegios dentro de un sistema en ejecución. El estado del bootloader y sus claves determinan qué imagen admite la cadena de confianza desde el encendido. Las pruebas comunitarias de arranque secundario sobre dispositivos que ya tienen acceso privilegiado dependen de una compilación y un kernel concretos. Falta verificar una combinación de firmware y revisión de Quest 2 que proporcione a este proyecto un arranque autónomo y recuperable. [ADB de Meta][adb-meta] · [Estados de bloqueo en AOSP][locking] · [Flujo de Verified Boot][boot-flow]

**B/C. Modelo de referencia de arranque.** Qualcomm describe una etapa de ROM que autentica el siguiente cargador y una cadena de etapas verificadas. Android describe la verificación de las imágenes del sistema, las ranuras A/B cuando se usan y la protección frente a regresiones de versión. El árbol de Meta configura DTB y DTBO para variantes de placa y habilita dm-verity. Falta levantar el inventario de ranuras, particiones físicas y lógicas, claves, encabezados y política de reversión de la unidad exacta. La presencia de `boot`, `vendor_boot`, `dtbo`, `vbmeta`, `super` o una partición de recuperación independiente debe confirmarse contra el firmware concreto. [Arranque seguro de Qualcomm, noviembre de 2016][qcom-boot] · [Particiones de AOSP][partitions] · [Imágenes de recuperación AOSP][recovery] · [DTB/DTBO de Hollywood][dt-make] · [Configuración Kona][kona-config]

**B. Recuperación del sistema original.** Meta lista Quest 2 en su herramienta de actualización. Sigue pendiente demostrar la recuperación de la unidad exacta tras un fallo de arranque y verificar qué datos conserva. Meta anunció el 2 de noviembre de 2026 que v2.13 es la última versión con funciones para Quest 2, con despliegue completo previsto en marzo de 2027 y parches de seguridad hasta diciembre de 2027. [Herramienta de Meta][update] · [Calendario de soporte de Meta][lifecycle]

## Código del kernel publicado por Meta

Se inspeccionó la rama `oculus-quest2-kernel-master` en la revisión **`dba8278b20c9b22d8e90db5ce03825fb6238e4d2`**, fechada **17 de noviembre de 2026 (UTC)**, compilación de proyecto **5237196.1410.150**. El `Makefile` de esa revisión declara **Linux 4.19.325**. Vincular la revisión a un visor requiere comparar la versión y el identificador de su kernel en ejecución con el código y los metadatos de su compilación. [Commit de Meta][kernel] · [Versión del kernel][kernel-make]

- Meta documenta la arquitectura **arm64**, las herramientas Clang y GCC prebuilts de la rama de AOSP `android14-release` y la combinación de `oculus_kona_defconfig` con `oculus_hollywood_defconfig`. Para una compilación reproducible deben fijarse también los commits de ambos repositorios de herramientas. La rama de herramientas corresponde a la receta de compilación. La versión de Android instalada se verifica en la unidad. [README de Meta][meta-readme] · [Configuración Kona][kona-config] · [Configuración Hollywood][hw-config]
- Hollywood se construye sobre DTB Kona, Kona v2 y Kona v2.1. El Makefile enumera overlays POC2, P1.1, EVT1, EVT2, DVT y PVT-B. La selección correcta del overlay y del panel requiere identificar la revisión de placa. [Árbol Hollywood][dt] · [DTB/DTBO de Hollywood][dt-make]
- El perfil Kona configura `CONFIG_MODULES=y` y `CONFIG_MODVERSIONS=y`. Las opciones `=m` incluyen `CONFIG_QCA_CLD_WLAN`, `CONFIG_QCOM_LLCC_PERFMON`, `CONFIG_POWERSTATE_MANAGER` y clases USB como audio, ACM, serial y adaptadores de red. El perfil compila SyncBoss SPI, sincronización temporal y cámaras Spectra dentro del kernel. La lista efectiva de `.ko`, ABI de símbolos, dependencias y firmware deben contrastarse con una compilación y con el dispositivo. [Configuración Kona][kona-config] · [Árbol SyncBoss][sync-code] · [Árbol WLAN][wifi-code]
- El kernel se publica con GPL-2.0 y excepción de llamadas al sistema. Algunos archivos y subárboles tienen avisos distintos. Conservar el aviso aplicable por archivo si se redistribuyen fuentes o parches. Las imágenes de arranque del fabricante, firmware de coprocesadores y bibliotecas de proveedor requieren una revisión de derechos propia. [COPYING de Meta][kernel-license] · [Directrices de licencia del kernel][linux-license]

## Matriz de soporte

La columna de licencia indica el alcance del código citado. El software de proveedor y los datos de calibración tienen condiciones independientes.

| Hardware o función | Controlador o subsistema | Código y licencia | Dependencias propietarias o sin inventariar | Estado | Trabajo pendiente |
| --- | --- | --- | --- | --- | --- |
| Snapdragon XR2 de primera generación, SXR2130P en la placa desmontada. CPU Kryo ARM64 de ocho núcleos y 6 GB de RAM | Árbol Qualcomm Kona, reloj, cpufreq, RPMh y reguladores | DTS y configuración del kernel Meta, licencia por archivo | Inicialización de DDR, cargadores y firmware de plataforma | B para hardware y código. D para arranque propio | Confirmar revisión y topología por diagnóstico de solo lectura. Medir frecuencia, suspensión y RAM. [Meta, 2020][meta-launch] · [Qualcomm, 16 sep 2020][qcom-launch] · [TechInsights DDT-2010-820][teardown-chip] · [DTS Kona][kona-dts] |
| GPU Adreno 650, identificable por chip ID y firmware en el DTS Kona | Qualcomm KGSL en kernel Meta. DRM/MSM con Freedreno y Turnip como candidatos | KGSL en kernel GPL-2.0. Mesa principalmente MIT | Firmware Adreno y GMU. El DTS referencia `a650_zap`. El stack Android de proveedor requiere bibliotecas EGL/Vulkan y HAL compatibles | B para código y familia. C para aceleración abierta en esta placa | Confirmar ABI KGSL o DRM, disponibilidad legal de firmware, Vulkan, presentación y estabilidad térmica. [DTS GPU Kona][gpu-dts] · [KGSL][kgsl] · [Mesa Freedreno/Turnip][freedreno] · [Licencia de Mesa][mesa-license] |
| Almacenamiento UFS. SKU de 64 GB (301-00350-01), 128 y 256 GB documentados en 2023 | Host UFS Qualcomm y PHY QMP | Controlador y DTS de Meta, GPL-2.0 con licencias por archivo | Firmware de almacenamiento y claves ligadas al dispositivo si hay cifrado | B para UFS y variantes comerciales. D para mapa y recuperación del sistema propio | Inventariar capacidad, slots y volúmenes sin escribirlos. Validar recuperación para la revisión exacta. [DTS UFS][ufs-dts] · [Controlador UFS][ufs-code] · [Ficha comercial de 64 GB][sku64] · [SKU de 2023][sku] |
| Panel LCD único, 1832 × 1920 píxeles por ojo, MIPI DSI con DSC. Tablas BOE, JDI y Sharp hasta 120 Hz | Display Qualcomm, árbol de paneles y retroiluminación | `techpack/display` y DTS, avisos por archivo | Identificación del panel, secuencias de inicialización y datos de calibración de fábrica si corresponden | B para especificaciones y configuración. D para ejecución en imagen propia | Seleccionar panel y overlay correctos. Medir modos, orientación, luminancia, temporización y apagado. [Anuncio de Meta][meta-launch] · [iFixit, 27 ene 2022][ifixit] · [Variantes de panel][panel-dts] · [Código de pantalla][display-code] |
| Óptica Fresnel, ajuste mecánico de IPD en tres posiciones | Compositor XR y modelo de distorsión por ojo. El perfil Hollywood activa `CONFIG_AS5510` | Código AS5510 en árbol Meta. Monado ofrece distorsión para otros visores bajo BSL-1.0 | Centros ópticos, calibración por posición o unidad y parámetros de distorsión | B para óptica, C para integración del sensor y D para perfil óptico propio | Medir geometría, distorsión, aberración cromática y posición de cada ojo. [Desmontaje][ifixit] · [Perfil Hollywood][hw-config] · [Sensor en código de Meta][as5510] · [Monado][monado] |
| Cuatro cámaras de seguimiento, cuatro nodos en Hollywood | Qualcomm Spectra, recursos de cámaras y V4L2 | `techpack/camera` y DTS, licencias por archivo | Identificación y tablas de sensor, firmware ISP, HAL, tiempos y calibración | B para cantidad y código. D para captura utilizable | Identificar cada sensor y obtener cuadros con marcas de tiempo. La API de cámaras de passthrough de Horizon OS v74 documenta Quest 3/3S. [DTS cámaras][camera-dts] · [Código][camera-code] · [API de Meta][pca] |
| IMU, proximidad y sincronización con cámaras | SyncBoss por SPI, FIFO, sincronización y cámara `cam-fsync` | SyncBoss y controladores Oculus, licencias por archivo | `syncboss.bin` referenciado en DTS. La sincronización exige firmware compatible. Modelo de IMU y calibración por confirmar | B para código y vínculo con firmware. D para datos calibrados | Correlacionar relojes de IMU y cámaras. Medir muestreo, latencia, ruido y deriva. [DTS SyncBoss][sync-dts] · [Código SyncBoss][sync-code] · [Controladores Oculus][oculus-code] |
| Seguimiento 6DoF, passthrough y límites de juego | Odometría visual-inercial y compositor | Monado BSL-1.0 y Basalt BSD-3-Clause como candidatos | Pipeline de tracking y calibración de Horizon OS. Los sustitutos requieren datos sincronizados y calibración | B para función original, C para VIO abierto, D para seguimiento propio | Medir deriva, latencia, pérdida de tracking y recuperación en banco. Implementar límites y degradación segura. [Desmontaje y seguimiento][ifixit] · [Monado][monado] · [Basalt][basalt] |
| Dos mandos Touch, botones, anillos de seguimiento y háptica | Pila de mandos, radio y correlación óptica de pose | Perfiles de interacción OpenXR. Falta identificar controlador abierto integral para uso autónomo en Quest 2 | Firmware, protocolo de enlace, calibración óptica y pose | B para mandos originales. D para emparejado y seguimiento abiertos | Identificar transporte, temporización, botones y háptica. Validar implementación física de la interfaz OpenXR. [Lanzamiento de Meta][meta-launch] · [OpenXR 1.1, § 6.4.20][touch-profile] |
| Wi-Fi y Bluetooth, QCA6391 en unidad de TechInsights y nombres QCA6390 en DTS Meta | CNSS2, qcacld y potencia BT en Kona. `ath11k` candidato para kernel moderno | Código publicado por Meta y Linux, licencias por archivo | Firmware WLAN/BT, datos de placa, calibración, dominio regulatorio y coexistencia | B para identificación. C para `ath11k`. D para integración | Confirmar PCI ID y revisión, obtener firmware autorizado y validar radio, suspensión y coexistencia. [Identificación de chips][teardown-chip] · [DTS WLAN][wifi-dts] · [CNSS2][cnss] · [Linux Wireless][ath11k] |
| USB-C, host/dispositivo y carga | DWC3 MSM, USB gadget, Type-C/PD y VDM | Controlador GPL-2.0 y DTS de Meta | Política PD y firmware de periféricos según variante | B para USB/ADB oficial y fuente. D para datos y carga en otro sistema | Probar enumeración, ADB, cambio de rol, reanudación y límites eléctricos. [DWC3 MSM][usb-code] · [DTS Hollywood][hw-dts] · [ADB de Meta][adb-meta] |
| Audio, dos altavoces y códecs AK4331/CM710x en Hollywood | ALSA SoC, códecs y Qualcomm LPASS/ADSP | `sound/soc`, `techpack/audio` y DTS, licencias por archivo | Firmware DSP, rutas de mezcla, afinación y posible firmware de códec | B para hardware y fuentes. D para audio integral | Validar micrófonos, altavoces, auriculares, ganancia y suspensión. [Desmontaje][ifixit] · [DTS de audio][audio-dts] · [Código de audio][audio-code] |
| Batería de 14,3 Wh en unidad desmontada, PMIC Qualcomm, ventilador y disipador | QPNP, medidor TI BQ27z561, PWM con tacómetro y zonas térmicas | Perfiles de batería Goertek en DTS, drivers y política parcial de kernel, licencias por archivo | Perfiles térmicos de producción, gestión de firmware y límites de cada batería | B para hardware y drivers. D para seguridad térmica autónoma | Verificar temperatura, ventilador, suspensión, carga, apagado y reacción a fallo. Mantener protecciones durante la puesta en marcha. [Desmontaje][ifixit] · [DTS Hollywood][hw-dts] · [DTS ventilador][fan-dts] · [DTS térmico][thermal-dts] |
| Arranque seguro y recuperación | PBL/cargadores del fabricante, Android Verified Boot y recuperación de Horizon OS | AOSP AVB Apache-2.0 como modelo de referencia. Kernel Meta con dm-verity | Cargadores firmados, claves, servicios seguros, imágenes oficiales y restricciones de versión | B para recuperación documentada. D para arranque propio y restauración ensayada | Correlacionar compilación, placa, particiones y estado. Validar una vía autorizada de arranque y recuperación antes de crear imágenes de instalación. [Arquitectura Qualcomm][qcom-boot] · [Código AVB][avb] · [Actualización Meta][update] |

## Qué se puede reutilizar

| Proyecto | Licencia | Uso posible |
| --- | --- | --- |
| Kernel de Meta, revisión descrita arriba | GPL-2.0 con excepción de syscall para el conjunto. Avisos específicos por archivo | Identificar buses, GPIO, dispositivos y variantes. Comparar configuración y producir `Image`, DTB y DTBO para análisis cuando se disponga de toolchain. [Fuentes fijadas][kernel] |
| Monado y Khronos OpenXR SDK | Monado BSL-1.0 para el núcleo, con otras licencias por archivo. SDK Apache-2.0 o MIT según archivo | Probar aplicaciones OpenXR nativas y seguimiento simulado. La conformidad publicada de Quest 2 corresponde al runtime de Meta en Android, con OpenXR 1.0 registrado el 15 de octubre de 2020. [Dispositivos simulados][monado-dev] · [Licencia Monado][monado-license] · [SDK Khronos][openxr-sdk] · [Conformidad][xr-cts] |
| Mesa, Freedreno y Turnip | Principalmente MIT | Investigar una pila gráfica abierta, sujeta a kernel, firmware y pruebas de placa. [Freedreno][freedreno] · [Licencias][mesa-license] |
| Basalt | BSD-3-Clause según licencia upstream | Investigar odometría visual-inercial tras obtener imágenes, IMU, sincronización y calibración. [Código y licencia][basalt] |
| WiVRn y ALVR | WiVRn GPL-3.0 según GitHub. ALVR MIT | Usar un cliente PC VR en Quest 2 ejecutando Horizon OS mientras se investiga el port. El streaming ejercita Horizon OS y el cliente. [WiVRn][wivrn] · [ALVR][alvr] |

## Ruta de validación física

1. **Diagnóstico en Horizon OS.** Usar una Quest 2 de laboratorio. Registrar revisión de placa si es legible, capacidad, compilación, versión del kernel y estado de arranque. Con ADB ya autorizado, propiedades como `ro.product.device`, `ro.build.fingerprint`, `ro.boot.slot_suffix`, `ro.boot.verifiedbootstate`, `ro.boot.flash.locked` y `uname -r` orientan la comprobación. Un campo ausente queda como desconocido. Eliminar números de serie, cuentas y otros identificadores del informe público. Instalar la APK de ejemplo mediante el flujo oficial permite validar la aplicación sobre Horizon OS. [Configuración de Meta para ADB][adb-meta]
2. **Reproducir el árbol del kernel fuera del visor.** Fijar repositorio, compilación de herramientas y configuración combinada. Guardar el hash de fuentes, `.config`, `Module.symvers`, inventario de `.ko` y DTB/DTBO que se generen. Comparar con los datos observados antes. Revisar ABI y política de actualizaciones de la rama 4.19. [Receta de Meta][meta-readme] · [DTB/DTBO Hollywood][dt-make]
3. **Resolver arranque y recuperación.** Solicitar a Meta una vía autorizada de arranque o una imagen de desarrollo para *Quest 2*, con constancia del modelo y la compilación admitidos. Documentar el estado inicial y el procedimiento oficial de restauración de la unidad. Mientras falte una ruta comprobada y recuperable, el despliegue físico se mantiene en **D** y la validación continúa en el emulador. [Actualización Meta][update] · [Verified Boot][boot-flow]
4. **Probar periféricos en banco cuando se resuelva el arranque.** Priorizar consola y registros, apagado, sensores térmicos, ventilador, carga y USB. Continuar con almacenamiento, suspensión, pantalla, GPU, audio y radios. Registrar ajustes, panel, firmware, comandos y mediciones por unidad.
5. **Integrar XR físico.** Medir calibración óptica por IPD, tiempos de cámaras e IMU, pérdida de seguimiento y recuperación de pose, emparejamiento y háptica. Antes del uso inmersivo verificar la respuesta a fallos, los límites de juego y el comportamiento de la pantalla. Actualizar a **A** cada componente cuando OpenVR cuente con evidencia directa.

## Dependencias que condicionan la distribución

Las imágenes firmadas, firmware de radios, GPU, DSP, ISP y SyncBoss, bibliotecas y HAL del proveedor, datos de calibración y pila de tracking requieren inventario por versión y permisos por componente. Cuando exista una fuente autorizada, registrar origen, versión, SHA-256 y licencia en un manifiesto local. Los blobs y datos de fábrica de Quest 2 quedan fuera de la imagen de demostración y del repositorio. [Licencia del kernel][kernel-license] · [Conformidad OpenXR][xr-cts] · [Firmware de ath11k][ath11k-fw]

[meta-launch]: https://developers.meta.com/vr/blog/introducing-oculus-quest-2-the-next-generation-of-all-in-one-vr/
[qcom-launch]: https://www.qualcomm.com/news/releases/2020/09/qualcomm-snapdragon-xr2-platform-commercially-debuts-oculus-quest-2
[teardown-chip]: https://www.techinsights.com/products/ddt-2010-820
[ifixit]: https://www.ifixit.com/News/56892/oculus-quest-2-teardown-into-the-metaverse
[sku64]: https://www.bhphotovideo.com/c/product/1590536-REG/oculus_301_00350_01_quest_2_all_in_one_vr.html/overview
[sku]: https://developers.meta.com/vr/blog/build-the-next-generation-of-vr-mr-with-meta-quest-3/
[update]: https://www.meta.com/help/quest/software_update/
[adb-meta]: https://developers.meta.com/vr/documentation/native/android/mobile-device-setup/
[go-unlock]: https://developers.meta.com/vr/blog/unlocking-oculus-go/
[lifecycle]: https://developers.meta.com/vr/blog/meta-quest-2-quest-pro-end-of-feature-development-what-to-know/
[qcom-boot]: https://www.qualcomm.com/content/dam/qcomm-martech/dm-assets/documents/secure-boot-image-authentication_11.30.16.pdf
[locking]: https://source.android.com/docs/core/architecture/bootloader/locking_unlocking
[boot-flow]: https://source.android.com/docs/security/features/verifiedboot/boot-flow
[partitions]: https://source.android.com/docs/core/architecture/partitions
[recovery]: https://source.android.com/docs/core/architecture/bootloader/recovery-images
[avb]: https://android.googlesource.com/platform/external/avb/
[kernel]: https://github.com/facebookincubator/oculus-linux-kernel/commit/dba8278b20c9b22d8e90db5ce03825fb6238e4d2
[kernel-make]: https://github.com/facebookincubator/oculus-linux-kernel/blob/dba8278b20c9b22d8e90db5ce03825fb6238e4d2/Makefile
[meta-readme]: https://github.com/facebookincubator/oculus-linux-kernel/blob/dba8278b20c9b22d8e90db5ce03825fb6238e4d2/README.meta.md
[kona-config]: https://github.com/facebookincubator/oculus-linux-kernel/blob/dba8278b20c9b22d8e90db5ce03825fb6238e4d2/arch/arm64/configs/vendor/oculus_kona_defconfig
[hw-config]: https://github.com/facebookincubator/oculus-linux-kernel/blob/dba8278b20c9b22d8e90db5ce03825fb6238e4d2/arch/arm64/configs/vendor/oculus_hollywood_defconfig
[kernel-license]: https://github.com/facebookincubator/oculus-linux-kernel/blob/dba8278b20c9b22d8e90db5ce03825fb6238e4d2/COPYING
[dt]: https://github.com/facebookincubator/oculus-linux-kernel/tree/dba8278b20c9b22d8e90db5ce03825fb6238e4d2/arch/arm64/boot/dts/oculus/hollywood
[dt-make]: https://github.com/facebookincubator/oculus-linux-kernel/blob/dba8278b20c9b22d8e90db5ce03825fb6238e4d2/arch/arm64/boot/dts/oculus/hollywood/Makefile
[hw-dts]: https://github.com/facebookincubator/oculus-linux-kernel/blob/dba8278b20c9b22d8e90db5ce03825fb6238e4d2/arch/arm64/boot/dts/oculus/hollywood/hollywood.dtsi
[kona-dts]: https://github.com/facebookincubator/oculus-linux-kernel/blob/dba8278b20c9b22d8e90db5ce03825fb6238e4d2/arch/arm64/boot/dts/vendor/qcom/kona.dtsi
[gpu-dts]: https://github.com/facebookincubator/oculus-linux-kernel/blob/dba8278b20c9b22d8e90db5ce03825fb6238e4d2/arch/arm64/boot/dts/vendor/qcom/kona-gpu.dtsi
[kgsl]: https://github.com/facebookincubator/oculus-linux-kernel/tree/dba8278b20c9b22d8e90db5ce03825fb6238e4d2/drivers/gpu/msm
[ufs-dts]: https://github.com/facebookincubator/oculus-linux-kernel/blob/dba8278b20c9b22d8e90db5ce03825fb6238e4d2/arch/arm64/boot/dts/oculus/hollywood/hollywood-ufs.dtsi
[ufs-code]: https://github.com/facebookincubator/oculus-linux-kernel/blob/dba8278b20c9b22d8e90db5ce03825fb6238e4d2/drivers/scsi/ufs/ufs-qcom.c
[panel-dts]: https://github.com/facebookincubator/oculus-linux-kernel/blob/dba8278b20c9b22d8e90db5ce03825fb6238e4d2/arch/arm64/boot/dts/oculus/hollywood/hollywood-panel.dtsi
[display-code]: https://github.com/facebookincubator/oculus-linux-kernel/tree/dba8278b20c9b22d8e90db5ce03825fb6238e4d2/techpack/display
[as5510]: https://github.com/facebookincubator/oculus-linux-kernel/blob/dba8278b20c9b22d8e90db5ce03825fb6238e4d2/drivers/staging/oculus/as5510.c
[camera-dts]: https://github.com/facebookincubator/oculus-linux-kernel/blob/dba8278b20c9b22d8e90db5ce03825fb6238e4d2/arch/arm64/boot/dts/oculus/hollywood/hollywood-camera.dtsi
[camera-code]: https://github.com/facebookincubator/oculus-linux-kernel/tree/dba8278b20c9b22d8e90db5ce03825fb6238e4d2/techpack/camera
[sync-dts]: https://github.com/facebookincubator/oculus-linux-kernel/blob/dba8278b20c9b22d8e90db5ce03825fb6238e4d2/arch/arm64/boot/dts/oculus/hollywood/hollywood-syncboss.dtsi
[sync-code]: https://github.com/facebookincubator/oculus-linux-kernel/tree/dba8278b20c9b22d8e90db5ce03825fb6238e4d2/drivers/staging/oculus/mcu/syncboss
[oculus-code]: https://github.com/facebookincubator/oculus-linux-kernel/tree/dba8278b20c9b22d8e90db5ce03825fb6238e4d2/drivers/staging/oculus
[wifi-dts]: https://github.com/facebookincubator/oculus-linux-kernel/blob/dba8278b20c9b22d8e90db5ce03825fb6238e4d2/arch/arm64/boot/dts/oculus/hollywood/hollywood-qca6390.dtsi
[wifi-code]: https://github.com/facebookincubator/oculus-linux-kernel/tree/dba8278b20c9b22d8e90db5ce03825fb6238e4d2/drivers/staging/qcacld-3.0
[cnss]: https://github.com/facebookincubator/oculus-linux-kernel/tree/dba8278b20c9b22d8e90db5ce03825fb6238e4d2/drivers/net/wireless/cnss2
[usb-code]: https://github.com/facebookincubator/oculus-linux-kernel/blob/dba8278b20c9b22d8e90db5ce03825fb6238e4d2/drivers/usb/dwc3/dwc3-msm.c
[audio-dts]: https://github.com/facebookincubator/oculus-linux-kernel/blob/dba8278b20c9b22d8e90db5ce03825fb6238e4d2/arch/arm64/boot/dts/oculus/hollywood/hollywood-audio.dtsi
[audio-code]: https://github.com/facebookincubator/oculus-linux-kernel/tree/dba8278b20c9b22d8e90db5ce03825fb6238e4d2/techpack/audio
[fan-dts]: https://github.com/facebookincubator/oculus-linux-kernel/blob/dba8278b20c9b22d8e90db5ce03825fb6238e4d2/arch/arm64/boot/dts/oculus/hollywood/hollywood-fan.dtsi
[thermal-dts]: https://github.com/facebookincubator/oculus-linux-kernel/blob/dba8278b20c9b22d8e90db5ce03825fb6238e4d2/arch/arm64/boot/dts/oculus/hollywood/hollywood-thermal.dtsi
[linux-license]: https://docs.kernel.org/process/license-rules.html
[pca]: https://developers.meta.com/vr/documentation/unreal/unreal-mr-utility-kit-features/
[touch-profile]: https://registry.khronos.org/OpenXR/specs/1.1-khr/html/xrspec.html
[ath11k]: https://wireless.docs.kernel.org/en/latest/en/users/drivers/ath11k.html
[ath11k-fw]: https://wireless.docs.kernel.org/en/latest/en/users/drivers/ath11k/installation.html
[monado]: https://monado.freedesktop.org/
[monado-dev]: https://monado.freedesktop.org/developing-with-monado.html
[monado-license]: https://gitlab.freedesktop.org/monado/monado/-/blob/main/LICENSE
[openxr-sdk]: https://github.com/KhronosGroup/OpenXR-SDK-Source
[xr-cts]: https://www.khronos.org/conformance/adopters/conformant-products/openxr
[freedreno]: https://docs.mesa3d.org/drivers/freedreno.html
[mesa-license]: https://docs.mesa3d.org/license.html
[basalt]: https://gitlab.com/VladyslavUsenko/basalt
[wivrn]: https://github.com/WiVRn/WiVRn
[alvr]: https://github.com/alvr-org/ALVR
