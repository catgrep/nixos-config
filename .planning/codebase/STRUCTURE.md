# Codebase Structure

**Analysis Date:** 2026-08-17

## Directory Layout

```
nixos-config/
├── flake.nix              # Root flake: inputs, mkSystem, nixosConfigurations, devShells
├── flake.lock
├── Makefile                # Command surface for build/deploy/check/sops/pkg-inspection
├── deploy.yaml              # Host deployment metadata (IPs, users, tags, smoketest paths)
├── statix.toml               # Nix linter config
├── AGENTS.md -> CLAUDE.md    # Symlink so both filenames resolve to the same guide
├── CLAUDE.md                  # Repository guide (agent-agnostic instructions)
├── hosts/                      # Host-specific NixOS configuration (one dir per machine)
│   ├── ser8/                     # Media/storage/automation server
│   │   ├── default.nix              # Import list (configuration, impermanence, samba)
│   │   ├── configuration.nix        # Host networking, boot, firewall, ZFS hostId
│   │   ├── disko-config.nix         # Declarative disk/ZFS layout
│   │   ├── hardware-configuration.nix
│   │   ├── impermanence.nix         # Persisted paths for ephemeral root
│   │   ├── samba.nix                # File-sharing config
│   │   └── media/                    # ser8-specific media stack overrides + orchestration
│   ├── firebat/                    # Gateway/reverse-proxy/monitoring server
│   ├── pi4/                        # AdGuard DNS/DHCP Raspberry Pi
│   └── pi5/                        # General-purpose Raspberry Pi 5
├── modules/                    # Reusable NixOS modules grouped by role
│   ├── common/                    # Always-applied base config (boot, ssh, users, packages)
│   ├── servers/                    # Server-role config (monitoring, backup, security, tailscale)
│   ├── media/                      # Jellyfin, *arr apps, download clients
│   ├── gateway/                    # Caddy, Prometheus, Grafana, blackbox, Tailscale
│   ├── dns/                        # AdGuard Home + exporter
│   ├── nordvpn/                    # WireGuard VPN network namespace
│   ├── automation/                 # Frigate, Home Assistant, Mosquitto
│   ├── subgen/                     # Subtitle generation service
│   ├── development/                # Gerrit and dev-role config
│   └── raspberrypi/                # Shared Pi base module
├── users/
│   └── bdhill.nix               # Combined NixOS systemConfig + Home Manager homeConfig
├── home-manager/                # Separate standalone Home Manager flake
├── overlays/                    # Package overrides (nixpkgs overlay functions)
├── packages/                    # Custom package derivations (subgen, faster-whisper, etc.)
├── secrets/                     # SOPS-encrypted secrets
│   ├── <host>.yaml                 # Per-host encrypted secrets
│   ├── shared.yaml                  # Cross-host encrypted secrets
│   └── keys/                        # Public key material
├── scripts/                    # Operational and validation scripts
│   ├── nixos-rebuild.sh            # Core deploy driver invoked by Makefile
│   ├── lib/                        # Shared shell helpers (host resolution, ssh, logging, yq)
│   ├── sops/                        # Secret management helpers (edit, gen-hash, gen-api-key)
│   ├── provision/                   # nixos-anywhere bootstrap variants per arch
│   ├── smoketests/                  # Post-deploy validation, one dir per role/host
│   │   ├── <role>/all.sh               # Entry point referenced by deploy.yaml
│   │   └── <role>/test-*.sh            # Individual smoketests
│   ├── validation/                  # Pre-deploy parity/permission/config checks
│   ├── license/                     # GPL header tooling
│   └── lutron/                      # Lutron-specific setup script
├── dashboards/                  # Version-controlled Grafana dashboard JSON
├── tools/
│   └── sagent/                    # Local subflake exporting `sagent`, `ast-bro`, `treehouse`
├── tests/                       # Nix test fixtures and NixOS VM tests
│   ├── fixtures/
│   └── nixos/
├── etc/
│   └── nix/                        # Repository-managed Nix daemon config
├── experimental/                # Work not part of the active host flake (docker-compose, etc.)
├── .planning/                    # GSD project planning state (not deployed code)
└── logs/                        # Timestamped nixos-rebuild logs (generated, not curated)
```

## Directory Purposes

**`hosts/<host>/`:**
- Purpose: Machine-specific identity — hardware, disks, host-scoped service overrides
- Contains: `default.nix` import list, `configuration.nix`, `disko-config.nix`, `hardware-configuration.nix`, optional `impermanence.nix`, host-only glue directories (e.g. `ser8/media/`)
- Key files: `hosts/ser8/media/orchestration.nix` (systemd sequencing for the *arr stack), `hosts/ser8/media/sops.nix` (SOPS template wiring)

**`modules/<role>/`:**
- Purpose: Reusable, host-agnostic feature bundles selected per host in `flake.nix`
- Contains: `default.nix` (imports only), one `.nix` file per service with `options`/`config`
- Key files: `modules/common/default.nix`, `modules/servers/default.nix` (always applied via `baseModules`); `modules/media/default.nix`, `modules/gateway/default.nix`, `modules/dns/default.nix`, `modules/nordvpn/default.nix`, `modules/automation/default.nix` (role-specific, opted in per host)

**`users/`:**
- Purpose: Centralized user account + Home Manager configuration, single source per person
- Key files: `users/bdhill.nix` (exports `systemConfig` and `homeConfig` attrsets consumed by `flake.nix`)

**`secrets/`:**
- Purpose: SOPS-encrypted credentials, decrypted at activation via age identities from SSH host keys
- Contains: `<host>.yaml` per host, `shared.yaml` for cross-host secrets, `keys/` for public key material
- Generated: No (hand-edited via `make sops-edit-<host>`)
- Committed: Yes (ciphertext only)

**`scripts/`:**
- Purpose: All operational tooling invoked by `Makefile` — deploy, provision, validate, manage secrets
- Contains: `nixos-rebuild.sh` (core deploy wrapper), `lib/` (shared bash helpers), `sops/`, `provision/`, `smoketests/`, `validation/`, `license/`, `lutron/`
- Key files: `scripts/lib/resolve-host.sh` (smart IP/Tailscale resolution), `scripts/lib/all.sh` (shared script bootstrap)

**`scripts/smoketests/`:**
- Purpose: Post-deploy live validation, organized by role/host, each with an `all.sh` entry point
- Contains: `gateway/`, `media/`, `nordvpn/`, `ser8/`, `subgen/`, plus `lib/` (fanout + service helpers)
- Key files: `<role>/all.sh` — referenced directly by `deploy.yaml`'s `smoketests` field per host

**`dashboards/`:**
- Purpose: Version-controlled Grafana dashboard definitions provisioned by `modules/gateway/grafana.nix`
- Generated: No (hand-maintained/exported JSON)
- Committed: Yes

**`packages/`:**
- Purpose: Custom Nix package derivations not available in nixpkgs (subgen stack: faster-whisper, stable-ts-whisperless, subgen itself, subgen-benchmark)
- Key files: `packages/subgen/default.nix` (built via `pkgs.callPackage` in `flake.nix`)

**`tools/sagent/`:**
- Purpose: Local subflake providing the sandboxed `sagent` CLI and exporting `ast-bro`/`treehouse` packages consumed by the dev shell
- Contains: Its own `flake.nix`/`flake.lock` (input `nixpkgs-unstable`), referenced as a flake input `sagent` from the root `flake.nix`

**`tests/`:**
- Purpose: NixOS module/VM tests and supporting fixtures
- Contains: `tests/nixos/` (VM test definitions), `tests/fixtures/` (test input data)

**`.planning/`:**
- Purpose: GSD workflow state — roadmap, requirements, phase plans, codebase maps
- Generated: Partially (codebase docs, STATE.md are agent-maintained; PROJECT.md/ROADMAP.md are curated)
- Committed: Yes

**`logs/`:**
- Purpose: Timestamped output of `scripts/nixos-rebuild.sh` runs
- Generated: Yes (one file per rebuild invocation)
- Committed: Currently tracked in git status as untracked/generated churn — treat as ephemeral, not a place to add hand-written content

**`experimental/`:**
- Purpose: Holds work-in-progress configuration (e.g. `docker-compose/`) not wired into the active host flake
- Generated: No
- Committed: Yes, but explicitly out of the deployed system — do not assume anything here is live

## Key File Locations

**Entry Points:**
- `flake.nix`: Root composition — `nixosConfigurations`, `devShells`, package/service introspection outputs
- `Makefile`: Developer/agent command surface for build, deploy, check, sops, package inspection

**Configuration:**
- `deploy.yaml`: Deployment target metadata (IP, user, tags, smoketest path) per host
- `hosts/<host>/configuration.nix`: Per-host runtime settings (networking, boot, firewall)
- `secrets/<host>.yaml`, `secrets/shared.yaml`: Encrypted secrets

**Core Logic:**
- `modules/<role>/default.nix` + per-service `.nix` files: Feature implementation
- `hosts/ser8/media/orchestration.nix`: Cross-service systemd sequencing for the media stack

**Testing:**
- `tests/nixos/`: NixOS VM tests
- `scripts/smoketests/<role>/all.sh` and `test-*.sh`: Live post-deploy validation
- `scripts/validation/*.sh`: Pre-deploy config/parity checks

## Naming Conventions

**Files:**
- Lowercase, kebab-case Nix files (`disko-config.nix`, `jellyfin-exporter.nix`, `hardware-configuration.nix`) per `CLAUDE.md`
- Every module group directory has a `default.nix` that is import-only
- Shell scripts use descriptive `test-*.sh` names inside `smoketests/`, and area entry points are always named `all.sh` (required by `deploy.yaml` references)

**Directories:**
- `modules/<role>/` names match the functional domain (`media`, `gateway`, `dns`, `nordvpn`, `automation`, `subgen`)
- `hosts/<hostname>/` names match the actual machine hostname used in `deploy.yaml` and `flake.nix`
- `scripts/<area>/` groups scripts by operational concern (`sops`, `provision`, `smoketests`, `validation`, `license`)

## Where to Add New Code

**New Service on an Existing Host Role (e.g. new media-stack app):**
- Module: add `modules/media/<service>.nix` declaring `options.services.<service>`/`config`, then add it to `modules/media/default.nix`'s `imports` list
- Host override (if ser8-specific): add corresponding file under `hosts/ser8/media/`
- Secrets: add entries to `secrets/ser8.yaml` via `make sops-edit-ser8`, referenced through `config.sops.secrets.*`
- Smoketest: add `scripts/smoketests/media/test-<service>.sh` (or the relevant role dir) and wire it into that dir's `all.sh`

**New Host:**
- Create `hosts/<newhost>/` with `default.nix`, `configuration.nix`, `hardware-configuration.nix`, and `disko-config.nix` if using disko
- Register it in `flake.nix` `nixosConfigurations` via `mkSystem`
- Add an entry to `deploy.yaml` with `targetHost`, `targetUser`, `tags`, and `smoketests` path
- Add a `scripts/smoketests/<newhost>/all.sh` (or reuse a role-based one)

**New Reusable Module Group:**
- Create `modules/<role>/` with a `default.nix` import list and per-service files
- Wire it into `flake.nix`'s `x86Modules`/`piModules`, or pass it directly in a host's `mkSystem` call

**New Deployment/Operations Script:**
- Place under the matching `scripts/<area>/` directory (`sops/`, `provision/`, `smoketests/`, `validation/`)
- Start with `set -euo pipefail`, source `scripts/lib/*.sh` helpers as needed, and add a `Makefile` target if it should be user-facing

**Utilities:**
- Shared shell helpers: `scripts/lib/`
- Package derivations: `packages/<name>/default.nix`, wired via `subgenPackagesFor` or `pkgs.callPackage` in `flake.nix`

## Special Directories

**`secrets/`:**
- Purpose: SOPS-encrypted credential storage
- Generated: No
- Committed: Yes (ciphertext only — never decrypt into this directory)

**`logs/`:**
- Purpose: Rebuild run output
- Generated: Yes
- Committed: Currently present in the tree but should be treated as disposable operational output, not source

**`.ast-bro/`, `.jj/`, `.gsd/`:**
- Purpose: Tool-local caches/state (ast-bro search index, jj VCS metadata, GSD dispatch state)
- Generated: Yes
- Committed: No (tool-managed runtime state)

**`result` (repo root symlink):**
- Purpose: Standard Nix build output symlink created by `nix build`
- Generated: Yes
- Committed: No — regenerated per build, should be gitignored

---

*Structure analysis: 2026-08-17*
