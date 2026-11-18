# Inventario de componentes

Consulta el 18 de noviembre de 2026. Los binarios de Google y el firmware de Meta se quedan fuera de la release. Los paquetes del escritorio y la demo XR se instalan localmente al construir sus imágenes.

| Componente | Versión o referencia | Licencia y distribución |
| --- | --- | --- |
| Código OpenVR y Java del ejemplo | 0.1.0 | MIT. Código en este repositorio y APK de ejemplo firmada para desarrollo. |
| Servidor y biblioteca estándar Go | 1.26.8, imagen de compilación Alpine 3.23 fijada por digest | BSD-3-Clause y avisos de componentes de Go. El contenedor scratch conserva los avisos de Go y MIT. [Código de Go](https://github.com/golang/go/tree/go1.26.8) |
| Sala VR web | Canvas 2D, JavaScript y CSS nativos | MIT. Sin SDK, librerías web ni fuentes remotas. |
| Escritorio Android | Debian Bookworm, snapshot 2026-10-01, Python 3.12.13, Xvfb, Openbox, x11vnc, noVNC, websockify | Licencias por paquete en /usr/share/doc; noVNC MPL-2.0, websockify LGPL-3.0. Lista resuelta en /usr/local/share/openvr-dev-packages.tsv. [Snapshot Debian](https://snapshot.debian.org/archive/debian/20261001T000000Z/) · [noVNC](https://github.com/novnc/noVNC) |
| Emulador, ADB, API Java y D8 | Versiones fijadas en android/setup.sh y android/build-apk.sh | Licencia SDK Google para binarios de emulador y repositorio Android. API Java Apache-2.0 y D8 BSD-3-Clause. [Inventario Android](../android/README.md#versiones-y-fuentes) |
| OpenXR, muestra y runtime | Debian Trixie, OpenXR 1.1.47, Monado 25.0.0, Mesa 25.0.7 | Khronos Apache-2.0, Monado Boost-1.0, Mesa bajo licencias libres por componente. [Perfil nativo](../openxr/README.md) |
| AOSP de compilación | android-14.0.0_r75. Repo v2.54 fijado al commit 97dc5c1bd9527c2abe2183b16a4b7ef037dc34a7 | AOSP admite Apache-2.0 como licencia preferida. El kernel Linux y otros componentes tienen licencias propias. [Licencias de AOSP](https://source.android.com/docs/setup/about/licenses) |
| Kernel Meta Quest 2 | Linux 4.19.325, árbol Meta Hollywood fijado en la matriz | Linux GPL-2.0 y avisos por fichero. Fuentes públicas documentadas. [Matriz del hardware](quest2-hardware.md) |
