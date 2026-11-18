# Inicio de Android de OpenVR

`OpenVRLauncher` es la aplicación de inicio del producto de laboratorio AOSP. Muestra las actividades que el usuario actual puede abrir, permite buscarlas por nombre o paquete y vuelve a consultar el listado tras instalar, actualizar o retirar aplicaciones. También abre Ajustes y muestra el modelo, la versión de Android, la ABI y la compilación que reporta el sistema.

La aplicación se instala en `/product/app` con el paquete `org.openvr.launcher`. Declara la categoría `HOME` y usa APIs públicas. El lanzador se ejecuta como una interfaz Android 2D. Los componentes OpenXR funcionan en su entorno independiente.

## Verificación

Se compiló Java y se enlazaron los recursos con el SDK público API 34 del tag AOSP `android-14.0.0_r75`. AAPT2 confirmó las categorías `HOME` y `DEFAULT` y el SDK de destino 34. D8 generó `classes.dex`. [Comandos y resultados](verification.md)

En una compilación AOSP configurada para el producto OpenVR, ejecuta `m OpenVRLauncher` para compilar el módulo. En Android arrancado, ve a Ajustes y comprueba que OpenVR aparece como aplicación de inicio predeterminada. Pulsa Inicio, instala la APK de `org.openvr.demo` mediante ADB y verifica que la puedes encontrar y abrir. Abre **Sistema** para contrastar el modelo, API y ABI con los valores que da `adb shell getprop`. Esas comprobaciones de ejecución quedan pendientes hasta que arranque la imagen personalizada.
