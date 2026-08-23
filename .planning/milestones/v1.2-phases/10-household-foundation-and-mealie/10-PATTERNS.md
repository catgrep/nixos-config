# Phase 10: Household Foundation and Mealie - Pattern Map

**Mapped:** 2026-08-17
**Files analyzed:** 14 (6 new Nix, 4 new shell, 6 edits — some files counted once)
**Analogs found:** 12 / 14

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|---|---|---|---|---|
| `modules/household/default.nix` (NEW) | module aggregator | config | `modules/media/default.nix` | exact |
| `modules/household/mealie.nix` (NEW) | reusable module | request-response (web svc) | `modules/media/prowlarr.nix` | exact |
| `modules/household/postgresql.nix` (NEW) | reusable module | CRUD (datastore) | `modules/media/prowlarr.nix` | role-match |
| `hosts/ser8/household/default.nix` (NEW) | host aggregator | config | `hosts/ser8/media/default.nix` | exact |
| `hosts/ser8/household/mealie.nix` (NEW) | host policy | request-response | `hosts/ser8/media/jellyfin.nix` (settings-heavy) / `hosts/ser8/media/bazarr.nix` (minimal) | exact |
| `hosts/ser8/household/postgresql.nix` (NEW) | host policy | CRUD | `hosts/ser8/media/bazarr.nix` | role-match |
| `flake.nix` (EDIT: ser8 modules list) | config | config | `flake.nix:194-201` itself | exact |
| `hosts/ser8/configuration.nix` (EDIT: imports) | config | config | `hosts/ser8/configuration.nix:11-15` itself | exact |
| `hosts/ser8/impermanence.nix` (EDIT: tmpfiles) | config | file-I/O | `hosts/ser8/impermanence.nix:108-112` itself | exact |
| `modules/gateway/Caddyfile` (EDIT: tsnet vhost) | config/route | request-response | `Caddyfile:99-105` (jellyfin block) | exact |
| `scripts/smoketests/household/all.sh` (NEW) | test suite entry | batch | `scripts/smoketests/ser8/all.sh` (fanout) | exact |
| `scripts/smoketests/household/test-mealie-service.sh` (NEW) | test | request-response | `scripts/smoketests/ser8/test-home-assistant.sh` | exact |
| `scripts/smoketests/household/test-mealie-endpoint.sh` (NEW) | test | request-response | `scripts/smoketests/gateway/test-tailscale.sh` | exact |
| `scripts/smoketests/ser8/all.sh` (EDIT) | test suite entry | batch | itself | exact |
| `scripts/smoketests/gateway/test-tailscale.sh` (EDIT: EXPECTED_NODES) | test | request-response | itself, lines 27-35 | exact |
| `scripts/validation/test-mealie-module.sh` (NEW) | validation gate | batch (offline eval) | `scripts/validation/test-actual-module.sh` | exact |
| `Makefile` (EDIT: `check` target) | config | batch | `Makefile:140-146` | exact |

**Important correction to RESEARCH.md:** `scripts/smoketests/ser8/all.sh` **already exists** and `deploy.yaml:16` **already points at it** with a working `run_suite` fan-out (`scripts/smoketests/lib/fanout.sh`). D-11 is a one-line array append, not new infrastructure.

---

## Pattern Assignments

### `modules/household/default.nix` (module aggregator)

**Analog:** `modules/media/default.nix:1-17` (verbatim shape)

```nix
# SPDX-License-Identifier: GPL-3.0-or-later

{ ... }:

{
  imports = [
    ./jellyfin.nix
    ./sonarr.nix
    # ...
  ];
}
```

Flat `imports` list, `{ ... }:` signature, SPDX header line 1, no `let`, no options.

---

### `modules/household/mealie.nix` (reusable module, request-response)

**Analog:** `modules/media/prowlarr.nix` — the only in-repo precedent for overriding an upstream `DynamicUser` module (Decision Point 1 Option B).

**Full analog structure** (`modules/media/prowlarr.nix:1-61`):

```nix
# SPDX-License-Identifier: GPL-3.0-or-later

{
  config,
  lib,
  ...
}:

{
  options.services.prowlarr = {
    useVpnNamespace = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Run Prowlarr in NordVPN network namespace for anonymization";
    };
  };

  config = {
    # Create dedicated prowlarr system group
    users.groups.prowlarr = lib.mkIf config.services.prowlarr.enable { };

    # Create dedicated prowlarr system user
    users.users.prowlarr = lib.mkIf config.services.prowlarr.enable {
      isSystemUser = true;
      group = "prowlarr";
      home = "/var/lib/prowlarr";
      description = "Prowlarr";
    };

    services.prowlarr = {
      enable = lib.mkDefault false;
    };

    # Override systemd service to use static user instead of DynamicUser
    systemd.services.prowlarr = lib.mkIf config.services.prowlarr.enable (
      lib.mkMerge [
        {
          serviceConfig = {
            DynamicUser = lib.mkForce false;
            User = "prowlarr";
            Group = "prowlarr";
          };
        }
      ]
    );

    # Open Prowlarr port when enabled
    networking.firewall.allowedTCPPorts = lib.mkIf config.services.prowlarr.enable [ 9696 ];
  };
}
```

**Copy exactly:**
- `{ config, lib, ... }:` signature, SPDX header, `options` block only if a new option is genuinely needed (Mealie likely needs none — drop the `options` stanza and the `config = { ... }` wrapper along with it, like `modules/media/bazarr.nix`).
- Every stanza guarded by `lib.mkIf config.services.mealie.enable`.
- `enable = lib.mkDefault false` so importing is inert.
- Literal port in the firewall list (`9000`) — prowlarr hardcodes `9696`; bazarr uses `config.services.bazarr.listenPort`. Prefer `config.services.mealie.port` if the option exists.
- `DynamicUser = lib.mkForce false;` + **explicit `Group`** (upstream mealie.nix sets `User` with no `Group`).

**Simpler guarded variant** (`modules/media/bazarr.nix:10-25`, quoted in RESEARCH.md:273-291) — no `options`/`config` wrapper, top-level attrs. Use this shape if no custom option is added.

---

### `modules/household/postgresql.nix` (reusable module, CRUD)

**No in-repo analog for PostgreSQL specifically** — `rg "services.postgresql"` returns zero hits outside `.planning/`. Use `modules/media/prowlarr.nix` for the *file shape* (SPDX, `{ config, lib, ... }`, `enable = lib.mkDefault false`, `lib.mkIf` guards) and RESEARCH.md for the option semantics.

Note: postgres already has an impermanence entry at `hosts/ser8/impermanence.nix:60` (`"/var/lib/postgresql"`) placed in anticipation.

---

### `hosts/ser8/household/default.nix` (host aggregator)

**Analog:** `hosts/ser8/media/default.nix:1-19`

```nix
# SPDX-License-Identifier: GPL-3.0-or-later

{ ... }:

{
  imports = [
    ./sops.nix
    ./permissions.nix
    ./jellyfin.nix
    # ...
  ];
}
```

No `sops.nix` needed this phase (CONTEXT.md `## Existing Code Insights`: `createLocally` peer auth has no password).

---

### `hosts/ser8/household/mealie.nix` (host policy, request-response)

**Minimal-policy analog** (`hosts/ser8/media/bazarr.nix:1-7`, entire file):

```nix
# SPDX-License-Identifier: GPL-3.0-or-later

_:

{
  services.bazarr.enable = true;
}
```

Note the `_:` argument form when no args are used.

**Settings-heavy policy analog** (`hosts/ser8/media/jellyfin.nix:1-8, 52-59`) — the shape when the host module carries real configuration:

```nix
# SPDX-License-Identifier: GPL-3.0-or-later

{
  config,
  lib,
  pkgs,
  ...
}:

let
  # host-specific helpers / values live in let
in
{
  services.jellyfin.enable = true;

  services.jellyfin-exporter = {
    enable = true;
    apiKeyFile = config.sops.secrets.jellyfin_api_key.path;
  };
```

Mealie's file follows this second shape: `enable = true`, `package = unstable.mealie`, `settings` (`BASE_URL`, `ALLOW_SIGNUP = "false"` as a **string**, `TZ`), `database.createLocally = true`, `extraOptions`.

**No analog for the `unstable` specialArg consumer.** `flake.nix:172-177` provides it and carries the comment:

```nix
          specialArgs = {
            inherit inputs;
            # Retained with no in-tree consumers: Phase 10 needs this plumbing.
            unstable = import nixpkgs-unstable {
              inherit system;
              config.allowUnfree = true;
            };
          };
```

`rg "unstable\." hosts/ modules/` finds only `modules/common/nix.nix:35` (registry pin). This host module is the **first** consumer — add `unstable` to the module argument set: `{ config, lib, pkgs, unstable, ... }:`.

---

### `hosts/ser8/household/postgresql.nix` (host policy, CRUD)

**Analog:** `hosts/ser8/media/bazarr.nix` (minimal host-policy shape). Body is the plain pin:

```nix
  services.postgresql.package = pkgs.postgresql_17;
```

Plain assignment, **not** `lib.mkDefault` (RESEARCH.md Anti-Patterns, FOUND-04). Requires `{ pkgs, ... }:` signature rather than `_:`.

---

### `flake.nix` (EDIT — ser8 module list)

**Exact edit site, `flake.nix:194-201`:**

```nix
      nixosConfigurations = {
        # Main media server (Beelink SER8)
        ser8 = mkSystem {
          hostname = "ser8";
          modules = [
            ./modules/media
            ./modules/nordvpn
            ./modules/automation
          ];
        };
```

Append `./modules/household` to this list. **Not** `x86Modules` (`flake.nix:148-153` — reaches firebat), **not** `piModules` (`flake.nix:155-157`).

---

### `hosts/ser8/configuration.nix` (EDIT — imports)

**Edit site, lines 11-15:**

```nix
  imports = [
    ./hardware-configuration.nix
    ./disko-config.nix
    ./media
  ];
```

Append `./household`.

---

### `hosts/ser8/impermanence.nix` (EDIT — tmpfiles)

**Existing persistence, already sufficient** (lines 38-41 and 60):

```nix
      {
        directory = "/var/lib/private";
        mode = "0700";
      }
...
      "/var/lib/postgresql"
```

**The dead rule to resurrect, line 112:**

```nix
    # "d /persist/var/lib/postgresql 0700 postgres postgres -"
```

**tmpfiles pattern to copy for ownership fixes** (lines 108-111):

```nix
    # Fix permissions for service directories after user creation
    "d /persist/var/lib/jellyfin 0755 jellyfin media -"
    "Z /persist/var/lib/jellyfin 0755 jellyfin media - -"
    "d /var/lib/jellyfin 0755 jellyfin media -"
    "Z /var/lib/jellyfin 0755 jellyfin media -"
```

The `d` + `Z` pair on both the `/persist` and `/var/lib` path is the established convention. For a DynamicUser-under-`/var/lib/private` service the precedent is line 150: `"d /persist/var/lib/private/prowlarr 0755 prowlarr prowlarr -"`.

---

### `modules/gateway/Caddyfile` (EDIT — one tsnet vhost)

**Analog:** lines 99-105, jellyfin block:

```
# -- Media *Arr services
https://jellyfin.shad-bangus.ts.net {
	log tailscale {
		level DEBUG
	}
	bind tailscale/jellyfin
	reverse_proxy 192.168.68.65:8096
}
```

Copy verbatim with `mealie`/`:9000`. Tabs, not spaces (`make fmt-caddy` enforces). Use the static IP `192.168.68.65` documented at lines 90-96 — never `ser8.local`.

**Do NOT copy** the `header_up Upgrade` / `header_up Connection "Upgrade"` pair from the Frigate/Home Assistant blocks (Caddyfile:186-200) — see RESEARCH.md Anti-Patterns.

---

### `scripts/smoketests/household/all.sh` (test suite entry, batch)

**Analog:** `scripts/smoketests/ser8/all.sh:22-39` — the `run_suite` contract:

```bash
set -euo pipefail

# shellcheck source=scripts/lib/all.sh
. ./scripts/lib/all.sh
# shellcheck source=scripts/smoketests/lib/fanout.sh
. ./scripts/smoketests/lib/fanout.sh

SUITE_NAME="ser8"
TESTS=(
	./scripts/smoketests/media/all.sh
	./scripts/smoketests/nordvpn/all.sh
	./scripts/smoketests/ser8/test-zfs-health.sh
)

run_suite "$@"
```

`run_suite` (`scripts/smoketests/lib/fanout.sh:35-67`) already answers the "how does fan-out handle per-area exit codes" discretion item: it runs every entry, prints `pass "$suite suite: N/M tests passed"`, and returns non-zero if any failed. Do not hand-roll a loop.

`SUITE_NAME="household"`. Paths in `TESTS` are repo-root-relative (`./scripts/...`) — all suites assume cwd is the repo root.

---

### `scripts/smoketests/household/test-mealie-service.sh` (test, request-response)

**Analog:** `scripts/smoketests/ser8/test-home-assistant.sh` — near line-for-line reusable.

**Header + arg handling** (lines 1-35):

```bash
#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail

# <why this test earns its place>

. ./scripts/lib/all.sh

title "$0"

if [ $# -lt 1 ]; then
	info "Usage: $0 <host>"
	exit 1
fi

host="$1"
ipaddr=$(get_ip "$host")
user=$(get_user "$host")
```

**Test harness + remote helper** (lines 37-62):

```bash
tests_run=0
tests_passed=0

run_test() {
	local test_name="$1"
	local test_func="$2"
	shift 2

	((tests_run += 1))
	if "$test_func" "$@"; then
		((tests_passed += 1))
		return 0
	fi
	warn "test failed: $test_name"
	return 1
}

# Run a command on the target host, returning its stdout.
remote() {
	local remote_command
	printf -v remote_command '%q ' "$@"
	# remote_command is intentionally expanded after printf %q shell escaping.
	# shellcheck disable=SC2029
	ssh "$user@$ipaddr" "$remote_command" 2>/dev/null || echo ""
}
```

**Unit-active probe** (lines 65-80), **HTTP probe with accepted status set** (lines 83-99):

```bash
	local response
	response=$(remote curl -s -o /dev/null -w '%{http_code}' --connect-timeout 5 --max-time 15 \
		"http://${HASS_HTTP_HOST}:${HASS_HTTP_PORT}/")

	case "$response" in
	200 | 301 | 302 | 303 | 401 | 403)
		pass "..."
		return 0
		;;
	esac

	fail "..."
	return 1
```

**Journal-error probe** (lines 106-124) — directly applicable to Mealie, which runs Alembic migrations on first start (D-06 is one-way):

```bash
	local errors
	errors=$(remote journalctl -b -u "$HASS_UNIT" --priority=err --no-pager -q -o cat)

	if [ -z "$errors" ]; then
		pass "no error-level journal entries ... in the current boot"
		return 0
	fi
```

**Summary footer** (lines 136-146):

```bash
echo
if [ $tests_run -eq 0 ]; then
	warn "no tests were run"
	exit 1
elif [ $tests_passed -eq $tests_run ]; then
	pass "all $tests_run Home Assistant tests passed"
else
	fail "$tests_passed/$tests_run Home Assistant tests passed"
	exit 1
fi
```

Note: this file is tab-indented; `scripts/smoketests/gateway/test-tailscale.sh` is 2-space indented. Follow the tab convention of the newer files (`ser8/test-home-assistant.sh`, `smoketests/lib/*.sh`); `shfmt -d` is the arbiter.

---

### `scripts/smoketests/household/test-mealie-endpoint.sh` (test, request-response)

**Analog:** `scripts/smoketests/gateway/test-tailscale.sh` — the tsnet URL probes.

**Domain constant + node list** (lines 23-35):

```bash
# Tailscale domain suffix
TS_DOMAIN="shad-bangus.ts.net"

EXPECTED_NODES=(
  "jellyfin"
  "sabnzbd"
  ...
)
```

**HTTPS probe against a tsnet name** (lines 143-179) — note the probe originates on the remote host via ssh because only tailnet members can resolve the name:

```bash
  local response
  local remote_command
  local remote_args=(
    curl -s -o /dev/null -w '%{http_code}'
    --connect-timeout 10 --max-time 15
    "https://$domain"
  )
  printf -v remote_command '%q ' "${remote_args[@]}"
  # shellcheck disable=SC2029
  response=$(ssh "$user@$ipaddr" "$remote_command" 2>/dev/null || echo "000")

  if [[ "$response" =~ ^(200|301|302|303|401|403)$ ]]; then
```

**DNS probe** (lines 120-140) uses `dig +short "$domain"` through the same `printf %q` + ssh escape.

**Edit to this same file:** append `"mealie"` to `EXPECTED_NODES` (line 27-35). The gateway suite runs against firebat, so the mealie node gets DNS/HTTPS/TLS coverage there for free.

---

### `scripts/validation/test-mealie-module.sh` (validation gate, offline eval)

**Analog:** `scripts/validation/test-actual-module.sh:1-57` — near-identical purpose (assert a resolved module's shape via `nix eval`, no deployment).

```bash
set -euo pipefail

project_root=$(git rev-parse --show-toplevel)
cd "$project_root"

host=ser8
failures=0

check_eval() {
	local label=$1 expr=$2 expected=$3 actual
	actual=$(nix eval --json "$expr")
	if [ "$actual" != "$expected" ]; then
		echo "FAIL: $label is $actual, expected $expected" >&2
		failures=$((failures + 1))
		return
	fi
	echo "ok: $label = $actual"
}

check_eval \
	"config.services.actual.settings.dataDir" \
	".#nixosConfigurations.${host}.config.services.actual.settings.dataDir" \
	'"/var/lib/actual"'

if [ "$failures" -ne 0 ]; then
	echo "$failures assertion(s) failed: ..." >&2
	exit 1
fi

echo "✓ 26.05 services.actual module confirmed on $host"
```

**Key conventions to copy:** `git rev-parse --show-toplevel` + `cd`; a `check_eval label expr expected` helper; `nix eval --json` with `.#nixosConfigurations.<host>.config...` / `.options...` attr paths; JSON-quoted expected values (`'"..."'`); accumulate `failures` rather than early-exit; evaluation errors deliberately propagate (no `|| default` fallback — that would make the gate certify nothing); final `✓` line. Assert against **option existence/type** where the goal is "the right module resolved" (lines 37-45) and against **config values** where the goal is "the right value is set".

Natural Mealie assertions: `config.services.mealie.package` name contains 3.22.0, `settings.BASE_URL == "https://mealie.shad-bangus.ts.net"`, `settings.ALLOW_SIGNUP == "false"` (string, catching Pitfall 1), `services.postgresql.package` major == 17.

---

### `Makefile` (EDIT — `check` target)

**Edit site, lines 140-146:**

```make
check:
	@nix flake check
	@statix check
	@./scripts/validation/test-nzbget-permissions.sh
	@./scripts/validation/test-actual-module.sh
	@./scripts/validation/test-pi-bootloader.sh
	@$(call success_msg,"✓ Flake check passed")
```

Append `@./scripts/validation/test-mealie-module.sh` to the run of `@./scripts/validation/*.sh` lines, before the `success_msg`.

---

### `scripts/smoketests/ser8/all.sh` (EDIT)

Already exists; already wired in `deploy.yaml:16`. One-line append to `TESTS` (lines 30-37):

```bash
TESTS=(
	./scripts/smoketests/media/all.sh
	./scripts/smoketests/nordvpn/all.sh
	./scripts/smoketests/ser8/test-zfs-health.sh
	./scripts/smoketests/ser8/test-vaapi.sh
	./scripts/smoketests/ser8/test-frigate.sh
	./scripts/smoketests/ser8/test-home-assistant.sh
)
```

The file's header comment (lines 4-20) documents the fan-out rationale; extend it if the household area's addition warrants a note.

---

## Shared Patterns

### SPDX header
**Source:** every `.nix` and `.sh` file in the repo
**Apply to:** all new files
```
# SPDX-License-Identifier: GPL-3.0-or-later
```
Line 1 of `.nix` files; line 2 of `.sh` files (after the shebang).

### Two-layer module split
**Source:** `modules/media/*.nix` + `hosts/ser8/media/*.nix`
**Apply to:** all new Nix files
Reusable layer declares user/group/firewall/systemd overrides with `enable = lib.mkDefault false` and every stanza guarded by `lib.mkIf config.services.<svc>.enable`. Host layer sets `enable = true` and all host-identifying values (URLs, package pins, secrets) in one file per service.

### Smoketest preamble
**Source:** `scripts/smoketests/ser8/test-home-assistant.sh:1-29`
**Apply to:** both new `test-*.sh` files
```bash
#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail

. ./scripts/lib/all.sh

title "$0"

if [ $# -lt 1 ]; then
	info "Usage: $0 <host>"
	exit 1
fi

host="$1"
ipaddr=$(get_ip "$host")
user=$(get_user "$host")
```
`get_ip` / `get_user` read `deploy.yaml`, keeping addresses out of scripts. Logging helpers `title` / `info` / `pass` / `fail` / `warn` / `fmt_bold` come from `scripts/lib/all.sh` — never `echo` a result line directly.

### SSH remote-command escaping
**Source:** `scripts/smoketests/ser8/test-home-assistant.sh:56-62`
**Apply to:** every remote probe
```bash
	local remote_command
	printf -v remote_command '%q ' "$@"
	# remote_command is intentionally expanded after printf %q shell escaping.
	# shellcheck disable=SC2029
	ssh "$user@$ipaddr" "$remote_command" 2>/dev/null || echo ""
```
The `shellcheck disable=SC2029` with its justification comment is required — the repo's zero-warnings policy makes an unannotated disable a defect.

### Suite fan-out
**Source:** `scripts/smoketests/lib/fanout.sh:35-67`
**Apply to:** `scripts/smoketests/household/all.sh`
Set `SUITE_NAME` and `TESTS`, call `run_suite "$@"`. Never a bare `for` loop — its exit status is only the last iteration's.

---

## No Analog Found

| File | Role | Data Flow | Reason |
|---|---|---|---|
| `modules/household/postgresql.nix` | reusable module | CRUD | No `services.postgresql` config exists anywhere in the repo (`rg` confirms). Use `modules/media/prowlarr.nix` for file shape only; option semantics from RESEARCH.md / STACK.md. |
| `unstable.mealie` package override | host policy | config | `flake.nix:172-177` provides the `unstable` specialArg with the comment "Retained with no in-tree consumers: Phase 10 needs this plumbing." This phase creates the first consumer — no precedent for the module argument or the override expression. |
| Takeout JSON structure notes doc | documentation | file-I/O | Discretionary location under `.planning/`; no structural analog needed. |

---

## Metadata

**Analog search scope:** `modules/`, `hosts/ser8/`, `scripts/smoketests/`, `scripts/validation/`, `flake.nix`, `Makefile`, `deploy.yaml`
**Files scanned:** 18 read, ~40 listed
**Pattern extraction date:** 2026-08-17
