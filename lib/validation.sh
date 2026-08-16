declare -gA OPS_PARAMS=()

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

validate_integer_range() {
    local name="$1"
    local value="$2"
    local min="$3"
    local max="$4"

    if ! [[ "$value" =~ ^[0-9]+$ ]]; then
        die "Parameter $name must be an integer"
    fi

    if (( value < min || value > max )); then
        die "Parameter $name must be between $min and $max"
    fi
}

validate_boolean() {
    local name="$1"
    local value="$2"

    case "$value" in
        true|false)
            return 0
            ;;
        *)
            die "Parameter $name must be true or false"
            ;;
    esac
}

validate_operation_parameter() {
    local command="$1"
    local key="$2"
    local value="$3"

    case "$command:$key" in
        health:disk_threshold|health:memory_threshold)
            validate_integer_range "$key" "$value" 1 100
            ;;
        diagnose:cpu_threshold|diagnose:memory_threshold|diagnose:disk_threshold)
            validate_integer_range "$key" "$value" 1 100
            ;;
        inventory:include_network)
            validate_boolean "$key" "$value"
            ;;
        *)
            die "Unsupported parameter for $command: $key"
            ;;
    esac
}

parse_parameters() {
    local command="$1"
    local parameter_string="${2:-}"
    local token
    local key
    local value

    OPS_PARAMS=()

    [[ -n "$parameter_string" ]] || return 0

    for token in $parameter_string; do
        if [[ "$token" != *=* ]]; then
            die "Invalid parameter: $token"
        fi

        key="${token%%=*}"
        value="${token#*=}"

        [[ -n "$key" ]] || die "Invalid parameter: $token"
        [[ -n "$value" ]] || die "Parameter $key must have a value"

        validate_operation_parameter "$command" "$key" "$value"
        OPS_PARAMS["$key"]="$value"
    done
}

param_get() {
    local key="$1"
    local default_value="$2"

    printf '%s' "${OPS_PARAMS[$key]:-$default_value}"
}

parameters_json() {
    local first=true
    local key

    printf '{'
    for key in "${!OPS_PARAMS[@]}"; do
        if [[ "$first" == false ]]; then
            printf ','
        fi
        first=false
        printf '"%s":"%s"' "$(json_escape "$key")" "$(json_escape "${OPS_PARAMS[$key]}")"
    done
    printf '}'
}
