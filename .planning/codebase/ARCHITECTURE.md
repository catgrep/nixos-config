# Architecture

**Analysis Date:** 2026-02-09

## Pattern Overview

**Overall:** Modular NixOS flake-based homelab configuration using a layered module system with host-specific composition.

**Key Characteristics:**
- Flake-based configuration management using `flake.nix` as the central entry point
- Modular architecture with shared base layers composed into host-specific configurations
- Host-specific overrides in `hosts/HOSTNAME/configuration.nix`
- Secrets management via SOPS with age encryption
- Multi-architecture support (x86_64 for ser8/firebat, aarch64 for pi4/pi5)

## Layers

**Layer 1 - Base/Common (Applied to all hosts):**
- Purpose: Shared configuration across all hosts
- Location: `modules/common/`
- Contains: SSH configuration, users, networking options, boot settings, locale, packages, tmux, neovim, banner
- Depends on: NixOS base modules
- Used by: All hosts via `baseModules` in flake.nix

**Layer 2 - Servers (Applied to x86_64 hosts: ser8, firebat):**
- Purpose: Server-specific optimizations and monitoring infrastructure
- Location: `modules/servers/`
- Contains:
  - Prometheus node exporter, systemd exporter, process exporter (per-service CPU/memory/IO)
  - Monitoring configuration with rules for alerting
  - Backup configuration
  - Security hardening (firewall, SSH hardening)
  - Tailscale integration for VPN access
- Depends on: Common layer
- Used by: ser8, firebat

**Layer 3 - Infrastructure-Specific Modules:**

**modules/gateway/ (Firebat only):**
- Purpose: Reverse proxy, monitoring, and metrics aggregation
- Location: `modules/gateway/`
- Contains: Caddy with Tailscale plugin, Prometheus scrape configs, Grafana dashboards, Tailscale daemon
- Depends on: Servers layer
- Used by: firebat host

**modules/media/ (ser8 only):**
- Purpose: Media service stack (Jellyfin, arr applications, torrent/usenet clients)
- Location: `modules/media/`
- Contains: Jellyfin, Sonarr, Radarr, Prowlarr, qBittorrent, SABnzbd, FlareSolverr, Jellyfin exporter, Exportarr
- Depends on: Servers layer, Nordvpn layer
- Used by: ser8 host

**modules/automation/ (ser8 only):**
- Purpose: Home automation and security camera management
- Location: `modules/automation/`
- Contains: Home Assistant, Frigate NVR, MQTT broker (Mosquitto), Frigate exporter
- Depends on: Common layer
- Used by: ser8 host

**modules/nordvpn/ (ser8 only):**
- Purpose: VPN network namespace isolation for anonymized torrenting
- Location: `modules/nordvpn/`
- Contains: WireGuard configuration, network namespace setup, veth bridge for qBittorrent isolation
- Depends on: Common layer, provides custom options for other modules
- Used by: ser8 host, referenced by qbittorrent module

**modules/dns/ (pi4 only):**
- Purpose: Network DNS server with blocking and rewriting
- Location: `modules/dns/`
- Contains: AdGuard Home, exporter metrics
- Depends on: Common layer
- Used by: pi4 host

**modules/raspberrypi/ (pi4, pi5):**
- Purpose: ARM-specific base configuration
- Location: `modules/raspberrypi/`
- Contains: Installer configuration, USB installer configuration, base.nix
- Depends on: Nothing; used as base layer
- Used by: pi4, pi5 via mkPiSystem helper

## Data Flow

**Host Configuration Composition Flow:**

1. **x86_64 Systems (ser8, firebat):**
   ```
   flake.nix mkSystem
   ├── caddy-nix overlay (caddy plugin support)
   ├── hosts/HOSTNAME/configuration.nix (host entry point)
   ├── baseModules
   │   ├── modules/common/ (shared: networking, users, boot, SSH)
   │   ├── modules/servers/ (server monitoring, backup, security)
   │   └── sops-nix + home-manager integration
   ├── x86Modules
   │   ├── disko (disk partitioning)
   │   ├── impermanence (root filesystem rollback)
   │   └── declarative-jellyfin
   └── Host-specific modules (media, gateway, automation, nordvpn)
   ```

2. **ARM Systems (pi4, pi5):**
   ```
   flake.nix mkPiSystem
   ├── nixos-raspberrypi base (Pi 4 or Pi 5 specific)
   ├── hosts/HOSTNAME/configuration.nix
   ├── baseModules (common, servers)
   ├── piModules (raspberrypi/base.nix)
   └── Host-specific modules (dns)
   ```

**Service Configuration Flow:**

Each service module (e.g., `modules/media/jellyfin.nix`) follows this pattern:
1. Define service-specific NixOS options in `services.SERVICENAME`
2. Configure with host-level overrides in `hosts/HOSTNAME/configuration.nix`
3. Export monitoring metrics via exporters (Prometheus exporters)
4. Open required firewall ports (if applicable)

**State Management:**

- **Ephemeral State:** Stored on tmpfs at `/tmp` (32GB on ser8)
- **Persistent State:** Via Impermanence on ser8/firebat - root filesystem rolls back to clean snapshot on boot
- **Permanent Data:**
  - Media: `/mnt/media` (MergerFS combining disk1/disk2)
  - Camera recordings: `/mnt/cameras` (ZFS backup pool)
  - Configuration: Via NixOS system configuration (declarative)
- **Secrets:** Via SOPS with age encryption, stored in `secrets/HOST.yaml` (host-specific) or `secrets/shared.yaml` (all hosts)

## Key Abstractions

**Networking Options (modules/common/networking.nix):**
- Purpose: Unified network configuration API across all hosts
- Examples: `networking.internal.interface`, `networking.internal.adguard`, `networking.internal.forwarding`
- Pattern: Options use `lib.mkOption` to define schema; hosts override via `config.networking.internal.*`

**SOPS Secrets:**
- Purpose: Declarative secret management with encryption
- Examples: `sops.secrets.nordvpn_access_token`, `sops.secrets.tailscale_authkey_caddy`
- Pattern: Dual secret declaration allows same YAML key with different file permissions (root:root vs caddy:caddy)

**Prometheus Exporters:**
- Purpose: Metric collection and monitoring across stack
- Instances: node (system), zfs (storage), process (per-service CPU/memory), systemd (unit state), Jellyfin, Exportarr, Frigate, AdGuard
- Pattern: Each service module enables exporters; Prometheus scrapes via static host targets (`.local` mDNS names)

**NordVPN Namespace Module:**
- Purpose: Network isolation for VPN-routed services
- Pattern: Provides custom NixOS options (`config.nordvpn.*`); qbittorrent module checks `useVpnNamespace` flag
- Implementation: Veth bridge between host (192.168.100.1) and VPN namespace (192.168.100.2)

**Service Discovery:**
- Purpose: Mapping services to packages for inventory/monitoring
- Implementation: `flake.nix` `enabledServices`, `servicePackages`, `packageInfo` outputs
- Query: `nix eval '.#enabledServices.ser8' --json` lists all enabled services on ser8

## Entry Points

**Primary Entry (flake.nix):**
- Location: `/Users/bobby/github/catgrep/nixos-config/flake.nix`
- Triggers: `nix flake show`, `nixos-rebuild`, `make` commands
- Responsibilities:
  - Defines all inputs (nixpkgs, disko, sops-nix, home-manager, declarative-jellyfin, caddy-nix, etc.)
  - Composes host configurations via mkSystem/mkPiSystem helpers
  - Exports nixosConfigurations for each host
  - Provides dev shell with build tools

**Host Entry Points:**
- `hosts/ser8/configuration.nix` - Media server entry
- `hosts/firebat/configuration.nix` - Gateway entry
- `hosts/pi4/configuration.nix` - DNS server entry
- `hosts/pi5/configuration.nix` - Experimental Pi entry

Each host entry imports:
1. Hardware configuration (disko, hardware-specific)
2. Impermanence configuration (if applicable)
3. Host-specific service modules
4. Declares service enable flags and overrides

**Module Entry Points:**
- `modules/common/default.nix` - Imports all common sub-modules
- `modules/media/default.nix` - Imports all media services
- `modules/gateway/default.nix` - Imports Caddy, Prometheus, Grafana
- `modules/servers/default.nix` - Imports monitoring, backup, security, Tailscale
- Similar pattern for automation, dns, nordvpn, raspberrypi

**Build/Deployment Entry (Makefile):**
- Location: `Makefile`
- Calls: `scripts/nixos-rebuild.sh` wrapper script
- Targets: `make build-HOST`, `make test-HOST`, `make switch-HOST`, `make apply-HOST`

## Error Handling

**Strategy:** Fail-fast with meaningful error messages; no silent failures.

**Patterns:**

1. **SOPS Secret Decryption Errors:**
   - Missing age keys → build fails at configuration evaluation
   - Wrong permissions on secret → runtime failure at service startup
   - Mitigation: Host keys stored in `secrets/keys/hosts/HOSTNAME`

2. **Network/DNS Failures:**
   - AdGuard failover: `networking.internal.adguard.mode = "failover"` allows fallback to router DNS
   - Caddy DNS resolution: Explicit restart on systemd-resolved changes (`partOf = [ "systemd-resolved.service" ]`)

3. **Service Dependencies:**
   - Mosquitto required for Frigate ↔ Home Assistant: Both configured in ser8
   - qBittorrent proxy depends on NordVPN namespace: nginx waits for namespace startup

4. **Impermanence/ZFS Rollback:**
   - Root filesystem rolled back on boot to clean snapshot
   - Prevents accidental state creep
   - Failures: If snapshot missing, boot fails loudly

## Cross-Cutting Concerns

**Logging:**
- Journal-based: All services log to systemd journal
- Retention: 1GB max, 100MB per file, 10 files max (see `modules/servers/monitoring.nix`)
- Rotation: logrotate on all hosts (7-day retention)

**Validation:**
- NixOS module system provides type checking at build time
- No runtime validation; all validation happens during `nixos-rebuild`

**Authentication:**
- SSH key-based for Tailscale and remote deployment
- Age encryption with SSH host keys for SOPS secrets
- Service-to-service: Tailscale MagicDNS for zero-trust networking

**Networking:**
- Tailscale daemon on all hosts for VPN access
- mDNS (`.local`) for local discovery
- AdGuard DNS on pi4 for network-wide DNS blocking/rewriting
- Caddy reverse proxy on firebat for HTTPS termination

---

*Architecture analysis: 2026-02-09*
