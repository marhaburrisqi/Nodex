# NODEX 🌐

> Zero-dependency, ultra-lightweight Dynamic DNS (DDNS) automation tool and interactive router-style TUI supporting **Cloudflare, DuckDNS, Dynu, deSEC, AWS Route 53, and Google Cloud DNS**. Designed for POSIX shells (`/bin/sh`), Linux, Android (Termux), macOS, and Windows (CMD/PowerShell).

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![POSIX Compliant](https://img.shields.io/badge/shell-POSIX%20compliant-blue.svg)](https://pubs.opengroup.org/onlinepubs/9699919799/)
[![Docker Image Size](https://img.shields.io/badge/docker%20image-~10MB-brightgreen.svg)]()

---

## ⚡ Key Features

- **Dual Mode**: Interactive arrow-key Navigable TUI menu (Router Gateway style) or Headless CLI daemon for automated environments.
- **Zero External Dependencies**: Pure POSIX shell implementation using standard Unix tools (`sed`, `awk`, `grep`, `curl`). Fallback regex JSON extraction for Cloudflare when `jq` is not available.
- **Sudo-Free User-Space Installation**: Auto-detects writable PATH directories (`~/.local/bin`, Termux `$PREFIX/bin`, `/usr/local/bin`).
- **Cross-Platform**: Full support for Linux, Termux (Android), macOS, and Windows (PowerShell/CMD).
- **Public IP Discovery Cascade**: High-availability IP retrieval across `api.ipify.org` → `icanhazip.com` → `ifconfig.me` supporting IPv4 (`A`) and IPv6 (`AAAA`).
- **Smart State Caching**: Local caching at `/tmp/ddns_${domain}_${RECORD_TYPE}.cache` to prevent redundant API calls and rate limiting.
- **Typo Tolerant**: Auto-aliased `modex` command wrapper.

---

## 🚀 Quick Start & Installation

### Option 1: Automatic Installer (Linux / macOS / Termux)

Run the non-root auto-installer:

```bash
curl -fsSL https://raw.githubusercontent.com/marhaburrisqi/Nodex/main/install.sh | sh
```

Launch the interactive Gateway TUI:

```bash
nodex
```

*(Note: `modex` also works as a built-in alias)*

---

### Option 2: Windows Installer (PowerShell)

Open PowerShell and execute:

```powershell
iwr -useb https://raw.githubusercontent.com/marhaburrisqi/Nodex/main/install.ps1 | iex
```

After installation, run `nodex` in CMD or PowerShell.

---

### Option 3: Direct One-Line Execution (No Installation / Cron)

Execute on-demand without installing:

```bash
# Cloudflare (IPv4)
curl -fsSL https://raw.githubusercontent.com/marhaburrisqi/Nodex/main/ddns.sh | sh -s -- \
  --provider cloudflare \
  --domain home.example.com \
  --token YOUR_CLOUDFLARE_API_TOKEN \
  --zone YOUR_CLOUDFLARE_ZONE_ID

# DuckDNS
curl -fsSL https://raw.githubusercontent.com/marhaburrisqi/Nodex/main/ddns.sh | sh -s -- \
  --provider duckdns \
  --domain mydomain.duckdns.org \
  --token YOUR_DUCKDNS_TOKEN
```

---

## 🖥️ Interactive TUI Gateway

Running `nodex` without arguments in an interactive terminal opens the TUI Router interface:

```text
 _  _   ___   ___   ___  __  __
| \| | / _ \ |   \ | __| \ \/ /    cloudflare // home.example.com
| .  || (_) || |) || _|   >  <     125.166.118.234 • ● ACTIVE • v1.3.2
|_|\_| \___/ |___/ |___| /_/\_\
──────────────────────────────────────────────────────────

  ▎ ◆  Sync DNS Pipeline
    ◇  Daemon Service
    ◇  Gateway Config
    ◇  Telemetry & Logs
    ◇  Uninstall NODEX
    ◇  Exit Console

──────────────────────────────────────────────────────────
  [↑/↓] Navigate  •  [Enter] Execute  •  [q] Quit
```

---

## ⚙️ CLI Reference & Flags

```bash
nodex [OPTIONS]
```

| Option | Environment Variable | Default | Description |
| :--- | :--- | :--- | :--- |
| `-p, --provider <name>` | `DDNS_PROVIDER` | `cloudflare` | DNS Provider (`cloudflare`, `duckdns`, `dynu`, `desec`, `route53`, `gcp`) |
| `-d, --domain <fqdn>` | `DDNS_DOMAIN` | *(Required)* | Target domain / hostname to update |
| `-t, --token <token>` | `DDNS_TOKEN` | *(Required)* | API token (Bearer / Token / API Key) |
| `-z, --zone <zone_id>` | `DDNS_ZONE_ID` | - | Zone ID / Hosted Zone ID / Managed Zone (Cloudflare, Route 53, GCP, deSEC) |
| `--project-id <id>` | `DDNS_PROJECT_ID` | - | Google Cloud Project ID (Required for GCP) |
| `-type, --record-type` | `DDNS_RECORD_TYPE` | `A` | DNS record type (`A` for IPv4, `AAAA` for IPv6) |
| `-i, --interval <sec>` | `DDNS_INTERVAL` | `300` | Polling interval in seconds for daemon mode |
| `--daemon` | `DDNS_MODE=daemon` | `once` | Run continuously in background loop |
| `--force` | `DDNS_FORCE=1` | `0` | Ignore local cache and force API update |
| `--dry-run` | - | - | Display parsed parameters and exit |
| `-u, --update` | - | - | Update NODEX to the latest version |
| `-h, --help` | - | - | Show usage guide |

---

## 🔒 Configuration Files & Environment Variables

Credentials can be loaded automatically from configuration files or environment variables:

1. **System Config**: `/etc/default/nodex`
2. **User Config**: `~/.config/nodex/config`

### Example Config File (`~/.config/nodex/config`)

```sh
DDNS_PROVIDER="cloudflare"
DDNS_DOMAIN="home.example.com"
DDNS_TOKEN="your_api_token_here"
DDNS_ZONE_ID="your_zone_id_here"
DDNS_RECORD_TYPE="A"
DDNS_INTERVAL="300"
DDNS_MODE="once"
```

---

## 🐳 Docker Setup

### Docker Run

```bash
docker run -d \
  --name nodex \
  --restart unless-stopped \
  -e DDNS_PROVIDER=cloudflare \
  -e DDNS_DOMAIN=home.example.com \
  -e DDNS_TOKEN=your_token \
  -e DDNS_ZONE_ID=your_zone_id \
  -e DDNS_MODE=daemon \
  marhaburrisqi/nodex:latest
```

### Docker Compose (`docker-compose.yml`)

```yaml
version: '3.8'

services:
  nodex:
    image: marhaburrisqi/nodex:latest
    container_name: nodex
    restart: unless-stopped
    environment:
      - DDNS_PROVIDER=cloudflare
      - DDNS_DOMAIN=home.example.com
      - DDNS_TOKEN=your_cloudflare_api_token
      - DDNS_ZONE_ID=your_cloudflare_zone_id
      - DDNS_RECORD_TYPE=A
      - DDNS_INTERVAL=300
      - DDNS_MODE=daemon
```

---

## 🧪 Running Tests

Execute the built-in POSIX test suite:

```bash
chmod +x test/run_tests.sh
./test/run_tests.sh
```

---

## 📄 License

Distributed under the [MIT License](LICENSE).
