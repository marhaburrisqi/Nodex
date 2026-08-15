#!/bin/sh
set -eu

CURRENT_VERSION="1.3.2"
BUILD_HASH="dev"

# Baseline defaults
PROVIDER="cloudflare"
DOMAIN=""
TOKEN=""
ZONE_ID=""
PROJECT_ID=""
RECORD_TYPE="A"
INTERVAL="300"
MODE="once"
FORCE=0
DRY_RUN=0
NO_INTRO=0
TEST_IP=""
DRY_RUN_UPDATE=0

# Capture caller environment before config file load
ENV_PROVIDER="${DDNS_PROVIDER-}"
ENV_DOMAIN="${DDNS_DOMAIN-}"
ENV_TOKEN="${DDNS_TOKEN-}"
ENV_ZONE_ID="${DDNS_ZONE_ID-}"
ENV_PROJECT_ID="${DDNS_PROJECT_ID-}"
ENV_RECORD_TYPE="${DDNS_RECORD_TYPE-}"
ENV_INTERVAL="${DDNS_INTERVAL-}"
ENV_MODE="${DDNS_MODE-}"
ENV_FORCE="${DDNS_FORCE-}"
ENV_NO_INTRO="${NODEX_NO_INTRO-}"

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
[ -z "${DDNS_PROJECT_ID+x}" ] || PROJECT_ID="$DDNS_PROJECT_ID"
[ -z "${DDNS_RECORD_TYPE+x}" ] || RECORD_TYPE="$DDNS_RECORD_TYPE"
[ -z "${DDNS_INTERVAL+x}" ] || INTERVAL="$DDNS_INTERVAL"
[ -z "${DDNS_MODE+x}" ] || MODE="$DDNS_MODE"
[ -z "${DDNS_FORCE+x}" ] || FORCE="$DDNS_FORCE"
[ -z "${NODEX_NO_INTRO+x}" ] || NO_INTRO="$NODEX_NO_INTRO"

# Caller environment overrides config file
[ -z "$ENV_PROVIDER" ] || PROVIDER="$ENV_PROVIDER"
[ -z "$ENV_DOMAIN" ] || DOMAIN="$ENV_DOMAIN"
[ -z "$ENV_TOKEN" ] || TOKEN="$ENV_TOKEN"
[ -z "$ENV_ZONE_ID" ] || ZONE_ID="$ENV_ZONE_ID"
[ -z "$ENV_PROJECT_ID" ] || PROJECT_ID="$ENV_PROJECT_ID"
[ -z "$ENV_RECORD_TYPE" ] || RECORD_TYPE="$ENV_RECORD_TYPE"
[ -z "$ENV_INTERVAL" ] || INTERVAL="$ENV_INTERVAL"
[ -z "$ENV_MODE" ] || MODE="$ENV_MODE"
[ -z "$ENV_FORCE" ] || FORCE="$ENV_FORCE"
[ -z "$ENV_NO_INTRO" ] || NO_INTRO="$ENV_NO_INTRO"

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

    case "$status" in
        *SUCCESS*)
            printf "  %b✔%b %b%s%b\n" "${GREEN}" "${NC}" "${WHITE}" "$title" "${NC}"
            printf "    %bStatus%b  : %b\n" "${GRAY}" "${NC}" "$status"
            printf "    %bDetails%b : %b%s%b\n" "${GRAY}" "${NC}" "${GRAY}" "$details" "${NC}"
            ;;
        *)
            printf "  %b✖%b %b%s%b\n" "${RED}" "${NC}" "${WHITE}" "$title" "${NC}"
            printf "    %bStatus%b  : %b\n" "${GRAY}" "${NC}" "$status"
            printf "    %bDetails%b : %b%s%b\n" "${GRAY}" "${NC}" "${GRAY}" "$details" "${NC}"
            ;;
    esac
}

usage() {
    show_banner
    cat <<EOF
Usage: nodex [OPTIONS]

Options:
  -p, --provider <name>   DNS Provider (cloudflare | duckdns | dynu | desec | route53 | gcp) [default: cloudflare]
  -d, --domain <fqdn>     Domain / Hostname to update
  -t, --token <token>     API token (Bearer / Token / Key)
  -z, --zone <zone_id>    Zone ID / Hosted Zone ID / Managed Zone
  --project-id <id>       Google Cloud Project ID (required for GCP)
  -type, --record-type <A|AAAA> DNS record type [default: A]
  -i, --interval <sec>    Check interval for daemon mode [default: 300]
  --daemon                Run continuously in daemon mode
  --force                 Ignore cache and force DNS update
  --no-intro              Skip micro-boot intro animation
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
        --project-id)
            [ $# -ge 2 ] || { echo "Error: $1 requires an argument" >&2; exit 1; }
            PROJECT_ID="$2"; shift 2 ;;
        -type|--record-type)
            [ $# -ge 2 ] || { echo "Error: $1 requires an argument" >&2; exit 1; }
            RECORD_TYPE="$2"; shift 2 ;;
        -i|--interval)
            [ $# -ge 2 ] || { echo "Error: $1 requires an argument" >&2; exit 1; }
            INTERVAL="$2"; shift 2 ;;
        --daemon) MODE="daemon"; shift ;;
        --force) FORCE=1; shift ;;
        --no-intro) NO_INTRO=1; shift ;;
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
    ip=$(curl -s $ip_flag --connect-timeout 5 --max-time 15 --retry 1 --compressed https://api.ipify.org 2>/dev/null || true)

    # 2. icanhazip fallback
    if [ -z "$ip" ]; then
        raw_ip=$(curl -s $ip_flag --connect-timeout 5 --max-time 15 --retry 1 --compressed https://icanhazip.com 2>/dev/null || true)
        ip=$(echo "$raw_ip" | tr -d ' \n\r')
    fi

    # 3. ifconfig.me fallback
    if [ -z "$ip" ]; then
        raw_ip=$(curl -s $ip_flag --connect-timeout 5 --max-time 15 --retry 1 --compressed https://ifconfig.me/ip 2>/dev/null || true)
        ip=$(echo "$raw_ip" | tr -d ' \n\r')
    fi

    if [ -z "$ip" ]; then
        log "${RED}Error: Failed to fetch public IP address${NC}" >&2
        return 1
    fi

    echo "$ip"
}

get_cache_file() {
    cache_dir="${TMPDIR:-/tmp}"
    clean_domain=$(echo "$DOMAIN" | tr '/:' '_')
    echo "${cache_dir}/ddns_${clean_domain}_${RECORD_TYPE}.cache"
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

    # Pure POSIX suffix stripping without sed/forks
    subdomain="${DOMAIN%.duckdns.org}"

    response=$(curl -sL --connect-timeout 5 --max-time 15 --retry 1 --compressed "https://www.duckdns.org/update?domains=${subdomain}&token=${TOKEN}&ip=${ip}")

    if [ "$response" = "OK" ]; then
        log_box "DuckDNS Sync Result" "${GREEN}SUCCESS${NC}" "Record updated to $ip"
        return 0
    else
        log_box "DuckDNS Sync Result" "${RED}FAILED${NC}" "Response: $response"
        return 1
    fi
}

update_dynu() {
    ip="$1"
    log "Updating Dynu record ${BOLD}$DOMAIN${NC} to ${GREEN}$ip${NC}..."

    ip_param="myip"
    [ "$RECORD_TYPE" = "AAAA" ] && ip_param="myipv6"

    # Dynu accepts Basic Auth (-u username:password or token:token) or query/header
    response=$(curl -sL --connect-timeout 5 --max-time 15 --retry 1 --compressed -u "${TOKEN}:${TOKEN}" \
        "https://api.dynu.com/nic/update?hostname=${DOMAIN}&${ip_param}=${ip}")

    case "$response" in
        *good*|*nochg*)
            log_box "Dynu Sync Result" "${GREEN}SUCCESS${NC}" "Record updated: $response"
            return 0
            ;;
        *)
            log_box "Dynu Sync Result" "${RED}FAILED${NC}" "Response: $response"
            return 1
            ;;
    esac
}

update_desec() {
    ip="$1"
    log "Updating deSEC record ${BOLD}$DOMAIN${NC} (${BOLD}$RECORD_TYPE${NC}) to ${GREEN}$ip${NC}..."

    domain_zone="${ZONE_ID:-$DOMAIN}"
    subdomain=""
    if [ "$DOMAIN" = "$domain_zone" ]; then
        subdomain="@"
    else
        subdomain="${DOMAIN%."$domain_zone"}"
        [ "$subdomain" = "$DOMAIN" ] && subdomain="@"
    fi

    desec_url="https://desec.io/api/v1/domains/${domain_zone}/rrsets/${subdomain}/${RECORD_TYPE}/"
    [ "$subdomain" = "@" ] && desec_url="https://desec.io/api/v1/domains/${domain_zone}/rrsets/.../${RECORD_TYPE}/"

    response=$(curl -s --connect-timeout 5 --max-time 15 --retry 1 --compressed -X PUT "$desec_url" \
        -H "Authorization: Token ${TOKEN}" \
        -H "Content-Type: application/json" \
        --data "{\"records\":[\"${ip}\"],\"ttl\":300}")

    case "$response" in
        *"records"*|*"created"*|*"\"name\""*)
            log_box "deSEC Sync Result" "${GREEN}SUCCESS${NC}" "Record updated to $ip"
            return 0
            ;;
        *)
            log_box "deSEC Sync Result" "${RED}FAILED${NC}" "Response: $response"
            return 1
            ;;
    esac
}

update_route53() {
    ip="$1"
    if [ -z "$ZONE_ID" ]; then
        log "${RED}Error: Route 53 requires Hosted Zone ID (--zone or DDNS_ZONE_ID)${NC}" >&2
        return 1
    fi
    log "Updating AWS Route 53 hosted zone ${ZONE_ID} record ${BOLD}$DOMAIN${NC} to ${GREEN}$ip${NC}..."

    clean_zone="${ZONE_ID#/hostedzone/}"
    payload="{\"Comment\":\"NODEX DDNS Update\",\"Changes\":[{\"Action\":\"UPSERT\",\"ResourceRecordSet\":{\"Name\":\"${DOMAIN}.\",\"Type\":\"${RECORD_TYPE}\",\"TTL\":300,\"ResourceRecords\":[{\"Value\":\"${ip}\"}]}}]}"

    response=$(curl -s --connect-timeout 5 --max-time 15 --retry 1 --compressed -X POST \
        "https://route53.amazonaws.com/2013-04-01/hostedzone/${clean_zone}/rrset" \
        -H "Authorization: Bearer ${TOKEN}" \
        -H "Content-Type: application/json" \
        --data "$payload")

    case "$response" in
        *"ChangeInfo"*|*"PENDING"*|*"INSYNC"*)
            log_box "AWS Route 53 Sync Result" "${GREEN}SUCCESS${NC}" "Record change submitted ($ip)"
            return 0
            ;;
        *)
            log_box "AWS Route 53 Sync Result" "${RED}FAILED${NC}" "Response: $response"
            return 1
            ;;
    esac
}

update_gcp() {
    ip="$1"
    if [ -z "$PROJECT_ID" ]; then
        log "${RED}Error: GCP Cloud DNS requires Project ID (--project-id or DDNS_PROJECT_ID)${NC}" >&2
        return 1
    fi
    if [ -z "$ZONE_ID" ]; then
        log "${RED}Error: GCP Cloud DNS requires Managed Zone (--zone or DDNS_ZONE_ID)${NC}" >&2
        return 1
    fi
    log "Updating Google Cloud DNS project ${PROJECT_ID} zone ${ZONE_ID} (${BOLD}$DOMAIN${NC}) to ${GREEN}$ip${NC}..."

    payload="{\"additions\":[{\"name\":\"${DOMAIN}.\",\"type\":\"${RECORD_TYPE}\",\"ttl\":300,\"rrdatas\":[\"${ip}\"]}]}"

    response=$(curl -s --connect-timeout 5 --max-time 15 --retry 1 --compressed -X POST \
        "https://dns.googleapis.com/dns/v1/projects/${PROJECT_ID}/managedZones/${ZONE_ID}/changes" \
        -H "Authorization: Bearer ${TOKEN}" \
        -H "Content-Type: application/json" \
        --data "$payload")

    case "$response" in
        *"\"status\""*|*"\"kind\": \"dns#change\""*|*"\"id\""*)
            log_box "Google Cloud DNS Sync Result" "${GREEN}SUCCESS${NC}" "Record change submitted ($ip)"
            return 0
            ;;
        *)
            log_box "Google Cloud DNS Sync Result" "${RED}FAILED${NC}" "Response: $response"
            return 1
            ;;
    esac
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
    records_response=$(curl -s --connect-timeout 5 --max-time 15 --retry 1 --compressed -X GET \
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
    update_response=$(curl -s --connect-timeout 5 --max-time 15 --retry 1 --compressed -X PUT \
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
            dynu) update_dynu "$current_ip" ;;
            desec) update_desec "$current_ip" ;;
            route53) update_route53 "$current_ip" ;;
            gcp) update_gcp "$current_ip" ;;
            *) log "${RED}Error: Unsupported provider $PROVIDER${NC}" >&2; exit 1 ;;
        esac

        update_ip_cache "$current_ip"
    else
        log "${GREEN}IP address unchanged ($current_ip). Skipping DNS update.${NC}"
    fi
}

# Quick Setup Config Action
_provider_name() {
    case "$1" in
        0) echo "Cloudflare" ;;
        1) echo "DuckDNS" ;;
        2) echo "Dynu" ;;
        3) echo "deSEC" ;;
        4) echo "AWS Route 53" ;;
        5) echo "Google Cloud DNS" ;;
    esac
}

select_provider_tui() {
    p_sel=0
    case "${PROVIDER:-cloudflare}" in
        cloudflare) p_sel=0 ;;
        duckdns) p_sel=1 ;;
        dynu) p_sel=2 ;;
        desec) p_sel=3 ;;
        route53) p_sel=4 ;;
        gcp) p_sel=5 ;;
    esac
    old_stty=$(stty -g 2>/dev/null || true)
    stty -echo -icanon min 1 time 0 2>/dev/null || true
    printf "\033[?25l" >&2
    while true; do
        printf "\033[H\033[J" >&2
        printf "%b──────────────────────────────────────────────────────────%b\n" "${GRAY}" "${NC}" >&2
        printf "  %bSelect DNS Provider%b\n" "${BOLD}${WHITE}" "${NC}" >&2
        printf "%b──────────────────────────────────────────────────────────%b\n\n" "${GRAY}" "${NC}" >&2

        idx=0
        while [ "$idx" -lt 6 ]; do
            p_display=$(_provider_name "$idx")
            if [ "$p_sel" -eq "$idx" ]; then
                printf "  %b▎%b %b◆%b  %b%s%b\n" "${CYAN}" "${NC}" "${CYAN}" "${NC}" "${WHITE}" "$p_display" "${NC}" >&2
            else
                printf "    %b◇  %s%b\n" "${GRAY}" "$p_display" "${NC}" >&2
            fi
            idx=$((idx + 1))
        done
        printf "\n%b──────────────────────────────────────────────────────────%b\n" "${GRAY}" "${NC}" >&2
        printf "%b  [↑/↓] Navigate  •  [Enter] Select%b\n" "${DIM}" "${NC}" >&2

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
                A) p_sel=$(( (p_sel - 1 + 6) % 6 )) ;; # Up
                B) p_sel=$(( (p_sel + 1) % 6 )) ;;     # Down
            esac
        elif [ "$key" = "k" ] || [ "$key" = "K" ] || [ "$key" = "w" ] || [ "$key" = "W" ]; then
            p_sel=$(( (p_sel - 1 + 6) % 6 ))
        elif [ "$key" = "j" ] || [ "$key" = "J" ] || [ "$key" = "s" ] || [ "$key" = "S" ]; then
            p_sel=$(( (p_sel + 1) % 6 ))
        elif [ "$key" = "1" ]; then p_sel=0; action=1
        elif [ "$key" = "2" ]; then p_sel=1; action=1
        elif [ "$key" = "3" ]; then p_sel=2; action=1
        elif [ "$key" = "4" ]; then p_sel=3; action=1
        elif [ "$key" = "5" ]; then p_sel=4; action=1
        elif [ "$key" = "6" ]; then p_sel=5; action=1
        elif [ -z "$key" ] || [ "$key" = "$(printf '\r')" ] || [ "$key" = "$(printf '\n')" ]; then
            action=1
        fi

        [ "$action" -eq 1 ] && break
    done
    stty "$old_stty" 2>/dev/null || stty sane 2>/dev/null || true
    printf "\033[?25h\033[H\033[2J" >&2
    case "$p_sel" in
        0) echo "cloudflare" ;;
        1) echo "duckdns" ;;
        2) echo "dynu" ;;
        3) echo "desec" ;;
        4) echo "route53" ;;
        5) echo "gcp" ;;
    esac
}

quick_setup() {
    printf "\033[H\033[J"
    printf "%b──────────────────────────────────────────────────────────%b\n" "${GRAY}" "${NC}"
    printf "  %bGateway Configuration%b\n" "${BOLD}${WHITE}" "${NC}"
    printf "%b──────────────────────────────────────────────────────────%b\n\n" "${GRAY}" "${NC}"

    current_p="${PROVIDER:-cloudflare}"
    if [ -t 0 ]; then
        provider_val=$(select_provider_tui)
    else
        printf "Provider (cloudflare | duckdns | dynu | desec | route53 | gcp) [%s]: " "$current_p"
        read input_provider || true
        provider_val="${input_provider:-$current_p}"
    fi

    printf "Domain / FQDN [%s]: " "${DOMAIN:-}"
    read input_domain || true
    domain_val="${input_domain:-$DOMAIN}"

    printf "API Token / Key [%s]: " "${TOKEN:-}"
    read input_token || true
    token_val="${input_token:-$TOKEN}"

    zone_val=""
    case "$provider_val" in
        cloudflare|route53|gcp|desec)
            prompt_zone="Zone ID"
            [ "$provider_val" = "route53" ] && prompt_zone="AWS Hosted Zone ID"
            [ "$provider_val" = "gcp" ] && prompt_zone="GCP Managed Zone"
            [ "$provider_val" = "desec" ] && prompt_zone="deSEC Domain/Zone (optional)"
            printf "%s [%s]: " "$prompt_zone" "${ZONE_ID:-}"
            read input_zone || true
            zone_val="${input_zone:-$ZONE_ID}"
            ;;
    esac

    project_val=""
    if [ "$provider_val" = "gcp" ]; then
        printf "Google Cloud Project ID [%s]: " "${PROJECT_ID:-}"
        read input_project || true
        project_val="${input_project:-$PROJECT_ID}"
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
DDNS_PROJECT_ID="${project_val}"
DDNS_RECORD_TYPE="${RECORD_TYPE:-A}"
DDNS_INTERVAL="${INTERVAL:-300}"
DDNS_MODE="${MODE:-once}"
EOF
    chmod 600 "$target_config" 2>/dev/null || true

    PROVIDER="$provider_val"
    DOMAIN="$domain_val"
    TOKEN="$token_val"
    ZONE_ID="$zone_val"
    PROJECT_ID="$project_val"

    printf "\n%b✓ Configuration saved to %s%b\n\n" "${GREEN}" "$target_config" "${NC}"
    printf "%bPress Enter to return to menu...%b" "${DIM}" "${NC}"
    read _ || true
}

inspect_status() {
    printf "\033[H\033[J"
    printf "%b──────────────────────────────────────────────────────────%b\n" "${GRAY}" "${NC}"
    printf "  %bTelemetry & System Health%b\n" "${BOLD}${WHITE}" "${NC}"
    printf "%b──────────────────────────────────────────────────────────%b\n\n" "${GRAY}" "${NC}"

    printf "  %bProvider%b      : %b%s%b\n" "${GRAY}" "${NC}" "${WHITE}" "${PROVIDER:-None}" "${NC}"
    printf "  %bDomain%b        : %b%s%b\n" "${GRAY}" "${NC}" "${CYAN}" "${DOMAIN:-Not Configured}" "${NC}"
    printf "  %bRecord Type%b   : %s\n" "${GRAY}" "${NC}" "${RECORD_TYPE:-A}"

    public_ip=$(get_public_ip 2>/dev/null || echo "Fetch Failed")
    printf "  %bPublic IP%b     : %b%s%b\n" "${GRAY}" "${NC}" "${WHITE}" "$public_ip" "${NC}"

    if [ -n "$DOMAIN" ]; then
        cache_f=$(get_cache_file)
        if [ -f "$cache_f" ]; then
            printf "  %bCached State%b  : %b%s%b %b(%s)%b\n" "${GRAY}" "${NC}" "${GREEN}" "$(cat "$cache_f")" "${NC}" "${DIM}" "$cache_f" "${NC}"
        else
            printf "  %bCached State%b  : %bNo cache file yet%b\n" "${GRAY}" "${NC}" "${YELLOW}" "${NC}"
        fi
    fi

    if command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet nodex 2>/dev/null; then
        printf "  %bDaemon Service%b: %b● ACTIVE (systemd)%b\n" "${GRAY}" "${NC}" "${GREEN}" "${NC}"
    else
        printf "  %bDaemon Service%b: %b○ INACTIVE / Manual%b\n" "${GRAY}" "${NC}" "${GRAY}" "${NC}"
    fi

    printf "\n%b──────────────────────────────────────────────────────────%b\n" "${GRAY}" "${NC}"
    printf "%b  Press Enter to return to menu...%b" "${DIM}" "${NC}"
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

# Fast kinetic micro-boot sequence (< 150ms)
micro_boot_intro() {
    [ ! -t 1 ] && return 0
    [ "${NO_INTRO:-0}" -eq 1 ] && return 0

    # Ensure cursor hidden
    printf "\033[?25l"

    # Frame 1: Dim matrix noise dots
    printf "\033[H\033[J"
    printf "%b ·  :   .·.   :··   .·:  :·  ·.%b\n" "${DIM}" "${NC}"
    printf "%b: \\: : / · \\ :   \\ : ·: \\ \\/ /%b\n" "${DIM}" "${NC}"
    printf "%b: .  :: (·) :: :) :: ·|   >  < %b\n" "${DIM}" "${NC}"
    printf "%b:·\\:· \\:·:/ :··· :··· /_/\\_\\\\%b\n" "${DIM}" "${NC}"
    sleep 0.04

    # Frame 2: Half block matrix shades
    printf "\033[H\033[J"
    printf "%b ░  ▒   ▓▒░   ░▒▓   ▓░▒  ▒░  ░▒%b\n" "${GRAY}" "${NC}"
    printf "%b| ▒| ░ / ▒ \\ |   \\ | ░▒| \\ \\/ /%b\n" "${GRAY}" "${NC}"
    printf "%b| ░  || (▒) || ░) || ▒|   >  < %b\n" "${GRAY}" "${NC}"
    printf "%b|░|\\▒| \\░▒▓/ |▒░▓/ |▓░▒| /_/\\_\\\\%b\n" "${GRAY}" "${NC}"
    sleep 0.04

    # Frame 3: Cyan glitch text
    printf "\033[H\033[J"
    printf "%b _  _   _░_   ___   _▒_  __  __%b\n" "${CYAN}" "${NC}"
    printf "%b| \\| | / _ \\ | ▓ \\ | __| \\ \\/ /%b\n" "${CYAN}" "${NC}"
    printf "%b| .  || (_) || |) || _|   > ░< %b\n" "${CYAN}" "${NC}"
    printf "%b|_|\\_| \\___/ |___/ |___| /_/\\_\\\\%b\n" "${CYAN}" "${NC}"
    sleep 0.04
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

    stty -echo -icanon min 1 time 0 2>/dev/null || true
    printf "\033[?25l" # Hide cursor

    micro_boot_intro

    selected=0
    get_remote_info

    local_hash="${BUILD_HASH:-dev}"
    has_update=0
    update_label=""

    if [ "$REMOTE_VERSION" != "$CURRENT_VERSION" ]; then
        has_update=1
        update_label="${REMOTE_VERSION}"
    elif [ "$local_hash" != "dev" ] && [ -n "$REMOTE_HASH" ] && [ "$REMOTE_HASH" != "$local_hash" ]; then
        has_update=1
        update_label="${REMOTE_HASH}"
    fi

    # Pre-fetch public IP once before entering loop so screen redraws don't block
    cached_tui_ip=$(get_public_ip 2>/dev/null || echo "")

    while true; do
        printf "\033[H\033[J" # Clear screen smoothly and reposition

        # Status evaluation
        is_running=0
        if command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet nodex 2>/dev/null; then
            is_running=1
        fi

        # Prepare metadata strings
        prov_text="${PROVIDER:-none}"
        dom_text="${DOMAIN:-}"
        ip_text="${cached_tui_ip:-0.0.0.0}"

        # Truncate long values — pure shell, no subshell forks
        if [ ${#dom_text} -gt 28 ]; then
            dom_text="$(printf '%.25s' "$dom_text")..."
        fi
        if [ ${#ip_text} -gt 15 ]; then
            ip_text="$(printf '%.12s' "$ip_text")..."
        fi

        # --- Header: Logo left, metadata right ---
        # Logo is 4 lines tall; metadata occupies lines 2-3 (vertically centered)
        # Line 1: logo only
        printf "%b _  _   ___   ___   ___  __  __%b\n" "${CYAN}" "${NC}"
        # Line 2: logo + meta line 1
        if [ -n "$dom_text" ]; then
            printf "%b| \\| | / _ \\ |   \\ | __| \\ \\/ /%b    %b%s%b // %b%s%b\n" \
                "${CYAN}" "${NC}" "${WHITE}" "$prov_text" "${NC}" "${CYAN}" "$dom_text" "${NC}"
        else
            printf "%b| \\| | / _ \\ |   \\ | __| \\ \\/ /%b    %b%s%b // %b%s%b\n" \
                "${CYAN}" "${NC}" "${WHITE}" "$prov_text" "${NC}" "${YELLOW}" "unconfigured" "${NC}"
        fi
        # Line 3: logo + meta line 2
        if [ "$is_running" -eq 1 ]; then
            stat_seg="${GREEN}● ACTIVE${NC}"
        else
            stat_seg="${GRAY}○ IDLE${NC}"
        fi
        printf "%b| .  || (_) || |) || _|   >  < %b    %b%s%b %b•%b %b %b•%b v%s\n" \
            "${CYAN}" "${NC}" "${DIM}" "$ip_text" "${NC}" "${GRAY}" "${NC}" "$stat_seg" "${GRAY}" "${NC}" "${CURRENT_VERSION}"
        # Line 4: logo only
        printf "%b|_|\\_| \\___/ |___/ |___| /_/\\_\\\\%b\n" "${CYAN}" "${NC}"

        # Update banner (if available)
        if [ "$has_update" -eq 1 ]; then
            printf "%b  Update available: %s%b\n" "${YELLOW}" "$update_label" "${NC}"
        fi

        # Horizontal divider
        printf "%b──────────────────────────────────────────────────────────%b\n\n" "${GRAY}" "${NC}"

        # Menu items — no subshells, no awk. Direct case lookup per index.
        # ponytail: hardcoded item count (6/7). Upgrade to dynamic IFS-split if menu exceeds ~10 items.
        if [ "$has_update" -eq 1 ]; then
            total_items=7
        else
            total_items=6
        fi

        _tui_label() {
            if [ "$has_update" -eq 1 ]; then
                case "$1" in
                    0) echo "Update NODEX" ;; 1) echo "Sync DNS Pipeline" ;;
                    2) echo "Daemon Service" ;; 3) echo "Gateway Config" ;;
                    4) echo "Telemetry & Logs" ;; 5) echo "Uninstall NODEX" ;;
                    6) echo "Exit Console" ;;
                esac
            else
                case "$1" in
                    0) echo "Sync DNS Pipeline" ;; 1) echo "Daemon Service" ;;
                    2) echo "Gateway Config" ;; 3) echo "Telemetry & Logs" ;;
                    4) echo "Uninstall NODEX" ;; 5) echo "Exit Console" ;;
                esac
            fi
        }

        # Render menu items — zero forks in the hot loop
        i=0
        while [ "$i" -lt "$total_items" ]; do
            t_val=$(_tui_label "$i")
            if [ "$i" -eq "$selected" ]; then
                printf "  %b▎%b %b◆%b  %b%s%b\n" "${CYAN}" "${NC}" "${CYAN}" "${NC}" "${WHITE}" "$t_val" "${NC}"
            else
                printf "    ◇  %b%s%b\n" "${GRAY}" "$t_val" "${NC}"
            fi
            i=$((i + 1))
        done

        # Footer
        printf "\n%b──────────────────────────────────────────────────────────%b\n" "${GRAY}" "${NC}"
        printf "%b  [↑/↓] Navigate  •  [Enter] Execute  •  [q] Quit%b\n" "${DIM}" "${NC}"

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
    # Trap termination signals to clean up gracefully
    trap 'exit 0' INT TERM HUP

    # If parameters passed, run CLI mode headlessly
    if [ "$HAS_ARGS" -eq 1 ] || [ "$MODE" = "daemon" ] || [ -n "${DDNS_TEST_MODE:-}" ]; then
        if [ -n "${DDNS_TEST_MODE:-}" ]; then
            return 0 2>/dev/null || exit 0
        fi
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
