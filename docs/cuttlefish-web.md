# OpenVR OS desde el laboratorio web

El flujo tiene dos etapas. Se arranca la **imagen AOSP de OpenVR** en Cuttlefish y, cuando el invitado está listo, se instalan **aplicaciones APK** mediante ADB. El navegador muestra el estado y enlaza al escritorio del invitado. Inicia Cuttlefish desde Linux con el script de arranque. [Compilar y arrancar el invitado](../aosp/README.md)

## Conectar el navegador al invitado

En el mismo anfitrión Linux x86‑64 que ejecuta Cuttlefish, abre una terminal en el repositorio. Usa Go 1.26 o posterior. Configura RUN_DIR con el directorio que utilizaste para arrancar el invitado.

~~~bash
run_dir=/ruta/al/guest-openvr
mkdir -p "$run_dir/web-results"
OPENVR_GUEST=cuttlefish \
OPENVR_ADB="$run_dir/bin/adb" \
OPENVR_ANDROID_SERIAL=127.0.0.1:6520 \
OPENVR_RESULTS="$run_dir/web-results" \
go run ./cmd/openvr
~~~

Si el puerto 8080 está ocupado, agrega OPENVR_HTTP_PORT con otro puerto. El servidor escucha en la interfaz local y utiliza solo el transporte ADB de bucle local que indiques. Comprueba que ADB tenga conectado el alias 127.0.0.1:6520 que crea el script de arranque.

1. Abre [localhost:8080](http://localhost:8080). La tarjeta **Sistema Android** muestra OpenVR OS en Cuttlefish y el estado de arranque del invitado.
2. Con **ADB listo**, abre la pantalla del invitado en [localhost:8443](https://localhost:8443/). En la sección **Instalar una aplicación**, elige una APK de hasta 256 MiB y pulsa **Instalar**.
3. En la pantalla del invitado, abre **Biblioteca**, busca la aplicación y ábrela. En **Registros → Android** se puede consultar logcat del invitado.

El servidor habilita las operaciones cuando ADB informa que Android terminó de arrancar y confirma el producto OpenVR y la ABI x86‑64. El perfil Docker demo sigue ejecutando la sala web. El perfil dev ofrece Android Emulator con noVNC y sirve para probar aplicaciones en su propio Android. [Perfil dev y WSL2](windows.md#android-y-apk)

## Verificación en este entorno

Se verificaron el servidor Go y las transiciones de la interfaz en Chromium con un ADB y una API simulados para las operaciones Android. La compilación completa de la imagen y su arranque real en Cuttlefish siguen pendientes. [Pruebas del panel](evidence/lab-guest-workflow.log) · [Estado de las pruebas](project-status.md)
