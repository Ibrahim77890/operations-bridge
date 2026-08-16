run_with_timeout() {
    local timeout_seconds="$1"
    shift

    timeout \
        --preserve-status \
        "${timeout_seconds}s" \
        "$@"
}

retry() {
    local attempts="$1"
    local delay="$2"
    shift 2

    local attempt=1

    while (( attempt <= attempts )); do
        if "$@"; then
            return 0
        fi

        if (( attempt == attempts )); then
            return 1
        fi

        warn "Attempt $attempt failed; retrying in ${delay}s"
        sleep "$delay"

        delay=$((delay * 2))
        attempt=$((attempt + 1))
    done

    return 1
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

listening_ports_json() {
    if command -v ss >/dev/null 2>&1; then
        { ss -H -tuln 2>/dev/null || true; } |
            awk '{print $1, $5}' |
            jq -Rn '[inputs | split(" ") | {protocol: .[0], local_address: .[1]}]'
        return
    fi

    if command -v netstat >/dev/null 2>&1; then
        { netstat -tuln 2>/dev/null || true; } |
            awk 'NR > 2 {print $1, $4}' |
            jq -Rn '[inputs | split(" ") | {protocol: .[0], local_address: .[1]}]'
        return
    fi

    jq -n '[]'
}

dns_resolves() {
    local host="${1:-example.com}"

    if command -v getent >/dev/null 2>&1; then
        getent hosts "$host" >/dev/null 2>&1
        return
    fi

    if command -v nslookup >/dev/null 2>&1; then
        nslookup "$host" >/dev/null 2>&1
        return
    fi

    if command -v ping >/dev/null 2>&1; then
        ping -c 1 "$host" >/dev/null 2>&1
        return
    fi

    return 1
}
