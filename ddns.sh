#!/bin/sh
set -eu

# Defaults from environment or baseline
PROVIDER="${DDNS_PROVIDER:-cloudflare}"
DOMAIN="${DDNS_DOMAIN:-}"
TOKEN="${DDNS_TOKEN:-}"
ZONE_ID="${DDNS_ZONE_ID:-}"
RECORD_TYPE="${DDNS_RECORD_TYPE:-A}"
INTERVAL="${DDNS_INTERVAL:-300}"
MODE="${DDNS_MODE:-once}"
FORCE="${DDNS_FORCE:-0}"
DRY_RUN=0
TEST_IP=""
DRY_RUN_UPDATE=0

# ANSI Colors
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
BOLD='\033[1m'
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
  -h, --help              Show this help message
EOF
    exit 0
}

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

main() {
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
}

main
