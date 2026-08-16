#!/usr/bin/env bash

set -euo pipefail

cd "$(dirname "$0")/.."

./agent.sh health host "disk_threshold=80" | jq -e '.command == "health"' >/dev/null

if ./agent.sh health host "disk_threshold=abc" >/dev/null 2>&1; then
    printf 'disk_threshold=abc should fail\n' >&2
    exit 1
fi

if ./agent.sh health host "disk_threshold=999" >/dev/null 2>&1; then
    printf 'disk_threshold=999 should fail\n' >&2
    exit 1
fi

if ./agent.sh health host "something=malicious" >/dev/null 2>&1; then
    printf 'something=malicious should fail\n' >&2
    exit 1
fi

./agent.sh diagnose host "memory_threshold=90 disk_threshold=80" |
    jq -e '.command == "diagnose"' >/dev/null

./agent.sh inventory host "include_network=false" |
    jq -e '.network.included == false' >/dev/null

printf 'test_parameters: OK\n'
