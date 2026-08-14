declare -gA CHECK_STATUS=()
declare -gA CHECK_VALUE=()
declare -ga CHECK_NAMES=()

result_add() {
    local name="$1"
    local status="$2"
    local value="${3:-}"

    if [[ ! -v "CHECK_STATUS[$name]" ]]; then
        CHECK_NAMES+=("$name")
    fi

    CHECK_STATUS["$name"]="$status"
    CHECK_VALUE["$name"]="$value"
}

run_with_timeout() {
    local timeout_seconds="$1"
    shift

    timeout \
        --preserve-status \
        "${timeout_seconds}s" \
        "$@"
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

emit_check_result_file() {
    local output_file="$1"
    local name="$2"
    local status="${CHECK_STATUS[$name]:-UNKNOWN}"
    local value="${CHECK_VALUE[$name]:-}"

    printf '{\n' >"$output_file"
    printf '  "name": "%s",\n' "$(json_escape "$name")" >>"$output_file"
    printf '  "status": "%s"' "$(json_escape "$status")" >>"$output_file"

    if [[ -n "$value" ]]; then
        printf ',\n' >>"$output_file"
        printf '  "value": "%s"\n' "$(json_escape "$value")" >>"$output_file"
    else
        printf '\n' >>"$output_file"
    fi

    printf '}\n' >>"$output_file"
}

read_json_string_field() {
    local field="$1"
    local input_file="$2"

    sed -nE \
        "s/^[[:space:]]*\"${field}\":[[:space:]]*\"(.*)\"[,]?[[:space:]]*$/\\1/p" \
        "$input_file" \
        | head -n 1
}

aggregate_check_result_file() {
    local input_file="$1"
    local name
    local status
    local value

    name="$(read_json_string_field "name" "$input_file")"
    status="$(read_json_string_field "status" "$input_file")"
    value="$(read_json_string_field "value" "$input_file")"

    if [[ -z "$name" || -z "$status" ]]; then
        warn "Ignoring invalid check result file: $input_file"
        return
    fi

    result_add "$name" "$status" "$value"
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

retry() {
    local attempts="$1"
    local delay="$2"
    shift 2

    local attempt=1

    while (( attempt <= attempts )); do
        if "$@"; then
            return 0
        fi

        if (( attempt == attempts )); then
            return 1
        fi

        warn "Attempt $attempt failed; retrying in ${delay}s"

        sleep "$delay"

        delay=$((delay * 2))
        attempt=$((attempt + 1))
    done

    return 1
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
