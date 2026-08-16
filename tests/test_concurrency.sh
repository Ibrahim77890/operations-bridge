#!/usr/bin/env bash

set -euo pipefail

cd "$(dirname "$0")/.."

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

./agent.sh health host >"$tmp_dir/health.json" 2>"$tmp_dir/health.log" &
./agent.sh inventory host >"$tmp_dir/inventory.json" 2>"$tmp_dir/inventory.log" &
./agent.sh security host >"$tmp_dir/security.json" 2>"$tmp_dir/security.log" &
./agent.sh diagnose host >"$tmp_dir/diagnose.json" 2>"$tmp_dir/diagnose.log" &
wait || true

for file in "$tmp_dir"/*.json; do
    jq -e '.execution_id and .command and .target and .status' "$file" >/dev/null
done

ids_count="$(
    jq -r '.execution_id' "$tmp_dir"/*.json |
        sort |
        uniq |
        wc -l |
        tr -dc '0-9'
)"

if (( ids_count != 4 )); then
    printf 'expected 4 unique execution IDs, got %s\n' "$ids_count" >&2
    exit 1
fi

printf 'test_concurrency: OK\n'
