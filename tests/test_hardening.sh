#!/usr/bin/env bash

set -euo pipefail

cd "$(dirname "$0")/.."

http_body() {
    local response_file="$1"

    awk 'body {print} $0 == "" || $0 == "\r" {body = 1}' "$response_file" |
        tr -d '\r'
}

make_request() {
    local body="$1"
    local key="${2:-test-key}"
    local runtime_dir="${3:-}"
    local request_file
    local response_file
    local length

    request_file="$(mktemp)"
    response_file="$(mktemp)"
    if [[ -z "$runtime_dir" ]]; then
        runtime_dir="$(mktemp -d)"
    fi
    length="$(printf '%s' "$body" | wc -c | tr -dc '0-9')"

    printf 'POST /execute HTTP/1.1\r\n' >"$request_file"
    printf 'Content-Type: application/json\r\n' >>"$request_file"
    printf 'X-OpsBridge-Key: %s\r\n' "$key" >>"$request_file"
    printf 'Content-Length: %s\r\n' "$length" >>"$request_file"
    printf '\r\n' >>"$request_file"
    printf '%s' "$body" >>"$request_file"

    OPSBRIDGE_KEY=test-key OPSBRIDGE_RUNTIME_DIR="$runtime_dir" ./bridge.sh --connection <"$request_file" >"$response_file"
    http_body "$response_file"

    rm -f "$request_file" "$response_file"
}

make_get_request() {
    local path="$1"
    local request_file
    local response_file

    request_file="$(mktemp)"
    response_file="$(mktemp)"

    printf 'GET %s HTTP/1.1\r\n' "$path" >"$request_file"
    printf 'X-OpsBridge-Key: test-key\r\n' >>"$request_file"
    printf '\r\n' >>"$request_file"

    OPSBRIDGE_KEY=test-key OPSBRIDGE_RUNTIME_DIR="$(mktemp -d)" ./bridge.sh --connection <"$request_file" >"$response_file"
    http_body "$response_file"

    rm -f "$request_file" "$response_file"
}

valid="{\"request_id\":\"REQ-hardening-valid-$$\",\"command\":\"health\",\"target\":\"host\",\"parameters\":{\"timeout\":\"30\"}}"
make_request "$valid" | jq -e '.success == true and .result.command == "health"' >/dev/null

make_request "$valid" "wrong-key" | jq -e '.success == false and .error == "Unauthorized"' >/dev/null

missing_request_id='{"command":"health","target":"host","parameters":{}}'
make_request "$missing_request_id" | jq -e '.success == false and (.error | test("request_id"))' >/dev/null

bad_parameter="{\"request_id\":\"REQ-hardening-bad-$$\",\"command\":\"health\",\"target\":\"host\",\"parameters\":{\"disk_threshold\":\"80 90\"}}"
make_request "$bad_parameter" | jq -e '.success == false and .error == "Invalid parameters"' >/dev/null

replay_runtime="$(mktemp -d)"
replay_body="{\"request_id\":\"REQ-hardening-replay-$$\",\"command\":\"health\",\"target\":\"host\",\"parameters\":{\"timeout\":\"30\"}}"
make_request "$replay_body" "test-key" "$replay_runtime" | jq -e '.success == true' >/dev/null
make_request "$replay_body" "test-key" "$replay_runtime" | jq -e '.success == false and .error == "Duplicate request_id"' >/dev/null

large_body="{\"request_id\":\"REQ-hardening-large-$$\",\"command\":\"health\",\"target\":\"host\",\"parameters\":{\"padding\":\"$(printf '%09000d' 0)\"}}"
make_request "$large_body" | jq -e '.success == false and .error == "Request body too large"' >/dev/null

make_get_request "/health" | jq -e '.status == "OK"' >/dev/null
make_get_request "/ready" | jq -e '(.status == "READY" or .status == "NOT_READY") and (.issues | type == "array")' >/dev/null
make_get_request "/metrics" | jq -e '.requests_total >= 0' >/dev/null

printf 'test_hardening: OK\n'
