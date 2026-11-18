#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname -- "${BASH_SOURCE[0]}")/.."
image=openvr-demo:0.1.0
archive=dist/openvr-demo-0.1.0-linux-amd64.tar
docker build --platform linux/amd64 --target demo --tag "$image" .
mkdir -p dist
docker image save --output "$archive" "$image"
(
  cd dist
  name=${archive##*/}
  sha256sum "$name" > "$name.sha256"
  wc -c "$name"
  cat "$name.sha256"
)
