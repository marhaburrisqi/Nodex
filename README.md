# DDNS Automation Bot

A zero-dependency POSIX Dynamic DNS automation tool supporting Cloudflare and DuckDNS.

## Features
- **Zero External Dependencies**: Standard POSIX shell script using `curl` and native `sed`/`awk`/`grep` JSON fallback parsing (uses `jq` if present).
- **Public IP Resolution Cascade**: Fallback discovery across `api.ipify.org`, `icanhazip.com`, and `ifconfig.me`. Supports IPv4 (`A`) and IPv6 (`AAAA`).
- **Domain State Caching**: Caches IP per domain/record type to avoid wasteful API updates.
- **Flexible Execution**: One-shot execution, daemon mode, single `curl | sh` invocation, and Docker support.

## Usage Options

### 1. One-Line Direct Curl Execution
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

## CLI Options

```
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
  -h, --help              Show help message
```

## Environment Variables

- `DDNS_PROVIDER`
- `DDNS_DOMAIN`
- `DDNS_TOKEN`
- `DDNS_ZONE_ID`
- `DDNS_RECORD_TYPE`
- `DDNS_INTERVAL`
- `DDNS_MODE`
- `DDNS_FORCE`

## Running Tests
```bash
./test/run_tests.sh
```
