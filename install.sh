#!/bin/sh
set -eu

INSTALL_DIR="${INSTALL_DIR:-/usr/local/bin}"
BINARY_NAME="nodex"
RAW_URL="${RAW_URL:-https://raw.githubusercontent.com/marhaburrisqi/Nodex/main/ddns.sh}"

# ANSI Colors
CYAN='\033[0;36m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

show_banner() {
    printf "%b" "${CYAN}"
    printf '%s\n' ' _  _   ___   ___   ___  __  __'
    printf '%s\n' '| \| | / _ \ |   \ | __| \ \/ /'
    printf '%s\n' '| .  || (_) || |) || _|   >  < '
    printf '%s\n' '|_|\_| \___/ |___/ |___| /_/\_\'
    printf '\n%s\n\n' ' Dynamic DNS Automation Tool'
    printf "%b" "${NC}"
}

log() {
    printf "%b[INSTALLER]%b %s\n" "${GREEN}" "${NC}" "$*"
}

show_banner

log "Installing NODEX to ${INSTALL_DIR}/${BINARY_NAME}..."

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

# Symlink 'modex' typo redirect to 'nodex'
if [ -w "$INSTALL_DIR" ]; then
    ln -sf "${INSTALL_DIR}/${BINARY_NAME}" "${INSTALL_DIR}/modex" 2>/dev/null || true
    log "Created helper alias 'modex' -> 'nodex'"
fi

# Optional Systemd service setup if /etc/systemd/system exists and is writable
if [ -d "/etc/systemd/system" ] && [ -w "/etc/systemd/system" ] && command -v systemctl >/dev/null 2>&1; then
    log "Creating systemd service template at /etc/systemd/system/nodex.service..."
    cat <<EOF | tee /etc/systemd/system/nodex.service >/dev/null
[Unit]
Description=NODEX Dynamic DNS Automation Service
After=network.target network-online.target
Wants=network-online.target

[Service]
Type=simple
EnvironmentFile=-/etc/default/nodex
ExecStart=${INSTALL_DIR}/${BINARY_NAME} --daemon
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
    log "Systemd service created at /etc/systemd/system/nodex.service."
    log "Create /etc/default/nodex with your configuration and run:"
    log "  systemctl daemon-reload && systemctl enable --now nodex"
fi

printf "\n%b✓ Installation complete! Run 'nodex --help' to get started.%b\n" "${BLUE}" "${NC}"
