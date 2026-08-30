---
phase: 14-backup-engine
plan: 03
subsystem: storage
tags: [zfs, snapshots, postgresql, sqlite, holds, vm-tests, systemd]
status: complete

requires:
  - hosts/ser8/backup slice (from 14-01)
  - sixteen covered-service dataset declarations (from 14-02)
  - checks.x86_64-linux.backup-behavior (from 14-01)
provides:
  - backup-pgdump.service (catalog-driven PostgreSQL dumps into the snapshotted tree)
  - backup-verify.service and backup-verify.timer (snapshot-read verification)
  - backup-failure-mail@.service (one failure-mail path for the whole slice)
  - the nightly manifest contract read by the next plan's smoketests
  - the six backup_* textfile metrics
  - a per-dataset last-verified ZFS hold
affects:
  - hosts/ser8/backup/default.nix
  - tests/backup-behavior.nix

tech-stack:
  added: []
  patterns:
    - oneshot unit with a sibling shell file and binaries interpolated from pkgs
    - templated onFailure mail unit instanced on %n
    - fail-closed shell that records check failures, then reports them, rather than aborting
    - a metric write placed last and guarded, so a stamp cannot outlive a failure
    - per-dataset ZFS holds as retention-proof pinning of the last proven-good snapshot

key-files:
  created:
    - hosts/ser8/backup/mail.nix
    - hosts/ser8/backup/dump.nix
    - hosts/ser8/backup/dump.sh
    - hosts/ser8/backup/verify.nix
    - hosts/ser8/backup/verify.sh
  modified:
    - hosts/ser8/backup/default.nix
    - tests/backup-behavior.nix
  deleted: []

decisions:
  - A refused destroy is not fatal to the prune run; sanoid logs it and exits 0
  - A digest that cannot be delivered fails the run, which suppresses the metric stamp
  - The dump directory is created by a tmpfiles rule, not by the script that writes it
  - backup-pgdump is ordered after postgresql.service to avoid spurious boot-time failure mail

metrics:
  duration: ~5h
  completed: 2026-08-27

actuals:
  tokens: 18000
  tasks: 3
  commits: 3
---

# Phase 14 Plan 03: Dump and Verification Summary

Every database on the host is now dumped in a portable format the night it appears, and every database inside the nightly snapshot is opened the way a restore would open it — with a per-dataset hold that makes the last snapshot proven good for each service undestroyable until a better one replaces it.

## Performance

| Metric | Value |
|--------|-------|
| Tasks | 3 of 3 |
| Commits | 3 |
| Files created | 5 |
| Files modified | 2 |
| VM test assertions | 19 (7 pre-existing, 12 new) |
| VM test runs | 11 (3 deliberate mutations) |

## Accomplishments

- `backup-pgdump` enumerates databases from the catalog rather than from a list, so a database created by a service added in a future phase is dumped the night it is created with no edit anywhere.
- Archives are published by rename only after `pg_restore --list` proves they are complete, so no snapshot can contain a truncated dump.
- The dump is ordered ahead of the snapshot job by a weak dependency rather than clocked on its own timer, so every snapshot carries fresh dumps — including the catch-up snapshot after an outage, which a fixed-time timer would miss by the length of the outage.
- `backup-verify` walks the snapshot tree, finds databases by kind, and checks each one on a copy opened read-write, which replays the write-ahead log exactly as crash recovery would. That is the claim the whole design rests on, and it is now performed nightly rather than assumed.
- A per-dataset `last-verified` hold advances only when everything belonging to that dataset checked clean. A held snapshot cannot be destroyed, so the newest proven-good copy of each service is structurally safe from pruning until a better one exists.
- The nightly manifest's sixth field names the snapshot each dataset's hold sits on, which answers "which snapshot would a restore use, and is it known good" without reading pool state.
- The freshness metrics are written last and behind a guard, so a fresh timestamp cannot sit beside a run that failed or a run that was killed.
- `backup-failure-mail@` gives every unit in the slice a loud-failure path through the same wrapper the storage event daemon already uses. There was no `OnFailure=` anywhere in this repository before.
- The behaviour suite went from 7 assertions to 19, including three that pull the guest's power at different points.

## Files Created/Modified

Created: `hosts/ser8/backup/mail.nix`, `dump.nix`, `dump.sh`, `verify.nix`, `verify.sh`.
Modified: `hosts/ser8/backup/default.nix` (three imports), `tests/backup-behavior.nix` (twelve new assertions, a PostgreSQL server, a second covered service, two seeded write-ahead-log databases and a sendmail stub).

## Decisions Made

**A refused destroy is not fatal to the prune run.**
This was the open interaction the plan flagged for measurement rather than assumption, and the measurement is now in the test: the prune logs `cannot destroy snapshot ...: it's being held` for each refusal and **exits 0**.
It also does not unwind what it destroyed before the refusal, so a nightly name is left on part of the tree.
Both facts are asserted explicitly rather than left implicit.
The consequence is worth stating plainly: the pathological case — verification failing for a whole retention window so the hold pins the oldest snapshot pruning wants — produces no noise from the prune at all.
Nothing is actually silent, because the verification has by then mailed a failure every night for thirty nights, but the prune is not a second signal and should not be counted as one.

**A digest that cannot be delivered fails the run.**
The obvious objection is circularity: mail is broken, so the alert about mail being broken cannot arrive.
It is not circular here.
Failing the run suppresses the metric stamp, and the staleness rule that notices an unstamped metric is evaluated by Prometheus on a different host over a different path.
So a night when this host cannot send mail still reaches someone.

**The dump directory is created by a tmpfiles rule, not by the script.**
The plan has the script create it. It cannot: `/persist/var/lib` is root-owned and the unit runs as the database superuser, so the first `mkdir` on a fresh host would fail and take the run with it.
The rule creates it `0700` owned by that account and the script still asserts the mode, so the two agree and neither is the only thing standing between the archives and a wrong mode.

**The verification reports check failures rather than aborting on them.**
A corrupt database has to fail the run, but it also has to leave behind a manifest that says which snapshot to restore from instead — and an abort at the first bad database would write nothing at all.
So check failures are recorded, the holds and the manifest are still written, the digest still goes out, and only then does the run exit non-zero with the metrics left unstamped.
Structural failures that make the run meaningless (no snapshot, a stale snapshot) still abort immediately, because there is nothing to record.

## Deviations from Plan

### 1. [Rule 3 - Blocking] The dump directory cannot be created by the account that writes it

**Found during:** Task 1.
**Issue:** The plan specifies `/persist/var/lib/backup-dumps` "created by the script with mode `0700`", and the unit runs as the database superuser so that no authentication has to be configured. `/persist/var/lib` is root-owned, so that `mkdir` fails on any host where the directory does not already exist — which is every host, the first time.
**Fix:** A `systemd.tmpfiles` rule in `dump.nix` creates it `0700` owned by that account. The script keeps its `mkdir -p` and `chmod 0700` as a fail-closed guard.
**Files:** `hosts/ser8/backup/dump.nix`, `dump.sh`. **Commit:** 768c863.

### 2. [Rule 2 - Missing critical functionality] The dump would mail a spurious failure at boot

**Found during:** Task 1.
**Issue:** The snapshot timer fires on the hour. A machine that boots shortly before one reaches the dump while PostgreSQL is still starting, the dump fails, and the failure mail describes a problem that does not exist. Alerting that cries wolf at every reboot is alerting that gets ignored.
**Fix:** `after = [ "postgresql.service" ]` on `backup-pgdump`. Ordering only, not a requirement — the server is in the same boot transaction so ordering is sufficient, and making it a requirement would mean a backup job could start a database.
**Files:** `hosts/ser8/backup/dump.nix`. **Commit:** 768c863.

### 3. [Rule 1 - Bug] `install` is not an atomic publish

**Found during:** Task 2.
**Issue:** The plan lists `install` among the binaries to export and separately requires the metrics file be written to a temporary name, chmod'd, "then rename into place". `install` copies; it does not rename, so the collector could read a partial file — the exact failure the requirement exists to prevent.
**Fix:** `chmod 0644` followed by `mv`, and `INSTALL_BIN` dropped from the exported set since nothing else used it.
**Files:** `hosts/ser8/backup/verify.nix`, `verify.sh`. **Commit:** d90756a.

### 4. [Rule 1 - Bug] A test that verified the snapshot taken before the damage

**Found during:** Task 3, by the assertion failing.
**Issue:** The corruption assertion damaged the live database and then ran the snapshot job, expecting a new snapshot. The policy decides from pool state whether a nightly is due, so a second run inside the same day takes nothing — and the verification then re-read the snapshot from before the damage and correctly reported it clean. The test would have concluded that corruption is not detected, when in fact no corrupted snapshot had ever been made.
**Fix:** A `nightly()` helper that advances the clock a day, takes the snapshot, replicates, and **asserts a new snapshot actually appeared**. Every place that needs a fresh snapshot goes through it, so the trap cannot recur silently. The corruption assertion additionally requires that the new snapshot differ from the clean one, and that the failure names the damaged database rather than being any failure at all.
**Files:** `tests/backup-behavior.nix`. **Commit:** 2a38502.

### 5. [Rule 1 - Bug] The all-or-none assertion was measuring the prune, not the crash

**Found during:** Task 3.
**Issue:** The crash assertion compares nightly names across the tree. It failed on names left inconsistent by the prune-versus-hold interaction two subtests earlier, not by any crash.
**Fix:** The prune's partial outcome is now asserted where it happens, as the observed behaviour it is, and the tree is put back to one consistent state before the crash group so those assertions measure the crash.
**Files:** `tests/backup-behavior.nix`. **Commit:** 2a38502.

### 6. [Rule 3 - Blocking] The guest clock does not survive a crash

**Found during:** Task 3.
**Issue:** The retention and catch-up assertions move the guest clock forward by weeks. The emulated hardware clock does not move with it, so after `machine.crash()` the guest came back believing it was two months earlier, every snapshot looked like it came from the future, and the policy concluded nothing had ever been due.
**Fix:** `crash_and_boot()` records the clock immediately before pulling the power and restores it after boot, alongside importing the pools and re-quiescing the timers.
**Files:** `tests/backup-behavior.nix`. **Commit:** 2a38502.

### 7. [Rule 1 - Bug] Waiting to observe a run that finishes in one second

**Found during:** Task 3.
**Issue:** The crash-during-verification assertion waited for the unit to be observably mid-run before crashing. The verification finishes in about a second even with several hundred megabytes to check, so the wait never matched and the test hung for its full fifteen-minute timeout — twice.
**Fix:** The power is pulled immediately after the job is queued. This cannot pass vacuously: the metrics recorded beforehand name the previous night's snapshot, so a run that did finish would have replaced them, and the comparison fails in exactly the case where the crash landed too late to prove anything.
**Files:** `tests/backup-behavior.nix`. **Commit:** 2a38502.

### 8. [Rule 1 - Bug] The retention count was off by the snapshot the run itself took

**Found during:** Task 3, by the assertion failing with 31 instead of 30.
**Issue:** The scheduled invocation takes and prunes in one pass, and prunes against the snapshot list it read before taking — so the snapshot the run creates survives on top of the window.
**Fix:** The two retention assertions drive the prune path directly, reading the invocation back off the real unit rather than writing a second copy of it. The observed take-and-prune behaviour is recorded in the helper's comment.
**Files:** `tests/backup-behavior.nix`. **Commit:** 2a38502.

## Red Before Green

Nine of the twelve new assertions were observed failing before they passed, and every one of those failures was a real defect rather than a staged one.

| Assertion | Observed red |
|-----------|--------------|
| 8 — corruption is caught | `a corrupt database inside the snapshot verified as healthy` — twice, first because no new snapshot was taken and then because the failure was not attributable to the database |
| 9 — health is confirmed | `[FAIL] The newest snapshot on backup/persist-replica is 5529613s old` |
| 10 — retention window | `expected 30 dailies after pruning, got 31` |
| 11 — retention floor | `the prune run failed: bash: line 1: --prune-snapshots: command not found` |
| 12 — catch-up after an outage | `the policy took no snapshot on a new night` (the same guard, from the `nightly()` helper) |
| 13 — dumps ride inside the snapshot | mutation: removed the snapshot job's `wants`/`after` on the dump → `test -s .../backup-dumps/globals.sql failed` |
| 14 — restore across the covered set | mutation: removed `mealie` from the covered set → `backup-restore mealie --force failed (exit code 1)` |
| 16 — hold stays put on a corrupt night | mutation: replaced the per-dataset clean guard with an unconditional advance → `the damaged dataset's hold moved off the last snapshot it verified clean` |
| 18 — crash leaves the metric unstamped | timed out twice against a verification that had already finished |
| 19 — all-or-none naming | `autosnap_2026-02-25_03:00:00_daily exists on ['rpool/safe/persist', 'rpool/safe/persist/donetick'] but not on every dataset` |

Three were never red and that is stated rather than glossed:

- **15 (hold advances on a clean night)** shares its code path with 16, whose mutation was red, but no mutation targeted the placement half on its own.
- **17 (interrupted send resumes)** has nothing local to mutate — resumable receives are a pool default, not a setting in this repository. Its resume-token assertions passed on the first run against a genuine mid-transfer crash.
- The **replica freshness** half of 9 was red as shown above; its integrity half is deliberately absent by design.

## Capability Set

The plan asks for the capability set to be determined empirically rather than copied. `CAP_DAC_OVERRIDE`, `CAP_DAC_READ_SEARCH` and `CAP_SYS_ADMIN` were the first set tried and the verification ran clean under it in the guest across every subtest, including the hold placement and release that go through the pool control device. `CAP_SYS_ADMIN` is broad and is there because pool operations need it; it was not narrowed further because no smaller capability grants them. `PrivateDevices` is unset with a comment saying why, since it would hide that device and the resulting failure reads as a permissions problem.

## Issues Encountered

The workstation still cannot build guest images locally — `/nix/store` is on a case-insensitive volume — so all eleven VM runs went to ser8 through the remote builder. Unchanged from 14-01 and 14-02 and still unaddressed.

A full run of this test now takes roughly twelve minutes on ser8, up from about four and a half. The additions that cost the most are the 80 MB database that exercises the page-level check, the 256 MB transfer the resume assertion has to interrupt, and three full reboots.

## Requirements

`BKP-02`, `BKP-03`, `BKP-06` and `BKP-07` are listed in this plan's frontmatter and **have not been marked complete**, following the precedent set in 14-01 and 14-02.

All four describe a backup that runs. Nothing in this plan touches ser8: no dataset exists there, no snapshot has been taken, no dump has been written and the verification has never executed outside a guest. What this plan produced is the mechanism and its proof.

`BKP-06` is the one worth being precise about, because it is the closest to satisfied and still is not. It wants a demonstrated Donetick restore, a demonstrated Actual restore, and a VM suite exercising the restore path across every covered service. The suite now drives the restore from a service list rather than a hardcoded name, which is the part that generalises — but the guest stands up two of the sixteen covered services, and no drill has been run against the real host at all.

## Known Stubs

None.

## Threat Flags

None. The register's mitigations for T-14-10 through T-14-15 and T-14-33 through T-14-36 are each either asserted by a subtest or visible in the rendered unit:

- T-14-10 (dump disclosure): the directory is `0700` owned by the database superuser via tmpfiles and the script runs `umask 0077`. The mode assertion belongs to the next plan's smoketest as planned.
- T-14-11 and T-14-35 (a stamp that outlives a failure): asserted by the corruption subtest and by the crash-during-verification subtest.
- T-14-12 (filenames out of a snapshot): null-delimited enumeration and reading throughout, no discovered path evaluated.
- T-14-13 (corruption ageing out good copies): asserted, and red under mutation.
- T-14-14 (mail contents): the digest carries paths, check names, results and sizes; the failure mail is bounded to fifty lines.
- T-14-15 (a failed dump suppressing the snapshot): the dependency is `wants`, confirmed by evaluation.
- T-14-33 (the last good copy pruned away): asserted in both directions, and red under mutation.
- T-14-34 (root across sixteen state trees): constrained by the sandbox above and exercised in the guest.
- T-14-36 (a send that never completes): asserted against a genuine mid-transfer crash.

## Deferred

Nothing new. The two items already in `deferred-items.md` are unchanged.

## Next Phase Readiness

The manifest and metrics contracts the next plan's smoketests read are now fixed and exercised:
`/persist/var/lib/backup-manifests/latest.tsv` with hash-prefixed `key=value` headers and six-field tab-separated rows, and `/persist/var/lib/node-exporter-textfile/backup.prom` with the six `backup_*` series.

Three things the next plans must carry:

- Everything is still declaration only. The engine has never run on ser8.
- The exporter is not yet pointed at the textfile directory; `services.prometheus.exporters.node.extraFlags` is untouched, so the metrics this plan writes are not yet scraped.
- The prune does not complain when a hold blocks it, so the staleness alerts are the only cross-check on a verification that has been failing for a long time. That raises the value of the absence arm on those rules rather than changing anything here.

## Self-Check: PASSED

All five created files exist on disk. All three commits (768c863, d90756a, 2a38502) are present in `git log`.
