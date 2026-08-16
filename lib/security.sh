check_firewall_security() {
    if command -v ufw >/dev/null 2>&1; then
        local state
        state="$({ ufw status 2>/dev/null || true; } | awk 'NR == 1 {print tolower($2)}')"

        if [[ "$state" == "active" ]]; then
            security_check_json "OK" "ufw is active"
        elif [[ -n "$state" ]]; then
            security_check_json "WARN" "ufw is not active"
        else
            security_check_json "UNKNOWN" "ufw is installed but status could not be read"
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
        rule_count="$({ iptables -S 2>/dev/null || true; } | wc -l | tr -dc '0-9')"

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
        awk 'tolower($1) == "passwordauthentication" {value=tolower($2)} END {print value}' "$config_file" || true
    )"
    permit_root="$(
        awk 'tolower($1) == "permitrootlogin" {value=tolower($2)} END {print value}' "$config_file" || true
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

    ports_json="$(listening_ports_json)"
    [[ -n "$ports_json" ]] || ports_json="[]"
    count="$(jq 'length' <<< "$ports_json")"

    jq -n \
        --arg status "$([[ "$count" -gt 0 ]] && printf WARN || printf OK)" \
        --arg details "$([[ "$count" -gt 0 ]] && printf '%s listening socket(s) found' "$count" || printf 'No listening sockets found')" \
        --argjson count "$count" \
        --argjson ports "$ports_json" \
        '{status: $status, details: $details, count: $count, ports: $ports}'
}

check_users_security() {
    local user_count=0
    local privileged_users_json="[]"

    if [[ ! -r /etc/passwd ]]; then
        security_check_json "UNKNOWN" "/etc/passwd is not readable"
        return
    fi

    user_count="$(awk -F: '$3 >= 1000 && $1 != "nobody" {count++} END {print count + 0}' /etc/passwd)"
    privileged_users_json="$({ awk -F: '$3 == 0 {print $1}' /etc/passwd || true; } | jq -Rn '[inputs]')"

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
        --arg details "$([[ "$count" -gt 0 ]] && printf '%s world-writable non-sticky paths found under %s' "$count" "$scan_root" || printf 'No world-writable non-sticky directories found under %s' "$scan_root")" \
        --argjson count "$count" \
        --argjson paths "$paths_json" \
        '{status: $status, details: $details, count: $count, sample_paths: $paths}'
}

check_updates_security() {
    if command -v apt-get >/dev/null 2>&1; then
        local pending_count
        pending_count="$({ apt list --upgradable 2>/dev/null || true; } | awk 'NR > 1 {count++} END {print count + 0}')"

        jq -n \
            --arg status "$([[ "$pending_count" -gt 0 ]] && printf WARN || printf OK)" \
            --arg details "$([[ "$pending_count" -gt 0 ]] && printf '%s package update(s) pending' "$pending_count" || printf 'No pending package updates reported')" \
            --argjson pending_count "$pending_count" \
            '{status: $status, details: $details, pending_count: $pending_count}'
        return
    fi

    security_check_json "UNKNOWN" "No supported package manager found for update check"
}

security_overall_status() {
    jq -r '
        [to_entries[].value.status] as $statuses |
        if any($statuses[]; . == "CRITICAL") then "CRITICAL"
        elif any($statuses[]; . == "WARN" or . == "WARNING") then "WARN"
        elif any($statuses[]; . == "UNKNOWN") then "WARN"
        else "OK"
        end
    '
}
