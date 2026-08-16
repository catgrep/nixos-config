# Technology Stack

**Analysis Date:** 2026-08-17

## Languages

**Primary:**
- Nix - all host/module configuration (`flake.nix`, `hosts/*/`, `modules/*/`)

**Secondary:**
- Bash - operational scripts and inline `writeShellApplication` blocks (`scripts/`, `modules/nordvpn/service.nix`, `modules/servers/backup.nix`)
- Python - packaged transcription tooling (`packages/subgen`, `packages/faster-whisper-medium`, `packages/stable-ts-whisperless`)

## Runtime

**Environment:**
- NixOS 25.11 host systems (x86_64: `ser8`, `firebat`; arm: `pi4`, `pi5`)
- Nix flakes as the sole entry point (`flake.nix`); no legacy `default.nix`/channels

**Package Manager:**
- Nix flakes with pinned inputs
- Lockfile: `flake.lock` (present, committed)

## Frameworks

**Core:**
- NixOS module system - declarative host configuration composed from `modules/` groups imported per host
- `disko` - declarative disk partitioning for `ser8`, `firebat`, `pi5`
- `impermanence` - ephemeral root filesystem with persisted state under `/persist` on `ser8` and `firebat`
- `home-manager` (release-26.05) - user-level (`bdhill`) dotfile/package management, wired through `baseModules` in `flake.nix`
- `sops-nix` - secrets decryption at activation time, keyed on SSH host keys

**Testing/Validation:**
- `statix` - Nix anti-pattern linter (`statix.toml`, `make check`)
- `nixfmt-rfc-style` - canonical Nix formatter (`make fmt`)
- Flake checks (`make check`) plus dry-run host builds (`make dry-activate-<host>`)
- Custom smoketest scripts per host area (`scripts/smoketests/<area>/all.sh`, referenced from `deploy.yaml`)

**Build/Dev:**
- `make dev` - enters a Nix dev shell providing `nixfmt-rfc-style`, `statix`, `shellcheck`, `sops`, `yq`, `caddy`, `nixos-anywhere`, `sb` (ast-bro), `treehouse`
- `nix-fast-build` (flake input) - parallel flake build tooling
- `nixos-anywhere` - remote install/kexec provisioning

## Key Dependencies (flake inputs)

**Critical:**
- `nixpkgs` (`nixos-26.05`) - primary package/module set for hosts
- `nixpkgs-unstable` (`nixos-unstable`) - used for `sagent`/ast-bro tooling packages
- `nixos-hardware` - pinned commit (`ff17823245ab9ff7bcae6acf950bd89cba82c38c`) for Raspberry Pi board support; deliberately not tracking `master`
- `disko` - disk layout declarations (follows root `nixpkgs`)
- `impermanence` - impermanent root + `/persist` pattern
- `sops-nix` - SOPS secret decryption module (follows root `nixpkgs`)
- `home-manager` (`release-26.05`) - follows root `nixpkgs`

**Service-specific:**
- `declarative-jellyfin` - declarative Jellyfin server config, used in `modules/media/jellyfin.nix`
- `caddy-nix` - Caddy build with plugin support (used for Caddy + Tailscale plugin), consumed in `modules/gateway/caddy.nix`
- `nixos-images` - kexec/installer image generation (aarch64 kexec target)

**Local/path inputs:**
- `sagent` (`path:./tools/sagent`) - repo-local sandboxing tool, built against `nixpkgs-unstable`

## Configuration

**Environment:**
- Per-host configuration lives in `hosts/<host>/`; shared behavior lives in `modules/<role>/default.nix`
- `deploy.yaml` is the single source of truth for target IPs, SSH users, deployment tags, and smoketest entry points
- Secrets are never plaintext; SOPS-encrypted YAML per host (`secrets/<host>.yaml`) and shared (`secrets/shared.yaml`), decrypted via age identities derived from SSH host keys (persistent hosts read from `/persist/etc/ssh/`)

**Build:**
- `flake.nix` - defines inputs, `nixosConfigurations`, dev shells, and exported flake outputs (`enabledServices`, `servicePackages`, `packageInfo`)
- `Makefile` - primary developer-facing command surface (`make check`, `make build-<host>`, `make switch-<host>`, `make sops-*`)
- `statix.toml` - lint configuration for `statix`
- `.claude/`, `.planning/` - agent/planning tooling, not part of the deployed system

## Platform Requirements

**Development:**
- macOS or Linux with Nix + flakes enabled
- `make dev` shell provides all required CLIs; no host-level tool installation needed

**Production:**
- x86_64 bare-metal/VM hosts (`ser8`, `firebat`) using ZFS + disko + impermanence
- Raspberry Pi 4/5 (`pi4`, `pi5`) built from upstream `nixpkgs` with `nixos-hardware` board modules; `pi5` also uses disko
- Deployment via `nixos-anywhere`/remote build (`buildOnTarget: true` in `deploy.yaml`), reached over Tailscale (`shad-bangus.ts.net`) and LAN static IPs

---

*Stack analysis: 2026-08-17*
