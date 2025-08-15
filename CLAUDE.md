# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is a NixOS homelab configuration using flakes that manages multiple hosts including x86_64 systems (beelink-homelab, firebat) and ARM Raspberry Pi devices (pi4, pi5). The configuration uses a modular architecture with shared common modules and host-specific configurations.

## Key Architecture

### Host Architecture
- **beelink-homelab**: Main media server with Jellyfin, Sonarr, Radarr, Transmission
- **firebat**: Gateway/reverse proxy with Caddy, Grafana, Prometheus
- **pi4**: DNS server with AdGuard Home
- **pi5** (192.168.0.110): Additional Raspberry Pi for experiments

### Module System
- `modules/common/`: Shared configuration (networking, SSH, users, packages)
- `modules/servers/`: Server-specific modules (backup, monitoring, security)
- `modules/media/`: Media services (Jellyfin, Sonarr, Radarr, Transmission)
- `modules/gateway/`: Reverse proxy and monitoring (Caddy, Grafana, Prometheus)
- `modules/dns/`: DNS services (AdGuard Home)
- `modules/raspberrypi/`: Raspberry Pi specific configurations

Host configurations are located in `hosts/HOSTNAME/` with each containing:
- `configuration.nix`: Main host configuration
- `hardware-configuration.nix`: Hardware-specific settings
- `disko-config.nix`: Disk partitioning (where applicable)
- `impermanence.nix`: Impermanence configuration (where applicable)

### Secrets Management
Uses SOPS for managing secrets with age encryption. Host keys are stored in `secrets/keys/hosts/` and user keys in `secrets/keys/users/`.

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
make sops-edit-HOST        # Edit secrets for specific host
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
- Hosts are accessible via mDNS (e.g., `beelink-homelab.local`)
- Some hosts use impermanence for stateless root filesystems
- Raspberry Pi hosts may require special handling for boot firmware mounting

## Testing

Each host can have smoketests defined in `deploy.yaml`. Gateway and DNS modules have comprehensive test suites in `scripts/smoketests/`.
