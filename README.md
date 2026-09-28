# NixOS Homelab Configuration

A comprehensive NixOS configuration for managing my homelab infrastructure with smart home, media, monitoring,
and DNS management services.

- **ZFS Storage**: ser8 uses ZFS with automatic snapshots and weekly scrubs
- **Impermanence**: Root filesystem rollback on boot for stateless operation
- **Tailscale VPN Integration**: Uses caddy with tailscale plugin for convenient MagicDNS service access
- **Monitoring**: Prometheus + Grafana for comprehensive metrics
- **Secrets Management**: SOPS with age encryption for sensitive data
- **Multi-Architecture**: Supports x86_64 and ARM (Raspberry Pi)

This was my first experience with NixOS. This repo will eventually be migrated to use:
- https://github.com/Doc-Steve/dendritic-design-with-flake-parts
- https://github.com/mightyiam/dendritic

## Infrastructure Overview

- **ser8** - Media server with Jellyfin, *arr stack, home assistant, frigate
- **firebat** - Gateway with Caddy reverse proxy, Prometheus, and Grafana
- **pi4** - DNS server running AdGuard Home
- **pi5** - Experimental Raspberry Pi setup

## Services

Access services through the gateway reverse proxy:
- **Media Services**:
  - `jellyfin` - Media streaming
  - `sonarr` - TV show management
  - `radarr` - Movie management
  - `prowlarr` - Indexer management
  - `frigate` - NVR management and object detection with YOLOv8s
  - `home-assistant` - IoT / smart devices management
- **Monitoring**:
  - `grafana` - Metrics dashboards
  - `prometheus` - Prometheus metrics
- **Internal**:
  - `adguard` - AdGuard Home DNS

## Development

This repo uses Determinate System and the flake was bootstrapped with:
``` sh
nix run "https://flakehub.com/f/DeterminateSystems/fh/*" -- init
```

Enter the development environment with:
``` sh
make dev
```

See help with:
``` sh
make
```

### Dependency policy

[omniflake.nix](omniflake.nix) selects third-party flakes with their recorded upstream inputs and documents the exceptions and caveats.
Home Manager and nixos-hardware retain their release/commit selections, and mvs remains a direct input so its index can be refreshed independently.

[dev.nix](dev.nix) defines the development shell, and [checks.nix](checks.nix) defines portable and Linux VM checks.
[multiverse.lock](multiverse.lock) selects explicit nixpkgs applications and tools for the shell, hosts, and standalone Home Manager configuration.
Only edit that file through `mvs lock` commands.

Refresh the index, inspect available versions, and change a pin from a newly entered shell:

``` sh
nix flake update mvs
nix develop -c mvs query versions prek
nix develop -c mvs lock status
```

Use `mvs lock add NAME@VERSION` to select a version and `mvs lock update NAME` to refresh its recipe within the recorded constraint.
An exact version constraint does not automatically opt into newer versions.
The standalone Home Manager flake shares the lock file; refresh its reader with `nix flake update mvs --flake ./home-manager` when new pins require newer index data.

Pins include their dependency closures, so matching application versions can still have different builds.
Do not automatically run `mvs lock minimize`: it can move packages to older recipes and dependencies without changing their version numbers.
Kernel/ZFS, systemd, Pi boot tools, and graphics drivers remain coupled to the host baseline.
Frigate, Home Assistant, Nginx, and Caddy retain compatible build tools, interpreters, or modules from the application's locked revision.
Local derivations and their build dependencies remain governed by the flake inputs.

## License

GPL-3.0-or-later
