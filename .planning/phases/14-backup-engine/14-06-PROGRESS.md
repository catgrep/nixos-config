# Phase 14 Plan 06 — progress at the pause of 2026-08-29

Written because the session running this plan was ending. The plan is **not**
complete; this file is the handoff, not a summary. It records what has actually
happened on the hosts, what the evidence is, what has already been approved, and
what is left.

## State: tasks 1, 2 and 3 done; task 4 outstanding

| Task | State |
| --- | --- |
| 1 — restore tool at full scope | Done, committed, virtual machine suite green |
| 2 — replication and one unattended cycle | Done. The cycle ran and **failed**; cause understood, fix not yet written |
| 3 — three restore drills | Done. All three executed against real snapshot data |
| 4 — runbook, then the deletion decision | Not started. Blocked on decisions below |

## Commits

| Hash | Subject |
| --- | --- |
| `0fe0ba9` | ser8: complete the restore tool |
| `8045014` | test: prove every restore path the tool now offers |
| `64cec24` | ser8: stop receiving the replica read-only |
| `f909513` | ser8: run the nightly verification on the snapshot's clock |
| `7511d87` | ser8: move the nightly cycle into the quiet hours |

`nix build .#checks.x86_64-linux.backup-behavior` passes with 31 subtests.
Red was observed for all seven new capabilities in one probe run before any of
them was implemented; each returned `[ERROR] Unknown option: …`.

## What is live on the hosts

**ser8 was switched** (generation 291). Activation reloaded `dbus-broker` and
restarted `backup-verify.timer`; no service restarted and nothing went down.
Live: `daily_hour=10`, `recvoptions u x mountpoint`,
`OnCalendar=*-*-* 10:30:00 UTC`. The timer did not re-fire on restart because
`03:30` local and `10:30 UTC` are the same instant under daylight saving.

**firebat was deployed** by the team lead at the operator's direct instruction.
All three `Backup*` rules are loaded. That activation exited 4 on a transient
`dbus-broker` reload failure while applying the switch in full, and it removed an
orphaned `backup` user and group from July 2025 — both recorded in
`deferred-items.md`.

## The first replication, measured

Ran unattended at `2026-08-28T15:00:00-07:00`, finished `15:01:39-07:00` —
**99 seconds**, exit 0. It created `backup/persist-replica` itself; the grant
hook logged `cannot open 'backup/persist-replica': dataset does not exist`,
confirming that not pre-creating it was right. It sent the oldest full snapshot
(`@pre-26.05-2026-08-17T085547Z`, ~15.3 GB by the tool's own estimate) and then
incrementals. The nightly run took **13 seconds**; hourly runs with nothing to
send take about **3 seconds**.

The `readonly` noise was smaller than feared: 18 lines per run that actually
receives, not per hour. Hourly no-op runs were already clean. Reverted anyway.

## The unattended cycle ran, mailed, and failed

`backup-verify` fired on its own at **03:30:04 PDT** and finished in **8 seconds**
(9.2s wall, 6.8s CPU, 279.6 MB read). It wrote its manifest and delivered its
digest (SMTP 250, 21,569 bytes). It exited 1.

Manifest: snapshot `autosnap_2026-08-29_03:00:04_daily` on both sides, all
sixteen services covered, `written_bytes=112,697,344`,
`usedbysnapshots_bytes=11,443,834,880`, **`status=fail`**.

**133 SQLite files checked, 101 failed, every one with `file is not a database`:**

| Source | Count | What it is |
| --- | --- | --- |
| `/var/lib/frigate/.cache/mesa_shader_cache_db/part*/mesa_cache.db` | 50 | Mesa shader cache, magic `MESA_DB\0` |
| the same files in the leftover `/persist/var/lib/frigate` copy | 50 | same |
| `/var/lib/mosquitto/mosquitto.db` | 1 | Mosquitto's format, magic `\0\265\0mosquitto db\0` |

Real databases begin `SQLite format 3\0`. The discovery rule matches on the
name `*.db`, which on this host is not the same set as "is a database".

Everything downstream then behaved correctly on bad input: fourteen services
verified clean and hold the snapshot, **frigate and mosquitto hold nothing**, the
freshness metrics were left unstamped, and all three staleness alerts fired
through their `absent(...)` arm. That last part is the positive control the plan
asked for — the alerts are proven capable of firing.

**Correction to what this file first said:** it claimed the firing alerts meant
mail was reaching the household. They did not. The alerting host had no
Alertmanager at the time, so a Prometheus rule that fires is evaluated, marked
firing in the API, handed to an empty list of receivers, and delivered nowhere.
The mail that did arrive came from two other paths — the storage host's own
failure mail, and Grafana's separate rules. That gap was closed later in this
plan; see the summary.

## Other evidence collected

- `zfs allow` is empty on both source and replica: the delegation is revoked.
- Replica: 17/17 unmounted, no mountpoint under `/var/lib`.
- Two property divergences, expected because the send carries no properties, and
  both recorded as the plan asked: `backup/persist-replica/postgresql` reports
  `recordsize 1M inherited from backup` against the source's `16K local`, and
  every replica child reports `atime on default` against the source's `off local`.
- Exactly two daily snapshot names across 17 datasets, and zero of every other
  period.
- Dumps ride inside the snapshot: `globals.sql`, `mealie.dump` (359,665 bytes)
  and `postgres.dump`, matching the live catalog exactly.
- Change rate, first data point: about 107 MB written across the tree between the
  nightly snapshot and the verification.
- ser8's exporter is correctly pointed at the textfile directory and reports
  `node_textfile_scrape_error 0`.

## The three drills, executed

**Donetick, from the replica.** `sudo backup-restore donetick --force --from replica`,
resolving its own default snapshot with no snapshot argument. Service active,
HTTP 200, 7 chores and 3 users intact. A marker file written beforehand is gone
from the live directory and **present in the preserved copy** with its exact
contents, and that copy's database still answers — the move-aside is a real copy.
The replica was left `mounted=no`, `mountpoint=none inherited from backup`.

**Actual, from the source.** `sudo backup-restore actual --force`. The blob tree
came back byte-for-byte: 2 files, 43,030 bytes both sides, MD5 `74e138e6…` and
`ee0ef73f…`. `server-files/account.sqlite` present at 69,632 bytes with its full
schema; budget "My Finances" registered and undeleted, 1 user, 1 session.

**Mealie, into a scratch machine on ser8.** The machine imported the real
`hosts/ser8/backup/restore.nix` and `modules/household/mealie.nix` from the
repository and pinned mealie 3.22.0 and PostgreSQL 17.11, matching ser8. The
database was dropped and the state directory wiped, then
`backup-restore mealie --force --pg-database mealie` ran with no snapshot
argument. The state directory came back identical to the snapshot except
`mealie.log`, which grew because the application started. At the application
level: logged in, the API returned both real recipes, and `original.webp` was
served over HTTP at 57,730 bytes with SHA-256 `7a1e2728…` — identical to both the
restored file and the copy inside the snapshot. The profile image likewise, at
21,184 bytes. The machine and all 94 MB of staged production data were destroyed.

Three things the drills taught, for the runbook:
- The tool does **not** create a missing database. A lost one must be recreated
  with its correct owner first.
- Recreating the `public` schema as the superuser instead leaves a schema the
  application's role cannot write to, and the error it produces names nothing
  useful.
- Ownership has to travel with the files, which matters whenever a restore
  crosses hosts.

After all three: sixteen services active, no failed units, household smoketests
**8/8**.

## Smoketests

Backup suite **6/9**. All three failures are understood:
`test-manifest-coverage.sh` and `test-metrics.sh` both fail because the
verification failed, and `test-no-stale-persist-dirs.sh` fails on the leftovers
pending the decision below.

## Approvals already granted — do not ask again

The operator has already approved, and these were carried out: the ser8 switch,
the firebat deploy, the Donetick drill, the Actual drill, and the Mealie drill
including running its scratch machine on ser8 and setting a throwaway password on
the restored copy to reach the interface.

The operator also **dropped the requirement to wait for an unattended first run**
before switching, and explicitly endorsed reconstructing first-run evidence from
unit logs.

## What remains

1. **Decide how to fix the SQLite discovery.** Recommendation: identify by the
   16-byte magic header rather than the name, and record non-SQLite files in the
   manifest under their own result rather than skipping them silently, so nothing
   becomes invisible. Alternatives are excluding `.cache` by path or keeping a
   deny-list, both of which need upkeep. Until this lands the backup suite cannot
   pass and the three alerts keep firing.
2. **Decide on the leftovers** — `delete-now`, `delete-after-a-week`, or `keep`.
   Live numbers below.
3. **Write `hosts/ser8/backup/README.md`.** The drill transcripts it needs are in
   this file. Deliberately left until the verification behaviour is settled so its
   commands describe the engine being kept.
4. **Then the phase's full verification**: `make smoketests-ser8`, both virtual
   machine checks, and `make check` with its runtime recorded.

### Live numbers for the deletion decision, read 2026-08-29

15 directories (mosquitto never had one), **4,127,343,839 bytes / 3.9 GB**, of
which Jellyfin is 1.9 GB. rpool 110 G of 920 G used (11%), 810 G free. Backup
pool 787 G of 21.8 T used (3%), 21.1 T free. `rpool/safe/persist` is 16.2 G used,
2.86 G referenced, 10.6 G held by snapshots; 10.72 GiB across the whole tree.

One thing the plan did not anticipate: the leftovers are not only a footprint
cost. The nightly verification walks them, and they contribute **50 of the 101
current failures** — a second copy of Frigate's shader cache. Deleting them
halves the noise but does not substitute for the fix, because the live tree still
fails.

## Requirements

None marked complete. `BKP-01` and `BKP-07` remain unmarkable: both need a
verification run that passes, and no run has passed yet.
