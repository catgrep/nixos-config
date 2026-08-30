# Phase 14: Backup Engine - Pattern Map

**Mapped:** 2026-08-26 (re-map after the snapshot-model pivot; the prior dump-engine PATTERNS.md is superseded)
**Files analyzed:** 19 (13 new, 5 modified, 2 deleted)
**Analogs found:** 17 / 19

The pivot changes what gets built but barely changes what it should look like.
Every new artifact in this phase has a near-verbatim analog already in the repo except the two VM tests and the `checks` flake output, which are genuinely new ground.

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `hosts/ser8/backup/default.nix` (new) | config aggregator | n/a | `hosts/ser8/media/default.nix` | exact |
| `hosts/ser8/backup/datasets.nix` (new) | config (fileSystems + tmpfiles) | n/a | `hosts/ser8/impermanence.nix` L99-215 | exact |
| `hosts/ser8/backup/policy.nix` (new) | config (service enable + settings) | n/a | `hosts/ser8/configuration.nix` L113-135 (ZFS block) | exact |
| `hosts/ser8/backup/dump.nix` (new) | systemd oneshot unit | batch / file-I/O | `hosts/ser8/media/orchestration.nix` L44-66 (`media-config`) | exact |
| `hosts/ser8/backup/verify.nix` (new) | systemd oneshot + timer | batch / file-I/O | `modules/dns/adguard-home.nix` L246-269 (`pi-temp-monitor` + timer) | role-match |
| `hosts/ser8/backup/dump.sh` (new) | shell script body | batch | `hosts/ser8/media/nzbget-normalize-permissions.sh` | exact |
| `hosts/ser8/backup/verify.sh` (new) | shell script body | batch / transform | `hosts/ser8/media/nzbget-normalize-permissions.sh` | exact |
| `hosts/ser8/backup/restore/backup-restore` (new) | CLI tool | file-I/O, destructive | `hosts/ser8/media/nzbget-normalize-permissions.sh` + `pkgs.writeShellApplication` in `hosts/ser8/media/nzbget.nix` L11-18 | exact |
| `hosts/ser8/backup/README.md` (new) | runbook | n/a | `hosts/ser8/README.md` | role-match |
| `hosts/ser8/disko-config.nix` (modified) | storage declaration | n/a | itself: `backup/cameras/*` L268-290, `rpool/safe/downloads` L224-234 | exact (self) |
| `hosts/ser8/impermanence.nix` (modified) | config | n/a | itself | exact (self) |
| `hosts/ser8/configuration.nix` (modified) | host entry point | n/a | itself L10-15 (imports), L113-126 (deletion target) | exact (self) |
| `modules/servers/monitoring.nix` (modified) | exporter config | request-response | itself L31-58 (`extraFlags` on the systemd exporter) | exact (self) |
| `modules/gateway/prometheus.nix` (modified) | alert rules | pub-sub | itself L249-315 (`homelab` rule group) | exact (self) |
| `modules/servers/backup.nix` (DELETE) | dead scaffolding | n/a | n/a | n/a |
| `modules/servers/default.nix` (modified) | import list | n/a | itself | exact (self) |
| `scripts/smoketests/backup/all.sh` (new) | test entry point | n/a | `scripts/smoketests/household/all.sh` | exact |
| `scripts/smoketests/backup/test-*.sh` (new, 5) | test | request-response (SSH) | `scripts/smoketests/ser8/test-zfs-health.sh` | exact |
| `scripts/smoketests/ser8/all.sh` (modified) | test entry point | n/a | itself L28-35 | exact (self) |
| `tests/backup-layout.nix` (new) | VM test | n/a | **none in repo** (upstream `disko/lib/tests.nix:72`) | no analog |
| `tests/backup-behavior.nix` (new) | VM test | n/a | **none in repo** (upstream `nixos/tests/sanoid.nix`) | no analog |
| `flake.nix` (modified: first `checks` output) | flake output | n/a | `flake.nix` L260-309 (`devShells` per-system block) | partial |

---

## Pattern Assignments

### `hosts/ser8/backup/default.nix` (config aggregator)

**Analog:** `hosts/ser8/media/default.nix` (whole file, 18 lines)

Directory slices in this repo are a bare `default.nix` whose only job is the import list. The slice is then imported by directory name from `hosts/ser8/configuration.nix`.

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

Note the argument pattern: `{ ... }:` when nothing is used, `{ config, lib, pkgs, ... }:` when they are (`hosts/ser8/media/orchestration.nix:3-8`). Do not accept unused arguments.

**D-13's "one attrset of covered services" lives here.** There is no existing attrset-generates-config analog in this repo — the closest generative shape is the `let` binding at `modules/servers/monitoring.nix:20-29` feeding a `lib.concatStringsSep` into `extraFlags`. Keep the attrset in `default.nix` as a plain `let` binding passed to the other files via a module argument or `_module.args`, or simply define it in `datasets.nix` and reference it — the repo has no precedent for cross-file sharing, so prefer the simplest: define the covered-services attrset once in `datasets.nix` and let `policy.nix`/`verify.nix` read it from `config.fileSystems` / the pool rather than importing a Nix value across files.

---

### `hosts/ser8/backup/datasets.nix` (child datasets -> mounts + tmpfiles)

**Analog:** `hosts/ser8/impermanence.nix` lines 99-215

**tmpfiles pattern with per-service ownership and a rationale comment** (lines 111-137). This is the shape to generate from the covered-services attrset — note that every non-obvious mode carries the reason it is not the systemd default:

```nix
  systemd.tmpfiles.rules = [
    # 0750, not 0700: the postgresql module sets StateDirectoryMode to 0750 for
    # any major >= 11, so a 0700 declarative rule would fight systemd on every
    # start. PostgreSQL accepts 0750 on PGDATA.
    "d /persist/var/lib/postgresql 0750 postgres postgres -"

    # Actual stores its SQLite account/budget databases ... 0700, matching
    # services.actual's own StateDirectoryMode -- unlike Mealie/Homebox, the
    # upstream Actual module hardcodes StateDirectoryMode = "0700"
    # unconditionally, so a 0750 rule here would fight it on every start.
    "d /persist/var/lib/actual 0700 actual actual -"
  ];
```

**The entries child datasets replace** (lines 52-63) — these are the impermanence `directories` lines that D-02 removes per migrated service:

```nix
      "/var/lib/jellyfin"
      "/var/lib/sonarr"
      "/var/lib/postgresql"
      "/var/lib/mealie"
```

**Mount declaration pattern** (lines 202-214) — the existing bind mounts. A ZFS child dataset mounted at `/var/lib/<svc>` replaces the bind entry; use `fileSystems."/var/lib/<svc>" = { device = "rpool/safe/persist/<svc>"; fsType = "zfs"; }` (legacy mountpoint) mirroring the `/persist` handling, or leave the mountpoint to ZFS. The `neededForBoot` flag pattern is here:

```nix
  fileSystems."/etc/nixos" = {
    device = "/persist/etc/nixos";
    fsType = "none";
    options = [ "bind" ];
    neededForBoot = true;
  };
```

**D-08 Mosquitto:** add to the `directories` list at line 52-88, or as a child dataset. Deletions this file owns (D-16): `/var/lib/docker` entry at lines 64-67, `d /persist/var/lib/private/prowlarr` at line 181.

---

### `hosts/ser8/disko-config.nix` (modified: nested datasets + replica target)

**Analog:** itself.

**Nested dataset pattern** (lines 279-290) — children inherit the parent's options, and only the override is declared:

```nix
          "cameras/recordings" = {
            type = "zfs_fs";
            options = {
              quota = "600G";
            };
          };
```

**Full option set with per-option rationale** (lines 268-278) — the shape for `backup/persist-replica` (`canmount`, `readonly`, `mountpoint`):

```nix
          "cameras" = {
            type = "zfs_fs";
            options = {
              mountpoint = "/mnt/cameras";
              compression = "lz4";
              recordsize = "1M";       # Optimal for video files
              atime = "off";           # Reduce write overhead
              dedup = "off";           # Video has low dedup ratio, uses lots of RAM
              "com.sun:auto-snapshot" = "false"; # Frigate handles its own retention
            };
          };
```

**Block-comment rationale above a pool/dataset** (lines 294-303, 219-223) — the repo documents *why the layout is what it is* directly above the declaration, in plain language, no planning terminology. Match that for the replica dataset and the `safe/persist/<svc>` children.

**`postCreateHook`** (lines 183-185) is the precedent for a dataset that needs an imperative step at creation time:

```nix
            postCreateHook = ''
              zfs snapshot rpool/local/root@blank
            '';
```

---

### `hosts/ser8/backup/policy.nix` (services.sanoid / services.syncoid)

**Analog:** `hosts/ser8/configuration.nix` lines 113-135 — the ZFS service block this file's contents replace.

```nix
  services.zfs = {
    autoScrub = {
      enable = true;
      interval = "weekly";
    };
    zed = {
      enableMail = true;
      settings = {
        ZED_EMAIL_ADDR = [ "catgrep@sudomail.com" ];
        ZED_NOTIFY_VERBOSE = true;
        ZED_SCRUB_AFTER_RESILVER = true;
      };
    };
  };
```

Lines 119-126 (`autoSnapshot` with `frequent`/`hourly`/`daily`/`weekly`/`monthly`) are the D-16 deletion target — remove the block, do not comment it out.

**Rationale-comment style for a version/behaviour pin** — `hosts/ser8/household/postgresql.nix` (whole file) is the model for `policy.nix`'s hardest-to-read lines (why every sanoid period is explicitly `0`, why `recursive = "zfs"` and not `true`, why the second sanoid section has `autosnap = no`):

```nix
  # services.postgresql.enable arrives implicitly from
  # services.mealie.database.createLocally. Without this pin the postgresql
  # module derives its major from system.stateVersion ("24.11" on this host),
  # which selects postgresql_16 with no warning.
  #
  # Plain assignment, not a defaultable one: a mkDefault on a one-way version
  # pin is not a pin.
  services.postgresql.package = pkgs.postgresql_17;
```

Note: `lib.mkDefault` is used in `modules/` (fleet-wide defaults, e.g. `modules/servers/monitoring.nix:33`) but **not** in `hosts/ser8/` host slices, which assign directly. `policy.nix` is a host slice — assign directly.

---

### `hosts/ser8/backup/dump.nix` (backup-pgdump.service)

**Analog:** `hosts/ser8/media/orchestration.nix` lines 44-66 (`media-config`) and 68-108 (`servarrs-setup`).

**oneshot unit with an external script body sourced from a sibling `.sh` file** (lines 44-66, 85-90) — this is exactly how a generic catalog-driven dump job should be written: Nix owns the unit and the interpolated binary paths, bash lives in a real file that `shellcheck` and `shfmt` can see:

```nix
    media-config = {
      description = "Deploy all media service configurations with secrets";
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "root";
      };

      script = ''
        export CURL_BIN="${pkgs.curl}/bin/curl"
        source ${./orchestration-helpers.sh}
        set -euo pipefail
        ...
      '';
    };
```

**Ordering/dependency pattern** (lines 70-77) — the shape for `Wants=`/`After=` between `backup-pgdump.service` and `sanoid.service`:

```nix
      after = [
        "media-config.service"
        "prowlarr.service"
      ];
      requires = [ "media-config.service" ];
      wantedBy = [ "multi-user.target" ];
```

**Binary paths are interpolated from `pkgs`, never assumed on `PATH`** (`export CURL_BIN="${pkgs.curl}/bin/curl"`, `export JQ_BIN="${pkgs.jq}/bin/jq"`, line 131). Apply to `pg_dump`, `pg_dumpall`, `sqlite3`, `zfs`, `sendmail`.

`OnFailure=` has **no existing analog anywhere in the repo** (`rg OnFailure` returns nothing) — D-09's mail-on-failure unit is new construction. The mail target it drives is established: `ZED_EMAIL_ADDR = [ "catgrep@sudomail.com" ]` via `/run/wrappers/bin/sendmail`.

---

### `hosts/ser8/backup/verify.nix` (backup-verify.service + timer)

**Analog:** `modules/dns/adguard-home.nix` lines 246-269 — the only service+timer pair in the repo.

```nix
  systemd.services.pi-temp-monitor = lib.mkIf (config.networking.hostName == "pi4") {
    description = "Raspberry Pi Temperature Monitor";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.writeShellScript "pi-temp-check" ''
        ...
      ''}";
    };
  };

  systemd.timers.pi-temp-monitor = lib.mkIf (config.networking.hostName == "pi4") {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "5min";
      OnUnitActiveSec = "5min";
    };
  };
```

Two deliberate departures for this phase:
- Use `script = ''...''` + a sibling `.sh` file (the orchestration.nix pattern above) rather than an inline `writeShellScript`; the verify job is far too long to inline.
- Use `OnCalendar` + `Persistent`, not `OnBootSec`/`OnUnitActiveSec`. **Note the researched trap:** `/var/lib/systemd/timers` is not persisted on ser8, so `Persistent=true` stamps do not survive the impermanence rollback. sanoid dissolves this for the snapshot itself (state-derived), but `backup-verify` at 03:30 does not get that for free — either persist the timer stamp directory or derive freshness from the pool, and say which in a comment.
- No `lib.mkIf (config.networking.hostName == ...)` guard — this file only exists inside the ser8 host slice.

---

### `hosts/ser8/backup/restore/backup-restore`, `dump.sh`, `verify.sh` (shell)

**Analog:** `hosts/ser8/media/nzbget.nix` lines 11-18 (packaging) + `hosts/ser8/media/nzbget-normalize-permissions.sh` (body).

**Packaging pattern** — `writeShellApplication` with explicit `runtimeInputs`, body read from a real file:

```nix
let
  permissionNormalizer = pkgs.writeShellApplication {
    name = "nzbget-normalize-permissions";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.findutils
    ];
    text = builtins.readFile ./nzbget-normalize-permissions.sh;
  };
in
```

For `backup-restore`, `runtimeInputs` is roughly `[ zfs coreutils systemd sqlite postgresql ]`. Add it to `environment.systemPackages` so the operator can invoke it by name — that is what D-11's runbook indexes.

**Script body pattern** (`nzbget-normalize-permissions.sh` lines 1-40) — this is the closest thing the repo has to a safety-gated destructive tool, and it is a strong template for D-11's guards:

```bash
#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail

readonly POSTPROCESS_SUCCESS=93
readonly POSTPROCESS_ERROR=94

trap 'echo "[ERROR] Could not normalize permissions for $download_dir"; exit 94' ERR

complete_root=$(realpath -e -- "$complete_root")
download_dir=$(realpath -e -- "$download_dir")

case "$download_dir" in
"$complete_root"/*) ;;
*)
	echo "[ERROR] Refusing to modify path outside $complete_root: $download_dir"
	exit "$POSTPROCESS_ERROR"
	;;
esac
```

Copy three specific things: `realpath -e --` before any path comparison, the `case`-prefix containment check with an explicit **"Refusing to ..."** message, and the `trap ... ERR`. D-11's "refuses to touch a non-empty target without an explicit flag" and the `--rollback` gate are the same shape — refuse loudly, name the path, name the flag that would allow it.

Indentation in repo shell is **tabs** (`shfmt` default, no `-i` flag in the Makefile's lint path). Every script starts `set -euo pipefail`.

---

### `hosts/ser8/backup/README.md` (runbook)

**Analog:** `hosts/ser8/README.md` — plain `##`/`###` headings, one topic each (`## Storage Architecture`, `## Accessing Media Drive over SMB`, `## Bazarr initial setup`), operator-facing prose with literal commands. One full sentence per physical line (global CLAUDE.md). **No planning terminology** — no phase numbers, no decision IDs, no "D-11". Write the rationale itself.

---

### `modules/servers/monitoring.nix` (modified: textfile collector directory)

**Analog:** itself, lines 31-58.

```nix
  services.prometheus.exporters.node = {
    enable = lib.mkDefault true;
    port = 9100;
    enabledCollectors = [
      "cpu"
      "meminfo"
      # ...
      "systemd"
      "processes"
    ]
    ++ lib.optional (config.boot.supportedFilesystems.zfs or false) "zfs";
    openFirewall = true;
  };

  services.prometheus.exporters.systemd = {
    enable = lib.mkDefault true;
    port = 9558;
    openFirewall = true;
    extraFlags = [
      "--systemd.collector.unit-include=${monitoredUnits}"
    ];
  };
```

The `extraFlags` list on the systemd exporter is the exact slot the node exporter needs for `--collector.textfile.directory=`. Two constraints from the research: the collector is **already enabled and scraping** on ser8 (only the directory flag is missing), and the textfile directory must be persisted and reachable under the exporter's hardening. This is a `modules/` file, so `lib.mkDefault` applies here (unlike the host slices).

**Conditional-collector precedent** for making the flag ser8-only if wanted: `lib.optional (config.boot.supportedFilesystems.zfs or false) "zfs"` at line 45.

---

### `modules/gateway/prometheus.nix` (modified: staleness alerts)

**Analog:** itself, lines 249-315 — the `homelab` rule group. Add three rules to this group; do not create a new group.

```nix
    ruleFiles = [
      (pkgs.writeText "homelab-rules.yml" ''
        groups:
          - name: homelab
            rules:
              - alert: ZFSPoolUnhealthy
                expr: node_zfs_zpool_health_state{state!="online"} > 0
                for: 5m
                labels:
                  severity: critical
                annotations:
                  summary: "ZFS pool {{ $labels.pool }} is not healthy on {{ $labels.instance }}"

              - alert: CameraStorageHigh
                expr: (node_filesystem_avail_bytes{mountpoint="/mnt/cameras"} / node_filesystem_size_bytes{mountpoint="/mnt/cameras"}) * 100 < 20
                for: 5m
                labels:
                  severity: warning
                annotations:
                  summary: "Camera storage is above 80% full"
      '')
    ];
```

Structure to copy exactly: `alert` / `expr` / `for: 5m` / `labels.severity` / `annotations.summary` with `{{ $labels.instance }}` templating.

**The one deliberate departure — this is the load-bearing part of D-09.** Every existing rule in this group uses a bare threshold expression, which never fires on an absent series. `BackupSnapshotStale`, `BackupReplicaStale`, and `BackupVerifyStale` must each be `expr: <threshold> or absent(<metric>)`, and must carry a comment saying why, because the surrounding twelve rules model the opposite pattern and the next editor will copy a neighbour.

No new scrape config is needed: the metrics ride the existing `node-exporter` job (lines 24-38, `ser8.local:9100`).

---

### `scripts/smoketests/backup/all.sh` (suite entry point)

**Analog:** `scripts/smoketests/household/all.sh` (whole file, 39 lines) — near-verbatim template.

```bash
#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

# Household services smoketest entry point.
#
# [what this area covers, and why new checks belong here rather than in the
#  ser8 array]
#
# Reached from deploy.yaml through scripts/smoketests/ser8/all.sh; there is no
# separate deploy.yaml entry for this area and none is needed.
#
# Fan-out goes through `run_suite` (scripts/smoketests/lib/fanout.sh) rather
# than a bare loop: a loop's exit status is that of its last iteration, so a
# failing service check followed by a passing endpoint check would certify the
# activation. `run_suite` runs every entry and returns non-zero if any failed.

set -euo pipefail

# shellcheck source=scripts/lib/all.sh
. ./scripts/lib/all.sh
# shellcheck source=scripts/smoketests/lib/fanout.sh
. ./scripts/smoketests/lib/fanout.sh

SUITE_NAME="household"
TESTS=(
	./scripts/smoketests/household/test-mealie-service.sh
	./scripts/smoketests/household/test-mealie-endpoint.sh
)

run_suite "$@"
```

Never a bare `for` loop — `run_suite` (`scripts/smoketests/lib/fanout.sh:34`) exists because a loop's exit status is only its last iteration's.

**`scripts/smoketests/ser8/all.sh` modification** (lines 28-35): add `./scripts/smoketests/backup/all.sh` to the `TESTS` array. `deploy.yaml` needs no change — it names exactly one script per host.

---

### `scripts/smoketests/backup/test-*.sh` (5 fail-closed tests)

**Analog:** `scripts/smoketests/ser8/test-zfs-health.sh` (whole file, 192 lines) — the fail-closed template, near-verbatim.

**Header, arg handling, host resolution** (lines 1-37):

```bash
#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail

# ZFS health smoketest for ser8.
#
# [what it asserts, and WHICH assertion is load-bearing and why]

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

**The fail-closed remote helper** (lines 57-66) — this is the D-15 requirement made concrete. Empty output is a failure, never a skip:

```bash
# Run a command on the target host, returning its stdout. Empty output means
# the command could not be run or produced nothing; every caller treats that as
# a failure rather than as an inconclusive result.
remote() {
	local remote_command
	printf -v remote_command '%q ' "$@"
	# remote_command is intentionally expanded after printf %q shell escaping.
	# shellcheck disable=SC2029
	ssh "$user@$ipaddr" "$remote_command" 2>/dev/null || echo ""
}
```

**Test-function shape — every branch is explicit, the empty case is checked first** (lines 92-111):

```bash
test_pool_no_data_errors() {
	local pool="$1"
	info "checking ZFS pool '$(fmt_bold "$pool")' for data errors"

	local errors
	errors=$(remote zpool status "$pool" | grep 'errors:' || echo "")

	if [ -z "$errors" ]; then
		fail "could not read the error line of 'zpool status $pool' from $host"
		return 1
	fi

	if echo "$errors" | grep -q 'No known data errors'; then
		pass "ZFS pool '$(fmt_bold "$pool")' reports no known data errors"
		return 0
	fi

	fail "ZFS pool '$(fmt_bold "$pool")' reports data errors: $errors"
	return 1
}
```

**Runner, tally, and the zero-tests-run guard** (lines 43-55, 164-192). The `tests_run -eq 0` branch is what stops an empty suite from certifying a deployment:

```bash
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

# ... run_test "rollback_snapshot" test_rollback_snapshot || true

if [ $tests_run -eq 0 ]; then
	warn "no tests were run"
	exit 1
elif [ $tests_passed -eq $tests_run ]; then
	pass "all $tests_run ZFS health tests passed"
else
	fail "$tests_passed/$tests_run ZFS health tests passed"
	exit 1
fi
```

Also copy the **inverted-assertion comment discipline** at lines 130-141: where an assertion is non-obvious or deliberately backwards, the file explains it and names the future condition under which to flip it. The manifest-coverage test (asserting the manifest matches the *declared* coverage set) is exactly that kind of assertion.

Constants named after their source file (lines 30-37):

```bash
# Pools declared in hosts/ser8/disko-config.nix
POOLS=(
	rpool
	backup
)

# The blank snapshot hosts/ser8/configuration.nix rolls back to in stage-1
ROLLBACK_SNAPSHOT="rpool/local/root@blank"
```

---

### `flake.nix` (modified: first `checks` output)

**Analog:** `flake.nix` lines 260-309 (`devShells`) — the only per-system output block with a `let`-bound maker function.

```nix
      devShells =
        let
          makeDevShell =
            system:
            let
              pkgs = nixpkgs-unstable.legacyPackages.${system};
            in
            pkgs.mkShell { ... };
        in
        {
          x86_64-linux.default = makeDevShell "x86_64-linux";
          aarch64-darwin.default = makeDevShell "aarch64-darwin";
          # ...
        };
```

`checks` should be **x86_64-linux only** — the VM tests cannot build on darwin, and the research flags that the workstation Linux-build path must be repaired first (`determinate-nixd login`). Do not add darwin keys that will never evaluate.

The block-comment-above-an-output convention is at lines 251-253 and 311-316 (`installerConfigurations`, `enabledServices`), including the literal invocation:

```nix
      # Service discovery - maps enabled services to their packages per host
      # Query with: nix eval '.#enabledServices.ser8' --json
```

Do the same for `checks`: state what each test proves and the exact `nix build .#checks.x86_64-linux.<name>` command.

---

## Shared Patterns

### SPDX header
**Source:** every `.nix` and `.sh` file in the repo
**Apply to:** all new files in this phase except `README.md`

```
# SPDX-License-Identifier: GPL-3.0-or-later
```

First line of `.nix` files; second line of shell scripts (after the shebang).

### Module argument discipline
**Source:** `hosts/ser8/media/default.nix:3` vs `hosts/ser8/media/orchestration.nix:3-8`
**Apply to:** every new `.nix` file

`{ ... }:` when nothing is used; the full `{ config, lib, pkgs, ... }:` only when all three are. Unused arguments are not accepted anywhere in the repo.

### Binaries interpolated from `pkgs`, never assumed on `PATH`
**Source:** `hosts/ser8/media/orchestration.nix:56,86,130-131`; `hosts/ser8/media/nzbget.nix:12-16`
**Apply to:** `dump.nix`, `verify.nix`, `restore/backup-restore`

Either `export FOO_BIN="${pkgs.foo}/bin/foo"` in a systemd `script`, or `runtimeInputs = [ pkgs.foo ]` in a `writeShellApplication`.

### Bash file separated from Nix
**Source:** `hosts/ser8/media/nzbget.nix:17` (`text = builtins.readFile ./nzbget-normalize-permissions.sh;`), `hosts/ser8/media/orchestration.nix:57` (`source ${./deployment-helpers.sh}`)
**Apply to:** all three new shell artifacts

Non-trivial bash lives in a `.sh` file so `shellcheck` and `shfmt -d` can see it. Anything beyond about ten lines qualifies. The dump, verify, and restore bodies are all far past that line.

### Comments carry the reason, not the restatement
**Source:** `hosts/ser8/impermanence.nix:115-117,139-149`; `hosts/ser8/household/postgresql.nix:6-17`; `hosts/ser8/disko-config.nix:294-303`; `scripts/smoketests/ser8/test-zfs-health.sh:11-15`
**Apply to:** every file in this phase

The repo's established style: when a value fights an upstream default, or an assertion is inverted, or a layout choice is non-obvious, the comment says *what would go wrong otherwise*. Never planning terminology — no phase numbers, no decision IDs, no `PLAN.md` references, in any file outside `.planning/`.

### Failure is loud and named
**Source:** `scripts/smoketests/ser8/test-zfs-health.sh:76-79,99-102`; `hosts/ser8/media/nzbget-normalize-permissions.sh:34-40`
**Apply to:** smoketests, restore tool, verify job

Empty/unreadable input is a failure with the command that failed named in the message. Refusals name the path and the flag that would permit the action.

### Mail path
**Source:** `hosts/ser8/configuration.nix:128-135` (`ZED_EMAIL_ADDR = [ "catgrep@sudomail.com" ]`), `/run/wrappers/bin/sendmail` on ser8
**Apply to:** `OnFailure=` units and the nightly digest

One mail mechanism fleet-wide. The digest and the failure mails use the same wrapper ZED already uses.

---

## No Analog Found

| File | Role | Data Flow | Reason |
|------|------|-----------|--------|
| `tests/backup-layout.nix` | VM test (disko) | n/a | The repo has **no `tests/` directory and no `checks` flake output**. Nothing here uses `makeDiskoTest`. Use upstream `disko/lib/tests.nix:72` and RESEARCH.md's Pattern 5 (`14-RESEARCH.md:565-620`). |
| `tests/backup-behavior.nix` | VM test (nixosTest) | n/a | Same. Use the pinned nixpkgs `nixos/tests/sanoid.nix` as the skeleton — it exercises sanoid + syncoid against real ZFS pools on virtio disks, which is precisely the harness D-14 needs. RESEARCH.md `14-RESEARCH.md:1106-1152` has the derived skeleton. |

Partial-analog note: `flake.nix`'s `devShells` block gives the *output shape* for `checks`, but nothing in the repo gives the *contents*. Treat the flake wiring as an analog copy and the two test files as RESEARCH.md-driven new construction.

Also new construction with no in-repo precedent, though small: `OnFailure=` (zero occurrences repo-wide) and `OnCalendar`/`Persistent` (zero occurrences — the only existing timer uses `OnBootSec`/`OnUnitActiveSec`).

---

## Metadata

**Analog search scope:** `hosts/ser8/**`, `modules/**`, `scripts/**`, `flake.nix`, `tests/` (absent)
**Files scanned:** 24 read in full or in targeted ranges; 6 whole-repo greps (`OnCalendar|OnFailure|writeShellApplication`, `node.?exporter`, `checks|packages\.|devShells`, `exporters.node`, `systemd.timers`, import wiring)
**Pattern extraction date:** 2026-08-26
**Supersedes:** the pre-pivot PATTERNS.md built on the six-method dump-engine model (removed)
