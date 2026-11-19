#!/usr/bin/env bash
# Linux resource measurements for the build tree or guest work directory.
openvr_resources() {
    local path="$1" group limit usage remainder
    openvr_disk_kib="$(df -Pk -- "$path" | awk 'NR == 2 {print $4}')"
    openvr_memory_kib="$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo)"
    group="/sys/fs/cgroup$(awk -F: '$1 == 0 {print $3}' /proc/self/cgroup)"
    group="${group%/}"
    if [[ ! -d "$group" ]]; then
        group=/sys/fs/cgroup
    fi
    while [[ "$group" == /sys/fs/cgroup* ]]; do
        if [[ -r "$group/memory.max" && -r "$group/memory.current" ]]; then
            read -r limit < "$group/memory.max"
            read -r usage < "$group/memory.current"
            if [[ "$limit" =~ ^[0-9]+$ && "$usage" =~ ^[0-9]+$ ]]; then
                remainder=$(((limit > usage ? limit - usage : 0) / 1024))
                if (( remainder < openvr_memory_kib )); then
                    openvr_memory_kib="$remainder"
                fi
            fi
        fi
        group="${group%/*}"
    done
    printf 'Espacio disponible: %s MiB · RAM disponible: %s MiB · CPU visibles: %s\n' \
        "$((openvr_disk_kib / 1024))" "$((openvr_memory_kib / 1024))" "$(nproc)"
}
