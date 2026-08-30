---
phase: 14-backup-engine
reviewed: 2026-08-29T19:37:10Z
depth: standard
files_reviewed: 52
files_reviewed_list:
  - flake.nix
  - hosts/ser8/backup/README.md
  - hosts/ser8/backup/datasets.nix
  - hosts/ser8/backup/default.nix
  - hosts/ser8/backup/dump.nix
  - hosts/ser8/backup/dump.sh
  - hosts/ser8/backup/mail.nix
  - hosts/ser8/backup/policy.nix
  - hosts/ser8/backup/restore.nix
  - hosts/ser8/backup/restore/backup-restore
  - hosts/ser8/backup/services.nix
  - hosts/ser8/backup/verify.nix
  - hosts/ser8/backup/verify.sh
  - hosts/ser8/configuration.nix
  - hosts/ser8/disko-config.nix
  - hosts/ser8/household/postgresql.nix
  - hosts/ser8/impermanence.nix
  - hosts/ser8/media/jellyfin.nix
  - modules/common/nix.nix
  - modules/gateway/alertmanager.nix
  - modules/gateway/default.nix
  - modules/gateway/prometheus.nix
  - modules/media/sabnzbd.nix
  - modules/servers/backup.nix
  - modules/servers/default.nix
  - modules/servers/monitoring.nix
  - scripts/smoketests/backup/all.sh
  - scripts/smoketests/backup/test-dataset-properties.sh
  - scripts/smoketests/backup/test-manifest-coverage.sh
  - scripts/smoketests/backup/test-metrics.sh
  - scripts/smoketests/backup/test-no-stale-persist-dirs.sh
  - scripts/smoketests/backup/test-pgdump.sh
  - scripts/smoketests/backup/test-replica-freshness.sh
  - scripts/smoketests/backup/test-snapshot-freshness.sh
  - scripts/smoketests/backup/test-spot-integrity.sh
  - scripts/smoketests/backup/test-verify-last-run.sh
  - scripts/smoketests/gateway/all.sh
  - scripts/smoketests/gateway/test-alertmanager.sh
  - scripts/smoketests/household/test-actual-service.sh
  - scripts/smoketests/household/test-donetick-endpoint.sh
  - scripts/smoketests/household/test-donetick-service.sh
  - scripts/smoketests/household/test-homebox-endpoint.sh
  - scripts/smoketests/household/test-homebox-service.sh
  - scripts/smoketests/household/test-mealie-service.sh
  - scripts/smoketests/ser8/all.sh
  - scripts/validation/test-donetick-module.sh
  - scripts/validation/test-homebox-module.sh
  - scripts/validation/test-mealie-module.sh
  - tests/backup-behavior.nix
  - tests/backup-layout-disko.nix
  - tests/backup-layout.nix
findings:
  critical: 0
  warning: 5
  info: 0
  total: 5
status: issues_found
---

# Phase 14: Code Review Report

**Reviewed:** 2026-08-29T19:37:10Z
**Depth:** standard
**Files Reviewed:** 52 (51 read; `modules/servers/backup.nix` no longer exists — see note below)
**Status:** issues_found

## Summary

This phase adds a ZFS-based backup engine on `ser8` (per-service datasets, sanoid/syncoid snapshot and replication, nightly PostgreSQL dumps, a fail-closed verification job with holds and a manifest, a `backup-restore` operator tool, Prometheus staleness alerts routed through a new Alertmanager on `firebat`, and a fail-closed smoketest suite) plus supporting host and module changes.

I read every file end to end (not pattern-matched), traced the shell logic in `verify.sh`, `dump.sh`, and `backup-restore` against the VM test assertions in `tests/backup-behavior.nix`, cross-checked the Nix module wiring (`datasets.nix`, `disko-config.nix`, `mail.nix`, `policy.nix`, `verify.nix`, `dump.nix`) against the smoketests that assert on the same properties, and confirmed the README's worked examples match the tool's actual behavior. I did not find a correctness or security defect severe enough to block shipping. The design is unusually careful about fail-closed behavior, ordering, and privilege — every place I probed for a gap (hold accounting, mount/unmount symmetry, rollback guards, ordering vs. `wants`/`after` semantics, capability bounding) turned out to be handled deliberately and correctly.

I found five WARNING-level issues: three small robustness/consistency gaps in the new shell code, and one place where a NixOS unit deviates from the hardening standard the phase otherwise sets for itself. The fifth is dead test coverage left behind by the migration, spread across four files.

`modules/servers/backup.nix` is listed in the file set but was deleted (see `git log -- modules/servers/backup.nix`, commit `8e03888 chore(14-01): delete unused backup scaffolding`, and its import was removed from `modules/servers/default.nix` in this same diff). There is nothing to review; this is intentional cleanup of dead scaffolding predating the current design, not a regression.

## Warnings

### WR-01: Manifest row sanitization only covers one of the fields that can carry a tab or newline

**File:** `hosts/ser8/backup/verify.sh:74-79`
**Issue:** `add_row()` collapses embedded tabs/newlines only in the `result` field (position 4):
```bash
add_row() {
	local result=$4
	result=${result//$'\t'/ }
	result=${result//$'\n'/ }
	rows+=("$(printf '%s\t%s\t%s\t%s\t%s\t-' "$1" "$2" "$3" "$result" "$5")")
}
```
but `$2` (the `subject`, a file path discovered via `find ... -print0` under a service's state directory) is not sanitized, even though tabs and newlines are legal in Linux filenames. A `.db`/`.sqlite`/`.sqlite3`/`.dump` file whose name contains a literal tab (plausible for a user-renamed Homebox or Actual attachment, though the current discovery pattern is extension-limited) would shift the TSV field count for that one row; an embedded newline would split it across two physical lines, breaking simple line-oriented consumers of the manifest (`sudo awk ...` snippets in the README, `test-manifest-coverage.sh`).

This cannot mis-route a restore: `dataset`-kind rows (the ones `backup-restore`'s `manifest_hold()` actually reads to resolve the default snapshot) are built separately, directly from ZFS dataset names, which cannot contain these characters. The blast radius is limited to `sqlite`/`pgdump`/`replica` informational rows.
**Fix:**
```bash
add_row() {
	local kind=$1 subject=$2 check=$3 result=$4 size=$5
	subject=${subject//$'\t'/ }
	subject=${subject//$'\n'/ }
	result=${result//$'\t'/ }
	result=${result//$'\n'/ }
	rows+=("$(printf '%s\t%s\t%s\t%s\t%s\t-' "$kind" "$subject" "$check" "$result" "$size")")
}
```

### WR-02: Multiple simultaneous hold-release failures lose all but the last

**File:** `hosts/ser8/backup/verify.sh:418-425`
**Issue:**
```bash
placed=$snapshot_name
for old in "${held[@]}"; do
	operation="releasing the $HOLD_TAG hold on $dataset@$old"
	if ! zfs release "$HOLD_TAG" "$dataset@$old"; then
		record_failure "Could not release the $HOLD_TAG hold on $dataset@$old"
		placed=$old
	fi
done
```
This only matters when a dataset already carries more than one `last-verified` hold — the code's own comment says that state means "an earlier run did exactly that" (partially failed release-then-place). If releasing *more than one* of those stale holds fails in the same run, `placed` is overwritten on each failure, so only the last one is recorded in the manifest's hold-position field. Any earlier snapshot whose release also failed is still genuinely held on the pool (protected from pruning), but the manifest no longer says so — understating, not overstating, what's protected. Low likelihood (requires an already-degraded prior run plus a second release failure), but the accounting gap is real and the manifest is the thing `backup-restore` cross-checks pool state against.
**Fix:** Track every stale hold that failed to release, not just the last one, e.g. collect them into an array and either fail the run outright (already fail-closed elsewhere) or record all of them.

### WR-03: Dry-run for `--pg-database` never checks the archive exists

**File:** `hosts/ser8/backup/restore/backup-restore:438-467` (dry-run block) vs. `479-485` (real run)
**Issue:** The real restore validates the database archive exists before proceeding:
```bash
dump="$READABLE_ROOT/.zfs/snapshot/$snapshot/$DUMP_SUBPATH/$pg_database.dump"
[ -f "$dump" ] || die "No archive for $pg_database inside $root@$snapshot: $dump"
```
but the `--dry-run` path only prints the path it *would* use and never checks it exists:
```bash
if [ -n "$pg_database" ]; then
	printf '  database:   %s, from <tree>/%s/%s.dump inside %s\n' \
		"$pg_database" "$DUMP_SUBPATH" "$pg_database" "$snapshot"
fi
printf 'Nothing was changed.\n'
exit 0
```
A misspelled `--pg-database` (or one for a database that was dropped) previews cleanly and then fails on the real run — the one case a `--dry-run` mode exists to catch before an operator commits to stopping a unit mid-incident.
**Fix:** In the dry-run branch, resolve `readable_root` for the dump and check `[ -f "$dump" ]` the same way the real path does, and report the mismatch instead of a clean preview.

### WR-04: `backup-pgdump.service` has none of the sandboxing the sibling `backup-verify.service` uses

**File:** `hosts/ser8/backup/dump.nix:29-62`
**Issue:** `backup-verify.service` (`hosts/ser8/backup/verify.nix:44-102`) runs with `ProtectSystem = "strict"`, an explicit `ReadWritePaths` allowlist, `PrivateTmp = true`, `NoNewPrivileges = true`, and a narrow `CapabilityBoundingSet` — extensively justified in comments. `backup-pgdump.service` sets only `Type = "oneshot"` and `User = superUser` (`postgres`), with no filesystem or capability restriction at all, despite running `pg_dumpall`/`pg_dump` against catalog-derived database names and writing to disk under `/persist/var/lib/backup-dumps`. This is a smaller attack surface than `backup-verify` (postgres already has broad database access, and it's not running as root), but the inconsistency is worth closing given the phase otherwise sets a clear hardening bar for itself, and the fix is cheap: the write target is a single known directory.
**Fix:**
```nix
serviceConfig = {
  Type = "oneshot";
  User = superUser;
  ProtectSystem = "strict";
  ReadWritePaths = [ "/persist/var/lib/backup-dumps" ];
  PrivateTmp = true;
  NoNewPrivileges = true;
};
```

### WR-05: Four household smoketests carry a duplicate check left behind by the dataset migration

**File:**
- `scripts/smoketests/household/test-actual-service.sh:178-201` (`test_actual_state_dir_shape`) vs. `203-226` (`test_actual_persist_dir`)
- `scripts/smoketests/household/test-donetick-service.sh:139-162` vs. `164-187`
- `scripts/smoketests/household/test-homebox-service.sh:139-162` vs. `164-187`
- `scripts/smoketests/household/test-mealie-service.sh:273-296` vs. `298-321`

**Issue:** Each file now declares `*_PERSIST_DIR="$*_DATA_DIR"` with a comment acknowledging the reason: "Homebox's state is its own ZFS dataset mounted here, so the state path and the persisted path are one and the same; there is no longer a second copy under /persist to check separately." The `*_persist_dir` test function was originally written to catch impermanence bind-mount and tmpfiles-rule drift between two *different* paths (`/var/lib/<svc>` vs `/persist/var/lib/<svc>`). Since the migration collapsed those into one path, the retained test now runs the identical `stat` command against the identical path with the identical expected value as the sibling `*_state_dir_shape` test just above it — for example, `test-homebox-service.sh`'s two tests both run `stat -c '%U %G %a' /var/lib/homebox` and both assert `"homebox homebox 750"`. This doubles the reported test count (`tests_run`) without adding coverage, and the tests' own doc comments ("Proves the impermanence directory entry and the tmpfiles rule describe the same thing") no longer describe what they check. The meaningful successor check — that the live path really is a mounted ZFS dataset, not a plain directory riding the parent — already exists at the suite level in `scripts/smoketests/backup/test-no-stale-persist-dirs.sh` (`test_live_paths_are_datasets`).
**Fix:** Either delete the four now-redundant `*_persist_dir` test functions and their `run_test` calls, or repurpose them to assert the ZFS-specific property `test-no-stale-persist-dirs.sh` already checks generically (e.g., `findmnt -t zfs` on the path) so each service suite still has its own local assertion of that fact rather than relying implicitly on the backup suite running first.

---

_Reviewed: 2026-08-29T19:37:10Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
