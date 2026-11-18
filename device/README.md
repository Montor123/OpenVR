# Inventario de Quest 2 por ADB

El script registra las versiones que declara Android para comparar una unidad Quest 2 con las fuentes del kernel publicadas por Meta. Necesita ADB de Android SDK Platform Tools y Windows PowerShell 5.1 o PowerShell 7. Conecta el visor por USB, habilita la depuración desde el modo desarrollador y acepta la autorización de ADB en el visor. [Android SDK Platform Tools](https://developer.android.com/tools/releases/platform-tools)

Con un solo dispositivo en `adb devices`, ejecuta el siguiente comando desde la raíz del repositorio.

```powershell
.\device\inspect-quest.ps1
```

Si ADB muestra varios dispositivos, copia el identificador del visor en `-Serial`. Puedes indicar una ruta explícita a ADB y añadir tamaño y densidad reportados por el gestor de ventanas de Android.

```powershell
adb devices
.\device\inspect-quest.ps1 -Serial "IDENTIFICADOR" -Adb "C:\Android\platform-tools\adb.exe" -Display -OutputPath ".\results\mi-quest2.json"
```

La salida predeterminada es `results/quest2-inventory.json`. Cada ejecución comprueba `hollywood` o el nombre de modelo Quest 2 y guarda un JSON nuevo. Con `-Display`, `physical_size` y `physical_density_dpi` son los valores etiquetados como `Physical` por `wm`. Sirven para comparar la vista del gestor de ventanas entre compilaciones. Para identificar las características del panel y la óptica se necesitan sus propias fuentes y mediciones.

Las propiedades ausentes o fuera del formato esperado aparecen como `null`. `read_errors` enumera las lecturas cuyo comando devolvió un error. Las propiedades de arranque describen lo que informa el firmware desde Android. La verificación del arranque de otro sistema requiere evidencia adicional.

Las únicas operaciones de ADB son enumerar transportes y leer propiedades seleccionadas, versión y arquitectura del kernel y, cuando se pide, la configuración de pantalla. El JSON omite los identificadores de transporte, registros del dispositivo, cuentas y archivos del visor.

## Prueba de la herramienta

Ejecuta la prueba con PowerShell 7, Bash y Python 3 en Linux o WSL.

```sh
bash device/tests/test-inventory.sh
```

La prueba usa un ejecutable ADB de prueba con datos ficticios.
