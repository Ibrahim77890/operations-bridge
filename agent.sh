#!/usr/bin/env bash

set -Eeuo pipefail

source "$(dirname "$0")/operations.sh"

readonly AGENT_VERSION="0.1.0"
readonly SCRIPT_NAME="$(basename "$0")"

WORK_DIR=""

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

main() {
    local command="${1:-}"
    local target="${2:-}"

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

    case "$command" in
        health)
            health_host
            ;;

        inventory)
            inventory_host
            ;;
    esac
}


trap on_error ERR
trap cleanup EXIT



main "$@"
