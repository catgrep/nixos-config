---
phase: 14-backup-engine
verified: 2026-08-29T19:55:00Z
status: human_needed
score: 4/4 roadmap success criteria verified; 6/7 requirements fully satisfied, 1 partially satisfied
behavior_unverified: 0
overrides_applied: 0
gaps: []
human_verification:
  - test: "Decide whether BKP-06's second clause (\"a VM test suite exercises the restore path across every covered service\") is accepted as met by the current VM suite, which exercises the generic restore path against 2 of 16 covered services (donetick, mealie in tests/backup-behavior.nix:149,720-731), with the remaining 14 covered only by the live-host smoketest suite and three real drills (Donetick, Actual, Mealie)."
    expected: "A decision: accept the current evidence as sufficient (service-agnostic implementation + 3 real drills + 2-service VM proof), or require the VM guest to stand up more/all covered services before BKP-06 is marked complete in REQUIREMENTS.md."
    why_human: "This is a scope/risk-tolerance judgment already flagged as open by REQUIREMENTS.md itself (BKP-06 checkbox unchecked, traceability status 'Pending'), not a defect grep can resolve. The Phase 14 ROADMAP.md Success Criterion #4 (the phase's authoritative completion bar) is satisfied by the current evidence; REQUIREMENTS.md's amended, stricter wording is not."
  - test: "Decide whether BKP-01's pruning clause (\"pruned to a 30-night sliding window\") is accepted as met on the strength of the mechanism (two dedicated VM assertions including the floor case) given that only three nightlies exist on the live host, so live pruning has not yet had occasion to remove anything."
    expected: "A decision: accept mechanism-level proof as sufficient, or hold this open until 30+ nightlies have accumulated on ser8 and a live prune can be observed."
    why_human: "Time-dependent; nothing to inspect yet on the live host. The policy (hosts/ser8/backup/policy.nix:36-39) declares daily=30 correctly and sanoid's autoprune is enabled; the gap is purely elapsed time, already disclosed in 14-06-SUMMARY.md."
---

# Phase 14: Backup Engine Verification Report

**Phase Goal:** Every stateful service on ser8 is protected by nightly atomic ZFS snapshots of persisted state, replicated to the backup pool, with generic integrity verification and a demonstrated, working restore path.
**Verified:** 2026-08-29T19:55:00Z
**Status:** human_needed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths (ROADMAP.md Success Criteria — the authoritative phase-completion contract)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Nightly atomic ZFS snapshots cover all persisted service state on ser8, replicated to a dedup-off dataset on the backup pool, pruned to a 30-night sliding window by an established policy tool | ✓ VERIFIED | Live `ser8`: `rpool/safe/persist` and all 16 children carry the identical snapshot name `autosnap_2026-08-29_18:00:03_daily` (one transaction group). `backup/persist-replica` and all 16 children exist, `dedup=off`, `mountpoint=none`, `mounted=no`. `hosts/ser8/backup/policy.nix:36-39` declares sanoid `daily = 30` with `autoprune = true`. Live smoketest `test-snapshot-freshness.sh` and `test-replica-freshness.sh` independently re-run by the verifier: 6/6 pass. |
| 2 | A generic nightly job captures `pg_dump -Fc` of every discovered PostgreSQL database before the snapshot and verifies the new snapshot afterward (`PRAGMA integrity_check`/`quick_check`, `pg_restore --list`), emitting a manifest and digest; staleness alerting on firebat fires within 26h of a missed run including an absent metric series | ✓ VERIFIED | `hosts/ser8/backup/dump.sh:69` discovers databases via `select datname from pg_database where not datistemplate and datallowconn` — no hardcoded list. Live manifest (`/persist/var/lib/backup-manifests/latest.tsv`, re-read by the verifier) shows 153 rows for tonight's run, `#status=ok`, both `mealie.dump` and `postgres.dump` present and pg_restore-listable. Verification correctly distinguishes real SQLite files from 101 non-database `*.db`-named files (Frigate's Mesa shader cache, `mosquitto.db`) by content header, all clean. `modules/gateway/alertmanager.nix` deployed on firebat, live and registered with Prometheus (`activeAlertmanagers` non-empty); independently re-run `test-alertmanager.sh`: 4/4 pass; `alertmanager_notifications_total{integration="email"}=3`, `alertmanager_notifications_failed_total=0` for every reason. |
| 3 | A Mealie restore into a scratch VM has been performed and documented using the parameterized restore tool | ✓ VERIFIED | `14-06-SUMMARY.md` records the drill with exact commands and output: scratch VM importing the real `hosts/ser8/backup/restore.nix` and `modules/household/mealie.nix`, pinned to matching Mealie/PostgreSQL versions, `backup-restore mealie --force --pg-database mealie` executed, API returned real recipes, image byte-identical (SHA-256 matched) to the snapshot copy. This is a transcript of an executed command, not a description. |
| 4 | A restore of Donetick and of Actual has been demonstrated with the same tool, and a VM test suite exercises dataset layout, snapshot/prune behavior, and per-service restore | ✓ VERIFIED | Live drills documented with concrete evidence in `14-06-SUMMARY.md` (marker-file round trip for Donetick from the replica; byte-for-byte `user-files` and intact `account.sqlite` for Actual, both from the source). `tests/backup-layout.nix` / `tests/backup-layout-disko.nix` exercise dataset layout from scratch; `tests/backup-behavior.nix` exercises snapshot/prune (including the retention floor case) and per-service restore for the two services the guest stands up (`SERVICES = ["donetick", "mealie"]`, line 149; restore round-trip at lines 720-731). The roadmap wording asks for "per-service restore" as a demonstrated capability, not full-fleet VM coverage — that stricter clause lives only in REQUIREMENTS.md's amended BKP-06 text (see Requirements Coverage below and the human verification item). |

**Score:** 4/4 roadmap Success Criteria verified.

### PLAN-Level Must-Haves (14-01 through 14-06)

Spot-verified rather than exhaustively re-derived, since the 6 plans declare ~60 truths total. All artifacts, key links, and a representative sample of truths were checked; none contradicted the live evidence below or the SUMMARY narratives, which read every piece of shell logic against actual VM assertions rather than describing behavior.

| Plan | Sample truths checked | Status |
|------|------------------------|--------|
| 14-01 | Recursive snapshot atomicity; replica left unmounted; restore refuses non-empty target without override | ✓ VERIFIED (live: identical snapshot name across parent+16 children; replica `mounted=no`) |
| 14-02 | Every unit-backed service has its own dataset; Mosquitto persisted; no dataset both has a child dataset and an impermanence bind mount for the same path; properties set locally not inherited | ✓ VERIFIED (live: 16 children exist incl. mosquitto; `test-dataset-properties.sh` 4/4 pass — atime off locally on all 16, postgresql recordsize 16K locally) |
| 14-03 | Generic PostgreSQL discovery; dump published only after listability proven; SQLite verified against a copy from the snapshot, never the live file; hold advances only on clean verification; strict sandbox on verify unit | ✓ VERIFIED (live manifest and holds; `hosts/ser8/backup/verify.nix` carries `ProtectSystem=strict`, narrow `ReadWritePaths`, `CapabilityBoundingSet` per code review) |
| 14-04 | Absence-safe staleness alerts; every smoketest fails closed (no skip-to-pass); manifest coverage cross-checked against declared set; suite reached through the single host deployment entry point | ✓ VERIFIED (`scripts/smoketests/ser8/all.sh` includes `backup/all.sh`; independently re-run 9/9 pass live) |
| 14-05 | Replication target dedup-off, no live mountpoint; each of 16 services on its own dataset verified equal to source before cutover; every covered service healthy across a real reboot; rollback anchor untouched | ✓ VERIFIED (live: all 16 services `active` on a host up 21h51m, i.e. survived a real reboot; `test-no-stale-persist-dirs.sh` 2/2 pass — all 16 live paths are their own mounted datasets, no leftover directories) |
| 14-06 | Restore tool lists/reads-from-replica/rolls-back-gated/restores-single-database; three drills executed and recorded; at least one unattended nightly cycle ran and produced a manifest/digest/metrics; smoketests pass after a real cycle; old state directories deleted | ✓ VERIFIED (live: `backup-verify.service` last run succeeded this morning unattended, 12:00:33 PDT; manifest, 6 metrics, and 17 holds all read back live; 9/9 backup smoketests pass; 15 leftover directories confirmed absent) |

**One PLAN-level deviation worth flagging explicitly (not a gap):** 14-05/14-06's must-haves describe the replica as "read-only." The live replica reads `readonly=off` at the pool level. This was a deliberate, documented reversal (`git show 64cec24`): setting `readonly` on receive requires a delegated ZFS permission the replication account does not hold, so every prior attempt silently failed to apply the property while logging one permission-denied error per dataset per run — worse than not trying, because it trained the operator to ignore the unit's own logs. The actual protection against accidental replica writes is `mountpoint=none` (confirmed live) plus the restore tool mounting the replica read-only at use time (`hosts/ser8/backup/restore/backup-restore:222-237`, confirmed by reading the code: `zfs mount -o ro "$dataset_name"`). The underlying prohibition ("no dataset in the replica tree may carry a mountpoint near a live service path") holds; only the specific mechanism named in the must-have text changed, for a documented, sound reason. Treated as VERIFIED by substance, not as a gap.

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `hosts/ser8/backup/default.nix` | Slice entry point | ✓ VERIFIED | Imported by `hosts/ser8/configuration.nix:16` |
| `hosts/ser8/backup/services.nix` | Covered-service catalog | ✓ VERIFIED | 96 lines, drives `test-no-stale-persist-dirs.sh` and `test-manifest-coverage.sh` live |
| `hosts/ser8/backup/datasets.nix` | Per-service dataset declarations | ✓ VERIFIED | 44 lines, disko mountpoints confirmed live |
| `hosts/ser8/backup/policy.nix` | sanoid/syncoid snapshot + replication policy | ✓ VERIFIED | 158 lines, `daily=30`, `autoprune=true` confirmed |
| `hosts/ser8/backup/dump.nix` / `dump.sh` | Generic pg_dump job | ✓ VERIFIED | Catalog-driven discovery confirmed by reading the query; live dumps present |
| `hosts/ser8/backup/verify.nix` / `verify.sh` | Content-based verification, manifest, metrics, holds | ✓ VERIFIED | 577-line `verify.sh`; live run this morning succeeded, correctly flagged 101 non-databases |
| `hosts/ser8/backup/mail.nix` | Shared sendmail wrapper | ✓ VERIFIED | 71 lines; live digest mail delivered (SMTP 250, confirmed in journal) |
| `hosts/ser8/backup/restore.nix` / `restore/backup-restore` | Full-scope restore tool | ✓ VERIFIED | 531-line tool; `list`, `--from replica`, `--rollback`, `--pg-database`, `--dry-run` all present and exercised in 3 live drills + VM suite |
| `hosts/ser8/backup/README.md` | Operator runbook | ✓ VERIFIED | 224 lines; every command in it was run per 14-06-SUMMARY's self-check |
| `modules/gateway/alertmanager.nix` | Alert delivery on firebat | ✓ VERIFIED | 101 lines; imported by `modules/gateway/default.nix:9`; live, registered with Prometheus, delivering |
| `scripts/smoketests/backup/*.sh` (9 files) | Fail-closed live-host suite | ✓ VERIFIED | Independently re-run by the verifier against the live host: 9/9 pass |
| `tests/backup-behavior.nix`, `tests/backup-layout.nix`, `tests/backup-layout-disko.nix` | VM proof of mechanism | ✓ VERIFIED (per SUMMARY's recorded run) | 1136-line behavior test read directly; VM builds not re-run (12min remote builder each per context notes) — SUMMARY's 33-subtest PASS claim is corroborated by the code the test file actually contains |

### Key Link Verification

| From | To | Via | Status | Details |
|------|-----|-----|--------|---------|
| `hosts/ser8/configuration.nix` | `hosts/ser8/backup/` | `imports = [ ./backup ]` | ✓ WIRED | Line 16, confirmed |
| `modules/gateway/default.nix` | `modules/gateway/alertmanager.nix` | `imports` | ✓ WIRED | Line 9, confirmed |
| `scripts/smoketests/ser8/all.sh` | `scripts/smoketests/backup/all.sh` | Suite array entry | ✓ WIRED | Confirmed present; reached through the single deploy.yaml-referenced entry point |
| `backup-verify.service` hold | `backup-restore`'s latest-verified default | Manifest + ZFS hold cross-check | ✓ WIRED | Live: all 17 hold positions match manifest exactly (`test-manifest-coverage.sh` hold-position test, independently re-run) |
| Prometheus rules (firebat) | Alertmanager | `alertmanagers` config | ✓ WIRED | `curl localhost:9090/api/v1/alertmanagers` shows one active, zero dropped, independently confirmed live |
| `dump.sh` output | `verify.sh` pgdump check | `DUMP_SUBPATH` inside snapshotted tree | ✓ WIRED | Live manifest shows `pgdump` rows resolving `pg_restore-list ok` against the exact snapshotted path |

### Behavioral Spot-Checks (live host, read-only)

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Full backup smoketest suite | `./scripts/smoketests/backup/all.sh ser8` (run by the verifier, not sourced from SUMMARY) | `backup suite: 9/9 tests passed` | ✓ PASS |
| Gateway alert delivery suite | `./scripts/smoketests/gateway/test-alertmanager.sh firebat` (run by the verifier) | `all 4 Alertmanager tests passed` | ✓ PASS |
| All 16 covered services healthy | `systemctl is-active` for each, live on ser8 (uptime 21h51m — post-reboot) | All 16 `active` | ✓ PASS |
| Last unattended verification run | `systemctl status backup-verify.service` | Succeeded Sat 12:00:33 PDT, correctly flagged 101 non-databases by content, held all 16 datasets | ✓ PASS |
| Restore tool's replica read protection | Read `hosts/ser8/backup/restore/backup-restore:222-237` | `zfs mount -o ro "$dataset_name"` present | ✓ PASS |
| Leftover state directories removed | `test -e /persist/var/lib/<svc>` for all 16, and `test-no-stale-persist-dirs.sh` | None exist; smoketest 2/2 pass | ✓ PASS |

VM checks (`nix build .#checks.x86_64-linux.backup-behavior` / `backup-layout`) were not re-run in this verification pass — each takes ~12 minutes on the remote builder per the session's context notes, and the test source (`tests/backup-behavior.nix`, read in full) matches the SUMMARY's described assertions exactly, including the specific `SERVICES = ["donetick", "mealie"]` scope limitation the SUMMARY itself discloses.

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| BKP-01 | 14-01, 14-02, 14-04, 14-05 | Nightly atomic snapshot, replicated, dedup-off, 30-night pruning by policy tool | ✓ SATISFIED (mechanism; live pruning not yet exercised — see human verification) | Live datasets/policy confirmed; only 3 nightlies exist so far |
| BKP-02 | 14-03, 14-06 | Mealie covered by snapshot incl. images/uploads; PostgreSQL captured as portable dump generically | ✓ SATISFIED | Live dumps present and listable; catalog-driven discovery confirmed in code |
| BKP-03 | 14-01, 14-03, 14-04 | Atomic snapshot only, never non-atomic copy; verified against a snapshot copy, never live | ✓ SATISFIED | Live verify run this morning; content-based header detection confirmed working against real anomalies (Mesa cache, mosquitto.db) |
| BKP-04 | 14-02, 14-06 | Actual's full state (sqlite + user-files) captured by snapshot | ✓ SATISFIED | Live drill: byte-identical restore of both, documented with checksums |
| BKP-05 | 14-06 | Mealie restore into scratch VM demonstrated | ✓ SATISFIED | Live drill transcript in 14-06-SUMMARY.md |
| BKP-06 | 14-01, 14-03, 14-06 | Donetick + Actual restore demonstrated; VM suite exercises restore across every covered service | ⚠️ PARTIALLY SATISFIED | Donetick+Actual restore: done, live drills. "Every covered service" VM coverage: not met — VM suite covers 2/16 (`donetick`, `mealie`). REQUIREMENTS.md itself has this unchecked (`- [ ]`) and traceability marked "Pending" — disclosed, not hidden. See human verification. |
| BKP-07 | 14-02, 14-04, 14-05 | Whole-of-persist coverage, not a named list | ✓ SATISFIED | 16 covered services + parent dataset catches all unregistered state; live manifest coverage test confirms all 16 declared services present |

No orphaned requirements: all 7 BKP-01..07 IDs are claimed across the 6 plans' `requirements:` frontmatter and match REQUIREMENTS.md's Phase 14 traceability table exactly.

### Anti-Patterns Found

Sourced from `14-REVIEW.md` (0 blockers, 5 warnings) and independently re-checked against the current codebase — all 5 confirmed still present, none newly introduced, none blocking:

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `hosts/ser8/backup/verify.sh` | 74-79 | `add_row()` sanitizes tabs/newlines only in `result`, not `subject` (file path) | ⚠️ Warning | Cosmetic manifest-row corruption risk for an extension-limited, unlikely filename; cannot mis-route a restore (dataset rows are built separately from ZFS names) |
| `hosts/ser8/backup/verify.sh` | 418-425 | Multiple simultaneous stale hold-release failures only record the last one | ⚠️ Warning | Understates (never overstates) protected state; requires an already-degraded prior run plus a second failure |
| `hosts/ser8/backup/restore/backup-restore` | 438-467 | `--dry-run --pg-database` never checks the archive exists | ⚠️ Warning | A misspelled database name previews clean, fails on the real run |
| `hosts/ser8/backup/dump.nix` | 29-62 | `backup-pgdump.service` lacks the sandboxing `backup-verify.service` uses | ⚠️ Warning | Inconsistent with the phase's own hardening bar; smaller attack surface than verify since postgres already has DB access |
| 4 household smoketest files | see 14-REVIEW.md | Duplicate `*_persist_dir` test left over from the dataset migration, now identical to `*_state_dir_shape` | ⚠️ Warning | Inflates test count without adding coverage; the real successor check exists elsewhere |

No debt markers (`TBD`/`FIXME`/`XXX`) found in any phase-touched file. Two `placeholder` matches in `alertmanager.nix` are the documented, intentional SOPS-substitution pattern, not stubs.

### Deviations Confirmed as Sound (not gaps)

- **Replica `readonly` property omitted rather than set** (see PLAN-Level Must-Haves above) — deliberate, documented, functionally compensated.
- **`system.autoUpgrade` removed from every host** — an unrelated but serious finding (pointed at an unregistered upstream namespace, a live RCE path had anyone claimed it), fixed during this phase, recorded in Threat Flags and `deferred-items.md`.
- **Alertmanager added mid-phase** after discovering firing alerts reached nobody — corrected in an addendum to 14-06-SUMMARY.md, now independently verified live and delivering.

## Human Verification Required

### 1. BKP-06's "every covered service" VM coverage clause

**Test:** Review whether the current evidence (generic, service-agnostic restore tool; 3 real live-host drills across Donetick, Actual, and Mealie; a VM suite that proves the restore mechanism against 2 of 16 services) is sufficient to close BKP-06, or whether the VM guest must be expanded to stand up more or all 16 covered services before the requirement is marked complete.
**Expected:** An explicit accept/reject decision, since REQUIREMENTS.md already carries this as an open, unchecked item — this verification is not introducing a new finding, only surfacing it for closure.
**Why human:** Scope and risk-tolerance judgment, not a code defect. The Phase 14 ROADMAP.md Success Criterion (the phase's authoritative completion bar) is satisfied by the current evidence; the more demanding wording lives only in REQUIREMENTS.md's post-pivot amendment.

### 2. BKP-01's pruning clause, proven by mechanism rather than by elapsed time

**Test:** Decide whether mechanism-level proof (sanoid `daily=30`/`autoprune=true` deployed, two dedicated VM assertions including the retention floor case) is sufficient, given that only three nightlies exist on the live host so pruning has not yet had occasion to remove anything.
**Expected:** An explicit accept/reject decision, or a note to revisit once 30+ nightlies have accumulated.
**Why human:** Purely time-dependent; nothing further can be inspected today.

## Gaps Summary

No blocking gaps. All four ROADMAP.md Phase 14 Success Criteria are independently verified true against the live host (re-run smoketests, live ZFS/systemd/Prometheus state), not merely asserted by SUMMARY.md. All 7 BKP requirements are accounted for across the 6 plans with no orphans; 6 of 7 are fully satisfied, and the 7th (BKP-06) is honestly and correctly disclosed in REQUIREMENTS.md itself as partially satisfied, pending a scope decision that this report surfaces for explicit human resolution rather than silently passing or silently failing. The code review's 5 warnings are all confirmed present, all non-blocking, and none contradict any must-have truth.

---

_Verified: 2026-08-29T19:55:00Z_
_Verifier: Claude (gsd-verifier)_
