#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${OPSBRIDGE_CONFIG:-$SCRIPT_DIR/config/defaults.env}"

if [[ -r "$CONFIG_FILE" ]]; then
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
fi

AGENT="${OPSBRIDGE_AGENT:-$SCRIPT_DIR/agent.sh}"
HOST="${OPSBRIDGE_HOST:-127.0.0.1}"
PORT="${OPSBRIDGE_PORT:-8080}"
OPSBRIDGE_KEY="${OPSBRIDGE_KEY:-}"
OPSBRIDGE_VERSION="${OPSBRIDGE_VERSION:-0.2.0}"
OPSBRIDGE_RUNTIME_DIR="${OPSBRIDGE_RUNTIME_DIR:-/tmp/opsbridge}"
OPSBRIDGE_MAX_BODY_SIZE="${OPSBRIDGE_MAX_BODY_SIZE:-8192}"
OPSBRIDGE_MAX_OUTPUT_SIZE="${OPSBRIDGE_MAX_OUTPUT_SIZE:-65536}"
OPSBRIDGE_MAX_HEADER_LENGTH="${OPSBRIDGE_MAX_HEADER_LENGTH:-4096}"
OPSBRIDGE_MAX_REQUEST_LINE_LENGTH="${OPSBRIDGE_MAX_REQUEST_LINE_LENGTH:-2048}"
OPSBRIDGE_MAX_COMMAND_LENGTH="${OPSBRIDGE_MAX_COMMAND_LENGTH:-32}"
OPSBRIDGE_MAX_TARGET_LENGTH="${OPSBRIDGE_MAX_TARGET_LENGTH:-32}"
OPSBRIDGE_MAX_PARAMETER_KEY_LENGTH="${OPSBRIDGE_MAX_PARAMETER_KEY_LENGTH:-64}"
OPSBRIDGE_MAX_PARAMETER_VALUE_LENGTH="${OPSBRIDGE_MAX_PARAMETER_VALUE_LENGTH:-256}"
OPSBRIDGE_RATE_LIMIT_PER_MINUTE="${OPSBRIDGE_RATE_LIMIT_PER_MINUTE:-60}"
OPSBRIDGE_REPLAY_TTL_SECONDS="${OPSBRIDGE_REPLAY_TTL_SECONDS:-900}"

LOG_PREFIX="[BRIDGE]"
HTTP_STATUS="200 OK"

log() {
    printf '%s %s\n' "$LOG_PREFIX" "$*" >&2
}

json_error() {
    local message="$1"

    jq -cn --arg message "$message" '{success: false, error: $message}'
}

json_agent_result() {
    local result="$1"

    jq -cn \
        --argjson result "$result" \
        '{
            success: (($result.status // "") != "FAILED" and ($result.status // "") != "TIMEOUT"),
            execution_id: ($result.execution_id // ""),
            result: $result
        }'
}

http_response() {
    local status="$1"
    local body="$2"
    local content_type="${3:-application/json}"
    local content_length

    content_length=$(printf '%s' "$body" | wc -c | tr -dc '0-9')

    printf 'HTTP/1.1 %s\r\n' "$status"
    printf 'Content-Type: %s\r\n' "$content_type"
    printf 'Content-Length: %s\r\n' "$content_length"
    printf 'Connection: close\r\n'
    printf '\r\n'
    printf '%s' "$body"
}

byte_count() {
    printf '%s' "$1" | wc -c | tr -dc '0-9'
}

hash_value() {
    local value="$1"

    if command -v sha256sum >/dev/null 2>&1; then
        printf '%s' "$value" | sha256sum | awk '{print $1}'
        return
    fi

    printf '%s' "$value" | shasum -a 256 | awk '{print $1}'
}

constant_time_equals() {
    local left="$1"
    local right="$2"
    local left_len="${#left}"
    local right_len="${#right}"
    local max_len="$left_len"
    local diff=$((left_len ^ right_len))
    local i

    if (( right_len > max_len )); then
        max_len="$right_len"
    fi

    for ((i = 0; i < max_len; i++)); do
        local left_char="${left:i:1}"
        local right_char="${right:i:1}"
        local left_ord=0
        local right_ord=0

        if [[ -n "$left_char" ]]; then
            printf -v left_ord '%d' "'$left_char"
        fi

        if [[ -n "$right_char" ]]; then
            printf -v right_ord '%d' "'$right_char"
        fi

        diff=$((diff | (left_ord ^ right_ord)))
    done

    (( diff == 0 ))
}

ensure_runtime_dirs() {
    mkdir -p "$OPSBRIDGE_RUNTIME_DIR/replay"
    chmod 700 "$OPSBRIDGE_RUNTIME_DIR" "$OPSBRIDGE_RUNTIME_DIR/replay" 2>/dev/null || true
}

audit_event() {
    local event="$1"
    local message="$2"
    local request_id="${3:-}"

    ensure_runtime_dirs

    jq -cn \
        --arg timestamp "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
        --arg event "$event" \
        --arg request_id "$request_id" \
        --arg message "$message" \
        '{timestamp: $timestamp, event: $event, request_id: $request_id, message: $message}' \
        >>"$OPSBRIDGE_RUNTIME_DIR/security-audit.jsonl"
}

record_metric() {
    local method="$1"
    local path="$2"
    local status="$3"
    local command="${4:-}"
    local duration_ms="${5:-0}"

    ensure_runtime_dirs

    jq -cn \
        --arg timestamp "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
        --arg method "$method" \
        --arg path "$path" \
        --arg status "$status" \
        --arg command "$command" \
        --argjson duration_ms "$duration_ms" \
        '{timestamp: $timestamp, method: $method, path: $path, status: $status, command: $command, duration_ms: $duration_ms}' \
        >>"$OPSBRIDGE_RUNTIME_DIR/metrics.jsonl"
}

metrics_json() {
    ensure_runtime_dirs

    if [[ ! -s "$OPSBRIDGE_RUNTIME_DIR/metrics.jsonl" ]]; then
        jq -cn '{requests_total: 0, executions_total: 0, failures_total: 0, average_duration_ms: 0}'
        return
    fi

    jq -s '
        {
            requests_total: length,
            executions_total: map(select(.path == "/execute")) | length,
            failures_total: map(select((.status | startswith("2") | not))) | length,
            average_duration_ms: (
                map(select(.duration_ms > 0) | .duration_ms) as $durations |
                if ($durations | length) == 0 then 0
                else (($durations | add) / ($durations | length) | floor)
                end
            )
        }
    ' "$OPSBRIDGE_RUNTIME_DIR/metrics.jsonl"
}

validate_environment() {
    ensure_runtime_dirs

    if [[ ! -x "$AGENT" ]]; then
        log "ERROR: agent.sh is missing or not executable"
        exit 1
    fi

    if ! command -v jq >/dev/null 2>&1; then
        log "ERROR: jq is required"
        exit 1
    fi

    if [[ -z "${OPSBRIDGE_KEY:-}" ]]; then
        log "ERROR: OPSBRIDGE_KEY is required"
        exit 1
    fi
}

validate_server_environment() {
    validate_environment

    if ! command -v socat >/dev/null 2>&1; then
        log "ERROR: socat is required"
        exit 1
    fi
}

validate_command_target() {
    local command="$1"
    local target="$2"

    case "${command}:${target}" in
        health:host|inventory:host|security:host|diagnose:host)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

validate_request_id() {
    local request_id="$1"

    [[ "$request_id" =~ ^[A-Za-z0-9._:-]{8,128}$ ]]
}

validate_request_shape() {
    local request="$1"

    jq -e '
        (.command | type == "string") and
        (.target | type == "string") and
        (.request_id | type == "string") and
        ((.parameters // {}) | type == "object")
    ' >/dev/null <<<"$request"
}

validate_parameter_contract() {
    local request="$1"

    jq -er \
        --argjson key_limit "$OPSBRIDGE_MAX_PARAMETER_KEY_LENGTH" \
        --argjson value_limit "$OPSBRIDGE_MAX_PARAMETER_VALUE_LENGTH" \
        '
            (.parameters // {}) |
            to_entries |
            all(
                (.key | test("^[A-Za-z_][A-Za-z0-9_]*$")) and
                (.key | length <= $key_limit) and
                (.value | tostring | length <= $value_limit) and
                (.value | tostring | test("[[:space:]]") | not)
            )
        ' <<<"$request" >/dev/null
}

rate_limit_allows() {
    ensure_runtime_dirs

    local state_file="$OPSBRIDGE_RUNTIME_DIR/rate-limit.timestamps"
    local lock_file="$OPSBRIDGE_RUNTIME_DIR/rate-limit.lock"
    local temp_file
    local now
    local cutoff
    local count
    local allowed=1

    temp_file="$(mktemp "$OPSBRIDGE_RUNTIME_DIR/rate-limit.XXXXXX")"
    now="$(date +%s)"
    cutoff=$((now - 60))
    touch "$state_file"

    {
        if command -v flock >/dev/null 2>&1; then
            flock -x 201
        fi

        awk -v cutoff="$cutoff" '$1 >= cutoff' "$state_file" >"$temp_file"
        count="$(wc -l <"$temp_file" | tr -dc '0-9')"

        if (( count < OPSBRIDGE_RATE_LIMIT_PER_MINUTE )); then
            printf '%s\n' "$now" >>"$temp_file"
            mv "$temp_file" "$state_file"
            allowed=0
        fi
    } 201>"$lock_file"

    rm -f "$temp_file" 2>/dev/null || true
    return "$allowed"
}

replay_allows() {
    local request_id="$1"
    local replay_file="$OPSBRIDGE_RUNTIME_DIR/replay/$request_id"
    local now
    local modified

    ensure_runtime_dirs
    now="$(date +%s)"

    if [[ -e "$replay_file" ]]; then
        modified="$(stat -c %Y "$replay_file" 2>/dev/null || printf '%s' "$now")"

        if (( now - modified <= OPSBRIDGE_REPLAY_TTL_SECONDS )); then
            return 1
        fi
    fi

    printf '%s\n' "$now" >"$replay_file"
}

execute_agent() {
    local command="$1"
    local target="$2"
    local parameters="${3:-}"
    local result
    local exit_code
    local error_file

    error_file="$(mktemp "$OPSBRIDGE_RUNTIME_DIR/agent-error.XXXXXX")"

    set +e
    result="$("$AGENT" "$command" "$target" "$parameters" 2>"$error_file")"
    exit_code=$?
    set -e

    if (( $(byte_count "$result") > OPSBRIDGE_MAX_OUTPUT_SIZE )); then
        rm -f "$error_file"
        json_error "Agent output exceeded maximum allowed size"
        return
    fi

    if [[ "$exit_code" -ne 0 ]]; then
        if jq -e . >/dev/null 2>&1 <<<"$result"; then
            rm -f "$error_file"
            json_agent_result "$result"
            return
        fi

        local error_message
        error_message="$(head -c 2048 "$error_file" 2>/dev/null || true)"
        rm -f "$error_file"

        jq -cn \
            --arg message "$error_message" \
            --argjson exit_code "$exit_code" \
            '{success: false, exit_code: $exit_code, error: $message}'
        return
    fi

    rm -f "$error_file"

    if ! jq -e . >/dev/null 2>&1 <<<"$result"; then
        json_error "agent.sh returned invalid JSON"
        return
    fi

    json_agent_result "$result"
}

process_execute_request() {
    local request="$1"
    local command
    local target
    local request_id
    local parameters

    HTTP_STATUS="200 OK"

    if ! jq -e . >/dev/null 2>&1 <<<"$request"; then
        HTTP_STATUS="400 Bad Request"
        audit_event "INVALID_JSON" "Invalid JSON request"
        json_error "Invalid JSON request"
        return
    fi

    if ! validate_request_shape "$request"; then
        HTTP_STATUS="400 Bad Request"
        audit_event "INVALID_REQUEST" "Missing or invalid command, target, request_id, or parameters"
        json_error "Missing or invalid command, target, request_id, or parameters"
        return
    fi

    command="$(jq -r '.command' <<<"$request")"
    target="$(jq -r '.target' <<<"$request")"
    request_id="$(jq -r '.request_id' <<<"$request")"

    if (( ${#command} > OPSBRIDGE_MAX_COMMAND_LENGTH || ${#target} > OPSBRIDGE_MAX_TARGET_LENGTH )); then
        HTTP_STATUS="400 Bad Request"
        audit_event "REQUEST_LIMIT" "Command or target exceeded length limit" "$request_id"
        json_error "Command or target exceeded length limit"
        return
    fi

    if ! validate_request_id "$request_id"; then
        HTTP_STATUS="400 Bad Request"
        audit_event "INVALID_REQUEST_ID" "Invalid request_id" "$request_id"
        json_error "Invalid request_id"
        return
    fi

    if ! validate_parameter_contract "$request"; then
        HTTP_STATUS="400 Bad Request"
        audit_event "INVALID_PARAMETERS" "Parameters failed bridge contract validation" "$request_id"
        json_error "Invalid parameters"
        return
    fi

    if ! replay_allows "$request_id"; then
        HTTP_STATUS="409 Conflict"
        audit_event "REPLAY_REJECTED" "Duplicate request_id rejected" "$request_id"
        json_error "Duplicate request_id"
        return
    fi

    if ! validate_command_target "$command" "$target"; then
        HTTP_STATUS="400 Bad Request"
        audit_event "UNSUPPORTED_COMMAND" "Unsupported command/target: ${command}/${target}" "$request_id"
        json_error "Unsupported command/target: ${command}/${target}"
        return
    fi

    parameters="$(
        jq -er '
            (.parameters // {}) |
            to_entries |
            map("\(.key)=\(.value|tostring)") |
            join(" ")
        ' <<<"$request"
    )"

    execute_agent "$command" "$target" "$parameters"
}

ready_json() {
    local ready=true
    local issues=()

    [[ -x "$AGENT" ]] || issues+=("agent_not_executable")
    command -v jq >/dev/null 2>&1 || issues+=("jq_missing")
    command -v socat >/dev/null 2>&1 || issues+=("socat_missing")
    [[ -n "${OPSBRIDGE_KEY:-}" ]] || issues+=("key_missing")

    if ((${#issues[@]} > 0)); then
        ready=false
    fi

    printf '%s\n' "${issues[@]}" |
        jq -Rsc \
            --arg version "$OPSBRIDGE_VERSION" \
            --argjson ready "$ready" \
            '{
                status: (if $ready then "READY" else "NOT_READY" end),
                version: $version,
                issues: (split("\n") | map(select(length > 0)))
            }'
}

handle_connection() {
    local request_line=""
    local method=""
    local path=""
    local version=""
    local content_length=0
    local authorization_key=""
    local header_name=""
    local header_value=""
    local header=""
    local request_body=""
    local response=""
    local started_ms
    local finished_ms
    local status_code

    started_ms="$(date +%s%3N)"
    IFS= read -r request_line || true
    request_line="${request_line%$'\r'}"

    if (( ${#request_line} > OPSBRIDGE_MAX_REQUEST_LINE_LENGTH )); then
        response="$(json_error "Request line too large")"
        http_response "414 URI Too Long" "$response"
        record_metric "" "" "414" "" 0
        return
    fi

    read -r method path version <<<"$request_line"
    log "Request: ${method} ${path} ${version}"

    while IFS= read -r header; do
        header="${header%$'\r'}"
        [[ -z "$header" ]] && break

        if (( ${#header} > OPSBRIDGE_MAX_HEADER_LENGTH )); then
            response="$(json_error "Header too large")"
            http_response "431 Request Header Fields Too Large" "$response"
            record_metric "$method" "$path" "431" "" 0
            return
        fi

        header_name="${header%%:*}"
        header_value="${header#*:}"
        header_name="$(printf '%s' "$header_name" | tr '[:upper:]' '[:lower:]')"
        header_value="$(printf '%s' "$header_value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

        case "$header_name" in
            content-length)
                content_length="${header_value//[[:space:]]/}"
                ;;
            x-opsbridge-key)
                authorization_key="$header_value"
                ;;
        esac
    done

    if [[ "$version" != "HTTP/1.0" && "$version" != "HTTP/1.1" ]]; then
        response="$(json_error "Unsupported HTTP version")"
        http_response "400 Bad Request" "$response"
        record_metric "$method" "$path" "400" "" 0
        return
    fi

    case "${method}:${path}" in
        GET:/health)
            response="$(jq -cn --arg version "$OPSBRIDGE_VERSION" '{status: "OK", version: $version}')"
            http_response "200 OK" "$response"
            record_metric "$method" "$path" "200" "" 0
            return
            ;;
        GET:/ready)
            response="$(ready_json)"
            if jq -e '.status == "READY"' >/dev/null <<<"$response"; then
                http_response "200 OK" "$response"
                record_metric "$method" "$path" "200" "" 0
            else
                http_response "503 Service Unavailable" "$response"
                record_metric "$method" "$path" "503" "" 0
            fi
            return
            ;;
        GET:/metrics)
            if ! constant_time_equals "$(hash_value "$authorization_key")" "$(hash_value "$OPSBRIDGE_KEY")"; then
                audit_event "AUTH_FAILURE" "Unauthorized metrics request"
                response="$(json_error "Unauthorized")"
                http_response "401 Unauthorized" "$response"
                record_metric "$method" "$path" "401" "" 0
                return
            fi
            response="$(metrics_json)"
            http_response "200 OK" "$response"
            record_metric "$method" "$path" "200" "" 0
            return
            ;;
    esac

    if [[ "$method" != "POST" ]]; then
        response="$(json_error "Only POST is supported")"
        http_response "405 Method Not Allowed" "$response"
        record_metric "$method" "$path" "405" "" 0
        return
    fi

    if [[ "$path" != "/execute" ]]; then
        response="$(json_error "Endpoint not found")"
        http_response "404 Not Found" "$response"
        record_metric "$method" "$path" "404" "" 0
        return
    fi

    if ! constant_time_equals "$(hash_value "$authorization_key")" "$(hash_value "$OPSBRIDGE_KEY")"; then
        audit_event "AUTH_FAILURE" "Unauthorized execute request"
        response="$(json_error "Unauthorized")"
        http_response "401 Unauthorized" "$response"
        record_metric "$method" "$path" "401" "" 0
        return
    fi

    if ! rate_limit_allows; then
        audit_event "RATE_LIMIT" "Request rejected by rate limit"
        response="$(json_error "Rate limit exceeded")"
        http_response "429 Too Many Requests" "$response"
        record_metric "$method" "$path" "429" "" 0
        return
    fi

    if ! [[ "$content_length" =~ ^[0-9]+$ ]]; then
        response="$(json_error "Invalid Content-Length")"
        http_response "400 Bad Request" "$response"
        record_metric "$method" "$path" "400" "" 0
        return
    fi

    if (( content_length > OPSBRIDGE_MAX_BODY_SIZE )); then
        audit_event "REQUEST_LIMIT" "Request body exceeded limit"
        response="$(json_error "Request body too large")"
        http_response "413 Payload Too Large" "$response"
        record_metric "$method" "$path" "413" "" 0
        return
    fi

    if (( content_length > 0 )); then
        request_body="$(head -c "$content_length")"
    fi

    response="$(process_execute_request "$request_body")"
    finished_ms="$(date +%s%3N)"
    status_code="${HTTP_STATUS%% *}"

    http_response "$HTTP_STATUS" "$response"
    record_metric "$method" "$path" "$status_code" "$(jq -r '.result.command // ""' <<<"$response" 2>/dev/null || true)" "$((finished_ms - started_ms))"
}

run_server() {
    log "========================================"
    log "OpsBridge HTTP Bridge"
    log "========================================"
    log "Host: $HOST"
    log "Port: $PORT"
    log "Agent: $AGENT"
    log "Runtime: $OPSBRIDGE_RUNTIME_DIR"
    log "Authentication: ENABLED"

    export OPSBRIDGE_KEY OPSBRIDGE_CONFIG

    exec socat \
        TCP-LISTEN:"$PORT",bind="$HOST",reuseaddr,fork \
        EXEC:"${SCRIPT_DIR}/bridge.sh --connection"
}

doctor() {
    local failed=false

    printf 'OpsBridge doctor\n'
    printf 'config_file=%s\n' "$CONFIG_FILE"
    printf 'runtime_dir=%s\n' "$OPSBRIDGE_RUNTIME_DIR"

    if [[ -x "$AGENT" ]]; then
        printf 'agent=OK\n'
    else
        printf 'agent=FAILED\n'
        failed=true
    fi

    for dependency in bash jq socat; do
        if command -v "$dependency" >/dev/null 2>&1; then
            printf '%s=OK\n' "$dependency"
        else
            printf '%s=MISSING\n' "$dependency"
            failed=true
        fi
    done

    if [[ -n "$OPSBRIDGE_KEY" ]]; then
        printf 'opsbridge_key=SET\n'
    else
        printf 'opsbridge_key=MISSING\n'
        failed=true
    fi

    [[ "$failed" == false ]]
}

main() {
    case "${1:-server}" in
        --connection)
            validate_environment
            handle_connection
            ;;
        doctor)
            doctor
            ;;
        *)
            validate_server_environment
            run_server
            ;;
    esac
}

main "$@"
