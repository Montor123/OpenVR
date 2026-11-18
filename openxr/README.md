# OpenXR nativo en Linux

Este módulo ejecuta Monado y la aplicación OpenXR `hello_xr` de Khronos en un escritorio remoto local. El driver QWERTY de Monado proporciona un visor y dos mandos simulados. Mesa renderiza en CPU mediante lavapipe. El módulo funciona por separado de la habitación y el menú web y del emulador Android.

## Inicio en Docker Desktop con WSL2

Activa el motor WSL2 y los contenedores Linux en Docker Desktop. Ejecuta estos comandos desde la raíz del repositorio con PowerShell o WSL.

```powershell
docker compose -f openxr/compose.yaml up --build --wait --wait-timeout 120
docker compose -f openxr/compose.yaml ps
```

Cuando el servicio esté saludable, abre [noVNC en localhost](http://127.0.0.1:6081/vnc.html?autoconnect=true&resize=scale). El servicio publica noVNC únicamente en la interfaz de bucle local. Mantén el enlace de red local porque el escritorio usa VNC sin contraseña. Si el puerto está ocupado, configura `OPENVR_XR_PORT` y usa ese puerto en el navegador.

La ventana titulada **Monado** muestra los cubos estereoscópicos y la representación de los mandos de `hello_xr`. Para controlar los dispositivos simulados, enfoca la ventana de diagnóstico **Monado!** y conserva visible la ventana del compositor. Si se superponen, mueve o redimensiona la de diagnóstico. El teclado y el ratón se procesan en la ventana de diagnóstico.

| Entrada | Función |
| --- | --- |
| W, A, S, D, Q, E | Trasladar el visor. Q baja y E sube. |
| Flechas o arrastre con el botón secundario | Girar el dispositivo seleccionado. |
| Ctrl izquierdo + los controles de movimiento | Mover o girar el mando izquierdo. |
| Alt izquierdo + los controles de movimiento | Mover o girar el mando derecho. |
| Botón izquierdo y botón central | Pulsar gatillo y agarre del mando seleccionado. |
| C y R | Alternar el seguimiento del visor y restablecer la pose de los mandos. |

Las teclas corresponden a posiciones físicas QWERTY. Si el navegador captura Alt, usa la opción de modificadores del panel de noVNC. La tecla N envía la acción de menú del mando. En `hello_xr` esa acción termina la sesión. Reinicia el módulo para volver a entrar.

```powershell
docker compose -f openxr/compose.yaml restart xr
```

## Diagnóstico

```powershell
docker compose -f openxr/compose.yaml logs xr
docker compose -f openxr/compose.yaml exec xr tail -n 30 /data/results/hello-xr.log
docker compose -f openxr/compose.yaml cp xr:/data/results ./resultados-openxr
docker compose -f openxr/compose.yaml down
```

El volumen `xr-results` conserva los registros de la última ejecución y `packages.tsv` con las versiones instaladas. El arranque comprueba el servidor X, la disponibilidad del dispositivo Vulkan y el socket de Monado. La comprobación de salud espera el estado OpenXR `FOCUSED` y una respuesta del servidor noVNC.

La imagen de prueba amd64 midió 928 942 517 bytes de acuerdo con `docker image inspect`. El almacenamiento transitorio de construcción depende del controlador Docker. El compositor muestra avisos de fotogramas tardíos con el renderizado por CPU. La prueba sirve para validar la ejecución y las vinculaciones OpenXR, sin una medición de rendimiento. La configuración usa `Vulkan2` de `hello_xr`, que negocia extensiones con el runtime usando `XR_KHR_vulkan_enable2`. La ruta `Vulkan` antigua falló porque el controlador de CPU carece de `VK_KHR_external_semaphore_fd`.

## Prueba del 18 de noviembre de 2026

Prueba ejecutada con Docker Engine 29.9.2 en Linux amd64. Construimos la imagen, ejecutamos el lanzador con el manifiesto lavapipe de Trixie y comprobamos los resultados siguientes.

- Monado 25.0.0 creó un visor QWERTY y dos mandos QWERTY. La aplicación detectó poses de ambos mandos con el perfil de interacción de Microsoft Motion Controller. [Inicio de Monado](evidence/monado-start.log) · [Registro OpenXR](evidence/hello-xr.log)
- `hello_xr` creó dos cadenas de imágenes de 384 × 432 y alcanzó `XR_SESSION_STATE_FOCUSED`. Vulkan reportó llvmpipe como dispositivo CPU. [Registro Vulkan](evidence/vulkan.log)
- La página de noVNC respondió y una conexión al WebSocket local completó RFB 3.8 y recuperó el fotograma. La captura corresponde a la ventana real de renderizado y está recortada al compositor. [Registro noVNC](evidence/novnc.log) · [Captura](evidence/stereo.png)

La verificación utilizó el lanzador corregido montado en un contenedor creado desde la imagen de prueba. La regla de colocación de ventanas y la comprobación automática de salud se incorporaron después. Falta verificar cambios de pose de cada mando de forma cuantitativa y probar en Windows con WSL2. Las poses son sintéticas y el runtime reporta `OrientationTracking=False PositionTracking=False` para el sistema QWERTY. Se excluyen el rastreo real, passthrough, las ópticas y los servicios de Meta.

## Componentes y código fuente

La imagen fija el digest de Debian Trixie y las versiones de los paquetes directos en el Dockerfile. APT resuelve las dependencias transitivas contra los repositorios de Debian y registra las versiones resultantes en el inventario.

| Componente | Versión | Licencia principal y fuente |
| --- | --- | --- |
| Monado y driver QWERTY | 25.0.0+dfsg-2 | BSL-1.0. [Paquete y fuente Debian](https://packages.debian.org/source/trixie/monado) · [Controles QWERTY v25.0.0](https://gitlab.freedesktop.org/monado/monado/-/blob/v25.0.0/src/xrt/drivers/qwerty/qwerty_sdl.c) |
| OpenXR loader y `hello_xr` | 1.1.47~ds-2 | Apache-2.0 para el ejemplo. [Código de Khronos de 2025](https://github.com/KhronosGroup/OpenXR-SDK-Source/tree/release-1.1.47/src/tests/hello_xr) · [Paquete y fuente Debian](https://packages.debian.org/source/trixie/openxr-sdk-source) |
| Mesa y lavapipe | 25.0.7-2+deb13u1 | MIT y otras. [Fuente Debian](https://packages.debian.org/source/trixie/mesa) |
| noVNC y websockify | 1:1.6.0-2 y 0.12.0+dfsg1-4+b1 | MPL-2.0 y LGPL-3.0, con licencias adicionales en los paquetes. [noVNC](https://packages.debian.org/source/trixie/novnc) · [websockify](https://packages.debian.org/source/trixie/websockify) |
| Xvfb, x11vnc y Fluxbox | 2:21.1.16-1.3+deb13u4, 0.9.17-1 y 1.3.7-1+b1 | Licencias por paquete en `/usr/share/doc/<paquete>/copyright`. [Xorg](https://packages.debian.org/source/trixie/xorg-server) · [x11vnc](https://packages.debian.org/source/trixie/x11vnc) · [Fluxbox](https://packages.debian.org/source/trixie/fluxbox) |
