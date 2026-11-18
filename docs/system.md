# OpenVR OS

El objetivo es un sistema Android abierto para Quest 2 que arranque de forma recuperable, ejecute APK propias y disponga de una sesión OpenXR local. El primer incremento integra un producto Android para Cuttlefish y reproduce por separado el kernel ARM64 publicado por Meta para Hollywood.

| Hito | Estado | Evidencia necesaria para darlo por completado |
| --- | --- | --- |
| Producto Android virtual | Receta de compilación, lanzador HOME y verificador ADB implementados | Compilar el producto, arrancarlo con su kernel virtual y verificar HOME, Ajustes e instalación de una APK |
| Device Tree Hollywood | Probado con el árbol Linux 4.19.325 publicado por Meta | Se generaron tres DTB Kona y seis DTBO Hollywood con sus SHA‑256 |
| Configuración de pantalla Hollywood | Identificadas las variantes candidatas, selección, alimentación, retroiluminación e IPD | Identificar en un visor la revisión, el panel activo y sus dependencias en el sistema de esa unidad |
| Entorno XR | Monado ha abierto una sesión OpenXR en Linux con entrada sintética | Portar o integrar un runtime Android y probar una sesión con gráficos e interacción en el producto |
| Arranque propio en Quest 2 | Pendiente | Una ruta admitida y recuperación comprobada en una unidad concreta, antes de probar una imagen física |
| Sistema VR físico | Pendiente | Arranque, pantalla, gráficos, audio y energía estables, seguimiento, mandos, APK y OpenXR verificados |

## Probar Android como sistema

El producto **openvr_cf_x86_64_phone** conserva el kernel y los dispositivos virtuales de Cuttlefish. Integra el lanzador, mantiene las aplicaciones de sistema y exporta el invitado junto a sus herramientas host. La ruta virtual nos permite verificar las funciones Android sin esperar a los controladores del visor. [Construcción, arranque y verificador del producto AOSP](../aosp/README.md)

El lanzador enumera apps instaladas, permite abrirlas y expone Ajustes. AAPT2 validó sus recursos y manifiesto con la API 34. Java compiló y D8 generó bytecode Android. La selección HOME y la apertura de aplicaciones siguen pendientes en un invitado real. [Verificación del lanzador](../aosp/launcher/verification.md)

Este entorno tiene dos CPU disponibles para compilación, 8 GiB de límite de memoria y una capacidad de disco aproximada de 8 GB. Una sincronización y compilación completas de AOSP requieren un anfitrión de mayor capacidad. Para arrancar Cuttlefish se necesita además KVM. [Requisitos de AOSP](https://source.android.com/docs/setup/start/requirements) · [Requisitos de Cuttlefish](https://source.android.com/docs/devices/cuttlefish/get-started)

## Preparar el port físico

El kernel Hollywood se construye con sus fragmentos de Meta y herramientas de AOSP fijadas por revisión. La prueba local de Device Tree completó Kconfig y generó los tres DTB y seis DTBO. DTC reportó advertencias sobre GPIO de audio y una entrada de interrupción en POC2. Con libfdt se pudieron aplicar quince de las dieciocho combinaciones de DTB base y overlay. POC2 falló en las tres bases porque faltan los símbolos extcon_storage_cd y ufshc_card. Esa prueba de estructura no determina el overlay que corresponde a un visor. [Receta del kernel](../kernel/README.md) · [Salida de DTC](evidence/hollywood-dtbs.log) · [SHA‑256](evidence/hollywood-dtbs.sha256) · [Prueba offline de overlays](evidence/hollywood-overlay-check.log)

Con el visor operativo y ADB autorizado, el inventario PowerShell registra la compilación, el kernel, la placa, la ABI y los campos de estado de arranque que Horizon OS publique. La prueba usó ADB simulado y PowerShell 7. Los números de serie se usan para seleccionar el dispositivo y se omiten del JSON. [Inventario del visor](../device/README.md)

En el paso de integración física, hay que correlacionar el inventario con la revisión del árbol y la selección del panel. Para obtener una primera imagen en pantalla se necesita la ruta DSI, los reguladores y la retroiluminación. Para presentar una escena XR se añaden gráficos, composición, sincronización y calibración. Los controladores de kernel, firmware y servicios Android se verifican por separado contra esa unidad. [Pantalla de Hollywood](hollywood-display.md) · [Matriz de hardware](quest2-hardware.md)

### Criterio del primer arranque físico

Una unidad de laboratorio identificada tiene que aceptar el arranque por una vía documentada y volver al firmware original de forma reproducible. La primera prueba debe registrar la compilación que arranca, una consola o registros del sistema y el estado tras la recuperación. A partir de esa verificación se pueden preparar el producto AOSP ARM64 para Hollywood y las pruebas de hardware en orden de dependencia.
