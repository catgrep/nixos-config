---
phase: 13-zfs-mirror-migration
plan: 01
subsystem: infra
tags: [zfs, smartctl, disko, ser8, migration-doc, ssh]

# Dependency graph
requires:
  - phase: 12-fleet-repair
    provides: "Stable, API-clean fleet (qBittorrent/wgnord/nginx deleted, Radarr root folders clean) that this plan's live checks depend on"
provides:
  - "Truthful migration doc (post-Phase-12, D-01/D-04/D-08/D-21/D-22-amended) as the single source of truth for Plans 13-02 through 13-07"
  - "Passing short SMART health test gate (ZFS-01 evidence) on both approved 12 TB disks"
  - "Frozen source-inventory manifest baseline on ser8 for later verification gates (Plans 13-04, 13-06)"
affects: [13-02-repository-storage-declaration, 13-03-freeze-and-staging-copy, 13-04-staging-verification, 13-06-restore]

# Actuals (#2632)
actuals:
  tokens: 4600
  tasks: 4
  commits: 2

# Tech tracking
tech-stack:
  added: []
  patterns: [smartctl-short-self-test-gate, zfs-send-recv-restore, per-file-sampled-verification]

key-files:
  created:
    - .planning/phases/13-zfs-mirror-migration/deferred-items.md
    - .planning/phases/13-zfs-mirror-migration/evidence/step-0.5-source-inventory-summary.md
  modified:
    - .planning/SER8-ZFS-MIRROR-MIGRATION.md
    - .planning/REQUIREMENTS.md
    - .planning/ROADMAP.md

key-decisions:
  - "Amended the 938-line migration doc across 10 targeted sections only, preserving Approval Contract, Safety Rules, Approved Disk Inventory, and Non-Goals byte-identical (git diff verified zero hunks in those ranges)"
  - "Left two pre-existing stale qBittorrent/wgnord/nginx references (Known Blockers section, Step 3.1) untouched — outside the approved 10-edit scope — and logged them to deferred-items.md instead of expanding scope"
  - "Did not mark ZFS-01/ZFS-05 complete in REQUIREMENTS.md — both requirements span multiple plans (ZFS-01: 13-01/13-03/13-04; ZFS-05: 13-01/13-05/13-07) and this plan only satisfies a portion of each"

patterns-established:
  - "Doc-stage-per-plan cadence (D-10): each plan reads the migration doc cold and updates exactly the sections its stage owns"
  - "Live SSH inspection results compared against the doc's Verified State at Handoff, with drift explicitly recorded rather than silently overwritten"

requirements-completed: []

coverage:
  - id: D1
    description: "Migration doc amended across 10 targeted sections (Service Freeze Set, Goal, Steps 0.2/0.3/0.4, Smoketests, Stage 5, mermaid, Step 3.3, Handoff Status, Desired ZFS Configuration) reflecting D-01/D-04/D-08/D-21/D-22, with Approval Contract/Safety Rules/Approved Disk Inventory preserved byte-identical"
    requirement: "ZFS-05"
    verification:
      - kind: other
        ref: "git diff HEAD~1 HEAD -- .planning/SER8-ZFS-MIRROR-MIGRATION.md — confirmed zero hunks in protected line ranges"
        status: pass
    human_judgment: false
  - id: D2
    description: "Both approved 12 TB disks (wwn-...b56ea81a, wwn-...b3733a87) pass smartctl -a counter check (PASSED, zero reallocated/pending/offline-uncorrectable) plus sequential smartctl -t short self-test (completed without error)"
    requirement: "ZFS-01"
    verification:
      - kind: manual_procedural
        ref: "ssh bdhill@192.168.68.65 'sudo smartctl -a ...' and 'sudo smartctl -t short ...' — results recorded in this SUMMARY's Accomplishments section"
        status: pass
    human_judgment: false
  - id: D3
    description: "Source inventory manifest written to /persist/zfs-migration/media-inventory-preflight.tsv on ser8 (3,809 entries, 3,478 regular files), byte total reconciling with du --apparent-size within 97 bytes; repo-side summary committed"
    verification:
      - kind: manual_procedural
        ref: "ssh bdhill@192.168.68.65 'sudo wc -l /persist/zfs-migration/media-inventory-preflight.tsv' and du -sb cross-check"
        status: pass
    human_judgment: false

duration: ~25min (across 4 checkpoint round-trips)
completed: 2026-08-24
status: complete
---

# Phase 13 Plan 01: Preflight & Doc Reconciliation Summary

**Migration doc reconciled to the post-Phase-12 world (D-01), both approved 12 TB disks pass the short SMART health test gate, and a 3,478-file source-inventory baseline is frozen on ser8**

## Performance

- **Duration:** ~25 min of active execution (plus checkpoint wait time for 4 separate human approvals)
- **Started:** 2026-08-24T06:44:00Z
- **Completed:** 2026-08-24T07:10:00Z
- **Tasks:** 4/4
- **Files modified:** 5 (3 modified, 2 created)

## Accomplishments

- Rewrote 10 sections of `.planning/SER8-ZFS-MIRROR-MIGRATION.md` (938 lines) to remove the deleted qBittorrent/wgnord/nginx stack from the Service Freeze Set, replace the 20+ hour extended SMART scan with a ~2 min short-test gate, replace the rsync-based restore with `zfs send/recv`, and mark Phase 12's fixes (wgnord loop, Radarr root folders) as satisfied — while leaving Approval Contract, Safety Rules, and Approved Disk Inventory byte-for-byte unchanged
- Confirmed live ser8 state via SSH: both approved WWNs resolve correctly (kernel names swapped exactly as the doc anticipated), all 16 freeze-set services active, zero `wgnord`/`qbittorrent` unit files remain, Radarr reports exactly one root folder (`/mnt/media/movies`)
- Both approved 12 TB disks (`ZJV4C2NZ`, `ZJV2V0K9`) passed `smartctl -a` counter checks (PASSED, all zero) and sequential `smartctl -t short` self-tests (completed without error) — the ZFS-01 evidence record
- Wrote and froze a source-inventory manifest (`/persist/zfs-migration/media-inventory-preflight.tsv`, 3,809 entries) as the baseline Plans 13-04 and 13-06 will verify against

## Task Commits

Each task was committed atomically (Tasks 2 and 3 were read-only inspection/diagnostic steps with no repository file changes to commit):

1. **Task 1: Doc reconciliation (D-01)** — `255eb15` (docs)
2. **Task 2: Step 0.1 live-state reconciliation** — no commit (read-only SSH inspection; findings folded into this SUMMARY)
3. **Task 3: Step 0.4 short SMART health test gate** — no commit (read-only diagnostic; results folded into this SUMMARY)
4. **Task 4: Step 0.5 source inventory manifest** — `3b6ea0e` (docs)

## Files Created/Modified

- `.planning/SER8-ZFS-MIRROR-MIGRATION.md` — 10 sections amended per D-01/D-04/D-08/D-21/D-22
- `.planning/REQUIREMENTS.md` — ZFS-01/ZFS-03 reworded to short-SMART-gate and send/recv language
- `.planning/ROADMAP.md` — Phase 13 success criterion 1 reworded to match
- `.planning/phases/13-zfs-mirror-migration/deferred-items.md` — new, logs two out-of-scope stale references
- `.planning/phases/13-zfs-mirror-migration/evidence/step-0.5-source-inventory-summary.md` — new, Step 0.5 evidence record

## Decisions Made

- Amended exactly the 10 sections the approved checkpoint scoped, verified via `git diff` that Approval Contract/Safety Rules/Approved Disk Inventory/Non-Goals stayed byte-identical
- Logged (rather than fixed) two pre-existing stale sections outside the approved scope — see `deferred-items.md` — to avoid expanding a human-approved edit boundary on a safety-critical document
- Deferred `requirements.mark-complete` for ZFS-01 and ZFS-05: both requirements are split across multiple plans in this phase (ZFS-01 also in 13-03/13-04; ZFS-05 also in 13-05/13-07) and this plan only satisfies a portion of each — marking them complete now would be a phantom completion

## Deviations from Plan

None — plan executed exactly as scoped by the four approved checkpoints. One out-of-scope discovery (stale qBittorrent/wgnord/nginx references in the Known Blockers section and Step 3.1, pre-existing before this task's changes) was logged to `deferred-items.md` per the scope-boundary rule rather than fixed.

## Issues Encountered

- `make check` (full flake evaluation + dry-run host builds) exceeded a 100s bound during Task 1's verification; this is expected for a multi-minute rebuild against doc-only changes with no Nix files touched, and isn't a signal of a problem with the edits. Not re-run to completion in this plan; the next plan that touches Nix files (13-02, repository storage declaration) will exercise it properly.
- SSH access required the deploy user `bdhill` with `sudo` rather than `root@ser8` directly (the plan's illustrative commands use `root@ser8` shorthand); functionally equivalent, `sudo -n true` confirmed passwordless sudo, consistent with Phase 12's evidence.
- A drift was found during Task 2: live `/mnt/media` usage (~5.73 TB) is ~2.06 TB lower than the doc's 2026-08-13 snapshot (7.79 TB). Leading explanation: Phase 12's qBittorrent/wgnord stack deletion removed `/persist/var/lib/qbittorrent` and likely associated torrent-side files under `/mnt/media/downloads`. This is favorable for staging capacity margin and not a blocker, but is recorded here per Task 2's explicit instruction to document any drift.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

Plan 13-02 (repository storage declaration) can proceed: the migration doc is truthful, both target disks are SMART-healthy, and a frozen source-inventory baseline exists for later verification. No blockers. The `deferred-items.md` note on stale Step 3.1 language should be addressed by Plan 13-03 before it presents that step's freeze commands to the operator.

---
*Phase: 13-zfs-mirror-migration*
*Completed: 2026-08-24*
