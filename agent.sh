#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/lib/logging.sh"
source "$SCRIPT_DIR/lib/json.sh"
source "$SCRIPT_DIR/lib/validation.sh"
source "$SCRIPT_DIR/lib/system.sh"
source "$SCRIPT_DIR/lib/network.sh"
source "$SCRIPT_DIR/lib/security.sh"
source "$SCRIPT_DIR/commands/health.sh"
source "$SCRIPT_DIR/commands/inventory.sh"
source "$SCRIPT_DIR/commands/security.sh"
source "$SCRIPT_DIR/commands/diagnose.sh"

readonly AGENT_VERSION="0.1.0"
readonly SCRIPT_NAME="$(basename "$0")"

WORK_DIR=""
EXECUTION_ID=""
START_TIME=0
END_TIME=0
FINAL_STATUS="SUCCESS"
LOCK_FILE="/tmp/opsbridge.lock"
LOCK_FD=200
LOCK_DIR=""
LOCK_HELD=false

acquire_lock() {
    if command -v flock >/dev/null 2>&1; then
        eval "exec $LOCK_FD>$LOCK_FILE"

        if ! flock -n "$LOCK_FD"; then
            return 1
        fi

        LOCK_HELD=true
        return
    fi

    local candidate_lock_dir="${LOCK_FILE}.dir"

    if ! mkdir "$candidate_lock_dir" 2>/dev/null; then
        return 1
    fi

    LOCK_DIR="$candidate_lock_dir"
    LOCK_HELD=true
}

on_error() {
    local exit_code=$?

    error "ERROR" "Unexpected failure at line ${BASH_LINENO[0]}"
    exit "$exit_code"
}

setup_workspace() {
    WORK_DIR="$(mktemp -d)"
    info "WORKSPACE" "path=$WORK_DIR"
}

cleanup() {
    if [[ -n "${WORK_DIR:-}" && -d "$WORK_DIR" ]]; then
        rm -rf "$WORK_DIR"
    fi

    if [[ "$LOCK_HELD" == true && -n "${LOCK_DIR:-}" && -d "$LOCK_DIR" ]]; then
        rmdir "$LOCK_DIR" 2>/dev/null || true
    fi
}

usage() {
    cat <<EOF
Usage:
    $SCRIPT_NAME <command> <target> [parameters]

Commands:
    health       Run health checks
    inventory    Inspect target
    security     Audit host security posture
    diagnose     Diagnose likely host problems
    help         Show this help

Targets:
    host

Examples:
    $SCRIPT_NAME health host
    $SCRIPT_NAME health host "disk_threshold=80"
    $SCRIPT_NAME inventory host
    $SCRIPT_NAME security host
    $SCRIPT_NAME diagnose host
EOF
}

generate_execution_id() {
    printf 'EXEC-%s-%s' \
        "$(date '+%Y%m%d%H%M%S')" \
        "$$"
}

start_timer() {
    START_TIME="$(date +%s%3N)"
}

stop_timer() {
    END_TIME="$(date +%s%3N)"
}

duration_ms() {
    printf '%s' "$((END_TIME - START_TIME))"
}

dispatch_command() {
    local command="$1"

    case "$command" in
        health)
            health_host
            stop_timer
            emit_health_result
            ;;
        inventory)
            inventory_host
            stop_timer
            emit_inventory_result
            ;;
        security)
            security_host
            stop_timer
            emit_security_result
            ;;
        diagnose)
            diagnose_host
            stop_timer
            emit_diagnose_result
            ;;
    esac
}

emit_execution_error_result() {
    local status="$1"
    local message="$2"

    jq -n \
        --arg command "$COMMAND" \
        --arg target "$TARGET" \
        --arg status "$status" \
        --arg execution_id "$EXECUTION_ID" \
        --arg error "$message" \
        --argjson duration_ms "$(duration_ms)" \
        --argjson parameters "$(parameters_json)" \
        '{
            command: $command,
            target: $target,
            status: $status,
            execution_id: $execution_id,
            duration_ms: $duration_ms,
            parameters: $parameters,
            error: $error
        }'
}

run_attempt_with_timeout() {
    local command="$1"
    local timeout_seconds="$2"
    local pid
    local started
    local now

    dispatch_command "$command" &
    pid=$!
    started="$(date +%s)"

    while kill -0 "$pid" 2>/dev/null; do
        now="$(date +%s)"
        if (( now - started >= timeout_seconds )); then
            kill "$pid" 2>/dev/null || true
            wait "$pid" 2>/dev/null || true
            return 124
        fi
        sleep 1
    done

    wait "$pid"
}

execute_with_policy() {
    local command="$1"
    local retries
    local timeout_seconds
    local max_attempts
    local attempt=1
    local delay=1
    local exit_code=1

    retries="$(param_get "retries" "0")"
    timeout_seconds="$(param_get "timeout" "30")"
    max_attempts=$((retries + 1))

    start_timer
    info "START" "operation=$command target=$TARGET retries=$retries timeout=${timeout_seconds}s"

    while (( attempt <= max_attempts )); do
        info "ATTEMPT" "attempt=$attempt max_attempts=$max_attempts"
        if run_attempt_with_timeout "$command" "$timeout_seconds"; then
            exit_code=0
        else
            exit_code=$?
        fi

        if (( exit_code == 0 )); then
            stop_timer
            info "COMPLETE" "status=SUCCESS duration_ms=$(duration_ms)"
            return 0
        fi

        if (( exit_code == 124 )); then
            warn "TIMEOUT" "attempt=$attempt timeout=${timeout_seconds}s"
            FINAL_STATUS="TIMEOUT"
        else
            warn "FAILED" "attempt=$attempt exit_code=$exit_code"
            FINAL_STATUS="FAILED"
        fi

        if (( attempt == max_attempts )); then
            stop_timer
            error "COMPLETE" "status=$FINAL_STATUS duration_ms=$(duration_ms)"
            if [[ "$FINAL_STATUS" == "TIMEOUT" ]]; then
                emit_execution_error_result "TIMEOUT" "Operation exceeded ${timeout_seconds} seconds"
            else
                emit_execution_error_result "FAILED" "Operation failed after ${max_attempts} attempt(s)"
            fi
            return 1
        fi

        warn "RETRY" "attempt=$attempt next_delay=${delay}s"
        sleep "$delay"
        delay=$((delay * 2))
        if (( delay > 16 )); then
            delay=16
        fi
        attempt=$((attempt + 1))
    done
}

main() {
    local command="${1:-}"
    local target="${2:-}"
    local parameters="${3:-}"

    EXECUTION_ID="$(generate_execution_id)"
    COMMAND="$command"
    TARGET="$target"

    if [[ -z "$command" ]]; then
        usage
        exit 1
    fi

    if [[ "$command" == "help" ||
          "$command" == "-h" ||
          "$command" == "--help" ]]; then
        usage
        exit 0
    fi

    validate_command "$command"
    [[ -n "$target" ]] || die "Target is required"
    validate_target "$target"
    parse_parameters "$command" "$parameters"

    setup_workspace
    info "EXECUTION" "id=$EXECUTION_ID"

    if ! acquire_lock; then
        start_timer
        stop_timer
        error "LOCKED" "Another Operations Bridge execution is already running"
        emit_execution_error_result "FAILED" "Another Operations Bridge execution is already running"
        exit 1
    fi

    if execute_with_policy "$command"; then
        return 0
    fi

    return 1
}

trap on_error ERR
trap cleanup EXIT

if main "$@"; then
    exit 0
else
    exit_code=$?
    exit "$exit_code"
fi
