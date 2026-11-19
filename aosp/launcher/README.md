# Inicio de Android de OpenVR

`OpenVRLauncher` es el lanzador HOME del producto AOSP de laboratorio. Se instala en `/product/app` como `org.openvr.launcher/.MainActivity` y presenta tres pestañas.

- **Inicio** muestra los favoritos y las últimas ocho actividades abiertas desde el lanzador. La estrella de cada tarjeta añade o quita el favorito. Ambos historiales se guardan en las preferencias privadas del usuario.
- **Biblioteca** lista las actividades que puede abrir el usuario actual. Apps y Juegos se basan en la categoría Android de cada paquete y en la marca de juego de paquetes antiguos sin categoría. Busca por nombre o paquete dentro de la categoría seleccionada. El listado se actualiza con instalaciones, cambios y desinstalaciones.
- **Ajustes** consulta batería, transporte de red activo y espacio disponible del volumen de datos. Los datos se actualizan al abrir la pestaña y al volver al lanzador. La configuración de Wi-Fi, Bluetooth, pantalla, sonido y almacenamiento se abre en las actividades estándar de Android. Si la imagen carece de alguna actividad, el lanzador indica que no puede abrirla.

Navega por toque, teclado o cruceta. **Intro**, el centro de la cruceta o el botón **A** abren el control enfocado. El botón **B** vuelve atrás. La búsqueda usa el teclado Android o un teclado físico. El lanzador dispone de un indicador visible de foco y admite crucetas que Android publica como teclas o ejes HAT.

El lanzador presenta una interfaz Android 2D. El estado de batería y red corresponde a lo que informa el invitado. El uso de `ACCESS_NETWORK_STATE` permite identificar el tipo de conexión sin consultar SSID, direcciones ni contraseñas.

## Verificación

Java compiló y se enlazaron los recursos con el SDK público API 34 de AOSP. AAPT2 confirmó `HOME`, `DEFAULT` y los IDs de navegación. D8 produjo `classes.dex`. [Comandos y resultados](verification.md)

En una compilación AOSP configurada para el producto OpenVR, ejecuta `m OpenVRLauncher`. Para verificar el flujo principal y la APK de ejemplo en un invitado arrancado, usa [el verificador de invitado](../verify-guest.sh). La apertura de HOME, el recorrido con mandos y las lecturas de Ajustes quedan pendientes en la imagen personalizada.
