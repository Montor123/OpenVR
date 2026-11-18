ARG SOURCE_DATE_EPOCH=1794960000

FROM golang:1.26.8-alpine3.23@sha256:a8fa79c5bd40d880b52bd3b6d7669ecdcfd00e85facdd427d279efb5ddd79cb1 AS compile
WORKDIR /src
COPY go.mod assets.go ./
COPY cmd/ cmd/
COPY web/ web/
RUN CGO_ENABLED=0 go build -trimpath -buildvcs=false -ldflags="-s -w -buildid=" -o /out/openvr ./cmd/openvr \
    && mkdir -p /out/data/results \
    && touch /out/data/results/.keep

FROM scratch AS demo
LABEL org.opencontainers.image.source="https://github.com/Montor123/OpenVR" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.title="OpenVR demo"
COPY --from=compile /out/openvr /openvr
COPY --from=compile --chown=1000:1000 /out/data/ /data/
COPY --from=compile /usr/local/go/LICENSE /licenses/Go-LICENSE
COPY --from=compile /usr/local/go/PATENTS /licenses/Go-PATENTS
COPY LICENSE /licenses/OpenVR-LICENSE
USER 1000:1000
EXPOSE 8080
HEALTHCHECK --interval=15s --timeout=3s CMD ["/openvr", "healthcheck"]
ENTRYPOINT ["/openvr"]

FROM python:3.12.13-slim-bookworm@sha256:4766d8b510c428e595d74b9cc5bbb2fae8e26316fffb4adc89908d79aacd58a2 AS packages
ARG DEBIAN_SNAPSHOT=20261001T000000Z
RUN rm /etc/apt/sources.list.d/debian.sources \
    && echo "deb [check-valid-until=no] https://snapshot.debian.org/archive/debian/${DEBIAN_SNAPSHOT}/ bookworm main" > /etc/apt/sources.list \
    && echo "deb [check-valid-until=no] https://snapshot.debian.org/archive/debian-security/${DEBIAN_SNAPSHOT}/ bookworm-security main" >> /etc/apt/sources.list

FROM packages AS dev
RUN --mount=type=secret,id=apt_ca,mode=0444 \
    --mount=type=bind,from=compile,source=/out/openvr,target=/tmp/openvr \
    --mount=type=bind,source=android,target=/tmp/android \
    --mount=type=bind,source=docker/dev-entrypoint.sh,target=/tmp/openvr-dev \
    export SSL_CERT_FILE=${SSL_CERT_FILE:-/etc/ssl/certs/ca-certificates.crt}; \
    if [ -r /run/secrets/apt_ca ]; then export SSL_CERT_FILE=/run/secrets/apt_ca; fi; \
    apt-get -o Acquire::https::CaInfo="$SSL_CERT_FILE" -o APT::Update::Error-Mode=any update \
    && apt-get -o Acquire::https::CaInfo="$SSL_CERT_FILE" install -y --no-install-recommends \
    aapt android-framework-res apksigner ca-certificates curl git libasound2 libdbus-1-3 \
    libfontconfig1 libfreetype6 libgl1 libgl1-mesa-dri libnss3 libpulse0 libx11-6 libx11-xcb1 \
    libxcb-cursor0 libxcb-icccm4 libxcb-image0 libxcb-keysyms1 libxcb-render-util0 libxcb-shape0 \
    libxcb-xfixes0 libxcb1 libxcomposite1 libxcursor1 libxi6 libxkbcommon-x11-0 libxkbcommon0 \
    libxrandr2 libxtst6 novnc openbox openjdk-17-jdk-headless unzip websockify x11-utils x11vnc xvfb zip zipalign \
    && rm -rf /var/lib/apt/lists/* \
    && useradd -m -u 1000 -s /bin/bash openvr \
    && install -d -o openvr -g openvr /data/android /data/results /data/downloads \
    && touch /data/android/.keep /data/results/.keep /data/downloads/.keep \
    && dpkg-query -W -f='${Package}\t${Version}\n' > /usr/local/share/openvr-dev-packages.tsv \
    && install -d /opt/openvr \
    && cp -R /tmp/android /opt/openvr/android \
    && chown -R openvr:openvr /opt/openvr \
    && chmod 0755 /opt/openvr/android/*.sh \
    && install -m 0755 /tmp/openvr /usr/local/bin/openvr \
    && install -m 0755 /tmp/openvr-dev /usr/local/bin/openvr-dev
ENV DISPLAY=:0 OPENVR_ANDROID=1 PROJECT_ROOT=/opt/openvr
USER 1000:1000
WORKDIR /opt/openvr
EXPOSE 8080 6080
HEALTHCHECK --interval=15s --timeout=5s CMD openvr healthcheck && xdpyinfo >/dev/null && curl -fsS http://127.0.0.1:6080/vnc.html >/dev/null
ENTRYPOINT ["/usr/local/bin/openvr-dev"]

FROM packages AS build
ARG REPO_COMMIT=97dc5c1bd9527c2abe2183b16a4b7ef037dc34a7
RUN --mount=type=secret,id=apt_ca,mode=0444 \
    export SSL_CERT_FILE=${SSL_CERT_FILE:-/etc/ssl/certs/ca-certificates.crt}; \
    if [ -r /run/secrets/apt_ca ]; then export SSL_CERT_FILE=/run/secrets/apt_ca; fi; \
    apt-get -o Acquire::https::CaInfo="$SSL_CERT_FILE" -o APT::Update::Error-Mode=any update \
    && apt-get -o Acquire::https::CaInfo="$SSL_CERT_FILE" install -y --no-install-recommends \
    bc bison build-essential ca-certificates curl flex fontconfig g++-multilib gcc-multilib git git-lfs gnupg gperf \
    lib32ncurses-dev lib32readline-dev lib32z1-dev libgl1-mesa-dev libx11-dev libxml2-utils \
    rsync unzip x11proto-dev xsltproc zip zlib1g-dev \
    && rm -rf /var/lib/apt/lists/* \
    && useradd -m -u 1000 -s /bin/bash openvr \
    && install -d -o openvr -g openvr /data/aosp /data/results \
    && touch /data/aosp/.keep /data/results/.keep \
    && git init /opt/git-repo \
    && GIT_SSL_CAINFO="$SSL_CERT_FILE" git -C /opt/git-repo fetch --depth=1 https://gerrit.googlesource.com/git-repo refs/tags/v2.54:refs/tags/v2.54 \
    && test "$(git -C /opt/git-repo rev-parse 'FETCH_HEAD^{commit}')" = "${REPO_COMMIT}" \
    && git -C /opt/git-repo checkout --detach "${REPO_COMMIT}" \
    && chown -R openvr:openvr /opt/git-repo \
    && ln -s /opt/git-repo/repo /usr/local/bin/repo
COPY --chown=1000:1000 aosp/ /opt/openvr/aosp/
COPY --chmod=0755 aosp/build.sh /usr/local/bin/openvr-aosp
USER 1000:1000
ENV REPO_COMMIT=${REPO_COMMIT}
WORKDIR /data/aosp
ENTRYPOINT ["/usr/local/bin/openvr-aosp"]
CMD ["help"]

FROM packages AS kernel
RUN --mount=type=secret,id=apt_ca,mode=0444 \
    export SSL_CERT_FILE=${SSL_CERT_FILE:-/etc/ssl/certs/ca-certificates.crt}; \
    if [ -r /run/secrets/apt_ca ]; then export SSL_CERT_FILE=/run/secrets/apt_ca; fi; \
    apt-get -o Acquire::https::CaInfo="$SSL_CERT_FILE" -o APT::Update::Error-Mode=any update \
    && apt-get -o Acquire::https::CaInfo="$SSL_CERT_FILE" install -y --no-install-recommends \
      bc bison build-essential cpio curl flex git libelf-dev libssl-dev openssl pahole pkg-config \
    && rm -rf /var/lib/apt/lists/* \
    && useradd -m -u 1000 -s /bin/bash openvr \
    && install -d -o openvr -g openvr /data/kernel /data/results \
    && touch /data/kernel/.keep /data/results/.keep
COPY --chmod=0644 kernel/sources.sh /opt/openvr/kernel/sources.sh
COPY --chmod=0755 kernel/build.sh /opt/openvr/kernel/build.sh
USER 1000:1000
WORKDIR /data/kernel
ENTRYPOINT ["/opt/openvr/kernel/build.sh"]
CMD ["help"]

FROM demo AS default
