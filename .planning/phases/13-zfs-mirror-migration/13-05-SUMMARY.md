---
phase: 13-zfs-mirror-migration
plan: 05
subsystem: infra
tags: [zfs, disko, sgdisk, systemd-mask, ser8, cutover, destructive]

# Dependency graph
requires:
  - phase: 13-zfs-mirror-migration
    provides: "Gate 3.3 PASS (zero unexplained differences between frozen /mnt/media and backup/media-staging), ZFS-01 fully satisfied (Plan 13-04)"
provides:
  - "Live two-disk media ZFS mirror on ser8 (wwn-0x5000c500b56ea81a + wwn-0x5000c500b3733a87, mirror-0, ONLINE), empty, dataset media/data mounted at /mnt/media with all documented properties"
  - "Original ext4 filesystems on both approved disks permanently erased; backup/media-staging is now the sole remaining copy of the media tree pending Plan 13-06's restore"
  - "All 19 freeze-set units masked live via /etc/systemd/system.control/ (survives make switch-ser8, does not survive a real reboot -- see key-decisions)"
  - "zfs-media-mirror branch merged to main (PR #1, merge commit dec09b3); main now truthfully describes the live media pool"
  - "ser8's persistent boot default (nixos-generation-282) activates the mirror-aware configuration"
affects: [13-06-restore, 13-07-cleanup]

# Actuals (#2632)
actuals:
  tokens: 2100
  tasks: 7
  commits: 0

# Tech tracking
tech-stack:
  added: []
  patterns: [etc-systemd-system-control-for-runtime-masking-on-nixos, wipefs-after-sgdisk-zap-to-clear-residual-fs-signatures, zfs-mount-service-restart-for-new-dataset-after-pool-import]

key-files:
  created: []
  modified: []

key-decisions:
  - "Step 4.1's read-only identity reconfirmation was pre-approved per the operator's explicit checkpoint policy for this plan and executed without stopping; results were folded into the checkpoint presented for Step 4.2 (the first mandatory-stop item) rather than requiring a separate approval round for a read-only check"
  - "Steps 4.2 (unmount), 4.3-gate (erase authorization), 4.3-execution (erase), 4.4 (mirror creation), 4.5a (make test-ser8), and 4.5b (make switch-ser8 + merge) were each treated as mandatory human-gated stops per the operator's explicit plan-level checkpoint policy, overriding this plan's own gate=blocking default -- never auto-approved regardless of mutation class"
  - "sgdisk was not pre-installed on ser8; resolved via an ephemeral nix run of nixpkgs#gptfdisk (a well-known, unambiguous nixpkgs package, not a project dependency addition) rather than treating this as a package-manager-install exclusion under Rule 3 -- no flake.nix or lockfile change, no slopsquat risk"
  - "sgdisk --zap-all clears only GPT metadata, not filesystem superblocks; both new partitions still reported blkid TYPE=ext4 after erase. Fixed with wipefs -a on both -part1 paths before proceeding to pool creation (Rule 1 -- an incomplete erase risked zpool create warning or misbehaving against a residual signature)"
  - "zfs create -o mountpoint=/mnt/media auto-mounted media/data immediately (ZFS default canmount=on, mountpoint was free after Step 4.2's unmount) -- contradicting the plan's own stated expectation that mounting would only happen at Step 4.5's Nix activation. Documented as a plan-fact correction, not a bug: the early mount was empty and correctly sourced, no harm"
  - "systemctl mask (with or without --runtime) cannot override a NixOS-declared unit on ser8: /etc/systemd/system fully resolves into the read-only /nix/store, and /run/systemd/system (where --runtime writes) is lower priority than /etc/systemd/system in systemd's unit search path, so the store-backed definition always wins. Resolved by masking through /etc/systemd/system.control/ instead -- a real, writable directory (only the system/ subdirectory itself is store-backed) that sits above /etc/systemd/system in the search order; verified via LoadState=masked for all 19 units before proceeding to make test-ser8"
  - "make test-ser8 imported the new media pool (fresh zfs-import-media.service) but did not mount media/data: zfs-mount.service is a oneshot/RemainAfterExit unit whose definition was unchanged from two days prior, so NixOS's activation script correctly judged it didn't need restarting even though a brand-new dataset now needed mounting. Fixed with systemctl restart zfs-mount.service"
  - "Operator decision (recorded for Plan 13-06): the /etc/systemd/system.control/ masks live on rpool/local/root, which ser8's impermanence setup wipes to blank on every real reboot -- they survive make switch-ser8 (no reboot occurs) but would not survive an unplanned reboot during the ~10.7h restore. Operator chose the declarative-disable option: Plan 13-06's FIRST task must add a Nix-config-level disable of the freeze-set units (repo change + activation) before the long zfs send/recv starts, so D-16 holds across any reboot; the units are re-enabled only at 13-06's documented service-start step by removing that declarative disable. This is now MANDATORY scope for Plan 13-06, not optional -- see Next Phase Readiness"
  - "ZFS-02 marked complete (mirror created with documented properties, media/data mounted at /mnt/media). ZFS-05 NOT marked complete: this plan followed the per-step approval contract for every step it executed, but ZFS-05's second clause (backup/media-staging destroyed only after post-cutover observation and separate approval) is still pending future plans -- ZFS-05 spans this plan through Plan 13-07's Step 6.2"
  - "PR #1 merged zfs-media-mirror into main without deleting the branch (--delete-branch=false): the migration is not finished (restore, service start, scrub, staging cleanup remain in Plans 13-06/13-07), and Plan 13-06's mandatory declarative-disable task will need further branch/PR work"

patterns-established:
  - "On NixOS, live unit masking that must take effect immediately (not just at next rebuild) requires writing into /etc/systemd/system.control/ (mkdir -p if absent, ln -sf /dev/null <unit>, systemctl daemon-reload) rather than plain systemctl mask or systemctl mask --runtime, because /etc/systemd/system is store-backed and read-only, and /run/systemd/system.control and control-tier directories are the correct, higher-than-/etc/systemd/system override path"
  - "After sgdisk --zap-all + new partition creation, always wipefs -a the new partition before handing it to zpool create -- GPT metadata erasure does not touch filesystem superblocks living inside the partition's data region"
  - "After zpool create/zfs create of a brand-new dataset during a live activation, verify the dataset actually mounted (zfs get mounted) rather than trusting that the pool-import unit alone handles it -- a oneshot zfs-mount.service with unchanged unit content will not be re-triggered by switch-to-configuration even when new datasets exist"

requirements-completed: [ZFS-02]

coverage:
  - id: D1
    description: "Both approved WWNs re-resolved and re-confirmed live (model/serial/capacity/mounts/SMART) independently at Step 4.1 and again at the Step 4.3 gate, per D-11; no protected device (system NVMe, four backup WWNs) implicated in any destructive command"
    requirement: "ZFS-05"
    verification:
      - kind: manual_procedural
        ref: "Live SSH readlink/lsblk/udevadm/smartctl/blkid re-resolution at Step 4.1 and again immediately before Step 4.3's erase gate; both approved tuples matched the doc's inventory exactly both times"
        status: pass
    human_judgment: false
  - id: D2
    description: "Both approved 12 TB disks erased (sgdisk zap + single ZFS-type partition) and only those two disks changed; all five protected devices (system NVMe, four backup WWNs) verified unchanged before and after"
    requirement: "ZFS-02"
    verification:
      - kind: manual_procedural
        ref: "Post-erase blkid/lsblk on all seven relevant devices (2 media + 4 backup + 1 NVMe); PARTTYPENAME=ZFS pool member on both media partitions, zfs_member/vfat/swap unchanged on all five protected devices"
        status: pass
    human_judgment: false
  - id: D3
    description: "media zpool created as exactly one mirror-0 vdev with exactly the two approved WWN partitions, both ONLINE; media/data created with all documented properties and mounted at /mnt/media"
    requirement: "ZFS-02"
    verification:
      - kind: manual_procedural
        ref: "zpool status media (one mirror-0, two members, both ONLINE, both approved WWNs); zfs get mountpoint,canmount,compression,recordsize,atime,acltype,xattr,normalization,dedup,com.sun:auto-snapshot media/data (all match Desired ZFS Configuration table)"
        status: pass
    human_judgment: false
  - id: D4
    description: "All 19 freeze-set units masked before any Nix activation (D-16); make test-ser8 and make switch-ser8 both exited 0 with no freeze-set unit starting; the new generation is ser8's persistent boot default"
    verification:
      - kind: manual_procedural
        ref: "systemctl show <unit> -p LoadState,ActiveState for all 19 units (masked/inactive) before and after both activations; /run/current-system, /nix/var/nix/profiles/system, and /boot/loader/loader.conf default all resolve to nixos-system-ser8-26.05.20260817.0dd31db / nixos-generation-282"
        status: pass
    human_judgment: false
  - id: D5
    description: "zfs-media-mirror branch merged to main via reviewed PR (not a direct push), main now contains the media pool declaration commits"
    verification:
      - kind: manual_procedural
        ref: "gh pr create + gh pr merge (PR #1, merge commit dec09b3); git log main --oneline confirms d5529b7 (feat: declare media zpool mirror, remove MergerFS) and all Plan 13-02/13-03/13-04 commits present on main"
        status: pass
    human_judgment: false

duration: ~1h20m (~45min active engineering across seven tasks; remainder spent waiting on three mandatory human-approval checkpoints, per this plan's explicit no-auto-approve policy)
completed: 2026-08-24
status: complete
---

# Phase 13 Plan 05: Destructive ZFS Mirror Cutover Summary

**Erased both approved 12 TB media disks, created the live two-disk `media` ZFS mirror with `media/data` mounted at `/mnt/media`, masked all 19 freeze-set services, activated the matching Nix generation as ser8's persistent boot default, and merged `zfs-media-mirror` to `main` -- the migration's point of no return, executed with a separate human approval for every disk-mutating step**

## Performance

- **Duration:** ~1h20m (~45 min active engineering across 7 tasks; remainder spent at three mandatory human-approval checkpoints per this plan's explicit no-auto-approve policy)
- **Started:** ~2026-08-24T19:25:00Z
- **Completed:** 2026-08-24T20:45:30Z
- **Tasks:** 7/7
- **Files modified:** 0 (this plan is entirely live-ops against ser8 plus a branch merge; `files_modified: []` per its own frontmatter)

## Accomplishments

- Re-resolved and re-confirmed both approved WWNs live, independently, at Step 4.1 (pre-approved read-only check) and again at the Step 4.3 gate immediately before the erase (D-11) -- exact match to the doc's inventory both times, with kernel device names observed to have swapped again (`/dev/sde`/`/dev/sdf`) since the last inspection, underscoring why the doc bans identifying disks by kernel name
- Unmounted MergerFS (`/mnt/media`) and both ext4 members (`/mnt/disk1`, `/mnt/disk2`) after the operator's typed `"4.2"` echo-back; zero writers confirmed via `lsof` before unmounting
- Erased and repartitioned only the two approved WWNs (`sgdisk --zap-all` + single `BF01` ZFS-type partition) after the operator's typed `"a81a 3a87"` echo-back authorizing the point-of-no-return step; found and fixed a residual-filesystem-signature gap (`wipefs -a` needed after `sgdisk` to clear stale `ext4` superblocks) before handing the partitions to `zpool create`; all five protected devices (system NVMe, four backup WWNs) verified unchanged
- Created `zpool media` as a two-disk mirror with all documented pool/dataset properties and `media/data` mounted at `/mnt/media`, after the operator's typed `"4.4"` echo-back
- Masked all 19 D-16 freeze-set units and ran `make test-ser8` (temporary activation) after operator approval; discovered and fixed two live-environment gaps beyond the plan's literal commands: (1) `systemctl mask`/`--runtime` cannot override a NixOS store-backed unit -- masked through `/etc/systemd/system.control/` instead, verified `LoadState=masked` for all 19 units; (2) the newly created `media/data` dataset wasn't mounted by `zfs-import-media.service` alone -- fixed with `systemctl restart zfs-mount.service`
- Ran `make switch-ser8` (persistent activation) after operator approval; confirmed the new generation (`nixos-generation-282`) as ser8's actual boot default via `/run/current-system`, `/nix/var/nix/profiles/system`, and `/boot/loader/loader.conf`, not just the deploy script's own success message
- Pushed `zfs-media-mirror` (never previously pushed to origin), opened PR #1, ran `make check` (exit 0) as the merge gate since no CI is configured on this repo, and merged to `main` -- `main` now truthfully contains the media pool declaration
- Recorded the operator's mask-durability decision for Plan 13-06 (see Next Phase Readiness) -- the live masks used in this plan do not survive a real reboot, and the operator chose to make a declarative Nix-config disable the mandatory first task of the next plan rather than accept the residual risk silently

## Task Commits

This plan produced zero repository file changes across all seven tasks (live-ops against ser8 plus a branch merge; `files_modified: []` per this plan's own frontmatter). No per-task commits were made.

1. **Task 1: Step 4.1 -- Reconfirm destructive targets** -- no commit (read-only, pre-approved per checkpoint policy)
2. **Task 2: Step 4.2 -- Unmount MergerFS and both ext4 members** -- no commit (live mount change only)
3. **Task 3: Step 4.3 gate -- Approve the irreversible disk erase** -- no commit (decision gate only)
4. **Task 4: Step 4.3 execution -- Erase and partition both approved disks** -- no commit (live-ops)
5. **Task 5: Step 4.4 -- Create and verify the empty media mirror** -- no commit (live-ops)
6. **Task 6: Step 4.5a -- Mask units, run make test-ser8** -- no commit (live-ops)
7. **Task 7: Step 4.5b -- make switch-ser8, merge to main** -- PR #1 merged to `main` via `gh pr merge`, merge commit `dec09b3` (contains prior Plans 13-02/13-03/13-04's commits, not new commits authored by this plan)

**Plan metadata:** (this commit, docs: complete plan)

## Files Created/Modified

None -- this plan's diff is entirely this SUMMARY plus STATE.md/ROADMAP.md/REQUIREMENTS.md tracking updates. All substantive work was live operations against ser8 (disk erase, pool creation, service masking, Nix activation) and a git branch merge of commits already made by Plans 13-02/13-03/13-04.

## Decisions Made

See `key-decisions` in the frontmatter for the full list. Highlights:

- Read-only Step 4.1 was pre-approved per operator policy and folded into the next checkpoint's results rather than requiring its own approval round
- Every disk-mutating step (4.2 unmount, 4.3 erase, 4.4 mirror creation, 4.5a/4.5b activation) was a mandatory human-gated stop with typed echo-backs where D-11 requires them, overriding this plan's own `gate=blocking` default per the operator's explicit plan-level policy
- `sgdisk`, missing on ser8, was resolved via an ephemeral `nix run` of the well-known `nixpkgs#gptfdisk` package (no project dependency change, no slopsquat risk) rather than treated as a Rule 3 package-install exclusion
- The `/etc/systemd/system.control/` masking mechanism and the `zfs-mount.service` restart are both genuine engineering discoveries, not workarounds around safety controls -- both are documented as reusable patterns above
- Operator explicitly chose the declarative-disable option for Plan 13-06's reboot-safety gap (see Next Phase Readiness) rather than accepting the residual risk or deferring the decision

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] sgdisk missing on ser8**
- **Found during:** Task 4 (erase and partition execution)
- **Issue:** `sudo sgdisk ...` failed with "command not found" -- no partitioning tool pre-installed on ser8
- **Fix:** Resolved via `nix run nixpkgs#gptfdisk` (fetched, but the derivation's default program isn't named `gptfdisk`, so invoked the resolved store path's `bin/sgdisk` directly). This is an ephemeral system-tool invocation against a well-known, unambiguous nixpkgs package -- not a project dependency addition, so not treated as the Rule 3 package-install exclusion
- **Files modified:** none (live-ops only)
- **Verification:** `sgdisk --version` succeeded from the resolved store path before any destructive use; both erase commands then succeeded
- **Committed in:** n/a (live-ops)

**2. [Rule 1 - Bug] Residual ext4 filesystem signature survived sgdisk --zap-all**
- **Found during:** Task 4, post-erase verification
- **Issue:** `blkid` still reported `TYPE="ext4"` on both new partitions after `sgdisk --zap-all` + new-partition creation -- `sgdisk` only clears GPT metadata, not filesystem superblocks living in the partition's data region. An incomplete erase risked `zpool create` warning or misbehaving against the residual signature
- **Fix:** `wipefs -a` on both `-part1` by-id paths before proceeding to Step 4.4
- **Files modified:** none (live-ops)
- **Verification:** `blkid` re-run afterward showed only `PTUUID`/`PTTYPE=gpt`/`PARTUUID`, no filesystem type, on both partitions
- **Committed in:** n/a (live-ops)

**3. [Rule 3 - Blocking] systemctl mask (including --runtime) cannot override a NixOS-declared unit**
- **Found during:** Task 6 (Step 4.5a)
- **Issue:** `systemctl mask --force` failed with `Read-only file system` (`/etc/systemd/system` resolves fully into read-only `/nix/store`). `systemctl mask --runtime --force` succeeded but had no effect -- `systemctl status` still showed `Loaded: loaded (/etc/systemd/system/...; enabled)`, because `/run/systemd/system` (where `--runtime` writes) is lower priority than `/etc/systemd/system` in systemd's unit search path, so the store-backed definition always wins
- **Fix:** Masked via `/etc/systemd/system.control/<unit> -> /dev/null` (a real, writable directory that sits above `/etc/systemd/system` in the search order) plus `systemctl daemon-reload`. Verified `LoadState=masked` for the probe unit before applying to all 19
- **Files modified:** none (live-ops)
- **Verification:** `systemctl show <unit> -p LoadState --value` returned `masked` for all 19 units before `make test-ser8`; remained `masked` after both `make test-ser8` and `make switch-ser8`
- **Committed in:** n/a (live-ops)

**4. [Rule 1 - Bug] media/data not mounted after make test-ser8 despite successful pool import**
- **Found during:** Task 6, post-activation verification
- **Issue:** `mount | grep /mnt/media` returned nothing after `make test-ser8` exited 0. `zfs-import-media.service` (new to this generation) ran and imported the pool, but `zfs-mount.service` -- a `oneshot`/`RemainAfterExit=true` unit whose content hadn't changed in two days -- was correctly judged by NixOS's activation script as not needing a restart, even though the brand-new `media/data` dataset now needed mounting
- **Fix:** `systemctl restart zfs-mount.service`
- **Files modified:** none (live-ops)
- **Verification:** `mount`/`findmnt`/`zfs get mounted` all confirmed `media/data` mounted at `/mnt/media` afterward
- **Committed in:** n/a (live-ops)

---

**Total deviations:** 4 auto-fixed (2 Rule 3 blocking-tool/mechanism issues, 2 Rule 1 incomplete-operation bugs). None required a package-manager dependency change, a repository file change, or an architectural decision beyond the single Rule-4-adjacent item escalated to the operator (see below).
**Impact on plan:** All four fixes were necessary for this plan's own stated acceptance criteria to hold (clean partition state before pool creation; masking actually taking effect before any Nix activation; the mount config matching the plan's exit criteria). No scope creep -- every fix stayed within the live-ops/no-repo-file-change boundary this plan's frontmatter declares.

## Issues Encountered

**Escalated rather than auto-decided (Rule 4-adjacent):** the `/etc/systemd/system.control/` masks live on `rpool/local/root`, which ser8's impermanence setup wipes to blank on every real reboot. They survive `make switch-ser8` (no reboot occurs during a switch) but would not survive an unplanned reboot during Plan 13-06's ~10.7h restore -- exactly the scenario D-16 exists to prevent, for the reboot case specifically. This was presented to the operator as an open decision at the Task 7 checkpoint (accept residual risk / declarative Nix-config disable in Plan 13-06 / separate small plan) rather than decided unilaterally, since any durable fix requires a repository change outside this plan's declared scope. The operator chose the declarative-disable option -- recorded below as mandatory scope for Plan 13-06.

No other issues beyond the four auto-fixed deviations above.

## User Setup Required

None -- no external service configuration required. All live-ops executed by the agent over SSH to `ser8` with the `bdhill` deploy user and passwordless `sudo`, plus `gh` for the PR.

## Next Phase Readiness

**Plan 13-06 (restore) can proceed, with one MANDATORY new first task per the operator's explicit decision at this plan's final checkpoint:**

> Before starting the long `zfs send`/`recv` restore, Plan 13-06's first task must add a Nix-config-level disable of the 19 freeze-set units (a repository change to `hosts/ser8/` plus an activation) so D-16's masking holds across any unplanned reboot during the ~10.7h restore window -- the live `/etc/systemd/system.control/` masks this plan applied do not survive a real reboot (ser8's impermanence wipes `rpool/local/root` on every boot). The declarative disable must only be removed (units re-enabled) at Plan 13-06's own documented service-start step, after the restore and its integrity checks are complete -- not before.

**Live state at handoff:**

- `media` zpool: ONLINE, one `mirror-0` vdev, both approved WWNs, empty (`media/data` created but contains no restored data yet)
- `backup/media-staging`: intact, gate-3.3-verified (zero unexplained differences vs the frozen source), the sole remaining copy of the media tree
- All 19 freeze-set units: masked (live, via `/etc/systemd/system.control/`) and inactive
- ser8's boot default: `nixos-generation-282`, the mirror-aware configuration, confirmed via `/run/current-system`, `/nix/var/nix/profiles/system`, and `/boot/loader/loader.conf`
- `main`: contains the media pool declaration (merge commit `dec09b3`); `zfs-media-mirror` branch preserved (not deleted) for Plan 13-06's mandatory declarative-disable work
- Original ext4 filesystems on both approved disks: permanently erased -- `backup/media-staging` is the only recovery path until restore completes

**Requirements status:** `ZFS-02` marked complete (mirror created with documented properties, mounted at `/mnt/media`). `ZFS-05` intentionally NOT marked complete -- its approval-contract clause held for every step this plan executed, but its second clause (staging destroyed only after post-cutover observation and separate approval) spans through Plan 13-07's Step 6.2.

**Rollback matrix (this plan's rows, per the plan's own `<output>` spec):**

| Point | Authoritative copy | Rollback action |
|---|---|---|
| After ext4 erase | `backup/media-staging` | Temporarily mount staging at `/mnt/media` (separately approved mountpoint change) or retry mirror creation |
| During/after this plan's activation | `backup/media-staging` | Destroy and recreate only the `media` pool after approval; masked units prevent any service from touching an empty/partial pool in the meantime |

Both original ext4 filesystems are gone permanently as of this plan -- `backup/media-staging` is the sole recovery path from this point through Plan 13-06's restore.

## Self-Check: PASSED

Live state re-verified directly (not trusted from summarized output) immediately before writing this SUMMARY: `zpool status media` ONLINE with both approved WWNs in one `mirror-0`; all 19 units `LoadState=masked`/`ActiveState=inactive`; `/mnt/media` mounted from `media/data` via ZFS; `/run/current-system` and `/boot/loader/loader.conf` both resolve to the new generation; `git log main --oneline` contains `d5529b7` and all Plan 13-02/13-03/13-04 commits after the merge.

---
*Phase: 13-zfs-mirror-migration*
*Completed: 2026-08-24*
