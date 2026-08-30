---
phase: 14-backup-engine
fixed_at: 2026-08-29T21:00:00Z
review_path: .planning/phases/14-backup-engine/14-REVIEW.md
iteration: 1
findings_in_scope: 5
fixed: 5
skipped: 0
status: all_fixed
---

# Phase 14: Code Review Fix Report

**Fixed at:** 2026-08-29T21:00:00Z
**Source review:** .planning/phases/14-backup-engine/14-REVIEW.md
**Iteration:** 1

**Summary:**
- Findings in scope: 5
- Fixed: 5
- Skipped: 0

Verification for every fix ran directly in the isolated worktree (repo-relative, checked out from `main`): `bash -n`, `shellcheck`, and `shfmt -d` for the shell changes, and `nixfmt --check` plus a targeted `nix eval` against the built `ser8` configuration for the Nix change. All results below are reproducible from that worktree's commit history before it was fast-forwarded onto `main`.

## Fixed Issues

### WR-01: Manifest row sanitization only covers one of the fields that can carry a tab or newline

**Files modified:** `hosts/ser8/backup/verify.sh`
**Commit:** ee666e6
**Applied fix:** `add_row()` now sanitizes the `subject` field (tabs and newlines collapsed to spaces) the same way it already sanitized `result`, closing the gap where a database filename containing a literal tab or newline could shift or split a manifest row. Verified with `bash -n`, `shellcheck`, and `shfmt -d`, all clean.

### WR-02: Multiple simultaneous hold-release failures lose all but the last

**Files modified:** `hosts/ser8/backup/verify.sh`
**Commit:** f014f7a
**Applied fix:** The manifest's format allows exactly one snapshot name per dataset row, and that field is compared byte-for-byte against live pool state by `backup-restore`'s `resolve_default_snapshot()` (a mismatch there already refuses to pick a default and sends the operator to `--list`). Embedding multiple stale-hold names in the single field would silently break that comparison. Instead, the release loop now counts failures; when more than one stale hold fails to release in the same pass, the hold position is recorded as unresolved (`-`) rather than naming just the last survivor. This routes the ambiguous case through the restore tool's existing fail-closed check instead of understating what remains held, which is the same operator-facing outcome the review's first suggested option ("fail the run outright") produces. Every individual release failure was already recorded in `failures[]` for the run's mail digest and `run_status`, both before and after this change. Verified with `bash -n`, `shellcheck`, and `shfmt -d`, all clean.

Classified in REVIEW.md as an accounting/logic issue (not a simple mechanical fix); the change alters control flow around a rarely-exercised failure path (requires an already-degraded prior run plus a second release failure in the same pass). Flagging as **fixed: requires human verification** per the logic-bug rule in the fixer's verification strategy, since no test in the current suite exercises the double-release-failure branch.

### WR-03: Dry-run for `--pg-database` never checks the archive exists

**Files modified:** `hosts/ser8/backup/restore/backup-restore`
**Commit:** 9a9303b
**Applied fix:** The `--dry-run` branch now calls `readable_root "$root"` and checks `[ -f "$preview_dump" ]` for the requested database's archive, mirroring the real restore path, and calls `die` with the same message on a missing archive instead of printing a clean preview. This lets a misspelled or dropped `--pg-database` value fail during dry-run, which is the scenario dry-run exists to catch before an operator stops a unit mid-incident. The `readable_root` mount it may perform is read-only and already cleaned up by the script's existing `release_mounts` EXIT trap. Verified with `bash -n`, `shellcheck`, and `shfmt -d`, all clean.

### WR-04: `backup-pgdump.service` has none of the sandboxing the sibling `backup-verify.service` uses

**Files modified:** `hosts/ser8/backup/dump.nix`
**Commit:** 86d4e66
**Applied fix:** Added `ProtectSystem = "strict"`, `ReadWritePaths = [ "/persist/var/lib/backup-dumps" ]`, `PrivateTmp = true`, and `NoNewPrivileges = true` to `backup-pgdump.service`'s `serviceConfig`, matching the fix suggested in the review. `CapabilityBoundingSet` was intentionally left as-is, matching the review's own reasoning: the unit already runs unprivileged as the database superuser rather than as root, so it needs no additional capability grants. Verified with `nixfmt --check` (clean) and a targeted `nix eval '.#nixosConfigurations.ser8.config.systemd.services.backup-pgdump.serviceConfig' --json`, which confirmed the four hardening options are present and `User` resolves to `postgres`.

### WR-05: Four household smoketests carry a duplicate check left behind by the dataset migration

**Files modified:** `scripts/smoketests/household/test-actual-service.sh`, `scripts/smoketests/household/test-donetick-service.sh`, `scripts/smoketests/household/test-homebox-service.sh`, `scripts/smoketests/household/test-mealie-service.sh`
**Commit:** 75261fb
**Applied fix:** Per the team lead's direction, repurposed (rather than deleted) each `*_persist_dir` test function to assert the ZFS-specific property that `test-no-stale-persist-dirs.sh`'s `test_live_paths_are_datasets` already checks generically: that the live path is a mounted ZFS dataset (`findmnt -rn -t zfs "$PATH"`), not a plain directory riding the parent dataset's mount. This replaces the now-redundant ownership/mode `stat` comparison (identical to the sibling `*_state_dir_shape` test since the migration collapsed the two paths into one) with a local, service-suite-level assertion that no longer depends implicitly on the backup suite having run first. Verified with `bash -n`, `shellcheck` (one pre-existing SC1091 info-level note per file about the `. ./scripts/lib/all.sh` source line, unrelated to the edited lines and present identically on `main` before this change), and `shfmt -d`, all clean.

## Skipped Issues

None -- all findings were fixed.

---

_Fixed: 2026-08-29T21:00:00Z_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
