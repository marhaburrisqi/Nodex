#!/bin/sh
set -eu

# ANSI Colors & Formatting
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
WHITE='\033[1;37m'
BOLD='\033[1m'
DIM='\033[2m'
GRAY='\033[90m'
NC='\033[0m'

cleanup_installer() {
    printf '\033[?25h'
    rm -f "${TMP_FILE:-}" 2>/dev/null || true
}
trap cleanup_installer EXIT INT TERM

show_banner() {
    printf "\033[H\033[J"
    printf "%b _  _   ___   ___   ___  __  __%b\n" "${CYAN}" "${NC}"
    printf "%b| \\| | / _ \\ |   \\ | __| \\ \\/ /%b    %bNODEX Gateway Installer%b\n" "${CYAN}" "${NC}" "${WHITE}" "${NC}"
    printf "%b| .  || (_) || |) || _|   >  < %b    %bAutomated Zero-Dependency Setup%b\n" "${CYAN}" "${NC}" "${GRAY}" "${NC}"
    printf "%b|_|\\_| \\___/ |___/ |___| /_/\\_\\\\%b\n" "${CYAN}" "${NC}"
    printf "%b──────────────────────────────────────────────────────────%b\n\n" "${GRAY}" "${NC}"
}

# POSIX Progress Bar Engine
render_progress() {
    pid=$1
    label="$2"
    total_blocks=24
    percent=0
    frame_idx=0

    printf '\033[?25l'

    # Smooth 1% increment loop running ~6.5 - 7.5 seconds total
    while [ "$percent" -lt 100 ]; do
        if kill -0 "$pid" 2>/dev/null; then
            # While background process is alive, increment steadily 1% per frame
            # Holds at 92% if process takes unusually long
            if [ "$percent" -lt 92 ]; then
                percent=$((percent + 1))
            fi
        else
            # Process is done: smoothly step through remaining percentage to 100%
            percent=$((percent + 1))
        fi

        filled=$((percent * total_blocks / 100))
        unfilled=$((total_blocks - filled))

        # Pure POSIX string generation without forks
        bar_filled=""
        _i=$filled
        while [ "$_i" -gt 0 ]; do
            bar_filled="${bar_filled}█"
            _i=$((_i - 1))
        done

        bar_unfilled=""
        _i=$unfilled
        while [ "$_i" -gt 0 ]; do
            bar_unfilled="${bar_unfilled}░"
            _i=$((_i - 1))
        done

        case "$frame_idx" in
            0) frame="⠋" ;; 1) frame="⠙" ;; 2) frame="⠹" ;; 3) frame="⠸" ;; 4) frame="⠼" ;;
            5) frame="⠴" ;; 6) frame="⠦" ;; 7) frame="⠧" ;; 8) frame="⠇" ;; 9) frame="⠏" ;;
        esac
        frame_idx=$(((frame_idx + 1) % 10))

        printf "\r  \033[37m%-18s\033[0m [\033[1;36m%s\033[0;90m%s\033[0m]  \033[1;37m%3d%%\033[0m  \033[90m(%s)\033[0m" \
            "$label" "$bar_filled" "$bar_unfilled" "$percent" "$frame"

        sleep 0.065
    done

    # Final 100% completion render
    full_bar=""
    _i=$total_blocks
    while [ "$_i" -gt 0 ]; do
        full_bar="${full_bar}█"
        _i=$((_i - 1))
    done

    printf "\r  \033[1;32m✔\033[0m \033[37m%-16s\033[0m [\033[1;32m%s\033[0m]  \033[1;32m100%%\033[0m  \033[90m(done)\033[0m\n" \
        "$label" "$full_bar"
    printf '\033[?25h'
}

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

show_banner

INSTALL_DIR=$(detect_install_dir)
BINARY_NAME="nodex"
RAW_URL="${RAW_URL:-https://raw.githubusercontent.com/marhaburrisqi/Nodex/main/ddns.sh}"

printf "  %bTarget Destination%b : %b%s/%s%b\n\n" "${GRAY}" "${NC}" "${WHITE}" "$INSTALL_DIR" "$BINARY_NAME" "${NC}"

if [ ! -d "$INSTALL_DIR" ]; then
    mkdir -p "$INSTALL_DIR" 2>/dev/null || true
fi

TMP_FILE=$(mktemp /tmp/nodex_install.XXXXXX 2>/dev/null || echo "/tmp/nodex_install.tmp")

if [ -f "./ddns.sh" ]; then
    cp ./ddns.sh "$TMP_FILE" &
    render_progress $! "Loading payload"
    wait $!
else
    curl -fsSL --connect-timeout 5 --max-time 15 --retry 1 --compressed "$RAW_URL" -o "$TMP_FILE" &
    render_progress $! "Fetching payload"
    wait $!
fi

# Dynamically stamp current commit hash into the installed binary
COMMIT_HASH=""
if command -v git >/dev/null 2>&1 && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    COMMIT_HASH=$(git rev-parse --short HEAD 2>/dev/null || true)
fi

if [ -z "$COMMIT_HASH" ]; then
    COMMIT_HASH=$(curl -fsSL --connect-timeout 5 --max-time 15 --retry 1 --compressed "https://api.github.com/repos/marhaburrisqi/Nodex/commits/main" 2>/dev/null | grep '"sha"' | head -n 1 | cut -d'"' -f4 | cut -c1-7 || true)
fi

if [ -n "$COMMIT_HASH" ]; then
    sed -i "s/^BUILD_HASH=\".*\"/BUILD_HASH=\"${COMMIT_HASH}\"/" "$TMP_FILE" 2>/dev/null || \
    sed "s/^BUILD_HASH=\".*\"/BUILD_HASH=\"${COMMIT_HASH}\"/" "$TMP_FILE" > "${TMP_FILE}.stamped" && mv "${TMP_FILE}.stamped" "$TMP_FILE" 2>/dev/null || true
fi

if ! cp "$TMP_FILE" "${INSTALL_DIR}/${BINARY_NAME}" 2>/dev/null; then
    printf "\n%bError: Cannot write to %s/%s.%b\n" "${RED}" "$INSTALL_DIR" "$BINARY_NAME" "${NC}" >&2
    exit 1
fi

chmod +x "${INSTALL_DIR}/${BINARY_NAME}" 2>/dev/null || true
sleep 0.7
printf "  %b✔%b %b%-16s%b %b[%s]%b\n" "${GREEN}" "${NC}" "${WHITE}" "Deploy binary" "${NC}" "${GRAY}" "${INSTALL_DIR}/${BINARY_NAME}" "${NC}"

# Symlink 'modex' typo redirect to 'nodex'
if [ -w "$INSTALL_DIR" ]; then
    ln -sf "${INSTALL_DIR}/${BINARY_NAME}" "${INSTALL_DIR}/modex" 2>/dev/null || true
    sleep 0.7
    printf "  %b✔%b %b%-16s%b %b[%s/modex]%b\n" "${GREEN}" "${NC}" "${WHITE}" "Create alias" "${NC}" "${GRAY}" "${INSTALL_DIR}" "${NC}"
fi

# Ensure INSTALL_DIR is in PATH for shell profile if it's a custom user dir
case ":$PATH:" in
    *":${INSTALL_DIR}:"*) ;;
    *)
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
        sleep 0.7
        printf "  %b✔%b %b%-16s%b %b[Shell Profile Updated]%b\n" "${GREEN}" "${NC}" "${WHITE}" "Config PATH" "${NC}" "${GRAY}" "${NC}"
        ;;
esac

# Optional Systemd service setup if /etc/systemd/system exists and is writable
if [ -d "/etc/systemd/system" ] && [ -w "/etc/systemd/system" ] && command -v systemctl >/dev/null 2>&1; then
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
    sleep 0.7
    printf "  %b✔%b %b%-16s%b %b[/etc/systemd/system/nodex.service]%b\n" "${GREEN}" "${NC}" "${WHITE}" "Systemd Service" "${NC}" "${GRAY}" "${NC}"
fi

sleep 0.7

# Final Summary Box
printf "\n%b──────────────────────────────────────────────────────────%b\n" "${GRAY}" "${NC}"
printf "  %bNODEX installed successfully!%b\n\n" "${GREEN}${BOLD}" "${NC}"
printf "  %bInteractive TUI%b : %bnodex%b\n" "${GRAY}" "${NC}" "${WHITE}" "${NC}"
printf "  %bQuick Setup%b     : %bnodex --help%b\n" "${GRAY}" "${NC}" "${CYAN}" "${NC}"
printf "%b──────────────────────────────────────────────────────────%b\n" "${GRAY}" "${NC}"
