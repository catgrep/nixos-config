# Codebase Structure

**Analysis Date:** 2026-02-09

## Directory Layout

```
nixos-config/
├── .planning/                    # GSD planning documents and analyses
├── .git/                         # Git repository metadata
├── dashboards/                   # Grafana dashboard JSON files (pre-built from grafana.com)
├── etc/                          # Example configuration files for local nix config
├── experimental/                 # Experimental features (not yet integrated)
├── flake.nix                     # Main flake configuration and entry point
├── flake.lock                    # Flake lock file with pinned versions
├── Makefile                      # Build and deployment command interface
├── deploy.yaml                   # Host metadata (IPs, users, deployment settings)
├── README.md                     # Project overview and quick start
├── CLAUDE.md                     # Claude AI instructions for this codebase
├── TODO.md                       # Project roadmap and task tracking
├── SPDX-License-Identifier: GPL-3.0-or-later (in file headers)
├── LICENSE                       # GPL-3.0-or-later license text
│
├── hosts/                        # Per-host configurations
│   ├── ser8/                     # Media server (Beelink SER8)
│   │   ├── default.nix           # Import barrel - aggregates host configuration
│   │   ├── configuration.nix     # Main host config (service enables, overrides)
│   │   ├── hardware-configuration.nix  # Hardware-specific (CPU, memory, storage)
│   │   ├── disko-config.nix      # ZFS/disk partitioning and layout
│   │   ├── impermanence.nix      # Persistent directories (SOPS, media, etc)
│   │   ├── media.nix             # Media server configuration
│   │   └── samba.nix             # SMB file sharing for media drive
│   │
│   ├── firebat/                  # Gateway/reverse proxy (x86_64)
│   │   ├── default.nix           # Import barrel
│   │   ├── configuration.nix     # Main host config
│   │   ├── hardware-configuration.nix
│   │   ├── disko-config.nix
│   │   └── impermanence.nix
│   │
│   ├── pi4/                      # DNS server (Raspberry Pi 4)
│   │   ├── configuration.nix     # Main host config (AdGuard Home)
│   │   └── hardware-configuration.nix
│   │
│   └── pi5/                      # Experimental Raspberry Pi 5
│       ├── configuration.nix
│       ├── hardware-configuration.nix
│       ├── disko-config.nix
│       └── configtxt.nix         # Pi-specific boot config
│
├── modules/                      # Reusable NixOS modules
│   ├── common/                   # Shared configuration for all hosts
│   │   ├── default.nix           # Import barrel aggregating all common modules
│   │   ├── boot.nix              # Bootloader, kernel params (server optimizations)
│   │   ├── networking.nix        # Network options API (interface, DNS, forwarding)
│   │   ├── users.nix             # User definitions and groups
│   │   ├── ssh.nix               # SSH server configuration
│   │   ├── locale.nix            # Time zone and locale settings
│   │   ├── nix.nix               # Nix daemon configuration (flakes, auto-optimise)
│   │   ├── packages.nix           # Common system packages (git, git-lfs, htop, etc)
│   │   ├── tmux.nix              # Tmux user configuration
│   │   ├── neovim.nix            # Neovim user configuration
│   │   └── banner.nix            # Login banner for all hosts
│   │
│   ├── servers/                  # Server-specific (applied to ser8, firebat)
│   │   ├── default.nix           # Import barrel
│   │   ├── monitoring.nix        # Prometheus exporters (node, zfs, systemd, process)
│   │   ├── security.nix          # SSH hardening, firewall baseline
│   │   ├── backup.nix            # Backup configuration
│   │   └── tailscale.nix         # Tailscale VPN daemon
│   │
│   ├── gateway/                  # Reverse proxy and monitoring (firebat only)
│   │   ├── default.nix           # Import barrel
│   │   ├── caddy.nix             # Reverse proxy with Tailscale plugin
│   │   ├── Caddyfile             # External Caddy configuration file
│   │   ├── prometheus.nix        # Prometheus scrape configs and alerting rules
│   │   ├── grafana.nix           # Grafana with provisioned dashboards
│   │   └── tailscale.nix         # Tailscale daemon specific config
│   │
│   ├── media/                    # Media services (ser8 only)
│   │   ├── default.nix           # Import barrel
│   │   ├── jellyfin.nix          # Media streaming server
│   │   ├── jellyfin-exporter.nix # Prometheus exporter for Jellyfin
│   │   ├── sonarr.nix            # TV show management
│   │   ├── radarr.nix            # Movie management
│   │   ├── prowlarr.nix          # Indexer manager
│   │   ├── qbittorrent.nix       # Torrent client (VPN namespace support)
│   │   ├── sabnzbd.nix           # Usenet download client
│   │   ├── exportarr.nix         # Prometheus exporter for arr stack
│   │   ├── alldebrid-proxy.nix   # AllDebrid integration (commented out)
│   │   └── transmission.nix      # Transmission torrent client (backup)
│   │
│   ├── automation/               # Home automation (ser8 only)
│   │   ├── default.nix           # Import barrel
│   │   ├── home-assistant.nix    # Home automation platform
│   │   ├── frigate.nix           # NVR security camera system
│   │   ├── frigate-exporter.nix  # Prometheus exporter for Frigate
│   │   └── README.md             # Frigate-specific documentation
│   │
│   ├── nordvpn/                  # VPN namespace isolation (ser8)
│   │   ├── default.nix           # Options definition and base config
│   │   └── service.nix           # VPN namespace systemd service
│   │
│   ├── dns/                      # DNS server (pi4 only)
│   │   ├── default.nix           # Import barrel
│   │   ├── adguard-home.nix      # AdGuard Home DNS blocking
│   │   ├── adguard-exporter.nix  # Prometheus metrics
│   │   └── users.nix             # AdGuard-specific user configuration
│   │
│   ├── raspberrypi/              # ARM-specific configuration
│   │   ├── base.nix              # Base Pi configuration
│   │   ├── installer.nix         # SD card installer for Pi 4
│   │   └── usb-installer.nix     # USB installer for Pi 5
│   │
│   └── development/              # Development tools (future)
│       ├── default.nix
│       └── gerrit.nix            # Gerrit code review (planned)
│
├── users/                        # User configurations
│   └── bdhill.nix                # Home-manager configuration for primary user
│
├── home-manager/                 # Separate home-manager flake
│   ├── flake.nix                 # Home-manager flake definition
│   └── ...                       # Home-manager specific configs
│
├── secrets/                      # SOPS-encrypted secrets (age encryption)
│   ├── .sops.yaml                # SOPS configuration (hosts, users, rules)
│   ├── ser8.yaml                 # ser8-specific secrets (NordVPN token, etc)
│   ├── firebat.yaml              # firebat-specific secrets (currently empty)
│   ├── shared.yaml               # Shared secrets for all hosts (Tailscale auth key)
│   └── keys/                     # Encryption keys
│       ├── hosts/                # Host SSH public keys for age encryption
│       │   ├── ser8.pub
│       │   ├── firebat.pub
│       │   └── ...
│       └── users/                # User SSH public keys
│           └── ...
│
├── scripts/                      # Automation and deployment scripts
│   ├── nixos-rebuild.sh          # Main deployment wrapper script
│   ├── lib/                      # Script utility libraries
│   ├── sops/                     # SOPS helper scripts
│   ├── provision/                # Host provisioning scripts
│   ├── smoketests/               # Post-deployment validation
│   │   ├── media/                # Media services smoke tests
│   │   ├── gateway/              # Gateway services smoke tests
│   │   └── dns/                  # DNS services smoke tests
│   └── license/                  # License header injection scripts
│
└── logs/                         # Build logs from deployments
    └── ... (various per-host logs)
```

## Directory Purposes

**hosts/HOSTNAME/:**
- Purpose: Host-specific configuration entry points
- Contains: One directory per host (ser8, firebat, pi4, pi5)
- Each host must have: `configuration.nix`, `hardware-configuration.nix`
- Key files:
  - `default.nix`: Barrel file that imports all host-specific modules
  - `configuration.nix`: Main entry - service enable flags and host overrides
  - `hardware-configuration.nix`: Generated by NixOS installer; CPU, RAM, storage layout
  - `disko-config.nix`: Declarative disk partitioning (if using Disko)
  - `impermanence.nix`: Lists persistent directories (if using Impermanence)

**modules/MODULENAME/:**
- Purpose: Reusable NixOS module groups
- Contains: Related service configurations and options
- Structure:
  - `default.nix`: Barrel file importing all sub-modules
  - `*.nix`: Individual service or feature modules
- Pattern: Each module is self-contained; can be added to any host via flake.nix

**modules/common/:**
- Purpose: Shared base layer applied to ALL hosts
- Contains: Fundamental settings (users, networking, SSH, boot, locale, packages)
- Key abstraction: `networking.internal.*` options (interface, DNS, forwarding)

**secrets/:**
- Purpose: SOPS-encrypted configuration secrets
- Contains: YAML files with encrypted values
- Pattern:
  - `secrets/HOSTNAME.yaml`: Host-specific secrets (only that host decrypts)
  - `secrets/shared.yaml`: Shared secrets readable by all hosts (Tailscale auth key)
- Encryption: Age keys derived from host SSH keys

**scripts/:**
- Purpose: Operational and deployment automation
- Key file: `scripts/nixos-rebuild.sh` - Main deployment wrapper called by Makefile
- Subdirectories:
  - `smoketests/`: Post-deployment validation scripts
  - `sops/`: Secret key management scripts
  - `provision/`: Initial provisioning and bootstrapping

## Key File Locations

**Entry Points:**
- `flake.nix`: Root flake defining all nixosConfigurations
- `hosts/ser8/configuration.nix`: Media server entry
- `hosts/firebat/configuration.nix`: Gateway entry
- `hosts/pi4/configuration.nix`: DNS server entry
- `hosts/pi5/configuration.nix`: Experimental Pi entry

**Configuration:**
- `deploy.yaml`: Host metadata (IPs, users, deployment tags)
- `.sops.yaml`: SOPS encryption rules and key paths
- `modules/common/networking.nix`: Shared networking options API
- `modules/gateway/Caddyfile`: Caddy reverse proxy routes

**Core Logic:**
- `modules/servers/monitoring.nix`: Prometheus exporter configuration
- `modules/gateway/prometheus.nix`: Scrape configs and alerting rules
- `modules/gateway/caddy.nix`: Reverse proxy with Tailscale plugin
- `modules/media/jellyfin.nix`: Media streaming server
- `modules/automation/frigate.nix`: NVR security camera system
- `modules/nordvpn/default.nix`: VPN namespace options

**Testing:**
- `scripts/smoketests/media/all.sh`: Media stack validation
- `scripts/smoketests/gateway/all.sh`: Gateway services validation
- `scripts/smoketests/dns/all.sh`: DNS services validation

**Build/Deployment:**
- `Makefile`: Primary command interface
- `scripts/nixos-rebuild.sh`: Deployment wrapper

## Naming Conventions

**Files:**
- Pattern: `kebab-case.nix` (e.g., `hardware-configuration.nix`, `media.nix`)
- Exceptions: Capital letters for special files (`Makefile`, `Caddyfile`, `README.md`, `CLAUDE.md`, `LICENSE`)

**Directories:**
- Pattern: `lowercase` for module directories (e.g., `modules/common/`, `hosts/ser8/`)
- Special: `UPPERCASE` for documentation (e.g., `.planning/codebase/ARCHITECTURE.md`)

**Nix Option Names:**
- Pattern: `snake_case` for service options (e.g., `services.jellyfin.enable`)
- Custom options: `networking.internal.adguard`, `nordvpn.accessTokenFile`

**Variables/Let-bindings:**
- Pattern: `camelCase` for local variables (e.g., `caddyWithTailscale`, `monitoredUnits`)

**NixOS Users/Groups:**
- Pattern: `lowercase` (e.g., `jellyfin`, `caddy`, `mosquitto`, `bdhill`)

## Where to Add New Code

**New Service/Feature:**
1. **Create module directory:** `modules/CATEGORY/SERVICENAME.nix`
2. **Add to module default.nix:** Update `modules/CATEGORY/default.nix` imports
3. **Implement service config:** Follow existing patterns in `modules/media/jellyfin.nix`, `modules/gateway/caddy.nix`
4. **Enable on host:** Add to appropriate `hosts/HOSTNAME/configuration.nix`

Example for new media service:
- Create: `modules/media/newsvc.nix` with `services.newsvc` config
- Update: `modules/media/default.nix` to import `./newsvc.nix`
- Enable: In `hosts/ser8/configuration.nix`, set `services.newsvc.enable = true`

**New Host:**
1. Create directory: `hosts/NEWHOSTNAME/`
2. Create required files:
   - `configuration.nix` (imports hardware, service enables)
   - `hardware-configuration.nix` (generated by installer)
   - `disko-config.nix` (if using declarative disk layout)
3. Add to `flake.nix`:
   ```nix
   newhostname = mkSystem {
     hostname = "newhostname";
     modules = [ ./modules/dns ]; # Add appropriate modules
   };
   ```
4. Add to `deploy.yaml` with IP and user metadata
5. Create secrets file: `secrets/newhostname.yaml`

**New Module (Shared Functionality):**
1. Create: `modules/CATEGORY/` directory
2. Create: `modules/CATEGORY/default.nix` barrel
3. Create: `modules/CATEGORY/feature.nix` implementation files
4. Follow pattern:
   - Use `lib.mkOption` for custom options
   - Use `lib.mkIf config.MODULE.enable` for conditional config
   - Define `options.MODULE.*` for all configuration knobs
5. Reference in flake.nix or host configuration

**New Prometheus Metric/Dashboard:**
1. **For exporter:** Update `modules/servers/monitoring.nix` to enable new exporter
2. **For scrape config:** Add job to `modules/gateway/prometheus.nix` scrapeConfigs
3. **For dashboard:** Add JSON to `dashboards/` directory and reference in `modules/gateway/grafana.nix`

**New Firewall Rule:**
- Add to host's `configuration.nix` in `networking.firewall.allowedTCPPorts` or `.allowedUDPPorts`
- Or in service module's `networking.firewall.allowedTCPPorts` (opens by default if `openFirewall = true`)

## Special Directories

**.planning/codebase/:**
- Purpose: GSD-generated analysis documents
- Generated: Via `/gsd:map-codebase` tool
- Committed: Yes, used by `/gsd:plan-phase` and `/gsd:execute-phase`
- Contents: ARCHITECTURE.md, STRUCTURE.md, CONVENTIONS.md, TESTING.md, CONCERNS.md, STACK.md, INTEGRATIONS.md

**dashboards/:**
- Purpose: Grafana dashboard JSON files
- Generated: Pre-built from grafana.com (IDs 1860, 7845, 3662)
- Committed: Yes
- Processing: Dashboard `${DS_*}` variables replaced at deploy time in `modules/gateway/grafana.nix`

**logs/:**
- Purpose: Build and deployment logs
- Generated: Via `scripts/nixos-rebuild.sh` during deployments
- Committed: Yes (for audit/debugging)

**secrets/:**
- Purpose: SOPS-encrypted credentials
- Generated: Via `make sops-*` commands for new keys/secrets
- Committed: Yes (SOPS encryption keeps values safe)
- Contents: `.yaml` files with encrypted values; never contains plaintext secrets

**experimental/:**
- Purpose: Work-in-progress features not yet integrated
- Generated: Ad-hoc during development
- Committed: Yes
- Status: Not included in any host configuration (not loaded by flake.nix)

---

*Structure analysis: 2026-02-09*
