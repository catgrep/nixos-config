# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is a NixOS homelab configuration using flakes that manages multiple hosts including x86_64 systems (ser8, firebat) and ARM Raspberry Pi devices (pi4, pi5). The configuration uses a modular architecture with shared common modules and host-specific configurations.

## Key Architecture

### Host Architecture
- **ser8** (192.168.68.65): Main media server with Jellyfin, Sonarr, Radarr, Prowlarr, qBittorrent, SABnzbd, FlareSolverr, AllDebrid-proxy, Frigate NVR, Home Assistant
  - Uses ZFS for storage with automatic snapshots and scrubbing
  - MergerFS for unified media view across multiple disks
  - NordVPN integration for anonymized torrenting
  - SABnzbd for Usenet downloads with category-based organization
  - Hardware acceleration for media transcoding (AMD VA-API with Radeon 780M)
  - Frigate NVR for security cameras with CPU-based object detection
  - Home Assistant for home automation with MQTT integration
  - Media stack orchestration via 3 systemd services:
    - `media-config.service`: Deploys all service configurations from SOPS templates
    - `servarrs-setup.service`: Connects Prowlarr to Sonarr/Radarr for indexer sync
    - `download-clients-setup.service`: Connects qBittorrent/SABnzbd to all arr services
  - API key sanitization in all systemd logs prevents secrets exposure
- **firebat** (192.168.68.63): Gateway/reverse proxy with Caddy, Grafana, Prometheus
  - Manages SSL certificates using Caddy's local CA
  - Prometheus monitoring for all hosts
  - Grafana dashboards for visualization
- **pi4** (192.168.68.56): DNS server with AdGuard Home
  - Primary DNS server for the network
- **pi5** (192.168.0.110): Additional Raspberry Pi for experiments

### Module System
- `modules/common/`: Shared configuration (networking, SSH, users, packages, neovim, tmux, banner)
- `modules/servers/`: Server-specific modules (backup, monitoring, security)
- `modules/media/`: Media services (Jellyfin, Sonarr, Radarr, Prowlarr, qBittorrent, SABnzbd, Transmission, AllDebrid-proxy)
- `modules/gateway/`: Reverse proxy and monitoring (Caddy, Grafana, Prometheus)
- `modules/dns/`: DNS services (AdGuard Home, users management)
- `modules/raspberrypi/`: Raspberry Pi specific configurations (base, installer, usb-installer)
- `modules/nordvpn/`: NordVPN WireGuard integration with network namespace isolation
- `modules/automation/`: Home automation services (Home Assistant, Frigate NVR)
- `modules/development/`: Development tools (Gerrit - planned)

Host configurations are located in `hosts/HOSTNAME/` with each containing:
- `configuration.nix`: Main host configuration
- `hardware-configuration.nix`: Hardware-specific settings
- `disko-config.nix`: Disk partitioning (where applicable)
- `impermanence.nix`: Impermanence configuration (where applicable)

### Secrets Management
Uses SOPS for managing secrets with age encryption. Host keys are stored in `secrets/keys/hosts/` and user keys in `secrets/keys/users/`.

- `secrets/HOST.yaml`: Host-specific secrets (only that host can decrypt)
- `secrets/shared.yaml`: Shared secrets readable by all hosts (e.g., `tailscale_authkey`)

The dual secret declaration pattern allows the same yaml key to be decrypted with different file permissions (e.g., root:root for tailscale daemon, caddy:caddy for Caddy service).

## Essential Commands

### Development Environment
```bash
make dev                    # Enter Nix development shell
make update                 # Update flake inputs
make check                  # Validate flake and all host configurations
make fmt                    # Format all Nix files with nixfmt
```

### Host Management
```bash
make status                 # Check connectivity to all hosts
make list-hosts            # Show all hosts with metadata
make info-HOST             # Show specific host information
make ssh-HOST              # SSH into host
```

### Deployment
```bash
make build-HOST            # Build configuration without activation
make test-HOST             # Build and temporarily activate (reverts on reboot)
make switch-HOST           # Build, activate, and make boot default
make apply-HOST            # Full deployment: test + switch + reboot + smoketests
make rollback-HOST         # Roll back to previous configuration
```

### Raspberry Pi Management
```bash
make HOST-installer        # Build ARM64 SD card image using Docker
make write-sd-HOST DEVICE=/dev/rdiskX  # Write image to SD card
```

### Secrets Management (SOPS)
```bash
make sops-init             # Initialize SOPS configuration
make sops-add-user         # Add user to SOPS
make sops-add-host-keys    # Add host keys to SOPS
make sops-add-shared-secrets  # Add shared secrets rule for all hosts
make sops-edit-HOST        # Edit secrets for specific host
make sops-edit-shared      # Edit shared secrets (all hosts can read)
make sops-status           # Check SOPS status
```

### Home Manager
```bash
make home-switch           # Apply home-manager configuration
```

## Build System Details

The Makefile is the primary interface that wraps around:
- `scripts/nixos-rebuild.sh`: Handles remote builds and deployments
- Host metadata in `deploy.yaml`: Contains IP addresses, users, and deployment settings
- Flake configuration in `flake.nix`: Defines all system configurations

Build targets support "all" to operate on all hosts (e.g., `make switch-all`).

## Important Files

- `flake.nix`: Main flake configuration defining all hosts and modules
- `deploy.yaml`: Host deployment metadata (IPs, users, build settings)
- `Makefile`: Primary build and deployment interface
- `scripts/nixos-rebuild.sh`: Remote deployment wrapper
- `secrets/`: SOPS-encrypted secrets for hosts
- `home-manager/`: Separate home-manager flake configuration

## Development Notes

- All Nix files should be formatted with `nixfmt-rfc-style`
- The repository uses GPL-3.0-or-later licensing
- Hosts are accessible via mDNS (e.g., `ser8.local` and `ser8.internal`)
- ser8 uses ZFS with "Erase Your Darlings" pattern - root filesystem is rolled back on boot
- Raspberry Pi hosts may require special handling for boot firmware mounting
- Users are defined in `users/` directory with centralized management
- Media services on ser8 use a shared `media` group for permissions
- qBittorrent runs in NordVPN network namespace for anonymization
- Transmission has been replaced by qBittorrent as the primary torrent client
- All hosts auto-authenticate to Tailscale on boot using shared `tailscale_authkey`

## Frigate NVR Configuration

Frigate runs on ser8 for security camera management:
- Camera credentials stored in SOPS (`frigate_cam_user`, `frigate_cam_pass`)
- Uses Frigate's environment variable substitution: `{FRIGATE_CAM_USER}`, `{FRIGATE_CAM_PASS}` in RTSP URLs
- TP-Link Tapo cameras require TCP transport (`preset-rtsp-restream`) for WiFi stability
- Auth disabled since Frigate is behind Tailscale
- Camera recordings stored on ZFS backup pool (`/mnt/cameras`)
- Reference for Tapo camera stability: https://github.com/blakeblackshear/frigate/discussions/14888

## Service Access

Services are accessible through the Caddy reverse proxy on the firebat host:
- `jellyfin.vofi.app`, `jellyfin.vofi` - Jellyfin media server
- `sonarr.vofi` - Sonarr TV show management
- `radarr.vofi` - Radarr movie management
- `prowlarr.vofi` - Prowlarr indexer management
- `torrent.vofi` - qBittorrent web UI
- `sabnzbd.vofi` - SABnzbd Usenet download client
- `frigate.vofi` - Frigate NVR security camera system
- `hass.vofi` - Home Assistant automation
- `grafana.vofi.app` - Grafana monitoring dashboards
- `prometheus.vofi.app` - Prometheus metrics
- `adguard.internal` - AdGuard Home DNS management (internal only)

Note: `.vofi.app` domains use Caddy's local CA for SSL certificates.

Services are also accessible via Tailscale MagicDNS (e.g., `frigate.shad-bangus.ts.net`, `hass.shad-bangus.ts.net`).

## Testing

Each host can have smoketests defined in `deploy.yaml`. Gateway, DNS, and media modules have comprehensive test suites in `scripts/smoketests/`.

## Debugging Tips

### Testing Packages on Remote Hosts

Use `nix-shell` to try out packages or commands on a remote host before adding them to the configuration:

```bash
# Test a single command with a package
ssh bdhill@ser8 nix-shell -p libva-utils --command vainfo

# Interactive shell with multiple packages
ssh bdhill@ser8 nix-shell -p htop iotop

# Example: verify VA-API hardware acceleration
ssh bdhill@ser8 nix-shell -p libva-utils --command "vainfo 2>&1 | grep -E 'Driver|profile'"
```

This avoids the full rebuild/switch cycle when debugging or verifying hardware capabilities.
