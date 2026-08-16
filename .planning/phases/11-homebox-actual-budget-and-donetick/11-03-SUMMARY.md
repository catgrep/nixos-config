---
phase: 11-homebox-actual-budget-and-donetick
plan: 03
subsystem: testing
tags: [actual, sqlite, smoketests, household, journalctl]

requires:
  - phase: 11-02
    provides: Actual Budget live on ser8 with a static actual:actual user, gateway vhost, and verified server password
provides:
  - Direct-SQL proof that exactly one unencrypted budget file exists in account.sqlite (ACT-02)
  - test-actual-service.sh and test-actual-endpoint.sh wired into the household smoketest suite
affects: [phase-11-closeout, future-actual-backup-verification]

actuals:
  tokens: 3830
  tasks: 2
  commits: 1

tech-stack:
  added: []
  patterns:
    - "journalctl --invocation=0 for no-startup-error checks instead of -b, to isolate a systemd unit's current start from earlier activations within the same uptime"

key-files:
  created:
    - scripts/smoketests/household/test-actual-service.sh
    - scripts/smoketests/household/test-actual-endpoint.sh
  modified:
    - scripts/smoketests/household/all.sh

key-decisions:
  - "Verified the budget file directly via SSH+sqlite3 before writing any test code, per the plan's resume point -- not trusting the user's 'created' report alone"
  - "Used journalctl --invocation=0 instead of -b for the no-startup-error check, deviating from the Mealie/Homebox pattern this plan mirrors, because the current boot's journal genuinely contained a pre-persist-fix mount-namespacing error from an earlier 11-02 activation that would have produced a false failure"

patterns-established:
  - "journalctl --invocation=0 scoping for startup-error smoketests on NixOS hosts that are activated without reboot -- more accurate than -b for this repo's deploy workflow"

requirements-completed: [ACT-02]

coverage:
  - id: D1
    description: "Exactly one non-deleted, unencrypted budget file exists in account.sqlite, proving ACT-02 by direct SQL query rather than trusting the checkpoint's human report"
    requirement: ACT-02
    verification:
      - kind: integration
        ref: "scripts/smoketests/household/test-actual-service.sh (actual_budget_file_unencrypted)"
        status: pass
    human_judgment: false
  - id: D2
    description: "test-actual-service.sh and test-actual-endpoint.sh added and wired into household/all.sh, both exit 0 against ser8"
    verification:
      - kind: integration
        ref: "./scripts/smoketests/household/test-actual-service.sh ser8"
        status: pass
      - kind: integration
        ref: "./scripts/smoketests/household/test-actual-endpoint.sh ser8"
        status: pass
    human_judgment: false

duration: ~20min
completed: 2026-08-21
status: complete
---

# Phase 11 Plan 03: Actual Budget -- Verify the Budget File and Add Household Smoketests Summary

ACT-02 is closed: `account.sqlite` on ser8 holds exactly one non-deleted, unencrypted budget file, proven by direct SQL query rather than trusted from the checkpoint's human report, and both new Actual smoketest scripts pass end to end.

## Performance

- **Duration:** ~20 min (this session; Task 1's checkpoint was reached in a prior session)
- **Started:** 2026-08-20 (Task 1 checkpoint reached, prior session)
- **Completed:** 2026-08-21 (Task 1 verified + Task 2 executed, this session)
- **Tasks:** 2/2
- **Files modified:** 3

## Accomplishments
- Independently verified the one budget file's encryption state by querying `account.sqlite` on ser8 directly (`SELECT count(*), group_concat(encrypt_keyid) FROM files WHERE deleted=0` returned `1|` -- one row, empty/NULL `encrypt_keyid`), closing ACT-02
- Added `test-actual-service.sh` and `test-actual-endpoint.sh`, mirroring the Mealie/Homebox household smoketest shape, and wired both into `household/all.sh`'s `TESTS` array
- Both new scripts pass against the live ser8/firebat deployment (6/6 and 4/4 tests respectively)

## Task Commits

1. **Task 1: Create the one budget file and decline end-to-end encryption** -- no commit (human-action checkpoint; the user completed the browser step in the prior session, this session independently verified it by SQL rather than trusting the report)
2. **Task 2: Verify the budget file by direct SQL query, add household smoketests** -- `57edf74` (test)

**Plan metadata:** (this commit, below)

## Files Created/Modified
- `scripts/smoketests/household/test-actual-service.sh` -- unit-active, port-listening, no-startup-error (invocation-scoped), state-directory-shape (both sides of the impermanence bind mount), and the ACT-02 budget-file count/encrypt_keyid check, guarded by `ACTUAL_ALLOW_UNSEEDED`
- `scripts/smoketests/household/test-actual-endpoint.sh` -- local `/account/needs-bootstrap` check, tsnet DNS check, tsnet HTTPS check
- `scripts/smoketests/household/all.sh` -- adds both new scripts to the `TESTS` array, after the Homebox entries

## Decisions Made
- Ran the SQL verification query on ser8 before touching any test code, per the resume point's explicit instruction not to trust the "created" report alone
- Deviated from the Mealie/Homebox no-startup-error pattern: used `journalctl -u actual --priority=err --invocation=0` instead of `journalctl -b -u actual --priority=err`. The current boot's journal genuinely contained a mount-namespacing failure from an earlier activation in 11-02 (before the tmpfiles subdirectory fix in `8da0782` landed), since ser8 has not rebooted between that fix and this verification. A boot-scoped check would have failed on stale history that has nothing to do with Actual's current health -- exactly the false positive the Mealie comment says the scoping exists to avoid, but `-b` cannot actually deliver that without a reboot between activations. `--invocation=0` scopes to the unit's current start instead and is unaffected by earlier activations in the same boot.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] journalctl -b would have produced a false failure on the no-startup-error check**
- **Found during:** Task 2, while writing `test-actual-service.sh`
- **Issue:** Mirroring `test-mealie-service.sh`'s `journalctl -b -u <unit> --priority=err` pattern verbatim would have surfaced a real but stale mount-namespacing error from an earlier `actual.service` activation in 11-02 (predating the tmpfiles subdirectory fix), because ser8 has not rebooted since. That error has no bearing on Actual's current health but would have failed this plan's own acceptance criteria (`test-actual-service.sh ser8` exits 0).
- **Fix:** Used `journalctl -u actual --priority=err --invocation=0` (systemd 245+), which scopes to the unit's current invocation rather than the whole boot.
- **Files modified:** `scripts/smoketests/household/test-actual-service.sh`
- **Verification:** Confirmed `--invocation=0` returns empty output on ser8 (systemd 260.2) while the stale `-b`-scoped error remains present in the boot-wide journal; ran the full script against ser8 and got 6/6 passing.
- **Committed in:** `57edf74`

---

**Total deviations:** 1 auto-fixed (Rule 1 - bug)
**Impact on plan:** Necessary for correctness of the smoketest itself; no scope creep. The mirrored Mealie/Homebox pattern is left unchanged for those services since neither has hit this edge case.

## Issues Encountered
None beyond the journalctl scoping issue documented above.

## User Setup Required
None -- no external service configuration required. The budget file was created by the household member in the prior session's checkpoint; this session only verified it.

## Next Phase Readiness
ACT-02 is fully closed: server password (11-02) plus exactly one unencrypted budget file (11-03), both verified programmatically rather than by report. Actual Budget's household smoketest coverage now matches Mealie's and Homebox's shape. Phase 11 can proceed to Donetick or phase closeout.

---
*Phase: 11-homebox-actual-budget-and-donetick*
*Completed: 2026-08-21*

## Self-Check: PASSED

Commit `57edf74` found in `git log`. Files `scripts/smoketests/household/test-actual-service.sh` and `scripts/smoketests/household/test-actual-endpoint.sh` present on disk and executable. `11-03-SUMMARY.md` present on disk.
