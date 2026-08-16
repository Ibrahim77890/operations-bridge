#!/usr/bin/env bash

set -euo pipefail

cd "$(dirname "$0")/.."

result="$(./agent.sh health host)"

jq -e '
    .command == "health" and
    .target == "host" and
    (.checks | type == "object") and
    (.execution_id | type == "string") and
    (.duration_ms | type == "number")
' >/dev/null <<< "$result"

printf 'test_health: OK\n'
