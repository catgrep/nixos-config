---
phase: 13-zfs-mirror-migration
plan: 04
subsystem: infra
tags: [zfs, rsync, sha256, systemd-run, ser8, verification, async-job]

# Dependency graph
requires:
  - phase: 13-zfs-mirror-migration
    provides: "Frozen source tree and a fully staged, structurally-matched copy at backup/media-staging (Plan 13-03)"
provides:
  - "scripts/sampled-verify.sh: a reusable, locally self-tested D-07 sampled + metadata verification tool (head + tail + one sample per GiB for files >=1 MiB, full sha256 for files <1 MiB, plus a 100%-coverage metadata-only rsync dry run)"
  - "Gate 3.3 PASS: zero unexplained differences between the frozen /mnt/media source and backup/media-staging on ser8, independently confirmed against the manifest file content (not systemctl's exit status alone)"
  - "ZFS-01 fully satisfied across Plans 13-01/13-03/13-04 (SMART gate, staged copy, checksum-verified final sync)"
affects: [13-05-cutover, 13-06-restore, 13-07-cleanup]

# Actuals (#2632)
actuals:
  tokens: 3800
  tasks: 2
  commits: 4

# Tech tracking
tech-stack:
  added: []
  patterns: [1-mib-block-index-sampling-not-byte-offset-division, external-job-manifest-for-medium-duration-checks, systemd-run-explicit-path-setenv]

key-files:
  created:
    - scripts/sampled-verify.sh
    - scripts/sampled-verify.test.sh
    - .planning/async-jobs/gate-3.3-sampled-verify.json
    - .planning/phases/13-zfs-mirror-migration/evidence/gate-3.3-result.md
  modified: []

key-decisions:
  - "Task 2's checkpoint:decision (gate=blocking) was auto-approved rather than stopped on: its own <context> states the mutation class is read-only against both trees (writes only the manifest file), which this phase's operator checkpoint policy pre-approves"
  - "Because the estimated ~21 min runtime exceeds this phase's 10-minute foreground threshold, gate 3.3 was dispatched as a detached systemd-run transient unit and the session returned rather than polling to completion, per explicit checkpoint-policy instruction -- following the external-job-manifest convention Plan 13-03 established, recorded at .planning/async-jobs/ rather than the core capability's default .planning/ns/ path, matching this repo's own precedent"
  - "Fixed the offset arithmetic in the plan's literal dd-skip formula: computing sample points directly in 1-MiB-block-index space (rather than raw byte offsets later divided by 1 MiB) so the head and tail samples always land on a file's true first and last bytes regardless of whether its size is a multiple of 1 MiB -- required for Test 2's acceptance criterion (a last-byte-only diff in a large file must be caught by the tail sample) to hold for arbitrary file sizes"
  - "The terminal async-job status was left as 'completed-unverified' (matching the enum precedent from 13-03, which has no separate 'verified' state) even though this plan's own manual step then independently re-read the manifest file content over SSH and confirmed the PASS -- the evidence file and this SUMMARY are the actual closure record, per the same convention"
  - "ZFS-01 marked complete: all three of its clauses (SMART health gate, staged copy, checksum-verified final sync reporting zero unexplained differences) are now satisfied across Plans 13-01/13-03/13-04"

patterns-established:
  - "Sample point computation in block-index space, not byte-offset space, avoids a rounding bug where dd's 'skip = offset / block_size' truncation can leave the tail sample short of a file's actual last bytes for non-block-aligned file sizes"

requirements-completed: [ZFS-01]

coverage:
  - id: D1
    description: "scripts/sampled-verify.sh implements the D-07 sampling algorithm (head/tail/per-GiB sampling for files >=1 MiB, full hash for files <1 MiB, 100%-coverage metadata dry run) and passes all five local self-test cases"
    requirement: "ZFS-01"
    verification:
      - kind: unit
        ref: "scripts/sampled-verify.test.sh (5/5 cases pass: identical trees, large-file tail mismatch, small-file mismatch, metadata-only mismatch, empty trees)"
        status: pass
      - kind: other
        ref: "shellcheck scripts/sampled-verify.sh scripts/sampled-verify.test.sh; shfmt -i 0 -d scripts/sampled-verify.sh scripts/sampled-verify.test.sh -- both zero issues"
        status: pass
    human_judgment: false
  - id: D2
    description: "Gate 3.3 runs against the real 5.7 TB /mnt/media vs /mnt/media-staging tree on ser8 and reports zero unexplained differences (ZFS-01's checksum-verified final sync clause)"
    requirement: "ZFS-01"
    verification:
      - kind: manual_procedural
        ref: "ssh bdhill@192.168.68.65 'systemctl show gate-33-sampled-verify -p ActiveState,SubState,Result,ExecMainStatus --value' (inactive/dead/success/0) and 'sudo cat /persist/zfs-migration/gate-3.3-manifest.txt' (PASS -- 3478 files sampled, 0 differences), both independently re-checked after the coordinator's terminal-state report"
        status: pass
    human_judgment: false

duration: ~18min (~10min active engineering + ~8.5min unattended sampled-verify run on ser8, tracked via the async-job manifest rather than polling)
completed: 2026-08-24
status: complete
---

# Phase 13 Plan 04: Sampled + Metadata Staging Verification Summary

**scripts/sampled-verify.sh (D-07 head/tail/per-GiB sampled hashing + 100%-coverage metadata dry run) passes all five local self-tests and gate 3.3's real run against the 5.7 TB media tree on ser8 reports zero unexplained differences -- clearing Plan 13-05's disk erase**

## Performance

- **Duration:** ~18 min (~10 min active engineering across both tasks; ~8.5 min unattended `sampled-verify.sh` run on ser8, dispatched as a detached `systemd-run` unit and tracked via `.planning/async-jobs/gate-3.3-sampled-verify.json` rather than polled)
- **Started:** ~2026-08-24T18:12:37Z
- **Gate 3.3 dispatched:** 2026-08-24T18:20:54Z
- **Gate 3.3 completed:** 2026-08-24T18:29:22Z
- **Tasks:** 2/2
- **Files modified:** 4 (all created)

## Accomplishments

- Wrote `scripts/sampled-verify.sh` implementing D-07's sampling algorithm: full sha256 comparison for files under 1 MiB, and for files 1 MiB and larger, deterministic sampling at head + tail + roughly one sample per GiB, computed in 1-MiB-block-index space so the tail sample always covers a file's true final bytes regardless of file-size alignment. Paired with a 100%-coverage metadata-only `rsync -aHAXn --itemize-changes` dry run (size/mtime/mode/uid/gid/type/symlink-target/hardlink-grouping/ACL/xattr). Exit status is derived exclusively from whether either pass produced non-empty output -- never from a sub-command's own exit code.
- Wrote `scripts/sampled-verify.test.sh`, a companion self-test harness using local `mktemp -d` fixtures (no network/SSH), covering all five required behavior cases: identical trees (pass), large-file last-byte mismatch caught by the tail sample, small-file mismatch caught by full hash, metadata-only mismatch (differing mode) caught by the rsync dry run even with identical content, and empty source/destination trees (pass, not an error). All 5/5 pass; `shellcheck` and `shfmt -d` report zero issues on both files.
- Task 2's checkpoint (read-only mutation class per its own `<context>`) was auto-approved per this phase's operator checkpoint policy. Copied the script to `ser8` and dispatched gate 3.3 as a detached `systemd-run --unit=gate-33-sampled-verify` transient unit against the real `/mnt/media` (frozen source) vs `/mnt/media-staging`. Since the estimated ~21 min runtime exceeds the phase's 10-minute foreground threshold, the session returned rather than polling, recording the dispatch in `.planning/async-jobs/gate-3.3-sampled-verify.json`.
- The coordinator reported the job's terminal state; independently re-verified over SSH rather than trusting the report at face value -- `systemctl show` confirmed `Result=success`/`ExecMainStatus=0`, and `/persist/zfs-migration/gate-3.3-manifest.txt` was read directly, showing `PASS -- 3478 files sampled, 0 differences`. All 3,478 regular files in the source inventory (matching the Plan 13-01 preflight manifest and the Plan 13-03 structural count) entered the content-sampling pass -- 100% file-level coverage, though not 100% byte-level coverage for files >=1 MiB (D-07's explicit, STRIDE-accepted sampling tradeoff). Recorded the PASS in `.planning/phases/13-zfs-mirror-migration/evidence/gate-3.3-result.md` and updated the async-job manifest to `completed-unverified` (this repo's terminal-status enum has no separate "verified" state) with the confirmed manifest content in `terminal_details`.

## Task Commits

1. **Task 1: Write scripts/sampled-verify.sh with local self-tests (D-07)** -- `8f6741c` (test)
2. **Task 2: Run gate 3.3: sampled verification of staging vs the frozen source** -- `9cfd239` (docs: dispatch + async-job manifest), `7f21a8e` (docs: PASS result evidence), `3dd5f2f` (docs: async-job manifest marked terminal)

**Plan metadata:** (this commit, docs: complete plan)

## Files Created/Modified

- `scripts/sampled-verify.sh` -- new; D-07 sampled + metadata verification tool
- `scripts/sampled-verify.test.sh` -- new; five-case local self-test harness
- `.planning/async-jobs/gate-3.3-sampled-verify.json` -- new; external-job manifest tracking the `gate-33-sampled-verify` `systemd-run` unit from dispatch (`running`) through independently-verified completion (`completed-unverified`, `terminal_details.gate_result: PASS`)
- `.planning/phases/13-zfs-mirror-migration/evidence/gate-3.3-result.md` -- new; gate 3.3 PASS evidence record

## Decisions Made

- Auto-approved Task 2's `checkpoint:decision` (gate=blocking) rather than stopping on it: its own `<context>` states the mutation class is read-only against both trees, which this phase's operator checkpoint policy explicitly pre-approves ("Approval should only be for running commands on ser8 for data migration... not code / doc changes" combined with the read-only/diagnostic carve-out)
- Dispatched gate 3.3 as a detached `systemd-run` unit and returned rather than polling, since the ~21 min estimated runtime exceeds this phase's 10-minute foreground threshold -- reused the `external-job-manifest` convention Plan 13-03 established for `media-staging-rsync`, at `.planning/async-jobs/` (this repo's own precedent) rather than the core capability's default `.planning/ns/` path
- Computed the D-07 sample points in 1-MiB-block-index space rather than literal byte-offset-then-divide arithmetic: the plan's action text describes `dd skip=$((offset / 1048576))`, which for a non-block-aligned file size can leave the "tail" sample's read range short of the file's actual last bytes (verified by hand: a 2,000,000-byte file's naive tail offset of 951,424 floors to block 0, i.e. bytes `[0, 1048576)`, entirely missing the last byte at offset 1,999,999). Fixed as a Rule 1 bug so Test 2's acceptance criterion (a last-byte-only diff in a large file must be caught by the tail sample) holds for arbitrary file sizes, not just block-aligned ones.
- Independently re-verified the coordinator's terminal-state report rather than trusting it directly: re-ran `systemctl show` and read the manifest file content itself over SSH before writing the PASS evidence record, consistent with this plan's own prohibition against trusting a summary of the gate rather than the manifest content.
- Marked `ZFS-01` complete: all three of its clauses (SMART health gate from 13-01, staged copy from 13-03, checksum-verified final sync reporting zero unexplained differences from this plan) are now satisfied.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed tail-sample offset arithmetic to use 1-MiB-block-index space**
- **Found during:** Task 1, while implementing the sampling algorithm and designing the local self-tests
- **Issue:** The plan's action text specifies `dd if="$file" bs=1M skip=$((offset / 1048576)) count=1`, with the tail offset defined as `size - 1048576`. For file sizes that are not exact multiples of 1 MiB, `floor((size - 1048576) / 1048576)` can select a block well before the file's actual end -- e.g. for a 2,000,000-byte file, the naive tail offset (951,424) floors to block 0 (`[0, 1048576)`), never reading the file's last byte at offset 1,999,999. This would make Test 2's required acceptance case (a last-byte-only diff caught by the tail sample) fail for most real-world file sizes.
- **Fix:** Compute `total_blocks = ceil(size / one_mib)` and `last_block = total_blocks - 1` directly, and derive the per-GiB sample points as block indices (`i * total_blocks / sample_points`) rather than byte offsets later divided down. The tail sample is now always `dd ... skip=$last_block count=1`, which reads through to the file's true end regardless of alignment.
- **Files modified:** `scripts/sampled-verify.sh`
- **Verification:** `scripts/sampled-verify.test.sh` Test 2 (2,000,000-byte file, last byte flipped in the destination copy) exits 1 and names the differing file, confirmed by direct arithmetic trace and by running the test suite (5/5 pass)
- **Committed in:** `8f6741c` (Task 1 commit)

**2. [Rule 3 - Blocking] Fixed missing coreutils in systemd-run's default PATH**
- **Found during:** Task 2, first dispatch of gate 3.3 on ser8
- **Issue:** `sudo systemd-run --unit=gate-33-sampled-verify -- bash /persist/zfs-migration/sampled-verify.sh ...` failed immediately with exit 127 ("mktemp: command not found"). `systemd-run`'s default minimal unit environment does not include `/run/current-system/sw/bin`, where ser8's NixOS-provided coreutils (`mktemp`, `dd`, `sha256sum`, `find`, `stat`, `rsync`, etc.) live -- unlike Plan 13-03's `media-staging-rsync` unit, which invoked `rsync` directly with no shell script wrapper and so never needed those tools resolved via `$PATH`.
- **Fix:** Re-dispatched with `--setenv=PATH=/run/wrappers/bin:/run/current-system/sw/bin`, matching root's normal interactive-login `$PATH` on ser8 (minus the per-profile entries that a script run under `systemd-run` doesn't need).
- **Files modified:** none (live-ops dispatch command only; the failed unit was reset via `systemctl reset-failed` before re-dispatch)
- **Verification:** `systemctl show gate-33-sampled-verify -p ActiveState,SubState --value` returned `active`/`running` with accumulating CPU time before the async-job manifest was committed; the unit later reached a clean terminal state (`Result=success`, `ExecMainStatus=0`)
- **Committed in:** `9cfd239` (documented in the async-job manifest's `notes` field; the dispatch command itself is a live-ops action with no separate repo commit)

---

**Total deviations:** 2 auto-fixed (1 Rule 1 correctness bug in the sampling arithmetic, 1 Rule 3 blocking environment issue on the first dispatch attempt)
**Impact on plan:** Both fixes were necessary for the plan's stated acceptance criteria to hold (Test 2's tail-sample case; gate 3.3 running at all). No scope creep -- neither fix touched anything outside `scripts/sampled-verify.sh`'s own algorithm or the live dispatch command.

## Issues Encountered

None beyond the two auto-fixed deviations above.

## User Setup Required

None -- no external service configuration required. All commands executed by the agent over SSH to `ser8` with the `bdhill` deploy user and passwordless `sudo`.

## Next Phase Readiness

Plan 13-05 (destructive cutover) can proceed: gate 3.3 reports zero unexplained differences between the frozen `/mnt/media` source and `backup/media-staging`, independently confirmed against the manifest file content on ser8 (never trusting `systemctl`'s exit status or a summarized report alone, per this plan's own prohibitions). `ZFS-01` is now fully satisfied.

**Outage window status:** the application stack remains **stopped** (all 18 freeze-set units, since Plan 13-03's Task 1) -- unchanged by this plan, which performed only read-only checks against the frozen source and staging. Services stay down through Plan 13-05's destructive cutover and Plan 13-06's restore, resuming only in Plan 13-07 after post-restore application tests and the first scrub.

**Rollback matrix (this plan's row, per the plan's `<output>` spec):**

| Point | Authoritative copy | Rollback action |
|---|---|---|
| After service freeze but before erase | Original ext4 plus verified staging | Remount or keep MergerFS and restart services |

Both the original ext4 + MergerFS media tree and the now-verified `backup/media-staging` copy remain valid rollback targets at this point -- nothing in this plan is irreversible. Plan 13-05's disk erase is the first irreversible step in the migration.

## Self-Check: PASSED

`scripts/sampled-verify.sh`, `scripts/sampled-verify.test.sh`, `.planning/async-jobs/gate-3.3-sampled-verify.json`, and `.planning/phases/13-zfs-mirror-migration/evidence/gate-3.3-result.md` all confirmed present; commits `8f6741c`, `9cfd239`, `7f21a8e`, `3dd5f2f` confirmed in `git log`.

---
*Phase: 13-zfs-mirror-migration*
*Completed: 2026-08-24*
