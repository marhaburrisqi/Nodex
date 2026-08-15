# DDNS Automation Bot - Detailed Design Specification

## Overview
A zero-dependency Dynamic DNS automation tool and installer designed for quick multi-provider IP updates via direct `curl` pipe execution (`curl -fsSL ... | sh`), standalone CLI installation, or Docker container.

---

## 1. Execution & One-Line Usage (`curl`)

### Direct Curl Pipe Execution (No local clone needed)
Users can run single updates or installation directly over `curl`:
```bash
# Direct run (One-shot check & update)
curl -fsSL https://raw.githubusercontent.com/user/ddns-bot/main/ddns.sh | sh -s -- --domain home.example.com --provider cloudflare --token YOUR_TOKEN --zone YOUR_ZONE_ID

# Direct daemon run
curl -fsSL https://raw.githubusercontent.com/user/ddns-bot/main/ddns.sh | sh -s -- --daemon --interval 300

# One-line System Installation (installs `ddns` binary to /usr/local/bin and sets up cron/systemd service)
curl -fsSL https://raw.githubusercontent.com/user/ddns-bot/main/install.sh | sh
```

---

## 2. Supported Providers & Capabilities
- **Cloudflare**: Updates A / AAAA records using Cloudflare API v4 (`/zones/{zone_id}/dns_records`).
- **DuckDNS**: Updates dynamic IP using DuckDNS HTTP GET API.
- **Extensibility**: Clean modular functions to add custom HTTP APIs / providers.

---

## 3. Dynamic IP Resolution & State Cache
- **IP Detection Service Cascade**:
  1. `https://api.ipify.org`
  2. `https://icanhazip.com`
  3. `https://ifconfig.me/ip`
- **State Caching**: Saves resolved IP to `/tmp/ddns_last_ip` (or environment cache dir). API call is skipped if public IP has not changed since last check.

---

## 4. CLI Interface & Flags
The runner/script supports flexible input via CLI parameters and environment variables:

```
Usage: ddns [OPTIONS]

Options:
  -p, --provider <name>   DNS Provider (cloudflare | duckdns) [default: cloudflare]
  -d, --domain <fqdn>     Domain / Hostname to update (e.g., home.example.com)
  -t, --token <token>     API token (Cloudflare API token or DuckDNS token)
  -z, --zone <zone_id>    Cloudflare Zone ID (required for Cloudflare)
  -i, --interval <sec>    Check interval for daemon mode in seconds [default: 300]
  --daemon                Run continuously in daemon mode
  --force                 Ignore IP cache and force update DNS record
  -h, --help              Show usage guide
```

---

## 5. Deployment Options

1. **Curl Direct Execution**: Run on demand, via crontab, or cloud init scripts without storing local repos.
2. **Global CLI Installer (`install.sh`)**: Installs executable `ddns` to `/usr/local/bin/ddns` and configures automatic system cron/systemd daemon.
3. **Docker Container**:
   - `Dockerfile` (~10MB Alpine image).
   - `docker-compose.yml` for homelabs (`image`, environment configuration).

---

## 6. Self-Checking Verification Suite
- `test/run_tests.sh`:
  - Validates argument parsing & defaults.
  - Tests CLI help output & error codes on missing parameters.
  - Mocks IP detection and state cache hit/miss logic.
