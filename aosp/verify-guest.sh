#!/usr/bin/env bash
set -euo pipefail

if ! command -v python3 >/dev/null; then
    printf '%s\n' 'Instala Python 3 en el anfitrión para verificar el invitado.' >&2
    exit 2
fi

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
exec python3 "$script_dir/tests/verify_guest.py" "$@"
