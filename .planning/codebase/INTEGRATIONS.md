# External Integrations

**Analysis Date:** 2026-02-09

## APIs & External Services

**Tailscale VPN:**
- Purpose: Secure remote access to all homelab services via WireGuard mesh network
- SDK/Client: `unstable.tailscale` package
- Auth: Shared authkey (`tailscale_authkey` from `secrets/shared.yaml`)
- Config files:
  - `modules/servers/tailscale.nix` - Auto-authentication on boot
  - `modules/gateway/caddy.nix` - Caddy plugin for auto HTTPS via Tailscale certificates
- Behavior: All hosts auto-connect on boot using shared key, domain = `shad-bangus.ts.net`
- Services accessible via Tailscale MagicDNS with valid Let's Encrypt certificates

**NordVPN:**
- Purpose: Anonymized torrent client via WireGuard tunnel
- Client: `wgnord` package with `modules/nordvpn/` module
- Auth: Access token file (path configured per-host in nordvpn module)
- Behavior: Creates isolated network namespace (`/var/run/netns/wgnord`) for qBittorrent
- qBittorrent runs exclusively in this namespace for IP anonymization
- Network bridge: veth pair connecting namespace to host (configurable subnet)

**Frigate NVR (Camera System):**
- Purpose: Security camera recording and AI object detection
- Config: `modules/automation/frigate.nix`
- Auth: Camera RTSP credentials stored in SOPS (`frigate_cam_user`, `frigate_cam_pass`)
- Credentials injected via environment variables: `{FRIGATE_CAM_USER}`, `{FRIGATE_CAM_PASS}`
- Cameras: TP-Link Tapo C120 RTSP cameras (driveway, front_door, garage, side_gate, living_room, basement)
- Ports: 8554 (RTSP restream), 8555 (WebRTC), port 80 (nginx web UI)
- Storage: `/mnt/cameras` on ZFS backup pool with 5-day motion retention
- Integrations:
  - MQTT to Mosquitto (localhost:1883) for Home Assistant connectivity
  - prometheus-frigate-exporter metrics on port 9710

**Home Assistant:**
- Purpose: Home automation hub
- Config: `modules/automation/home-assistant.nix`
- Components: MQTT integration, generic camera drivers, FFmpeg transcoding
- MQTT Broker: Mosquitto (localhost:1883) for Frigate data ingestion
- Storage: SQLite database at `/var/lib/hass` with 30-day retention
- Web UI: Port 8123, accessible via Caddy reverse proxy at `hass.vofi`
- Trusted proxies configured for Caddy reverse proxy (192.168.68.0/24)
- Data directories: Custom components, www assets in `/var/lib/hass/`

**Mosquitto MQTT Broker:**
- Purpose: Message broker for Frigate <-> Home Assistant communication
- Config: `modules/automation/home-assistant.nix`
- Listener: 127.0.0.1:1883 (local-only, no authentication)
- Topic pattern: Read-write all topics (permissive for internal network)
- Behavior: Started alongside Home Assistant

## Data Storage

**Databases:**
- SQLite (Home Assistant) - `/var/lib/hass/` with 30-day state retention
- Frigate SQLite - `/var/lib/frigate/frigate.db` for object detection history

**File Storage:**
- ZFS pools (ser8):
  - Main pool: Stores media library (Jellyfin content)
  - Backup pool: Stores camera recordings at `/mnt/cameras`
  - ARC max configured: 8GB
  - Auto-import: Backup pool on boot
- MergerFS (ser8): Unified view across multiple ZFS datasets for media organization
- Storage paths:
  - `/mnt/media/downloads/` - qBittorrent and SABnzbd downloads
  - `/mnt/media/downloads/complete/` - Completed downloads for arr stack
  - `/mnt/cameras/` - Frigate recordings (5-day + 30-day event retention)

**Caching:**
- Redis: Not used
- In-memory: Prometheus time-series database (TSDB) on firebat
- Retention policy: 30 days / 10GB size limit for Prometheus

## Authentication & Identity

**Auth Provider:**
- Custom SOPS-based secrets (no external auth service)

**Implementation:**
- Jellyfin: Hashed passwords stored in SOPS (`jellyfin_admin_password`, `jellyfin_jordan_password`)
  - Hash generation: `scripts/sops/genhash.py` before SOPS storage
  - Credentials managed via declarative-jellyfin module
- Grafana: Admin password via SOPS (`grafana_admin_password`) with file reference `$__file{}`
- Caddy: Tailscale plugin auto-provisions HTTPS certificates
- Frigate: Auth disabled (behind Tailscale firewall)
- Home Assistant: Onboarding flow for initial user creation
- SSH: Key-based authentication to all hosts (no password login)

**Secrets Management:**
- SOPS with age encryption (RFC 8439)
- Master GPG key: `05BE930549C3E945BA3D8B6E72B6A6E95F049306` (admin_bobby)
- Age keys per-host stored in `secrets/keys/hosts/`
- Shared secrets in `secrets/shared.yaml` (readable by all hosts)
- Host-specific secrets in `secrets/HOST.yaml` (readable only by that host)
- Creation rules in `.sops.yaml` define encryption keys per file

## Monitoring & Observability

**Metrics Collection:**
- Prometheus (firebat:9090) - Time-series database
- 30-day retention, 10GB storage limit
- Admin API enabled for series deletion

**Scrape Targets:**
- Node Exporter: System metrics from ser8, firebat, pi4 (port 9100)
  - CPU, memory, filesystem, disk I/O, load average, network, processes
- Systemd Exporter: Service state and restart counts (port 9558)
  - Monitors: jellyfin, sonarr, radarr, prowlarr, qbittorrent, sabnzbd, frigate, home-assistant, caddy, grafana, prometheus, adguardhome, mosquitto, nginx
- Process Exporter: Per-service CPU/memory/IO metrics (port 9256)
  - Process filtering by name and command line
- ZFS Exporter: Pool health and metrics (ser8 only, port 9134)
- Frigate Exporter: NVR metrics via `/api/stats` endpoint (port 9710)
- Jellyfin Exporter: Media server metrics (port 9711)
- Exportarr: Sonarr (9707), Radarr (9708), Prowlarr (9709)
- Caddy Metrics: Admin API on port 2019
- AdGuard Home: DNS metrics (pi4, port 9618)

**Visualization:**
- Grafana (firebat:3000)
- Dashboards from grafana.com (pre-downloaded in `dashboards/`):
  - Node Exporter Full (ID 1860) - System metrics
  - ZFS Pool Status (ID 7845) - Storage health
  - Prometheus Stats (ID 3662) - Self-monitoring
  - Frigate dashboard - NVR metrics
  - Jellyfin dashboard - Media server metrics
  - Sonarr, Radarr dashboards - Arr stack metrics
  - AdGuard dashboard - DNS filtering stats
  - Caddy dashboard - Reverse proxy metrics
  - Systemd dashboard - Service monitoring
- Datasource: Prometheus (http://localhost:9090)
- Admin auth: SOPS-encrypted password
- Anonymous viewer access enabled for dashboards

**Error Tracking:**
- systemd journal aggregation with log rotation
- Journal max: 1GB per host, 100MB per file, 10 files max
- Service logs accessible via `journalctl`
- No external error tracking (Sentry, Rollbar, etc.)

**Logs:**
- All systemd service logs via journald
- Log rotation: 7-day retention, daily rotation, compression enabled
- API key sanitization in logs (secrets not exposed in systemd output)

## CI/CD & Deployment

**Hosting:**
- Self-hosted homelab:
  - ser8: Beelink SER8 (x86_64, media server)
  - firebat: x86_64 gateway/proxy
  - pi4: Raspberry Pi 4B (DNS)
  - pi5: Raspberry Pi 5 (experimental)
- No cloud hosting

**Deployment Process:**
- Local build via `nixos-rebuild` wrapped in Makefile
- Remote build available on targets (`buildOnTarget: true` in deploy.yaml)
- nixos-anywhere for initial provisioning with kexec installers
- Rollback capability to previous system generation
- SD card image builders for Raspberry Pi via Docker
- Smoketests post-deployment: `scripts/smoketests/` per service type

**CI Pipeline:**
- No external CI (GitHub Actions, GitLab CI, etc.)
- Local testing via `make check` (flake validation)
- Format validation via `make fmt` with nixfmt-rfc-style

## Environment Configuration

**Required env vars:**
- None hardcoded in deployment
- All secrets via SOPS (age-encrypted files)
- Service-specific env vars injected via systemd unit files from SOPS templates

**Critical SOPS Secrets:**
- `tailscale_authkey` (shared.yaml) - Shared across all hosts for auto-auth
- `tailscale_authkey_caddy` (shared.yaml) - Caddy-owned copy for reverse proxy
- `grafana_admin_password` (firebat.yaml) - Grafana admin access
- `jellyfin_admin_password` (ser8.yaml) - Jellyfin media server admin
- `jellyfin_jordan_password` (ser8.yaml) - Jellyfin user account
- `frigate_cam_user` (ser8.yaml) - RTSP camera username
- `frigate_cam_pass` (ser8.yaml) - RTSP camera password
- `nordvpn_access_token` (ser8.yaml) - NordVPN API token

**Secrets location:**
- `secrets/shared.yaml` - Readable by all hosts (age-encrypted with all host keys + admin GPG)
- `secrets/HOST.yaml` - Host-specific secrets (encrypted with admin GPG + single host age key)
- `secrets/keys/hosts/` - Host age private keys (generated during provisioning)
- `secrets/keys/users/` - User age keys for admin access
- `.sops.yaml` - Encryption rules and key management configuration

## Webhooks & Callbacks

**Incoming Webhooks:**
- None configured
- Frigate runs locally without external webhook callbacks
- Home Assistant automation internal only

**Outgoing Webhooks:**
- None configured
- No external service callbacks
- All integrations are pull-based (Prometheus scraping exporters)

## Network & DNS

**DNS Provider:**
- Internal: AdGuard Home on pi4 (DNS on port 53)
- Upstream: Cloudflare (1.1.1.1, 1.0.0.1), Google (8.8.8.8, 8.8.4.4)
- All hosts configured to use pi4 as primary DNS server
- Internal domain rewriting for `.internal` and `.local` domains
- Tailscale MagicDNS for remote access via `shad-bangus.ts.net`

**Reverse Proxy:**
- Caddy with Tailscale plugin (firebat)
- Local domain: `vofi.app` and `vofi` with self-signed certs via local CA
- Tailscale domain: `shad-bangus.ts.net` with Let's Encrypt certificates
- HTTPS enforcement for remote access

**Services via Caddy:**
- `jellyfin.vofi.app` → localhost:8096
- `sonarr.vofi` → localhost:8989
- `radarr.vofi` → localhost:7878
- `prowlarr.vofi` → localhost:9696
- `torrent.vofi` → localhost:8080 (qBittorrent)
- `sabnzbd.vofi` → localhost:8085
- `frigate.vofi` → localhost:5000
- `hass.vofi` → localhost:8123
- `grafana.vofi.app` → localhost:3000
- `prometheus.vofi.app` → localhost:9090
- `adguard.internal` → localhost:3000 (AdGuard admin)

---

*Integration audit: 2026-02-09*
