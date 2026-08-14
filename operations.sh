source "$(dirname "$0")/helpers.sh"

INVENTORY_HOSTNAME=""
INVENTORY_KERNEL=""
INVENTORY_OS=""
INVENTORY_CPU=""
INVENTORY_MEMORY=""

health_host() {
    local result_dir
    local pid_cpu
    local pid_memory
    local pid_disk
    local pid_network

    info "Running host health checks"

    CHECK_STATUS=()
    CHECK_VALUE=()
    CHECK_NAMES=()

    result_dir="$WORK_DIR/health-results"
    mkdir -p "$result_dir"

    run_health_check_worker "cpu" check_cpu "$result_dir/cpu.json" &
    pid_cpu=$!

    run_health_check_worker "memory" check_memory "$result_dir/memory.json" &
    pid_memory=$!

    run_health_check_worker "disk" check_disk "$result_dir/disk.json" &
    pid_disk=$!

    run_health_check_worker "network" check_network "$result_dir/network.json" &
    pid_network=$!

    wait "$pid_cpu"
    wait "$pid_memory"
    wait "$pid_disk"
    wait "$pid_network"

    aggregate_check_result_file "$result_dir/cpu.json"
    aggregate_check_result_file "$result_dir/memory.json"
    aggregate_check_result_file "$result_dir/disk.json"
    aggregate_check_result_file "$result_dir/network.json"
}

run_health_check_worker() {
    local name="$1"
    local check_function="$2"
    local output_file="$3"

    CHECK_STATUS=()
    CHECK_VALUE=()
    CHECK_NAMES=()

    if ! "$check_function"; then
        result_add "$name" "ERROR"
    fi

    emit_check_result_file "$output_file" "$name"
}

inventory_host() {
    info "Collecting host inventory"

    INVENTORY_HOSTNAME="$(hostname)"
    INVENTORY_KERNEL="$(uname -r)"

    if [[ -r /etc/os-release ]]; then
        INVENTORY_OS="$(. /etc/os-release && printf '%s' "$PRETTY_NAME")"
    else
        INVENTORY_OS="$(uname -s)"
    fi

    if command -v nproc >/dev/null 2>&1; then
        INVENTORY_CPU="$(nproc)"
    else
        INVENTORY_CPU="0"
    fi

    if [[ -r /proc/meminfo ]]; then
        INVENTORY_MEMORY="$(awk '/MemTotal/ {printf "%.0f MB", $2 / 1024}' /proc/meminfo)"
    else
        INVENTORY_MEMORY="unknown"
    fi
}

emit_inventory_result() {
    printf '%s\n' "{"
    printf '  "command": "inventory",\n'
    printf '  "target": "host",\n'
    printf '  "execution_id": "%s",\n' "$(json_escape "${EXECUTION_ID:-}")"
    printf '  "duration_ms": %s,\n' "$(duration_ms)"
    printf '  "hostname": "%s",\n' "$(json_escape "$INVENTORY_HOSTNAME")"
    printf '  "os": "%s",\n' "$(json_escape "$INVENTORY_OS")"
    printf '  "kernel": "%s",\n' "$(json_escape "$INVENTORY_KERNEL")"
    printf '  "cpu_count": %s,\n' "$INVENTORY_CPU"
    printf '  "memory": "%s"\n' "$(json_escape "$INVENTORY_MEMORY")"
    printf '%s\n' "}"
}
