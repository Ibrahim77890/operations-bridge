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

check_cpu() {
    local load
    local cpu_count

    info "Checking CPU"

    load="$(cpu_load_1m)"
    cpu_count="$(nproc 2>/dev/null || printf '1')"

    if awk "BEGIN {exit !($load < $cpu_count)}"; then
        result_add "cpu" "OK" "$load"
    else
        result_add "cpu" "WARNING" "$load"
    fi
}

check_memory() {
    local percentage

    info "Checking memory"

    percentage="$(memory_used_percent)"

    if (( percentage < 80 )); then
        result_add "memory" "OK" "${percentage}%"
    elif (( percentage < 90 )); then
        result_add "memory" "WARNING" "${percentage}%"
    else
        result_add "memory" "CRITICAL" "${percentage}%"
    fi
}

check_disk() {
    local usage

    info "Checking disk"

    usage="$(disk_used_percent)"
    [[ "$usage" =~ ^[0-9]+$ ]] || usage=0

    if (( usage < 80 )); then
        result_add "disk" "OK" "${usage}%"
    elif (( usage < 90 )); then
        result_add "disk" "WARNING" "${usage}%"
    else
        result_add "disk" "CRITICAL" "${usage}%"
    fi
}

check_network() {
    info "Checking network"

    if command -v curl >/dev/null 2>&1; then
        if retry 3 1 run_with_timeout 5 curl \
            --silent \
            --fail \
            https://example.com \
            >/dev/null; then
            result_add "network" "OK"
        else
            result_add "network" "WARNING"
        fi
    else
        result_add "network" "UNKNOWN" "curl unavailable"
    fi
}

emit_health_result() {
    local overall
    local first=true
    local name
    local status
    local value

    overall="$(overall_status)"

    printf '{\n'
    printf '  "command": "health",\n'
    printf '  "target": "host",\n'
    printf '  "status": "%s",\n' "$(json_escape "$overall")"
    printf '  "checks": {\n'

    for name in "${CHECK_NAMES[@]}"; do
        status="${CHECK_STATUS[$name]}"
        value="${CHECK_VALUE[$name]:-}"

        if [[ "$first" == false ]]; then
            printf ',\n'
        fi
        first=false

        printf '    "%s": {\n' "$(json_escape "$name")"
        printf '      "status": "%s"' "$(json_escape "$status")"

        if [[ -n "$value" ]]; then
            printf ',\n'
            printf '      "value": "%s"\n' "$(json_escape "$value")"
        else
            printf '\n'
        fi

        printf '    }'
    done

    printf '\n  },\n'
    printf '  "execution_id": "%s",\n' "$(json_escape "${EXECUTION_ID:-}")"
    printf '  "duration_ms": %s\n' "$(duration_ms)"
    printf '}\n'
}
