#!/bin/sh
set -eu

CURRENT_VERSION="1.0.1"
BUILD_HASH="dev"

# Baseline defaults
PROVIDER="cloudflare"
DOMAIN=""
TOKEN=""
ZONE_ID=""
RECORD_TYPE="A"
INTERVAL="300"
MODE="once"
FORCE=0
DRY_RUN=0
TEST_IP=""
DRY_RUN_UPDATE=0

# Capture caller environment before config file load
ENV_PROVIDER="${DDNS_PROVIDER-}"
ENV_DOMAIN="${DDNS_DOMAIN-}"
ENV_TOKEN="${DDNS_TOKEN-}"
ENV_ZONE_ID="${DDNS_ZONE_ID-}"
ENV_RECORD_TYPE="${DDNS_RECORD_TYPE-}"
ENV_INTERVAL="${DDNS_INTERVAL-}"
ENV_MODE="${DDNS_MODE-}"
ENV_FORCE="${DDNS_FORCE-}"

# Config File Paths
CONFIG_DIR="${HOME:-/root}/.config/nodex"
CONFIG_FILE="${CONFIG_DIR}/config"
GLOBAL_CONFIG="/etc/default/nodex"

# Load config file if present
if [ -f "$GLOBAL_CONFIG" ]; then
    . "$GLOBAL_CONFIG" 2>/dev/null || true
elif [ -f "$CONFIG_FILE" ]; then
    . "$CONFIG_FILE" 2>/dev/null || true
fi

# Config file values
[ -z "${DDNS_PROVIDER+x}" ] || PROVIDER="$DDNS_PROVIDER"
[ -z "${DDNS_DOMAIN+x}" ] || DOMAIN="$DDNS_DOMAIN"
[ -z "${DDNS_TOKEN+x}" ] || TOKEN="$DDNS_TOKEN"
[ -z "${DDNS_ZONE_ID+x}" ] || ZONE_ID="$DDNS_ZONE_ID"
[ -z "${DDNS_RECORD_TYPE+x}" ] || RECORD_TYPE="$DDNS_RECORD_TYPE"
[ -z "${DDNS_INTERVAL+x}" ] || INTERVAL="$DDNS_INTERVAL"
[ -z "${DDNS_MODE+x}" ] || MODE="$DDNS_MODE"
[ -z "${DDNS_FORCE+x}" ] || FORCE="$DDNS_FORCE"

# Caller environment overrides config file
[ -z "$ENV_PROVIDER" ] || PROVIDER="$ENV_PROVIDER"
[ -z "$ENV_DOMAIN" ] || DOMAIN="$ENV_DOMAIN"
[ -z "$ENV_TOKEN" ] || TOKEN="$ENV_TOKEN"
[ -z "$ENV_ZONE_ID" ] || ZONE_ID="$ENV_ZONE_ID"
[ -z "$ENV_RECORD_TYPE" ] || RECORD_TYPE="$ENV_RECORD_TYPE"
[ -z "$ENV_INTERVAL" ] || INTERVAL="$ENV_INTERVAL"
[ -z "$ENV_MODE" ] || MODE="$ENV_MODE"
[ -z "$ENV_FORCE" ] || FORCE="$ENV_FORCE"

# ANSI Colors
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
BOLD='\033[1m'
DIM='\033[2m'
REVERSE='\033[7m'
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
    timestamp=$(date -u +'%Y-%m-%dT%H:%M:%SZ')
    printf "%b[%s]%b %b\n" "${CYAN}" "$timestamp" "${NC}" "$*"
}

log_box() {
    title="$1"
    status="$2"
    details="$3"

    printf "%b┌────────────────────────────────────────────────────────┐%b\n" "${BLUE}" "${NC}"
    printf "%b│%b %b%-54s%b %b│%b\n" "${BLUE}" "${NC}" "${BOLD}" "$title" "${NC}" "${BLUE}" "${NC}"
    printf "%b├────────────────────────────────────────────────────────┤%b\n" "${BLUE}" "${NC}"
    printf "%b│%b Status:  %-46b %b│%b\n" "${BLUE}" "${NC}" "$status" "${BLUE}" "${NC}"
    printf "%b│%b Details: %-46b %b│%b\n" "${BLUE}" "${NC}" "$details" "${BLUE}" "${NC}"
    printf "%b└────────────────────────────────────────────────────────┘%b\n" "${BLUE}" "${NC}"
}

usage() {
    show_banner
    cat <<EOF
Usage: nodex [OPTIONS]

Options:
  -p, --provider <name>   DNS Provider (cloudflare | duckdns) [default: cloudflare]
  -d, --domain <fqdn>     Domain / Hostname to update
  -t, --token <token>     API token (Cloudflare API token or DuckDNS token)
  -z, --zone <zone_id>    Cloudflare Zone ID (required for Cloudflare)
  -type, --record-type <A|AAAA> DNS record type [default: A]
  -i, --interval <sec>    Check interval for daemon mode [default: 300]
  --daemon                Run continuously in daemon mode
  --force                 Ignore cache and force DNS update
  --dry-run               Output parsed parameters and exit
  -u, --update            Update NODEX to the latest version
  -h, --help              Show this help message
EOF
    exit 0
}

perform_self_update() {
    log "Checking for updates and updating NODEX..."
    RAW_INSTALL_URL="https://raw.githubusercontent.com/marhaburrisqi/Nodex/main/install.sh"
    if curl -fsSL --max-time 15 "$RAW_INSTALL_URL" | sh; then
        log_box "NODEX Update" "${GREEN}SUCCESS${NC}" "NODEX updated successfully."
        exit 0
    else
        log_box "NODEX Update" "${RED}FAILED${NC}" "Update failed. Check network connectivity."
        return 1
    fi
}

get_remote_info() {
    tmp_v=$(mktemp /tmp/nodex_ver.XXXXXX 2>/dev/null || echo "/tmp/nodex_ver.tmp")
    tmp_h=$(mktemp /tmp/nodex_hash.XXXXXX 2>/dev/null || echo "/tmp/nodex_hash.tmp")

    (curl -fsSL --max-time 2 https://raw.githubusercontent.com/marhaburrisqi/Nodex/main/ddns.sh 2>/dev/null | sed -n 's/^CURRENT_VERSION="\([^"]*\)"/\1/p' > "$tmp_v") &
    (curl -fsSL --max-time 2 "https://api.github.com/repos/marhaburrisqi/Nodex/commits/main" 2>/dev/null | grep '"sha"' | head -n 1 | cut -d'"' -f4 | cut -c1-7 > "$tmp_h") &
    wait

    r_ver=$(cat "$tmp_v" 2>/dev/null || true)
    r_hash=$(cat "$tmp_h" 2>/dev/null || true)
    rm -f "$tmp_v" "$tmp_h" 2>/dev/null || true

    REMOTE_VERSION="${r_ver:-$CURRENT_VERSION}"
    REMOTE_HASH="${r_hash:-}"
}

HAS_ARGS=0
if [ $# -gt 0 ]; then
    HAS_ARGS=1
fi

while [ $# -gt 0 ]; do
    case "$1" in
        -p|--provider)
            [ $# -ge 2 ] || { echo "Error: $1 requires an argument" >&2; exit 1; }
            PROVIDER="$2"; shift 2 ;;
        -d|--domain)
            [ $# -ge 2 ] || { echo "Error: $1 requires an argument" >&2; exit 1; }
            DOMAIN="$2"; shift 2 ;;
        -t|--token)
            [ $# -ge 2 ] || { echo "Error: $1 requires an argument" >&2; exit 1; }
            TOKEN="$2"; shift 2 ;;
        -z|--zone)
            [ $# -ge 2 ] || { echo "Error: $1 requires an argument" >&2; exit 1; }
            ZONE_ID="$2"; shift 2 ;;
        -type|--record-type)
            [ $# -ge 2 ] || { echo "Error: $1 requires an argument" >&2; exit 1; }
            RECORD_TYPE="$2"; shift 2 ;;
        -i|--interval)
            [ $# -ge 2 ] || { echo "Error: $1 requires an argument" >&2; exit 1; }
            INTERVAL="$2"; shift 2 ;;
        --daemon) MODE="daemon"; shift ;;
        --force) FORCE=1; shift ;;
        --dry-run) DRY_RUN=1; shift ;;
        --test-ip)
            [ $# -ge 2 ] || { echo "Error: $1 requires an argument" >&2; exit 1; }
            TEST_IP="$2"; shift 2 ;;
        --dry-run-update) DRY_RUN_UPDATE=1; shift ;;
        -u|--update) perform_self_update ;;
        -h|--help) usage ;;
        *) echo "Error: Unknown argument $1" >&2; exit 1 ;;
    esac
done

if [ "$DRY_RUN" -eq 1 ]; then
    echo "domain=$DOMAIN provider=$PROVIDER type=$RECORD_TYPE mode=$MODE force=$FORCE"
    exit 0
fi

get_public_ip() {
    if [ -n "$TEST_IP" ]; then
        echo "$TEST_IP"
        return 0
    fi

    ip_flag="-4"
    if [ "$RECORD_TYPE" = "AAAA" ]; then
        ip_flag="-6"
    fi

    ip=""
    # 1. ipify
    ip=$(curl -s $ip_flag --max-time 5 https://api.ipify.org 2>/dev/null || true)

    # 2. icanhazip fallback
    if [ -z "$ip" ]; then
        ip=$(curl -s $ip_flag --max-time 5 https://icanhazip.com 2>/dev/null | tr -d ' \n\r' || true)
    fi

    # 3. ifconfig.me fallback
    if [ -z "$ip" ]; then
        ip=$(curl -s $ip_flag --max-time 5 https://ifconfig.me/ip 2>/dev/null | tr -d ' \n\r' || true)
    fi

    if [ -z "$ip" ]; then
        log "${RED}Error: Failed to fetch public IP address${NC}" >&2
        return 1
    fi

    echo "$ip"
}

get_cache_file() {
    clean_domain=$(echo "$DOMAIN" | tr '/:' '_')
    echo "/tmp/ddns_${clean_domain}_${RECORD_TYPE}.cache"
}

is_ip_changed() {
    new_ip="$1"
    cache_file=$(get_cache_file)

    if [ "$FORCE" -eq 1 ]; then
        return 0
    fi

    if [ -f "$cache_file" ]; then
        old_ip=$(cat "$cache_file" 2>/dev/null || true)
        if [ "$old_ip" = "$new_ip" ]; then
            return 1 # Unchanged
        fi
    fi

    return 0 # Changed or no cache
}

update_ip_cache() {
    new_ip="$1"
    cache_file=$(get_cache_file)
    echo "$new_ip" > "$cache_file"
}

update_duckdns() {
    ip="$1"
    log "Updating DuckDNS record ${BOLD}$DOMAIN${NC} to ${GREEN}$ip${NC}..."

    # DuckDNS domains argument usually drops .duckdns.org suffix if passed
    subdomain=$(echo "$DOMAIN" | sed 's/\.duckdns\.org$//')

    response=$(curl -sL --max-time 15 "https://www.duckdns.org/update?domains=${subdomain}&token=${TOKEN}&ip=${ip}")

    if [ "$response" = "OK" ]; then
        log_box "DuckDNS Sync Result" "${GREEN}SUCCESS${NC}" "Record updated to $ip"
        return 0
    else
        log_box "DuckDNS Sync Result" "${RED}FAILED${NC}" "Response: $response"
        return 1
    fi
}

update_cloudflare() {
    ip="$1"
    if [ -z "$ZONE_ID" ]; then
        log "${RED}Error: CF_ZONE_ID (or --zone) is required for Cloudflare provider${NC}" >&2
        return 1
    fi
    if [ -z "$TOKEN" ]; then
        log "${RED}Error: CF_API_TOKEN (or --token) is required for Cloudflare provider${NC}" >&2
        return 1
    fi

    log "Querying Cloudflare API for existing $RECORD_TYPE record (${BOLD}$DOMAIN${NC})..."
    records_response=$(curl -s --max-time 15 -X GET \
        "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records?type=${RECORD_TYPE}&name=${DOMAIN}" \
        -H "Authorization: Bearer ${TOKEN}" \
        -H "Content-Type: application/json")

    record_id=""
    if command -v jq >/dev/null 2>&1; then
        record_id=$(echo "$records_response" | jq -r '.result[0].id // empty')
    else
        record_id=$(echo "$records_response" | sed -n 's/.*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)
    fi

    if [ -z "$record_id" ]; then
        log_box "Cloudflare Sync Result" "${RED}FAILED${NC}" "No existing $RECORD_TYPE record found for $DOMAIN"
        return 1
    fi

    log "Updating Cloudflare record $record_id to ${GREEN}$ip${NC}..."
    update_response=$(curl -s --max-time 15 -X PUT \
        "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records/${record_id}" \
        -H "Authorization: Bearer ${TOKEN}" \
        -H "Content-Type: application/json" \
        --data "{\"type\":\"${RECORD_TYPE}\",\"name\":\"${DOMAIN}\",\"content\":\"${ip}\",\"ttl\":1,\"proxied\":false}")

    success=""
    if command -v jq >/dev/null 2>&1; then
        success=$(echo "$update_response" | jq -r '.success // false')
    else
        case "$update_response" in
            *"\"success\":true"*) success="true" ;;
            *) success="false" ;;
        esac
    fi

    if [ "$success" = "true" ]; then
        log_box "Cloudflare Sync Result" "${GREEN}SUCCESS${NC}" "Record updated to $ip"
        return 0
    else
        log_box "Cloudflare Sync Result" "${RED}FAILED${NC}" "API response error"
        return 1
    fi
}

run_check() {
    if [ -z "$DOMAIN" ] || [ -z "$TOKEN" ]; then
        log "${YELLOW}Missing required parameters. Showing usage guide...${NC}"
        echo ""
        usage
    fi

    current_ip=$(get_public_ip)
    log "Current public IP (${BOLD}$RECORD_TYPE${NC}): ${GREEN}$current_ip${NC}"

    if is_ip_changed "$current_ip"; then
        log "${YELLOW}IP changed or force update requested. Triggering update...${NC}"

        if [ "$DRY_RUN_UPDATE" -eq 1 ]; then
            log "[DRY-RUN] Would update $PROVIDER for $DOMAIN to $current_ip"
            update_ip_cache "$current_ip"
            return 0
        fi

        case "$PROVIDER" in
            cloudflare) update_cloudflare "$current_ip" ;;
            duckdns) update_duckdns "$current_ip" ;;
            *) log "${RED}Error: Unsupported provider $PROVIDER${NC}" >&2; exit 1 ;;
        esac

        update_ip_cache "$current_ip"
    else
        log "${GREEN}IP address unchanged ($current_ip). Skipping DNS update.${NC}"
    fi
}

# Quick Setup Config Action
select_provider_tui() {
    p_sel=0
    [ "${PROVIDER:-cloudflare}" = "duckdns" ] && p_sel=1
    old_stty=$(stty -g 2>/dev/null || true)
    stty -echo -icanon min 1 time 0 2>/dev/null || true
    printf "\033[?25l" >&2
    while true; do
        printf "\033[H\033[2J" >&2
        printf "%b=== Select DNS Provider ===%b\n\n" "${CYAN}${BOLD}" "${NC}" >&2
        if [ "$p_sel" -eq 0 ]; then
            printf "%b> 1. Cloudflare%b\n" "${CYAN}${BOLD}" "${NC}" >&2
            printf "  2. DuckDNS   \n" >&2
        else
            printf "  1. Cloudflare\n" >&2
            printf "%b> 2. DuckDNS   %b\n" "${CYAN}${BOLD}" "${NC}" >&2
        fi
        printf "\n----------------------------------------\n" >&2
        printf "[Up/Down] Navigate  |  [Enter] Select\n" >&2

        key=$(dd bs=1 count=1 2>/dev/null || true)
        action=0
        if [ "$key" = "$(printf '\033')" ]; then
            stty -echo -icanon min 0 time 1 2>/dev/null || true
            k2=$(dd bs=1 count=1 2>/dev/null || true)
            k3=""
            if [ "$k2" = "[" ] || [ "$k2" = "O" ]; then
                k3=$(dd bs=1 count=1 2>/dev/null || true)
            fi
            stty -echo -icanon min 1 time 0 2>/dev/null || true
            case "$k3" in
                A|B|C|D) p_sel=$((1 - p_sel)) ;;
            esac
        elif [ "$key" = "j" ] || [ "$key" = "k" ] || [ "$key" = "w" ] || [ "$key" = "s" ]; then
            p_sel=$((1 - p_sel))
        elif [ "$key" = "1" ]; then
            p_sel=0; action=1
        elif [ "$key" = "2" ]; then
            p_sel=1; action=1
        elif [ -z "$key" ] || [ "$key" = "$(printf '\r')" ] || [ "$key" = "$(printf '\n')" ]; then
            action=1
        fi

        [ "$action" -eq 1 ] && break
    done
    stty "$old_stty" 2>/dev/null || stty sane 2>/dev/null || true
    printf "\033[?25h\033[H\033[2J" >&2
    if [ "$p_sel" -eq 0 ]; then
        echo "cloudflare"
    else
        echo "duckdns"
    fi
}

quick_setup() {
    echo ""
    printf "%b=== NODEX Quick Credentials Setup ===%b\n\n" "${CYAN}${BOLD}" "${NC}"

    current_p="${PROVIDER:-cloudflare}"
    if [ -t 0 ]; then
        provider_val=$(select_provider_tui)
    else
        printf "Provider (cloudflare | duckdns) [%s]: " "$current_p"
        read input_provider || true
        provider_val="${input_provider:-$current_p}"
    fi

    printf "Domain / FQDN [%s]: " "${DOMAIN:-}"
    read input_domain || true
    domain_val="${input_domain:-$DOMAIN}"

    printf "API Token [%s]: " "${TOKEN:-}"
    read input_token || true
    token_val="${input_token:-$TOKEN}"

    zone_val=""
    if [ "$provider_val" = "cloudflare" ]; then
        printf "Cloudflare Zone ID [%s]: " "${ZONE_ID:-}"
        read input_zone || true
        zone_val="${input_zone:-$ZONE_ID}"
    fi

    target_config=""
    if [ -w "/etc/default" ] || [ "$(id -u 2>/dev/null || echo 1)" -eq 0 ]; then
        target_config="/etc/default/nodex"
    else
        mkdir -p "$CONFIG_DIR"
        target_config="$CONFIG_FILE"
    fi

    cat <<EOF > "$target_config"
DDNS_PROVIDER="${provider_val}"
DDNS_DOMAIN="${domain_val}"
DDNS_TOKEN="${token_val}"
DDNS_ZONE_ID="${zone_val}"
DDNS_RECORD_TYPE="${RECORD_TYPE:-A}"
DDNS_INTERVAL="${INTERVAL:-300}"
DDNS_MODE="${MODE:-once}"
EOF
    chmod 600 "$target_config" 2>/dev/null || true

    PROVIDER="$provider_val"
    DOMAIN="$domain_val"
    TOKEN="$token_val"
    ZONE_ID="$zone_val"

    printf "\n%b✓ Configuration saved to %s%b\n" "${GREEN}" "$target_config" "${NC}"
    printf "Press Enter to return to menu..."
    read _ || true
}

inspect_status() {
    echo ""
    printf "%b============================================================%b\n" "${CYAN}" "${NC}"
    printf "%b  NODEX Status & System Health%b\n" "${BOLD}" "${NC}"
    printf "%b============================================================%b\n" "${CYAN}" "${NC}"

    printf "Active Provider  : %s\n" "${PROVIDER:-None}"
    printf "Target Domain    : %s\n" "${DOMAIN:-Not Configured}"
    printf "Record Type      : %s\n" "${RECORD_TYPE:-A}"

    public_ip=$(get_public_ip 2>/dev/null || echo "Fetch Failed")
    printf "Public IP        : %s\n" "$public_ip"

    if [ -n "$DOMAIN" ]; then
        cache_f=$(get_cache_file)
        if [ -f "$cache_f" ]; then
            printf "Cached IP State  : %s (%s)\n" "$(cat "$cache_f")" "$cache_f"
        else
            printf "Cached IP State  : No cache file yet\n"
        fi
    fi

    if command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet nodex 2>/dev/null; then
        printf "Daemon Status    : %bActive (systemd)%b\n" "${GREEN}" "${NC}"
    else
        printf "Daemon Status    : %bInactive / Manual%b\n" "${YELLOW}" "${NC}"
    fi

    printf "%b============================================================%b\n\n" "${CYAN}" "${NC}"
    printf "Press Enter to return to menu..."
    read _ || true
}

uninstall_nodex() {
    echo ""
    printf "%bAre you sure you want to uninstall NODEX? (y/N): %b" "${RED}${BOLD}" "${NC}"
    read confirm || true
    case "$confirm" in
        y|Y|yes|YES)
            if command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet nodex 2>/dev/null; then
                systemctl disable --now nodex 2>/dev/null || true
                rm -f /etc/systemd/system/nodex.service 2>/dev/null || true
            fi

            # Detect path where running script or installed binary lives
            self_path=""
            if command -v nodex >/dev/null 2>&1; then
                self_path=$(command -v nodex 2>/dev/null || true)
            fi

            # Remove binaries across all potential user/system locations
            rm -f /usr/local/bin/nodex /usr/local/bin/modex \
                  /usr/bin/nodex /usr/bin/modex \
                  "${HOME:-}/.local/bin/nodex" "${HOME:-}/.local/bin/modex" \
                  "${PREFIX:-}/bin/nodex" "${PREFIX:-}/bin/modex" 2>/dev/null || true

            if [ -n "$self_path" ] && [ -f "$self_path" ]; then
                rm -f "$self_path" 2>/dev/null || true
            fi

            rm -rf "$CONFIG_DIR" "$GLOBAL_CONFIG" 2>/dev/null || true
            rm -f /tmp/ddns_*.cache 2>/dev/null || true
            printf "%b✓ NODEX uninstalled cleanly.%b\n" "${GREEN}" "${NC}"
            exit 0
            ;;
        *)
            printf "Uninstall cancelled.\n"
            sleep 1
            ;;
    esac
}

# TUI Interactive Router Menu Engine
tui_menu() {
    OLD_STTY=$(stty -g 2>/dev/null || true)
    cleanup_tui() {
        stty "$OLD_STTY" 2>/dev/null || stty sane 2>/dev/null || true
        printf "\033[?25h"
        exit 0
    }
    trap cleanup_tui INT TERM EXIT

    selected=0
    get_remote_info

    local_hash="${BUILD_HASH:-dev}"
    has_update=0
    update_label=""

    if [ "$REMOTE_VERSION" != "$CURRENT_VERSION" ]; then
        has_update=1
        if [ -n "$REMOTE_HASH" ]; then
            update_label="v${REMOTE_VERSION} (${REMOTE_HASH})"
        else
            update_label="v${REMOTE_VERSION}"
        fi
    elif [ "$local_hash" != "dev" ] && [ -n "$REMOTE_HASH" ] && [ "$REMOTE_HASH" != "$local_hash" ]; then
        has_update=1
        update_label="${REMOTE_HASH}"
    fi

    if [ "$has_update" -eq 1 ]; then
        menu_items="* Update to ${update_label};1. Sync DNS Now (One-Shot Trigger);2. Start Background Daemon;3. Quick Setup / Configure Credentials;4. Inspect Status and Cache Logs;5. Uninstall NODEX;6. Exit"
        total_items=7
    else
        menu_items="1. Sync DNS Now (One-Shot Trigger);2. Start Background Daemon;3. Quick Setup / Configure Credentials;4. Inspect Status and Cache Logs;5. Uninstall NODEX;6. Exit"
        total_items=6
    fi

    # Pre-fetch public IP once before entering loop so screen redraws don't block
    cached_tui_ip=$(get_public_ip 2>/dev/null || echo "")

    stty -echo -icanon min 1 time 0 2>/dev/null || true
    printf "\033[?25l" # Hide cursor

    while true; do
        printf "\033[H\033[2J" # Clear screen smoothly

        # Color & raw value evaluation for header fields
        prov_val="${PROVIDER:-None}"
        if [ "$prov_val" = "None" ]; then prov_color="$YELLOW"; else prov_color="$GREEN"; fi

        dom_val="${DOMAIN:-Not Configured}"
        if [ "$dom_val" = "Not Configured" ]; then dom_color="$YELLOW"; else dom_color="$GREEN"; fi

        ip_val="${cached_tui_ip:-Not Available}"
        if [ "$ip_val" = "Not Available" ]; then ip_color="$YELLOW"; else ip_color="$GREEN"; fi

        printf "+----------------------------------------------------------+\n"
        if [ "$has_update" -eq 1 ]; then
            title_text="NODEX Gateway (v${CURRENT_VERSION}) -> Update Available: ${update_label}"
            printf "| %b%-56s%b |\n" "${YELLOW}${BOLD}" "$title_text" "${NC}"
        else
            title_text="NODEX Gateway (v${CURRENT_VERSION})"
            printf "| %b%-56s%b |\n" "${CYAN}${BOLD}" "$title_text" "${NC}"
        fi
        printf "| Provider  : %b%-44s%b |\n" "$prov_color" "$prov_val" "${NC}"
        printf "| Target    : %b%-44s%b |\n" "$dom_color" "$dom_val" "${NC}"
        printf "| Public IP : %b%-44s%b |\n" "$ip_color" "$ip_val" "${NC}"
        printf "+----------------------------------------------------------+\n\n"

        idx=0
        old_ifs="$IFS"
        IFS=";"
        for item in $menu_items; do
            if [ "$idx" -eq "$selected" ]; then
                if [ "$has_update" -eq 1 ] && [ "$idx" -eq 0 ]; then
                    printf "%b> %s%b\n" "${YELLOW}${BOLD}" "$item" "${NC}"
                else
                    printf "%b> %s%b\n" "${CYAN}${BOLD}" "$item" "${NC}"
                fi
            else
                if [ "$has_update" -eq 1 ] && [ "$idx" -eq 0 ]; then
                    printf "  %b%s%b\n" "${YELLOW}" "$item" "${NC}"
                else
                    printf "  %s\n" "$item"
                fi
            fi
            idx=$((idx + 1))
        done
        IFS="$old_ifs"

        printf "\n----------------------------------------\n"
        printf "[Up/Down] Navigate  |  [Enter] Select  |  [q] Quit\n"

        key=$(dd bs=1 count=1 2>/dev/null || true)
        action=0

        if [ "$key" = "$(printf '\033')" ]; then
            stty -echo -icanon min 0 time 1 2>/dev/null || true
            k2=$(dd bs=1 count=1 2>/dev/null || true)
            k3=""
            if [ "$k2" = "[" ] || [ "$k2" = "O" ]; then
                k3=$(dd bs=1 count=1 2>/dev/null || true)
            fi
            stty -echo -icanon min 1 time 0 2>/dev/null || true
            case "$k3" in
                A) selected=$(( (selected - 1 + total_items) % total_items )) ;; # Up
                B) selected=$(( (selected + 1) % total_items )) ;;               # Down
            esac
        elif [ "$key" = "k" ] || [ "$key" = "K" ] || [ "$key" = "w" ] || [ "$key" = "W" ]; then
            selected=$(( (selected - 1 + total_items) % total_items ))
        elif [ "$key" = "j" ] || [ "$key" = "J" ] || [ "$key" = "s" ] || [ "$key" = "S" ]; then
            selected=$(( (selected + 1) % total_items ))
        elif [ "$key" = "1" ]; then selected=0; action=1
        elif [ "$key" = "2" ]; then selected=1; action=1
        elif [ "$key" = "3" ]; then selected=2; action=1
        elif [ "$key" = "4" ]; then selected=3; action=1
        elif [ "$key" = "5" ]; then selected=4; action=1
        elif [ "$key" = "6" ]; then selected=5; action=1
        elif [ "$key" = "q" ] || [ "$key" = "Q" ]; then
            cleanup_tui
        elif [ -z "$key" ] || [ "$key" = "$(printf '\r')" ] || [ "$key" = "$(printf '\n')" ]; then
            action=1
        fi

        if [ "$action" -eq 1 ]; then
            stty "$OLD_STTY" 2>/dev/null || stty sane 2>/dev/null || true
            printf "\033[?25h\033[H\033[2J"
            if [ "$has_update" -eq 1 ]; then
                case "$selected" in
                    0) perform_self_update ;;
                    1) FORCE=1; run_check; printf "\nPress Enter to return to menu..."; read _ || true ;;
                    2) MODE="daemon"; main ;;
                    3) quick_setup; cached_tui_ip=$(get_public_ip 2>/dev/null || echo "") ;;
                    4) inspect_status ;;
                    5) uninstall_nodex ;;
                    6) exit 0 ;;
                esac
            else
                case "$selected" in
                    0) FORCE=1; run_check; printf "\nPress Enter to return to menu..."; read _ || true ;;
                    1) MODE="daemon"; main ;;
                    2) quick_setup; cached_tui_ip=$(get_public_ip 2>/dev/null || echo "") ;;
                    3) inspect_status ;;
                    4) uninstall_nodex ;;
                    5) exit 0 ;;
                esac
            fi
            stty -echo -icanon min 1 time 0 2>/dev/null || true
            printf "\033[?25l"
        fi
    done
}

main() {
    # If parameters passed, run CLI mode headlessly
    if [ "$HAS_ARGS" -eq 1 ] || [ "$MODE" = "daemon" ]; then
        if [ "$MODE" = "daemon" ]; then
            show_banner
            log "Starting NODEX in daemon mode (interval: ${INTERVAL}s)..."
            while true; do
                run_check || log "${YELLOW}Warning: Check iteration encountered errors.${NC}"
                sleep "$INTERVAL"
            done
        else
            if [ -z "$DOMAIN" ] || [ -z "$TOKEN" ]; then
                usage
            else
                show_banner
                run_check
            fi
        fi
    else
        # If no arguments passed, check if in an interactive TTY
        if [ -t 0 ]; then
            tui_menu
        else
            usage
        fi
    fi
}

main
