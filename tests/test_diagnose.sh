#!/usr/bin/env bash

set -euo pipefail

cd "$(dirname "$0")/.."

result="$(./agent.sh diagnose host)"

jq -e '
    .command == "diagnose" and
    .target == "host" and
    (.findings | type == "array") and
    (.findings | length > 0) and
    (.execution_id | type == "string") and
    (.duration_ms | type == "number")
' >/dev/null <<< "$result"

printf 'test_diagnose: OK\n'
