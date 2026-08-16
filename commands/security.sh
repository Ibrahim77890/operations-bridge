SECURITY_CHECKS_JSON="{}"

security_host() {
    info "Auditing host security posture"
    require_jq
    run_security
}

run_security() {
    local firewall
    local ssh
    local open_ports
    local users
    local sudo
    local world_writable
    local updates

    firewall="$(safe_security_check "firewall" check_firewall_security)"
    ssh="$(safe_security_check "ssh" check_ssh_security)"
    open_ports="$(safe_security_check "open_ports" check_open_ports_security)"
    users="$(safe_security_check "users" check_users_security)"
    sudo="$(safe_security_check "sudo" check_sudo_security)"
    world_writable="$(safe_security_check "world_writable" check_world_writable_security)"
    updates="$(safe_security_check "updates" check_updates_security)"

    SECURITY_CHECKS_JSON="$(
        jq -n \
            --argjson firewall "$firewall" \
            --argjson ssh "$ssh" \
            --argjson open_ports "$open_ports" \
            --argjson users "$users" \
            --argjson sudo "$sudo" \
            --argjson world_writable "$world_writable" \
            --argjson updates "$updates" \
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

safe_security_check() {
    local name="$1"
    local check_function="$2"
    local output
    local exit_code

    set +e
    output="$("$check_function" 2>&1)"
    exit_code=$?
    set -e

    if [[ "$exit_code" -eq 0 ]] && jq -e . >/dev/null 2>&1 <<< "$output"; then
        printf '%s' "$output"
        return
    fi

    security_check_json "UNKNOWN" "${name} check failed"
}

emit_security_result() {
    local overall

    overall="$(security_overall_status <<< "$SECURITY_CHECKS_JSON")"

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
