diagnose_host() {
    info "Diagnosing host issues"
    require_jq

    DIAGNOSE_FINDINGS=()

    diagnose_cpu_pressure
    diagnose_memory_pressure
    diagnose_disk_pressure
    diagnose_systemd_services
    diagnose_recent_errors
    diagnose_network_connectivity
    diagnose_dns_resolution
    diagnose_listening_services
}

diagnose_cpu_pressure() {
    local load
    local cores
    local threshold
    local warning_load
    local critical_load

    load="$(cpu_load_1m)"
    cores="$(nproc 2>/dev/null || printf '1')"
    threshold="$(param_get "cpu_threshold" "100")"
    warning_load="$(awk "BEGIN {printf \"%.2f\", $cores * ($threshold / 100)}")"
    critical_load="$(awk "BEGIN {printf \"%.2f\", $warning_load * 2}")"

    if awk "BEGIN {exit !($load >= $critical_load)}"; then
        diagnose_add_finding "cpu" "CRITICAL" "1-minute load is ${load}, above critical threshold ${critical_load}"
    elif awk "BEGIN {exit !($load >= $warning_load)}"; then
        diagnose_add_finding "cpu" "WARN" "1-minute load is ${load}, above threshold ${warning_load}"
    else
        diagnose_add_finding "cpu" "OK" "CPU load is within expected range"
    fi
}

diagnose_memory_pressure() {
    local percentage
    local threshold

    percentage="$(memory_used_percent)"
    threshold="$(param_get "memory_threshold" "85")"

    if (( percentage >= 95 )); then
        diagnose_add_finding "memory" "CRITICAL" "Memory usage is ${percentage}%"
    elif (( percentage >= threshold )); then
        diagnose_add_finding "memory" "WARN" "Memory usage is ${percentage}%"
    else
        diagnose_add_finding "memory" "OK" "Memory usage is ${percentage}%"
    fi
}

diagnose_disk_pressure() {
    local percentage
    local threshold

    percentage="$(disk_used_percent)"
    [[ "$percentage" =~ ^[0-9]+$ ]] || percentage=0
    threshold="$(param_get "disk_threshold" "80")"

    if (( percentage >= 95 )); then
        diagnose_add_finding "disk" "CRITICAL" "Root filesystem is ${percentage}% full"
    elif (( percentage >= threshold )); then
        diagnose_add_finding "disk" "WARN" "Root filesystem is above ${threshold}%"
    else
        diagnose_add_finding "disk" "OK" "Root filesystem usage is ${percentage}%"
    fi
}

diagnose_systemd_services() {
    if ! command -v systemctl >/dev/null 2>&1; then
        diagnose_add_finding "systemd" "WARN" "systemctl is unavailable"
        return
    fi

    local failed_count
    failed_count="$(systemctl --failed --no-legend 2>/dev/null | awk 'NF {count++} END {print count + 0}')"

    if (( failed_count > 0 )); then
        diagnose_add_finding "systemd" "WARN" "${failed_count} failed systemd service(s)"
    else
        diagnose_add_finding "systemd" "OK" "No failed systemd services"
    fi
}

diagnose_recent_errors() {
    if command -v journalctl >/dev/null 2>&1; then
        local error_count
        error_count="$(journalctl -p err..alert --since '1 hour ago' --no-pager 2>/dev/null | awk 'NF {count++} END {print count + 0}')"

        if (( error_count > 0 )); then
            diagnose_add_finding "logs" "WARN" "${error_count} critical/error log line(s) in the last hour"
        else
            diagnose_add_finding "logs" "OK" "No recent critical journal errors"
        fi
        return
    fi

    diagnose_add_finding "logs" "WARN" "journalctl is unavailable"
}

diagnose_network_connectivity() {
    if command -v curl >/dev/null 2>&1; then
        if run_with_timeout 5 curl --silent --fail https://example.com >/dev/null; then
            diagnose_add_finding "network" "OK" "HTTPS connectivity to example.com works"
        else
            diagnose_add_finding "network" "WARN" "HTTPS connectivity to example.com failed"
        fi
        return
    fi

    diagnose_add_finding "network" "WARN" "curl is unavailable"
}

diagnose_dns_resolution() {
    if dns_resolves "example.com"; then
        diagnose_add_finding "dns" "OK" "DNS resolution for example.com works"
    else
        diagnose_add_finding "dns" "WARN" "DNS resolution for example.com failed or no resolver tool is available"
    fi
}

diagnose_listening_services() {
    local ports_json
    local count

    ports_json="$(listening_ports_json)"
    count="$(jq 'length' <<< "$ports_json")"

    if (( count > 0 )); then
        diagnose_add_finding "services" "WARN" "${count} listening socket(s) detected"
    else
        diagnose_add_finding "services" "OK" "No listening sockets detected"
    fi
}

emit_diagnose_result() {
    local findings_json
    local overall

    findings_json="$(diagnose_findings_json)"
    overall="$(severity_overall_status <<< "$findings_json")"

    jq -n \
        --arg execution_id "${EXECUTION_ID:-}" \
        --argjson duration_ms "$(duration_ms)" \
        --arg status "$overall" \
        --argjson findings "$findings_json" \
        '{
            command: "diagnose",
            target: "host",
            status: $status,
            execution_id: $execution_id,
            duration_ms: $duration_ms,
            findings: $findings
        }'
}
