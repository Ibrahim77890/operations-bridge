#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="${OPSBRIDGE_INSTALL_DIR:-/opt/opsbridge}"
CONFIG_DIR="${OPSBRIDGE_CONFIG_DIR:-/etc/opsbridge}"
SERVICE_FILE="/etc/systemd/system/opsbridge.service"

require_root() {
    if [[ "$(id -u)" -ne 0 ]]; then
        printf 'Run install.sh as root so it can create the service user and systemd unit.\n' >&2
        exit 1
    fi
}

check_dependencies() {
    local dependency

    for dependency in bash jq socat flock timeout; do
        command -v "$dependency" >/dev/null 2>&1 || {
            printf 'Missing dependency: %s\n' "$dependency" >&2
            exit 1
        }
    done
}

install_files() {
    install -d -m 0755 "$INSTALL_DIR" "$INSTALL_DIR/lib" "$INSTALL_DIR/commands" "$INSTALL_DIR/config"
    install -d -m 0750 "$CONFIG_DIR"
    install -m 0755 "$ROOT_DIR/agent.sh" "$ROOT_DIR/bridge.sh" "$INSTALL_DIR/"
    install -m 0644 "$ROOT_DIR/lib/"*.sh "$INSTALL_DIR/lib/"
    install -m 0644 "$ROOT_DIR/commands/"*.sh "$INSTALL_DIR/commands/"
    install -m 0644 "$ROOT_DIR/config/defaults.env" "$INSTALL_DIR/config/defaults.env"

    if [[ ! -f "$CONFIG_DIR/opsbridge.env" ]]; then
        install -m 0600 "$ROOT_DIR/.env.example" "$CONFIG_DIR/opsbridge.env"
    fi
}

install_service() {
    if ! id opsbridge >/dev/null 2>&1; then
        useradd --system --home-dir "$INSTALL_DIR" --shell /usr/sbin/nologin opsbridge
    fi

    chown -R opsbridge:opsbridge "$INSTALL_DIR"
    install -m 0644 "$ROOT_DIR/deploy/opsbridge.service" "$SERVICE_FILE"
    systemctl daemon-reload
    printf 'Installed OpsBridge. Configure %s, then run:\n' "$CONFIG_DIR/opsbridge.env"
    printf '  systemctl enable --now opsbridge\n'
}

require_root
check_dependencies
install_files
install_service
