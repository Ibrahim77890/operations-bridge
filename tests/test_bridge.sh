#!/usr/bin/env bash

set -euo pipefail

cd "$(dirname "$0")/.."

body='{"command":"diagnose","target":"host","parameters":{}}'
length="$(printf '%s' "$body" | wc -c | tr -dc '0-9')"
request_file="$(mktemp)"
response_file="$(mktemp)"
trap 'rm -f "$request_file" "$response_file"' EXIT

printf 'POST /execute HTTP/1.1\r\n' >"$request_file"
printf 'Content-Type: application/json\r\n' >>"$request_file"
printf 'X-OpsBridge-Key: test-key\r\n' >>"$request_file"
printf 'Content-Length: %s\r\n' "$length" >>"$request_file"
printf '\r\n' >>"$request_file"
printf '%s' "$body" >>"$request_file"

OPSBRIDGE_KEY=test-key ./bridge.sh --connection <"$request_file" >"$response_file"

tail -n 1 "$response_file" |
    jq -e '.success == true and .result.command == "diagnose"' >/dev/null

printf 'test_bridge: OK\n'
