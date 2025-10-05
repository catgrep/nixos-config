# NixOS Homelab Configuration

A comprehensive NixOS configuration for managing a homelab infrastructure with media services, monitoring, and DNS management.

## Infrastructure Overview

- **ser8** (192.168.68.65) - Media server with Jellyfin, *arr stack, and torrent management
- **firebat** (192.168.68.63) - Gateway with Caddy reverse proxy, Prometheus, and Grafana
- **pi4** (192.168.68.56) - DNS server running AdGuard Home
- **pi5** (192.168.0.110) - Experimental Raspberry Pi setup

## Quick Start

Enter the development environment:
```sh
make dev
```

Deploy to a host:
```sh
make switch-ser8      # Deploy to ser8
make switch-all       # Deploy to all hosts
```

## Home-Manager

Run
``` sh
nix run home-manager -- switch --flake ./home-manager
# or
make home-switch
```

## Development

This repo uses Determinate System and the flake was bootstrapped with:
``` sh
nix run "https://flakehub.com/f/DeterminateSystems/fh/*" -- init
```

### Prerequisites

You will need:
1) `nix` package manager for installing `nix` packages.
2) `nixfmt` for formatting `nix` files.

Install nix:
``` sh
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
```

Test with:
``` sh
echo "Hello Nix" | nix run "https://flakehub.com/f/NixOS/nixpkgs/*#charasay" say
```

Install `nixfmt`:

``` sh
nix-env -i -f https://github.com/NixOS/nixfmt/archive/master.tar.gz
```

Add `/etc/nix/nix.custom.conf` and:
1) add builder machines to `/etc/nix/machines`
2) add any `extra-substituters`

See `./etc/nix` for examples.

After updating config files, restart the nix daemon with:
```
sudo launchctl kickstart -k system/org.nixos.nix-daemon
```

## Services

Access services through the gateway reverse proxy:
- **Media Services**:
  - `jellyfin.vofi.app` - Media streaming
  - `sonarr.vofi` - TV show management
  - `radarr.vofi` - Movie management
  - `prowlarr.vofi` - Indexer management
  - `torrent.vofi` - qBittorrent web UI
- **Monitoring**:
  - `grafana.vofi.app` - Metrics dashboards
  - `prometheus.vofi.app` - Prometheus metrics
- **Internal**:
  - `adguard.internal` - AdGuard Home DNS

## Accessing Media Drive over SMB

### MacOS

Go to `Finder` > `Go` > `Connect to Server` (or `Command + K`)

Type in:
```
smb://media@ser8.local
```

And login as the `media` user.


## DNS Configuration

The homelab uses AdGuard Home on pi4 as the primary DNS server. Configure your router's DHCP to use `192.168.68.56` as the DNS server.

### Testing DNS Setup

```
Client → DHCP Request → TP-Link Deco
TP-Link Deco -> DHCP Response with Adguard DNS address "Here's IP 192.168.68.X, use 192.168.68.56 for DNS" -> Client
Client -> DNS Query "jellyfin.vofi.app" -> Adguard
AdGuard → DNS Response "Redirect to gateway" → Client
```

Verify after configuring your router:
```sh
# Check DNS server
ipconfig getpacket en0 | grep domain_name_server

# Clear manual DNS entries if needed
networksetup -getdnsservers Wi-Fi
sudo networksetup -setdnsservers Wi-Fi empty
```

## Key Features

- **ZFS Storage**: ser8 uses ZFS with automatic snapshots and weekly scrubs
- **Impermanence**: Root filesystem rollback on boot for stateless operation
- **VPN Integration**: qBittorrent runs in isolated NordVPN namespace
- **Monitoring**: Prometheus + Grafana for comprehensive metrics
- **Secrets Management**: SOPS with age encryption for sensitive data
- **Multi-Architecture**: Supports x86_64 and ARM (Raspberry Pi)

## Documentation

- `CLAUDE.md` - Detailed architecture and command reference
- `TODO.md` - Project roadmap and task tracking
- `deploy.yaml` - Host configuration metadata

## License

GPL-3.0-or-later
