get_hostname() {
    hostname 2>/dev/null || printf 'unknown'
}

get_os_info() {
    local distribution="unknown"
    local distribution_id="unknown"
    local version="unknown"

    if [[ -r /etc/os-release ]]; then
        distribution="$(
            . /etc/os-release
            printf '%s' "${PRETTY_NAME:-${NAME:-unknown}}"
        )"
        distribution_id="$(
            . /etc/os-release
            printf '%s' "${ID:-unknown}"
        )"
        version="$(
            . /etc/os-release
            printf '%s' "${VERSION_ID:-unknown}"
        )"
    else
        distribution="$(uname -s 2>/dev/null || printf 'unknown')"
    fi

    jq -n \
        --arg distribution "$distribution" \
        --arg distribution_id "$distribution_id" \
        --arg version "$version" \
        '{distribution: $distribution, distribution_id: $distribution_id, version: $version}'
}

get_kernel_info() {
    local kernel="unknown"
    local architecture="unknown"

    kernel="$(uname -r 2>/dev/null || printf 'unknown')"
    architecture="$(uname -m 2>/dev/null || printf 'unknown')"

    jq -n \
        --arg kernel "$kernel" \
        --arg architecture "$architecture" \
        '{kernel: $kernel, architecture: $architecture}'
}

get_system_info() {
    local hostname_value
    local os_json
    local kernel_json

    hostname_value="$(get_hostname)"
    os_json="$(get_os_info)"
    kernel_json="$(get_kernel_info)"

    jq -n \
        --arg hostname "$hostname_value" \
        --argjson os "$os_json" \
        --argjson kernel "$kernel_json" \
        '{
            hostname: $hostname,
            kernel: $kernel.kernel,
            architecture: $kernel.architecture,
            distribution: $os.distribution,
            distribution_id: $os.distribution_id,
            version: $os.version
        }'
}

get_cpu_info() {
    local cores=0
    local model="unknown"

    if command -v nproc >/dev/null 2>&1; then
        cores="$(nproc)"
    elif [[ -r /proc/cpuinfo ]]; then
        cores="$(awk '/^processor[[:space:]]*:/ {count++} END {print count + 0}' /proc/cpuinfo)"
    fi

    if [[ -r /proc/cpuinfo ]]; then
        model="$(awk -F': ' '/model name/ {print $2; exit}' /proc/cpuinfo)"
        [[ -n "$model" ]] || model="unknown"
    elif command -v sysctl >/dev/null 2>&1; then
        model="$(sysctl -n machdep.cpu.brand_string 2>/dev/null || printf 'unknown')"
    fi

    jq -n \
        --arg model "$model" \
        --argjson cores "$cores" \
        '{cores: $cores, model: $model}'
}

get_memory_info() {
    local total_mb=0
    local available_mb=0
    local used_mb=0

    if [[ -r /proc/meminfo ]]; then
        total_mb="$(awk '/MemTotal/ {printf "%.0f", $2 / 1024}' /proc/meminfo)"
        available_mb="$(awk '/MemAvailable/ {printf "%.0f", $2 / 1024}' /proc/meminfo)"

        if [[ -z "$available_mb" ]]; then
            available_mb="$(awk '/MemFree/ {printf "%.0f", $2 / 1024}' /proc/meminfo)"
        fi

        [[ "$total_mb" =~ ^[0-9]+$ ]] || total_mb=0
        [[ "$available_mb" =~ ^[0-9]+$ ]] || available_mb=0
        used_mb=$((total_mb - available_mb))

        if (( used_mb < 0 )); then
            used_mb=0
        fi
    fi

    jq -n \
        --argjson total_mb "$total_mb" \
        --argjson available_mb "$available_mb" \
        --argjson used_mb "$used_mb" \
        '{total_mb: $total_mb, available_mb: $available_mb, used_mb: $used_mb}'
}

get_disk_info() {
    local total_kb=0
    local used_kb=0
    local available_kb=0
    local used_percent=0

    if df -Pk / >/dev/null 2>&1; then
        read -r total_kb used_kb available_kb used_percent < <(
            df -Pk / |
            awk 'NR == 2 {
                gsub("%", "", $(NF - 1))
                print $(NF - 4), $(NF - 3), $(NF - 2), $(NF - 1)
            }'
        )
    fi

    [[ "$total_kb" =~ ^[0-9]+$ ]] || total_kb=0
    [[ "$used_kb" =~ ^[0-9]+$ ]] || used_kb=0
    [[ "$available_kb" =~ ^[0-9]+$ ]] || available_kb=0
    [[ "$used_percent" =~ ^[0-9]+$ ]] || used_percent=0

    jq -n \
        --argjson root_total_gb "$((total_kb / 1024 / 1024))" \
        --argjson root_used_gb "$((used_kb / 1024 / 1024))" \
        --argjson root_available_gb "$((available_kb / 1024 / 1024))" \
        --argjson root_used_percent "$used_percent" \
        '{
            root_total_gb: $root_total_gb,
            root_used_gb: $root_used_gb,
            root_available_gb: $root_available_gb,
            root_used_percent: $root_used_percent
        }'
}

cpu_load_1m() {
    awk '{print $1}' /proc/loadavg 2>/dev/null || printf '0'
}

memory_used_percent() {
    local total
    local available

    total="$(awk '/MemTotal/ {print $2}' /proc/meminfo 2>/dev/null || printf '0')"
    available="$(awk '/MemAvailable/ {print $2}' /proc/meminfo 2>/dev/null || true)"

    if [[ -z "$available" ]]; then
        available="$(awk '/MemFree/ {print $2}' /proc/meminfo 2>/dev/null || printf '0')"
    fi

    [[ "$total" =~ ^[0-9]+$ ]] || total=0
    [[ "$available" =~ ^[0-9]+$ ]] || available=0

    if (( total == 0 )); then
        printf '0'
    else
        printf '%s' "$((100 - (available * 100 / total)))"
    fi
}

disk_used_percent() {
    df -Pk / 2>/dev/null |
        awk 'NR == 2 {gsub("%", "", $(NF - 1)); print $(NF - 1)}' |
        tr -dc '0-9'
}
