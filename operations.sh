source "$(dirname "$0")/helpers.sh"

INVENTORY_SYSTEM_JSON="{}"
INVENTORY_CPU_JSON="{}"
INVENTORY_MEMORY_JSON="{}"
INVENTORY_DISK_JSON="{}"
INVENTORY_NETWORK_JSON="{}"
SECURITY_CHECKS_JSON="{}"

health_host() {
    local result_dir
    local pid_cpu
    local pid_memory
    local pid_disk
    local pid_network

    info "Running host health checks"

    CHECK_STATUS=()
    CHECK_VALUE=()
    CHECK_NAMES=()

    result_dir="$WORK_DIR/health-results"
    mkdir -p "$result_dir"

    run_health_check_worker "cpu" check_cpu "$result_dir/cpu.json" &
    pid_cpu=$!

    run_health_check_worker "memory" check_memory "$result_dir/memory.json" &
    pid_memory=$!

    run_health_check_worker "disk" check_disk "$result_dir/disk.json" &
    pid_disk=$!

    run_health_check_worker "network" check_network "$result_dir/network.json" &
    pid_network=$!

    wait "$pid_cpu"
    wait "$pid_memory"
    wait "$pid_disk"
    wait "$pid_network"

    aggregate_check_result_file "$result_dir/cpu.json"
    aggregate_check_result_file "$result_dir/memory.json"
    aggregate_check_result_file "$result_dir/disk.json"
    aggregate_check_result_file "$result_dir/network.json"
}

run_health_check_worker() {
    local name="$1"
    local check_function="$2"
    local output_file="$3"

    CHECK_STATUS=()
    CHECK_VALUE=()
    CHECK_NAMES=()

    if ! "$check_function"; then
        result_add "$name" "ERROR"
    fi

    emit_check_result_file "$output_file" "$name"
}

inventory_host() {
    info "Collecting host inventory"

    if ! command -v jq >/dev/null 2>&1; then
        die "jq is required for inventory"
    fi

    run_inventory
}

run_inventory() {
    INVENTORY_SYSTEM_JSON="$(get_system_info)"
    INVENTORY_CPU_JSON="$(get_cpu_info)"
    INVENTORY_MEMORY_JSON="$(get_memory_info)"
    INVENTORY_DISK_JSON="$(get_disk_info)"
    INVENTORY_NETWORK_JSON="$(get_network_info)"
}

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
        '{
            distribution: $distribution,
            distribution_id: $distribution_id,
            version: $version
        }'
}

get_kernel_info() {
    local kernel="unknown"
    local architecture="unknown"

    kernel="$(uname -r 2>/dev/null || printf 'unknown')"
    architecture="$(uname -m 2>/dev/null || printf 'unknown')"

    jq -n \
        --arg kernel "$kernel" \
        --arg architecture "$architecture" \
        '{
            kernel: $kernel,
            architecture: $architecture
        }'
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
        '{
            cores: $cores,
            model: $model
        }'
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
        '{
            total_mb: $total_mb,
            available_mb: $available_mb,
            used_mb: $used_mb
        }'
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

get_network_info() {
    if command -v ip >/dev/null 2>&1 && ip -j addr show >/dev/null 2>&1; then
        ip -j addr show |
            jq '{
                interfaces: [
                    .[] | {
                        name: .ifname,
                        state: (.operstate // "unknown"),
                        mac: (.address // ""),
                        addresses: [
                            .addr_info[]? | {
                                family: .family,
                                address: .local,
                                prefix_length: .prefixlen
                            }
                        ]
                    }
                ]
            }'
        return
    fi

    if [[ -d /sys/class/net ]]; then
        find /sys/class/net -mindepth 1 -maxdepth 1 -type l -printf '%f\n' |
            while IFS= read -r interface_name; do
                local state="unknown"
                local mac=""

                [[ -r "/sys/class/net/$interface_name/operstate" ]] &&
                    state="$(cat "/sys/class/net/$interface_name/operstate")"

                [[ -r "/sys/class/net/$interface_name/address" ]] &&
                    mac="$(cat "/sys/class/net/$interface_name/address")"

                printf '%s\t%s\t%s\n' "$interface_name" "$state" "$mac"
            done |
            jq -Rn '{
                interfaces: [
                    inputs |
                    split("\t") |
                    {
                        name: .[0],
                        state: .[1],
                        mac: .[2],
                        addresses: []
                    }
                ]
            }'
        return
    fi

    jq -n '{interfaces: []}'
}

emit_inventory_result() {
    jq -n \
        --arg execution_id "${EXECUTION_ID:-}" \
        --argjson duration_ms "$(duration_ms)" \
        --argjson system "$INVENTORY_SYSTEM_JSON" \
        --argjson cpu "$INVENTORY_CPU_JSON" \
        --argjson memory "$INVENTORY_MEMORY_JSON" \
        --argjson disk "$INVENTORY_DISK_JSON" \
        --argjson network "$INVENTORY_NETWORK_JSON" \
        '{
            command: "inventory",
            target: "host",
            status: "OK",
            execution_id: $execution_id,
            duration_ms: $duration_ms,
            system: $system,
            cpu: $cpu,
            memory: $memory,
            disk: $disk,
            network: $network
        }'
}

security_host() {
    info "Auditing host security posture"

    if ! command -v jq >/dev/null 2>&1; then
        die "jq is required for security audit"
    fi

    run_security
}

run_security() {
    SECURITY_CHECKS_JSON="$(
        jq -n \
            --argjson firewall "$(check_firewall_security)" \
            --argjson ssh "$(check_ssh_security)" \
            --argjson open_ports "$(check_open_ports_security)" \
            --argjson users "$(check_users_security)" \
            --argjson sudo "$(check_sudo_security)" \
            --argjson world_writable "$(check_world_writable_security)" \
            --argjson updates "$(check_updates_security)" \
            '{
                firewall: $firewall,
                ssh: $ssh,
                open_ports: $open_ports,
                users: $users,
                sudo: $sudo,
                world_writable: $world_writable,
                updates: $updates
            }'
    )"
}

security_overall_status() {
    jq -r '
        [to_entries[].value.status] as $statuses |
        if any($statuses[]; . == "CRITICAL") then "CRITICAL"
        elif any($statuses[]; . == "WARN" or . == "WARNING") then "WARN"
        elif any($statuses[]; . == "UNKNOWN") then "WARN"
        else "OK"
        end
    ' <<< "$SECURITY_CHECKS_JSON"
}

security_check_json() {
    local status="$1"
    local details="$2"

    jq -n \
        --arg status "$status" \
        --arg details "$details" \
        '{
            status: $status,
            details: $details
        }'
}

check_firewall_security() {
    if command -v ufw >/dev/null 2>&1; then
        local state
        state="$(ufw status 2>/dev/null | awk 'NR == 1 {print tolower($2)}')"

        if [[ "$state" == "active" ]]; then
            security_check_json "OK" "ufw is active"
        else
            security_check_json "WARN" "ufw is not active"
        fi
        return
    fi

    if command -v firewall-cmd >/dev/null 2>&1; then
        if firewall-cmd --state >/dev/null 2>&1; then
            security_check_json "OK" "firewalld is running"
        else
            security_check_json "WARN" "firewalld is not running"
        fi
        return
    fi

    if command -v iptables >/dev/null 2>&1; then
        local rule_count
        rule_count="$(iptables -S 2>/dev/null | wc -l | tr -dc '0-9')"

        if (( rule_count > 0 )); then
            security_check_json "OK" "iptables has ${rule_count} rule(s)"
        else
            security_check_json "WARN" "iptables has no visible rules"
        fi
        return
    fi

    security_check_json "UNKNOWN" "No supported firewall tool found"
}

check_ssh_security() {
    local config_file="/etc/ssh/sshd_config"
    local password_auth="unknown"
    local permit_root="unknown"
    local status="OK"
    local details="SSH configuration looks acceptable"

    if [[ ! -r "$config_file" ]]; then
        security_check_json "UNKNOWN" "sshd_config is not readable or SSH server is not installed"
        return
    fi

    password_auth="$(
        awk 'tolower($1) == "passwordauthentication" {value=tolower($2)} END {print value}' "$config_file"
    )"
    permit_root="$(
        awk 'tolower($1) == "permitrootlogin" {value=tolower($2)} END {print value}' "$config_file"
    )"

    password_auth="${password_auth:-default}"
    permit_root="${permit_root:-default}"

    if [[ "$password_auth" == "yes" || "$permit_root" == "yes" ]]; then
        status="WARN"
        details="PasswordAuthentication=${password_auth}; PermitRootLogin=${permit_root}"
    fi

    security_check_json "$status" "$details"
}

check_open_ports_security() {
    local count=0
    local ports_json="[]"

    if command -v ss >/dev/null 2>&1; then
        ports_json="$(
            { ss -H -tuln 2>/dev/null || true; } |
                awk '{print $1, $5}' |
                jq -Rn '
                    [
                        inputs |
                        split(" ") |
                        {
                            protocol: .[0],
                            local_address: .[1]
                        }
                    ]
                '
        )"
    elif command -v netstat >/dev/null 2>&1; then
        ports_json="$(
            { netstat -tuln 2>/dev/null || true; } |
                awk 'NR > 2 {print $1, $4}' |
                jq -Rn '
                    [
                        inputs |
                        split(" ") |
                        {
                            protocol: .[0],
                            local_address: .[1]
                        }
                    ]
                '
        )"
    else
        security_check_json "UNKNOWN" "No supported listening-port tool found"
        return
    fi

    [[ -n "$ports_json" ]] || ports_json="[]"
    count="$(jq 'length' <<< "$ports_json")"

    jq -n \
        --arg status "$([[ "$count" -gt 0 ]] && printf WARN || printf OK)" \
        --arg details "$([[ "$count" -gt 0 ]] && printf '%s listening socket(s) found' "$count" || printf 'No listening sockets found')" \
        --argjson count "$count" \
        --argjson ports "$ports_json" \
        '{
            status: $status,
            details: $details,
            count: $count,
            ports: $ports
        }'
}

check_users_security() {
    local user_count=0
    local privileged_users_json="[]"

    if [[ ! -r /etc/passwd ]]; then
        security_check_json "UNKNOWN" "/etc/passwd is not readable"
        return
    fi

    user_count="$(awk -F: '$3 >= 1000 && $1 != "nobody" {count++} END {print count + 0}' /etc/passwd)"
    privileged_users_json="$(
        awk -F: '$3 == 0 {print $1}' /etc/passwd |
            jq -Rn '[inputs]'
    )"

    jq -n \
        --arg status "OK" \
        --arg details "${user_count} regular user account(s); $(jq 'length' <<< "$privileged_users_json") uid-0 account(s)" \
        --argjson regular_user_count "$user_count" \
        --argjson privileged_users "$privileged_users_json" \
        '{
            status: $status,
            details: $details,
            regular_user_count: $regular_user_count,
            privileged_users: $privileged_users
        }'
}

check_sudo_security() {
    local sudoers_count=0
    local status="OK"
    local details="No passwordless sudo entries found"

    if [[ ! -r /etc/sudoers && ! -d /etc/sudoers.d ]]; then
        security_check_json "UNKNOWN" "sudo configuration is not readable or sudo is not installed"
        return
    fi

    sudoers_count="$(
        {
            [[ -r /etc/sudoers ]] && grep -E '^[^#].*NOPASSWD' /etc/sudoers 2>/dev/null || true
            [[ -d /etc/sudoers.d ]] && grep -RE '^[^#].*NOPASSWD' /etc/sudoers.d 2>/dev/null || true
        } | wc -l | tr -dc '0-9'
    )"

    if (( sudoers_count > 0 )); then
        status="WARN"
        details="${sudoers_count} passwordless sudo entr$( ((sudoers_count == 1)) && printf 'y' || printf 'ies' ) found"
    fi

    security_check_json "$status" "$details"
}

check_world_writable_security() {
    local scan_root="/tmp"
    local count=0
    local paths_json="[]"

    if [[ ! -d "$scan_root" ]]; then
        security_check_json "UNKNOWN" "$scan_root is not available"
        return
    fi

    paths_json="$(
        { find "$scan_root" -xdev -type d -perm -0002 ! -perm -1000 2>/dev/null || true; } |
            head -n 20 |
            jq -Rn '[inputs]'
    )"
    [[ -n "$paths_json" ]] || paths_json="[]"
    count="$(jq 'length' <<< "$paths_json")"

    jq -n \
        --arg status "$([[ "$count" -gt 0 ]] && printf WARN || printf OK)" \
        --arg details "$([[ "$count" -gt 0 ]] && printf '%s world-writable non-sticky director%s found under %s' "$count" "$([[ "$count" -eq 1 ]] && printf y || printf ies)" "$scan_root" || printf 'No world-writable non-sticky directories found under %s' "$scan_root")" \
        --argjson count "$count" \
        --argjson paths "$paths_json" \
        '{
            status: $status,
            details: $details,
            count: $count,
            sample_paths: $paths
        }'
}

check_updates_security() {
    if command -v apt-get >/dev/null 2>&1; then
        local pending_count
        pending_count="$(apt list --upgradable 2>/dev/null | awk 'NR > 1 {count++} END {print count + 0}')"

        jq -n \
            --arg status "$([[ "$pending_count" -gt 0 ]] && printf WARN || printf OK)" \
            --arg details "$([[ "$pending_count" -gt 0 ]] && printf '%s package update(s) pending' "$pending_count" || printf 'No pending package updates reported')" \
            --argjson pending_count "$pending_count" \
            '{
                status: $status,
                details: $details,
                pending_count: $pending_count
            }'
        return
    fi

    security_check_json "UNKNOWN" "No supported package manager found for update check"
}

emit_security_result() {
    local overall

    overall="$(security_overall_status)"

    jq -n \
        --arg execution_id "${EXECUTION_ID:-}" \
        --argjson duration_ms "$(duration_ms)" \
        --arg status "$overall" \
        --argjson checks "$SECURITY_CHECKS_JSON" \
        '{
            command: "security",
            target: "host",
            status: $status,
            execution_id: $execution_id,
            duration_ms: $duration_ms,
            checks: $checks
        }'
}
