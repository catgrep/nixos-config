# Repository Guide

This file provides agent-agnostic guidance for working in this repository.
`AGENTS.md` is a symlink to this file so tools that recognize either filename receive the same instructions.

## Repository Overview

This repository is a NixOS homelab flake built around NixOS 25.11.
It manages two x86_64 systems and two Raspberry Pi systems through shared modules and host-specific configuration.
The root flake also exports development shells, kexec installers, service metadata, package inspection data, and the local `sagent` tool.

## Host Architecture

| Host | Address | Role | Configuration |
|------|---------|------|---------------|
| `ser8` | `192.168.68.65` | Media, storage, and automation server | `hosts/ser8/` |
| `firebat` | `192.168.68.63` | Gateway, reverse proxy, and monitoring server | `hosts/firebat/` |
| `pi4` | `192.168.68.56` | AdGuard Home DNS and DHCP server | `hosts/pi4/` |
| `pi5` | `192.168.0.110` | General-purpose Raspberry Pi 5 | `hosts/pi5/` |

`deploy.yaml` is the source of truth for deployment addresses, users, tags, and smoketest commands.
The `ser8` and `firebat` hosts use disko and impermanence.
The Pi hosts build from upstream `nixpkgs` with the pinned `nixos-hardware` board modules, and `pi5` also uses disko.

### ser8

The media host imports `modules/media/`, `modules/nordvpn/`, and `modules/automation/`.
It runs Jellyfin, Sonarr, Radarr, Prowlarr, qBittorrent, SABnzbd, NZBGet, FlareSolverr, Frigate, Home Assistant, Mosquitto, and related exporters.
qBittorrent runs in the NordVPN network namespace and is exposed locally through nginx.
The host uses ZFS for the system and backup pool, MergerFS for `/mnt/media`, Samba for file sharing, and AMD hardware acceleration for media workloads.
Media configuration and service integration are coordinated by systemd units defined in `hosts/ser8/media.nix`.

### firebat

The gateway host imports `modules/gateway/`.
It runs Caddy, Prometheus, Grafana, the Prometheus blackbox exporter, and Tailscale-related proxying.
Grafana dashboards are stored as version-controlled JSON in `dashboards/` and provisioned by `modules/gateway/grafana.nix`.
Reverse proxy routes are defined in `modules/gateway/Caddyfile`.

### pi4 and pi5

`pi4` imports `modules/dns/` and runs AdGuard Home plus its Prometheus exporter.
`pi5` currently has base server configuration, Raspberry Pi boot configuration, and disk layout but no role-specific module group.

## Repository Layout

- `.claude/` contains repository-local agent configuration and historical planning artifacts.
- `.planning/` contains GSD project planning state.
- `dashboards/` contains provisioned Grafana dashboard JSON.
- `etc/` contains repository-managed Nix daemon configuration.
- `experimental/` contains work that is not part of the active host flake.
- `home-manager/` contains the separate Home Manager flake.
- `hosts/` contains host-specific NixOS configuration.
- `modules/` contains reusable NixOS modules grouped by role.
- `overlays/` contains package overrides.
- `scripts/` contains operational and validation scripts.
- `secrets/` contains SOPS-encrypted secrets and public key material.
- `tools/` contains repository-local tooling and subflakes.
- `users/` contains centralized user configuration.

Prefer small modules imported through the relevant directory's `default.nix`.
Do not assume that every module file is active because some implementations remain unimported or commented out.

## Development Commands

Enter the development shell before running repository tooling:

```bash
make dev
```

The shell includes `nixfmt-rfc-style`, `statix`, `shellcheck`, `sops`, `yq`, `caddy`, `nixos-anywhere`, `sb`, and `treehouse`.

Use these commands for routine validation:

```bash
make fmt                    # Format all Nix files
make fmt-caddy              # Format and validate the Caddyfile
make check                  # Run flake checks, statix, and dry-run host builds
make flake-info             # Show exported flake outputs
```

`make check` is the main repository-wide validation command.
For focused work, validate the affected host or file first, then run broader checks when practical.

## Host and Deployment Commands

Targets use the host as a suffix:

```bash
make list-hosts
make info-ser8
make status
make ssh-ser8
make build-ser8
make dry-activate-ser8
make test-ser8
make smoketests-ser8
```

`make test-HOST` activates a configuration temporarily and is safer than switching it into the boot default.
`make switch-HOST`, `make reboot-HOST`, and `make apply-HOST` affect live systems and require explicit intent.
Interactive deployment commands prompt by default, and `NO_CONFIRM=true` must only be used for intentional non-interactive operations.
The `rollback-HOST` target is currently a placeholder and must not be presented as functional.

Package and service metadata can be inspected without deploying:

```bash
make pkg-list-ser8
make pkg-list-ser8 CATEGORY=services
make pkg-version-ser8 PKG=jellyfin
make pkg-eval-ser8 EXPR='config.services.jellyfin.enable'
nix eval '.#enabledServices.ser8' --json
nix eval '.#servicePackages.ser8' --json
nix eval '.#packageInfo.ser8' --json
```

Build the Arm64 kexec installer with `make aarch64-kexec`.
Raspberry Pi bootstrap-image and device-write targets do not currently exist and must not be presented as available.

## Coding Conventions

Format Nix with `nixfmt-rfc-style` and do not hand-align against formatter output.
Keep module filenames lowercase and kebab-case.
Preserve `SPDX-License-Identifier: GPL-3.0-or-later` headers where present.
Keep shell scripts compatible with their declared interpreter and start new Bash scripts with `set -euo pipefail`.
Run `shellcheck` and `shfmt -d` for changed shell scripts.
Use `sb` for structure-aware repository exploration before reading large files in full.
Use `rg` and `fd` for text and filename searches.
Use `treehouse get --lease` when isolated worktree execution is needed, and return the lease with `treehouse return <path>`.

## Testing Expectations

Test behavior at the narrowest relevant level before running repository-wide checks.
Add or update smoketests when changing deployed services, networking, DNS, gateway behavior, monitoring, or media automation.
Keep area entry points named `all.sh` when they are referenced by `deploy.yaml`.
Use descriptive `test-*.sh` names for individual smoketests.
Treat warnings from formatters, linters, evaluators, and tests as failures to resolve.

## Secrets and Safety

Never commit plaintext credentials, decrypted SOPS content, private keys, or generated access tokens.
Use the provided targets instead of editing encrypted data through ad hoc commands:

```bash
make sops-status
make sops-edit-ser8
make sops-edit-shared
make sops-gen-api-key
make sops-gen-hash
make sops-gen-hash-qbittorrent
```

Host-specific encrypted data lives in `secrets/<host>.yaml`, and shared encrypted data lives in `secrets/shared.yaml`.
SOPS age identities come from SSH host keys, with persistent hosts reading keys from `/persist/etc/ssh/`.
Do not expose secret values in logs, test output, documentation, or diffs.

## Change and Review Guidance

Use short, scoped commit subjects in imperative form, such as `media: enable exporter` or `flake: update input`.
Keep each commit to one logical change and do not add an agent as a co-author.
Before committing, review the diff, run relevant tests, and resolve all warnings.
Do not push directly to `main`.
Pull requests should identify affected hosts and modules, list validation performed, and call out required deployment or secret steps.
Include dashboard screenshots or exported JSON diffs when Grafana assets change.
