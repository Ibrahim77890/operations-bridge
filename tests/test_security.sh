#!/usr/bin/env bash

set -euo pipefail

cd "$(dirname "$0")/.."

result="$(./agent.sh security host)"

jq -e '
    .command == "security" and
    .target == "host" and
    (.checks | type == "object") and
    (.checks.firewall | type == "object") and
    (.checks.ssh | type == "object") and
    (.checks.open_ports | type == "object")
' >/dev/null <<< "$result"

printf 'test_security: OK\n'
