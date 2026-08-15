#!/bin/sh
set -eu

INSTALL_DIR="${INSTALL_DIR:-/usr/local/bin}"
BINARY_NAME="ddns"
RAW_URL="${RAW_URL:-https://raw.githubusercontent.com/user/ddns-bot/main/ddns.sh}"

log() {
    echo "[INSTALLER] $*"
}

log "Installing DDNS Automation Bot to ${INSTALL_DIR}/${BINARY_NAME}..."

if [ ! -d "$INSTALL_DIR" ]; then
    mkdir -p "$INSTALL_DIR"
fi

if [ -f "./ddns.sh" ]; then
    log "Using local ddns.sh..."
    cp ./ddns.sh "${INSTALL_DIR}/${BINARY_NAME}"
else
    log "Downloading ddns.sh from ${RAW_URL}..."
    curl -fsSL "$RAW_URL" -o "${INSTALL_DIR}/${BINARY_NAME}"
fi

chmod +x "${INSTALL_DIR}/${BINARY_NAME}"
log "Successfully installed binary to ${INSTALL_DIR}/${BINARY_NAME}"

# Optional Systemd service setup if /etc/systemd/system exists and is writable
if [ -d "/etc/systemd/system" ] && [ -w "/etc/systemd/system" ] && command -v systemctl >/dev/null 2>&1; then
    log "Creating systemd service template at /etc/systemd/system/ddns.service..."
    cat <<EOF | tee /etc/systemd/system/ddns.service >/dev/null
[Unit]
Description=DDNS Automation Bot Service
After=network.target network-online.target
Wants=network-online.target

[Service]
Type=simple
EnvironmentFile=-/etc/default/ddns
ExecStart=${INSTALL_DIR}/${BINARY_NAME} --daemon
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
    log "Systemd service created. Create /etc/default/ddns with your configuration and run:"
    log "  systemctl daemon-reload && systemctl enable --now ddns"
fi

log "Installation complete!"
