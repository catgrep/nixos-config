---
phase: 13-zfs-mirror-migration
plan: 07
subsystem: infra
tags: [zfs, scrub, ser8, downloads, sabnzbd, nzbget, sops, samba, docs]

# Dependency graph
requires:
  - phase: 13-zfs-mirror-migration
    provides: "media/data fully populated and verified byte-identical to the pre-freeze baseline, all 19 freeze-set units active, full Step 5.4 application validation passed (Plan 13-06)"
provides:
  - "First independent end-to-end integrity check of the restored media mirror: scrub repaired 0B in 07:42:32 with 0 errors on both approved WWN mirror members (ZFS-03)"
  - "ser8 storage documentation (CLAUDE.md, hosts/ser8/README.md, samba.nix share comment) fully truthful -- zero MergerFS references describing current state"
  - "rpool/safe/downloads: 500G-quota NVMe dataset live on ser8, mounted at /mnt/downloads, off the media mirror's write path"
  - "SABnzbd and NZBGet write completed downloads exclusively to rpool/safe/downloads; the media mirror receives writes only from confirmed imports"
  - "backup/media-staging destroyed -- not executed by this plan's automated flow (deferred to the operator, D-18), but confirmed complete: the operator ran zfs destroy -r themselves at 2026-08-25 16:39:47 PDT, after the scrub and after their own independent review"
affects: [14-backup-engine]

# Actuals (#2632)
actuals:
  tokens: 5400
  tasks: 5
  commits: 12

# Tech tracking
tech-stack:
  added: []
  patterns: [imperative-zfs-create-matching-disko-declaration-for-existing-pool, sops-templates-restartunits-required-for-cp-based-config-deploy]

key-files:
  created:
    - .planning/async-jobs/media-scrub.json
    - .planning/phases/13-zfs-mirror-migration/evidence/scrub-and-staging-destroy.md
  modified:
    - CLAUDE.md
    - hosts/ser8/README.md
    - hosts/ser8/samba.nix
    - hosts/ser8/disko-config.nix
    - hosts/ser8/impermanence.nix
    - hosts/ser8/media/sabnzbd.nix
    - hosts/ser8/media/nzbget.nix
    - .planning/phases/13-zfs-mirror-migration/deferred-items.md
    - .planning/REQUIREMENTS.md

key-decisions:
  - "Operator decision mid-plan: backup/media-staging's destroy is permanently out of this plan's (and phase's) automated scope. The operator will run `zfs destroy -r backup/media-staging` themselves after independently confirming the scrub result. This plan's original Task 3 (observe cutover), Task 4 (destroy approval checkpoint), and Task 5 (destroy execution) were intentionally not run -- recorded durably in deferred-items.md so no future session re-dispatches them."
  - "Operator approved proceeding out of order with the plan's non-scrub-dependent tasks (doc sweep, downloads relocation) while the multi-hour scrub ran in the background, rather than waiting idle for it -- both completed and verified before the scrub finished."
  - "rpool/safe/downloads created imperatively via `zfs create` with properties matching the disko-config.nix declaration exactly, then activated via make test-ser8/switch-ser8 -- the same pattern Plan 13-05 used for the media mirror itself, since disko does not retrofit new datasets onto an already-provisioned pool through a normal nixos-rebuild switch."
  - "[Rule 1 - Bug] media-config.service's configure_arr only cp's the sops-rendered template when the service unit itself (re)starts; neither sabnzbd.ini nor nzbget.conf's sops.templates entry declared restartUnits, so the first switch after the path migration silently left the live .ini/.conf on the old /mnt/media/downloads paths. Fixed by adding restartUnits = [ media-config.service <service>.service ] to both templates (matching the already-known Phase 11 sops-templates lesson in STATE.md), then manually restarting media-config.service -> sabnzbd.service/nzbget.service to apply the already-rendered content immediately."
  - "Confirmed, not assumed: Radarr and Sonarr's remotepathmapping APIs both returned an empty list, so no config change was needed in either service for the downloads path migration -- verified via direct API calls with each service's sops-managed API key, per the plan's own instruction not to skip this check."
  - "ZFS-05 marked complete: the operator ran `zfs destroy -r backup/media-staging` themselves (zpool history: 2026-08-25.16:39:47), after the scrub completed (15:59:52) and after their own independent review -- satisfying the requirement's literal text (\"destroyed only after post-cutover observation and separate approval\") even though this plan's own automated Task 3/4/5 never ran. Discovered via this plan's own live-state self-check, not assumed from the coordinator's earlier message (which correctly reported staging still present at the time it was sent, before the operator acted)."

patterns-established:
  - "For a dataset added to an already-imported ZFS pool (not a fresh disko provisioning run), declare it in disko-config.nix for documentation/future-rebuild fidelity, then create it imperatively via `zfs create` with the exact same -o flags as the declared options, then activate the matching Nix generation -- disko's module does not retrofit new datasets onto a live pool through nixos-rebuild alone."
  - "Any sops.templates entry whose rendered content is consumed via a custom deploy script (not systemd's own EnvironmentFile/ExecStart mechanism) needs explicit restartUnits covering both the deploy oneshot and the actual service, or a content-only template change will silently fail to reach the live service."

requirements-completed: [ZFS-03, ZFS-05]

coverage:
  - id: D1
    description: "First scrub of the restored media mirror completes with zero data errors and zero required repairs, both mirror members remaining ONLINE"
    requirement: "ZFS-03"
    verification:
      - kind: manual_procedural
        ref: "zpool status media: 'scan: scrub repaired 0B in 07:42:32 with 0 errors on Tue Aug 25 15:59:52 2026'; both approved WWN members ONLINE 0/0/0; systemctl show media-scrub: ActiveState=inactive SubState=dead Result=success ExecMainStatus=0 -- independently re-verified directly against ser8, not trusted from the relayed report alone"
        status: pass
    human_judgment: false
  - id: D2
    description: "MergerFS documentation sweep: zero references describing current ser8 storage as MergerFS-backed in CLAUDE.md, hosts/ser8/README.md, or samba.nix"
    requirement: "ZFS-04 (doc-sweep clause)"
    verification:
      - kind: manual_procedural
        ref: "grep -ric mergerfs CLAUDE.md hosts/ser8/README.md returns 0/0; repo-wide grep across hosts/ser8/ and modules/ shows only a correctly-historical past-tense reference (disko-config.nix comment) and generic gateway Prometheus/Grafana fstype exclusion filters unrelated to ser8's current storage"
        status: pass
    human_judgment: false
  - id: D3
    description: "rpool/safe/downloads live with a 500G quota, mounted at /mnt/downloads, and SABnzbd/NZBGet write there exclusively"
    requirement: "ZFS-05 context (D-21/D-22), not a numbered ZFS-0x requirement itself"
    verification:
      - kind: manual_procedural
        ref: "zfs get quota rpool/safe/downloads = 500G; mount shows a ZFS mount at /mnt/downloads; sabnzbd.ini and nzbget.conf both show zero /mnt/media/downloads occurrences and confirmed-live /mnt/downloads paths on disk after a forced media-config/sabnzbd/nzbget restart; test-zfs-media.sh's 6-check suite (including the import-write test) passes; Radarr/Sonarr remotepathmapping APIs both empty"
        status: pass
    human_judgment: false
  - id: D4
    description: "backup/media-staging destroyed by the operator's own action, satisfying ZFS-05's destroy-completion clause -- discovered via this plan's own final live-state check, not assumed"
    requirement: "ZFS-05"
    verification:
      - kind: manual_procedural
        ref: "zpool history backup shows '2026-08-25.16:39:47 zfs destroy -r backup/media-staging'; zfs list backup/media-staging returns 'dataset does not exist'; backup pool capacity returned (364G used, 10.1T avail, up from ~5.05T consumed); mount shows zero media-staging mounts; camera datasets (backup/cameras, backup/cameras/recordings, backup/cameras/clips) confirmed unchanged; media/data remains the sole live source at /mnt/media"
        status: pass
    human_judgment: true
    rationale: "The operator explicitly decided this plan's automated flow would not execute the destroy (D-18) and would instead own both the approval and the execution themselves. They then did exactly that, independently, after the scrub completed and after their own review -- confirmed by this plan's own live-state self-check rather than assumed from the coordinator's earlier message (which correctly reported staging as still present at the moment it was sent, before the operator's action). The requirement's literal text is now satisfied: the destroy happened only after post-cutover observation (this scrub, plus Plan 13-06's Step 5.4) and separate approval (the operator's own explicit decision and action, with no delegation gap)."

duration: ~8h25m wall clock (~50min active engineering across two sessions; ~7h42m32s was the unattended scrub, remainder was the external-job wait between sessions per this plan's explicit external_job_waiting policy)
completed: 2026-08-25
status: complete
---

# Phase 13 Plan 07: Scrub, Documentation Sweep, and Downloads Relocation Summary

**Scrubbed the restored media mirror clean (0 errors, 0B repaired), swept every stale MergerFS reference from ser8's documentation, relocated SABnzbd/NZBGet downloads onto a new 500G-quota NVMe dataset, and confirmed the operator's own independent destroy of `backup/media-staging` -- handed off mid-plan rather than executed by this plan's automated flow, then completed by the operator shortly after the scrub finished**

## Performance

- **Duration:** ~8h25m wall clock (~50min active engineering across two sessions; ~7h42m32s was the unattended scrub, remainder was the external-job wait between sessions)
- **Started:** 2026-08-25T15:16:30Z (scrub launch)
- **Completed:** 2026-08-25T23:41:00Z (approximate, this summary's commit)
- **Tasks:** 5 executed as designed (launch scrub, verify scrub, MergerFS sweep, downloads dataset, path migration) + 1 explicit operator-deferral decision recorded in place of the plan's original destroy-related tasks (3/8), later confirmed executed by the operator's own independent action
- **Files modified:** 11 (see key-files)

## Accomplishments

- **Step 5.5 (Task 1):** Launched the first scrub of the restored `media` mirror as a detached `systemd-run` unit (`media-scrub`), confirmed scanning, recorded an async-job manifest, and returned control per D-12/D-13 rather than blocking on a multi-hour operation. Preconditions (pool ONLINE 0 errors, staging intact, all freeze-set services active) were independently confirmed before launch.
- **Task 2 (scrub verification, ZFS-03):** Independently re-verified the scrub's terminal result directly against ser8 (not trusted from any relayed report alone): `scrub repaired 0B in 07:42:32 with 0 errors on Tue Aug 25 15:59:52 2026`, both approved WWN mirror members ONLINE with 0/0/0 read/write/checksum counters, unit `ActiveState=inactive`/`Result=success`/`ExecMainStatus=0`. The full result is recorded in `evidence/scrub-and-staging-destroy.md`. **ZFS-03 marked complete.**
- **Operator decision, then operator action -- staging destroy (D-18):** Mid-plan, the operator decided `backup/media-staging`'s destroy would not be executed by this plan's automated flow at all; they would run it themselves after their own review of the scrub evidence. This plan's original Task 3 (observe the cutover), Task 4 (destroy approval checkpoint), and Task 5 (destroy execution) were intentionally not run -- recorded durably in `deferred-items.md`. The operator then did exactly that: `zpool history backup` on ser8 shows `2026-08-25.16:39:47 zfs destroy -r backup/media-staging`, roughly 40 minutes after the scrub completed. Discovered and independently confirmed via this plan's own final live-state check (not assumed from any prior report), with capacity returned to the backup pool and camera datasets unaffected.
- **Task 6 (MergerFS documentation sweep, D-20):** Rewrote `CLAUDE.md`'s ser8 section and added a plain-language Storage Architecture section to `hosts/ser8/README.md`, both now describing the four live ZFS pools/datasets instead of MergerFS. Also fixed a stale, user-visible Samba share comment (`"Media Storage (MergerFS)"`) found during the repo-wide sweep -- in scope per the task's own grep instruction even though `samba.nix` wasn't in the plan's `files_modified` list.
- **Task 7 (declare and activate `rpool/safe/downloads`, D-21):** Declared the 500G-quota NVMe dataset in `disko-config.nix` and its tmpfiles rules in `impermanence.nix`, build-validated, then created the dataset imperatively via `zfs create` with properties matching the declaration exactly (the same pattern Plan 13-05 used for the media mirror itself), and activated via `make test-ser8` then `make switch-ser8`. Both `media` and `backup` pools stayed ONLINE throughout; no existing downloads data needed migrating (0 files under the old path).
- **Task 8 (migrate SABnzbd/NZBGet paths, D-21/D-22):** Changed both services' download/complete/category paths from `/mnt/media/downloads/usenet/...` to `/mnt/downloads/...`. Found and fixed a real Rule 1 bug along the way (see Deviations) before the migration actually took effect on disk. Confirmed via direct API calls that neither Radarr nor Sonarr has a remote path mapping referencing the old path (both return an empty list). Re-ran `test-zfs-media.sh`'s full 6-check suite, including the import-write test, against the new downloads location -- all pass.

## Task Commits

1. **Task 1 (launch scrub) + async-job manifest** -- `abf566a`, `23c28fe`
2. **Operator-deferral decision recorded** -- `7f22280`
3. **Task 6 (MergerFS doc sweep)** -- `916554d`
4. **Task 7 (declare/activate rpool/safe/downloads)** -- `1b6d4ad`
5. **Task 8 (migrate SABnzbd/NZBGet paths + restartUnits fix)** -- `878239a`
6. **Scrub manifest + session-state update after out-of-order work** -- `407ea76`
7. **Task 2 (scrub verification), ZFS-03** -- `2262d04` (evidence file first drafted here, async-job terminal update, ZFS-03 requirement)
8. **Plan completion (first pass, before the staging-destroy discovery)** -- `f69fa30`
9. **Correction after independently discovering the operator's completed destroy** -- this commit (evidence file and SUMMARY updated to reflect the destroy as complete, ZFS-05 marked complete, deferred-items.md updated, STATE.md/ROADMAP.md)

**Plan metadata:** local only, per this phase's git policy -- not pushed.

## Files Created/Modified

- `.planning/async-jobs/media-scrub.json` - created for the detached scrub, updated to `completed-verified` with full `terminal_details`
- `.planning/phases/13-zfs-mirror-migration/evidence/scrub-and-staging-destroy.md` - created; scrub result plus staging-destroy status/rationale
- `CLAUDE.md` - ser8 section rewritten to describe the four ZFS pools/datasets
- `hosts/ser8/README.md` - added a Storage Architecture section
- `hosts/ser8/samba.nix` - dropped the stale `(MergerFS)` suffix from the media share comment
- `hosts/ser8/disko-config.nix` - added the `safe/downloads` dataset declaration
- `hosts/ser8/impermanence.nix` - added tmpfiles rules for `/mnt/downloads` and its category subdirectories
- `hosts/ser8/media/sabnzbd.nix` - migrated download paths, added `restartUnits`
- `hosts/ser8/media/nzbget.nix` - migrated download paths, added `restartUnits`
- `.planning/phases/13-zfs-mirror-migration/deferred-items.md` - recorded the operator's staging-destroy deferral, then updated to record the operator's completed destroy
- `.planning/REQUIREMENTS.md` - ZFS-03 and ZFS-05 marked complete

## Decisions Made

See `key-decisions` in the frontmatter for the full list. Highlights:

- Staging destroy was permanently out of this plan's/phase's automated scope, by explicit operator decision -- the operator took ownership of both the approval and the execution of that one-way step, and did in fact execute it independently shortly after the scrub completed
- Approved proceeding out of order with the non-scrub-dependent tasks (doc sweep, downloads relocation) while the scrub ran in the background, rather than sitting idle for ~11.7h
- `rpool/safe/downloads` created imperatively matching its disko declaration, mirroring the established Plan 13-05 pattern for adding a dataset to an already-provisioned pool
- Fixed a real Rule 1 bug (`media-config.service`'s config redeploy was never triggered by the path-migration content change) before the plan's own acceptance criteria could actually hold
- ZFS-05 marked complete after this plan's own live-state self-check discovered the operator had already run the destroy -- not assumed from the coordinator's earlier report, which was accurate as of when it was sent

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] `media-config.service`'s config redeploy was never triggered by the SABnzbd/NZBGet path migration**
- **Found during:** Task 8 (migrate SABnzbd/NZBGet download paths)
- **Issue:** The plan's Task 8 action assumed `make switch-ser8` would restart `sabnzbd.service`/`nzbget.service` "via the `media-config.service` oneshot's config redeploy." In fact, `media-config.service`'s script does a plain `cp` of the sops-rendered template into the live `.ini`/`.conf` location, and neither `sabnzbd.ini` nor `nzbget.conf`'s `sops.templates` entry declared `restartUnits` -- so after the first switch, the live config on disk was still `/mnt/media/downloads/usenet/...`, unchanged, even though the rendered template and the repo both showed the new `/mnt/downloads/...` paths
- **Fix:** Added `restartUnits = [ "media-config.service" "<service>.service" ]` to both `sops.templates` entries (matching the already-documented Phase 11 lesson in STATE.md: "`sops.templates.<name>.restartUnits` must be set explicitly for any template whose content can change post-deploy"), then manually ran `systemctl restart media-config.service sabnzbd.service nzbget.service` to apply the already-rendered content immediately rather than waiting for a future unrelated template change to trigger it
- **Files modified:** `hosts/ser8/media/sabnzbd.nix`, `hosts/ser8/media/nzbget.nix`
- **Verification:** `grep -E "download_dir|complete_dir" /var/lib/sabnzbd/sabnzbd.ini` and the equivalent for `nzbget.conf` both confirmed on disk after the manual restart; both services `active`; `test-zfs-media.sh`'s full suite passed afterward
- **Committed in:** `878239a`

**2. [Rule 1/2 - Stale user-facing text, out-of-scope-file discovery] Samba share comment still said "(MergerFS)"**
- **Found during:** Task 6 (MergerFS documentation sweep)
- **Issue:** The task's own repo-wide grep instruction (`grep -rn "mergerfs|MergerFS|/mnt/disk1|/mnt/disk2" hosts/ser8/ modules/ CLAUDE.md hosts/ser8/README.md`) surfaced `hosts/ser8/samba.nix:101` (`comment = "Media Storage (MergerFS)";`) -- a live, user-visible Samba share comment describing the retired topology as current. Not in the plan's `files_modified` list, but explicitly within the task's own search scope and acceptance criteria ("No code comment in `hosts/ser8/` or `modules/` still describes MergerFS as the current media storage mechanism")
- **Fix:** Dropped the `(MergerFS)` suffix
- **Files modified:** `hosts/ser8/samba.nix`
- **Verification:** `grep -c mergerfs hosts/ser8/samba.nix` returns 0; `make build-ser8` dry-run confirmed the change evaluates cleanly
- **Committed in:** `916554d`

---

**Total deviations:** 2 auto-fixed (1 Rule 1 bug blocking the plan's own Task 8 acceptance criteria from holding, 1 Rule 1/2 stale-text fix within the doc-sweep task's own explicit scope).
**Impact on plan:** Both fixes were necessary for this plan's own stated acceptance criteria to actually hold. No scope creep beyond what each task's own instructions already covered.

## Known Issues (deferred, not fixed)

Carried forward from Plan 13-06 (`deferred-items.md`), unaffected by this plan's changes -- see that file for full detail:

1. `scripts/smoketests/media/all.sh`'s stale `/mnt/media/downloads/complete` path check. This plan's downloads relocation makes the underlying question moot (downloads no longer live under `/mnt/media/downloads` at all), but the smoketest itself was not updated -- that remains separately scoped follow-up work.
2. Systemic ACL gap blocking Bazarr's write access across ~280 `tv`/`movies` directories -- confirmed pre-existing, unrelated to this plan.

## Issues Encountered

None beyond the two auto-fixed deviations documented above.

## User Setup Required

None. The operator's staging-destroy action (deferred to them mid-plan) has already been completed -- confirmed via this plan's own live-state check, not merely assumed. No further action required on their part for this plan. All live-ops executed over SSH to ser8 with the `bdhill` deploy user and passwordless `sudo`.

## Next Phase Readiness

**Phase 13 (ZFS Mirror Migration) is complete.** All 7 plans executed. `ZFS-01` through `ZFS-05` are all complete.

**Live state at handoff:**

- `media` zpool: ONLINE, scrubbed clean (`repaired 0B`, `0 errors`), both approved WWNs ONLINE
- `backup/media-staging`: destroyed by the operator (`zpool history`: `2026-08-25.16:39:47 zfs destroy -r backup/media-staging`); capacity returned to the backup pool (364G used, 10.1T avail); camera datasets unaffected
- `rpool/safe/downloads`: live, 500G quota, mounted at `/mnt/downloads`, SABnzbd/NZBGet writing there exclusively
- ser8's boot default: generation 286 (post-downloads-relocation switch), confirmed via `/boot/loader/loader.conf`
- All ser8 documentation (`CLAUDE.md`, `hosts/ser8/README.md`, `samba.nix`) is truthful about the current ZFS-only storage architecture

### ZFS-05 evaluation (per plan coverage rules, given the operator's completed destroy)

ZFS-05's text has two clauses: (1) "Every destructive step follows the migration doc's per-step human approval contract" and (2) "`backup/media-staging` is destroyed only after post-cutover observation and separate approval."

Clause 1 is satisfied -- every destructive step across Plans 13-01 through 13-06 (staging creation, the freeze, the disk erase/repartition, the mirror creation, the restore) was individually approved per the migration doc's contract, with no exceptions.

Clause 2 is now also satisfied. The destroy happened -- `zpool history` on ser8 shows it, timestamped after the scrub completed -- and it happened only after the operator's own independent review (post-cutover observation) and their own explicit decision to act (separate approval), even though this plan's own automated Task 3/4/5 never ran. Approval and execution lived in the same hands with no delegation gap, which is a stricter fulfillment of the requirement's spirit than the plan's original checkpoint-based design. **ZFS-05 marked complete in `REQUIREMENTS.md`.** This conclusion rests on this plan's own final live-state self-check (`zpool history`, `zfs list`, `mount`), not on the coordinator's earlier message, which correctly reported staging as still present at the moment it was sent -- the operator acted in the window between that message and this plan's completion.

**Rollback matrix (this plan's row, per the plan's own `<output>` spec):**

| Point | Authoritative copy | Rollback action |
|---|---|---|
| After staging deletion | New mirror only | Restore from whatever external backups exist (explicitly none for media content, by design per D-18) |

**Requirements status:** `ZFS-03` and `ZFS-05` marked complete this plan, alongside the already-complete `ZFS-01`, `ZFS-02`, `ZFS-04` -- all five Storage requirements for v1.3 are now complete. Phase 14 (Backup Engine) can proceed on the final, stable ZFS topology.

## Self-Check: PASSED

Re-verified live state directly (not trusted from any summarized report, including the coordinator's own) immediately before finalizing this SUMMARY: `zpool status media` shows the exact scrub line quoted above, independently re-queried; `systemctl show media-scrub` independently re-queried showing `inactive`/`dead`/`success`/`0`; `zfs list backup/media-staging` returns `dataset does not exist` and `zpool history backup` shows the exact destroy command and timestamp; `backup` pool capacity confirmed returned; camera datasets confirmed unchanged; `grep` on both `sabnzbd.ini` and `nzbget.conf` on ser8 confirms the migrated paths are live, not just declared; `git log --oneline -10` on `main` shows the expected commit chain culminating in this plan's work. This self-check is what caught the staging-destroy discrepancy between the coordinator's message and the plan's actual final state -- documented here rather than silently overwritten.

---
*Phase: 13-zfs-mirror-migration*
*Completed: 2026-08-25*
