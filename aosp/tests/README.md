# Pruebas del verificador de Cuttlefish

Ejecuta el conjunto de regresión desde la raíz del repositorio con Python 3.9 o posterior.

```bash
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s aosp/tests -v
```

Cinco casos usan archivos de exportación sintéticos para verificar metadatos, hashes, rutas y extracción. El caso de extracción usa el filtro data de tarfile. Dieciséis casos usan un ADB simulado y comprueban la secuencia de comandos del verificador. Cubre el recorrido completo de HOME a Ajustes y de Biblioteca a la APK, el modo sin APK, el rechazo de destinos ajenos al laboratorio y la persistencia de evidencias de error. También comprueba que una captura XML obsoleta, un paquete distinto, una actividad que sólo aparece en el historial o la ausencia de `APP_READY` impiden declarar éxito.

En un anfitrión con un invitado OpenVR ya arrancado, ejecuta el verificador con el serial de bucle local que indicó el lanzador de Cuttlefish. El APK es opcional para una prueba de HOME y Ajustes. Para comprobar también Biblioteca, pasa el archivo generado por el laboratorio Android.

```bash
OPENVR_ADB="$RUN_DIR/bin/adb" aosp/verify-guest.sh 127.0.0.1:6520 /ruta/openvr-demo.apk
```

Se crea una carpeta `guest-*` por ejecución bajo `OPENVR_RESULTS`, o `results/cuttlefish/` por defecto. Cada fase registra el comando ADB, la respuesta relevante, la jerarquía XML usada para pulsar y las actividades en primer plano. Una vez verificada la identidad del invitado se guarda logcat y se intentan capturas PNG. Los límites `AOSP_BOOT_TIMEOUT` y `AOSP_UI_TIMEOUT` se indican en segundos y por defecto son 300 y 60.

El entorno de desarrollo no dispone de `/dev/kvm`. La ejecución pendiente requiere la imagen construida de OpenVR y un anfitrión Cuttlefish con KVM.

[Resultado de las 21 pruebas](../../docs/evidence/aosp-flow-tests.log)
