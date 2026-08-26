---
phase: 13-zfs-mirror-migration
plan: 06
subsystem: infra
tags: [zfs, send-recv, systemd-run, ser8, restore, samba, jellyfin, radarr, sonarr]

# Dependency graph
requires:
  - phase: 13-zfs-mirror-migration
    provides: "Empty two-disk media ZFS mirror ONLINE with media/data mounted at /mnt/media, all 19 freeze-set units masked, zfs-media-mirror merged to main (Plan 13-05)"
provides:
  - "media/data fully populated via zfs send/recv from backup/media-staging@verified -- independently verified byte-identical to the Plan 13-01 baseline (3,478 files, 5,727,815,651,227 apparent bytes)"
  - "All 19 freeze-set units unmasked (both the declarative Nix-config disable and the leftover Plan 13-05 runtime masks) and individually confirmed active, started in the fixed documented order"
  - "Full Step 5.4 validation: Jellyfin plays a movie and an episode, Radarr/Sonarr roots verified against real files on disk, Samba read/write/delete round-trip via SMB, ZFS exporter exposes the media pool, zpool status clean"
  - "Two pre-existing, non-migration-caused data-hygiene findings surfaced and deferred (stale downloads/complete smoketest path, systemic Bazarr ACL write gap)"
affects: [13-07-cleanup]

# Actuals (#2632)
actuals:
  tokens: 4200
  tasks: 5
  commits: 3

# Tech tracking
tech-stack:
  added: []
  patterns: [nix-declarative-service-disable-for-reboot-safe-freeze, dual-mask-layer-clearing-declarative-plus-runtime-control, zfs-recv-dash-F-onto-nix-precreated-empty-dataset]

key-files:
  created:
    - hosts/ser8/media/freeze-set-disable.nix (temporary, added then removed within this plan)
    - .planning/async-jobs/media-mirror-restore.json
  modified:
    - hosts/ser8/default.nix
    - .planning/phases/13-zfs-mirror-migration/deferred-items.md

key-decisions:
  - "Mandatory first-scope task (operator decision recorded in Plan 13-05): declared all 19 freeze-set units enable=false via a new hosts/ser8/media/freeze-set-disable.nix, build-validated and activated (make test-ser8 then make switch-ser8) before the restore launched, so D-16's masking survives an unplanned reboot during the ~10h transfer (the live Plan 13-05 runtime masks alone do not survive impermanence's root-filesystem wipe on reboot)"
  - "zfs send -s is --skip-missing on this host's zfs-2.4.3-1 (valid only with -R/replicate), not a resumability-enabling flag as the migration doc's D-08 assumed -- dropped -s entirely; resumable receive is automatic zfs receive behavior on an interrupted stream via receive_resume_token, not something the sender requests"
  - "zfs recv needed -F to receive a full (non-incremental) stream into media/data, which already existed as an empty dataset with Plan 13-05's declared properties -- confirmed safe since -F's rollback is a no-op against zero snapshots/data, and the stream carries no -p/--props so the pre-set dataset properties were untouched"
  - "Two independent mask layers had to be cleared at the service-start step, not one: Task 0's declarative enable=false (cleared by removing freeze-set-disable.nix + make switch-ser8) AND the separate Plan 13-05 runtime masks at /etc/systemd/system.control/<unit> -> /dev/null (cleared by explicit rm + systemctl daemon-reload) -- switching to a generation with enable=true again does not touch the second layer, which lives outside NixOS's managed /etc/systemd/system tree by design"
  - "Two pre-existing, non-migration-caused issues found during Step 5.4 validation and explicitly NOT auto-fixed per the executor's scope boundary: (1) scripts/smoketests/media/all.sh checks a legacy /mnt/media/downloads/complete path that no longer exists (confirmed absent in the untouched Plan 13-01 preflight inventory, predating this phase); (2) a systemic ACL gap (base group:: entry is r-x, not rwx) blocks Bazarr's write access across ~280 tv/movies directories (confirmed byte-identical on backup/media-staging, created weeks before any ZFS work) -- both logged to deferred-items.md and the cross-phase WINDOWS.md ledger (entries 13, 14) rather than fixed, since neither is caused by this plan's changes and both require separately-scoped remediation"
  - "Git policy correction mid-plan (operator, effective for the remainder of the phase): no pushes to origin during the phase at all -- not even via PR. All commits (source and planning docs) are local on main; origin is updated once at phase completion after a history restructure. Task 0's declarative-disable commit and this plan's manifest/summary commits were pushed before this correction landed (left in place per operator instruction, not reverted); Task 3's re-enable commit and everything after are local-only"
  - "History was rewritten mid-plan by the operator (component-scoped commits + one docs squash) -- re-anchored via git log before continuing; no pre-rewrite SHA referenced or reset to"
  - "ZFS-04 marked complete: MergerFS removed (Plan 13-05), disko defines the mirror (Plan 13-02), the full media stack runs healthy on ZFS (all 19 units individually confirmed active), and the named smoketests (test-zfs-media.sh's six checks: mount type, pool health, mirror membership, canonical dirs, group access, import-write) all pass. ZFS-03 intentionally NOT marked complete -- its second clause (first scrub completes with zero data errors) is Plan 13-07's Step 5.5, not yet run"

patterns-established:
  - "For a reboot-safe freeze on an impermanence host, disable services declaratively (systemd.services.<name>.enable = lib.mkForce false via lib.genAttrs over a name list) rather than relying solely on a live systemctl mask, which does not survive impermanence's root wipe on real reboot -- verified by build (units compile as *-disabled derivations) before activating"
  - "When two independent mask mechanisms are stacked (a live runtime override plus a later declarative one), removing only the declarative layer and switching generations is not sufficient -- explicitly audit and clear every mask layer (systemctl show -p LoadState on every affected unit) before attempting to start anything"
  - "zfs recv into a Nix/disko-created empty destination dataset that already carries the desired properties needs -F (forces rollback to the most recent snapshot, a no-op when the destination has zero snapshots/data) since a full stream refuses to receive into an existing filesystem without it; because the stream is not sent with -p, the destination's pre-set properties survive the receive untouched"
  - "ls -l's displayed group permission bits reflect a file's ACL mask, not its true base group:: entry, whenever an extended POSIX ACL (visible as a trailing + in ls -l) is present -- always getfacl before trusting mode bits for a group-permission question on ACL'd media libraries"

requirements-completed: [ZFS-04]

coverage:
  - id: D1
    description: "zfs send/recv restore of the full 5.7 TB media tree into media/data, independently verified byte-identical to the Plan 13-01 baseline (file count and apparent byte total both exact matches)"
    requirement: "ZFS-03"
    verification:
      - kind: manual_procedural
        ref: "find /mnt/media -xdev -type f | wc -l = 3478 (baseline 3,478); du -sb --apparent-size /mnt/media = 5727815651227 (baseline 5,727,815,651,227); zpool status media ONLINE, 0/0/0 errors on both approved WWN mirror members"
        status: pass
    human_judgment: false
  - id: D2
    description: "All 19 freeze-set units unmasked (declarative + runtime layers both cleared) and started in the documented fixed order, each individually confirmed active"
    requirement: "ZFS-04"
    verification:
      - kind: manual_procedural
        ref: "systemctl is-active per-unit loop over all 19 units on ser8, DOWN count = 0"
        status: pass
    human_judgment: false
  - id: D3
    description: "Full application-level validation: Jellyfin serves real movie and episode bytes, Radarr/Sonarr roots match real files on disk, Samba read/write/delete round-trips via SMB, ZFS exporter exposes the media pool, zpool status clean"
    requirement: "ZFS-04"
    verification:
      - kind: manual_procedural
        ref: "Jellyfin /Videos/{id}/stream range request HTTP 206 for one movie and one episode; Radarr rootfolder accessible=true with sampled movieFile paths present on disk; Sonarr rootfolder accessible=true with 3,350 episode files on disk vs 3,364 reported; smbclient put/get/del round-trip against //localhost/media confirmed on-disk and removed; findmnt shows fstype zfs; curl localhost:9134/metrics matches zfs_pool.*media; zpool status media clean"
        status: pass
    human_judgment: false
  - id: D4
    description: "Two pre-existing, non-migration-caused findings from Step 5.4 (stale smoketest path, systemic Bazarr ACL gap) require an operator decision on remediation scope and priority"
    verification: []
    human_judgment: true
    rationale: "Both findings are confirmed out of this plan's scope (present before the freeze began) but represent real, non-trivial follow-up work (updating/retiring a stale smoketest path, and a setfacl normalization pass across ~280 directories plus a decision on whether the group:mealie:rwx named ACL entries are intentional) -- the operator should decide priority and whether either blocks Plan 13-07"

duration: ~18h25m wall clock (~1h45m active engineering across the mandatory first-scope task and 4 plan tasks; ~10h16m was the unattended zfs send/recv transfer, remainder was checkpoint approval wait time, per this plan's explicit no-auto-approve policy on the two MANDATORY STOP gates)
completed: 2026-08-25
status: complete
---

# Phase 13 Plan 06: ZFS Send/Recv Restore and Service Restart Summary

**Restored the full 5.7 TB media tree into `media/data` via `zfs send/recv`, independently verified byte-identical to the pre-freeze baseline, then brought all 19 freeze-set services back online in the documented fixed order and confirmed the restored mirror serves Jellyfin, Radarr/Sonarr, and Samba correctly**

## Performance

- **Duration:** ~18h25m wall clock (~1h45m active engineering; ~10h16m was the unattended `zfs send/recv` transfer; remainder was checkpoint approval wait time)
- **Started:** ~2026-08-24T20:50:00Z
- **Completed:** 2026-08-25T15:12:26Z
- **Tasks:** 5/5 (mandatory first-scope task + 4 plan tasks)
- **Files modified:** 4 (`hosts/ser8/default.nix`, `hosts/ser8/media/freeze-set-disable.nix` created-then-removed, `.planning/async-jobs/media-mirror-restore.json`, `.planning/phases/13-zfs-mirror-migration/deferred-items.md`)

## Accomplishments

- **Mandatory first-scope task:** declared all 19 freeze-set units `enable = false` in a new `hosts/ser8/media/freeze-set-disable.nix`, build-validated (`make check`, `make build-ser8` confirmed all 19 units built as `*-disabled`), then activated (`make test-ser8` then `make switch-ser8`, confirmed as ser8's boot default) before the restore launched -- so D-16's masking survives an unplanned reboot during the multi-hour transfer, per the operator's decision recorded in Plan 13-05
- **Step 5.1:** snapshotted `backup/media-staging@verified` and dispatched the restore as a detached `systemd-run` unit (`media-mirror-restore`), fixing two Rule 1 bugs in the literal doc/plan command along the way (see Deviations) before it ran; the corrected `zfs send backup/media-staging@verified | zfs recv -F -u media/data` completed cleanly after 10h15m43s (`ExecMainStatus=0`, `Result=success`, `receive_resume_token` absent -- stream completed whole)
- **Step 5.2:** independently re-verified restore integrity (not trusted from any relayed report alone) -- `zpool status media` ONLINE with zero errors, mounted `media/data` at `/mnt/media`, and confirmed the restored tree matches the Plan 13-01 baseline exactly: 3,478 files, 5,727,815,651,227 apparent bytes
- **Step 5.3:** removed the declarative disable (local commit, `make check`/`build`/`test`/`switch`), discovered and cleared a second, independent mask layer left over from Plan 13-05 (`/etc/systemd/system.control/*.service -> /dev/null`, outside NixOS's managed unit tree), then started all 19 units in the documented fixed order (`media-config` -> arr stack + Jellyfin -> the two setup oneshots -> mount re-check -> Samba -> household/home-automation), confirming every unit individually active (never trusting a bulk exit code)
- **Step 5.4:** ran the full validation suite -- Jellyfin serves real byte ranges (HTTP 206) for both a movie and an episode; Radarr/Sonarr roots report `/mnt/media/movies`/`/mnt/media/tv` accessible with previously-registered files verified present on disk; a full Samba write/read/delete round-trip via `smbclient` confirmed on-disk ownership and clean removal; `findmnt`/ZFS exporter/`zpool status` all clean; the new `test-zfs-media.sh` D-19 six-test suite passed cleanly in full
- Found and transparently documented two pre-existing, non-migration-caused data-hygiene issues during Step 5.4 (a stale legacy smoketest path, and a systemic ACL gap blocking Bazarr's write access across most of the library) -- both proven pre-existing against artifacts that predate any ZFS work, deferred per the executor's scope boundary rather than auto-fixed, and logged to both `deferred-items.md` and the cross-phase `WINDOWS.md` ledger

## Task Commits

Executed under two different git policies mid-plan (operator corrections; see Decisions) -- commits below reflect the final, rewritten history:

1. **Mandatory first-scope task (declarative freeze-set disable)** -- `3e411d1` (`media: declaratively disable freeze-set services during restore`)
2. **Task 1 (Step 5.1 snapshot + launch) / Task 2 (Step 5.2 verify + mount)** -- doc/manifest commits squashed by the operator's mid-phase history rewrite into `769e235` (`docs: GSD planning artifacts for v1.2 close and v1.3 phases 12-13 (in progress)`)
3. **Task 3 (Step 5.3 re-enable + unmask + start)** -- `8d78de1` (`media: re-enable freeze-set services after verified restore`)
4. **Task 4 (Step 5.4 validation)** -- no repo file change; live validation only, findings documented in this SUMMARY and `deferred-items.md`

**Plan metadata:** this commit (local only, per the corrected git policy -- not pushed)

## Files Created/Modified

- `hosts/ser8/media/freeze-set-disable.nix` - created for the mandatory first-scope task, removed again at Task 3 once the restore was verified
- `hosts/ser8/default.nix` - import added then removed to match
- `.planning/async-jobs/media-mirror-restore.json` - external-job manifest for the detached restore, updated to `completed-unverified` with full `terminal_details` after independent re-verification
- `.planning/phases/13-zfs-mirror-migration/deferred-items.md` - two new entries for the pre-existing findings

## Decisions Made

See `key-decisions` in the frontmatter for the full list. Highlights:

- The mandatory first-scope task (operator decision from Plan 13-05) was implemented, build-validated, and activated before the restore launched, exactly as scoped
- Two Rule 1 bugs in the plan's literal `zfs send -s | zfs recv -u` command were found and fixed inline before the restore could run at all (see Deviations)
- Two independent mask layers (declarative + leftover runtime) both had to be cleared at the service-start step -- documented as a reusable pattern for any future dual-mechanism freeze
- Two pre-existing, non-migration-caused findings from Step 5.4 were deferred, not fixed, per the executor's scope boundary -- both proven pre-existing against artifacts (the Plan 13-01 preflight inventory, and `backup/media-staging`'s identical ACL) that predate this plan
- Mid-plan git policy correction: pushes to `origin` are no longer allowed during the phase at all (not even via PR); `origin` updates once at phase completion after a history restructure. The two commits pushed before this correction landed (`8809c33`, then-`6c0c93d`/`f07ab00` which no longer exist under those SHAs post-rewrite) were left in place per explicit operator instruction, not reverted
- ZFS-04 marked complete; ZFS-03 intentionally left open pending Plan 13-07's scrub (Step 5.5)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] `zfs send -s` is `--skip-missing` on this host's ZFS version, not a resumability flag**
- **Found during:** Task 1 (Step 5.1 restore launch)
- **Issue:** The migration doc's D-08 and this plan's literal Task 1 `<action>` specified `zfs send -s backup/media-staging@verified | zfs recv -u media/data`. The first dispatch (invocation `915d98c1`) failed immediately (`exit 1`, "skip-missing flag can only be used in conjunction with replicate") with zero bytes written -- on `zfs-2.4.3-1`, `-s`/`--skip-missing` is only valid with `-R` (replicate) and is unrelated to resumability
- **Fix:** Dropped `-s` entirely. Resumable receive is automatic `zfs receive` behavior on an interrupted stream (via the destination's `receive_resume_token` property), not something the sender requests -- the doc's rationale was a naming-only misunderstanding, not a real requirement gap
- **Files modified:** none (live-ops only; documented in `.planning/async-jobs/media-mirror-restore.json`)
- **Verification:** Confirmed `media/data` unchanged (96K, empty) after the failed attempt before relaunching
- **Committed in:** `769e235` (docs squash, manifest notes)

**2. [Rule 1 - Bug] `zfs recv` needs `-F` to receive a full stream into the pre-existing empty `media/data`**
- **Found during:** Task 1 (Step 5.1 restore launch), second attempt
- **Issue:** After fixing #1, the second dispatch (invocation `51cae55b`) failed immediately (`exit 1`, "cannot receive new filesystem stream: destination media/data exists -- must specify -F to overwrite it") because `media/data` already existed as an empty dataset with Plan 13-05's declared properties
- **Fix:** Added `-F`. Confirmed safe: `media/data` had zero snapshots and zero data, so `-F`'s rollback is a no-op; the stream carries no `-p`/`--props`, so the destination's pre-set properties (mountpoint, compression, recordsize, etc.) were not touched by the receive
- **Files modified:** none (live-ops only)
- **Verification:** The corrected command (`zfs send backup/media-staging@verified | zfs recv -F -u media/data`, invocation `1ba36b7b`) reached `active/running` and was confirmed transferring real data (3.07G -> 7.18G -> 17.1G used, growing) before this session ended per D-12
- **Committed in:** `769e235` (docs squash, manifest notes)

**3. [Rule 3 - Blocking, out-of-scope discovery] Leftover Plan 13-05 runtime masks did not clear when the declarative disable was removed**
- **Found during:** Task 3 (Step 5.3 service start)
- **Issue:** After removing `freeze-set-disable.nix` and running `make switch-ser8`, all 19 units still reported `LoadState=masked` -- the Plan 13-05 runtime masks at `/etc/systemd/system.control/<unit>.service -> /dev/null` live outside NixOS's managed `/etc/systemd/system` tree by design (that's exactly why they were needed to override a store-backed unit in 13-05) and are not touched by activation
- **Fix:** Explicitly removed all 19 `/etc/systemd/system.control/*.service` symlinks and ran `systemctl daemon-reload`. Confirmed every unit's `LoadState` was `loaded` (not `masked`) before starting anything
- **Files modified:** none (live-ops only)
- **Verification:** Per-unit `systemctl show -p LoadState` loop confirmed all 19 `loaded` before the start sequence began; all 19 confirmed `active` after
- **Committed in:** n/a (live-ops)

---

**Total deviations:** 3 auto-fixed (2 Rule 1 bugs in the restore command, 1 Rule 3 blocking discovery about a second mask layer). Two additional findings (stale smoketest path, systemic Bazarr ACL gap) were investigated, confirmed pre-existing and out of scope, and deliberately NOT auto-fixed -- see below.
**Impact on plan:** All three fixes were necessary for this plan's own stated acceptance criteria to hold (the restore could not run at all without fixes #1/#2; the service stack could not start without fix #3). No scope creep -- every fix stayed within the live-ops/minimal-repo-change boundary.

## Known Issues (deferred, not fixed)

Both confirmed pre-existing and NOT caused by this plan's changes -- see `deferred-items.md` for full detail and the recommended remediation for each. Logged to `WINDOWS.md` as ledger entries 13 and 14.

**1. `scripts/smoketests/media/all.sh` checks a legacy `/mnt/media/downloads/complete` path that no longer exists.** Confirmed absent even in the Plan 13-01 preflight inventory (taken before this phase's freeze began) -- almost certainly a Phase 12 qBittorrent/torrent-retirement leftover the smoketest was never updated for. Every other check in `all.sh` (service connectivity, primary groups, media library permissions, and the full `test-zfs-media.sh` D-19 six-test suite) was independently run and passed; only this one stale check fails, so `./scripts/smoketests/media/all.sh ser8` does not itself exit 0 even though the migration's actual deliverables are all verified.

**2. Systemic ACL gap blocks Bazarr's write access across ~280 `tv`/`movies` directories.** The base `group::` ACL entry on these directories is `r-x`, not `rwx` (only a named `group:mealie:rwx` entry gets full access) -- `ls -l`'s displayed mode bits reflect the ACL mask, not the true base group entry, which is why this wasn't visually obvious. Confirmed byte-identical on `backup/media-staging` (created via `rsync -aHAX` in Plan 13-03, weeks before any ZFS work), proving the restore faithfully preserved a pre-existing condition rather than introducing one. Needs a deliberate `setfacl -R` normalization pass and a decision on whether the `mealie` named entries are intentional -- out of scope for a restore-cutover plan to invent.

Neither finding blocks Plan 13-07 (the scrub and staging destroy depend only on data/checksum integrity, independently confirmed intact here).

## Issues Encountered

None beyond the three auto-fixed deviations and the two deferred findings documented above.

## User Setup Required

None -- no external service configuration required. All live-ops executed over SSH to ser8 with the `bdhill` deploy user and passwordless `sudo`.

## Next Phase Readiness

**Plan 13-07 (scrub, staging destroy, cleanup, downloads relocation) can proceed.**

**Live state at handoff:**

- `media` zpool: ONLINE, one `mirror-0` vdev, both approved WWNs, `media/data` mounted at `/mnt/media` with the full restored library (5.20T used, 5.58T avail)
- `backup/media-staging` and its `@verified` snapshot: still intact, untouched -- the sole remaining backup copy until Plan 13-07's Step 5.5 (scrub) and Step 6.2 (staging destroy, separately approved) complete
- All 19 freeze-set units: unmasked (both layers cleared) and confirmed individually `active`
- ser8's boot default: generation 284, confirmed via `/run/current-system`, `/nix/var/nix/profiles/system`, and `/boot/loader/loader.conf`
- Two pre-existing findings (stale smoketest path, systemic Bazarr ACL gap) logged and deferred -- available for the operator to prioritize separately from this migration

**Rollback matrix (this plan's row, per the plan's own `<output>` spec):**

| Point | Authoritative copy | Rollback action |
|---|---|---|
| After restore verification | New mirror plus staging | Return services to staging or repair the mirror |

**Requirements status:** `ZFS-04` marked complete. `ZFS-03` intentionally NOT marked complete -- its first clause (intrinsic checksum-clean restore) is satisfied here, but its second clause (first scrub completes with zero data errors) is Plan 13-07's Step 5.5, not yet run.

## Self-Check: PASSED

Re-verified live state directly (not trusted from any summarized report) immediately before writing this SUMMARY: `zpool status media` ONLINE, zero errors; all 19 units individually `active` via a fresh `systemctl is-active` loop; `find`/`du` byte-for-byte match against the Plan 13-01 baseline; Samba round-trip file confirmed removed from `/mnt/media`; `git log --oneline -5` on `main` shows `8d78de1` as `HEAD` with the expected commit chain beneath it.

---
*Phase: 13-zfs-mirror-migration*
*Completed: 2026-08-25*
