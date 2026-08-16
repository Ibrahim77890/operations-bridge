#!/usr/bin/env bash

set -euo pipefail

SERVICE_FILE="/etc/systemd/system/opsbridge.service"

if [[ "$(id -u)" -ne 0 ]]; then
    printf 'Run uninstall.sh as root.\n' >&2
    exit 1
fi

systemctl disable --now opsbridge 2>/dev/null || true
rm -f "$SERVICE_FILE"
systemctl daemon-reload

printf 'OpsBridge service removed. Configuration and install files were left in place intentionally.\n'
