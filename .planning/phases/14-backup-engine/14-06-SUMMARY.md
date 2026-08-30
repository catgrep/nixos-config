---
phase: 14-backup-engine
plan: 06
subsystem: storage
tags: [zfs, restore, verification, drills, runbook, sanoid, syncoid, live-host]
status: complete

requires:
  - hosts/ser8/backup/restore/backup-restore (from 14-01) as the tracer this plan extends
  - hosts/ser8/backup/verify.sh (from 14-03) for the manifest and hold mechanism
  - scripts/smoketests/backup/ (from 14-04) as the fail-closed gate
  - the sixteen live datasets and the running engine (from 14-05)
provides:
  - the restore tool at full scope, with listing, replica reads, database restore, gated rollback and preview
  - a verification that identifies databases by content rather than by filename
  - hosts/ser8/backup/README.md, the operator runbook
  - modules/gateway/alertmanager.nix, so a firing alert reaches a person
  - three executed restore drills with recorded evidence
  - the migration's leftover state directories deleted
affects:
  - hosts/ser8/backup/verify.sh
  - hosts/ser8/backup/policy.nix
  - modules/common/nix.nix
  - scripts/smoketests/backup/test-metrics.sh
  - scripts/validation/test-mealie-module.sh
  - scripts/validation/test-donetick-module.sh
  - modules/gateway/prometheus.nix
  - scripts/smoketests/gateway/all.sh

tech-stack:
  added: []
  patterns:
    - identify a file by its magic header, and record what it turned out to be rather than skipping it
    - anchor coupled timers to one clock, and say which, because a bare time is read locally
    - a sidecar file as evidence of a file's former kind, so damage cannot masquerade as foreignness
    - build a drill machine that imports the production modules rather than approximating them

key-files:
  created:
    - hosts/ser8/backup/README.md
    - modules/gateway/alertmanager.nix
    - scripts/smoketests/gateway/test-alertmanager.sh
    - .planning/phases/14-backup-engine/14-06-PROGRESS.md
    - .planning/phases/14-backup-engine/14-06-SUMMARY.md
  modified:
    - hosts/ser8/backup/restore/backup-restore
    - hosts/ser8/backup/restore.nix
    - hosts/ser8/backup/verify.sh
    - hosts/ser8/backup/verify.nix
    - hosts/ser8/backup/policy.nix
    - tests/backup-behavior.nix
    - modules/common/nix.nix
    - scripts/smoketests/backup/test-metrics.sh
    - scripts/validation/test-mealie-module.sh
    - scripts/validation/test-donetick-module.sh
  - modules/gateway/prometheus.nix
  - scripts/smoketests/gateway/all.sh
    - .planning/phases/14-backup-engine/deferred-items.md
  deleted:
    - fifteen leftover state directories under /persist/var/lib (live host, not repository)

decisions:
  - Databases are identified by their sixteen-byte header, not by the *.db filename
  - A file carrying a SQLite sidecar without the header is damage, not a foreign file
  - The whole nightly cycle moved to 10:00/10:30 UTC so both halves share one clock
  - system.autoUpgrade removed from every host rather than repointed
  - The fifteen leftover directories were deleted now (operator chose delete-now)
  - The two drill move-aside directories are kept for now
  - Alertmanager reuses Grafana's SMTP credential rather than adding a second one

metrics:
  duration: ~8h wall clock across two sessions
  completed: 2026-08-29

actuals:
  tokens: 23519
  tasks: 4
  commits: 14
---

# Phase 14 Plan 06: Restore Tooling, Drills and Close-out Summary

The restore tool now covers every path an incident needs and three real restores have been executed to prove it, but the headline finding is that the engine's first unattended verification failed on 101 files that were never databases — a name-based check meeting a host where `*.db` and "database" are different sets.

## Performance

| Metric | Value |
|--------|-------|
| Tasks | 4 of 4 |
| Commits | 14 (12 source, 2 docs) |
| Behaviour assertions | 33, up from 19 |
| Restore drills executed | 3 of 3 |
| Leftover state removed | 4,127,343,839 bytes across 15 directories |
| `make smoketests-ser8` | 6/7 suites (one pre-existing failure) |
| `backup/all.sh` | **9/9** |
| `make check` | passes, 83 s warm |

## Accomplishments

- **The restore tool covers the whole surface.** Listing with the proven-good snapshot marked, a default that resolves the last verified snapshot from the manifest and refuses when the manifest and the pool's hold disagree, reads from the replica, single-database restore from the archive inside the snapshot, a rollback behind two flags and refused against the replica, and a preview that composes with every mode.
- **Three restores actually happened**, with commands and output as the evidence rather than description. Details below.
- **The verification now identifies databases by content**, records what a non-database turned out to be, and still fails a database whose header was destroyed.
- **The engine's first green cycle.** All seventeen datasets verified and held, all six metrics published, digest delivered, and all three alerts resolved from firing to inactive.
- **An unclaimed-namespace auto-upgrade was removed from every host.**
- **The runbook exists** and every command in it has been run.

## The verification was checking files that were never databases

The unattended run fired at 03:30:04 PDT, took 8 seconds, mailed its digest, and exited 1. Of **133 files checked, 101 failed**, every one with `file is not a database`:

| Source | Count | Magic |
|--------|-------|-------|
| Frigate's `mesa_shader_cache_db/part*/mesa_cache.db` | 50 | `MESA_DB\0` |
| the same files in the leftover `/persist/var/lib/frigate` copy | 50 | same |
| `mosquitto.db` | 1 | `\0\265\0mosquitto db\0` |

Real databases begin `SQLite format 3\0`. Everything downstream then behaved exactly as designed on bad input, which is what made it expensive: fourteen services held their verified snapshot while **frigate and mosquitto held nothing**, the freshness metrics were left unstamped, and all three staleness alerts fired.

The fix decides the kind by reading the header. Files that are not databases are written into the manifest under their own result with the magic that was found, and carried in a metric of their own, so a file that stops being checked is visible rather than absent.

The cost of deciding by content is real and is handled rather than accepted: a database damaged badly enough to lose its header would look like a file that never was one. A write-ahead log or shared-memory sidecar is created by SQLite and by nothing else, so a file carrying one without the header is reported as damaged. Otherwise the worst case would have read as a pass.

After the fix, run by hand: `Verified autosnap_2026-08-29_18:00:03_daily: 32 database(s), 2 archive(s), all clean (101 named like one but are not)`, `#status=ok`, 25 seconds.

## The two halves of the cycle were on different clocks

The snapshot tool's unit runs with `TZ=UTC` forced upstream, so its configured `daily_hour = 3` meant 03:00 **UTC** — 20:00 local. The verification's timer carried a bare `OnCalendar=03:30`, read locally. The two halves of one nightly cycle were **7.5 hours apart** in summer and 8.5 in winter.

Nothing reported it, because the 26-hour freshness window absorbs it. The only visible symptom was a verification slot sitting 30 minutes ahead of the nightly upgrade instead of the hour of margin it was chosen for.

Both are now anchored to UTC at 10:00 and 10:30, which is 03:00 and 03:30 local in summer — the quiet window originally intended. The dump keeps its position by unit ordering rather than by a time, so it moved with them.

One transition artifact, benign: moving the hour produced a second daily for the same UTC day, because the previous one had been taken before the new hour.

## The three drills

**Donetick, read from the replica.** `sudo backup-restore donetick --force --from replica` resolved its own default snapshot with no snapshot argument. Service active, HTTP 200, 7 chores and 3 users intact. A marker file written beforehand was gone from the live directory and present in the preserved copy with its exact contents, and that copy's database still answered queries — the move-aside is a real copy. The replica was left `mounted=no`, `mountpoint=none inherited from backup`.

**Actual, read from the source.** `sudo backup-restore actual --force`. The `user-files` tree came back byte-for-byte: 2 files, 43,030 bytes both sides, MD5 `74e138e6…` and `ee0ef73f…`. `server-files/account.sqlite` present at 69,632 bytes with its full schema; budget "My Finances" registered and undeleted, 1 user, 1 session.

**Mealie, into a scratch machine on ser8.** The machine imported the real `hosts/ser8/backup/restore.nix` and `modules/household/mealie.nix` and pinned mealie 3.22.0 and PostgreSQL 17.11 — identical to ser8. The database was dropped and the state directory emptied, then `backup-restore mealie --force --pg-database mealie` ran with no snapshot argument. The state directory came back identical to the snapshot apart from the application's own log, which grew because it had started. At the application level: logged in, the API returned both real recipes, and `original.webp` was served over HTTP at 57,730 bytes with SHA-256 `7a1e2728…` — identical to both the restored file and the copy inside the snapshot. The machine and all 94 MB of staged production data were destroyed.

Three lessons went into the runbook: the tool does not create a missing database; recreating the `public` schema as the superuser leaves one the application's role cannot write to, and the resulting error names nothing useful; and ownership has to travel with the files whenever a restore crosses hosts.

## Deviations from Plan

### 1. [Rule 1 - Bug] The verification failed on files that are not databases

Found during Task 2. Described above. Fixed in `40d8c87` with three new assertions.

### 2. [Rule 1 - Bug] The snapshot and verification ran on different clocks

Found during Task 2. Described above. Fixed in `f909513` and `7511d87`.

### 3. [Rule 1 - Bug] The metric freshness smoketest could not parse its own metric

The exporter renders gauges as floating point, and a Unix timestamp comes back as `1.788026403e+09`. The check trimmed at the first dot — correct for a plain decimal — turning it into `1`, so the age read as the whole span since the epoch. It could not have surfaced before: until this run the metric had never been published, so the test always failed earlier, on absence. Fixed in `489aabc`.

### 4. [Rule 1 - Bug] Two validation gates had drifted from the configuration

`make check` was failing on both. The Mealie gate still expected signup closed; it has been deliberately open since the instance became Tailscale-only. Its real purpose is the *type* — `toString false` is the empty string, so a Nix boolean would build and silently reopen registration — so the expectation moved to the quoted string `"true"` with the reasoning recorded. The Donetick gate checked for an impermanence directory entry; that state is now a dataset of its own, a stronger form of the same guarantee, so it pins the mount. Fixed in `2a033e5`.

### 5. [Rule 2 - Missing critical functionality] Auto-upgrade pointed at an unclaimed namespace

`modules/common/nix.nix` enabled `system.autoUpgrade` on **every host** against `github:your-username/nixos-config` — the upstream template's placeholder. Every host had been failing nightly with a 404, so the 04:00 window the backup schedule was designed around was a no-op. The account name is unregistered and the reference unpinned, so anyone registering it would have had all four machines fetch and activate their configuration as root the next night. Removed rather than repointed, in `d9c60ad`.

### 6. [Rule 1 - Bug] A racy assertion in the behaviour suite

The interrupted-replication assertion watched the whole replica grow and crashed when any dataset had moved 32 MiB, which says nothing about whether the dataset it then asserts on was still receiving; and its 256 MiB payload transferred faster than the roughly one-second polling interval, so the window could be stepped over entirely. It now watches the child it asserts on and sends a gigabyte.

### 7. [Rule 1 - Bug] The behaviour suite depended on the builder's wall clock

The policy only takes a nightly once past its configured hour, and the guest inherited whatever time the build machine was at, so every assertion resting on "a night passed" was conditional on the builder being late enough in the day. The guest clock is now pinned to midday UTC.

### 8. [Observation] The scratch drill machine had to import the production module

The first drill machine approximated Mealie's configuration and got `DynamicUser=true`, which relocates state behind `/var/lib/private` — a layout the host does not have. It now imports `modules/household/mealie.nix` directly. A related trap: the first pin read `flake.lock`'s `nodes.nixpkgs` and produced PostgreSQL **17.7**; the root input actually resolves through `nodes.nixpkgs_3` to **17.11**, and a version mismatch is exactly the coupling the portable archive exists to defeat.

## Known Issues

### `make smoketests-ser8` is 6/7, on a pre-existing failure

`media/all.sh` fails: Bazarr cannot access `/mnt/media/tv/Seinfeld`. This is the ACL drift recorded in 14-05, on the `media/data` dataset, which no part of this phase touches.

### Both Raspberry Pi hosts are unreachable

pi4 and pi5 could not be reached on their LAN addresses or over Tailscale; the monitoring host has reported pi4 down since **2026-08-17**. pi4 is the AdGuard Home DNS and DHCP server, which makes it worth attention beyond this phase. The `autoUpgrade` removal has therefore not reached either Pi — harmless while they are off, and it 404s even when they are on.

### Space is not reclaimed yet, by design

Deleting the leftovers took `rpool/safe/persist` from **2.85G referenced to 224M**, but `usedbysnapshots` rose from 10.6G to 13.2G: the snapshots now hold the only copy. The pool frees the space as those snapshots age out over the next thirty nights, which is exactly the escape route the deletion was gated on.

## Verification

| Check | Result |
|-------|--------|
| `nix build .#checks.x86_64-linux.backup-behavior` | PASS, 33 subtests |
| `nix build .#checks.x86_64-linux.backup-layout` | PASS |
| `shellcheck` / `shfmt` on every changed script | PASS |
| `nixfmt` / `statix` | PASS |
| `make check` | PASS, 83 s warm |
| `./scripts/smoketests/backup/all.sh ser8` | **9/9** |
| `household/all.sh` after the drills | 8/8 |
| `make smoketests-ser8` | 6/7 — see Known Issues |
| Manifest `#status` | `ok` |
| All 17 datasets held at the verified snapshot | PASS |
| Six metrics published and served | PASS |
| Three alerts, fired then resolved | PASS |
| Sixteen services active after all drills | PASS |
| No planning terminology in produced files | PASS |
| Every flag in the runbook exists in the tool | PASS |

On `make check`'s runtime: 83 seconds is the **warm** figure, with both machine tests already built. Cold, it is dominated by them at roughly 11–13 minutes each on the remote builder.

## Requirements

Marked complete on live evidence: **BKP-01, BKP-02, BKP-03, BKP-04, BKP-05, BKP-07**.

**BKP-06 is deliberately left incomplete.** Its first half is met — Donetick and Actual were both restored with the same tool, and the transcripts are above. Its second half asks that "a VM test suite exercises the restore path across every covered service", and the suite drives its restore assertions across the two services the guest stands up, not all sixteen. The path is service-agnostic and driven from the covered-service list rather than hardcoded, so the generality is argued rather than demonstrated. Standing up sixteen real services in the guest is its own piece of work.

A note on BKP-01: its pruning clause says "pruned to a 30-night sliding window". The policy is deployed and its pruning is proven by two dedicated assertions including the floor case, but only three nightlies exist on the live host, so pruning has not yet had to remove anything there. Marked complete on the strength of the mechanism rather than on elapsed time; challenge it if that reads too generously.

## Threat Flags

None new. The plan's register was exercised: the rollback needs two flags and is refused against the replica, with both refusals asserted (T-14-27); the move-aside was spot-checked inside on both live drills (T-14-28); the drill data never left the host and was destroyed with the machine (T-14-29); the replica was confirmed unmounted and without a mountpoint after the replica read (T-14-30); every drill is a transcript rather than a description (T-14-31); the deletion happened only after a verified cycle, three restores and the runbook (T-14-32).

One finding outside the register, recorded above and in `deferred-items.md`: the unclaimed auto-upgrade namespace, which was a live remote-code-execution path on all four hosts had anyone registered the name.

## Deferred

`deferred-items.md` gained: the two operator scheduling decisions (chain the cycle by unit completion; alert on the verification relative to the snapshot), the orphaned `backup` user and group from the firebat deploy, both Pi hosts being unreachable, the two preserved drill directories and when to remove them, a replication permission failure seen after a crash in the guest, the stale `overlays/` reference in `CLAUDE.md`, and the deliberate-auto-upgrade question left open by the removal.

## Self-Check: PASSED

`hosts/ser8/backup/README.md` and `14-06-SUMMARY.md` exist on disk. All eleven prior commits are present in `git log`. The fifteen leftover directories are absent from `/persist/var/lib`, confirmed by listing it. The manifest, the metrics, the seventeen holds and the three resolved alerts were read back from the hosts rather than inferred from exit codes.

## Addendum, 2026-08-29: alert delivery

Added after this plan was first written up. It is filed here rather than edited into the body above so the record shows what was known when, and corrects something the body originally implied.

### A firing alert was reaching nobody

Found after the rest of this plan was written, and it inverts something recorded
earlier: the three staleness alerts did fire, but firing is not the same as
arriving. The alerting host had **no Alertmanager**, and Prometheus hands a
firing rule to whatever is listed under `alertmanagers` — with nothing listed,
that is nowhere. The rules page and the API look identical either way, which is
what let this sit unnoticed.

The mail that did arrive during this phase came from two narrower paths that
happen to overlap the same subject: the storage host's own `OnFailure` mail,
which fires within seconds of a unit *failing*, and Grafana's separate rules.
Neither covers the case these alerts exist for — a job that stopped running, so
nothing failed and nothing was stamped.

`modules/gateway/alertmanager.nix` closes it. The credential is the Gmail
application password Grafana already uses, referenced rather than copied so there
is one to rotate; it stays a placeholder in the world-readable store and is
substituted at start from a root-only file, because the service runs under a
transient user and `EnvironmentFile` is read before privileges drop.

Proven rather than assumed: a labelled test alert posted to the real path came
back `alertmanager_notifications_total{integration="email"} 1` with every
`alertmanager_notifications_failed_total{integration="email"}` at zero. Four
smoketests now cover the delivery path, the sharpest being that Prometheus has a
live Alertmanager registered with none dropped — the check that would have caught
this from the start.

**What the earlier write-up got wrong.** It treated the three alerts firing as evidence the household was being told. Firing and arriving are different things, and only the first had been established. The alerts had never notified anyone in the whole history of this phase.

**Also corrected here:** an earlier note in the progress file suspected `make dry-activate-HOST` of creating a system generation. It does not. A dry-activate at 12:20 left the generation untouched and it moved only on the 12:21 switch; the earlier generation was a deploy someone else had already reported. Treat dry-activate as read-only.

**Still open, deliberately:** pi4 is decommissioned rather than broken, and four permanently firing `HostDown` alerts about it would now reach a person every twelve hours. Removing it from the scrape targets and from Grafana's host-down scope is filed in `deferred-items.md`, unmade here because deciding what the monitoring watches is not a storage change.
