#!/bin/sh
set -eu

# ANSI Colors
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
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

# Auto-detect best writable directory in PATH (No sudo required)
detect_install_dir() {
    if [ -n "${INSTALL_DIR:-}" ]; then
        echo "$INSTALL_DIR"
        return
    fi

    # Check Termux environment
    if [ -n "${PREFIX:-}" ] && [ -d "${PREFIX}/bin" ] && [ -w "${PREFIX}/bin" ]; then
        echo "${PREFIX}/bin"
        return
    fi

    # Check writable directories in user PATH
    OLD_IFS="$IFS"
    IFS=":"
    for dir in $PATH; do
        if [ -n "$dir" ] && [ -d "$dir" ] && [ -w "$dir" ]; then
            case "$dir" in
                */.local/bin|*/bin|*/*)
                    # Exclude system dirs if non-root
                    if [ "$(id -u 2>/dev/null || echo 1)" -ne 0 ]; then
                        case "$dir" in
                            /usr/bin|/bin|/usr/sbin|/sbin) continue ;;
                        esac
                    fi
                    echo "$dir"
                    IFS="$OLD_IFS"
                    return
                    ;;
            esac
        fi
    done
    IFS="$OLD_IFS"

    # Default user-space fallback (~/.local/bin)
    user_bin="${HOME:-~}/.local/bin"
    mkdir -p "$user_bin" 2>/dev/null || true
    echo "$user_bin"
}

INSTALL_DIR=$(detect_install_dir)
BINARY_NAME="nodex"
RAW_URL="${RAW_URL:-https://raw.githubusercontent.com/marhaburrisqi/Nodex/main/ddns.sh}"

log "Installing NODEX to ${INSTALL_DIR}/${BINARY_NAME}..."

if [ ! -d "$INSTALL_DIR" ]; then
    mkdir -p "$INSTALL_DIR" 2>/dev/null || true
fi

TMP_FILE=$(mktemp /tmp/nodex_install.XXXXXX 2>/dev/null || echo "/tmp/nodex_install.tmp")
trap 'rm -f "$TMP_FILE"' EXIT INT TERM

if [ -f "./ddns.sh" ]; then
    log "Using local ddns.sh..."
    cp ./ddns.sh "$TMP_FILE"
else
    log "Downloading ddns.sh from ${RAW_URL}..."
    curl -fsSL "$RAW_URL" -o "$TMP_FILE"
fi

if ! cp "$TMP_FILE" "${INSTALL_DIR}/${BINARY_NAME}" 2>/dev/null; then
    log "${RED}Error: Cannot write to ${INSTALL_DIR}/${BINARY_NAME}.${NC}" >&2
    exit 1
fi

chmod +x "${INSTALL_DIR}/${BINARY_NAME}" 2>/dev/null || true
log "Successfully installed binary to ${INSTALL_DIR}/${BINARY_NAME}"

# Symlink 'modex' typo redirect to 'nodex'
if [ -w "$INSTALL_DIR" ]; then
    ln -sf "${INSTALL_DIR}/${BINARY_NAME}" "${INSTALL_DIR}/modex" 2>/dev/null || true
fi

# Ensure INSTALL_DIR is in PATH for shell profile if it's a custom user dir
case ":$PATH:" in
    *":${INSTALL_DIR}:"*) ;;
    *)
        log "${YELLOW}Adding ${INSTALL_DIR} to shell PATH profile...${NC}"
        if [ -f "${HOME:-}/.bashrc" ]; then
            echo "export PATH=\"${INSTALL_DIR}:\$PATH\"" >> "${HOME}/.bashrc"
        fi
        if [ -f "${HOME:-}/.zshrc" ]; then
            echo "export PATH=\"${INSTALL_DIR}:\$PATH\"" >> "${HOME}/.zshrc"
        fi
        if [ -d "${HOME:-}/.config/fish" ]; then
            mkdir -p "${HOME}/.config/fish/conf.d" 2>/dev/null || true
            echo "set -gx PATH \"${INSTALL_DIR}\" \$PATH" > "${HOME}/.config/fish/conf.d/nodex.fish"
        fi
        export PATH="${INSTALL_DIR}:$PATH"
        ;;
esac

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
fi

printf "\n%b✓ Installation complete! Run 'nodex' or 'nodex --help' to get started.%b\n" "${BLUE}" "${NC}"
