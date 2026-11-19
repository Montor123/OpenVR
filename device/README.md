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

El inventario conserva las propiedades originales y añade tres bloques de diagnóstico.

| Bloque | Contenido |
| --- | --- |
| `boot` | Ranura activa `a` o `b`, estado de arranque verificado, bloqueo declarado y estado de AVB. Si las dos propiedades de ranura contienen valores válidos distintos, `slot_conflict` vale `true` y la ranura queda como `null`. |
| `board` | Modelo publicado por el árbol de dispositivos y propiedades de revisión y SKU que estén disponibles. Una denominación genérica del SoC puede requerir otras fuentes para identificar la revisión del visor. |
| `partitions` | Nombres visibles para ADB en `by-name` y `mapper`. Cada lista incluye el directorio consultado. Una lista accesible vacía se registra como `[]`. Si el directorio queda inaccesible, la lista y el origen son `null`. |

Las propiedades ausentes o fuera del formato esperado aparecen como `null`. `read_errors` registra lecturas fallidas y los grupos cuyo origen siguió sin estar disponible tras agotar sus rutas de lectura. El estado de arranque lo declara el firmware de Android. La capacidad de arrancar y recuperar otro sistema requiere una prueba aparte.

ADB enumera los dispositivos y lee propiedades, la versión del kernel, el modelo del árbol, los nombres de particiones y, si se solicita, la configuración de pantalla. El inventario omite los identificadores de transporte, los registros, las cuentas y el contenido de las particiones. Guarda el JSON en local y revísalo antes de compartirlo para la fase F2. [Hoja de ruta](../docs/quest2-roadmap.md)

## Prueba de la herramienta

Ejecuta la prueba con PowerShell 7, Bash y Python 3 en Linux o WSL.

```sh
bash device/tests/test-inventory.sh
```

La prueba usa un ejecutable ADB de prueba con datos ficticios.

[Resultado de la prueba con PowerShell 7.4.13](../docs/evidence/quest2-inventory-check.log)
