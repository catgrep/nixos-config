<!-- refreshed: 2026-08-17 -->
# Architecture

**Analysis Date:** 2026-08-17

## System Overview

```text
┌─────────────────────────────────────────────────────────────────────┐
│                          flake.nix (root)                            │
│  Declares inputs, `mkSystem` helper, `nixosConfigurations`,          │
│  devShells, service-introspection outputs (enabledServices, etc.)    │
└───────────────┬────────────────────────────┬─────────────────────────┘
                │                             │
                ▼                             ▼
┌───────────────────────────┐   ┌────────────────────────────────────┐
│   Host configs (per-node) │   │   Shared module groups              │
│   `hosts/<host>/`         │   │   `modules/common`, `modules/servers`│
│   default.nix -> imports  │   │   (baseModules, always applied)     │
│   configuration.nix,      │   │   plus x86Modules / piModules and   │
│   disko-config.nix,       │   │   role modules (media, gateway,     │
│   hardware-configuration  │   │   dns, nordvpn, automation, subgen) │
└──────────────┬────────────┘   └───────────────┬──────────────────────┘
               │                                 │
               ▼                                 ▼
     ┌────────────────────────────────────────────────────┐
     │        NixOS module system (option merge)           │
     │  Each module declares `options.<ns>` + `config`      │
     │  guarded by `lib.mkIf config.<ns>.enable`             │
     └───────────────────────┬────────────────────────────┘
                              │ nix build / nixos-rebuild
                              ▼
     ┌────────────────────────────────────────────────────┐
     │           Live system (systemd units, users,         │
     │           firewall, ZFS, services) on target host    │
     └───────────────────────┬────────────────────────────┘
                              │
                              ▼
     ┌────────────────────────────────────────────────────┐
     │   Deployment + validation tooling                    │
     │   `Makefile` targets -> `scripts/*.sh` -> deploy.yaml │
     │   -> `scripts/smoketests/<host>/all.sh`               │
     └────────────────────────────────────────────────────┘
```

## Component Responsibilities

| Component | Responsibility | File |
|-----------|----------------|------|
| Flake outputs | Wires inputs, builds `nixosConfigurations`, devShells, package/service introspection | `flake.nix` |
| Host entry point | Per-host top-level import list, hardware/disk config | `hosts/<host>/default.nix` |
| Host configuration | Host-specific networking, boot, firewall, ZFS/hostId | `hosts/<host>/configuration.nix` |
| Disk layout | Declarative partitioning via disko | `hosts/<host>/disko-config.nix` |
| Impermanence rules | Persisted paths for hosts using ephemeral root | `hosts/<host>/impermanence.nix` |
| Role module group | Grouped, importable feature set (media, gateway, dns, automation, nordvpn, subgen) | `modules/<role>/default.nix` |
| Individual service module | Defines `options.<service>` and `config` for one service | `modules/<role>/<service>.nix` |
| Media orchestration | systemd unit graph (`media-config` -> `servarrs-setup`/`download-clients-setup` -> `media-setup.target`) coordinating *arr/download-client wiring | `hosts/ser8/media/orchestration.nix`, `orchestration-helpers.sh` |
| User definitions | Centralizes both NixOS user account and Home Manager config for a single logical user | `users/bdhill.nix` |
| Secrets | SOPS-encrypted per-host and shared secrets, decrypted at activation via `sops-nix` | `secrets/<host>.yaml`, `secrets/shared.yaml` |
| Deployment metadata | Source of truth for target IPs, users, tags, smoketest entrypoints | `deploy.yaml` |
| Deployment orchestration | `make` targets driving `nixos-rebuild`/`nixos-anywhere` against hosts resolved from `deploy.yaml` | `Makefile`, `scripts/nixos-rebuild.sh`, `scripts/lib/*.sh` |
| Smoketests | Post-deploy validation scripts, one entrypoint per host/role (`all.sh`) fanned out to individual `test-*.sh` | `scripts/smoketests/<role>/` |
| Dev tooling subflake | Local flake exporting the `sagent` sandbox tool and `ast-bro`/`treehouse` binaries consumed by devShells | `tools/sagent/` |
| GSD planning state | Not part of the deployed system; tracks project/phase planning artifacts | `.planning/` |

## Pattern Overview

**Overall:** Declarative infrastructure-as-code using the NixOS module system. This is not an application codebase with runtime layers — the "architecture" is a composition graph of Nix modules that evaluate into a single system closure per host, deployed via SSH/`nixos-rebuild`.

**Key Characteristics:**
- Every host is defined by `mkSystem` in `flake.nix`, which composes a fixed set of module groups: `baseModules` (always), `x86Modules` or `piModules` (architecture-specific), plus host-specific role modules passed in per host entry.
- Feature areas are organized as self-contained module groups under `modules/<role>/`, each with a `default.nix` that only lists imports — no logic lives in `default.nix` files.
- Individual `.nix` files under a role directory each own one service: declare `options.<namespace>` (when the module is configurable) and a `config = lib.mkIf config.<namespace>.enable { ... }` block.
- Host-specific overrides and glue that don't belong in a reusable module live directly under `hosts/<host>/`, e.g. `hosts/ser8/media/` contains ser8-specific orchestration for the shared `modules/media/*` services.
- Secrets are never inline; they are referenced via `sops-nix` templates and decrypted paths (`config.sops.secrets.*` / `config.sops.templates.*`), sourced from `secrets/<host>.yaml` and `secrets/shared.yaml`.
- Deployment, build, and validation are all `make`-driven; `deploy.yaml` is the single source of truth for host connection info and which smoketest script to run per host.

## Layers

**Flake/outputs layer:**
- Purpose: Input pinning, host composition, cross-cutting Nix-level introspection (service discovery, package info)
- Location: `flake.nix`
- Contains: `mkSystem`, `nixosConfigurations`, `devShells`, `enabledServices`/`servicePackages`/`packageInfo` outputs
- Depends on: `nixpkgs`, `nixpkgs-unstable`, `nixos-hardware`, `disko`, `impermanence`, `sops-nix`, `nixos-images`, `declarative-jellyfin`, `home-manager`, `caddy-nix`, `tools/sagent` (as flake input `sagent`)
- Used by: `Makefile` targets (`nix build`, `nix eval`, `nixos-rebuild --flake`)

**Host layer:**
- Purpose: Per-machine identity — hardware, disk layout, host-specific networking/firewall, which role modules apply
- Location: `hosts/<host>/`
- Contains: `default.nix` (import list), `configuration.nix` (host settings), `disko-config.nix`, `hardware-configuration.nix`, optional `impermanence.nix`, host-only service overrides (e.g. `hosts/ser8/media/`, `hosts/ser8/samba.nix`, `hosts/firebat/subgen.nix`)
- Depends on: role modules from `modules/`, `users/bdhill.nix` (via `baseModules`), secrets from `secrets/<host>.yaml`
- Used by: `flake.nix` `mkSystem` (one call per host in `nixosConfigurations`)

**Module (role) layer:**
- Purpose: Reusable, host-agnostic feature bundles — media stack, gateway/reverse-proxy+monitoring, DNS, VPN network namespace, home automation, subtitle generation, Raspberry Pi base
- Location: `modules/<role>/`
- Contains: `default.nix` import lists, per-service `.nix` files each declaring `options`/`config`
- Depends on: `modules/common`, `modules/servers` (via `baseModules`), external flake inputs where relevant (e.g. `declarative-jellyfin`, `disko`)
- Used by: `hosts/<host>/default.nix` selection in `flake.nix` (e.g. ser8 gets `modules/media`, `modules/nordvpn`, `modules/automation`; firebat gets `modules/gateway`; pi4 gets `modules/dns`)

**Users layer:**
- Purpose: Single definition combining NixOS system-user attributes and the corresponding Home Manager profile for the same person
- Location: `users/bdhill.nix`
- Depends on: nothing project-specific (pure attrset consumed by both NixOS and Home Manager module systems)
- Used by: `baseModules` in `flake.nix` (`home-manager.users.bdhill`), and any module reading `systemConfig`

**Secrets layer:**
- Purpose: Encrypted credential storage decrypted at system activation
- Location: `secrets/<host>.yaml`, `secrets/shared.yaml`, `secrets/keys/`
- Depends on: SSH host keys as SOPS age identities (`/persist/etc/ssh/` on persistent hosts)
- Used by: any module referencing `config.sops.secrets.*` (media services, nordvpn tokens, samba credentials)

**Deployment/operations layer:**
- Purpose: Build, deploy, roll out, and verify host configurations from a developer machine
- Location: `Makefile`, `scripts/`, `deploy.yaml`
- Contains: `scripts/nixos-rebuild.sh` (core deploy driver), `scripts/lib/*.sh` (host resolution, SSH, logging, prompts, cleanup), `scripts/sops/*` (secret management helpers), `scripts/provision/*` (nixos-anywhere bootstrap variants), `scripts/smoketests/*` (post-deploy checks), `scripts/validation/*` (pre-deploy parity/permission checks)
- Depends on: `deploy.yaml` for host metadata, SSH access to targets
- Used by: developer/agent invoking `make <target>-<host>`

## Data Flow

### Primary Deploy Path

1. Developer runs `make switch-ser8` (or `test-`, `dry-activate-`, `build-`) (`Makefile`)
2. Makefile resolves host connection info from `deploy.yaml` via `yq` (`scripts/lib/resolve-host.sh`)
3. `scripts/nixos-rebuild.sh` invokes `nixos-rebuild` against the flake output `nixosConfigurations.<host>` over SSH, optionally building on target
4. NixOS evaluates `hosts/<host>/default.nix` → merges `baseModules` + arch modules (`x86Modules`/`piModules`) + host-specific role modules from `flake.nix`
5. SOPS decrypts `secrets/<host>.yaml` / `secrets/shared.yaml` into runtime secret files during activation (`sops-nix`)
6. systemd activates services; on ser8, `media-config.service` deploys templated configs before `servarrs-setup.service` / `download-clients-setup.service` wire up the *arr stack (`hosts/ser8/media/orchestration.nix`)
7. Post-deploy, `deploy.yaml`'s `smoketests` path is invoked (e.g. `scripts/smoketests/ser8/all.sh`) to validate the live system

### Media Automation Flow (ser8)

1. `media-config.service` renders SOPS-templated configs for Sonarr, Radarr, Prowlarr, NZBGet, SABnzbd, qBittorrent (`hosts/ser8/media/orchestration.nix`, `hosts/ser8/media/sops.nix`)
2. `servarrs-setup.service` connects Prowlarr to Sonarr/Radarr for indexer sync (parallel with step 3)
3. `download-clients-setup.service` connects qBittorrent/NZBGet/SABnzbd to the *arr apps and configures categories
4. `media-setup.target` aggregates both setup services as a single readiness target
5. qBittorrent itself runs inside the NordVPN network namespace (`modules/nordvpn/service.nix`) and is exposed to the LAN through local nginx/Caddy proxying

**State Management:**
- No application-level state store; state is the live NixOS system (systemd unit status, ZFS pool state, service data directories under `/mnt`/`/persist`) plus encrypted secrets in `secrets/`.
- Impermanence (`hosts/ser8/impermanence.nix`, `hosts/firebat/impermanence.nix`) defines which paths survive reboot; everything else is wiped, so state must be explicitly declared as persisted.

## Key Abstractions

**Module group (`default.nix` import list):**
- Purpose: Group related service modules into one importable unit
- Examples: `modules/media/default.nix`, `modules/gateway/default.nix`, `modules/automation/default.nix`
- Pattern: File contains only an `imports = [ ... ]` list — no options or config directly in `default.nix`

**Namespaced options module:**
- Purpose: One `.nix` file owns one service's configuration surface and its systemd/service wiring
- Examples: `modules/nordvpn/default.nix` (`options.nordvpn.*`), `modules/dns/adguard-home.nix`
- Pattern: `options.<namespace> = { enable = lib.mkEnableOption ...; ... }` followed by `config = lib.mkIf config.<namespace>.enable { ... }`

**`mkSystem` host factory:**
- Purpose: Central function producing a `nixosSystem` from a hostname, target arch, and extra modules, avoiding per-host duplication of `baseModules`/`x86Modules`/`piModules`
- Location: `flake.nix` (lines ~159-189)
- Pattern: Called once per host inside `nixosConfigurations`, with `useX86Modules`/`usePiModules` toggling architecture-specific module sets

**Provisioning alias configs:**
- Purpose: `provisioning-<host>` configs alias the real host config so `nixos-anywhere` can target the same evaluation for bare-metal bootstrap
- Location: `flake.nix` (`nixosConfigurations."provisioning-*"`)

## Entry Points

**`flake.nix` `nixosConfigurations.<host>`:**
- Location: `flake.nix`
- Triggers: `nixos-rebuild --flake .#<host>`, `nix build .#nixosConfigurations.<host>.config.system.build.toplevel`
- Responsibilities: Produces the full evaluated system closure for a host

**`Makefile`:**
- Location: `Makefile`
- Triggers: Developer/agent invocation (`make switch-ser8`, `make check`, `make dev`, etc.)
- Responsibilities: Human-facing command surface over flake builds, deployment scripts, sops helpers, and package introspection

**`scripts/nixos-rebuild.sh`:**
- Location: `scripts/nixos-rebuild.sh`
- Triggers: Called by Makefile deploy/test/switch targets
- Responsibilities: Wraps `nixos-rebuild` with host resolution, confirmation prompts, logging to `logs/nixos-rebuild.log-*`

**`scripts/smoketests/<role>/all.sh`:**
- Location: `scripts/smoketests/*/all.sh`
- Triggers: `make smoketests-<host>`, referenced directly by `deploy.yaml`
- Responsibilities: Fans out to individual `test-*.sh` scripts validating a live deployment

**`hosts/ser8/media/orchestration.nix` systemd units:**
- Location: `hosts/ser8/media/orchestration.nix`
- Triggers: `multi-user.target` on boot/activation
- Responsibilities: Sequences media-service configuration and cross-service API wiring

## Architectural Constraints

- **Evaluation model:** Nix module evaluation is lazy and declarative — there is no runtime "call graph" in the traditional sense; behavior is determined by which modules are imported and which options are set, not by imperative control flow.
- **Global state:** Nix module system options act as the shared mutable state within a single evaluation (e.g. `config.networking.internal.*`, `config.sops.secrets.*`); there is no other global/singleton state across the repo.
- **Module import order:** `flake.nix` composes module lists (`baseModules ++ x86Modules/piModules ++ host modules`) — accidental option collisions (`lib.mkForce`, `lib.mkIf`) must be resolved explicitly, as seen in `hosts/ser8/configuration.nix` (`boot.supportedFilesystems = lib.mkForce [...]`).
- **Secrets availability at eval time:** SOPS secrets are only available as decrypted files at activation time on the target host, not at evaluation time on the build machine — modules must reference `config.sops.secrets.<name>.path`, never read decrypted content during evaluation.
- **Network namespace isolation:** qBittorrent's network path only works when the NordVPN module's veth/namespace config is applied; modifying `modules/nordvpn/` has blast radius into `modules/media/qbittorrent.nix` and ser8-specific overrides in `hosts/ser8/media/qbittorrent.nix`.
- **Pinned `nixos-hardware`:** deliberately pinned to a specific commit (not `master`) because Raspberry Pi board modules under active upstream development could silently change Pi boot behavior (`flake.nix` inputs comment) — must be bumped deliberately, not left on a floating ref.

## Anti-Patterns

### Logic inside `default.nix` import files

**What happens:** Some `default.nix` files under `modules/<role>/` are pure import lists; this is the established convention.
**Why it's wrong (if violated):** Mixing `options`/`config` blocks into a `default.nix` alongside its own imports makes the module group harder to scan and blurs the "group vs. individual service" boundary.
**Do this instead:** Keep `default.nix` limited to `imports = [ ... ]`; put all `options`/`config` in a dedicated per-service file (see `modules/gateway/default.nix`, `modules/media/default.nix` as the reference pattern).

### Retained but unused specialArgs plumbing

**What happens:** `flake.nix` passes `unstable = import nixpkgs-unstable ...` into `specialArgs` with an explicit comment: "Retained with no in-tree consumers: Phase 10 needs this plumbing."
**Why it's wrong:** Unused specialArgs are easy to assume are wired to something; a future edit could silently leave it dead longer than intended.
**Do this instead:** When adding a phase that consumes `unstable`, wire it explicitly in the consuming module and remove the placeholder comment; if a phase is abandoned, remove the unused plumbing rather than leaving it indefinitely.

## Error Handling

**Strategy:** Nix module evaluation fails fast (assertion/type errors at `nix build`/`nixos-rebuild` time); shell scripts follow `set -euo pipefail` per project convention (`CLAUDE.md`) so deployment/orchestration scripts abort on first failure rather than continuing in a partially-applied state.

**Patterns:**
- `flake.nix` uses `builtins.tryEval` to safely probe for renamed/deprecated NixOS options (`enabledServices`, `servicePackages`, `packageInfo`) instead of letting an abort crash the whole eval.
- systemd units in `hosts/ser8/media/orchestration.nix` use `Type = "oneshot"` + `RemainAfterExit = true` with explicit dependency ordering (`wantedBy`, `after`, `requires`) rather than blind `sleep`-based synchronization — the module's own comments call out "no blind sleep delays."

## Cross-Cutting Concerns

**Logging:** Deploy/rebuild activity is captured to timestamped files under `logs/nixos-rebuild.log-<timestamp>` by `scripts/nixos-rebuild.sh`. On-host service logs go through systemd journal as usual.
**Validation:** `make check` runs flake checks, `statix` (Nix linter), and dry-run host builds; `scripts/validation/*.sh` performs targeted checks (media parity, permissions, Pi bootloader) outside the main `make check` path.
**Authentication/secrets:** Centralized through `sops-nix`; per-host encrypted files in `secrets/<host>.yaml` plus shared secrets in `secrets/shared.yaml`, decrypted via SSH-host-key-derived age identities.

---

*Architecture analysis: 2026-08-17*
