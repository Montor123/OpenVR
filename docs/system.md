# OpenVR OS

OpenVR desarrolla un sistema autónomo para Quest 2 basado en Android Open Source Project (AOSP) sobre Linux. El objetivo es arrancar de forma recuperable, instalar y ejecutar APK propias, y ofrecer una sesión OpenXR local. El producto Android x86_64 de Cuttlefish y el kernel ARM64 Hollywood son dos pasos de desarrollo hacia ese objetivo. Un invitado virtual usa sus propios controladores y kernel. [Arquitectura y compatibilidad](architecture.md) · [Estado y criterios de aceptación](project-status.md)

## Producto Android virtual

**openvr_cf_x86_64_phone** fija AOSP `android-14.0.0_r75`, se basa en el teléfono virtual de Cuttlefish y conserva su kernel, HAL y particiones. Instala el lanzador Android 2D `org.openvr.launcher` en la partición `product` y declara su actividad HOME como preferida. La imagen del invitado y las herramientas host se exportan desde la misma compilación. El procedimiento comprueba tamaños, identidad del build y SHA-256 antes de extraer y arrancar. [Construcción y arranque AOSP](../aosp/README.md)

El lanzador ofrece Inicio con favoritos y recientes, Biblioteca con búsqueda y filtros Apps/Juegos, y Ajustes con información de batería, conexión y almacenamiento junto a los accesos del sistema. Guarda favoritos y recientes en las preferencias privadas del usuario Android. Admite táctil, teclado y controles de navegación de gamepad. El panel de OpenVR muestra el estado del sistema y permite instalar APK por ADB en un invitado Cuttlefish ya iniciado. El panel se enlaza al bucle local, exige un serial ADB de bucle local y comprueba producto y ABI. La aplicación instalada se abre desde la Biblioteca del lanzador. El arranque se ejecuta en el anfitrión Linux mediante las herramientas de Cuttlefish, que abren sus propios puertos. [Arranque y puertos](../aosp/README.md#arrancar-y-comprobar-cuttlefish) · [Lanzador](../aosp/launcher/README.md) · [Panel de Cuttlefish](cuttlefish-web.md)

La verificación compiló la edición actual del lanzador con las API públicas de Android 34, enlazó recursos y manifiesto con AAPT2 y generó bytecode con D8. Las pruebas de herramientas y del contrato ADB con datos de prueba permiten revisar la integración sin virtualización. La compilación AOSP completa, el arranque del invitado, la selección inicial de HOME y el recorrido visual de instalación y apertura de una APK requieren aún una ejecución real de ese producto. [Evidencia del módulo](../aosp/launcher/verification.md) · [Matriz de pruebas y bloqueos](project-status.md)

## Entornos de ejecución

- **Windows con Docker Desktop y WSL2.** La demo web usa Canvas y abre el laboratorio sin visor físico ni GPU dedicada. El perfil dev usa Android Emulator de referencia para pruebas de APK. El perfil OpenXR usa Linux y Monado con seguimiento simulado. Cada entorno tiene su propio registro de pruebas. [Manual Windows](windows.md) · [Evidencia de las pruebas](testing.md)
- **Linux x86_64 para el producto AOSP.** La guía vigente de AOSP usa como referencia 400 GB libres y 64 GB de RAM para compilar la rama actual. El consumo exacto de la revisión r75 debe medirse con un build completo. Para arrancar Cuttlefish hacen falta KVM accesible y el software anfitrión que indica AOSP. [Requisitos de AOSP](https://source.android.com/docs/setup/start/requirements) · [Preparación del anfitrión Cuttlefish](https://source.android.com/docs/devices/cuttlefish/get-started)
- **Quest 2 física.** El producto ARM64 requiere autoridad de arranque y recuperación en una unidad identificada, una configuración compatible de kernel, y los controladores, firmware y servicios vendor que se validen para esa unidad. [Integración física](quest2-integration.md) · [Matriz de hardware](quest2-hardware.md)

## Kernel Hollywood

Se compiló Linux 4.19.325 desde la revisión de Meta fijada por el proyecto. El enlace produjo un `Image` ARM64 de 30 371 856 bytes, 27 módulos, `Module.symvers` y los nueve archivos de Device Tree. Se verificaron los 40 hashes del manifiesto. La configuración y los árboles coinciden con la compilación de Device Tree por separado. Los diagnósticos de prototipos heredados de Clang 17 en dos objetos de Wi-Fi se conservaron como advertencias. [Receta del kernel](../kernel/README.md) · [Salida de compilación](evidence/hollywood-compile.log) · [Manifiesto de artefactos](evidence/hollywood-compile.sha256)

La prueba offline aplicó con libfdt 15 de 18 combinaciones entre los tres DTB Kona y los seis DTBO Hollywood. POC2 dio `FDT_ERR_NOTFOUND` en las tres bases por los símbolos `extcon_storage_cd` y `ufshc_card`. DTC también reportó advertencias de GPIO de audio y una entrada de interrupción en POC2. La revisión y el overlay de una unidad siguen sujetos a su inventario de placa y firmware. [Salida de DTC](evidence/hollywood-dtbs.log) · [Hashes DTB y DTBO](evidence/hollywood-dtbs.sha256) · [Comprobación de overlays](evidence/hollywood-overlay-check.log)

En Horizon OS con ADB autorizado, el inventario PowerShell recoge compilación, kernel, placa, ABI y los campos de estado de arranque que el sistema publique. La prueba usó un ADB simulado y PowerShell 7. El serial sirve para seleccionar el destino y se omite del JSON. Para una primera imagen física, correlacionar la revisión con los nodos DSI, reguladores, retroiluminación y calibración. [Inventario del visor](../device/README.md) · [Pantalla y hardware](hollywood-display.md)

## Uso local sin cuenta

La demo web carga sus recursos del servidor local. El lanzador AOSP trabaja con actividades y Ajustes del usuario Android. El panel envía APK al gestor de paquetes por ADB local y los registros quedan en el directorio de resultados o en el volumen. Las descargas de SDK, dependencias, imágenes y fuentes corresponden a la preparación de los entornos. En Horizon OS, ADB en el dispositivo físico usa el flujo de modo desarrollador de Meta.

La sincronización en la nube queda como función opcional de una etapa posterior. La sesión local y las APK deben seguir disponibles con el equipo desconectado. [Criterios offline y plan de sincronización](project-status.md#funcionamiento-local-y-sincronización-opcional)
