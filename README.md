# NODEX 🌐

> Zero-dependency, ultra-lightweight Dynamic DNS updater for Cloudflare and DuckDNS. Supports one-line curl execution, IP discovery cascade, multi-domain state caching, background daemon mode, plus out-of-the-box systemd and Docker setups.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![POSIX Compliant](https://img.shields.io/badge/shell-POSIX%20compliant-blue.svg)](https://pubs.opengroup.org/onlinepubs/9699919799/)
[![Docker Image Size](https://img.shields.io/badge/docker%20image-~10MB-brightgreen.svg)]()

---

## ⚡ Highlights

- **Zero Dependencies**: Pure POSIX `/bin/sh` implementation utilizing standard Unix utilities (`sed`, `awk`, `grep`) and `curl`.
- **Direct Curl Pipe**: Run on-demand or in ephemeral environments without local repository cloning.
- **Dynamic IP Fallback Cascade**: High-availability IP discovery across `api.ipify.org`, `icanhazip.com`, and `ifconfig.me`. Supports both IPv4 (`-4`) and IPv6 (`-6`).
- **Domain State Caching**: Stores IP state locally (`/tmp/ddns_${DOMAIN}_${TYPE}.cache`) to minimize API requests and prevent rate-limiting.
- **Multiple Providers**: Built-in support for Cloudflare (v4 API with regex JSON extraction fallback) and DuckDNS.
- **Versatile Deployments**: Supports CLI one-shot, continuous daemon loop, systemd service, and minimal Alpine Docker containers.

---

## 🚀 Quick Start

### 1. Direct One-Line Run (Ephemeral / Cron)

Execute dynamic updates without storing any scripts locally:

```bash
# Cloudflare (IPv4)
curl -fsSL https://raw.githubusercontent.com/marhaburrisqi/nodex/main/ddns.sh | sh -s -- \
  --provider cloudflare \
  --domain home.example.com \
  --token YOUR_CLOUDFLARE_API_TOKEN \
  --zone YOUR_CLOUDFLARE_ZONE_ID

# DuckDNS
curl -fsSL https://raw.githubusercontent.com/marhaburrisqi/nodex/main/ddns.sh | sh -s -- \
  --provider duckdns \
  --domain mydomain.duckdns.org \
  --token YOUR_DUCKDNS_TOKEN
```

### 2. Global Installation & Systemd Service

Install the executable binary to `/usr/local/bin/ddns` and manage it as a background service:

```bash
# Step 1: Run the one-line installer
curl -fsSL https://raw.githubusercontent.com/marhaburrisqi/nodex/main/install.sh | sh

# Step 2: Configure credentials
sudo tee /etc/default/ddns << 'EOF'
DDNS_PROVIDER="cloudflare"
DDNS_DOMAIN="home.example.com"
DDNS_TOKEN="your_cloudflare_api_token_here"
DDNS_ZONE_ID="your_cloudflare_zone_id_here"
DDNS_RECORD_TYPE="A"
DDNS_INTERVAL="300"
DDNS_MODE="daemon"
EOF

# Step 3: Secure credentials file
sudo chmod 600 /etc/default/ddns

# Step 4: Enable and start systemd daemon
sudo systemctl daemon-reload
sudo systemctl enable --now ddns

# Step 5: Check service status and live logs
sudo systemctl status ddns
sudo journalctl -u ddns -f
```

### 3. Docker Compose (Homelab)

Deploy an isolated container using `docker-compose.yml`:

```yaml
version: '3.8'

services:
  nodex:
    build: .
    container_name: nodex
    restart: unless-stopped
    environment:
      - DDNS_PROVIDER=cloudflare
      - DDNS_DOMAIN=home.example.com
      - DDNS_TOKEN=your_cloudflare_api_token_here
      - DDNS_ZONE_ID=your_cloudflare_zone_id_here
      - DDNS_RECORD_TYPE=A
      - DDNS_INTERVAL=300
      - DDNS_MODE=daemon
```

Start the container in detached mode:

```bash
docker-compose up -d
```

---

## ⚙️ Configuration & CLI Flags

Parameters can be configured via command-line arguments or environment variables (environment variables are recommended for security):

| Flag | Environment Variable | Default | Description |
| --- | --- | --- | --- |
| `-p, --provider` | `DDNS_PROVIDER` | `cloudflare` | DNS Provider (`cloudflare` or `duckdns`) |
| `-d, --domain` | `DDNS_DOMAIN` | *(Required)* | Fully qualified domain name to update |
| `-t, --token` | `DDNS_TOKEN` | *(Required)* | API token for authentication |
| `-z, --zone` | `DDNS_ZONE_ID` | - | Cloudflare Zone ID (required for Cloudflare) |
| `-type, --record-type` | `DDNS_RECORD_TYPE` | `A` | DNS record type (`A` for IPv4, `AAAA` for IPv6) |
| `-i, --interval` | `DDNS_INTERVAL` | `300` | Polling interval in seconds (daemon mode) |
| `--daemon` | `DDNS_MODE=daemon` | `once` | Run continuously in background loop |
| `--force` | `DDNS_FORCE=1` | `0` | Bypass local IP cache and force record update |
| `--dry-run` | - | - | Display parsed parameters and exit |
| `-h, --help` | - | - | Show usage guide |

---

## 🛠️ Troubleshooting & Common Fixes

### 1. Cloudflare: "Could not find existing A/AAAA record"

* **Cause**: Cloudflare requires an existing DNS record before it can be updated via the API.
* **Fix**: Log into the Cloudflare Dashboard, navigate to your DNS management page, and manually create an initial dummy `A` or `AAAA` record for your target domain (e.g., pointing to `1.1.1.1` or `::1`).

### 2. Cloudflare: "Authentication Error" or HTTP 403

* **Cause**: The API Token does not have sufficient permissions.
* **Fix**: When creating the token on Cloudflare, select **Create Custom Token** with the permission:
  * `Zone` -> `DNS` -> `Edit`
  * Set **Zone Resources** to `Include` -> `Specific zone` -> Select your domain.

### 3. IP Cache Not Updating After Network Switch

* **Cause**: Nodex reads `/tmp/ddns_${DOMAIN}_${TYPE}.cache` to avoid duplicate API requests. If your IP changed but the cache was not cleared, updates may be delayed.
* **Fix**: Force an immediate update using the `--force` flag or delete the cache file manually:
```bash
rm -f /tmp/ddns_*.cache
```

### 4. Permission Denied on `/usr/local/bin/ddns`

* **Cause**: Missing root/sudo privileges when installing globally or running systemd.
* **Fix**: Make sure to run `sudo chmod +x /usr/local/bin/ddns` and execute installer commands with administrative access.

---

## 🧪 Testing Suite

Validate argument parsing, mock cascades, and state caching locally:

```bash
chmod +x test/run_tests.sh
./test/run_tests.sh
```

---

## 📄 License

Distributed under the [MIT License](LICENSE).
