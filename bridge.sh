#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENT="${SCRIPT_DIR}/agent.sh"

HOST="${OPSBRIDGE_HOST:-127.0.0.1}"
PORT="${OPSBRIDGE_PORT:-8080}"
OPSBRIDGE_KEY="${OPSBRIDGE_KEY:-}"

LOG_PREFIX="[BRIDGE]"


log() {
    printf '%s %s\n' "$LOG_PREFIX" "$*" >&2
}


json_error() {
    local message="$1"

    jq -cn \
        --arg message "$message" \
        '{
            success: false,
            error: $message
        }'
}


json_success() {
    local result="$1"

    jq -cn \
        --argjson result "$result" \
        '{
            success: true,
            execution_id: ($result.execution_id // ""),
            result: $result
        }'
}


http_response() {
    local status="$1"
    local body="$2"

    local content_length
    content_length=$(printf '%s' "$body" | wc -c)

    printf 'HTTP/1.1 %s\r\n' "$status"
    printf 'Content-Type: application/json\r\n'
    printf 'Content-Length: %s\r\n' "$content_length"
    printf 'Connection: close\r\n'
    printf '\r\n'
    printf '%s' "$body"
}


validate_environment() {

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

        health:host)
            return 0
            ;;

        inventory:host)
            return 0
            ;;

        *)
            return 1
            ;;

    esac
}


execute_agent() {

    local command="$1"
    local target="$2"

    local result
    local exit_code
    local error_file

    error_file="$(mktemp)"

    set +e

    result="$(
        "$AGENT" "$command" "$target" \
        2>"$error_file"
    )"

    exit_code=$?

    set -e

    if [[ "$exit_code" -ne 0 ]]; then

        local error_message

        error_message="$(cat "$error_file" 2>/dev/null || true)"

        rm -f "$error_file"

        jq -cn \
            --arg message "$error_message" \
            --argjson exit_code "$exit_code" \
            '{
                success: false,
                exit_code: $exit_code,
                error: $message
            }'

        return
    fi

    rm -f "$error_file"

    if ! jq -e . >/dev/null 2>&1 <<< "$result"; then

        json_error "agent.sh returned invalid JSON"

        return
    fi

    json_success "$result"
}


process_request() {

    local request="$1"

    if ! jq -e . >/dev/null 2>&1 <<< "$request"; then
        json_error "Invalid JSON request"
        return
    fi

    local command

    command="$(
        jq -er '.command // empty' <<< "$request"
    )" || {
        json_error "Missing command"
        return
    }


    local target

    target="$(
        jq -er '.target // empty' <<< "$request"
    )" || {
        json_error "Missing target"
        return
    }


    if ! validate_command_target "$command" "$target"; then

        json_error \
            "Unsupported command/target: ${command}/${target}"

        return
    fi


    execute_agent "$command" "$target"
}


handle_connection() {

    local request_line=""

    IFS= read -r request_line || true

    request_line="${request_line%$'\r'}"

    local method=""
    local path=""
    local version=""

    read -r method path version <<< "$request_line"


    log "Request: ${method} ${path} ${version}"


    # --------------------------------------------------------
    # Read headers
    # --------------------------------------------------------

    local content_length=0
    local authorization_key=""
    local header_name=""
    local header_value=""

    while IFS= read -r header; do

        # Remove CR from HTTP CRLF.
        header="${header%$'\r'}"

        # Empty line means headers are finished.
        [[ -z "$header" ]] && break

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

    log "Content-Length parsed as: [$content_length]"
    log "Auth header present: $([[ -n "$authorization_key" ]] && printf yes || printf no)"

    # --------------------------------------------------------
    # Validate HTTP version
    # --------------------------------------------------------

    if [[ "$version" != "HTTP/1.0" &&
          "$version" != "HTTP/1.1" ]]; then

        http_response \
            "400 Bad Request" \
            "$(json_error "Unsupported HTTP version")"

        return
    fi


    # --------------------------------------------------------
    # Validate method
    # --------------------------------------------------------

    if [[ "$method" != "POST" ]]; then

        http_response \
            "405 Method Not Allowed" \
            "$(json_error "Only POST is supported")"

        return
    fi


    # --------------------------------------------------------
    # Validate endpoint
    # --------------------------------------------------------

    if [[ "$path" != "/execute" ]]; then

        http_response \
            "404 Not Found" \
            "$(json_error "Endpoint not found")"

        return
    fi


    # --------------------------------------------------------
    # Validate authentication
    # --------------------------------------------------------

    if [[ "$authorization_key" != "$OPSBRIDGE_KEY" ]]; then

        http_response \
            "401 Unauthorized" \
            "$(json_error "Unauthorized")"

        return
    fi


    # --------------------------------------------------------
    # Validate Content-Length
    # --------------------------------------------------------

    if ! [[ "$content_length" =~ ^[0-9]+$ ]]; then

        http_response \
            "400 Bad Request" \
            "$(json_error "Invalid Content-Length")"

        return
    fi


    # --------------------------------------------------------
    # Read body
    # --------------------------------------------------------

    local request_body=""

    if (( content_length > 0 )); then
        request_body="$(head -c "$content_length")"
    fi


    # --------------------------------------------------------
    # Process
    # --------------------------------------------------------

    local response

    response="$(
        process_request "$request_body"
    )"


    # --------------------------------------------------------
    # Return HTTP response
    # --------------------------------------------------------

    http_response \
        "200 OK" \
        "$response"
}


run_server() {

    log "========================================"
    log "OpsBridge HTTP Bridge"
    log "========================================"

    log "Host: $HOST"
    log "Port: $PORT"
    log "Agent: $AGENT"

    log "Authentication: ENABLED"

    export OPSBRIDGE_KEY

    exec socat \
        TCP-LISTEN:"$PORT",bind="$HOST",reuseaddr,fork \
        EXEC:"${SCRIPT_DIR}/bridge.sh --connection"
}


main() {
    case "${1:-server}" in

        --connection)
            validate_environment
            handle_connection
            ;;

        *)
            validate_server_environment
            run_server
            ;;

    esac
}


main "$@"
