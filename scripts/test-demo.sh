#!/usr/bin/env bash
set -euo pipefail
base=${1:-http://127.0.0.1:8080}

printf 'Salud HTTP: '
curl -fsS "$base/healthz" | grep -F '"ok":true'
printf 'Estado demo: '
curl -fsS "$base/api/status" | grep -F '{"android":false,"desktop":false}'
printf 'Registro persistente: '
curl -fsS "$base/api/logs?target=demo" | grep -F 'OpenVR iniciado'
curl -fsS "$base/" | grep -Fq '<title>OpenVR'
printf 'Interfaz HTTP correcta\n'

code=$(curl -sS -o /dev/null -w '%{http_code}' -X POST "$base/api/demo")
[[ $code == 503 ]]
printf 'Android deshabilitado en demo: HTTP %s\n' "$code"

code=$(curl -sS -o /dev/null -w '%{http_code}' -H 'Origin: https://otra-pagina.invalid' -X POST "$base/api/demo")
[[ $code == 403 ]]
printf 'Petición cruzada rechazada: HTTP %s\n' "$code"
