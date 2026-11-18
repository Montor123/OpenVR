# Arquitectura de OpenVR

Evaluación del 18 de noviembre de 2026. La arquitectura principal propuesta para el visor es **AOSP sobre Linux, con un lanzador local y una integración OpenXR específica de la plataforma**. Android utiliza un kernel Linux y su espacio de usuario incluye ART, el gestor de paquetes, Binder, SurfaceFlinger y las interfaces de hardware del sistema. En este proyecto «Linux + Android» significa esa pila AOSP en el sistema objetivo, más Linux de propósito general en las herramientas del laboratorio.

| Alternativa | Ventaja | Trabajo y dependencias |
| --- | --- | --- |
| AOSP + lanzador VR | Android gestiona APK, permisos, ABI, actividades, gráficos y ADB de forma nativa. Es la base elegida para la compilación del sistema | El visor requiere ruta de arranque, kernel exacto, compatibilidad vendor/HAL, compositor XR, seguimiento y puesta a punto |
| Linux + Monado + Android en contenedor | DP/X11/Wayland, Monado y Vulkan resultan prácticos para probar OpenXR en un PC | Waydroid requiere Binder y un entorno Linux/Wayland adecuado. Habría que adaptar gráficos, ventanas, sensores y ciclo de vida Android a la experiencia VR en Quest 2 |
| Linux anfitrión + Android virtualizado | Aísla pruebas de Android y permite reproducir el laboratorio en WSL2 | La comunicación entre compositor, aplicación Android y seguimiento añade latencia y dependencias. Se utiliza en el banco de pruebas |

[Arquitectura de AOSP](https://source.android.com/docs/core/architecture) · [Waydroid](https://docs.waydro.id/) · [Monado](https://monado.freedesktop.org/) · [Registro de OpenXR](https://registry.khronos.org/OpenXR/).

~~~mermaid
flowchart LR
    Browser["Navegador en Windows"]
    subgraph Lab["Docker Desktop · WSL2 · laboratorio"]
      Web["Sala y mandos simulados · Canvas"]
      Panel["Panel local · API HTTP"]
      Desk["noVNC · escritorio Linux"]
      ADB["ADB · emulador Android"]
      APK["Android 14 x86_64 · APK de ejemplo"]
      XR["Monado · OpenXR · Vulkan por software"]
      CF["Compilación AOSP · Cuttlefish"]
      Web --- Panel
      Panel --> ADB --> APK
      Desk --> ADB
    end
    Browser --> Web
    Browser --> Desk
    Browser --> XR
    subgraph Quest["Quest 2 física · port pendiente"]
      Boot["Cadena de arranque y recuperación"]
      HAL["Linux Hollywood · firmware y HAL"]
      System["AOSP ARM64 · lanzador · runtime OpenXR"]
      Boot --> HAL --> System
    end
    CF -. "referencia de compilación" .-> System
~~~

### Superficies de prueba

- **Sala web.** Canvas dibuja una vista en perspectiva. El teclado y el ratón modifican las poses del visor y de cada mando. El menú abre un ejercicio interactivo. El renderizado Canvas funciona sin GPU dedicada. Las poses permanecen dentro de la página.
- **OpenXR nativo.** Monado ejecuta OpenXR en Linux. Su controlador QWERTY aporta poses de visor y mandos a la muestra Khronos. Vulkan por software renderiza las vistas y noVNC transmite la ventana de espejo.
- **Android.** El emulador usa un kernel Android invitado en QEMU. Docker ejecuta los procesos del laboratorio sobre el kernel de WSL2. El panel usa ADB para instalar una APK local en el invitado y abrir el ejemplo. El escritorio permite interactuar con las actividades Android. La prueba de referencia de AOSP Cuttlefish es una ruta de compilación aparte.
- **Integración pendiente.** El futuro runtime Android necesitará integrar OpenXR Loader, descubrimiento de runtime, sesiones Android, superficies y entrada de seguimiento. En Cuttlefish o el emulador deberá demostrarse una sesión XR de una APK propia y su ciclo de vida. Compartir poses entre servicios podría servir en una prueba posterior. Aún quedan por validar sincronización, compositor y latencia.

[OpenXR en Android](https://github.com/KhronosGroup/OpenXR-SDK-Source/tree/main/src/loader) · [Cuttlefish](https://source.android.com/docs/devices/cuttlefish) · [Emulador Android](https://developer.android.com/studio/run/emulator).

### Compatibilidad de aplicaciones

| Aplicación | Laboratorio actual | Objetivo para hardware |
| --- | --- | --- |
| APK 2D Java/Kotlin | Ejemplo API 26–34 sin bibliotecas nativas. La instalación usa el Package Manager del invitado. Aplicaciones 2D aparecen en el escritorio de pruebas | Actividades Android disponibles en el lanzador. Composición de ventanas 2D en VR por integrar |
| APK con JNI x86_64 | Depende de API, permisos, gráficos y servicios requeridos | La arquitectura objetivo es ARM64 |
| APK nativa arm64-v8a | Ejecución pendiente en una VM ARM64 | Requiere AOSP ARM64 y verificación de bibliotecas, GPU y API |
| APK OpenXR | API real probada en Linux con hello_xr. La sesión de una APK OpenXR en Android queda por integrar | Cargador, runtime y validación de extensiones y gráficos por aplicación |
| APK vinculada a Meta o a Play | Depende de servicios o componentes ajenos al laboratorio | El diseño local prescinde de las cuentas de Meta y de Play. Compatibilidad específica sin verificar |

[ABI de Android NDK](https://developer.android.com/ndk/guides/abis) · [Android Package Manager y ADB](https://developer.android.com/tools/adb).

### Recuperación y diagnóstico

Los volúmenes conservan AVD, SDK, descargas y evidencia. El servidor expone salud HTTP, y el perfil dev recoge la salida del emulador, el historial de ADB y la captura al completar la prueba. En un visor físico, primero se tendría que demostrar una ruta de arranque identificada y una recuperación reproducible para la revisión exacta. El plan de hardware fija los pasos de validación y los componentes propietarios que bloquean ese trabajo. [Matriz y plan físico](quest2-hardware.md).
