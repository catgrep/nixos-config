# Phase 9: Channel Bump to NixOS 26.05 - Pattern Map

**Mapped:** 2026-08-16
**Files analyzed:** 22 (5 new, 12 modified, 5 deleted)
**Analogs found:** 17 / 17 non-deleted files

This phase is a migration, not a feature build. Most "new" code is a rewrite of an existing
file in a new option schema, so the closest analog is frequently the file's own current
contents plus a sibling that already does the target thing. Where the analog is upstream
(`nixos-hardware`), RESEARCH.md carries the verbatim upstream excerpt and is cited instead.

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `flake.nix` (mkPiSystem removal) | config | transform | `flake.nix:204-234` (`mkSystem`, same file) | exact |
| `hosts/pi4/default.nix` **NEW** | config | transform | `hosts/ser8/default.nix` | exact |
| `hosts/pi5/default.nix` **NEW** | config | transform | `hosts/ser8/default.nix` | exact |
| `hosts/pi5/configtxt.nix` (rewrite) | config | transform | upstream `nixos-hardware/raspberry-pi/common/config-txt.nix` | schema-source |
| `modules/raspberrypi/base.nix` | module | transform | itself (lines 49-58 rewritten); `modules/dns/` for host-policy split | partial |
| `modules/gateway/grafana.nix` | module | config | `grafana.nix:43-54` + `:66-69` (same file, adjacent secrets) | exact |
| `hosts/ser8/impermanence.nix` | config | file-I/O | `hosts/ser8/configuration.nix:138-176` (explicit `fsType` mounts) | exact |
| `modules/automation/home-assistant.nix` | module | config | itself (`:285-287`, `:58-69`, `:447`) | self |
| `modules/media/sabnzbd.nix` | module | config | any overlay-free `modules/media/*.nix` | role-match |
| `modules/servers/tailscale.nix` | module | config | any `pkgs.<name>` reference in `modules/` | role-match |
| `etc/nix/nix.custom.conf` | config | config | itself (`:11-13`) | self |
| `Makefile` | build | batch | itself (`:306-321` installer block) | self |
| `deploy.yaml` | config | config | `deploy.yaml:33-37` (pi5's `"test"` placeholder) | exact |
| `scripts/smoketests/media/test-zfs-health.sh` **NEW** | test | request-response | `scripts/smoketests/gateway/test-tailscale.sh` | exact |
| `scripts/smoketests/media/test-vaapi.sh` **NEW** | test | request-response | `scripts/smoketests/gateway/test-tailscale.sh` | exact |
| `scripts/smoketests/nordvpn/test-qbittorrent-confinement.sh` **NEW** | test | request-response | `scripts/smoketests/gateway/test-tailscale.sh` + `nordvpn/test-netns.sh` (for the netns commands) | exact |
| `scripts/smoketests/nordvpn/all.sh` (wire new test) | test | batch | `scripts/smoketests/nordvpn/all.sh` (same file) | self |
| `scripts/smoketests/lib/services.sh` (skip guard) | utility | request-response | `gateway/test-tailscale.sh:186-193` (skip-with-pass guard) | role-match |
| `scripts/smoketests/dns/` (3 files) | test | — | DELETE per D-15 | n/a |
| `modules/raspberrypi/installer.nix`, `usb-installer.nix` | module | — | DELETE per D-08 | n/a |

---

## Pattern Assignments

### `hosts/pi4/default.nix` and `hosts/pi5/default.nix` (NEW, config)

**Analog:** `hosts/ser8/default.nix` — the entire file, 11 lines. This is the only
`hosts/*/default.nix` in the tree and defines the convention `mkSystem` relies on
(`./hosts/${hostname}` resolves to the directory).

**Copy verbatim, changing only the import list** (`hosts/ser8/default.nix:1-11`):

```nix
# SPDX-License-Identifier: GPL-3.0-or-later

{ ... }:

{
  imports = [
    ./configuration.nix
    ./impermanence.nix
    ./samba.nix
  ];
}
```

Note the exact shape to preserve: SPDX header, blank line, `{ ... }:` (no unused args
destructured), blank line, single `imports` attrset.

**Target contents:**

- `hosts/pi4/default.nix` → `imports = [ ./configuration.nix ];`
  (`hosts/pi4/configuration.nix` already imports `hardware-configuration.nix` — verify
  before assuming; if not, list both.)
- `hosts/pi5/default.nix` → `imports = [ ./configuration.nix ./configtxt.nix ./disko-config.nix ];`
  This pulls `configtxt.nix` and `disko-config.nix` out of the flake's per-host `modules`
  list (`flake.nix:272-275`) and into the host directory, matching how ser8 keeps
  `impermanence.nix` / `samba.nix` local rather than in the flake.

---

### `flake.nix` — Pi hosts via `mkSystem` (config, transform)

**Analog:** `flake.nix:204-234` — `mkSystem` in the same file. It already accepts
`system`, `useX86Modules`, `usePiModules`; the parameters exist and are simply unused.

**The helper being deleted** (`flake.nix:176-201`):

```nix
      mkPiSystem =
        {
          hostname,
          piVersion ? "4", # "4" or "5"
          modules ? [ ],
        }:
        nixos-raspberrypi.lib.nixosSystem {
          ...
          modules = [
            nixos-raspberrypi.nixosModules."raspberry-pi-${piVersion}".base
            nixos-raspberrypi.nixosModules."raspberry-pi-${piVersion}".display-vc4
            ./hosts/${hostname}/configuration.nix
          ]
          ++ baseModules
          ++ piModules
          ++ modules;
        };
```

**The call-site pattern to copy** (`flake.nix:239-257`, ser8/firebat):

```nix
        ser8 = mkSystem {
          hostname = "ser8";
          modules = [
            ./modules/media
            ./modules/nordvpn
            ./modules/automation
            { nixpkgs.overlays = [ (import ./overlays/frigate-tflite-optional.nix) ]; }
          ];
        };

        firebat = mkSystem {
          hostname = "firebat";
          modules = [ ./modules/gateway ];
        };
```

**Target shape** for `flake.nix:259-276` — same call shape plus the three previously
unused flags:

```nix
        pi4 = mkSystem {
          hostname = "pi4";
          system = "aarch64-linux";
          useX86Modules = false;
          usePiModules = true;
          modules = [
            nixos-hardware.nixosModules.raspberry-pi-4
            ./modules/dns
          ];
        };

        pi5 = mkSystem {
          hostname = "pi5";
          system = "aarch64-linux";
          useX86Modules = false;
          usePiModules = true;
          modules = [
            nixos-hardware.nixosModules.raspberry-pi-5
            disko.nixosModules.disko
          ];
        };
```

**Keep** `piModules` (`flake.nix:171-173`) untouched — it is `[ ./modules/raspberrypi/base.nix ]`
and `mkSystem` already consumes it via `usePiModules`.

**Delete alongside:** the `unstable` comment blocks at `flake.nix:186-187` and `:216-217`
(stale after the tailscale move, per Pitfall 10), the `nixConfig` cachix block at
`flake.nix:60-67`, the input block at `:25-33`, and `installerConfigurations` at `:292-316`.
Do **not** delete the `unstable` `specialArgs` plumbing itself — D-11 keeps the input.

---

### `hosts/pi5/configtxt.nix` (rewrite, config)

**Analog:** upstream `nixos-hardware/raspberry-pi/common/config-txt.nix` is the schema
source. There is no in-repo analog for the new shape — this file is the first consumer.

**Current shape being replaced** (`hosts/pi5/configtxt.nix`, verbatim structure):

```nix
  hardware.raspberry-pi.config = {
    all = {
      options = {
        enable_uart   = { enable = true; value = true; };
        uart_2ndstage = { enable = true; value = true; };
      };
      base-dt-params = {
        pciex1     = { enable = true; value = "on"; };
        pciex1_gen = { enable = true; value = "3"; };
      };
    };
  };
```

**Target shape** (RESEARCH.md Pattern 3, lines 346-366):

```nix
  hardware.raspberry-pi.configtxt.settings.all = {
    # NOTE: this list REPLACES the module default `lib.mkDefault [ "audio=on" ]`
    # from config-txt-defaults.nix, so audio=on must be re-listed explicitly.
    dtparam = [ "audio=on" "pciex1=on" "pciex1_gen=3" ];
  };
```

Two constraints the planner must carry into the plan:

1. `dtparam` is a plain list at normal priority — it outranks upstream's `mkDefault
   [ "audio=on" ]`. Omitting `audio=on` silently drops it.
2. **Drop `enable_uart` / `uart_2ndstage` entirely.** Upstream's defaults file sets
   `pi5.enable_uart = lib.mkDefault false` deliberately (ghost input into boot); the
   current values were fork-install serial-console debugging aids.

**File header to preserve** (existing `hosts/pi5/configtxt.nix:1-8`):

```nix
# SPDX-License-Identifier: GPL-3.0-or-later

{
  config,
  pkgs,
  lib,
  ...
}:
```

Trim unused args once the body no longer references them — `{ ... }:` per
`hosts/ser8/default.nix` if none are used.

---

### `modules/raspberrypi/base.nix` (module, transform)

**Analog:** itself. Only lines 49-58 are fork-coupled; the networking, udev, and
`boot.tmp.useTmpfs` blocks above must survive untouched (anti-pattern: deleting the file).

**Block being replaced** (`modules/raspberrypi/base.nix:48-58`, verbatim):

```nix
  # System tags for identification
  system.nixos.tags =
    let
      cfg = config.boot.loader.raspberryPi;
    in
    [
      "raspberry-pi-${cfg.variant}"
      cfg.bootloader
      config.boot.kernelPackages.kernel.version
    ];
```

**Target — Option B from RESEARCH.md Pitfall 6** (declare interface in the reusable
module, set policy in the host). This is the repo's two-layer convention:

```nix
  options.homelab.raspberryPi.variant = lib.mkOption {
    type = lib.types.enum [ "4" "5" ];
    description = "Raspberry Pi board revision, used for boot-menu tagging.";
  };

  config = {
    system.nixos.tags = [
      "raspberry-pi-${config.homelab.raspberryPi.variant}"
      "extlinux"
      config.boot.kernelPackages.kernel.version
    ];
  };
```

Note: introducing `options` forces the whole file into the `{ options = ...; config = ...; }`
shape. The file is currently a bare config attrset, so every existing top-level key
(`networking`, `systemd.network.networks`, `environment.systemPackages`,
`services.udev.extraRules`, `boot.tmp.useTmpfs`) must move under `config`. If the planner
prefers to avoid that churn, dropping `system.nixos.tags` entirely is a sanctioned
alternative (RESEARCH.md calls it cosmetic).

**Also add to this file** (D-03, Pattern 2 — plain assignment beats nixos-hardware's
`lib.mkDefault`):

```nix
  boot.kernelPackages = pkgs.linuxPackages;
```

`pkgs` is already in the file's arg list (`base.nix:3-8`).

---

### `modules/gateway/grafana.nix` (module, config)

**Analog:** the same file, lines 43-54 and 66-69. Two SOPS secrets already follow the exact
pattern the new `grafana_secret_key` needs.

**Secret declaration pattern** (`modules/gateway/grafana.nix:43-54`, verbatim):

```nix
  sops.secrets.grafana_admin_password = {
    owner = "grafana";
    group = "grafana";
    mode = "0400";
  };

  # SOPS secret for Grafana SMTP password (Gmail App Password)
  sops.secrets.grafana_smtp_password = {
    owner = "grafana";
    group = "grafana";
    mode = "0400";
  };
```

**Consumption pattern** (`modules/gateway/grafana.nix:66-69`, verbatim):

```nix
      security = {
        admin_user = "admin";
        admin_password = "$__file{${config.sops.secrets.grafana_admin_password.path}}";
      };
```

**Target — add a third secret in the identical shape, and one line inside `security`:**

```nix
  # SOPS secret for Grafana secret_key. 26.05 removed the option's default; this
  # pins the LEGACY upstream constant so existing grafana.db ciphertext stays
  # decryptable. Compatibility pin, not a security decision.
  sops.secrets.grafana_secret_key = {
    owner = "grafana";
    group = "grafana";
    mode = "0400";
  };
```

```nix
      security = {
        admin_user = "admin";
        admin_password = "$__file{${config.sops.secrets.grafana_admin_password.path}}";
        secret_key = "$__file{${config.sops.secrets.grafana_secret_key.path}}";
      };
```

The SOPS value written into `secrets/firebat.yaml` via `make sops-edit-firebat` must be the
legacy constant `SW2YcwTIb9zpOOhoPsMm`, not a freshly generated key.

---

### `hosts/ser8/impermanence.nix` (config, file-I/O)

**Analog:** `hosts/ser8/configuration.nix:138-176` — every other `fileSystems` entry in the
repo already carries an explicit `fsType` (`fuse.mergerfs`, `tmpfs`), so the two bind mounts
are the only outliers.

**Current** (`hosts/ser8/impermanence.nix:172-183`, verbatim):

```nix
fileSystems."/etc/nixos" = {
  device = "/persist/etc/nixos";
  options = [ "bind" ];
  neededForBoot = true;
};

fileSystems."/var/log" = {
  device = "/persist/var/log";
  options = [ "bind" ];
  neededForBoot = true;
};
```

**Target** — one line each, `fsType` placed after `device` to match sibling ordering:

```nix
fileSystems."/etc/nixos" = {
  device = "/persist/etc/nixos";
  fsType = "none";          # 26.05: no longer defaults to "auto"
  options = [ "bind" ];
  neededForBoot = true;
};

fileSystems."/var/log" = {
  device = "/persist/var/log";
  fsType = "none";
  options = [ "bind" ];
  neededForBoot = true;
};
```

`fileSystems."/persist"` at `:25` is expected to get `fsType` from disko by merge — confirm
by eval (`make check`), do not pre-emptively edit.

---

### New smoketests: `test-zfs-health.sh`, `test-vaapi.sh`, `test-qbittorrent-confinement.sh` (test, request-response)

**Analog:** `scripts/smoketests/gateway/test-tailscale.sh` — the only test in the tree with
a real pass/fail harness and a non-zero exit on failure. Copy its skeleton exactly.
Do **not** use `nordvpn/test-netns.sh` as the structural analog: it is a diagnostic dump
inside a single heredoc with no assertions and always exits 0. Borrow only its
`sudo ip netns exec wgnord ...` command vocabulary for the confinement test.

**Header + arg handling** (`gateway/test-tailscale.sh:1-21`, verbatim):

```bash
#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail

# <one-line description>
# <what it asserts>

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

**Test harness** (`gateway/test-tailscale.sh:37-53`, verbatim):

```bash
# Track test results
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
```

**Individual test function shape** (`gateway/test-tailscale.sh:56-65`, verbatim):

```bash
test_tailscale_daemon() {
  info "checking Tailscale daemon status"
  if ssh "$user@$ipaddr" 'systemctl is-active --quiet tailscaled'; then
    pass "tailscaled service is running"
    return 0
  else
    fail "tailscaled service is not running"
    return 1
  fi
}
```

**Skip-with-pass guard** (`gateway/test-tailscale.sh:186-193`) — the exact pattern to reuse
for the D-16 `.vofi` guard and for any "tool not present on host" case:

```bash
  if ! ssh "$user@$ipaddr" "command -v openssl >/dev/null 2>&1"; then
    warn "openssl not available on $host, skipping TLS certificate check for $service_name"
    # Count as passed since we can't test without openssl
    pass "$service_name TLS check skipped (openssl not installed)"
    return 0
  fi
```

**Summary block** (`gateway/test-tailscale.sh:280-290`, verbatim — this is what makes the
test a real gate):

```bash
# Summary
echo
if [ $tests_run -eq 0 ]; then
  warn "no tests were run"
  exit 1
elif [ $tests_passed -eq $tests_run ]; then
  pass "all $tests_run <Area> tests passed"
else
  fail "$tests_passed/$tests_run <Area> tests passed"
  exit 1
fi
```

**Section grouping** (`gateway/test-tailscale.sh:247-254`):

```bash
echo
info "=== Tailscale Daemon Tests ==="
run_test "tailscale_daemon" test_tailscale_daemon || true
run_test "tailscale_connected" test_tailscale_connected || true
```

**Remote-command escaping** — required whenever the remote command is built from an array
rather than a single-quoted literal (`gateway/test-tailscale.sh:126-131`, verbatim):

```bash
  local remote_command
  local remote_args=(dig +short "$domain")
  printf -v remote_command '%q ' "${remote_args[@]}"
  # remote_command is intentionally expanded after printf %q shell escaping.
  # shellcheck disable=SC2029
  dns_result=$(ssh "$user@$ipaddr" "$remote_command" 2>/dev/null || echo "")
```

**Indentation:** `gateway/*.sh` uses 2 spaces; `media/all.sh` uses tabs; `nordvpn/*.sh` uses
4 spaces. New files should match the directory they land in. Run `shfmt -d` on each.

**Per-test subject matter** (from D-14, commands only — structure comes from the analog):

| New file | Assertions |
|---|---|
| `media/test-zfs-health.sh` | `zpool status -x rpool` / `backup` reports healthy; `zfs list -t snapshot rpool/local/root@blank` exists (impermanence rollback depends on it); no feature-flag upgrade nag |
| `media/test-vaapi.sh` | `/dev/dri/renderD128` present; `vainfo` lists VAAPI profiles; jellyfin/frigate units active |
| `nordvpn/test-qbittorrent-confinement.sh` | qBittorrent's PID is inside netns `wgnord`; egress IP from within the netns differs from the host's; port 8080 answers on localhost via the nginx proxy |

---

### `scripts/smoketests/nordvpn/all.sh` (test, batch)

**Analog:** the same file. Append the new test to the array; no other change.

```bash
TESTS=(
    ./scripts/smoketests/nordvpn/test-veth-interfaces.sh
    ./scripts/smoketests/nordvpn/test-forwarding.sh
    ./scripts/smoketests/nordvpn/test-qbittorrent.sh
    ./scripts/smoketests/nordvpn/test-anonymity.sh
)
```

Note `media/all.sh` has **no** `TESTS=()` array — it is a monolithic script that inlines
its checks. Wiring `media/test-zfs-health.sh` and `media/test-vaapi.sh` therefore requires
either invoking them from the bottom of `media/all.sh` or restructuring `media/all.sh` to
the `nordvpn/all.sh` array shape. The array shape is the better pattern; flag the choice
in the plan.

---

### `scripts/smoketests/lib/services.sh` — `.vofi` skip guard (utility)

**Analog:** the skip-with-pass guard at `gateway/test-tailscale.sh:186-193` (excerpt above).

**Code being guarded** (`scripts/smoketests/lib/services.sh:13-18`, verbatim):

```bash
    info "using host 'pi4' as the DNS server"
    dns_ipaddr=$(get_ip "pi4")

    # First check if we can resolve the domain using the AdGuard DNS server
    if ! nslookup "$domain" "$dns_ipaddr" >/dev/null 2>&1; then
        warn "DNS resolution failed for $domain using AdGuard DNS, trying with Host header"
```

Key finding from RESEARCH.md Pitfall 9: `test_service()` **already** degrades to the
Host-header path when pi4 does not answer. The tests are not failing — they emit a `warn`
per service. The guard's job is to skip the pi4 lookup and the `warn` and go straight to
the Host-header branch, so the D-16 flag belongs here, not in `media/all.sh`.

Suggested guard (env var, per CONTEXT "Claude's Discretion"):

```bash
    # D-16: pi4 AdGuard is disconnected pending retirement. Skip the DNS path
    # until .vofi ownership is re-established (Phase 10).
    if [ "${SKIP_VOFI_DNS:-1}" = "1" ]; then
        dns_ipaddr=""
    else
        info "using host 'pi4' as the DNS server"
        dns_ipaddr=$(get_ip "pi4")
    fi
```

Note the existing file uses 4-space indent and has **no** `set -euo pipefail` (it is sourced,
not executed) and no shebang-driven execution path — preserve that.

---

### `deploy.yaml` (config)

**Analog:** the pi5 entry in the same file (`deploy.yaml:33-37`) — it already uses the
`"test"` placeholder that pi4 needs once `scripts/smoketests/dns/` is deleted.

**Current pi4 entry** (`deploy.yaml:25-30`, verbatim):

```yaml
  pi4:
    targetHost: "192.168.68.56"
    targetUser: "bdhill"
    buildOnTarget: true
    tags: ["dns", "arm", "raspberrypi"]
    smoketests: "./scripts/smoketests/dns/all.sh"
```

**Precedent to copy** (`deploy.yaml:33-37`, verbatim):

```yaml
  pi5:
    targetHost: "192.168.0.110"
    targetUser: "nixos"
    buildOnTarget: true
    tags: ["arm", "raspberrypi"]
    smoketests: "test"
```

**Target:** pi4's `smoketests:` becomes `"test"`. Consider whether the `"dns"` tag should
also go, given D-06 records pi4 as "disconnected, pending retirement/repurpose" — the tag
is what a future `--tag dns` deploy would select.

---

## Shared Patterns

### SPDX header

**Source:** every `.nix` and `.sh` file in the tree
**Apply to:** all new files (`hosts/pi{4,5}/default.nix`, the three new `test-*.sh`)

```nix
# SPDX-License-Identifier: GPL-3.0-or-later
```

For shell scripts it goes on line 2, after the shebang:

```bash
#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
```

### Shell script preamble

**Source:** `scripts/smoketests/gateway/test-tailscale.sh:1-21`
**Apply to:** all three new `test-*.sh` files

`set -euo pipefail` → `. ./scripts/lib/all.sh` → `title "$0"` → arg check → `get_ip` /
`get_user`. Note that `nordvpn/test-netns.sh` puts `set -euo pipefail` *after* the source
line — follow `gateway/test-tailscale.sh` (before), which is the CLAUDE.md-conformant order.

### Logging helpers

**Source:** `scripts/lib/logging.sh:20-26`
**Apply to:** all new `test-*.sh`

`info` (yellow), `warn` (pink), `pass` (green), `fail` (red, stderr), `title` (blue banner),
`fmt_bold` for inlining names. Never `echo` a result — always route through `pass`/`fail`
so the output format stays uniform.

### Host resolution

**Source:** `scripts/lib/yq.sh:7-9`
**Apply to:** all new `test-*.sh`

```bash
get_ip() { yq -e eval ".hosts.$1.targetHost" "$DEPLOY_YAML"; }
get_user() { yq -e eval ".hosts.$1.targetUser" "$DEPLOY_YAML"; }
```

Never hard-code an IP in a smoketest — `deploy.yaml` is the source of truth. The one
existing violation (`nordvpn/test-netns.sh:44` pings `192.168.68.56` literally) is a
counter-example, not a pattern; and that address is pi4, which this phase is retiring.

### SOPS secret declaration

**Source:** `modules/gateway/grafana.nix:43-47`
**Apply to:** the new `grafana_secret_key` secret

```nix
  sops.secrets.<name> = {
    owner = "<service-user>";
    group = "<service-group>";
    mode = "0400";
  };
```

Consumed by Grafana via the `"$__file{${config.sops.secrets.<name>.path}}"` interpolation.

### Verification commands (already in the flake, use them)

**Source:** `flake.nix:375-519` — `enabledServices`, `servicePackages`, `packageInfo`
**Apply to:** every commit in D-09's staging

```bash
nix eval --json '.#enabledServices.ser8'
nix eval --json '.#packageInfo.ser8'
```

Capture on the 25.11 lock before edits, diff after. This is the cheapest regression check
in the repo and it already exists — do not hand-roll a config differ.

---

## No Analog Found

| File | Role | Data Flow | Reason |
|------|------|-----------|--------|
| `hosts/pi5/configtxt.nix` (new schema) | config | transform | `hardware.raspberry-pi.configtxt.settings` has zero existing consumers in-tree. Schema source is upstream `nixos-hardware/raspberry-pi/common/config-txt.nix`; RESEARCH.md Pattern 3 (lines 332-381) carries the verified before/after and both default-collision traps. |
| `modules/raspberrypi/base.nix` `options.homelab.*` block | module | transform | The repo has no existing custom `homelab.*` option namespace to copy from. If the planner wants a precedent, check `modules/subgen/` before inventing one; otherwise Option B in RESEARCH.md Pitfall 6 is the spec. |
| `hosts/pi4/hardware-configuration.nix` | config | file-I/O | **Do not touch.** Hard-coded UUIDs describe the currently-running pi4 disk. Listed here so the planner does not treat its absence from the change list as an oversight. |

---

## Metadata

**Analog search scope:** `hosts/`, `modules/`, `scripts/smoketests/`, `scripts/lib/`,
`flake.nix`, `deploy.yaml`, `Makefile`
**Files read this session:** `hosts/ser8/default.nix`, `hosts/pi5/configtxt.nix`,
`modules/raspberrypi/base.nix`, `scripts/smoketests/gateway/test-tailscale.sh`,
`scripts/smoketests/nordvpn/test-netns.sh`, `scripts/smoketests/nordvpn/all.sh`,
`scripts/smoketests/lib/services.sh`, `scripts/smoketests/media/all.sh` (head),
`flake.nix:160-289`, `deploy.yaml`, `modules/gateway/grafana.nix` (grepped ranges)
**Pattern extraction date:** 2026-08-16
