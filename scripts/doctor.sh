#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cd "$ROOT_DIR"
./bridge.sh doctor

printf '\nAgent smoke test:\n'
./agent.sh health host "timeout=30" | jq -e '.command == "health" and .target == "host"' >/dev/null
printf 'agent_health=OK\n'
