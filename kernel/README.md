# Kernel Hollywood para Quest 2

Esta receta construye fuera del visor el kernel ARM64 que Meta publica para la placa Hollywood. El objetivo de la primera prueba son los árboles de dispositivos base y sus overlays. El objetivo de la compilación completa es obtener Image, módulos y la tabla de símbolos para comparar con un visor de laboratorio.

| Entrada | Revisión |
| --- | --- |
| Linux 4.19.325, compilación de Meta 5237196.1410.150 | [dba8278b20c9](https://github.com/facebookincubator/oculus-linux-kernel/commit/dba8278b20c9b22d8e90db5ce03825fb6238e4d2) |
| Clang 17.0.2, clang-r487747c de android14-release | [425c8149f17c](https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+/425c8149f17c8d9914bf690b4d5abe45a13fb993/clang-r487747c/) |
| Herramientas GNU del repositorio AOSP GCC 4.9 | [961622e926a1](https://android.googlesource.com/platform/prebuilts/gcc/linux-x86/aarch64/aarch64-linux-android-4.9/+/961622e926a1b21382dba4dd9fe0e5fb3ee5ab7c/) |

Meta indica usar android14-release para ambos repositorios de herramientas. La consulta pública de esa referencia para GCC no devolvió un commit. La receta usa una revisión verificable del mismo repositorio, presente en android-msm-redbull-4.19-android13, y conserva los argumentos de compilación cruzada publicados por Meta. Esta selección permite reproducir las pruebas de OpenVR. La paridad binaria con el kernel de fábrica queda pendiente. [Receta de Meta](https://github.com/facebookincubator/oculus-linux-kernel/blob/dba8278b20c9b22d8e90db5ce03825fb6238e4d2/README.meta.md)

## Construcción

Desde la raíz del repositorio, en Linux amd64 con Docker o Windows con Docker Desktop y WSL2:

~~~sh
docker compose build kernel
docker compose run --rm kernel fetch-source
docker compose run --rm kernel merge
docker compose run --rm kernel fetch-tools
docker compose run --rm kernel config
docker compose run --rm -e KERNEL_JOBS=4 kernel dtbs
docker compose run --rm -e KERNEL_JOBS=4 kernel compile
~~~

- **merge** combina los defconfigs Kona y Hollywood con el script de Meta y funciona con Git, Bash y herramientas básicas. El resultado es la entrada a Kconfig.
- **config** resuelve el perfil con Kconfig y registra las versiones de herramientas.
- **dtbs** comprueba tres DTB de Kona y seis overlays de Hollywood. **compile** solicita además Image, módulos y Module.symvers. Ambos comandos registran hashes SHA‑256 relativos al directorio de salida.
- Los volúmenes kernel-work y results conservan el árbol en kernel/qcom/kona, los compiladores, la salida en /data/kernel/out y los registros en /data/results. En una ejecución local de build.sh, KERNEL_OUT_DIR permite ubicar la salida en otro disco. La configuración de Meta incluye símbolos de depuración y BTF. Reserva al menos 20 GB libres como estimación inicial para las herramientas, fuentes y salida.

Para copiar los registros al checkout sin montar el volumen en Windows:

~~~sh
docker compose run --name openvr-kernel-results kernel help
docker cp openvr-kernel-results:/data/results ./results
docker rm openvr-kernel-results
~~~

La ruta kernel/qcom/kona conserva los enlaces relativos a cabeceras que usa el audio de Meta. La receta conserva el perfil de Meta y genera archivos para análisis de laboratorio. La identificación del panel y del overlay que carga una unidad concreta depende del inventario de ese visor. La cadena de arranque y recuperación de fábrica debe verificarse antes de integrar una imagen para el dispositivo. [Pantalla Hollywood](../docs/hollywood-display.md) · [Matriz de hardware y arranque](../docs/quest2-hardware.md)
