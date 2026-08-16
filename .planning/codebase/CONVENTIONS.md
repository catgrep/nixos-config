# Coding Conventions

**Analysis Date:** 2026-08-17

## Naming Patterns

**Files:**
- Nix module files use lowercase kebab-case: `modules/media/jellyfin-exporter.nix`, `modules/gateway/blackbox-exporter.nix`.
- Every directory of related modules has a `default.nix` that aggregates `imports`, e.g. `modules/media/default.nix`.
- Shell scripts use lowercase kebab-case with a `.sh` extension and a `test-` prefix for individual smoketests/validation checks: `scripts/smoketests/ser8/test-vaapi.sh`, `scripts/validation/test-nzbget-permissions.sh`.
- Suite entry points that fan out to multiple test scripts are always named `all.sh` (required because `deploy.yaml` references this exact filename per host/tag): `scripts/smoketests/ser8/all.sh`, `scripts/smoketests/media/all.sh`.
- Shared shell helpers live under `scripts/lib/` (repo-wide) and `scripts/smoketests/lib/` (smoketest-only), named after their responsibility: `logging.sh`, `cleanup.sh`, `fanout.sh`, `services.sh`.

**Nix attributes/options:**
- Standard NixOS option paths (`services.<name>.*`, `users.users.<name>.*`, `networking.firewall.*`) — no custom naming scheme; matches upstream nixpkgs conventions.

**Shell functions/variables:**
- Local shell variables are `lower_snake_case` (`remote_command`, `service_user`, `tests_run`).
- Constants and array names that stay fixed for a script's lifetime are `UPPER_SNAKE_CASE` (`RENDER_NODE`, `VAAPI_ENCODER`, `SERVICE_USERS`, `TESTS`, `SUITE_NAME`).
- Test predicate functions are prefixed `test_`: `test_render_node_present`, `test_vaapi_encode`, `test_unit_active` (`scripts/smoketests/ser8/test-vaapi.sh`).
- Private/internal helper functions inside a shared lib file are prefixed with an underscore: `_try_host_header`, `_try_resolved_address` (`scripts/smoketests/lib/services.sh`).

## Code Style

**Nix formatting:**
- Format with `nixfmt-rfc-style` via `make fmt` (`find . -name "*.nix" -exec nixfmt {} \;`). Do not hand-align against formatter output (per project CLAUDE.md).
- `statix check` runs as part of `make check` for lint-level Nix issues.

**Shell formatting:**
- All scripts start with `#!/usr/bin/env bash` followed immediately by `# SPDX-License-Identifier: GPL-3.0-or-later`, then `set -euo pipefail`.
- Indentation uses tabs (visible in `scripts/smoketests/ser8/test-vaapi.sh` and others), consistent with `shfmt` defaults for bash.
- Run `shellcheck script.sh` and `shfmt -d script.sh` on changed scripts before committing.
- `# shellcheck disable=SC<code>` is used sparingly and only with an explanatory comment directly above it, e.g. in `scripts/smoketests/ser8/test-vaapi.sh`:
  ```bash
  # remote_command is intentionally expanded after printf %q shell escaping.
  # shellcheck disable=SC2029
  if ssh "$user@$ipaddr" "$remote_command" 2>/dev/null; then
  ```

## Import Organization (Nix)

**Module aggregation:**
- Each module group directory has a `default.nix` whose entire body is an `imports` list of sibling files, in the order they are referenced elsewhere (roughly deployment/dependency order), e.g. `modules/media/default.nix`:
  ```nix
  { ... }:
  {
    imports = [
      ./jellyfin.nix
      ./jellyfin-exporter.nix
      ./sonarr.nix
      ./radarr.nix
      ./bazarr.nix
      ./prowlarr.nix
      ./qbittorrent.nix
      ./sabnzbd.nix
      ./nzbget.nix
    ];
  }
  ```
- Host configs (`hosts/<host>/`) import module-group `default.nix` files, never individual submodules directly, keeping the module group's internal composition private to the group.

**Shell sourcing:**
- Shared shell libraries are sourced with a leading `. ./scripts/lib/...` (dot syntax, not `source`), always with a `# shellcheck source=<path>` directive immediately above when the source path is dynamic or otherwise non-obvious to shellcheck:
  ```bash
  # shellcheck source=scripts/lib/all.sh
  . ./scripts/lib/all.sh
  # shellcheck source=scripts/smoketests/lib/fanout.sh
  . ./scripts/smoketests/lib/fanout.sh
  ```
- `scripts/lib/all.sh` acts as a barrel file that sources the other `scripts/lib/*.sh` helpers (`logging.sh`, `cleanup.sh`, `yq.sh`, `ssh.sh`, `prompt.sh`) so consumers only need one source line.

## Error Handling

**Shell scripts:**
- Every script sets `set -euo pipefail` unconditionally — no exceptions found in `scripts/`.
- Assertion helpers accumulate failures into a counter and `exit 1` at the end rather than failing fast mid-script, so every check runs and reports (`scripts/validation/test-actual-module.sh`, `scripts/smoketests/ser8/test-vaapi.sh`). This mirrors the "run everything, then report" pattern used at the suite level (`run_suite` in `scripts/smoketests/lib/fanout.sh`).
- Individual `run_test`/check invocations are explicitly allowed to fail without aborting the whole script via `|| true`, since the script's own summary logic (not `set -e`) determines the exit code:
  ```bash
  run_test "render_node_present" test_render_node_present || true
  ```
- Diagnostic-only steps that should never affect pass/fail are explicitly commented as such and also use `|| true`, e.g. `report_vaapi_driver || true` in `scripts/smoketests/ser8/test-vaapi.sh`.
- Validation scripts that assert against `nix eval` output deliberately do NOT wrap the eval call in a fallback — evaluation failures are allowed to propagate so the gate can't silently pass on a masked error (documented explicitly in `scripts/validation/test-actual-module.sh`).

**Nix:**
- `lib.mkForce` is used sparingly and only where a documented conflict with an upstream module default requires it, e.g. `services.jellyfin.group = lib.mkForce "media";` in `modules/media/jellyfin.nix`.

## Comments

**Rationale-first commenting:** Scripts consistently open with a prose block explaining *why* the script exists and *why* it is built the way it is, not just what it does. Example header pattern from `scripts/smoketests/ser8/all.sh`:
```bash
# ser8 smoketest entry point.
#
# deploy.yaml names exactly one script per host, so this is the only path
# `make smoketests-ser8` reaches. Before it existed the entry pointed straight
# at the media suite, which left the NordVPN checks unreachable...
```
This pattern recurs in `scripts/smoketests/lib/fanout.sh`, `scripts/smoketests/ser8/test-vaapi.sh`, `scripts/validation/test-actual-module.sh`, and `scripts/smoketests/lib/services.sh`. Follow it for any new script: explain the failure mode the script prevents, not just its mechanics.

**Inline comments:** Used to justify non-obvious choices (timeouts, magic numbers, disabled lint rules), not to restate the code. E.g. "One second of 320x240 keeps the check fast" above `test_vaapi_encode`.

**TODO/FIXME:** Rare and explicit about their own status. Existing instances:
- `scripts/sops/status.sh:6` and `scripts/sops/add-user.sh:8`: `# FIXME: commenting these out for now since its easier for me to use my gpg key`
- `modules/common/tmux.nix:3`: `# TODO - host variable for status-bg color`

New TODO/FIXME comments should follow this style — short, specific, and tied to a concrete follow-up, not vague markers.

**License headers:** Every `.nix` and `.sh` file in this repo carries `# SPDX-License-Identifier: GPL-3.0-or-later` as the first (or second, after shebang) line. Preserve this on all new and edited files.

## Function Design

**Shell:**
- Test predicate functions take explicit positional arguments (`local test_name="$1"`) rather than relying on globals where avoidable, and return `0`/`1` for pass/fail rather than printing ad hoc.
- Remote command construction consistently uses an array + `printf -v remote_command '%q ' "${remote_args[@]}"` pattern before shipping the command over `ssh`, to avoid quoting bugs:
  ```bash
  local remote_args=(sudo -n -u "$service_user" ffmpeg -hide_banner ...)
  printf -v remote_command '%q ' "${remote_args[@]}"
  ```
- HTTP-connectivity helper functions accept `domain`/`service_name` and try HTTPS then HTTP, returning on first success (`_try_host_header`, `_try_resolved_address` in `scripts/smoketests/lib/services.sh`).

**Nix modules:**
- Modules are small and single-service-scoped (one file per service: `jellyfin.nix`, `sonarr.nix`, `qbittorrent.nix`), aggregated by a group `default.nix`. New services should follow the same one-file-per-service pattern rather than growing an existing file.

## Module Design (Nix)

**Exports:** Nix modules export via the standard `{ config, lib, pkgs, ... }: { ... }` module function signature; no custom export mechanism.

**Grouping:** Related services that form one logical subsystem are grouped under a shared directory imported as a unit by the host (`modules/media/`, `modules/gateway/`, `modules/nordvpn/`, `modules/automation/`, `modules/dns/`). Do not assume every file under `modules/` is active — some remain unimported or commented out; always check the relevant `default.nix` (per project CLAUDE.md).

---

*Convention analysis: 2026-08-17*
