---
phase: 13-zfs-mirror-migration
plan: 03
subsystem: infra
tags: [zfs, rsync, systemd-run, ser8, freeze, staging, async-job]

# Dependency graph
requires:
  - phase: 13-zfs-mirror-migration
    provides: "zfs-media-mirror branch (Plan 13-02) and the truthful migration doc / SMART evidence / source-inventory baseline (Plan 13-01)"
provides:
  - "Fully frozen source: all 18 app services stopped, zero writers under /mnt/media confirmed via lsof — the sole freeze window for the whole migration (D-03)"
  - "backup/media-staging: a complete, structurally verified frozen copy of /mnt/media (3,478 files, 5,727,815,651,227 apparent bytes, exact match on both sides)"
  - "External-job manifest pattern (.planning/async-jobs/) proven end-to-end for a multi-hour unattended operation spanning an execution session"
affects: [13-04-staging-verification, 13-05-cutover, 13-06-restore, 13-07-cleanup]

# Actuals (#2632)
actuals:
  tokens: 3200
  tasks: 4
  commits: 3

# Tech tracking
tech-stack:
  added: []
  patterns: [external-job-manifest-for-multi-hour-copies, systemd-run-detached-transient-unit, lsof-writer-check-before-freeze]

key-files:
  created:
    - .planning/async-jobs/media-staging-rsync.json
  modified: []

key-decisions:
  - "Task 1's stop list already superseded deferred-items.md's stale Step 3.1 wgnord/nginx references (both deleted in Phase 12); per this plan's files_modified: [] scoping, the migration doc's Step 3.1 prose was left as narrative staleness rather than edited, treating Task 1's corrected list as the authoritative correction per deferred-items.md's second option"
  - "All three live-mutating checkpoints (freeze, staging creation, copy launch) required and received explicit human approval per this phase's checkpoint policy -- none were auto-approved, unlike Plan 13-02's repo-only checkpoints"
  - "Deviated from the plan's D-12 stage-per-session cadence for Task 3 on explicit operator instruction: instead of ending the session immediately after launch, the copy was tracked to completion within this extended session using the external_job_waiting async-job manifest pattern (.planning/async-jobs/media-staging-rsync.json), so the plan closes in one continuous execution rather than requiring a second resumed session"
  - "ZFS-01 NOT marked complete: the requirement also demands a checksum-verified final sync reporting zero unexplained differences, which is Plan 13-04's sampled verification gate, not this plan's structural count/byte check"

requirements-completed: []

coverage:
  - id: D1
    description: "All 18 freeze-set application services stopped and confirmed to hold zero writable file descriptors under /mnt/media before any copy started"
    requirement: "ZFS-01"
    verification:
      - kind: manual_procedural
        ref: "ssh bdhill@192.168.68.65 'systemctl is-active <unit>' for all 18 units (16 inactive, 2 failed, none active) and 'sudo lsof +D /mnt/media | awk \"\\$4 ~ /[uw]\\$/\"' (empty output)"
        status: pass
    human_judgment: false
  - id: D2
    description: "backup/media-staging created with target-matching ZFS properties, within the D-17 >=1.5 TB capacity floor"
    requirement: "ZFS-01"
    verification:
      - kind: manual_procedural
        ref: "ssh bdhill@192.168.68.65 'zfs get -o property,value compression,recordsize,atime,dedup,com.sun:auto-snapshot backup/media-staging' plus capacity math (~4.86 TiB projected free, well above the 1.5 TB floor)"
        status: pass
    human_judgment: false
  - id: D3
    description: "Single frozen rsync pass from /mnt/media into backup/media-staging completed with a clean exit and structurally matches the Plan 13-01 preflight manifest"
    requirement: "ZFS-01"
    verification:
      - kind: manual_procedural
        ref: "ssh bdhill@192.168.68.65 'systemctl show media-staging-rsync -p ExecMainStatus,Result --value' (0 / success), journalctl (no error/fail/denied lines), file count 3,478 on both sides, du -sb --apparent-size 5,727,815,651,227 on both sides (exact match)"
        status: pass
    human_judgment: false

duration: ~10h47m elapsed (~45min active engineering across 3 checkpoints + verification; ~7h43m unattended copy; remainder was the async wait for the job to reach a terminal state)
completed: 2026-08-24
status: complete
---

# Phase 13 Plan 03: Freeze and Initial Staging Copy Summary

**All 18 ser8 app services frozen with zero confirmed writers, `backup/media-staging` created and verified, and a single frozen `rsync` pass landed 5.73 TB / 3,478 files into staging with an exact byte-for-byte structural match against the source**

## Performance

- **Duration:** ~10h47m elapsed (~45min active engineering; ~7h43m unattended `rsync`; remainder was async-wait for job completion notification)
- **Started:** ~2026-08-24T07:24:00Z (immediately after Plan 13-02's completion)
- **Copy launched:** 2026-08-24T07:35:51Z
- **Copy completed:** 2026-08-24T15:19:10Z (7h43m19s wall clock, per `systemd`)
- **Verified / Completed:** 2026-08-24T18:10:00Z
- **Tasks:** 4/4
- **Files modified:** 1 (created — `.planning/async-jobs/media-staging-rsync.json`)

## Accomplishments

- Stopped all 18 freeze-set units in one `systemctl stop` command (orchestration oneshots and arr services first, Samba last for clean write drain); confirmed every unit non-active (16 `inactive`, `nzbget`/`frigate` `failed` — both acceptable per the plan's own criterion) and zero processes holding a writable handle under `/mnt/media` via `lsof`. `/mnt/media` stayed mounted throughout — this is the ONLY freeze window for the whole migration per D-03, and the ~23h total outage clock started here.
- Rechecked staging capacity against the now-frozen source (no further growth risk): `/mnt/media` at 5,727,815,651,227 apparent bytes against `backup`'s 11,067,525,160,704-byte available, projecting ~4.86 TiB (~5.34 TB) free after staging — well clear of the D-17 1.5 TB floor. Created `backup/media-staging` with the target-matching properties (`compression=lz4 recordsize=1M atime=off dedup=off com.sun:auto-snapshot=false`) and no reservation.
- Launched the single frozen copy (D-03's collapse of the migration doc's original two-pass live-then-frozen design into one clean pass) as a detached `systemd-run --unit=media-staging-rsync` transient unit, surviving the rest of the session regardless of SSH connectivity.
- Per explicit operator direction, tracked the ~7h43m unattended copy to completion within this session using the `external_job_waiting` async-job manifest pattern (`.planning/async-jobs/media-staging-rsync.json`) rather than ending the session at launch (the plan's original D-12 cadence) — this is the first time this repository has used that pattern for a multi-hour live-ops operation.
- Verified the completed copy structurally against the Plan 13-01 preflight manifest: `systemctl show media-staging-rsync -p ExecMainStatus,Result` returned `0` / `success`; `journalctl -u media-staging-rsync` showed only `rsync --info=progress2` output and a clean `Deactivated successfully` line, no error/fail/denied entries; file count matched exactly at 3,478 on both `/mnt/media` and `/mnt/media-staging`; apparent byte total matched exactly at 5,727,815,651,227 on both sides. The `backup` pool's scrub (running at dispatch time) also completed during the copy window with `scrub repaired 0B ... with 0 errors`.

## Task Commits

Tasks 1 and 2 were live-ops checkpoints with no repository file changes (matching the plan's `files_modified: []`); Task 3 and Task 4 produced the async-job manifest and its terminal-state update:

1. **Task 1: Freeze the full application stack (D-02/D-03)** — no commit (live-ops only; 18 units stopped, `lsof` and mount verified)
2. **Task 2: Recheck staging capacity and create `backup/media-staging` (Steps 2.1+2.2, D-17)** — no commit (live-ops only; dataset created and verified)
3. **Task 3: Launch the frozen copy as a `systemd-run` transient unit (D-03/D-13)** — `3647bbd` (docs: record `media-staging-rsync` as `external_job_waiting`)
4. **Task 4: Verify the frozen copy completed successfully** — `22943d2` (docs: mark job `completed-unverified` with verification results) and `2df7325` (fix: correct a UTC timestamp conversion error in the manifest's own notes field, self-caught before this commit)

**Plan metadata:** (this commit, docs: complete plan)

## Files Created/Modified

- `.planning/async-jobs/media-staging-rsync.json` — new; external-job manifest tracking the `media-staging-rsync` `systemd-run` unit from dispatch (`running`) through verified completion (`completed-unverified`, with the verification results recorded in its `notes` field)

## Decisions Made

- All three live-mutating checkpoints (service freeze, staging dataset creation, copy launch) required and received explicit human approval per this phase's checkpoint policy ("Approval should only be for running commands on ser8 for data migration") — none were auto-approved, in contrast to Plan 13-02's repository-only checkpoints
- Left the migration doc's Step 3.1 stale wgnord/nginx prose untouched (per `deferred-items.md`'s note from Plan 13-01): this plan's `files_modified: []` scoping and Task 1's own already-corrected 18-unit stop list satisfy the "treat this note as authoritative correction" option without expanding this plan's edit scope into doc maintenance
- On explicit operator instruction, deviated from the plan's designed D-12 stage-per-session cadence for Task 3: instead of ending the session at launch, used the `external_job_waiting` async-job manifest convention to track the ~7h43m unattended copy to a verified terminal state within one continuous execution, avoiding a second resumed session for a plan that was otherwise ready to close
- Did not mark `ZFS-01` complete: the requirement text also demands "a frozen, checksum-verified final sync reporting zero unexplained differences" — this plan's Task 4 is an explicit structural sanity check (file count + apparent byte total), not the checksum-based sampled verification gate that is Plan 13-04's job

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Corrected a UTC timestamp conversion error in the async-job manifest's own notes field**
- **Found during:** Task 4, while re-verifying the manifest content before the terminal-status commit
- **Issue:** The manifest's `notes` field recorded the copy's completion time as `2026-08-24T08:19:10Z`, taken directly from `journalctl`'s server-local (PDT, UTC-7) timestamp without converting it — the correct UTC value is `15:19:10Z` (`08:19:10` local `+ 7h`), matching `systemd`'s own reported `7h 43min 18.928s wall clock time` from the `07:35:51Z` launch
- **Fix:** Corrected the notes field to `2026-08-24T15:19:10Z`
- **Files modified:** `.planning/async-jobs/media-staging-rsync.json`
- **Verification:** Recomputed `15:19:10Z - 07:35:51Z = 7h43m19s`, matching `systemd`'s reported wall-clock duration
- **Committed in:** `2df7325`

---

**Total deviations:** 1 auto-fixed (timestamp bug in a docs-only tracking artifact, no live-state impact)
**Impact on plan:** No impact on the actual migration data or verification results — the error was confined to a human-readable note in the tracking manifest, caught and corrected before the plan closed.

## Issues Encountered

- ZFS `used` (5,551,694,275,968 bytes / 5.05T) on `backup/media-staging` reads lower than `logicalused` (5,729,791,449,088 bytes / 5.21T) and the `du --apparent-size` total (5,727,815,651,227 bytes). This is ZFS block-level accounting (recordsize/ashift rounding of how referenced blocks are counted at the dataset level), not missing data — the authoritative completeness check is the exact match between `du --apparent-size` on `/mnt/media` and `/mnt/media-staging` (both 5,727,815,651,227 bytes) and the exact file-count match (3,478 on both sides), both confirmed in Task 4.
- The `backup` pool had a scrub in progress when Task 2's capacity recheck ran (started before this plan, unrelated maintenance); it was not a blocker per the plan's exit criteria (pool `ONLINE`, no errors reported) and completed cleanly during the copy window (`scrub repaired 0B ... with 0 errors`).

## User Setup Required

None — no external service configuration required. All commands executed by the agent over SSH to `ser8` with the `bdhill` deploy user and passwordless `sudo`.

## Next Phase Readiness

Plan 13-04 (staging verification) can proceed: `backup/media-staging` holds a complete, structurally verified frozen copy of `/mnt/media`, matching the Plan 13-01 preflight manifest exactly on file count and apparent byte total. Plan 13-04 should run its full sampled/checksum verification gate against this staging copy to close out `ZFS-01`.

**Outage window status:** the application stack remains **stopped** by design (all 18 freeze-set units, since Task 1) — this is expected and correct per D-03's timing tradeoff (the freeze happens once, here, not again at the original Stage 3). Services stay down through Plan 13-04's verification, Plan 13-05's destructive cutover, and Plan 13-06's restore, resuming only in Plan 13-07 after the post-restore application tests and first scrub. Camera recording (Frigate) remains paused for the duration, as accepted in Task 1's checkpoint.

**Rollback matrix (this plan's row, per the plan's `<output>` spec):**

| Point | Authoritative copy | Rollback action |
|---|---|---|
| After initial staging copy | Original ext4 plus MergerFS | Destroy staging only after separate approval |

The original ext4 + MergerFS media tree is untouched and remains the authoritative copy until Plan 13-05's destructive disk erase — nothing in this plan is irreversible. Restarting the original stack against the unchanged MergerFS mount remains available at any point before Plan 13-05.

## Self-Check: PASSED

`backup/media-staging` and `.planning/async-jobs/media-staging-rsync.json` both confirmed present; commits `3647bbd`, `22943d2`, `2df7325` confirmed in `git log`.

---
*Phase: 13-zfs-mirror-migration*
*Completed: 2026-08-24*
