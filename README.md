# OpenVR

Laboratorio abierto para investigar un sistema de realidad virtual basado en AOSP para Meta Quest 2. Esta primera versión incluye una sala VR en el navegador, un laboratorio Android para APK y una prueba OpenXR nativa con Monado. Se ejecuta en un PC sin conectar el visor.

## Desarrollo de OpenVR OS

El producto Android de desarrollo usa AOSP 14 en Cuttlefish e incluye el lanzador OpenVR. En paralelo se compiló el kernel ARM64 Hollywood de Meta, con 27 módulos y los árboles de dispositivos verificados por SHA‑256. Sigue pendiente arrancar el producto AOSP completo y validar una ruta de arranque para Quest 2.

- [Estado de OpenVR OS y verificación](docs/system.md)
- [Compilar y exportar el producto AOSP](aosp/README.md)
- [Compilar el kernel Hollywood](kernel/README.md)
- [Leer el inventario del visor en Windows](device/README.md)

## Inicio rápido en Windows

Con Docker Desktop en modo Linux y WSL2, descarga la imagen y su SHA-256 desde [OpenVR 0.1.0](https://github.com/Montor123/OpenVR/releases/tag/v0.1.0). El archivo tar mide **6 807 040 bytes**. En PowerShell:

~~~powershell
Get-FileHash .\openvr-demo-0.1.0-linux-amd64.tar -Algorithm SHA256
docker load -i .\openvr-demo-0.1.0-linux-amd64.tar
docker run -d --name openvr-demo -p 127.0.0.1:8080:8080 --read-only --mount type=volume,source=openvr-demo-results,target=/data/results openvr-demo:0.1.0
~~~

Compara la salida de Get-FileHash con el fichero SHA-256 antes de cargar. Abre [localhost:8080](http://localhost:8080). Usa **WASD** y arrastra con el ratón para mover el visor. Con **1** o **2** seleccionas un mando virtual. Pulsa **M** para abrir el menú y elige **Prueba de seguimiento**.

Para reconstruir la imagen desde una copia del repositorio:

~~~powershell
docker compose up --build --detach --wait demo
~~~

Para activar el entorno Android, abre el [manual de Windows y WSL2](docs/windows.md). La descarga inicial incluye la sala web. Los perfiles de Android y OpenXR se construyen por separado.

| Entorno | Qué puedes probar | Estado |
| --- | --- | --- |
| Demo web | Visor y mandos simulados, sala 3D, menú, ejercicio y registros | Probado en Chromium sobre Docker, con renderizado Canvas |
| OpenXR nativo | Sesión real OpenXR en Linux, dispositivo QWERTY de Monado, dos mandos y muestra Khronos | Probado con Vulkan por software |
| Android | Compilar una APK de ejemplo, preparar Android 14 x86_64, instalar con ADB y acceder al escritorio en el navegador | APK compilada y firma verificada. El arranque y la instalación en el invitado quedan pendientes de ensayo |
| AOSP | Descargar la revisión fijada y compilar una imagen de referencia Cuttlefish | Scripts de preparación y compilación. Compilación completa pendiente |
| Quest 2 | Evaluar el kernel de Meta, el hardware y la cadena de arranque | Investigación documentada. Arranque autónomo del port pendiente |

- [Arquitectura y compatibilidad de aplicaciones](docs/architecture.md)
- [Quest 2, matriz del hardware y ruta de validación física](docs/quest2-hardware.md)
- [Windows, WSL2, instalación de APK y ADB](docs/windows.md)
- [Android, versiones, fuentes y prueba de ejecución](android/README.md)
- [OpenXR con Monado](openxr/README.md)
- [Pruebas y evidencia](docs/testing.md)
- [Componentes, versiones y licencias](docs/components.md)

El código original se publica con [licencia MIT](LICENSE).
