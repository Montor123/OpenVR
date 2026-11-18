# Captura del laboratorio OpenXR

La aplicación se ejecutó el 18 de noviembre de 2026 sobre Docker Engine 29.9.2, Linux amd64 y Vulkan de CPU. El ensayo usó el Dockerfile de dependencias y el lanzador actualizado montado en el contenedor. La imagen temporal y el contenedor ya se retiraron.

```bash
docker build --progress=plain -t openvr-native-xr:dev openxr
docker run -d --name openvr-xr-check --shm-size=256m \
  -p 127.0.0.1:6081:6081 \
  -e VK_DRIVER_FILES=/usr/share/vulkan/icd.d/lvp_icd.json \
  --mount "type=bind,source=$PWD/openxr/start.sh,target=/opt/openvr-xr-test.sh,readonly" \
  --entrypoint /bin/bash openvr-native-xr:dev /opt/openvr-xr-test.sh
curl -fsS http://127.0.0.1:6081/vnc.html
docker exec openvr-xr-check sh -c 'tail -28 /data/results/hello-xr.log'
docker exec openvr-xr-check xwininfo -root -tree
docker image inspect openvr-native-xr:dev --format '{{.Size}}'
docker cp openvr-xr-check:/data/results /tmp/openvr-native-pass
```

Un cliente de prueba de RFB 3.8 solicitó el fotograma mediante `ws://127.0.0.1:6081/websockify`. La captura `stereo.png` se recortó a partir de ese fotograma. El registro `monado-start.log` contiene las primeras 134 líneas del registro del servicio. Los registros `hello-xr.log`, `novnc.log` y `vulkan.log` corresponden a la ejecución observada.
