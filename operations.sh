source "$(dirname "$0")/helpers.sh"

health_host() {
    info "Running host health checks"

    CHECK_STATUS=()
    CHECK_VALUE=()

    check_cpu
    check_memory
    check_disk
    check_network

    emit_health_result
}

inventory_host() {
    local hostname
    local kernel
    local os
    local cpu
    local memory

    info "Collecting host inventory"

    hostname="$(hostname)"
    kernel="$(uname -r)"

    if [[ -r /etc/os-release ]]; then
        os="$(. /etc/os-release && printf '%s' "$PRETTY_NAME")"
    else
        os="$(uname -s)"
    fi

    if command -v nproc >/dev/null 2>&1; then
        cpu="$(nproc)"
    else
        cpu="0"
    fi

    if [[ -r /proc/meminfo ]]; then
        memory="$(awk '/MemTotal/ {printf "%.0f MB", $2 / 1024}' /proc/meminfo)"
    else
        memory="unknown"
    fi

    printf '%s\n' "{"
    printf '  "command": "inventory",\n'
    printf '  "target": "host",\n'
    printf '  "hostname": "%s",\n' "$(json_escape "$hostname")"
    printf '  "os": "%s",\n' "$(json_escape "$os")"
    printf '  "kernel": "%s",\n' "$(json_escape "$kernel")"
    printf '  "cpu_count": %s,\n' "$cpu"
    printf '  "memory": "%s"\n' "$(json_escape "$memory")"
    printf '%s\n' "}"
}
