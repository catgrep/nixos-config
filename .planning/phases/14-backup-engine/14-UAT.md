---
status: testing
phase: 14-backup-engine
source: [14-VERIFICATION.md]
started: 2026-08-29T20:05:00Z
updated: 2026-08-30T19:40:00Z
---

## Current Test

number: 2
name: BKP-01 live pruning — time-dependent observation
expected: |
  Confirm once the 30-night window fills (~2026-09-27) that the nightly count
  holds at 30 and the oldest nightly ages out.
awaiting: time (window fills ~2026-09-27)

## Tests

### 1. BKP-06 VM restore coverage — accept or extend
expected: REQUIREMENTS.md's amended wording asks that "a VM test suite exercises the restore path across every covered service." The suite drives the generic restore path against 2 of 16 services (tests/backup-behavior.nix:149). The phase's ROADMAP Success Criterion #4 is satisfied by current evidence; the stricter requirement text is not. Decide: accept as met by substance, or require extended VM coverage first.
result: |
  decided (2026-08-29): extend. The guest's services are cheap stand-in units
  (sleep infinity) and every per-service assertion already iterates a list, so
  the fix is to derive both the stand-in units and the SERVICES list from
  hosts/ser8/backup/services.nix. Coverage then tracks the covered set
  automatically, including the irregular unit names (hass, tailscale) that are
  currently untested. BKP-06 stays open until that lands.

  closed (2026-08-30): landed. tests/backup-behavior.nix now imports
  hosts/ser8/backup/services.nix, generates a stand-in unit per entry under the
  entry's real unit name (postgresql runs for real), and derives the test
  script's service list from the same attrset — all sixteen covered services
  round-trip through backup-restore, hass and tailscaled included. The suite
  also covers the chained pipeline (single timer, wants+after completion
  barriers, the verify gate both ways, post-crash catch-up) and caught a real
  ordering bug while landing: sanoid and syncoid ship as Type=simple, so the
  chain's after= edges were launch orders, not completion barriers — both are
  now forced oneshot in policy.nix. Suite passes; guest script ≈11 min.
  BKP-06 marked complete in REQUIREMENTS.md.

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
passed: 1
issues: 0
pending: 2
skipped: 0
blocked: 0

## Gaps
