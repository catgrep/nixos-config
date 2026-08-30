---
phase: 14-backup-engine
plan: 01
subsystem: storage
tags: [zfs, snapshots, replication, restore, vm-tests]
status: complete

requires: []
provides:
  - hosts/ser8/backup slice (covered-service set, snapshot/replication policy, restore tool)
  - checks.x86_64-linux.backup-behavior
  - rpool/safe/persist/donetick dataset declaration
affects:
  - hosts/ser8/configuration.nix
  - hosts/ser8/disko-config.nix
  - modules/servers/default.nix
  - flake.nix

tech-stack:
  added: [sanoid, syncoid]
  patterns:
    - covered-service attrset as the single identifier for dataset, mount, unit and restore argument
    - build-time assertion tying each covered service to its storage declaration
    - writeShellApplication with an injected allowlist environment variable

key-files:
  created:
    - hosts/ser8/backup/default.nix
    - hosts/ser8/backup/services.nix
    - hosts/ser8/backup/datasets.nix
    - hosts/ser8/backup/policy.nix
    - hosts/ser8/backup/restore.nix
    - hosts/ser8/backup/restore/backup-restore
    - tests/backup-behavior.nix
  modified:
    - flake.nix
    - hosts/ser8/configuration.nix
    - hosts/ser8/disko-config.nix
    - modules/servers/default.nix
  deleted:
    - modules/servers/backup.nix

decisions:
  - The replica dataset is deliberately NOT declared in disko; replication must create it
  - Receive-side mountpoint exclusion is latent insurance, not the active mechanism
  - policy.nix uses `_:` rather than `{ ... }:` to satisfy statix

metrics:
  duration: ~3h
  completed: 2026-08-27

actuals:
  tokens: 71000
  tasks: 3
  commits: 4
---

# Phase 14 Plan 01: Backup Tracer Summary

One service's state now makes the full round trip -- child dataset, atomic recursive snapshot, replication that cannot shadow live paths, restore back into the live directory -- proven by seven assertions in the repository's first `checks` flake output.

## Performance

| Metric | Value |
|--------|-------|
| Tasks | 3 of 3 |
| Commits | 4 |
| Files created | 7 |
| Files modified | 4 |
| Files deleted | 1 |
| VM test runs | 5 (2 deliberate mutations) |

## Accomplishments

- `hosts/ser8/backup/` slice built and wired into ser8's closure.
- `tests/backup-behavior.nix` boots a guest, builds real `rpool` and `backup` pools on scratch disks, and asserts all seven behaviours. It runs on ser8 through the remote builder.
- The legacy `services.zfs.autoSnapshot` block and its five inert timers are gone, as is `modules/servers/backup.nix`.
- All four host closures dry-build; `statix`, `nixfmt`, `shellcheck` and `shfmt` are clean.

## Files Created/Modified

Created: the six slice files plus `tests/backup-behavior.nix`.
Modified: `flake.nix` (first `checks` output), `hosts/ser8/configuration.nix` (import, autoSnapshot removal), `hosts/ser8/disko-config.nix` (donetick child dataset), `modules/servers/default.nix` (import removal).
Deleted: `modules/servers/backup.nix`.

## Decisions Made

**The replica dataset must not be declared.** Replication refuses to send into a target that already exists without matching snapshots -- it errors with "Cowardly refusing to destroy your existing target", and the tool's own source carries a mollyguard naming this exact mistake. Declaring `backup/persist-replica` in disko would create it empty on a fresh install and wedge the first send. It is left undeclared with a comment above the backup pool explaining why, so nobody "fixes" it later.

**Receive-side mountpoint exclusion is insurance, not the active guard.** See the deviation below.

## Deviations from Plan

### 1. [Rule 1 - Bug] The replica dataset declaration would break the first replication

**Found during:** Task 2.
**Issue:** The plan specified adding `persist-replica` to the backup pool's disko datasets with `mountpoint`, `canmount`, `readonly` and `com.sun:auto-snapshot`. Replication's first send must land on a dataset that does not yet exist; a pre-created target is refused outright.
**Fix:** The declaration was omitted and a block comment above the backup pool records the reason. The safety properties survive without it: the receive drops the mountpoint property, so the replica inherits `mountpoint=none` from the pool root and cannot mount anywhere at all -- strictly stronger than the planned `canmount=noauto` at a real path.
**Files:** `hosts/ser8/disko-config.nix`. **Commit:** b2343b2.

### 2. [Rule 1 - Bug] The shadowing assertion passed for the wrong reason

**Found during:** Task 2, by mutation testing.
**Issue:** Removing `-x mountpoint` did not fail the test. Investigation of the tool's source and the NixOS module showed `sendOptions` defaults to empty, and `zfs send` carries no dataset properties unless asked -- so no mountpoint ever travels and the exclusion had nothing to do. The research's claim that "local dataset properties travel in the send stream" is only true with `-p` or `-R`. The assertion was true but vacuous.
**Fix:** Added an assertion that the replica's mountpoint is *inherited* rather than received, which fails the moment a property arrives in the stream. Verified by mutating `sendOptions = "p"` with the exclusion removed: the test failed with `replica carries live mountpoints: ['/var/lib/donetick']`, confirming both that the hazard is real and that the exclusion prevents it. The policy comment was corrected to describe the flag as a guard against a latent hazard rather than an active one.
**Files:** `tests/backup-behavior.nix`, `hosts/ser8/backup/policy.nix`. **Commit:** 9f12a0c.

### 3. [Rule 3 - Blocking] Restore tool cannot rename its own mountpoint

**Found during:** Task 2.
**Issue:** The research sketch moved the live directory aside with `mv`, then swallowed the error. The live path is a ZFS mountpoint and cannot be renamed while mounted, so every restore would have silently merged the snapshot over existing state while reporting a preserved copy that did not exist.
**Fix:** The tool moves the directory's *contents* into a dated sibling instead. `findutils` was added to `runtimeInputs` for this.
**Files:** `hosts/ser8/backup/restore/backup-restore`, `restore.nix`. **Commit:** b2343b2.

### 4. [Rule 3 - Blocking] statix rejects `{ ... }:` in policy.nix

`policy.nix` uses `_:`, matching `media/bazarr.nix` and `household/actual.nix`. The `{ ... }:` form the patterns document specified is used by `default.nix` aggregators, which statix does not flag. **Commit:** b2343b2.

### 5. [Out of scope, fixed anyway] Planning terminology in flake.nix

Two pre-existing comments referenced a phase number and a decision ID, violating the repo rule against planning terminology outside `.planning/`. Both were rewritten to carry the plain rationale. **Commit:** 9f12a0c.

### 6. [Rule 1 - Bug] Plan frontmatter claims three requirements this plan does not satisfy

**Found during:** state update.
**Issue:** The frontmatter lists `requirements: [BKP-01, BKP-03, BKP-06]`. None is met. BKP-01 wants a nightly replication actually running on ser8, and nothing here touches ser8 -- not one dataset exists. BKP-03 wants nightly `integrity_check` against a snapshot copy, and the verify job is a later plan. BKP-06 wants demonstrated Donetick *and* Actual restores plus a VM suite across *every* covered service; this covers one service in a guest and runs no drill. The plan's own objective ("no live ser8 mutation anywhere in this plan") contradicts its frontmatter, and its own `planner_assumptions` table says the VM suite is "additional evidence rather than a substitute" for a real BKP-06 execution.
**Fix:** `requirements mark-complete` was run per the plan, then reverted. All three are back to Pending. Marking them complete would have read as "backups are running" while nothing runs -- the precise false-completion this tracer exists to prevent.
**Files:** `.planning/REQUIREMENTS.md` (no net change).

### 7. Remote builder repair, reversed twice

The earlier decision to skip repairing the stale SSH host keys was reversed by the operator after the VM probe showed the workstation's Nix store is on a case-insensitive volume, which makes every guest initrd unbuildable locally. The repaired builders are now load-bearing: all VM tests in this phase build on ser8.

## Issues Encountered

The workstation cannot build guest images locally. `/nix/store` sits on a case-insensitive filesystem, so Nix applies its case hack and `make-initrd-ng` fails looking for `terminfo/l/linux`. Every VM test therefore builds remotely. Recreating `/nix` as a case-sensitive volume remains the real fix and is unaddressed.

Nix also cannot run in this sandbox without `XDG_CONFIG_HOME`, `NIXPKGS_CONFIG` and `HOME` overrides.

## Known Stubs

None. The restore tool implements only `<service>`, `--snapshot` and `--force`; `--list`, `--from replica`, `--rollback` and `--pg-database` are deliberately absent rather than stubbed, and an unrecognised flag exits non-zero.

## Threat Flags

None. The threat register's mitigations for T-14-01 through T-14-04 are each asserted by a subtest.

## Next Phase Readiness

The architecture is confirmed viable on all three questions the tracer was built to answer: recursive snapshots do land parent and child in one transaction group, an unprivileged receive works without shadowing live mountpoints, and state copied out of `.zfs/snapshot` reconstructs a working service.

Two things the next plans must carry:

- Every dataset is still a declaration only. Nothing exists on ser8; the imperative creation and per-service migration are unstarted.
- The expansion to the remaining ~15 covered services adds one entry to `services.nix` and one disko block each; the build-time assertion will name any service that gets one without the other.

## Self-Check: PASSED

All seven created files exist on disk. All four commits (9c27356, b2343b2, 9f12a0c, 8e03888) are present in `git log`.
