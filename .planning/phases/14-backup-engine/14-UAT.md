---
status: testing
phase: 14-backup-engine
source: [14-VERIFICATION.md]
started: 2026-08-29T20:05:00Z
updated: 2026-08-29T20:05:00Z
---

## Current Test

number: 1
name: BKP-06 VM restore coverage — accept or extend
expected: |
  A decision: accept the current evidence as sufficient (service-agnostic restore
  implementation, three real drills — Donetick from replica, Actual from source,
  Mealie in a scratch VM — plus a two-service VM proof in tests/backup-behavior.nix),
  or require the VM guest to stand up more or all sixteen covered services before
  BKP-06 is marked complete in REQUIREMENTS.md.
awaiting: user response

## Tests

### 1. BKP-06 VM restore coverage — accept or extend
expected: REQUIREMENTS.md's amended wording asks that "a VM test suite exercises the restore path across every covered service." The suite drives the generic restore path against 2 of 16 services (tests/backup-behavior.nix:149). The phase's ROADMAP Success Criterion #4 is satisfied by current evidence; the stricter requirement text is not. Decide: accept as met by substance, or require extended VM coverage first.
result: [pending]

### 2. BKP-01 live pruning — time-dependent observation
expected: The 30-night sliding window is declared and mechanism-proven in the VM suite (including the retention floor), but only ~3 nightlies exist on the live host, so live pruning has never removed anything. Nothing to check today; confirm once the window fills (~2026-09-27) that nightly count holds at 30 and the oldest nightly ages out. The staleness alerts and verification digest provide interim coverage.
result: [pending]

### 3. WR-02 fix — hold accounting on double release failure
expected: |
  The code-review fix for WR-02 (commit f014f7a) changes verify.sh's hold-release
  accounting on a branch that only runs when a dataset carries multiple stale
  last-verified holds and more than one release fails in the same pass. The fix
  records the hold position as unresolved ("-") in that case, routing operators to
  backup-restore's fail-closed default-snapshot check. Exercise the branch by hand
  (place two extra holds on a test dataset, make one release fail, run the verify
  job) or accept the VM suite's existing single-failure coverage as sufficient.
result: [pending]

## Summary

total: 3
passed: 0
issues: 0
pending: 3
skipped: 0
blocked: 0

## Gaps
