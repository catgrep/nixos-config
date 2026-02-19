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

## License

GPL-3.0-or-later
