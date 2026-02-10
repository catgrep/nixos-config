# Coding Conventions

**Analysis Date:** 2026-02-09

## Naming Patterns

**Files:**
- Nix modules follow lowercase with hyphens: `caddy.nix`, `frigate.nix`, `qbittorrent.nix`
- Module directories follow lowercase: `modules/common/`, `modules/media/`, `modules/gateway/`
- Bash scripts follow lowercase with hyphens: `test-caddy.sh`, `test-dns.sh`
- Configuration files: `configuration.nix`, `hardware-configuration.nix`, `disko-config.nix`, `impermanence.nix`
- Dashboard files: `node-exporter.json`, `zfs.json` (from Grafana)
- SOPS secret files: `ser8.yaml`, `shared.yaml`

**Functions:**
- Nix: Function arguments use lowercase with underscores: `config`, `lib`, `pkgs`, `unstable`
- Bash: Function names use lowercase with underscores: `get_ip()`, `get_user()`, `resolve_ssh_host()`, `test_media_service()`
- No camelCase used in either Nix or Bash

**Variables:**
- Nix local variables in `let` bindings use camelCase for descriptive names: `caddyWithTailscale`, `dashboards`, `cfg`
- Nix configuration uses dot-notation: `config.services.caddy`, `config.sops.secrets`
- Bash global variables use UPPERCASE: `TESTS`, `MEDIA_SERVICES`, `LABEL_INFO`, `BOLD`, `RED`, `GREEN`
- Bash local variables use lowercase: `host`, `ipaddr`, `user`, `domain`, `response`

**Types:**
- Nix types use full names: `lib.types.str`, `lib.types.path`, `lib.types.port`, `lib.types.bool`
- lib.mk* helpers distinguish between merge strategies: `lib.mkDefault`, `lib.mkForce`, `lib.mkIf`, `lib.mkMerge`

## Code Style

**Formatting:**
- Tool: `nixfmt` with RFC style (`nixfmt-rfc-style`)
- Run before commit: `make fmt`
- Indentation: 2 spaces in Nix
- Indentation: 2 spaces in Bash for continuations

**Linting:**
- Nix files validated via flake check: `make check` runs `nix flake check`
- Bash scripts enforce strict mode: `set -euo pipefail` at top of each test script
- No specific linter used for Bash, but scripts use shell best practices

## Import Organization

**Nix Module Order:**
1. SPDX license header (always first)
2. Module function signature with `{config, lib, pkgs, ...}:`
3. `let` bindings for local definitions (if needed)
4. `in` keyword followed by configuration
5. `{ imports = [...]; ... }` structure for aggregation modules

**Nix Let Bindings:**
- Define intermediate computations before configuration block
- Example from `modules/gateway/caddy.nix`: Define `caddyWithTailscale` in `let`, use in `in { ... }`
- Example from `modules/gateway/grafana.nix`: Define `dashboards` let-binding with source paths

**Bash Script Order:**
1. SPDX license header
2. Source includes: `. ./scripts/lib/all.sh`
3. `set -euo pipefail` for strict error handling
4. Title output: `title "$0"`
5. Parameter validation
6. Variable assignment
7. Function definitions
8. Main logic

**Path Aliases:**
- Nix uses relative paths with `./`: `./modules/`, `../../secrets/`
- No import aliases defined; always use relative paths
- Bash scripts source from relative paths: `./scripts/lib/all.sh`

## Error Handling

**Patterns in Nix:**
- Conditional configuration via `lib.mkIf`: Wrap entire sections or merge strategies when feature is disabled
- SOPS secret declarations use `lib.mkIf` to only create when service is enabled
- Example from `modules/automation/frigate.nix`:
  ```nix
  sops.secrets = lib.mkIf config.services.frigate.enable { ... };
  ```
- Dependency ordering via `systemd.services.<name>.after` and `requires` for service startup
- Example from `modules/automation/frigate.nix`:
  ```nix
  systemd.services.frigate = lib.mkIf config.services.frigate.enable {
    after = [ "zfs-mount.service" "network-online.target" "sops-nix.service" ];
    requires = [ "zfs-mount.service" ];
  };
  ```

**Patterns in Bash:**
- Return codes: `0` on success, `1` on failure
- Non-fatal issues trigger warning: `warn "message"` to stderr
- Fatal issues trigger failure: `fail "message"` to stderr and `exit 1`
- Example from `scripts/smoketests/dns/test-dns.sh`:
  ```bash
  if ! resolves google.com "$ipaddr"; then
      exit 1
  fi
  ```
- Fallback behavior on DNS failure: Try Host header, then HTTP instead of HTTPS
- Example from `scripts/smoketests/lib/services.sh`: Multiple curl attempts with different strategies

**Systemd Service Error Handling:**
- `Restart = "on-failure"` with `RestartSec = "5s"` for auto-recovery
- `Type = "exec"` for straightforward services
- Timeouts specified: `TimeoutStartSec = "5min"` for long-startup services like Caddy
- Example from `modules/gateway/caddy.nix`:
  ```nix
  serviceConfig = {
    TimeoutStartSec = "5min";
    ...
  };
  ```

## Logging

**Framework:** `printf` for Bash (custom logging library in `scripts/lib/logging.sh`)

**Patterns:**
- Color-coded output with functions: `info()`, `warn()`, `pass()`, `fail()`
- Example from `scripts/lib/logging.sh`:
  ```bash
  info() { printf "${BOLD}${YELLOW}%-6s${RESET} %b\n" "${LABEL_INFO}" "$1"; }
  pass() { printf "${BOLD}${GREEN}%-6s${RESET} %b\n" "${LABEL_DONE}" "$1"; }
  fail() { printf "${BOLD}${RED}%-6s${RESET} %b\n" "${LABEL_FAIL}" "$1" >&2; }
  ```
- Test progress output: `title()` for section headers
- Structured format: `[info]`, `[WARN]`, `[FAIL]`, `[done]` labels with colored output

**Nix Logging:**
- No explicit logging; relies on systemd journal via `systemctl status`
- Service debugging: SSH into host and check logs with `journalctl -u <service> -n 50`
- API key sanitization documented in service configs to prevent secrets exposure

## Comments

**When to Comment:**
- Explain the "why" not the "what" - code structure is self-explanatory from reading
- Document security decisions: "Allow insecure Frigate packages (has known CVE, but we're behind firewall/Tailscale)"
- Reference external issues/discussions: "See: https://github.com/blakeblackshear/frigate/discussions/14888"
- Mark deprecated or conditionally-used code with comments
- Explain non-obvious configuration requirements: "Note: hostname must be set unconditionally as the NixOS module requires it"

**Example from `modules/automation/frigate.nix` (lines 16-18):**
```nix
# Allow insecure Frigate packages (has known CVE, but we're behind firewall/Tailscale)
# See: https://github.com/blakeblackshear/frigate/security/advisories/GHSA-vg28-83rp-8xx4
nixpkgs.config.permittedInsecurePackages = lib.mkIf config.services.frigate.enable [
```

**Example from `modules/gateway/caddy.nix` (lines 50-54):**
```nix
# Ensure Caddy restarts when systemd-resolved restarts
# This is needed because Caddy caches DNS lookups and won't pick up
# new DNS config until restarted
{
  after = [ "systemd-resolved.service" ];
```

**JSDoc/TSDoc:**
- Not used; this is Nix/Bash, not TypeScript
- Internal documentation uses inline comments in Nix modules

## Function Design

**Size:**
- Bash test functions typically 20-50 lines (e.g., `test_media_service()` is 40 lines)
- Bash library functions are utility-focused and small (5-15 lines)
- Nix modules define service config in single file per service (30-150 lines)

**Parameters:**
- Bash: Use positional parameters with validation: `if [ $# -lt 1 ]; then exit 1; fi`
- Bash: Extract and name early: `host="$1"`, `ipaddr="$2"`, `user="$3"`
- Nix: Always accept `{ config, lib, pkgs, ... }` in module function signature
- Nix: Use `let cfg = config.services.<name>;` for DRY access to service config

**Return Values:**
- Bash: Functions return status codes (0 = pass, 1 = fail)
- Bash: Output to stdout with `echo`, logging to stderr with `printf "..." >&2`
- Nix: No explicit returns; all files are attribute sets or function applications

## Module Design

**Exports:**
- Nix modules always export a single attribute set: `{ imports = [...]; options = {}; config = {}; }`
- No module explicitly "exports" - all are imported in parent modules via `imports = [ ./file.nix ]`
- Example from `modules/common/default.nix`:
  ```nix
  {
    imports = [
      ./banner.nix
      ./boot.nix
      ./networking.nix
      ...
    ];
  }
  ```

**Barrel Files (Index Files):**
- `modules/*/default.nix` acts as aggregation point
- Collects sub-modules via `imports` list
- No re-exports or complex barrel logic
- Example from `modules/media/default.nix`:
  ```nix
  { ... }:
  {
    imports = [
      ./jellyfin.nix
      ./sonarr.nix
      ./radarr.nix
      ...
    ];
  }
  ```

## License and Headers

**All files start with:**
```nix
# SPDX-License-Identifier: GPL-3.0-or-later
```

**Applied to:**
- `.nix` files: Nix modules, flake.nix
- `.sh` files: Bash scripts in `scripts/`
- `Makefile`: Build automation
- YAML files: deploy.yaml, .sops.yaml

## Secrets Management

**Pattern:**
- Secrets declared in `sops.secrets` block at top of module
- Key format: `"secret_name"` maps to YAML key in `secrets/<host>.yaml` or `secrets/shared.yaml`
- Ownership specified: `owner = "service"`, `group = "service"`, `mode = "0600"`
- Template substitution: Use `sops.templates` to inject secrets into service environment files
- Example from `modules/automation/frigate.nix`:
  ```nix
  sops.secrets."frigate_cam_user" = {
    owner = "root";
    group = "root";
    mode = "0600";
  };

  sops.templates."frigate.env" = {
    content = ''
      FRIGATE_CAM_USER=${config.sops.placeholder."frigate_cam_user"}
      FRIGATE_CAM_PASS=${config.sops.placeholder."frigate_cam_pass"}
    '';
  };
  ```

**Never:**
- Hardcode credentials in `.nix` files
- Commit `.env` or secrets files
- Include actual secret values in comments or examples

---

*Convention analysis: 2026-02-09*
