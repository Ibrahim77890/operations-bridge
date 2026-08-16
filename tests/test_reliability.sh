#!/usr/bin/env bash

set -euo pipefail

cd "$(dirname "$0")/.."

timeout_result="$(./agent.sh diagnose host "timeout=1" || true)"

jq -e '
    .command == "diagnose" and
    .target == "host" and
    .status == "TIMEOUT" and
    (.error | test("exceeded"))
' >/dev/null <<< "$timeout_result"

retry_result="$(./agent.sh health host "retries=1 timeout=30")"

jq -e '
    .command == "health" and
    (.execution_id | type == "string") and
    (.duration_ms | type == "number")
' >/dev/null <<< "$retry_result"

if ./agent.sh health host "retries=9" >/dev/null 2>&1; then
    printf 'retries=9 should fail\n' >&2
    exit 1
fi

if ./agent.sh health host "timeout=999999999" >/dev/null 2>&1; then
    printf 'timeout=999999999 should fail\n' >&2
    exit 1
fi

printf 'test_reliability: OK\n'
