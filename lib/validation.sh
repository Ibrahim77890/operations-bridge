validate_command() {
    case "$1" in
        health|inventory|security|diagnose)
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

require_jq() {
    command -v jq >/dev/null 2>&1 || die "jq is required"
}
