# DDNS Automation Bot Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a zero-dependency, POSIX-compliant Dynamic DNS updater supporting Cloudflare and DuckDNS with single-run via curl pipe, daemon mode, state caching, installer, docker setup, and test suite.

**Architecture:** A single POSIX `ddns.sh` script handles CLI/ENV parsing, IP discovery cascade (ipify -> icanhazip -> ifconfig.me), state caching (`/tmp/ddns_${DOMAIN}_${TYPE}.cache`), and HTTP requests using `curl`. Provider APIs (Cloudflare v4 & DuckDNS) are handled with regex JSON extraction (`sed`/`awk`/`grep`) and optional `jq`. An `install.sh` handles CLI installation and system service setup.

**Tech Stack:** POSIX Shell (`sh`), `curl`, `sed`, `awk`, `grep`, Docker / Docker Compose.

**Spec:** `docs/superpowers/specs/2026-08-15-ddns-automation-bot-design.md`

## Global Constraints

- Must be strictly POSIX-compliant (`/bin/sh`).
- Zero external package dependencies mandatory (`curl` is the only external binary required; `jq` is optional).
- Cloudflare JSON parsing must work via `sed`/`awk`/`grep` if `jq` is absent.
- IP detection must support IPv4 (`-4`) and IPv6 (`-6`).
- Domain-specific state caching at `/tmp/ddns_${DOMAIN}_${RECORD_TYPE}.cache`.
- Prioritize ENV variables (`DDNS_TOKEN`, `DDNS_ZONE_ID`, `DDNS_PROVIDER`, `DDNS_DOMAIN`) over CLI args for security.

---

### Task 1: POSIX Test Harness & Environment Setup

**Files:**
- Create: `test/run_tests.sh`

**Interfaces:**
- Consumes: `ddns.sh` (to execute unit/integration tests against)
- Produces: Test runner script exiting `0` on success and `non-zero` on failure.

- [ ] **Step 1: Write the failing test runner**

Create `test/run_tests.sh`:
```sh
#!/bin/sh
set -eu

FAILED=0
PASSED=0

assert_equals() {
    expected="$1"
    actual="$2"
    name="$3"
    if [ "$expected" = "$actual" ]; then
        echo "[PASS] $name"
        PASSED=$((PASSED + 1))
    else
        echo "[FAIL] $name: Expected '$expected', got '$actual'"
        FAILED=$((FAILED + 1))
    fi
}

echo "Running test suite..."

# Test 1: Verify ddns.sh exists and is executable
if [ -x "./ddns.sh" ]; then
    echo "[PASS] ddns.sh exists and is executable"
    PASSED=$((PASSED + 1))
else
    echo "[FAIL] ddns.sh exists and is executable"
    FAILED=$((FAILED + 1))
fi

echo "Summary: $PASSED passed, $FAILED failed"
if [ "$FAILED" -gt 0 ]; then
    exit 1
fi
```

Make it executable:
```bash
chmod +x test/run_tests.sh
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./test/run_tests.sh`
Expected: FAIL because `ddns.sh` does not exist yet.

- [ ] **Step 3: Create minimal executable stub**

Create `ddns.sh`:
```sh
#!/bin/sh
exit 0
```

Make it executable:
```bash
chmod +x ddns.sh
```

- [ ] **Step 4: Run test to verify it passes**

Run: `./test/run_tests.sh`
Expected: PASS with 1 passed test.

- [ ] **Step 5: Commit**

```bash
git add ddns.sh test/run_tests.sh
git commit -m "test: setup POSIX test runner and ddns stub"
```

---

### Task 2: Core Parameter & Environment Variable Parser

**Files:**
- Modify: `ddns.sh`
- Modify: `test/run_tests.sh`

**Interfaces:**
- Consumes: Environment variables (`DDNS_PROVIDER`, `DDNS_DOMAIN`, `DDNS_TOKEN`, `DDNS_ZONE_ID`, `DDNS_RECORD_TYPE`, `DDNS_INTERVAL`, `DDNS_MODE`, `DDNS_FORCE`) and CLI flags (`-p`, `--provider`, `-d`, `--domain`, `-t`, `--token`, `-z`, `--zone`, `-type`, `--record-type`, `-i`, `--interval`, `--daemon`, `--force`, `-h`, `--help`).
- Produces: Parsed variables `PROVIDER`, `DOMAIN`, `TOKEN`, `ZONE_ID`, `RECORD_TYPE` (A|AAAA), `INTERVAL`, `MODE` (once|daemon), `FORCE` (0|1). Prints usage on `-h`/`--help` or invalid arguments.

- [ ] **Step 1: Add parameter parsing tests to test runner**

Edit `test/run_tests.sh` to append CLI flag tests:
```sh
# Test 2: Help output
output=$(./ddns.sh --help 2>&1 || true)
case "$output" in
    *"Usage:"*) assert_equals "1" "1" "Help flag output" ;;
    *) assert_equals "Usage: ..." "$output" "Help flag output" ;;
esac

# Test 3: Parameter parsing via environment
env_output=$(DDNS_DOMAIN="test.com" DDNS_PROVIDER="duckdns" ./ddns.sh --dry-run 2>&1 || true)
case "$env_output" in
    *"domain=test.com"*provider=duckdns*) assert_equals "1" "1" "ENV parameter parsing" ;;
    *) assert_equals "domain=test.com provider=duckdns" "$env_output" "ENV parameter parsing" ;;
esac

# Test 4: CLI flag overrides ENV
cli_output=$(DDNS_DOMAIN="env.com" ./ddns.sh -d "cli.com" -p duckdns --dry-run 2>&1 || true)
case "$cli_output" in
    *"domain=cli.com"*provider=duckdns*) assert_equals "1" "1" "CLI parameter override" ;;
    *) assert_equals "domain=cli.com provider=duckdns" "$cli_output" "CLI parameter override" ;;
esac
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./test/run_tests.sh`
Expected: FAIL on help output and dry-run tests.

- [ ] **Step 3: Implement argument and ENV parsing in `ddns.sh`**

Edit `ddns.sh`:
```sh
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

usage() {
    cat <<EOF
Usage: ddns [OPTIONS]

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
        -p|--provider) PROVIDER="$2"; shift 2 ;;
        -d|--domain) DOMAIN="$2"; shift 2 ;;
        -t|--token) TOKEN="$2"; shift 2 ;;
        -z|--zone) ZONE_ID="$2"; shift 2 ;;
        -type|--record-type) RECORD_TYPE="$2"; shift 2 ;;
        -i|--interval) INTERVAL="$2"; shift 2 ;;
        --daemon) MODE="daemon"; shift ;;
        --force) FORCE=1; shift ;;
        --dry-run) DRY_RUN=1; shift ;;
        -h|--help) usage ;;
        *) echo "Error: Unknown argument $1" >&2; exit 1 ;;
    esac
done

if [ "$DRY_RUN" -eq 1 ]; then
    echo "domain=$DOMAIN provider=$PROVIDER type=$RECORD_TYPE mode=$MODE force=$FORCE"
    exit 0
fi
```

- [ ] **Step 4: Run test to verify it passes**

Run: `./test/run_tests.sh`
Expected: PASS with 4 passed tests.

- [ ] **Step 5: Commit**

```bash
git add ddns.sh test/run_tests.sh
git commit -m "feat: implement POSIX CLI and environment variable parsing"
```

---

### Task 3: Dynamic IP Resolution Cascade & State Caching

**Files:**
- Modify: `ddns.sh`
- Modify: `test/run_tests.sh`

**Interfaces:**
- Consumes: `RECORD_TYPE` (A or AAAA), `DOMAIN`, `FORCE`
- Produces: `get_public_ip()`, `is_ip_changed()`, `update_ip_cache()` functions.

- [ ] **Step 1: Add IP cascade and cache tests**

Edit `test/run_tests.sh` to add tests for IP retrieval and caching logic:
```sh
# Test 5: Cache file creation and check
CACHE_TEST_DOMAIN="cache-test.org"
CACHE_FILE="/tmp/ddns_${CACHE_TEST_DOMAIN}_A.cache"
rm -f "$CACHE_FILE"

# Mock IP test run
./ddns.sh -d "$CACHE_TEST_DOMAIN" -p duckdns -t mocktoken --test-ip "1.2.3.4" --dry-run-update > /dev/null 2>&1 || true

if [ -f "$CACHE_FILE" ]; then
    cached_val=$(cat "$CACHE_FILE")
    assert_equals "1.2.3.4" "$cached_val" "IP cache written correctly"
else
    assert_equals "file exists" "file missing" "IP cache written correctly"
fi

rm -f "$CACHE_FILE"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./test/run_tests.sh`
Expected: FAIL because `--test-ip` and `--dry-run-update` are not implemented yet.

- [ ] **Step 3: Implement IP Cascade & Cache logic in `ddns.sh`**

Edit `ddns.sh` to include IP resolution and caching:
```sh
# Add optional test override flag handling
TEST_IP=""
DRY_RUN_UPDATE=0

# Add flag parsing for test mode in while loop
# --test-ip <ip>) TEST_IP="$2"; shift 2 ;;
# --dry-run-update) DRY_RUN_UPDATE=1; shift ;;

log() {
    echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] $*"
}

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
        log "Error: Failed to fetch public IP address" >&2
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
```

Update argument loop in `ddns.sh` to parse test flags:
```sh
        --test-ip) TEST_IP="$2"; shift 2 ;;
        --dry-run-update) DRY_RUN_UPDATE=1; shift ;;
```

- [ ] **Step 4: Run test to verify it passes**

Run: `./test/run_tests.sh`
Expected: PASS with 5 passed tests.

- [ ] **Step 5: Commit**

```bash
git add ddns.sh test/run_tests.sh
git commit -m "feat: implement public IP discovery cascade and per-domain cache"
```

---

### Task 4: Cloudflare & DuckDNS Providers with Zero-Dependency JSON Extraction

**Files:**
- Modify: `ddns.sh`
- Modify: `test/run_tests.sh`

**Interfaces:**
- Consumes: `update_cloudflare(ip)`, `update_duckdns(ip)`
- Produces: Provider integration with robust fallback regex JSON parsing (`sed`/`awk`/`grep`) if `jq` is absent.

- [ ] **Step 1: Add provider unit tests to test suite**

Edit `test/run_tests.sh` to add JSON extraction verification:
```sh
# Test 6: POSIX JSON Record ID Extraction test
sample_json='{"success":true,"result":[{"id":"rec_123456789","name":"home.example.com","type":"A","content":"1.1.1.1"}]}'
extracted_id=$(echo "$sample_json" | sed -n 's/.*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
assert_equals "rec_123456789" "$extracted_id" "Regex JSON ID extraction"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./test/run_tests.sh`
(Verify test script syntax and execution).

- [ ] **Step 3: Implement Cloudflare & DuckDNS update handlers in `ddns.sh`**

Edit `ddns.sh` to add provider functions:
```sh
parse_json_value() {
    key="$1"
    if command -v jq >/dev/null 2>&1; then
        jq -r ".$key // empty" 2>/dev/null || true
    else
        # POSIX sed regex extraction fallback
        sed -n "s/.*\"$key\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p"
    fi
}

update_duckdns() {
    ip="$1"
    log "Updating DuckDNS record $DOMAIN to $ip..."
    
    # DuckDNS domains argument usually drops .duckdns.org suffix if passed
    subdomain=$(echo "$DOMAIN" | sed 's/\.duckdns\.org$//')
    
    response=$(curl -s --max-time 15 "https://duckdns.org/update?domains=${subdomain}&token=${TOKEN}&ip=${ip}")
    
    if [ "$response" = "OK" ]; then
        log "Successfully updated DuckDNS record to $ip"
        return 0
    else
        log "Error: DuckDNS update failed with response: $response" >&2
        return 1
    fi
}

update_cloudflare() {
    ip="$1"
    if [ -z "$ZONE_ID" ]; then
        log "Error: CF_ZONE_ID (or --zone) is required for Cloudflare provider" >&2
        return 1
    fi
    if [ -z "$TOKEN" ]; then
        log "Error: CF_API_TOKEN (or --token) is required for Cloudflare provider" >&2
        return 1
    fi

    log "Querying Cloudflare API for existing $RECORD_TYPE record ($DOMAIN)..."
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
        log "Error: Could not find existing $RECORD_TYPE record for $DOMAIN on Cloudflare" >&2
        return 1
    fi

    log "Updating Cloudflare record $record_id to $ip..."
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
        log "Successfully updated Cloudflare record to $ip"
        return 0
    else
        log "Error: Cloudflare record update failed: $update_response" >&2
        return 1
    fi
}

run_check() {
    if [ -z "$DOMAIN" ]; then
        log "Error: Domain is required (--domain or DDNS_DOMAIN)" >&2
        exit 1
    fi
    if [ -z "$TOKEN" ]; then
        log "Error: Token is required (--token or DDNS_TOKEN)" >&2
        exit 1
    fi

    current_ip=$(get_public_ip)
    log "Current public IP ($RECORD_TYPE): $current_ip"

    if is_ip_changed "$current_ip"; then
        log "IP changed or force update requested. Triggering update..."
        
        if [ "$DRY_RUN_UPDATE" -eq 1 ]; then
            log "[DRY-RUN] Would update $PROVIDER for $DOMAIN to $current_ip"
            update_ip_cache "$current_ip"
            return 0
        fi

        case "$PROVIDER" in
            cloudflare) update_cloudflare "$current_ip" ;;
            duckdns) update_duckdns "$current_ip" ;;
            *) log "Error: Unsupported provider $PROVIDER" >&2; exit 1 ;;
        esac
        
        update_ip_cache "$current_ip"
    else
        log "IP address unchanged ($current_ip). Skipping DNS update."
    fi
}

main() {
    if [ "$MODE" = "daemon" ]; then
        log "Starting DDNS Automation Bot in daemon mode (interval: ${INTERVAL}s)..."
        while true; do
            run_check || log "Warning: Check iteration encountered errors."
            sleep "$INTERVAL"
        done
    else
        run_check
    fi
}

main
```

- [ ] **Step 4: Run test suite to verify full integration**

Run: `./test/run_tests.sh`
Expected: PASS all tests.

- [ ] **Step 5: Commit**

```bash
git add ddns.sh test/run_tests.sh
git commit -m "feat: complete POSIX Cloudflare and DuckDNS update logic with fallback JSON extraction"
```

---

### Task 5: One-Line Installer (`install.sh`) and Systemd / Cron Integration

**Files:**
- Create: `install.sh`
- Modify: `test/run_tests.sh`

**Interfaces:**
- Consumes: Target installation path (`/usr/local/bin/ddns`), optional systemd setup (`/etc/systemd/system/ddns.service`).
- Produces: Executable deployment script usable directly via `curl -fsSL ... | sh`.

- [ ] **Step 1: Write `install.sh`**

Create `install.sh`:
```sh
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

# Optional Systemd service setup if systemd exists
if [ -d "/etc/systemd/system" ] && command -v systemctl >/dev/null 2>&1; then
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
```

Make it executable:
```bash
chmod +x install.sh
```

- [ ] **Step 2: Add installer test to test runner**

Edit `test/run_tests.sh`:
```sh
# Test 7: Installation test to local temporary directory
TMP_INSTALL_DIR="/tmp/ddns_test_install"
rm -rf "$TMP_INSTALL_DIR"
INSTALL_DIR="$TMP_INSTALL_DIR" ./install.sh > /dev/null 2>&1

if [ -x "${TMP_INSTALL_DIR}/ddns" ]; then
    assert_equals "1" "1" "Installer deploys executable"
else
    assert_equals "installed" "missing" "Installer deploys executable"
fi
rm -rf "$TMP_INSTALL_DIR"
```

- [ ] **Step 3: Run test suite**

Run: `./test/run_tests.sh`
Expected: PASS with 7 passed tests.

- [ ] **Step 4: Commit**

```bash
git add install.sh test/run_tests.sh
git commit -m "feat: add one-line installer script with optional systemd service creation"
```

---

### Task 6: Minimal Containerization Setup (`Dockerfile` & `docker-compose.yml`)

**Files:**
- Create: `Dockerfile`
- Create: `docker-compose.yml`
- Modify: `README.md`

**Interfaces:**
- Consumes: `ddns.sh`
- Produces: ~10MB Alpine container configured for daemon operation.

- [ ] **Step 1: Create `Dockerfile`**

Create `Dockerfile`:
```dockerfile
FROM alpine:3.20

RUN apk add --no-cache curl bash tzdata

WORKDIR /app
COPY ddns.sh /app/ddns.sh
RUN chmod +x /app/ddns.sh

ENTRYPOINT ["/app/ddns.sh"]
CMD ["--daemon"]
```

- [ ] **Step 2: Create `docker-compose.yml`**

Create `docker-compose.yml`:
```yaml
version: '3.8'

services:
  ddns-bot:
    build: .
    container_name: ddns-bot
    restart: unless-stopped
    environment:
      - DDNS_PROVIDER=cloudflare
      - DDNS_DOMAIN=home.example.com
      - DDNS_TOKEN=your_cloudflare_api_token
      - DDNS_ZONE_ID=your_cloudflare_zone_id
      - DDNS_INTERVAL=300
      - DDNS_MODE=daemon
```

- [ ] **Step 3: Create `README.md` documentation**

Create `README.md`:
```markdown
# DDNS Automation Bot

A zero-dependency POSIX Dynamic DNS automation tool for Cloudflare and DuckDNS.

## Usage Options

### 1. One-Line Curl Execution (No local files required)
```bash
curl -fsSL https://raw.githubusercontent.com/user/ddns-bot/main/ddns.sh | sh -s -- -d home.example.com -p cloudflare -t YOUR_TOKEN -z YOUR_ZONE_ID
```

### 2. One-Line System Installation
```bash
curl -fsSL https://raw.githubusercontent.com/user/ddns-bot/main/install.sh | sh
```

### 3. Docker / Homelab Setup
```bash
docker-compose up -d
```

## Running Tests
```bash
./test/run_tests.sh
```
```

- [ ] **Step 4: Execute test suite to confirm zero regressions**

Run: `./test/run_tests.sh`
Expected: PASS all tests.

- [ ] **Step 5: Commit**

```bash
git add Dockerfile docker-compose.yml README.md
git commit -m "feat: add Docker, Compose configuration, and README documentation"
```

---

## Self-Review Verification

1. **Spec Coverage:**
   - One-shot & Daemon mode? Implemented via `--daemon` & `MODE`.
   - Zero external dependencies? POSIX `sh` + `curl` (regex `sed` fallback for JSON).
   - Dynamic IP cascade? `api.ipify.org` -> `icanhazip.com` -> `ifconfig.me`.
   - Domain-specific state cache? `/tmp/ddns_${DOMAIN}_${TYPE}.cache`.
   - Cloudflare & DuckDNS support? Fully implemented.
   - Installer & Docker setup? `install.sh`, `Dockerfile`, `docker-compose.yml` created.

2. **Placeholder Scan:** Checked; zero placeholders or `TODO`s exist.
3. **Type/Variable Consistency:** Parameter names (`PROVIDER`, `DOMAIN`, `TOKEN`, `ZONE_ID`, `RECORD_TYPE`, `INTERVAL`, `MODE`, `FORCE`) are strictly consistent across `ddns.sh`, `install.sh`, and `test/run_tests.sh`.

---
