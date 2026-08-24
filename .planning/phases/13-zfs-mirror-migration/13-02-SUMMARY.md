---
phase: 13-zfs-mirror-migration
plan: 02
subsystem: infra
tags: [zfs, disko, mergerfs, ser8, smoketest, feature-branch]

# Dependency graph
requires:
  - phase: 13-zfs-mirror-migration
    provides: "Truthful migration doc (D-01), SMART-healthy disk evidence, and a frozen source-inventory baseline from Plan 13-01"
provides:
  - "The zfs-media-mirror feature branch declaring the media zpool mirror and its smoketest, validated by a clean make build-ser8, ready for Plan 13-03 to build on"
affects: [13-03-freeze-and-staging-copy, 13-04-staging-verification, 13-05-cutover, 13-06-restore, 13-07-cleanup]

# Actuals (#2632)
actuals:
  tokens: 2940
  tasks: 3
  commits: 2

# Tech tracking
tech-stack:
  added: []
  patterns: [disko-zfs-mirror-pool-declaration, remote-sh-c-wrapping-for-shell-metacharacters]

key-files:
  created:
    - scripts/smoketests/media/test-zfs-media.sh
  modified:
    - hosts/ser8/disko-config.nix
    - hosts/ser8/configuration.nix
    - scripts/smoketests/media/all.sh
    - .planning/REQUIREMENTS.md
    - .planning/ROADMAP.md

key-decisions:
  - "Both checkpoint:decision tasks (Step 1.1 branch/declare, Step 1.2 validate) auto-approved per the operator's explicit checkpoint policy for this phase: both are repository-writing/build-only mutations, no live ser8 state touched"
  - "impermanence.nix reviewed and left unchanged per the plan's explicit allowance: the existing /mnt/media tmpfiles rules only fix ownership/permissions after mount and do not conflict with a ZFS-native mountpoint"
  - "Task 2 (tdd=\"true\") implemented directly rather than via a literal RED/GREEN cycle: the deliverable IS the smoketest itself (not application code under test), and the plan's own Task 3 explicitly forbids exercising it against live ser8 in this plan -- there is no live mirror yet to run it against"
  - "Corrected the stale 'cross-directory hardlink' wording in REQUIREMENTS.md ZFS-04 and ROADMAP.md Phase 13 criterion 4 to 'import-write ownership check', per D-22's note that this rewording should ride with the requirement edits -- it was missed in Plan 13-01"
  - "Did not mark ZFS-02/ZFS-04 complete in REQUIREMENTS.md: both describe live-state outcomes ('reformatted', 'active configuration', 'full media stack runs healthy') that only exist after Plan 13-05's cutover, not after this repo-only declaration"

patterns-established:
  - "remote() in smoketests %q-escapes each argument individually before joining into one ssh command string -- shell metacharacters like && and () must be wrapped in `sh -c '...'` (single-quoted, one argument) rather than passed as bare tokens, or they arrive on the remote end as literal characters, not operators"

requirements-completed: []

coverage:
  - id: D1
    description: "hosts/ser8/disko-config.nix declares zpool `media` as a two-disk mirror using exactly the two approved WWNs, with dataset `data` mounted at /mnt/media"
    requirement: "ZFS-02"
    verification:
      - kind: other
        ref: "grep -c '\"media\"' hosts/ser8/disko-config.nix (2 matches: disk pool assignment + zpool block) and make build-ser8 exit 0"
        status: pass
    human_judgment: false
  - id: D2
    description: "hosts/ser8/configuration.nix no longer declares fileSystems.\"/mnt/media\" as fuse.mergerfs; boot.zfs.extraPools includes \"media\" alongside \"backup\"; mergerfs/mergerfs-tools removed from environment.systemPackages"
    requirement: "ZFS-04"
    verification:
      - kind: other
        ref: "grep -n 'fuse.mergerfs\\|mergerfs' hosts/ser8/configuration.nix (zero matches) and grep -n extraPools hosts/ser8/configuration.nix"
        status: pass
    human_judgment: false
  - id: D3
    description: "scripts/smoketests/media/test-zfs-media.sh exists, is dispatched from scripts/smoketests/media/all.sh, implements the six behavior-spec checks (mount type, pool health, mirror membership, canonical directories, service access, import-write), and passes shellcheck/shfmt -d with zero non-baseline issues"
    requirement: "ZFS-04"
    verification:
      - kind: other
        ref: "shellcheck scripts/smoketests/media/test-zfs-media.sh scripts/smoketests/media/all.sh (exit 0, only baseline SC1091 info matching the test-zfs-health.sh analog) and shfmt -d (no diff)"
        status: pass
    human_judgment: false
  - id: D4
    description: "make build-ser8 succeeds against the new declaration on the zfs-media-mirror branch without activating anything; main remains untouched"
    verification:
      - kind: other
        ref: "make build-ser8 exit 0, produced /nix/store/z84d7dhaf320dv0rq8ajrxrs87aw29pq-nixos-system-ser8-26.05.20260817.0dd31db; git show main:hosts/ser8/configuration.nix still has 3 mergerfs references"
        status: pass
    human_judgment: false

duration: ~20min
completed: 2026-08-24
status: complete
---

# Phase 13 Plan 02: Repository Storage Declaration Summary

**`zfs-media-mirror` branch declares the media zpool mirror (disko + boot config), removes MergerFS entirely, and ships a six-check pool-health smoketest -- validated by a clean `make build-ser8` with zero live ser8 state changed**

## Performance

- **Duration:** ~20 min
- **Started:** 2026-08-24T07:11:00Z
- **Completed:** 2026-08-24T07:31:00Z
- **Tasks:** 3/3
- **Files modified:** 5 (2 repo config, 1 new smoketest, 1 smoketest dispatcher, 2 planning docs)

## Accomplishments

- Created the `zfs-media-mirror` feature branch (D-15) and declared the `media` zpool as a two-disk mirror in `hosts/ser8/disko-config.nix`, preserving both approved WWNs (`wwn-0x5000c500b56ea81a`, `wwn-0x5000c500b3733a87`) exactly, with a single `data` dataset (lz4 compression, 1M recordsize, no auto-snapshot) mounted at `/mnt/media`
- Removed MergerFS entirely from `hosts/ser8/configuration.nix`: the `fuse.mergerfs` fileSystems entry, the `mergerfs`/`mergerfs-tools` packages, and added `"media"` to `boot.zfs.extraPools`
- Reviewed `hosts/ser8/impermanence.nix`'s existing `/mnt/media` tmpfiles rules and confirmed no conflict with a ZFS-native mount -- left unchanged, as the plan anticipated
- Wrote `scripts/smoketests/media/test-zfs-media.sh` (D-19) implementing all six behavior-spec checks: mount type (ZFS not fuse.mergerfs), pool health, mirror membership by exact WWN, canonical library directories, media-group read access, and an import-write ownership check (D-22, replacing the old cross-directory hardlink test now that torrents are retired) -- wired into `scripts/smoketests/media/all.sh`
- Found and fixed a real bug during Task 2's own shellcheck/verification pass: `remote()` reconstructs each argument as an independent shell word via `printf %q`, so bare `&&`/`()` tokens arrive on the remote end as literal characters rather than shell operators -- fixed by wrapping conditionals in a single `sh -c '...'` argument (see Deviations)
- `make fmt` (no diff), `statix check` (zero warnings), and `make build-ser8` (exit 0, new store path built) all pass on the branch; `main` is untouched

## Task Commits

Each task was committed atomically:

1. **Step 1.1: Create feature branch, declare media zpool, remove MergerFS** - `d5529b7` (feat)
2. **Write test-zfs-media.sh, wire into media/all.sh (D-19)** - `624162f` (test)
3. **Step 1.2: Validate the repository change without activation** - no new commit (validation-only task; `make fmt`/`statix check`/`make build-ser8`/`shellcheck` all ran clean against the two commits already made in Tasks 1-2, nothing left to stage)

**Plan metadata:** (this commit, docs: complete plan)

## Files Created/Modified

- `hosts/ser8/disko-config.nix` - `media-disk1`/`media-disk2` now ZFS members of pool `media` (mirror mode); new `zpool.media` block with `data` dataset
- `hosts/ser8/configuration.nix` - `extraPools` gains `"media"`; `fuse.mergerfs` fileSystems entry and mergerfs packages removed
- `scripts/smoketests/media/test-zfs-media.sh` - new; six-check ZFS media pool smoketest
- `scripts/smoketests/media/all.sh` - dispatches the new smoketest after the Bazarr-access check
- `.planning/REQUIREMENTS.md` - ZFS-04 wording corrected (hardlink -> import-write) per D-22
- `.planning/ROADMAP.md` - Phase 13 criterion 4 wording corrected to match

## Decisions Made

- Both checkpoint:decision tasks auto-approved per the operator's explicit checkpoint policy for this phase (repository-only / build-only mutations, no live ser8 state touched) -- see Deviations for the specific note on each
- `impermanence.nix` left unchanged after review: existing tmpfiles rules only fix ownership after mount, no conflict with ZFS-native mounting
- Task 2's `tdd="true"` tag applied to a smoketest script whose deliverable IS the test itself, with no live mirror to exercise it against in this plan -- implemented directly per the plan's `<action>` rather than forcing an artificial RED/GREEN split
- Corrected the stale "cross-directory hardlink" wording in REQUIREMENTS.md (ZFS-04) and ROADMAP.md (Phase 13 criterion 4) to "import-write ownership check", closing a gap D-22 flagged for Plan 13-01 but that plan didn't complete
- ZFS-02/ZFS-04 requirements NOT marked complete: both describe live-state outcomes that only exist after Plan 13-05's cutover actually reformats the disks and switches the running configuration

## Deviations from Plan

### Auto-approved Checkpoints (per operator's explicit phase policy, not a plan deviation)

**1. Step 1.1 (checkpoint:decision, gate="blocking") -- auto-approved**
- Mutation class: repository-writing only (branch creation + disko/config declaration), no live ser8 state touched
- Per the operator's stated policy for this phase: "Checkpoints whose mutation class is repository-only ... treat as PRE-APPROVED"
- Proceeded directly to creating the branch and writing the declaration

**2. Step 1.2 (checkpoint:decision, gate="blocking") -- auto-approved**
- Mutation class: build/eval only (`make fmt`, `statix check`, `make build-ser8`, `shellcheck`) -- explicitly forbidden from running `make test-ser8`/`make switch-ser8` per the task's own action text
- Auto-approved per the same policy; validation ran and passed cleanly

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed shell-metacharacter mishandling in remote() usage**
- **Found during:** Task 2 (writing test-zfs-media.sh), while verifying my own draft against shellcheck/manual reconstruction before committing
- **Issue:** `remote()` builds its ssh command by `printf %q`-escaping each argument individually, then space-joining. Passing bare `&&` or `()` as separate arguments to `remote` causes them to arrive on the remote shell as literal `\&\&`/`\(`/`\)` tokens -- i.e. ordinary characters, not shell operators -- which broke a draft of the canonical-directories check (`test` received extra literal arguments and errored "too many arguments")
- **Fix:** Wrapped the conditional in a single `sh -c '...'` argument (one %q-escaped token containing the full mini-script), matching the pattern the plan's own action text already used for the import-write test. Verified the fix by hand-reconstructing the escaped command locally against a scratch directory before trusting it against ser8
- **Files modified:** scripts/smoketests/media/test-zfs-media.sh
- **Verification:** Local reconstruction test (`bash -c "$test_cmd"`) confirmed correct behavior; shellcheck/shfmt clean
- **Committed in:** 624162f (Task 2 commit)

**2. [Rule 2 - Missing Critical] Corrected stale requirement/roadmap wording left over from Plan 13-01**
- **Found during:** Writing this SUMMARY, cross-checking ZFS-04's text against what Task 2 actually built
- **Issue:** REQUIREMENTS.md ZFS-04 and ROADMAP.md Phase 13 criterion 4 both still said "a cross-directory hardlink" smoketest, which D-22 explicitly retired in favor of the import-write test -- D-22 noted "rewording rides with D-04's requirement edits" but Plan 13-01 only reworded ZFS-01/ZFS-03, missing ZFS-04
- **Fix:** Reworded both to "import-write ownership check", matching what Task 2 actually implemented
- **Files modified:** .planning/REQUIREMENTS.md, .planning/ROADMAP.md
- **Verification:** Grepped both files post-edit to confirm no remaining "cross-directory hardlink" reference tied to Phase 13's storage smoketest (the unrelated Phase 15/Nixflix criterion about a live usenet import hardlink was left untouched -- different concern, different phase)
- **Committed in:** (this plan's metadata commit)

---

**Total deviations:** 2 auto-fixed (1 bug, 1 missing-critical/doc-consistency), plus 2 auto-approved checkpoints per operator policy
**Impact on plan:** The remote() escaping fix was necessary for the smoketest to actually work against a real host; without it, the canonical-directories check would have failed every run regardless of pool state. The requirement-wording fix closes a gap from the prior plan with no functional impact. No scope creep beyond what Task 2's own deliverable required.

## Issues Encountered

None beyond the auto-fixed items above.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

Plan 13-03 (staging and initial copy) can proceed. It must `git checkout zfs-media-mirror` (not `main`) before doing any repository work, since `main` intentionally still describes the pre-migration MergerFS configuration until Plan 13-05's cutover succeeds and the branch merges (per D-15). The branch currently contains two commits (`d5529b7` disko/config declaration, `624162f` smoketest) on top of `main`'s `13-01` completion commit, plus this plan's SUMMARY/state-tracking commit. No blockers for Plan 13-03.

**Rollback matrix:** unchanged from the "Before Step 3.1" row in `.planning/SER8-ZFS-MIRROR-MIGRATION.md` -- this plan touched only the git repository (a new branch and its commits), no live ser8 state. Reverting is `git branch -D zfs-media-mirror` on any clone that hasn't pulled it, or reverting the two commits on the branch itself; `main` was never touched.

## Self-Check: PASSED

All 7 created/modified files confirmed present on disk; all 3 commits (`d5529b7`, `624162f`, `fcdddd3`) confirmed in git log.

---
*Phase: 13-zfs-mirror-migration*
*Completed: 2026-08-24*
