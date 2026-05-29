# Repository Guidelines

## Project Structure & Module Organization

This repository is a NixOS homelab flake. `flake.nix` wires host systems, module groups, dev shells, packages, and service metadata. Host-specific configuration lives in `hosts/<host>/` for `ser8`, `firebat`, `pi4`, and `pi5`. Reusable NixOS modules live in `modules/`, grouped by concern: `common/`, `servers/`, `media/`, `gateway/`, `dns/`, `automation/`, `nordvpn/`, and `raspberrypi/`. Operational scripts are under `scripts/`, smoketests under `scripts/smoketests/<area>/`, Grafana JSON dashboards under `dashboards/`, and SOPS-encrypted secrets under `secrets/`.

## Build, Test, and Development Commands

Use `make dev` to enter the Nix development shell with `nixfmt`, `statix`, `sops`, `yq`, `caddy`, and related tools. Run `make check` before opening a PR; it executes `nix flake check`, `statix check`, and dry-run builds for every host. Use `make fmt` for all Nix files and `make fmt-caddy` for `modules/gateway/Caddyfile`. Host workflows use `HOST` suffixes, for example `make build-ser8`, `make test-firebat`, `NO_CONFIRM=true make switch-pi4`, and `make smoketests-ser8`. Use `make list-hosts` and `make info-HOST` to inspect deployment metadata from `deploy.yaml`.

## Coding Style & Naming Conventions

Format Nix with `nixfmt-rfc-style`; do not hand-align code against formatter output. Keep module filenames lowercase and kebab-case, such as `adguard-home.nix` or `jellyfin-exporter.nix`. Prefer small, focused modules imported through each directory's `default.nix`. Preserve `GPL-3.0-or-later` headers where present. Shell scripts should stay POSIX-aware unless they already require Bash or Zsh.

## Testing Guidelines

The main validation path is `make check`. Add or update smoketests in `scripts/smoketests/<area>/` when changing deployed services, networking, DNS, gateway behavior, or media automation. Keep test entrypoints named `all.sh` for areas that are referenced from `deploy.yaml`, and use descriptive `test-*.sh` filenames for individual checks.

## Commit & Pull Request Guidelines

Recent commits use short, scoped subjects like `flake: add nurl to devshell`, `modules: update caddy-tailscale hash`, and `tools: add sagent`. Follow `scope: imperative summary`, keeping the scope to a host, module, service, or file. PRs should describe affected hosts/modules, list validation commands run, note any required secret or deployment steps, and include dashboard screenshots or exported JSON diffs when Grafana assets change.

## Security & Configuration Tips

Never commit plaintext credentials. Use `make sops-edit-HOST`, `make sops-edit-shared`, and the helper scripts in `scripts/sops/` for secrets. Be careful with `switch-HOST`, `reboot-HOST`, and `apply-HOST`; pass `NO_CONFIRM=true` only in intentional non-interactive runs.
