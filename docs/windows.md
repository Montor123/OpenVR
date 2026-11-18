# Inicio en Windows con Docker Desktop y WSL2

1. Comprueba que Windows usa WSL2 y que Docker Desktop ejecuta contenedores Linux. Activa **Use the WSL 2 based engine** en Docker Desktop. La demo puede funcionar en Chrome o Edge sin GPU dedicada. [Docker Desktop con WSL2](https://docs.docker.com/desktop/features/wsl/) · [Guía de WSL](https://learn.microsoft.com/windows/wsl/install).
2. Clona el repositorio. Si vas a editar código con herramientas Linux, guárdalo en el sistema de archivos de tu distribución WSL2. Para una prueba en PowerShell también puedes utilizar una copia en NTFS.
3. Carga la imagen de la [release](https://github.com/Montor123/OpenVR/releases/tag/v0.1.0) según el README. También puedes construir el perfil demo. Si el puerto 8080 de Windows está ocupado, exporta OPENVR_PORT con un puerto libre antes de usar Compose.

~~~powershell
wsl --status
docker info --format '{{.OSType}}'
docker compose version
git clone https://github.com/Montor123/OpenVR.git
Set-Location OpenVR
.\scripts\run.ps1 demo
~~~

El script de importación verifica SHA-256 y arranca el contenedor.

~~~powershell
.\scripts\load-demo.ps1 -Archive .\openvr-demo-0.1.0-linux-amd64.tar -Checksum .\openvr-demo-0.1.0-linux-amd64.tar.sha256
~~~

## Android y APK

Los perfiles demo y dev comparten el puerto de la interfaz. Para cambiar al dev, detén el contenedor de demo que hayas arrancado con Compose o con docker run.

~~~powershell
docker compose stop demo
# Para el contenedor de docker run, usa docker stop openvr-demo.
.\scripts\run.ps1 dev
.\scripts\run.ps1 android-build
~~~

El escritorio estará en [localhost:6080](http://localhost:6080/vnc.html?autoconnect=true&resize=scale). Lee la licencia del SDK. Si la aceptas, ejecuta la descarga y luego inicia Android.

~~~powershell
.\scripts\run.ps1 android-setup -AcceptAndroidSdk
.\scripts\run.ps1 android-start
~~~

Deja esa terminal abierta. En otra terminal, ejecuta la prueba. Con la interfaz web puedes pulsar **Instalar y abrir ejemplo**, seleccionar una APK propia y consultar registros. La APK que instales aparecerá en el lanzador del invitado si declara una actividad de inicio. ADB se ejecuta dentro del contenedor.

~~~powershell
.\scripts\run.ps1 android-test
docker compose exec dev /data/android/sdk/platform-tools/adb -s emulator-5554 logcat -d -t 100
docker compose exec dev /data/android/sdk/platform-tools/adb -s emulator-5554 emu kill
docker compose cp dev:/data/results ./results
~~~

Puedes usar los mismos comandos con Docker Compose desde Bash. Los scripts Android están en el [manual de Android](../android/README.md).

### RAM, almacenamiento y aceleración

- Para un PC con 16 GB, prueba primero la sala web y ejecuta Monado o Android de uno en uno. Como punto de partida puedes limitar WSL2 a 6–8 GB si Windows necesita margen. El invitado Android se configura con 2 GB y dos CPU virtuales. Reserva unos 8 GB para la descarga, el AVD y sus copias temporales, además de lo que ocupen las imágenes Docker. [Configuración avanzada de WSL](https://learn.microsoft.com/windows/wsl/wsl-config).
- La Intel Iris Xe puede acelerar Chrome/Edge en Windows. La sala funciona también con renderizado por software. Monado de referencia usa Mesa Lavapipe, y el emulador Android usa SwiftShader. La velocidad de emulación de CPU depende de si KVM está disponible en el mismo contenedor.
- Comprueba KVM con el comando siguiente. En un anfitrión Linux donde el dispositivo y los permisos sean válidos, puedes añadir /dev/kvm como dispositivo en un override de Compose. Docker Desktop y WSL2 no garantizan esa exposición. El modo auto comprueba el dispositivo y el propio emulador. La emulación sin aceleración puede superar la espera predeterminada. [Aceleración del emulador](https://developer.android.com/studio/run/emulator-acceleration).

~~~powershell
docker compose exec dev sh -c 'test -r /dev/kvm && test -w /dev/kvm && echo KVM-accesible || echo KVM-no-accesible'
docker compose exec -e ANDROID_ACCEL=software dev android/start.sh
~~~

### Volúmenes y construcción remota

Compose guarda resultados en results, SDK y AVD en android, y fuentes y salida de AOSP en aosp-source. El código Android del checkout se puede compilar sin reconstruir el contenedor mediante `docker compose exec dev bash /workspace/android/build-apk.sh`. Las descargas auxiliares pueden conservarse en downloads. Para copiar una APK al contenedor usa `docker compose cp .\mi.apk dev:/data/downloads/mi.apk`. El panel también permite subirla directamente. `docker compose --profile '*' down` detiene los servicios y conserva los volúmenes.

La compilación completa de Android es una tarea para una máquina Linux amd64 con SSD, alrededor de 64 GB de RAM y al menos 400 GB libres. AOSP publica una referencia de unas seis horas para seis núcleos y 64 GB, y de unos 40 minutos con 72 núcleos y 64 GB. Son cifras de referencia, no mediciones de este proyecto. [Requisitos de AOSP](https://source.android.com/docs/setup/start/requirements).

~~~bash
docker compose build build
docker compose run --rm build sync
docker compose run --rm -e AOSP_JOBS=8 build compile
~~~

La receta usa la etiqueta android-14.0.0_r75 y el objetivo aosp_cf_x86_64_phone-trunk_staging-userdebug. Los logs y el manifiesto resuelto quedan en results. Las imágenes que genere Cuttlefish son imágenes de referencia para su entorno virtual. [Manifiesto AOSP](https://android.googlesource.com/platform/manifest/+/refs/tags/android-14.0.0_r75) · [Objetivo Cuttlefish](https://android.googlesource.com/device/google/cuttlefish/+/refs/tags/android-14.0.0_r75/AndroidProducts.mk) · [Ejecución de Cuttlefish](https://source.android.com/docs/devices/cuttlefish/get-started).

En redes con un proxy TLS corporativo, el constructor admite un fichero PEM de CA de confianza como secreto BuildKit `apt_ca`. Para las descargas del SDK o las dependencias del APK, proporciona la CA en tiempo de ejecución con `CURL_CA_BUNDLE` apuntando a un archivo montado.

~~~powershell
docker build --target dev --secret id=apt_ca,src=company-ca-bundle.pem -t openvr-dev:0.1.0 .
docker compose up --detach --wait dev
~~~
