---
phase: 14-backup-engine
plan: 05
subsystem: storage
tags: [zfs, datasets, migration, cutover, impermanence, sanoid, syncoid, live-host]
status: complete

requires:
  - hosts/ser8/backup/services.nix (from 14-02) for the sixteen covered services and their unit names
  - hosts/ser8/disko-config.nix (from 14-02) for each child dataset's declared properties
  - hosts/ser8/backup/policy.nix (from 14-01/14-03) for the snapshot and replication policy
  - scripts/smoketests/backup/ (from 14-04) for the fail-closed suite
provides:
  - sixteen child datasets live on ser8, each holding its service's state
  - the backup engine running on the host: sanoid, syncoid, backup-verify timers enabled
  - backup/persist-replica created by the first replication, holding all sixteen children
  - the legacy zfs-snapshot-* machinery gone from the running system
affects:
  - hosts/ser8/backup/policy.nix
  - scripts/smoketests/household/test-donetick-service.sh
  - scripts/smoketests/household/test-homebox-service.sh
  - scripts/smoketests/household/test-actual-service.sh
  - scripts/smoketests/household/test-mealie-service.sh

tech-stack:
  added: []
  patterns:
    - create dataset unmounted, read properties back, only then mount and copy
    - checksummed rsync dry-run with --delete as the migration comparison gate
    - pre-build the closure on the target while services still run, so build time is outside the outage
    - smoketest path derived from the service's own DATA_DIR rather than duplicated as a literal

key-files:
  created:
    - .planning/phases/14-backup-engine/14-05-SUMMARY.md
  modified:
    - hosts/ser8/backup/policy.nix
    - scripts/smoketests/household/test-donetick-service.sh
    - scripts/smoketests/household/test-homebox-service.sh
    - scripts/smoketests/household/test-actual-service.sh
    - scripts/smoketests/household/test-mealie-service.sh
    - .planning/phases/14-backup-engine/deferred-items.md
  deleted: []

decisions:
  - The Jellyfin activation tarballs were deleted permanently (operator chose delete-now)
  - backup/persist-replica was NOT pre-created; replication must create it or the first send is refused
  - readonly=on was added to recvOptions and is INEFFECTIVE at runtime; see Known Issues
  - The closure is pre-built on ser8 before the outage rather than during it
  - Phase A was approved as a batch rather than per service, because approval latency dominates the outage

metrics:
  duration: ~6h wall clock, of which 5h20m was service downtime
  completed: 2026-08-28

actuals:
  tokens: 6000
  tasks: 4
  commits: 3
---

# Phase 14 Plan 05: Live Cutover Summary

Sixteen services on ser8 now sit on their own ZFS datasets, the backup engine is running, and every covered service came back healthy across a real reboot — but the outage ran 5h20m against a 30–50 minute estimate, the `readonly=on` hardening I recommended does not work, and the tarball deletion did not shrink the first replication the way the plan predicted.

## Performance

| Metric | Value |
|--------|-------|
| Tasks | 4 of 4 |
| Commits | 3 (2 source, 1 docs) |
| Datasets created | 16 |
| State migrated | 4,135,828,856 bytes across 25,749 entries |
| Migration wall clock | **72 seconds** |
| Activation | 43 seconds |
| **Service downtime** | **5h 20m 35s** (16:17:57Z → 21:38:32Z) |
| Comparison failures | 0 of 16 |

## Accomplishments

- All sixteen covered services are backed by `rpool/safe/persist/<svc>` and not by a bind mount from the parent, confirmed from the mount table both after activation and after a real reboot.
- Every migration compared clean. The gate was a checksummed `rsync --dry-run --delete --itemize-changes`, which catches content, ownership, permission, xattr, missing-file **and** extra-file differences — strictly stronger than the `diff -r` the plan implied.
- The record-size ordering hazard is evidenced rather than asserted. `postgresql` read back `recordsize 16K local` at 16:20:25Z and its copy began at 16:20:25Z. Every other child reports no locally set recordsize.
- Mosquitto gained durable state for the first time. A retained MQTT message published before the reboot was still present after it, which is the definitive proof: its state previously lived on the root filesystem that the boot rollback destroys.
- The legacy snapshot machinery is gone from the running system. Zero `zfs-snapshot-*` timers or units remain, down from five.
- The engine ran itself end to end. `sanoid` took the first recursive nightly at 22:00:00Z and `syncoid` replicated all sixteen children plus the parent in 99 seconds, exit status 0.
- Every original is still in place under `/persist`. Nothing was moved or deleted by the migration, so the escape route is intact.

## Decisions Made

**The replica was not pre-created, reversing what the plan instructed.** Task 2 step 3 called for creating `backup/persist-replica` imperatively "with exactly the properties the declaration describes." No such declaration exists — `disko-config.nix:432-443` deliberately omits it, and 14-01 had already filed and fixed this exact bug. Verified against the installed syncoid rather than the summary: `.syncoid-wrapped:632` refuses with `Cowardly refusing to destroy your existing target`, followed by a mollyguard reading `did you mistakenly run 'zfs create' on the target? ZFS initial replication must be to a NON EXISTENT DATASET`. Pre-creating it would have wedged the first send. The operator approved skipping the step; the first replication then created the dataset correctly and unattended.

**The closure was pre-built before the outage.** `scripts/nixos-rebuild.sh:74-76` points both `--build-host` and `--target-host` at ser8, so the plan's ordering would have run the build after every service was stopped. Building first with services still running removed that from the window. In the event this mattered far less than feared: ser8 needed 42 cheap config derivations and one 239.8 KiB fetch, 27 seconds. My pre-flight figure of 302 derivations and 3.2 GiB was my workstation's store lacking the Linux closure — an upper bound that I flagged as such and that proved roughly 100x too pessimistic.

**Phase A was batch-approved.** The plan required each of sixteen migrations to be approved individually. Those approvals would have run inside the outage, making human latency the dominant term. Since nothing in Task 3 is destructive — originals are read-only input throughout — the batch was approved under three commitments: originals untouched, any single difference halts, properties read back before any copy. All three held.

## Deviations from Plan

### 1. [Rule 1 - Bug] Task 2 step 3 would have broken the first replication

**Found during:** Task 2, before execution.
**Issue:** The plan instructed creating a dataset that the repository explicitly forbids creating, reintroducing a bug 14-01 had already removed.
**Fix:** Step 3 skipped with operator approval. Its four acceptance criteria are recorded N/A below.
**Files:** none. **Commit:** none (live-host task).

### 2. [Rule 3 - Blocking] The build would have run inside the outage

**Found during:** Task 3 preparation.
**Issue:** The deploy builds on ser8, and the plan scheduled activation after all services were stopped.
**Fix:** `make dry-build-ser8` then `make build-ser8` with services still running.
**Files:** none. **Commit:** none.

### 3. [Rule 2 - Missing critical functionality] The cutover required repository changes the plan did not list

**Found during:** Task 4.
**Issue:** The plan declares `files: none` for every task, but 14-04's summary requires the household smoketest retarget to land in the cutover itself, and the operator's `readonly` decision needed a config change.
**Fix:** Two commits before activation — `b78cb49` and `2f027aa`.
**Files:** `hosts/ser8/backup/policy.nix` and four household smoketests.

### 4. [Observation] Three services stopped uncleanly

`sabnzbd` and `frigate` hit their stop timeouts and were SIGKILLed; `nzbget`'s control process exited 1 while its main process exited 0. No processes survived, so the copies were consistent — nothing was writing during rsync. All three recovered fully: `frigate` serves version `0.17.2`, `nzbget` answers with an auth challenge, `sabnzbd` redirects normally, and `journalctl -p err` is empty for all three since restart.

## Known Issues

### `readonly=on` on the replica does not work — the change I recommended is ineffective

The first replication logged **18 instances** of:

```
cannot receive readonly property on backup/persist-replica/<svc>: permission denied
```

The syncoid unit runs as `User=syncoid` with `--no-privilege-elevation`, and setting the `readonly` property on receive requires a delegated permission that user does not hold. `zfs allow` returns nothing on either `rpool/safe/persist` or `backup`. The replica reads `readonly off default`.

Replication itself succeeded — all sixteen children transferred, exit status 0 — so this is noise plus a false sense of protection, not a data risk. But it is worse than not having made the change: it adds 18 error lines to every hourly run while delivering nothing.

I recommended this change and it does not work. Two ways forward, both needing a decision:
- **Revert `recvOptions` to `"u x mountpoint"`.** The replica relies on `mountpoint=none` exactly as before, which is what 14-04 concluded and what the smoketest already asserts.
- **Delegate the permission** so the property can be received, which means a `zfs allow` on the backup pool and a declaration to match.

I did not fix this forward on the live host, per instruction. `deferred-items.md` still carries no entry for it because it is raised here as an open decision rather than a deferral.

### The tarball deletion did not shrink the first replication

Task 1's decision rested on a projection that the first send would drop from ~11 GB to ~2.8 GB. It did not. The replica holds **17.45 GB**, because syncoid sends the *oldest* full snapshot first and `rpool/safe/persist@pre-26.05-2026-08-17T085547Z` still contains the 8.4 GB of tarballs. That snapshot alone accounts for 11.42 GB used and 13.78 GB referenced on the replica; the nightly refers 3.14 GB.

Stated plainly: the tarballs were destroyed permanently on the live tree **and** replicated anyway via the pre-upgrade snapshot. The operator accepted a one-way deletion partly on a projection that turned out to be wrong. The deletion still achieves its real purpose — future nightlies pin 3.07 GB rather than 11.2 GB — but the first-send argument did not hold, and the honest framing is that `delete-after-first-cycle` is roughly what happened by accident.

Reclaiming the space requires destroying the pre-upgrade snapshot on both sides, which is out of scope here.

### Two pre-existing smoketest failures, not caused by this cutover

The plan's criterion "every non-backup suite passes" is **not met**. Three suites failed; all three causes predate this work:

- **`media/all.sh`** — 279 directories under `/mnt/media` are non-writable by `bazarr`. The ACLs show `group::r-x` while `default:group::rwx`, so directories created before the default ACL was set are read-only to the media group. `/mnt/media` is the `media/data` dataset, untouched by this plan, and the flagged directories have mtimes months old.
- **`household/all.sh`** — the Homebox and Donetick *endpoint* signup tests fail. `HBOX_OPTIONS_ALLOW_REGISTRATION=true` was set by commit `2427677`, which updated only Mealie's test (`848a2e8`); Homebox's still asserts registration is closed. Donetick's `DT_IS_USER_CREATION_DISABLED` is not set at all while its test expects it. Both were already failing against generation 289 before this plan started.
- **`backup/all.sh`** — expected and correct. `backup-verify` has not run (next 03:30 local), so the manifest does not exist.

The four household tests this plan retargeted all passed: Mealie 12/12 service and 7/7 endpoint, Homebox 5/5 service, Actual 6/6 and 4/4, Donetick 5/5 service. Their assertions now resolve to `/var/lib/<service>` and read the live datasets.

## The outage was 5h 20m, not 30–50 minutes

Services were down **16:17:57Z → 21:38:32Z, 5h 20m 35s**, against an acknowledged 30–50 minutes.

The work was never the constraint. Migration took 72 seconds and activation 43 seconds — under two minutes of machine time for a nominally 3.85 GiB, 25,749-file migration. The remaining five hours was wall-clock latency waiting for approvals between checkpoints.

This is the exact failure mode raised when arguing against sixteen individual approvals, and it materialised anyway across only three or four round trips, because each costs real elapsed time regardless of how few there are. **The lesson for any future gated live-host plan: estimate the outage in approval round trips, not in bytes moved.** Batching Phase A was directionally right and nowhere near sufficient. The structural fix is to complete every approval *before* the first service stops, so the gated sequence runs unattended once the window opens.

## Verification

| Check | Result |
|-------|--------|
| 16 datasets exist, no others | PASS |
| Each `mountpoint=legacy`, `atime=off` local | PASS, 16/16 |
| `postgresql` `recordsize=16K` local, set before copy | PASS, evidenced by timestamp |
| No other child has a local recordsize | PASS |
| Recursive comparison reports no differences | PASS, 16/16 |
| Byte and entry counts equal both sides | PASS, 16/16 |
| Originals still present | PASS, 16/16 |
| `findmnt` reports the dataset after activation | PASS, 16/16 |
| `findmnt` reports the dataset after reboot | PASS, 16/16 |
| All units active after activation and after reboot | PASS, 16/16 |
| Application checks after activation and reboot | PASS, 13/13 |
| Retained MQTT message survives reboot | PASS |
| Frigate and Home Assistant reconnect to the broker | PASS, both seen connecting |
| Engine timers present and enabled | PASS, 3/3 |
| Legacy `zfs-snapshot-*` timers gone | PASS, 0 remain |
| Rollback anchor intact | PASS, checked after every step |
| Boot generation is the new closure after reboot | PASS |
| `make smoketests-ser8` — every non-backup suite passes | **FAIL** — see Known Issues |
| Replica `readonly=on` | **FAIL** — see Known Issues |

Task 2's four replica criteria (`backup/persist-replica` exists / dedup / canmount / readonly) are **N/A**: step 3 was skipped by decision. The dataset now exists because replication created it, reading `dedup off default` and `mountpoint none inherited`.

## Requirements

`BKP-01` and `BKP-07` are in this plan's frontmatter and are **not marked complete**, following the precedent of 14-01 through 14-04.

Both are closer than they have ever been — the engine is genuinely running and the first nightly snapshot and replication both succeeded. But BKP-01 also requires source retention "pruned to a 30-night sliding window," and exactly one nightly exists, so pruning is unexercised on the live host. BKP-07's coverage is real, yet the suite that would confirm it cannot: `test-manifest-coverage.sh` needs a manifest that `backup-verify` has not yet written.

They become markable after the verification timer fires at 03:30 local and the backup suite goes green.

## Deferred

`deferred-items.md` lost two entries, both resolved here: the household smoketest retarget landed in `2f027aa`, and the `readonly` question was decided (though the decision did not work — tracked above as an open issue rather than a deferral). The two remaining entries, the `stdenv.isDarwin` warning and unwired Prometheus rule tests, are unchanged.

New items for the register:
- The `readonly=on` receive failure — revert or delegate.
- 279 media directories non-writable by `bazarr` (pre-existing ACL drift).
- Homebox and Donetick signup tests contradict deployed configuration (pre-existing).
- The pre-upgrade snapshot pins 8.4 GB of deleted tarballs on both pools.
- `make reboot-ser8` gives up after ~50 seconds; ser8 returned at ~2 minutes. The target reports failure on a successful reboot.

## Threat Flags

None new. T-14-21 through T-14-26 were each exercised: activation followed dataset creation and the sixteen generated mount entries all resolved (T-14-21); originals were never moved and every copy was compared (T-14-22); the anchor was confirmed after every step (T-14-23); replica properties were read back rather than inferred, which is precisely how the `readonly` failure was caught (T-14-24); the first replication ran at 22:00Z well clear of the nightly upgrade window and took 99 seconds (T-14-25); the only permanent deletion was gated behind an explicit one-way decision (T-14-26).

## Next Phase Readiness

The engine is running and has completed one full cycle of snapshot and replication unattended. Three things 14-06 must carry:

- **The first replication already happened.** It was meant to be 14-06's watched out-of-band step; activation armed an hourly timer that fired at 22:00Z on its own. The run is measured — 99 seconds, 17.45 GB, exit 0 — but from unit logs after the fact rather than under observation.
- **The `readonly` decision must be resolved** before it accumulates 18 error lines per hour indefinitely.
- **The backup suite is still red** and becomes the real gate only after `backup-verify` fires at 03:30 local.

## Self-Check: PASSED

`14-05-SUMMARY.md` exists on disk. Commits `b78cb49`, `2f027aa` and `e09bdb4` are all present in `git log`. All five modified repository files are in the working tree. The sixteen datasets, the replica and its seventeen snapshots were read back from ser8 rather than inferred from command exit codes.
