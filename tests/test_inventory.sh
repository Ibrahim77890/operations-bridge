#!/usr/bin/env bash

set -euo pipefail

cd "$(dirname "$0")/.."

result="$(./agent.sh inventory host)"

jq -e '
    .command == "inventory" and
    .target == "host" and
    .status == "OK" and
    (.system | type == "object") and
    (.cpu | type == "object") and
    (.memory | type == "object") and
    (.disk | type == "object") and
    (.network | type == "object")
' >/dev/null <<< "$result"

printf 'test_inventory: OK\n'
