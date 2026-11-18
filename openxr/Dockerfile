FROM debian:trixie-slim@sha256:a72b4433de1cf7d6bae0c4cee74d0547f58601a643b3375f070c51600d63b6b2

RUN apt-get update && apt-get install -y --no-install-recommends \
      fluxbox=1.3.7-1+b1 \
      libgl1-mesa-dri=25.0.7-2+deb13u1 \
      libopenxr-loader1=1.1.47~ds-2 \
      libopenxr-utils=1.1.47~ds-2 \
      libopenxr1-monado=25.0.0+dfsg-2 \
      mesa-vulkan-drivers=25.0.7-2+deb13u1 \
      monado-service=25.0.0+dfsg-2 \
      novnc=1:1.6.0-2 \
      vulkan-tools=1.4.304.0+dfsg1-1 \
      websockify=0.12.0+dfsg1-4+b1 \
      x11-utils=7.7+7 \
      x11vnc=0.9.17-1 \
      xvfb=2:21.1.16-1.3+deb13u4 \
    && rm -rf /var/lib/apt/lists/* \
    && useradd --create-home --uid 1000 xr \
    && install -d -o xr -g xr /data/results \
    && install -d -m 1777 /tmp/.X11-unix

COPY --chmod=0755 start.sh /usr/local/bin/openvr-xr
COPY --chown=1000:1000 fluxbox-apps /home/xr/.fluxbox/apps
ENV LANG=C.UTF-8 \
    DISPLAY=:81 \
    LIBGL_ALWAYS_SOFTWARE=1 \
    VK_DRIVER_FILES=/usr/share/vulkan/icd.d/lvp_icd.json \
    XR_RUNTIME_JSON=/usr/share/openxr/1/openxr_monado.json \
    XRT_COMPOSITOR_FORCE_XCB=1 \
    XRT_COMPOSITOR_SCALE_PERCENTAGE=60 \
    XRT_DEBUG_GUI=1 \
    QWERTY_ENABLE=1
USER xr
EXPOSE 6081
HEALTHCHECK --interval=5s --timeout=3s --start-period=25s CMD \
  grep -q -- '->XR_SESSION_STATE_FOCUSED' "${OPENVR_XR_RESULTS:-/data/results}/hello-xr.log" \
  && python3 -c 'import urllib.request; print(urllib.request.urlopen("http://127.0.0.1:6081/vnc.html", timeout=2).status)'
ENTRYPOINT ["/usr/local/bin/openvr-xr"]
