declare -gA CHECK_STATUS=()
declare -gA CHECK_VALUE=()
declare -ga CHECK_NAMES=()
declare -ga DIAGNOSE_FINDINGS=()

json_escape() {
    local value="$1"

    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    value="${value//$'\n'/\\n}"
    value="${value//$'\r'/\\r}"
    value="${value//$'\t'/\\t}"

    printf '%s' "$value"
}

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

overall_status() {
    local status
    local has_warning=false

    for status in "${CHECK_STATUS[@]}"; do
        case "$status" in
            CRITICAL|ERROR)
                printf 'CRITICAL'
                return
                ;;
            WARN|WARNING)
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

security_check_json() {
    local status="$1"
    local details="$2"

    jq -n \
        --arg status "$status" \
        --arg details "$details" \
        '{status: $status, details: $details}'
}

diagnose_add_finding() {
    local component="$1"
    local severity="$2"
    local message="$3"

    DIAGNOSE_FINDINGS+=("$(
        jq -cn \
            --arg component "$component" \
            --arg severity "$severity" \
            --arg message "$message" \
            '{component: $component, severity: $severity, message: $message}'
    )")
}

diagnose_findings_json() {
    if ((${#DIAGNOSE_FINDINGS[@]} == 0)); then
        jq -n '[]'
        return
    fi

    printf '%s\n' "${DIAGNOSE_FINDINGS[@]}" | jq -s '.'
}

severity_overall_status() {
    jq -r '
        [.[].severity] as $severities |
        if any($severities[]; . == "CRITICAL") then "CRITICAL"
        elif any($severities[]; . == "WARN" or . == "WARNING") then "WARN"
        else "OK"
        end
    '
}
