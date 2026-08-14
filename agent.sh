#!/usr/bin/env bash

set -Eeuo pipefail

source "$(dirname "$0")/operations.sh"

readonly AGENT_VERSION="0.1.0"
readonly SCRIPT_NAME="$(basename "$0")"

WORK_DIR=""
EXECUTION_ID=""
START_TIME=0
END_TIME=0

LOCK_FILE="/tmp/opsbridge.lock"
LOCK_FD=200
LOCK_DIR=""

acquire_lock() {
    if command -v flock >/dev/null 2>&1; then
        eval "exec $LOCK_FD>$LOCK_FILE"

        if ! flock -n "$LOCK_FD"; then
            die "Another Operations Bridge execution is already running"
        fi

        return
    fi

    LOCK_DIR="${LOCK_FILE}.dir"

    if ! mkdir "$LOCK_DIR" 2>/dev/null; then
        die "Another Operations Bridge execution is already running"
    fi
}

log() {
    local level="$1"
    shift

    printf '[%s] [%s] %s\n' \
        "$(date '+%Y-%m-%d %H:%M:%S')" \
        "$level" \
        "$*" >&2
}

info() {
    log "INFO" "$@"
}

warn() {
    log "WARN" "$@"
}

error() {
    log "ERROR" "$@"
}

die() {
    error "$*"
    exit 1
}

on_error() {
    local exit_code=$?

    error "Unexpected failure at line ${BASH_LINENO[0]}"
    exit "$exit_code"
}

setup_workspace() {
    WORK_DIR="$(mktemp -d)"
    info "Workspace: $WORK_DIR"
}

cleanup() {
    if [[ -n "${WORK_DIR:-}" && -d "$WORK_DIR" ]]; then
        rm -rf "$WORK_DIR"
    fi

    if [[ -n "${LOCK_DIR:-}" && -d "$LOCK_DIR" ]]; then
        rmdir "$LOCK_DIR"
    fi
}

validate_command() {
    case "$1" in
        health|inventory)
            return 0
            ;;
        help|-h|--help)
            return 0
            ;;
        *)
            die "Unsupported command: $1"
            ;;
    esac
}

validate_target() {
    case "$1" in
        host)
            return 0
            ;;
        *)
            die "Unsupported target: $1"
            ;;
    esac
}

usage() {
    cat <<EOF
Usage:
    $SCRIPT_NAME <command> <target>

Commands:
    health       Run health checks
    inventory    Inspect target
    help         Show this help

Targets:
    host

Examples:
    $SCRIPT_NAME health host
    $SCRIPT_NAME inventory host
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

main() {
    acquire_lock
    
    local command="${1:-}"
    local target="${2:-}"

    EXECUTION_ID="$(generate_execution_id)"

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

    setup_workspace
    info "Execution ID: $EXECUTION_ID"

    case "$command" in
        health)
            start_timer
            health_host
            stop_timer
            emit_health_result
            ;;

        inventory)
            start_timer
            inventory_host
            stop_timer
            emit_inventory_result
            ;;
    esac
}


trap on_error ERR
trap cleanup EXIT



main "$@"
