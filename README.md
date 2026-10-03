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

Caddy on firebat serves the routes defined in [modules/gateway/Caddyfile](modules/gateway/Caddyfile).
LAN names use Caddy's local CA, and each Tailscale node is reached as `https://NODE.shad-bangus.ts.net` with a Tailscale certificate.

| Service | LAN name | Tailscale node |
|---------|----------|----------------|
| Jellyfin | `jellyfin.vofi`, `jellyfin.vofi.app` | `jellyfin` |
| Sonarr, Radarr, Bazarr, Prowlarr, SABnzbd, NZBGet, torrent | `NAME.vofi` | `NAME` |
| Frigate, Home Assistant | `frigate.vofi`, `hass.vofi` | `frigate`, `hass` |
| Grafana | `grafana.vofi.app` | `grafana` |
| Prometheus | `prometheus.vofi.app` | `prom` |
| Alertmanager | none | `alertmanager` |
| Mealie, Homebox, Actual, Donetick | none | `NAME` |

AdGuard Home on pi4 has no gateway route; its web interface is reached directly at `http://192.168.68.56:3000`.

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
[multiverse.lock](multiverse.lock) selects explicit nixpkgs applications and tools for the shell, the hosts, and the Mac's Home Manager and nix-darwin configurations.
Edit that file only through `mvs lock` commands or `hm`, never by hand.

Refresh the index, inspect available versions, and change a pin from a newly entered shell:

``` sh
nix flake update mvs
nix develop -c mvs query versions prek
nix develop -c mvs lock status
```

Use `mvs lock add NAME@VERSION` to select a version and `mvs lock update NAME` to refresh its recipe within the recorded constraint.
An exact version constraint does not automatically opt into newer versions.
The root flake's Home Manager and nix-darwin outputs for the Mac read the same lock file through the `pinned` special argument, and `hm add` pins a tool there and installs it in one step.

Pins include their dependency closures, so matching application versions can still have different builds.
Do not automatically run `mvs lock minimize`: it can move packages to older recipes and dependencies without changing their version numbers.
Kernel/ZFS, systemd, Pi boot tools, and graphics drivers remain coupled to the host baseline.
Frigate, Home Assistant, Nginx, and Caddy retain compatible build tools, interpreters, or modules from the application's locked revision.
Local derivations and their build dependencies remain governed by the flake inputs.

## License

GPL-3.0-or-later
