---
phase: 14-backup-engine
plan: 04
subsystem: observability
tags: [prometheus, node-exporter, alerting, smoketests, zfs, promtool]
status: complete

requires:
  - hosts/ser8/backup/verify.nix and verify.sh (from 14-03) for the metrics directory and the six series
  - hosts/ser8/backup/services.nix (from 14-02) for the declared covered-service set
  - the nightly manifest contract (from 14-03)
provides:
  - the six backup_* series served on the host's existing exporter target
  - BackupSnapshotStale, BackupReplicaStale, BackupVerifyStale alert rules
  - scripts/smoketests/backup/ as a nine-test fail-closed suite
  - the backup area on the ser8 deployment entry point
affects:
  - modules/servers/monitoring.nix
  - modules/gateway/prometheus.nix
  - scripts/smoketests/ser8/all.sh

tech-stack:
  added: []
  patterns:
    - alert expression as a disjunction of an age arm and an instance-scoped absence arm
    - covered-service set derived by evaluating services.nix as plain data rather than parsed or hardcoded
    - remote batch call returning a completion sentinel so "ran and found nothing" is distinguishable from "did not run"
    - a test that asserts its own scratch cleanup rather than assuming it

key-files:
  created:
    - scripts/smoketests/backup/all.sh
    - scripts/smoketests/backup/test-snapshot-freshness.sh
    - scripts/smoketests/backup/test-replica-freshness.sh
    - scripts/smoketests/backup/test-dataset-properties.sh
    - scripts/smoketests/backup/test-verify-last-run.sh
    - scripts/smoketests/backup/test-manifest-coverage.sh
    - scripts/smoketests/backup/test-pgdump.sh
    - scripts/smoketests/backup/test-spot-integrity.sh
    - scripts/smoketests/backup/test-metrics.sh
    - scripts/smoketests/backup/test-no-stale-persist-dirs.sh
  modified:
    - modules/servers/monitoring.nix
    - modules/gateway/prometheus.nix
    - scripts/smoketests/ser8/all.sh
  deleted: []

decisions:
  - The absence arm is scoped to the expected instance so absent() synthesises a label the summary can name
  - The replica smoketest asserts mountpoint=none rather than readonly/canmount, because nothing sets those
  - The covered-service set is evaluated from services.nix as data, not parsed and not hardcoded
  - The never-ran signal is read from the timer's last-trigger stamp, not the service's result

metrics:
  duration: ~2h
  completed: 2026-08-27

actuals:
  tokens: 24000
  tasks: 3
  commits: 3
---

# Phase 14 Plan 04: Observability and Fail-Closed Verification Summary

The engine is now visible from outside itself: the freshness metrics are served on the exporter target that already existed, three alert rules fire both when a job goes stale and when it stops reporting entirely, and a nine-test suite asserts the live outcomes no VM test can see, with every test proven to fail when its subject is absent.

## Performance

| Metric | Value |
|--------|-------|
| Tasks | 3 of 3 |
| Commits | 3 |
| Files created | 10 |
| Files modified | 3 |
| Smoketest assertions | 28 across 9 scripts |
| Alert rules added | 3 (group went from 8 rules to 11) |

## Accomplishments

- The node exporter now reads the directory the nightly verification writes to.
The textfile collector was already enabled and scraping cleanly on this host, so only the directory flag was missing; the collector list is unchanged.
- The three staleness rules are the first in the `homelab` group whose expressions are not bare thresholds, and the departure is proven rather than asserted.
Each is a disjunction of a 26-hour age arm and an explicit absence arm.
- Every one of the nine smoketests fails when the thing it inspects is missing.
This was demonstrated end to end rather than argued: a full suite run against an unreachable host returned 0 of 28 assertions passed and exit 1, with each failure naming the command that produced no output.
- The suite reaches the deploy path through the existing single entry point for the host, so `deploy.yaml` is untouched.
- The manifest test does not trust the manifest.
It reads the recorded hold position out of each dataset row and then cross-checks it against pool state, so a hold recorded on a snapshot that has since been destroyed, or on one nothing is actually holding, fails rather than reading as healthy.
- Three tests derive their subject list from `hosts/ser8/backup/services.nix` evaluated as plain data, so a service added later is checked with no edit to any test.

## Decisions Made

**The absence arm is scoped to the expected instance.**
An unscoped `absent(metric)` returns a series with no labels, so the summary annotation renders as "No fresh persist snapshot on  in over 26 hours" and the page arrives blaming nobody.
Scoping the absence arm to `instance="ser8.local:9100"` makes `absent()` synthesise that label from the matcher, so both arms produce a summary that names a host.
The age arm is deliberately left unscoped: it should cover any host that exports the series, whereas absence needs a specific subject to be absent from.

**The never-ran signal comes from the timer, not the service.**
A oneshot service that has never been started reports `Result=success`, because that is the field's default.
A test reading only the service would therefore pass on a host where the verification has never once executed, which is precisely the failure this suite exists to catch.
The timer's `LastTriggerUSec` is unset until it genuinely fires and is written to persisted storage, so it survives the reboot that resets the service's runtime state.

**The covered-service set is evaluated, not parsed.**
`services.nix` takes no arguments, so `nix eval --file` reads it directly in about 50 ms without evaluating a host configuration.
That is exact where a `grep` over Nix syntax would be approximate, and it means the tests compare against the same value the configuration uses rather than against a second reading of it.

**The suite entry point is linted with `shellcheck -x`.**
Without `-x`, a suite entry point that sources shared helpers reports SC1091 and SC2034 for `SUITE_NAME` and `TESTS`.
That is not new: the pre-existing `household/all.sh` and `ser8/all.sh` produce byte-identical output under the same invocation.
The `# shellcheck source=` directives already in these files exist so that `-x` resolves them, and under `-x` all eleven scripts are clean.

## Deviations from Plan

### 1. [Rule 1 - Bug] The replica property assertions the plan names cannot hold

**Found during:** Task 3.
**Issue:** The plan specifies the replica test asserts "deduplication off, not automatically mountable, read-only".
Nothing in the repository sets `readonly` or `canmount` on `backup/persist-replica`: the dataset is deliberately undeclared because replication must create it, the backup pool root sets neither, and `recvOptions = "u x mountpoint"` sets neither.
A test asserting `readonly=on` or `canmount=noauto` would fail against a correctly deployed host, which is the same class of broken as an always-pass test and harder to argue with once it is red.
**Fix:** The test asserts `dedup=off` and `mountpoint=none`, plus a tree-wide check that no replica dataset carries a mountpoint under `/var/lib`.
`mountpoint=none` is what the design actually relies on, is documented as such in `hosts/ser8/disko-config.nix` and `hosts/ser8/backup/policy.nix`, and is strictly stronger than `canmount=noauto` for the shadowing hazard the property exists to prevent.
The comment in the test explains why the property is checked as a value rather than as a locally set one.
**Files:** `scripts/smoketests/backup/test-dataset-properties.sh`. **Commit:** 72e499d.
Logged in `deferred-items.md` so adding `-o readonly=on` to `recvOptions` is decided in the cutover work rather than dropped.

### 2. [Rule 2 - Missing critical functionality] The new scripts were not executable

**Found during:** Task 3, before commit.
**Issue:** `run_suite` invokes each entry as `"$test" "$@"`, which needs the executable bit.
The nine tests and the entry point were created mode 644, so every one would have failed with a permission error.
Fail-closed, but for the wrong reason and with a message that says nothing about backups.
**Fix:** `chmod +x` on all ten, matching every existing smoketest in the repository.
**Files:** all ten new scripts. **Commit:** 72e499d.

### 3. [Rule 2 - Missing critical functionality] Nothing asserted the collector had parsed the file

**Found during:** Task 3.
**Issue:** The plan's metrics test checks that the six series are served and that the snapshot timestamp is fresh.
A malformed `.prom` file makes the textfile collector drop every metric in the directory while the endpoint keeps answering normally, so the six-series check alone reports it as "metrics missing" without saying why.
**Fix:** The test also requires `node_textfile_scrape_error` to be present and zero.
Its absence is itself a failure, because a missing counter means the collector is not enabled at all.
**Files:** `scripts/smoketests/backup/test-metrics.sh`. **Commit:** 72e499d.

### 4. [Rule 2 - Missing critical functionality] Assertions added beyond the nine the plan lists

Three tests grew an assertion the plan does not name, each closing a gap where the named assertion could pass over a real fault:

- **Snapshot freshness** also asserts the nightly name is present on every child dataset.
The parent holds almost none of the state; a snapshot on the parent but missing from a child is a service with no backup, and the parent's own snapshot list cannot show it.
- **Replica freshness** also asserts the replica's newest nightly name equals the source's.
Freshness alone cannot separate a replication run that delivered last night's snapshot from one that delivered the night before's and then stalled, because both sit inside the window for part of a day.
- **Stale persisted directories** also asserts each covered service's live path is a mounted dataset.
An absent leftover proves the old copy is gone; it does not prove the replacement arrived, and a plain directory on the parent dataset would satisfy the leftover check while having no granularity at all.

**Files:** `test-snapshot-freshness.sh`, `test-replica-freshness.sh`, `test-no-stale-persist-dirs.sh`. **Commit:** 72e499d.

## Red Before Green

The plan's prohibition on bare threshold expressions was carrying `status: flagged-unverified`.
It is now verified by measurement rather than by reading the expression.

A `promtool test rules` file was written covering three cases and run against the rendered rule file: an absent series must fire all three alerts, a series whose timestamp has stopped advancing must fire the age arm, and a series keeping up with wall clock must fire nothing.
All three passed.

The rule file was then mutated by stripping ` or absent(...)` from each expression, leaving exactly the bare form the twelve neighbouring rules use, and the test re-run:

```
FAILED:
  name: absent series fires all three,
  alertname: BackupSnapshotStale, time: 10m,
      exp:[ 0: Labels:{alertname="BackupSnapshotStale", instance="ser8.local:9100", severity="critical"} ],
      got:[]
```

`got:[]` is the silent failure the rules exist to prevent, reproduced on demand.
The stale and fresh cases still passed under the mutant, which is the point: the two forms are indistinguishable except in the case where the job stopped running.

The test file itself was not committed; there is no harness for Prometheus rule tests in this repository and building one is its own change.
That gap is recorded in `deferred-items.md`.

## Fail-Closed Evidence

The plan asks for a suite run before deployment, recorded as evidence the tests cannot pass on absence.
Running it against the live host was ruled out for this plan, so the stronger version was run instead: `ssh` was replaced with a stub that never connects, making every remote command return empty output.
That is exactly the "engine never ran / host unreachable" case, and unlike a run against ser8 it cannot be muddied by pre-existing state that happens to satisfy a check.

| Script | Result |
|--------|--------|
| test-snapshot-freshness.sh | 0/3 passed |
| test-replica-freshness.sh | 0/3 passed |
| test-dataset-properties.sh | 0/4 passed |
| test-verify-last-run.sh | 0/3 passed |
| test-manifest-coverage.sh | 0/4 passed |
| test-pgdump.sh | 0/3 passed |
| test-spot-integrity.sh | 0/3 passed |
| test-metrics.sh | 0/3 passed |
| test-no-stale-persist-dirs.sh | 0/2 passed |
| **suite** | **0/9 scripts passed, exit 1** |

Zero of 28 assertions passed and not one reported a skip.
Every failure named the artifact or command that produced nothing, for example `no nightly snapshot of 'rpool/safe/persist' on ser8` and `the exporter at 'http://localhost:9100/metrics' served no backup series on ser8`.

The run also confirms the covered-service derivation works: `test-dataset-properties.sh` failed at the remote property read rather than at "could not read the covered-service set", which it would have reported had the local evaluation failed.

## Verification

| Check | Result |
|-------|--------|
| Four host closures dry-build | OK |
| `statix check` | OK |
| `nixfmt --check` on both modified modules | OK |
| `shellcheck -x` on all eleven scripts | OK |
| `shfmt -d` on all eleven scripts | OK |
| `bash -n` on all ten new scripts | OK |
| `promtool check rules` on the rendered rule file | SUCCESS, 11 rules, exactly one group named `homelab` |
| Rule metric names present verbatim in `verify.sh` | 3 of 3 |
| `scrapeConfigs` length before and after | 13, unchanged |
| `enabledCollectors` before and after | unchanged |
| Exporter flag path vs the tmpfiles path | byte-identical |
| `git diff -- deploy.yaml` | empty |
| Planning terminology in `scripts/smoketests/backup` | none |

## Requirements

`BKP-01`, `BKP-03`, `BKP-04` and `BKP-07` are listed in this plan's frontmatter and **have not been marked complete**, following the precedent set in 14-01, 14-02 and 14-03.

This plan produced the instruments that will collect the evidence for those requirements, not the evidence.
All four describe properties of a running backup engine, and nothing in this phase has touched ser8 yet: no dataset exists there, no snapshot has been taken, no metric has ever been served, and the suite that would prove those requirements currently fails every one of its assertions, which is the correct result and is recorded above as such.

They become markable when the cutover deploys the engine and this suite passes against the live host.

## Known Stubs

None.

## Threat Flags

None.
The register's mitigations for T-14-16 through T-14-20 are each implemented and, where testable without a live host, tested:

- T-14-16 (an alert over an absent series): each rule is a disjunction with an explicit absence arm, the group carries a comment explaining why copying a neighbour would break it, and the mutation run above shows the bare form producing no alert.
- T-14-17 (a smoketest passing while its subject is absent): the empty-output branch precedes every branch that can pass in all 28 assertions, the shared remote helper returns empty on any failure, and the suite refuses to certify a run in which zero tests executed. The 0/28 run is the evidence.
- T-14-18 (a replica shadowing a live service path): `test-dataset-properties.sh` asserts no dataset anywhere in the replica tree carries a mountpoint under `/var/lib`, independently of the mountpoint value on the replica root.
- T-14-19 (metrics readable locally): accepted as planned. The directory is world-readable because the exporter requires it; the files carry timestamps, counts and byte totals only.
- T-14-20 (smoketests mutating the host): every check is read-only except the spot integrity scratch copy, which is removed by the same remote command that creates it, and whose removal is then asserted by a third test rather than assumed.

No new security-relevant surface was introduced. This plan adds no package, no network listener and no scrape target.

## Deferred

Two new entries in `deferred-items.md`:

- The replica is not `readonly=on`, and adding `-o readonly=on` to `recvOptions` belongs in the cutover work where the replication configuration is already being touched.
- Prometheus rule unit tests are not wired into `make check`, so nothing mechanical stops a future edit from removing an absence arm. A `checks.x86_64-linux.prometheus-rules` output running `promtool test rules` would close it.

The two pre-existing entries are unchanged. Note that the first of them, the household smoketests reading `/persist/var/lib/<service>` paths, is now directly adjacent to work in this plan: `test-no-stale-persist-dirs.sh` asserts those exact paths are gone after the cutover, so the two will contradict each other until the household tests are retargeted in the same change.

## Next Phase Readiness

The observability half of the engine is complete in declaration and unproven in operation, which is the same state as everything else in this phase.

Three things the cutover plans must carry:

- The suite currently fails every assertion, correctly. It becomes a gate only after the engine has run at least once on ser8, and specifically after the verification timer has fired once, which `test-verify-last-run.sh` requires.
- The household smoketests and `test-no-stale-persist-dirs.sh` make opposite assertions about `/persist/var/lib/<service>`. Both cannot pass at once, so the retarget must land in the cutover commit itself.
- The alert rules are on firebat and the metrics are on ser8, so the two hosts must both be deployed before the alerting path exists end to end. Deploying firebat alone arms three rules whose absence arms will fire correctly and immediately.

## Self-Check: PASSED

All ten created files exist on disk and are mode 755.
Both modified modules and the modified entry point are present in the working tree.
All three commits (f9891f3, 7fe340e, 72e499d) are present in `git log`.
