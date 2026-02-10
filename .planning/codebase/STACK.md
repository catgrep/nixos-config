# Technology Stack

**Analysis Date:** 2026-02-09

## Languages

**Primary:**
- Nix - System configuration language, used throughout flake.nix and all modules
- Bash/Zsh - Shell scripting for build and deployment scripts in `scripts/`

**Secondary:**
- Python - Home Assistant components, Frigate exporter scripts
- Go - Tools like Caddy, Prometheus, related utilities

## Runtime

**Environment:**
- NixOS 25.05 (stable channel) - Primary OS for x86_64 systems (ser8, firebat)
- NixOS unstable - Used selectively for packages with known issues in stable (Jellyfin stack, Tailscale, Caddy)
- Raspberry Pi OS via nixos-raspberrypi - ARM64 systems (pi4, pi5)

**Package Manager:**
- Nix (flake-based) - `flake.nix` as primary manifest
- Lockfile: `flake.lock` (present, locked inputs)

## Frameworks

**Core Infrastructure:**
- NixOS with flake system - Declarative system configuration across multiple hosts
- home-manager 25.05 - User environment and dotfile management

**Deployment:**
- Disko - Declarative disk partitioning (`modules/` configurations)
- Impermanence - Ephemeral root filesystem with Erase Your Darlings pattern (ser8)
- sops-nix - Secrets management with age encryption (`modules/servers/`)

**Build/Dev:**
- nixos-rebuild - System configuration rebuild and activation
- nixos-anywhere - Remote NixOS provisioning
- nixos-raspberrypi - Raspberry Pi OS builders and installers

## Key Dependencies

**Critical (All Hosts):**
- nixpkgs (NixOS 25.05) - Standard package collection
- nixpkgs-unstable - Security and compatibility fixes for select services
- caddy-nix - Caddy reverse proxy with plugin support overlay

**Media & Streaming (ser8):**
- Jellyfin (8.11.x from unstable) - Media server with declarative-jellyfin module
- Sonarr - TV show management
- Radarr - Movie management
- Prowlarr - Indexer management
- qBittorrent-nox - Torrent client (runs in NordVPN namespace)
- SABnzbd - Usenet download client
- FFmpeg - Media transcoding (hardware acceleration via VA-API with Radeon 780M)

**Automation (ser8):**
- Frigate 0.15.2 - NVR with AI object detection via CPU
- Home Assistant - Home automation platform
- Mosquitto - MQTT broker for Frigate <-> Home Assistant communication

**Gateway (firebat):**
- Caddy 2.10.2+ (with Tailscale plugin) - Reverse proxy with auto HTTPS via Let's Encrypt
- Prometheus - Metrics collection and time-series database
- Grafana - Monitoring dashboards with provisioned configs
- node-exporter - System metrics from all hosts (port 9100)
- systemd-exporter - Service state metrics (port 9558)
- process-exporter - Per-service CPU/memory/IO metrics (port 9256)
- zfs-exporter - ZFS pool metrics (ser8 only, port 9134)

**DNS (pi4):**
- AdGuard Home - DNS filtering and ad blocking
- adguard-exporter - Prometheus metrics for AdGuard (port 9618)

**VPN & Network:**
- Tailscale - VPN mesh network for remote access (all hosts)
- NordVPN WireGuard - Anonymized tunnel via network namespace (ser8)
- wgnord - NordVPN WireGuard config manager

**Monitoring Exporters:**
- prometheus-frigate-exporter - Frigate NVR metrics scraper (port 9710)
- jellyfin-exporter - Jellyfin media server metrics (port 9711)
- exportarr - Sonarr/Radarr/Prowlarr metrics (ports 9707-9709)

## Configuration

**Environment:**
- Configuration via Nix module system in `modules/`
- Host-specific overrides in `hosts/HOSTNAME/configuration.nix`
- Secrets via SOPS (age encryption) in `secrets/` directory
- Environment variables for service configuration injected via systemd units
- Firewall rules per-service module with conditional opening based on role

**Build:**
- `flake.nix` - Main flake configuration with module composition
- `deploy.yaml` - Host metadata (IPs, users, tags, smoketests)
- Makefile wrapper around nixos-rebuild for consistent deployments
- scripts/nixos-rebuild.sh - Remote build and switch execution

## Platform Requirements

**Development:**
- NixOS 25.05 or compatible with flakes support
- SSH key access to target hosts
- sops, age, ssh-to-age tools (provided in devShell)
- mkcert for local CA (optional, for certificate testing)

**Production (ser8 - Media Server):**
- Beelink SER8 (x86_64, 12-core CPU, Radeon 780M iGPU)
- ZFS storage pool(s) for media library
- Backup pool for camera recordings (`/mnt/cameras`)
- MergerFS for unified media view across multiple disks
- Hardware acceleration: AMD VA-API (Radeon 780M)
- Network: Static IP 192.168.68.65 (eth0), Tailscale tunnel

**Production (firebat - Gateway):**
- x86_64 system, acts as reverse proxy/monitoring hub
- Network: Static IP 192.168.68.63, Tailscale tunnel
- Must resolve DNS locally via AdGuard on pi4

**Production (pi4 - DNS Server):**
- Raspberry Pi 4 Model B
- Network: Static IP 192.168.68.56
- Powers all network DNS queries (1.1.1.1, 8.8.8.8 as fallback)

**Production (pi5 - Experimental):**
- Raspberry Pi 5
- Network: Static IP 192.168.0.110
- Reserved for experiments, minimal configuration

## Development Shell

**Tools Provided:**
- nixfmt-rfc-style - Nix code formatter
- nixos-rebuild - System rebuild command
- sops, age, ssh-to-age - Secrets management
- yq-go - YAML parsing
- jq - JSON parsing
- python3 - Build scripting
- wireguard-tools - VPN testing
- caddy - Reverse proxy testing
- shellcheck - Shell script linting

---

*Stack analysis: 2026-02-09*
