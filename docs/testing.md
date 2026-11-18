# Informe de pruebas

Fecha de ejecución, 18 de noviembre de 2026. Anfitrión de pruebas Linux amd64, Docker 29.9.2, Compose 2.40.3 y Chromium 156.0.8078.79. Las pruebas del visor y los mandos emplean poses generadas por software. El equipo de pruebas carecía de /dev/kvm y de un visor físico conectado.

| Prueba | Resultado | Evidencia |
| --- | --- | --- |
| Construir, exportar y cargar el archivo Docker | OK. Tar Linux amd64 de 6 807 040 bytes. SHA-256 comprobado y arranque con healthcheck | [Docker, log y comandos](evidence/demo-test.log) |
| Navegador sobre contenedor real | OK. Sala y menú visibles, movimientos con teclado y ratón, poses separadas de los mandos, un objetivo alcanzado, registros reales y vista estrecha de 390 px | [Registro](evidence/demo-test.log) · [Captura de Chromium](evidence/browser.png) |
| Operaciones del panel Android | OK contra la API de prueba para carga binaria, apertura de ejemplo, visibilidad de estado y tratamiento de errores. El servidor demo devuelve 503 a una operación Android y 403 a un POST de otro origen | [Prueba Chromium y HTTP](evidence/demo-test.log) |
| Sesión OpenXR con Monado | OK en imagen de prueba. Lavapipe, dos cadenas de imágenes, sesión FOCUSED y poses de ambos mandos vinculadas. noVNC devolvió 200 y se capturó un fotograma. Los cambios finales de layout y salud quedan por probar en ejecución | [Evidencia OpenXR](../openxr/evidence/README.md) · [Captura de la ventana del compositor](../openxr/evidence/stereo.png) |
| Construir el perfil dev | OK. Imagen Linux amd64 de 1 129 730 379 bytes. El controlador vfs de Docker no dispuso de espacio para copiar el sistema de archivos durante la creación del contenedor | [Receta dev](../Dockerfile) |
| Compilar la APK de ejemplo | OK. APK de 12 691 bytes, firmas v2/v3 válidas, actividad de inicio identificada, API mínima 26 y destino 34 | [Salida de compilación y firma](evidence/android-build-apk.log) |
| Arranque Android, instalación y lanzamiento | Scripts implementados. Validación real pendiente. Los tres paquetes del SDK fijados se comprobaron en el catálogo oficial. Su descarga requiere aceptar los términos del SDK y el anfitrión de pruebas carece de KVM | [Android y prueba de arranque y APK](../android/README.md) |
| Compilación AOSP completa | Pendiente. Configuración y etiqueta de referencia identificadas. La máquina de pruebas tenía un total de 7,9 GiB de disco y unos 9,7 GiB de RAM, por debajo de los recursos para sincronizar y compilar AOSP | [Instrucciones del perfil build](windows.md#volúmenes-y-construcción-remota) |
| Windows, Intel Iris Xe y Quest 2 física | Pendiente la ejecución en ese equipo y en el visor. Compatibilidad física y recuperación documentadas como trabajo futuro | [Manual WSL2](windows.md) · [Matriz física](quest2-hardware.md) |

## Repetir la verificación

~~~bash
scripts/build-demo.sh
(cd dist && sha256sum -c openvr-demo-0.1.0-linux-amd64.tar.sha256)
docker image load --input dist/openvr-demo-0.1.0-linux-amd64.tar
docker compose up --wait demo
scripts/test-demo.sh
~~~

Para ejecutar la prueba de navegador en Linux con Chromium instalado y Node.js, instala las dependencias en un directorio aparte. Con OPENVR_URL se prueba la demo real. Sin esa variable se ejecuta un servidor de prueba para verificar también el contrato de la interfaz Android.

~~~bash
npm install --prefix /tmp/openvr-browser --no-save playwright@1.62.1
export OPENVR_PLAYWRIGHT=/tmp/openvr-browser/node_modules/playwright/index.mjs
export OPENVR_CHROMIUM=/usr/bin/chromium
OPENVR_URL=http://127.0.0.1:8080 node scripts/test-browser.mjs
node scripts/test-browser.mjs
~~~

La APK publicada usa una clave de desarrollo. Sus bytes incluyen la firma y la clave se genera localmente al reconstruir. La verificación SHA-256 identifica el archivo descargado concreto.
