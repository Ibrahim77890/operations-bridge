log() {
    local level="$1"
    local event="$2"
    shift
    shift

    printf '%s %s %s %s %s\n' \
        "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
        "$level" \
        "${EXECUTION_ID:-NO_EXECUTION}" \
        "$event" \
        "$*" >&2
}

info() {
    local event="${1:-INFO}"
    shift || true
    log "INFO" "$event" "$@"
}

warn() {
    local event="${1:-WARN}"
    shift || true
    log "WARN" "$event" "$@"
}

error() {
    local event="${1:-ERROR}"
    shift || true
    log "ERROR" "$event" "$@"
}

die() {
    error "ERROR" "$*"
    exit 1
}
