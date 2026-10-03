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
The configuration declares one interactive account on every host, `bobby` (uid 1000), in `modules/common/users.nix`.
The SSH user that deployments connect as follows `deploy.yaml`, and the remote-builder identities follow `etc/nix/machines`, so neither is implied by the declared account.
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
`programs.nh.flake` in `home-manager/modules/nh.nix` sets `NH_FLAKE` to the main checkout, so `nh` and `hm` work from any directory but act on that checkout.
In another worktree, pass `hm --flake "$PWD"` or `nh home switch "$PWD"` so the run reads and edits that tree.
The global `hm --dry-run` prints the commands a run would execute and the diff it would write, and changes nothing.
A Home Manager switch is user-level and one generation away from rollback.
Automatic cleaning is off in `home-manager/modules/nh.nix`, so old generations stay until `hm clean` removes them.
`nh darwin switch` changes system files, Homebrew installs, and launchd agents, and `hm brew cleanup --force` uninstalls software, so both require explicit intent.

`hm` (`tools/hm`) wraps `mvs lock`, `nh`, and the Homebrew lists so that adding, removing, or updating a tool is one command.
Home Manager installs it, and `nix run .#hm -- --help` runs the same binary from the flake before the first switch.
`man hm` is the full reference, and `hm help` prints the same text.

- `hm add NAME[@VERSION]` pins a nixpkgs attribute in `multiverse.lock`, inserts it in `home-manager/packages.nix`, and runs `nh home switch`.
- `hm add --cask NAME` and `hm add --brew NAME` append to `darwin/homebrew/casks.nix` or `brews.nix` and run `nh darwin switch`.
- `hm add --go MODULE@VERSION`, `hm add --uv PACKAGE==VERSION`, and `hm add --cargo CRATE@VERSION` append to the matching tool list and run `hm sync` for it.
- `hm rm NAME` removes the name from whichever list holds it: a nixpkgs attribute leaves `packages.nix` and Home Manager switches, a go, uv, or cargo tool is uninstalled directly, and a cask or brew leaves its list and nix-darwin switches, which keeps the software installed until `hm brew cleanup --force`.
- `hm rm --prune NAME` also drops the pin from `multiverse.lock`, and refuses the whole removal when another Nix file in the repository names the attribute.
- `hm up [ATTR]` runs `nix flake update mvs`, moves the named pin or every pin that `home-manager/packages.nix` lists, and runs `nh home switch` only when a pin moved.
- `hm up --repo ATTR` is required for a pin that `packages.nix` does not list, such as a host service or a pin a `programs.*` module installs (`git`, `nh`, `go_1_27`).
- `hm sync [go|uv|cargo]` installs the tools the lists declare that are missing or at another version; `--force` reinstalls every declared entry.
- `hm switch [home|darwin|all]` runs `nh home switch`, `nh darwin switch`, or both.
- `hm list` shows the installed packages with their source tag (`pinned`, `nixpkgs`, `custom`, `cask`, `brew`, `go`, `cargo`, `uv`, or `native`), and `--generation PATH` reads a built, unactivated home generation instead of the active one.
- Its `cask` and `brew` rows come from the declared lists, so a Homebrew install that no list declares shows only in `hm brew cleanup`.
- `hm status` reports pins behind the index, the `mvs lock minimize --check` result, uncommitted flake files, and the last run.
- `hm doctor` reports PATH entries that shadow Nix binaries and tools that no list declares.
- `hm try ATTR [-- COMMAND...]` runs a nixpkgs package once without installing it.
- `hm clean [--keep N]` runs `nh clean user --keep 5` unless `N` is given, which also removes gcroots and direnv roots and runs a store GC; it refuses while `~/.local/state/home-manager/keep-gen19` exists.
- `hm brew cleanup [--force] [--zap]` previews what Homebrew has beyond the lists; `--force` removes it and `--zap` also deletes cask data.
- `hm completion zsh|bash|fish` prints the shell completion script, and `hm help [COMMAND]` prints the manual or one command's help.

`--build-only` on `add`, `rm`, `up`, and `sync` does every step except the one that changes the machine, so the lists and the lock are still edited; it prints the built store path instead of activating, or the `hm sync` or uninstall command instead of running it.
`hm` commits only with `--commit`, scoped to the files it changed, with a generated subject such as `home: add zizmor 1.30.1` or `darwin: add cask ghostty`.
It refuses to start when a file it would edit has uncommitted changes.
Exit codes are stable: 0 success, 1 the run failed, 2 usage error, 3 refused (a dirty owned file, a held lock, an unresolved run, or a different version for a shared pin), and 4 the build or switch succeeded but the commit did not, which `--build-only` can also produce.
After exit 1 the edited files are restored only when no generation was activated, nothing else edited them, and `--keep-on-failure` was not given; otherwise they are kept and the run journal under `.git/hm/` records an unresolved run, which every later run refuses until that journal file is removed.

The lists `hm` owns are `home-manager/packages.nix`, `home-manager/go-tools.nix`, `home-manager/uv-tools.nix`, `home-manager/cargo-tools.nix`, `darwin/homebrew/casks.nix`, and `darwin/homebrew/brews.nix`.
Each is a bracketed Nix list of double-quoted strings, one per line, with `#` comments allowed between entries.
Edit them through `hm`, not by hand.

Homebrew activation never removes anything, so a wrong list costs an unwanted install, never a lost one.
Third-party taps are declared with `trusted = true` in `darwin/homebrew/default.nix`, and nix-darwin writes that flag into the Brewfile, so a switch trusts them as it installs it.
Only a `hm brew cleanup` preview run before the first switch meets the taps untrusted; it then prints the one-time `brew trust TAP` command to run first.

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

`make test-HOST` builds and activates a configuration without making it the boot default, so a reboot returns to the previous one.
It activates without a prompt: only the `switch` and `reboot` actions in `scripts/nixos-rebuild.sh` prompt, so `make test-HOST` needs the same explicit intent on a live host as `make switch-HOST` and `make reboot-HOST`.
`make apply-HOST` runs test, switch, reboot, and the smoketests in that order, so it activates its test configuration before its first prompt.
`NO_CONFIRM=true` disables the remaining prompts and must only be used for intentional non-interactive operations.
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
`hm add` reuses an existing pin and refuses a different version for an attribute that is already pinned, because changing a shared pin is `hm up`.
`hm rm` leaves the pin in place unless `--prune` is given and no other Nix file in the repository names the attribute.
`hm up` moves only the pins that `home-manager/packages.nix` lists unless an attribute is named with `--repo`, switches only Home Manager, and never passes `--all`.
The nix-darwin system and the hosts pick up a moved pin through `nh darwin switch` and `make test-HOST` or `make switch-HOST`.
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
The Nix list format `hm` owns has golden tests under `tools/hm/internal/nixlist/testdata/`, and the run journal has behavioural tests in `tools/hm/internal/txn/`.
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
The git identity in `home-manager/modules/git.nix` is configured to sign commits on every machine.
On the hosts signing works only once the `gpg_signing_subkey` secret is declared in a Nix module and provisioned through sops; the Home Manager user service in `home-manager/modules/gpg.nix` then imports it, and the primary key never leaves the Mac.
Do not expose secret values in logs, test output, documentation, or diffs.

## Change and Review Guidance

Use short, scoped commit subjects in imperative form, such as `media: enable exporter`, `home: add zizmor 1.30.1`, or `flake: update input`.
Keep each commit to one logical change and do not add an agent as a co-author.
Before committing, review the diff, run relevant tests, and resolve all warnings.
Do not push directly to `main`.
Pull requests should identify affected hosts and modules, list validation performed, and call out required deployment or secret steps.
Include dashboard screenshots or exported JSON diffs when Grafana assets change.
