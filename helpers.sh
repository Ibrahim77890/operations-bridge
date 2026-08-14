declare -gA CHECK_STATUS=()
declare -gA CHECK_VALUE=()

result_add() {
    local name="$1"
    local status="$2"
    local value="${3:-}"

    CHECK_STATUS["$name"]="$status"
    CHECK_VALUE["$name"]="$value"
}

overall_status() {
    local status
    local has_warning=false

    for status in "${CHECK_STATUS[@]}"; do
        case "$status" in
            CRITICAL|ERROR)
                printf 'CRITICAL'
                return
                ;;
            WARNING)
                has_warning=true
                ;;
            OK)
                ;;
            *)
                printf 'UNKNOWN'
                return
                ;;
        esac
    done

    if [[ "$has_warning" == true ]]; then
        printf 'WARNING'
    else
        printf 'OK'
    fi
}

json_escape() {
    local value="$1"

    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    value="${value//$'\n'/\\n}"
    value="${value//$'\r'/\\r}"
    value="${value//$'\t'/\\t}"

    printf '%s' "$value"
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

    for name in "${!CHECK_STATUS[@]}"; do
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

    printf '\n  }\n'
    printf '}\n'
}

check_cpu() {
    local load
    local cpu_count
    local threshold

    info "Checking CPU"

    load="$(awk '{print $1}' /proc/loadavg)"
    cpu_count="$(nproc)"
    threshold="$cpu_count"

    if awk "BEGIN {exit !($load < $threshold)}"; then
        result_add "cpu" "OK" "$load"
    else
        result_add "cpu" "WARNING" "$load"
    fi
}

check_memory() {
    local available
    local total
    local percentage

    info "Checking memory"

    total="$(awk '/MemTotal/ {print $2}' /proc/meminfo)"
    available="$(awk '/MemAvailable/ {print $2}' /proc/meminfo)"

    percentage=$((100 - (available * 100 / total)))

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

    usage="$(
        df --output=pcent / \
        | tail -n 1 \
        | tr -dc '0-9'
    )"

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
        if curl \
            --silent \
            --fail \
            --max-time 5 \
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
