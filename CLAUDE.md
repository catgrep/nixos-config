# Repository Guide

This file provides agent-agnostic guidance for working in this repository.
`AGENTS.md` is a symlink to this file so tools that recognize either filename receive the same instructions.

## Repository Overview

This repository is a NixOS homelab flake built around NixOS 26.05.
It manages two x86_64 systems and two Raspberry Pi systems through shared modules and host-specific configuration.
It also manages the `bob-mac` workstation through a standalone Home Manager configuration and a nix-darwin system configuration.
Every machine builds the same user home from `home-manager/users/bobby.nix`, with platform differences gated inside the modules.
The root flake also exports development shells, kexec installers, service metadata, package inspection data, the `hm` and `mvs` packages, and the local `sagent` tool.
Third-party flake selections and their dependency policies live in `omniflake.nix`.
Development shells and checks live in `dev.nix` and `checks.nix`.

## Host Architecture

| Host | Address | Role | Configuration |
|------|---------|------|---------------|
| `ser8` | `192.168.68.65` | Media, storage, and automation server | `hosts/ser8/` |
| `firebat` | `192.168.68.63` | Gateway, reverse proxy, and monitoring server | `hosts/firebat/` |
| `pi4` | `192.168.68.56` | AdGuard Home DNS and DHCP server | `hosts/pi4/` |
| `pi5` | `192.168.0.110` | General-purpose Raspberry Pi 5 | `hosts/pi5/` |
| `bob-mac` | local | Workstation with standalone Home Manager and nix-darwin | `home-manager/`, `darwin/` |

`deploy.yaml` is the source of truth for deployment addresses, users, tags, and smoketest commands.
The `ser8` and `firebat` hosts use disko and impermanence.
The Pi hosts build from upstream `nixpkgs` with the pinned `nixos-hardware` board modules, and `pi5` also uses disko.
The interactive account on every host is `bobby` (uid 1000), defined in `modules/common/users.nix`.
`home-manager.users.bobby` in `flake.nix` imports the same user file the Mac uses and passes the locked package set as the `pinned` special argument.

### ser8

The media host's role-specific configuration lives in `hosts/ser8/media/`, `hosts/ser8/household/`, and `hosts/ser8/backup/`, with home automation services from `modules/automation/`.
It runs Jellyfin, Sonarr, Radarr, Bazarr, Prowlarr, SABnzbd, NZBGet, FlareSolverr, Frigate, Home Assistant, Mosquitto, household apps (Actual, Donetick, Homebox, Mealie) backed by PostgreSQL, and related exporters.
The nightly backup engine in `hosts/ser8/backup/` snapshots, replicates, and verifies `rpool/safe/persist`; see its `README.md`.
The host uses ZFS for all persistent storage: `rpool` (system disk, impermanence rollback), `backup` (RAID-Z2, archives and camera recordings), `media` (two-disk mirror, unified library mount at `/mnt/media`), and `rpool/safe/downloads` (NVMe staging with a hard quota, mounted at `/mnt/downloads`, used by SABnzbd and NZBGet before completed downloads are imported into the mirror).
Samba exposes `/mnt/media` for shared access, and AMD hardware acceleration handles media workloads.
Media configuration and service integration are coordinated by systemd units defined in `hosts/ser8/media/orchestration.nix`.

### firebat

The gateway host imports `modules/gateway/`.
It runs Caddy, Prometheus, Grafana, the Prometheus blackbox exporter, and Tailscale-related proxying.
Grafana dashboards are stored as version-controlled JSON in `dashboards/` and provisioned by `modules/gateway/grafana.nix`.
Reverse proxy routes are defined in `modules/gateway/Caddyfile`.

### pi4 and pi5

`pi4` imports `modules/dns/` and runs AdGuard Home plus its Prometheus exporter.
`pi5` currently has base server configuration, Raspberry Pi boot configuration, and disk layout but no role-specific module group.

### bob-mac

The Mac is the workstation and not a deployment target, so it has no `deploy.yaml` entry and no `make` host targets.
`homeConfigurations."bobby@bob-mac"` is its standalone Home Manager configuration, built from the same user file and modules as the hosts.
Platform differences live inside the modules they affect, gated on `pkgs.stdenv.hostPlatform.isDarwin`, and `home-manager/darwin/` holds the Mac-only additions.
`darwinConfigurations."bob-mac"` is the nix-darwin system layer in `darwin/`: Homebrew casks and formulae from `darwin/homebrew/`, and yabai, skhd, and borders as launchd agents from `darwin/services.nix`.
It leaves Nix itself unmanaged (`nix.enable = false`) because Determinate Nix owns `/etc/nix/nix.conf` and the daemon.
Home Manager stays a separate layer, so `nh home switch` and `nh darwin switch` are independent steps.

## Repository Layout

- `.claude/` contains repository-local agent configuration and historical planning artifacts.
- `.planning/` contains GSD project planning state.
- `darwin/` contains the nix-darwin system configuration for `bob-mac`, including the Homebrew lists `hm` owns.
- `dashboards/` contains provisioned Grafana dashboard JSON.
- `etc/` contains repository-managed Nix daemon configuration.
- `experimental/` contains work that is not part of the active host flake.
- `home-manager/` contains the shared Home Manager modules, the single user file, and the tool lists `hm` owns.
- `hosts/` contains host-specific NixOS configuration.
- `modules/` contains reusable NixOS modules grouped by role.
- `overlays/` contains package overrides.
- `scripts/` contains operational and validation scripts.
- `secrets/` contains SOPS-encrypted secrets and public key material.
- `tools/` contains repository-local tooling: the `hm` Go module and the `sagent` subflake.

Prefer small modules imported through the relevant directory's `default.nix`.
Do not assume that every module file is active because some implementations remain unimported or commented out.

## Development Commands

Enter the development shell before running repository tooling:

```bash
make dev
```

The shell includes `nixfmt-rfc-style`, `statix`, `shellcheck`, `sops`, `yq`, `caddy`, `nixos-anywhere`, `sb`, `treehouse`, and `mvs`.

Use these commands for routine validation:

```bash
make fmt                    # Format all Nix files
make fmt-caddy              # Format and validate the Caddyfile
make check                  # Run flake checks, statix, and dry-run host builds
make flake-info             # Show exported flake outputs
```

`make check` is the main repository-wide validation command.
For focused work, validate the affected host or file first, then run broader checks when practical.
On the Mac, `nix flake check` also builds `hm` and the `bob-mac` nix-darwin system, so a broken Homebrew list or launchd service fails `make check`.

### Home Manager, nix-darwin, and hm

`make home-switch` runs `nh home switch .`, which builds and activates the Mac's Home Manager configuration.
`nh darwin switch` builds and activates the Mac's nix-darwin system layer.
`programs.nh.flake` in `home-manager/modules/nh.nix` sets `NH_FLAKE` to this repository, so `nh` and `hm` work from any directory.
A Home Manager switch is user-level and one generation away from rollback.
`nh darwin switch` changes system files, Homebrew installs, and launchd agents, and `hm brew cleanup --force` uninstalls software, so both require explicit intent.

`hm` (`tools/hm`) wraps `mvs lock`, `nh`, and the Homebrew lists so that adding, removing, or updating a tool is one command.
Home Manager installs it, and `nix run .#hm -- --help` runs the same binary from the flake before the first switch.
`man hm` is the full reference, and `hm help` prints the same text.

- `hm add NAME[@VERSION]` pins a nixpkgs attribute in `multiverse.lock`, inserts it in `home-manager/packages.nix`, and runs `nh home switch`.
- `hm add --cask NAME` and `hm add --brew NAME` append to `darwin/homebrew/casks.nix` or `brews.nix` and run `nh darwin switch`.
- `hm add --go MODULE@VERSION`, `hm add --uv PACKAGE==VERSION`, and `hm add --cargo CRATE@VERSION` append to the matching tool list and run `hm sync` for it.
- `hm rm NAME` removes the name from whichever list holds it and switches; `--prune` also drops a pin that nothing else in the repository names.
- `hm up [ATTR]` runs `nix flake update mvs`, moves the named pin or every `packages.nix` pin, and switches; `--repo` allows a host or dev-shell pin.
- `hm sync [go|uv|cargo]` installs the tools the lists declare that are missing or at another version; `--force` reinstalls every declared entry.
- `hm switch [home|darwin|all]` runs `nh home switch`, `nh darwin switch`, or both.
- `hm list` shows every installed package with its source tag: `pinned`, `nixpkgs`, `custom`, `cask`, `brew`, `go`, `cargo`, `uv`, or `native`.
- `hm status` reports pins behind the index, the `mvs lock minimize --check` result, uncommitted flake files, and the last run.
- `hm doctor` reports PATH entries that shadow Nix binaries and tools that no list declares.
- `hm try ATTR [-- COMMAND...]` runs a nixpkgs package once without installing it.
- `hm clean [--keep N]` removes old Home Manager generations with `nh clean user`.
- `hm brew cleanup [--force] [--zap]` previews what Homebrew has beyond the lists; `--force` removes it and `--zap` also deletes cask data.
- `hm completion zsh|bash|fish` prints the shell completion script, and `hm help [COMMAND]` prints the manual or one command's help.

`--build-only` on `add`, `rm`, `up`, and `sync` does every step except the one that changes the machine, printing the built store path or the `hm sync` command instead.
`hm` commits only with `--commit`, scoped to the files it changed, with a generated subject such as `home: add zizmor 1.30.1` or `darwin: add cask ghostty`.
It refuses to start when a file it would edit has uncommitted changes.
Exit codes are stable: 0 success, 1 failed and restored, 2 usage error, 3 refused (a dirty owned file, a held lock, an unresolved run, or a version for a shared pin), and 4 switch succeeded but the commit did not.

The lists `hm` owns are `home-manager/packages.nix`, `go-tools.nix`, `uv-tools.nix`, `cargo-tools.nix`, `darwin/homebrew/casks.nix`, and `brews.nix`.
Each is a bracketed Nix list of double-quoted strings, one per line, with `#` comments allowed between entries.
Edit them through `hm`, not by hand.

Homebrew activation never removes anything, so a wrong list costs an unwanted install, never a lost one.
Third-party taps are declared with `trusted = true` in `darwin/homebrew/default.nix`.
Homebrew applies that flag only when a switch installs the Brewfile, so before the first `nh darwin switch` each such tap needs a one-time `brew trust TAP`, and `hm brew cleanup` prints the command when it is missing.

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
nix eval '.#enabledServices.ser8' --json
nix eval '.#servicePackages.ser8' --json
nix eval '.#nixosConfigurations.ser8.config.services.jellyfin.enable'
nix eval --raw '.#nixosConfigurations.ser8.pkgs.tailscale.version'
```

Use `mvs` (in the dev shell) to query nixpkgs version history, for example `mvs query versions tailscale`.
The repo-root `multiverse.lock` is the source of truth for application versions pinned from nixpkgs history; edit it only through `mvs lock` commands or `hm`, never by hand.
Hosts consume pins through `config.multiverse.locked.<attr>` (wired in `modules/common/multiverse.nix`).
The Mac's Home Manager and nix-darwin configurations, and the Home Manager modules on every host, consume the same pins through the `pinned` special argument.
`hm add <attr>` is the day-to-day way to pin a tool and install it on the Mac, and `mvs lock` remains the way to manage host-only pins.
Moving a host pin forward is two steps: `nix flake update mvs`, then `mvs lock update <attr>`.
Run the lock command from a newly entered development shell so it uses the refreshed index.
`hm up` performs both steps for the pins that `home-manager/packages.nix` lists.
An existing version constraint remains in force; use `mvs lock add <attr>@<version>` to change it.
`multiverse.lock` is shared by the hosts, the development shell, and the Mac, so `hm` never treats it as its own package list.
`hm add` reuses an existing pin and refuses a version for an attribute that is already pinned, because changing a shared pin is `hm up`.
`hm rm` leaves the pin in place unless `--prune` is given and no other Nix file in the repository names the attribute.
`hm up` moves only the pins that `packages.nix` lists unless `--repo` is given, and never passes `--all`.
Do not automatically minimize pins: the same application version can carry older recipes and dependencies after `mvs lock minimize`.
`hm status` reports what `mvs lock minimize --check` would change, so minimizing stays a deliberate step.

Build the Arm64 kexec installer with `make aarch64-kexec`.
Raspberry Pi bootstrap-image and device-write targets do not currently exist and must not be presented as available.

## Coding Conventions

Format Nix with `nixfmt-rfc-style` and do not hand-align against formatter output.
Keep module filenames lowercase and kebab-case.
Preserve `SPDX-License-Identifier: GPL-3.0-or-later` headers where present.
Keep shell scripts compatible with their declared interpreter and start new Bash scripts with `set -euo pipefail`.
Run `shellcheck` and `shfmt -d` for changed shell scripts.
Go code in `tools/hm` uses the standard library only, so `vendorHash` stays `null`.
Keep it `gofmt`, `go vet`, and `staticcheck` clean, with functions under 100 lines and no package-level mutable state.
The package's check phase runs `go test ./...` and then `staticcheck` from the pinned `go-tools`, so `nix build .#hm` is the test command and `make check` covers it.
Every file format `hm` owns has golden tests, such as the Nix list cases under `tools/hm/internal/nixlist/testdata/`.
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
```

Host-specific encrypted data lives in `secrets/<host>.yaml`, and shared encrypted data lives in `secrets/shared.yaml`.
SOPS age identities come from SSH host keys, with persistent hosts reading keys from `/persist/etc/ssh/`.
The git identity in `home-manager/modules/git.nix` signs commits on every machine.
On the hosts the signing subkey, when present, is delivered by sops as `gpg_signing_subkey` and imported by a Home Manager user service in `home-manager/modules/gpg.nix`; the primary key never leaves the Mac.
Do not expose secret values in logs, test output, documentation, or diffs.

## Change and Review Guidance

Use short, scoped commit subjects in imperative form, such as `media: enable exporter`, `home: add zizmor 1.30.1`, or `flake: update input`.
Keep each commit to one logical change and do not add an agent as a co-author.
Before committing, review the diff, run relevant tests, and resolve all warnings.
Do not push directly to `main`.
Pull requests should identify affected hosts and modules, list validation performed, and call out required deployment or secret steps.
Include dashboard screenshots or exported JSON diffs when Grafana assets change.
