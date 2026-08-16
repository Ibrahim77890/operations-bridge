INVENTORY_SYSTEM_JSON="{}"
INVENTORY_CPU_JSON="{}"
INVENTORY_MEMORY_JSON="{}"
INVENTORY_DISK_JSON="{}"
INVENTORY_NETWORK_JSON="{}"

inventory_host() {
    info "Collecting host inventory"
    require_jq
    run_inventory
}

run_inventory() {
    INVENTORY_SYSTEM_JSON="$(get_system_info)"
    INVENTORY_CPU_JSON="$(get_cpu_info)"
    INVENTORY_MEMORY_JSON="$(get_memory_info)"
    INVENTORY_DISK_JSON="$(get_disk_info)"

    if [[ "$(param_get "include_network" "true")" == "true" ]]; then
        INVENTORY_NETWORK_JSON="$(get_network_info)"
    else
        INVENTORY_NETWORK_JSON="$(jq -n '{included: false, interfaces: []}')"
    fi
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
