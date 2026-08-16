# External Integrations

**Analysis Date:** 2026-08-17

## APIs & External Services

**VPN:**
- NordVPN (WireGuard, via `wgnord`) - `modules/nordvpn/service.nix`, `modules/nordvpn/default.nix`
  - Auth: access token file referenced by `config.nordvpn.accessTokenFile` (SOPS-backed)
  - qBittorrent runs inside the resulting `wgnord` network namespace on `ser8`

**Remote access / mesh networking:**
- Tailscale - `modules/servers/tailscale.nix` (base auth), `modules/gateway/tailscale.nix`, `caddy-nix`'s Tailscale plugin (`modules/gateway/caddy.nix`)
  - Auth: `tailscale_authkey` SOPS secret from `secrets/shared.yaml`, injected via `services.tailscale.authKeyFile`
  - Domain: `shad-bangus.ts.net` (`deploy.yaml`); services get individual Tailscale nodes and automatic ACME TLS via the `bind tailscale/<service>` directive in `modules/gateway/Caddyfile`

**Media automation (*Arr stack, internal service-to-service):**
- Sonarr, Radarr, Prowlarr, Bazarr, qBittorrent, SABnzbd, NZBGet, FlareSolverr - all under `modules/media/`, orchestrated together on `ser8`; inter-service API keys/config coordinated by `hosts/ser8/media.nix` systemd units
- Jellyfin - declaratively configured via the `declarative-jellyfin` flake input (`modules/media/jellyfin.nix`)

**Home automation:**
- Home Assistant - `modules/automation/home-assistant.nix`
- Frigate (NVR/object detection) - `modules/automation/frigate.nix`, exposed via Caddy with WebSocket upgrade headers
- Mosquitto (MQTT broker) - referenced alongside Home Assistant/Frigate integration on `ser8`

## Data Storage

**Databases:**
- No standalone RDBMS; each service (Jellyfin, *Arr apps, Home Assistant, Grafana) manages its own embedded/SQLite-style state under its NixOS-managed data directory

**File Storage:**
- ZFS - system and backup pool on `ser8`
- MergerFS - unified `/mnt/media` pool on `ser8`
- Samba - LAN file sharing of media storage
- Local filesystem only for all other hosts; no object storage / S3-compatible integration detected

**Caching:**
- None detected (no Redis/Memcached)

## Authentication & Identity

**Auth Provider:**
- No third-party identity provider (no OAuth/OIDC integration detected)
- Per-service local auth: qBittorrent password hash generated via `make sops-gen-hash-qbittorrent`; generic API keys/hashes via `make sops-gen-api-key` / `make sops-gen-hash`
- SSH key-based access for deployment (`deploy.yaml` targetUser per host)

## Monitoring & Observability

**Metrics:**
- Prometheus - `modules/gateway/prometheus.nix`, scraping exporters across hosts
- Prometheus Blackbox Exporter - `modules/gateway/blackbox.nix` for endpoint/uptime probing
- Grafana - `modules/gateway/grafana.nix`, dashboards version-controlled as JSON in `dashboards/`, provisioned declaratively
- Service-specific exporters: `modules/automation/frigate-exporter.nix`, `modules/media/jellyfin-exporter.nix`, `modules/dns/adguard-exporter.nix`

**Error Tracking:**
- None (no Sentry or similar APM/error-tracking integration)

**Logs:**
- systemd journal (standard NixOS logging) plus Caddy access/error logs (per-route `log tailscale { level DEBUG }` in `modules/gateway/Caddyfile`)

## CI/CD & Deployment

**Hosting:**
- Self-hosted bare-metal/homelab (no cloud provider); four physical hosts per `deploy.yaml`

**CI Pipeline:**
- None detected in-repo (no `.github/workflows/`); `make check` is the local pre-deploy validation gate
- Deployment executed manually via `make build-<host>`, `make test-<host>`, `make switch-<host>` using `nixos-anywhere`/remote build (`buildOnTarget: true`)

## Environment Configuration

**Required env vars:**
- None required for the flake itself (SOPS/age handle secret injection at the Nix/systemd level rather than shell env vars)
- `NO_CONFIRM=true` - opt-in Makefile flag to bypass interactive deploy prompts

**Secrets location:**
- `secrets/<host>.yaml` - host-specific SOPS-encrypted secrets (e.g. NordVPN token, service API keys)
- `secrets/shared.yaml` - cross-host secrets (e.g. `tailscale_authkey`)
- Age identities derived from SSH host keys; persistent hosts read keys from `/persist/etc/ssh/`
- Managed exclusively through `make sops-edit-<host>`, `make sops-edit-shared`, `make sops-status` — never via ad hoc plaintext edits

## Webhooks & Callbacks

**Incoming:**
- None detected (no webhook receiver endpoints configured)

**Outgoing:**
- *Arr-stack-to-download-client API calls (Sonarr/Radarr/Prowlarr → qBittorrent/SABnzbd/NZBGet) are internal service integrations, not external webhooks
- No outbound webhook/notification integrations (e.g. Slack, Discord, PagerDuty) detected

---

*Integration audit: 2026-08-17*
