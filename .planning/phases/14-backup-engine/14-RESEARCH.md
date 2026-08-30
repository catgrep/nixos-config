# Phase 14: Backup Engine - Research (pass 2, post-pivot)

**Researched:** 2026-08-26
**Supersedes:** the pass-1 six-method dump-engine research of the same date. Live inventory, exclusion evidence, journal-mode data, and several pitfalls are carried forward; the architecture, tooling, and recommendation sections are replaced wholesale.
**Domain:** Atomic ZFS snapshot backup and replication on NixOS (sanoid/syncoid vs zrepl, child-dataset migration under impermanence, snapshot-read verification, nixosTest ZFS harnesses)
**Confidence:** HIGH for the tool comparison and mechanics (read from the pinned nixpkgs modules and the sanoid/syncoid source this session), HIGH for the live inventory and churn measurement (probed on ser8 this session), MEDIUM for the receive-side property recommendation and the VM restore harness (mechanism verified, this exact combination not exercised end to end)

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01 (supersedes old D-01/D-06):** Backup generation is **atomic ZFS snapshots of persisted service state** - no per-service dump engine, no plain-dated-directory artifact format. The "zero extra tooling for restores" rationale survives: any snapshot's files are browsable at `.zfs/snapshot/<name>/...` and restorable with `cp`. - **Reversibility:** reversible in design (the old engine model can be revived from this file's history), but the child-dataset migration in D-02 is effortful to unwind once done.
- **D-02:** **Per-service child datasets**: `rpool/safe/persist/<svc>` mounted at `/var/lib/<svc>`, replacing the per-directory impermanence bind mounts for covered services. Generated from **one attrset** in the backup module (D-13) - service name in, dataset + mount + policy out. The parent `rpool/safe/persist` continues to be snapshotted so misc persisted state (Tailscale node identity, Samba tdbs, systemd bits, anything unregistered) is covered **without registration** - forgetting to add a child dataset degrades granularity, never coverage. Recursive snapshots (`zfs snapshot -r`, one TXG) keep the whole tree atomic across parent and children. Migration to child datasets is imperative per service (stop unit, `zfs create`, copy, remount, start) because disko declarations do not retro-create datasets on a live pool (Phase 13 Plans 05/07 precedent); mechanics are a research task. Which services get child datasets first vs riding in the parent is planner's discretion - granularity can grow incrementally.
- **D-03:** **Replication to the backup pool is the backup half.** Snapshots on `rpool` alone die with the NVMe. Each nightly snapshot is sent (`zfs send`/`recv`, incremental) to receive-side dataset(s) on the `backup` pool (RAID-Z2, 21.1 T free; dedup off is the inherited default there, satisfying BKP-01's dedup-off requirement). Replica files must remain browsable for restores (`.zfs/snapshot` on the received dataset); receive-side mount/property handling is a research task.
- **D-04 (supersedes old D-04):** Snapshot/prune/replication is driven by an **established policy tool, not hand-rolled units**: researcher compares **sanoid + syncoid vs zrepl** and recommends one (comparison criteria in Research tasks). The chosen tool is the retention authority. The legacy inert `services.zfs.autoSnapshot` block is **removed, not revived** (it is the older machinery; all five timers fire for nothing today).
- **D-05 (carries old D-02/D-03):** Nightly at **03:00**; source retention is a **30-nightly flat sliding window**. Receive-side retention on the backup pool may be longer (space is cheap there) - researcher recommends, planner locks. **Missed-run replay must be verified under the chosen tool** - note `/var/lib/systemd/timers` is NOT persisted on ser8, so `Persistent=true` stamps do not survive the impermanence rollback (first-research Pitfall 6); fix or tool-native equivalent required. The 04:00 `nixos-upgrade.timer` window interaction should be checked once real durations are known (snapshots are near-instant; the send and verify are the long poles).
- **D-06:** A generic nightly **verify + dump job with kind discovery, zero per-service registration** (operator constraint: no special-casing; adding a service must never require remembering to register it for verification):
  - **Pre-snapshot dump:** `pg_dumpall --globals-only` + `pg_dump -Fc` for **every non-template database discovered from the catalog** (old D-12's shape, kept because it is already generic), written INTO the persisted tree (exact location planner's discretion) and ordered before the snapshot - so the portable dumps ride inside every snapshot and replica. This generically solves PostgreSQL's major-version coupling on crash-consistent restores; no per-app dump wiring exists or is added.
  - **Post-snapshot verify:** walk the new snapshot's paths (`.zfs/snapshot/<name>/...`) and run `PRAGMA integrity_check` on **every discovered `*.db`/`*.sqlite*` file**, and `pg_restore --list` on the dumps. Structural corruption is detected within 24 h so it cannot age out the good copies. Verification reads from the snapshot, never the live files.
- **D-07 (supersedes old D-09/D-10 mechanism):** **App-side backup rule: app-native backups stay on their defaults unless their churn dominates the dataset.** Concretely:
  - Arr apps' built-in weekly backups (Sonarr/Radarr/Prowlarr/Bazarr, ~1-10 MB zips, app-side retention) **stay on** - they land inside the state dirs and ride along in every snapshot as a free app-consistent bonus layer. **No API integration, no API keys, no Bazarr secret question** - that whole surface is deleted from scope.
  - `services.declarative-jellyfin.backups = false` and the existing **8.4 GB of activation tarballs in `/var/lib/jellyfin/backups` are deleted** - each activation tars the full state (~1.8 GB), five landed on 2026-08-25 alone, and this churn dominates persist (the 9-day-old `pre-26.05` snapshot pins 10.5 GB, ~1.2 GB/day, mostly these tarballs). Their config-rollback purpose is covered by ZFS snapshots + NixOS generations.
  - Path excludes are not a ZFS feature; where junk churn matters, the mechanism is disable-at-source (preferred) or a non-snapshotted child dataset (only if disabling is impossible).
- **D-08 (new):** **Persist Mosquitto**: `/var/lib/mosquitto` gets a persistence entry (or child dataset) - today it lives on `rpool/local/root` and is destroyed every boot, so "cover Mosquitto" was theatre. Accepted side effect: retained MQTT messages and session state now survive reboots, which is correct broker behavior. Verify Frigate/HA behave across a reboot after the change.
- **D-09 (carries old D-16):** Alerting on **both channels**: `OnFailure=` email (existing msmtp/ZED `sendmail` path, one mail mechanism fleet-wide) for loud failures of the snapshot/replication/verify units, plus a **staleness metric with a firebat alert at >26 h** that MUST be written absent-series-safe (`expr ... or absent(...)` - a bare `time() - metric > 26h` never fires on a missing series, which is exactly the silent-never-ran case). Metric source: **zrepl's native Prometheus endpoint if zrepl is chosen** (D-04), else the node-exporter textfile collector (textfile dir must be persisted and must respect the exporter's `ProtectHome`/strict hardening - first-research Pitfalls 7/8).
- **D-10 (carries old D-15/D-18, reduced):** The verify job (D-06) writes a **per-night manifest** (covered datasets/services, sizes, integrity results, dump list, durations) and composes **one digest email**. The snapshot listing is the restore-time picker; the manifest adds the verification evidence and feeds the smoketests.
- **D-11 (carries old D-21's preferred shape, now uniform):** **One parameterized restore tool** - the same three steps for every service: stop unit -> replace state from the chosen snapshot -> start unit. Default mechanism is copy-from-snapshot (`.zfs/snapshot/...` on source or replica) into the live path; `zfs rollback` is available as an explicit fast destructive path (it destroys newer snapshots - gate it behind an explicit flag). The tool refuses to touch a non-empty target without an explicit flag. Runbook at `hosts/ser8/backup/README.md` indexes the tool; the drills execute it, so it is a tested artifact.
- **D-12 (carries old D-19/D-20, extended):** Restore drills (BKP-05/06) are demonstrated in a **workstation VM**: Mealie (via the generic pg dump), **Donetick** (SQLite; smallest DB, `delete` journal mode - planner's pick is now locked), and Actual (state-dir restore including `user-files/`). Additionally, the **VM test suite parameterizes restore verification across ALL covered services** (boot VM, inject snapshot state, start service, assert health) - the manual drills prove the human path; the VM suite proves generality. "Only checking Mealie" was an artifact of assuming drills are manual; with VM infra they are not.
- **D-13 (carries old D-07):** Everything lives as a host slice under **`hosts/ser8/backup/`**: one attrset of covered services generating child datasets/mounts (D-02), tool policies (D-04), the verify/dump units (D-06), and the metric wiring (D-09). Promotion to `modules/backup/` deferred until a second host needs it. **Keep it boring**: no speculative options, no method plugins, no compression knobs.
- **D-14 (carries old D-17, extended):** **VM test infrastructure is a first-class deliverable**, not just a gate: repair the workstation Linux-build path first (Determinate `determinate-nixd login` as primary; fix the stale `firebat.local` host key in `/var/root/.ssh/known_hosts` as hygiene regardless - both breakages are root-caused in the first research pass), add the repo's **first `checks` flake output**, and build a `nixosTest` suite covering: disko dataset layout creation (closing the "declaration doesn't create the dataset" class pre-deployment), snapshot + prune behavior under the chosen tool, and the parameterized per-service restore flow (D-12). This seeds the standing todo of converting smoketests into NixOS integration tests.
- **D-15 (carries old D-08):** **Fail-closed smoketests** in `scripts/smoketests/backup/` (`all.sh` + `test-*.sh`), reached through `scripts/smoketests/ser8/all.sh` (the documented convention; `deploy.yaml` itself needs no change): snapshots fresher than 26 h on BOTH source and replica, last verify run succeeded, manifest complete and matching the declared coverage set, spot `integrity_check` on one snapshot-read file. Absent artifact, unreachable host, or unparseable manifest is a FAILURE, never a skip (recorded repo sore point: five existing always-pass smoketests).
- **D-16 (carries old D-05, extended):** Deletions this phase (replace-don't-deprecate): `modules/servers/backup.nix` + its import in `modules/servers/default.nix`; the inert `services.zfs.autoSnapshot` block in `hosts/ser8/configuration.nix`; the dead `/var/lib/docker` impermanence entry; the empty `/var/lib/private/prowlarr` leftover; the stale `*.reset-bak-20260822` files (Homebox, Donetick); the Jellyfin tarball directory (D-07). The legacy `backup/backups` dataset (`dedup=on`) is left alone after a contents check.
- **D-17 (carries old D-14's amendment duty, extended):** The planner amends requirement/roadmap wording to match the pivot (same pattern as Phase 13's D-04 requirement edits): BKP-01 (the dedup-off dataset on the backup pool is the **replication target**), BKP-02 (Mealie covered by snapshot + the generic pg dump; images are in the snapshot), BKP-03 (forbid **non-atomic live file copies**; atomic snapshot + snapshot-read `integrity_check` is the mechanism), BKP-04 (correct paths: `server-files/account.sqlite`; `user-files/` contains live SQLite + blobs - whole-state snapshot subsumes), BKP-07 (coverage = everything persisted, not a named app list).

### Claude's Discretion

- Child dataset naming/layout and which services get child datasets in this phase vs riding in the parent (D-02).
- Snapshot naming scheme, manifest format, digest composition, pg dump location within the persisted tree.
- Receive-side dataset layout and property overrides on the backup pool.
- Exact requirement/roadmap amendment wording (D-17).
- Whether Mosquitto gets a child dataset or a plain persistence entry (D-08).
- Ordering/dependency details between dump unit, snapshot, send, and verify under the chosen tool's hook model.

### Deferred Ideas (OUT OF SCOPE)

- **Off-host/remote backup with indefinite retention** - out of scope this milestone. Borg/borgmatic (or restic/Kopia) become the interesting candidates HERE, pushing to non-ZFS storage from snapshot mounts; with ZFS on both ends on-site, snapshot+send dominates and borgmatic's repo format buys nothing now. Revisit at the remote phase.
- **Hourly snapshots of persist (oops-protection tier)** - under the chosen policy tool this becomes roughly one more policy line, but it is still its own decision (snapshot pinning behavior, alert tuning); not smuggled into this phase.
- **Automated periodic test-restore on a schedule** - the VM restore suite (D-12/D-14) covers regression; a scheduled production-artifact drill remains deferred until the manual drills prove the paths.
- **`media/data@verified` snapshot destruction** - Phase 13 leftover, 32.9 GB pinned as of 2026-08-26, operator manual action (live-host mutation). **Status update: this snapshot no longer exists on ser8 as of 2026-08-26 17:35 PDT** (`zfs list -t snapshot` returns only `rpool/local/root@blank` and `rpool/safe/persist@pre-26.05-2026-08-17T085547Z`). The operator has already destroyed it.
- **Rationalizing the legacy `backup/backups` dataset (`dedup=on`)** - left alone per D-16 after a contents check.
- **Age-based cleanup timer inside the downloads quota** - carried from Phase 13; best after Phase 15 (Nixflix owns the import flow).
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description (current wording; D-17 amends) | Research support |
|----|-------------------------------------------|------------------|
| BKP-01 | A nightly backup job on ser8 writes to a dedup-off dataset on the backup pool | `backup` pool root has `dedup=off` inherited (live 2026-08-26); 21.1 T free. Receive-side dataset shape and properties recommended in *Architecture Patterns -> Pattern 3*; the "declaration does not create the dataset" trap is *Pitfall 1*. |
| BKP-02 | Mealie backup captures pg_dump plus the recipe image/upload directory | `/var/lib/mealie` is a bind mount from `rpool/safe/persist` (live `findmnt`), so it rides in the recursive snapshot. The generic pg dump job discovers `mealie` from `pg_database` (live: `postgres`, `template1`, `template0`, `mealie`). See *Code Examples -> generic pg dump*. |
| BKP-03 | SQLite-backed services are backed up via `sqlite3 .backup`/`VACUUM INTO` with `PRAGMA integrity_check`, never a raw copy | Amended by D-17. Mechanism is now atomic snapshot plus snapshot-read `integrity_check`. The non-obvious part is *how* to read a WAL SQLite file out of a read-only snapshot correctly - see *Pitfall 6* and *Code Examples -> generic verify walk*. |
| BKP-04 | Actual backup captures `account.sqlite` plus the entire `user-files/` blob tree | Path correction carried forward: `account.sqlite` lives at `/var/lib/actual/server-files/account.sqlite` (journal mode `delete`, re-verified live 2026-08-26). Whole-state snapshot subsumes both paths. |
| BKP-05 | A Mealie restore into a scratch instance is demonstrated and documented | VM harness template found in the pinned nixpkgs (`nixos/tests/sanoid.nix`) and disko (`lib/tests.nix` `makeDiskoTest`). See *Architecture Patterns -> Pattern 5* and *Validation Architecture*. |
| BKP-06 | A restore of one SQLite service and of Actual is demonstrated | Donetick locked by D-12 (`delete` journal mode, re-verified live). Restore tool shape in *Pattern 4*. |
| BKP-07 | Media application state (Sonarr, Radarr, Prowlarr, Jellyfin, Bazarr, SABnzbd, NZBGet) is covered by the nightly engine using the correct method per state store | Amended by D-17 to "everything persisted". All seven are among the 25 live bind mounts from `rpool/safe/persist` (verified `findmnt`), so a recursive snapshot of that dataset covers them by construction. See *Runtime State Inventory*. |
</phase_requirements>

## Summary

The pivot is well supported by what is actually on the box, and one tool choice falls out of the evidence rather than out of preference.

**sanoid + syncoid, not zrepl.** Three findings decide it, all read from source this session rather than from docs. First, sanoid can take a genuinely atomic recursive snapshot: `recursive = "zfs"` sets `zfs_recursion`, and the snapshot call is literally `system($zfs, "snapshot", "-r", "$snap")` - one TXG across parent and every child. Upstream zrepl snapshots each filesystem separately; making them simultaneous is an open feature request (zrepl issue #251), and the fork that implements it is not what the pinned nixpkgs packages. D-02's whole design rests on parent-plus-children atomicity, so this is disqualifying for zrepl as packaged. Second, sanoid's "is a snapshot due" test is derived from the pool's own state, not from a stamp file: `if ( $newestage > $maxage )` where `$maxage` is now minus the most recent preferred wall-clock time. That means a missed 03:00 is taken on the first sanoid run after boot, with no dependence on `/var/lib/systemd/timers` - it dissolves the `Persistent=true` gap that D-05 flags, rather than working around it. zrepl's `cron` snapshotter has no equivalent catch-up, and its `periodic` snapshotter cannot be pinned to 03:00. Third, sanoid exposes `pre_snapshot_script` / `post_snapshot_script` as first-class NixOS options, and the pinned nixpkgs ships an upstream VM test (`nixos/tests/sanoid.nix`) that exercises sanoid and syncoid together against real ZFS pools on virtio disks - that test is the ready-made skeleton for D-14's harness.

zrepl's two real advantages are cheaply replaceable here. Its native Prometheus endpoint is unnecessary because ser8's node_exporter **already has the textfile collector enabled and scraping cleanly** (`node_scrape_collector_success{collector="textfile"} 1`, `node_textfile_scrape_error 0`, live 2026-08-26) - this corrects the first pass's claim that the collector was absent; only `--collector.textfile.directory=` needs setting. Its single-job both-side pruning is replaced by a second sanoid section over the replica with `autosnap = no; autoprune = yes;`, which is the documented sanoid/syncoid pattern and is one config block.

**The churn estimate can be tightened from a live measurement rather than left as a range.** `zfs get -Hp written@pre-26.05-2026-08-17T085547Z rpool/safe/persist` returns `9704439808` bytes written in the 9.4 days since that snapshot. Of that, 9.0 GB is the five Jellyfin activation tarballs created on 2026-08-25 (8.4 GB still live). Non-tarball churn is therefore roughly 0.7 GB over 9.4 days, about **75 MB/day**, which puts 30 nightly snapshots at **~2.2 GB** on rpool once D-07's tarball deletion lands - comfortably below CONTEXT's 5-15 GB estimate, and the estimate can be confirmed with one week of `written@` sampling rather than guessed.

**Two mechanics are more subtle than they look and are where planning effort belongs.** The first is the receive side: on Linux the `mount` permission cannot be delegated at all, so syncoid's `--no-privilege-elevation` receive must use `zfs recv -u` or it fails outright; and because `mountpoint` travels in the send stream, a replica of `rpool/safe/persist/jellyfin` would carry `mountpoint=/var/lib/jellyfin` and could shadow live data if ever mounted. `--recvoptions "u x mountpoint"` fixes both (verified against syncoid's own parser: `-x` takes a value, and `getoptionsline(\@recvoptions, ('h','o','x','u','v'))` whitelists `u` and `x`). The second is snapshot-read SQLite verification: opening a WAL database from a read-only snapshot path cannot create the `-shm` file, so the naive `sqlite3 /persist/.zfs/snapshot/.../x.db "PRAGMA integrity_check"` either errors or, with `immutable=1`, silently skips the WAL and validates a stale main file. The correct generic move is to copy the `db`/`-wal`/`-shm` triple out of the snapshot into scratch and open it read-write, which replays the WAL - that is exactly the crash-recovery path the whole architecture claims, so the verify job proves the claim instead of assuming it.

**Primary recommendation:** `services.sanoid` with `recursive = "zfs"` on `rpool/safe/persist` (`daily = 30`, every other period explicitly `0`, `daily_hour = 3`, `daily_min = 0`, `interval = "hourly"`), `services.syncoid` with one local-to-local command to `backup/persist-replica` using `commonArgs = [ "--no-sync-snap" ]` and `recvOptions = "u x mountpoint"`, a second sanoid section over the replica for receive-side pruning, an independent `backup-pgdump.service` pulled in by `Wants=`/`After=` on `sanoid.service`, and an independent `backup-verify.service` at 03:30 that discovers datasets and SQLite files generically, writes the manifest, stamps the textfile metrics, and mails the digest.

## Architectural Responsibility Map

| Capability | Primary tier | Secondary tier | Rationale |
|------------|-------------|----------------|-----------|
| Atomic point-in-time capture of all persisted state | ZFS (kernel, one TXG) | - | Only the filesystem can freeze parent and children at a single instant. No userspace orchestration can approximate `zfs snapshot -r`. |
| Snapshot scheduling and retention policy | sanoid (ser8) | systemd timer | sanoid is the retention authority per D-04. The timer only wakes it; sanoid decides from pool state whether a period is due. |
| Off-device durability | syncoid `zfs send`/`recv` -> `backup` pool | ZFS RAID-Z2 | An `rpool` snapshot dies with the NVMe. Replication is the actual backup; the snapshot is the consistency mechanism. |
| Portable PostgreSQL representation | `pg_dump -Fc` inside the snapshotted tree | ZFS snapshot | A crash-consistent PGDATA copy is only restorable into the same major version with the same binaries. The dump decouples that, and riding inside the snapshot means it inherits retention for free. |
| Structural corruption detection | verify job reading `.zfs/snapshot` (ser8) | - | Must read the snapshot, never the live file, so the thing verified is the thing that would be restored. |
| Bit-rot detection | ZFS scrub (existing `zfs-scrub.timer`) | - | Already covered fleet-wide; deliberately not this phase's job. |
| Loud failure notification | systemd `OnFailure=` -> msmtp `sendmail` (ser8) | node_exporter `systemd` collector | The mail path already works for ZED. `node_systemd_unit_state{state="failed"}` is already exported and needs no new metric. |
| Silent never-ran detection | Prometheus (firebat) | node_exporter textfile (ser8) | Only an external observer sees absence. The collector is already enabled; only a directory flag is missing. |
| Per-service granularity | ZFS child datasets under `rpool/safe/persist` | impermanence | Granularity is opt-in; the parent snapshot guarantees coverage whether or not a service is registered. |
| Restore execution | one parameterized shell tool (ser8 + VM) | `hosts/ser8/backup/README.md` | D-11. The drills execute the tool, so the tool is the tested artifact and the runbook is its index. |
| Pre-deployment layout verification | `makeDiskoTest` (disko) | `checks.x86_64-linux.*` | Proves the disko declarations would recreate the dataset tree from scratch, which activation never does. |
| Pre-deployment behavior verification | `runNixOSTest` with real ZFS on virtio disks | - | Snapshot, prune, replicate, and per-service restore are all testable in a VM against real ZFS. |
| Post-deployment verification | `scripts/smoketests/backup/` | `scripts/smoketests/ser8/all.sh` | Asserts live outcomes (real freshness on both source and replica, real manifest) the VM cannot. |

## Standard Stack

Two new packages enter the closure; both come from the pinned `nixpkgs` input, both have first-party NixOS modules, and both are covered by an upstream nixpkgs VM test.

### Core

| Tool | Version | Purpose | Why standard |
|------|---------|---------|--------------|
| `sanoid` | 2.3.0 [VERIFIED: `pkgs/by-name/sa/sanoid/package.nix:21` `version = "2.3.0";`] | Snapshot policy, atomic recursive snapshots, pruning on both source and replica | The de facto ZFS snapshot policy tool. `services.sanoid` is a mature NixOS module with a maintainer and an upstream VM test. State-derived scheduling makes it correct across the impermanence rollback. |
| `syncoid` | ships in the same `sanoid` derivation [VERIFIED: `/nix/store/52pp96l26x1n086d3jhzf7ysy744q1k3-sanoid-2.3.0/bin/{sanoid,syncoid,findoid}`] | Incremental `zfs send`/`recv` to the backup pool, resume tokens, bookmarks | `services.syncoid` handles `zfs allow`/`unallow` around every run, supports local-to-local, and defaults to resumable receives. |
| OpenZFS | `zfs-2.4.3-1` / `zfs-kmod-2.4.3-1` [VERIFIED: `zfs version` on ser8, 2026-08-26] | Snapshots, send/recv, bookmarks, `.zfs/snapshot` | Already the platform. 2.4.x has resume tokens, bookmarks, and `zfs recv -x`. |
| `sqlite3` | 3.51.2, `/run/current-system/sw/bin/sqlite3` [VERIFIED: `command -v` on ser8] | `PRAGMA integrity_check` / `quick_check` during verify | BKP-03 names it. Runs against a scratch copy of the snapshot triple, not the live file. |
| `pg_dump` / `pg_dumpall` / `pg_restore` | PostgreSQL 17, `/run/current-system/sw/bin/pg_dump` [VERIFIED: `command -v` on ser8] | Generic per-database custom-format dumps and `--list` verification | `-Fc` is the only format supporting selective restore and cheap `--list` verification. |
| `prometheus-node-exporter` textfile collector | 1.11.1, **already enabled and scraping** [VERIFIED: `curl localhost:9100/metrics` on ser8 returns `node_scrape_collector_success{collector="textfile"} 1` and `node_textfile_scrape_error 0`] | Snapshot/replication/verify freshness metrics | The documented way to get batch-job state into a pull-based system. Only the directory flag is missing. |
| `msmtp` `sendmail` wrapper | `/run/wrappers/bin/sendmail` [VERIFIED: `ZED_EMAIL_PROG="/run/wrappers/bin/sendmail"` in `/etc/zfs/zed.d/zed.rc` on ser8] | `OnFailure=` mail and the nightly digest | Already the ZED mail path to `catgrep@sudomail.com`. One mail mechanism fleet-wide. |

### Supporting

| Tool | Source | Purpose | When to use |
|------|--------|---------|-------------|
| `disko` `testLib.makeDiskoTest` | disko flake input, `lib/tests.nix:72` | Prove the disko dataset declarations create the intended layout from scratch | D-14's layout test. Takes a `disko-config`, runs disko in an installer VM, boots the result, runs `extraTestScript`. |
| `pkgs.testers.runNixOSTest` | pinned nixpkgs | Snapshot/prune/replicate/restore behavior tests | D-14's behavior tests; first `checks` output in this flake. |
| `pkgs.parted` | pinned nixpkgs | Partitioning the scratch virtio disk inside the test VM | Required by the upstream `nixos/tests/sanoid.nix` pattern. |
| `zstd` | already in ser8's system profile | Optional extra compression | `pg_dump -Fc` already compresses; on an lz4 dataset a second pass is not worth it. Mentioned only to close the question. |

### Alternatives considered

| Instead of | Could use | Trade-off |
|------------|-----------|-----------|
| sanoid + syncoid | **zrepl 0.7.0** (`services.zrepl`, in pinned nixpkgs [VERIFIED: `pkgs/by-name/zr/zrepl/package.nix:12` `version = "0.7.0";`]) | Genuinely nicer in three ways: one daemon covers snapshot + replicate + prune-both-sides, `pruning.keep` grid rules are more expressive than sanoid's period counts, and it has a native Prometheus endpoint on `:9811`. **Rejected on atomicity**: upstream zrepl snapshots each filesystem individually; simultaneous creation is open issue #251, and the `dsh2dsh` fork that adds `zfs snapshot -r` is not what nixpkgs packages. D-02's parent-plus-children atomicity is the load-bearing property. Secondary strikes: the NixOS module is a bare freeform-YAML passthrough with no option validation, its `cron` snapshotter has no missed-run catch-up, and its `periodic` snapshotter cannot be pinned to 03:00. |
| sanoid + syncoid | **znapzend** (`nixos/modules/services/backup/znapzend.nix` present) | Mature and does both-side retention, but its plan syntax is opaque, it has no pre/post snapshot hook comparable to sanoid's, and the NixOS module has less community mileage than `services.sanoid`. No advantage that offsets a third tool to learn. |
| sanoid + syncoid | **hand-rolled `zfs snapshot -r` + `zfs send -i` units** | Would be perhaps 120 lines. Rejected by D-04, and correctly: the hard parts are prune-safety (never delete the newest), incremental base selection after a partial send, resume-token handling, and catch-up. sanoid gets all four right and is CI-tested upstream. |
| `zfs recv` into a mounted replica | `zfs recv -u` + `-x mountpoint` | Not really an alternative - on Linux the `mount` permission cannot be delegated, so an unprivileged receive that tries to mount fails. `-u` is mandatory, not optional. |
| textfile collector | zrepl's native `:9811` endpoint | Moot once zrepl is rejected. The textfile collector is already live on ser8. |
| textfile collector | Prometheus Pushgateway | Pushgateway exists for ephemeral cross-host jobs and has well-known staleness semantics problems. Wrong tool for a timer on a scraped host. |
| snapshot + send | **borgmatic / restic / Kopia** | Explicitly deferred by CONTEXT to the future off-host phase. With ZFS on both ends on-site, snapshot+send strictly dominates: no chunking, no repo format, no dedup index, and restores need no tooling at all. |

**Installation:**

```nix
# hosts/ser8/backup/default.nix - no explicit environment.systemPackages needed;
# both modules pull their own package.
services.sanoid.enable = true;
services.syncoid.enable = true;
```

**Version verification (this session):**

```bash
# pinned nixpkgs input: github:NixOS/nixpkgs/nixos-26.05 @ e4bae1bd10c9c57b2cf517953ab70060a828ee6f
grep version /nix/store/5nkggxpr2qy7v4z4b7x2056a4wsgrgy3-source/pkgs/by-name/sa/sanoid/package.nix   # 2.3.0
grep version /nix/store/5nkggxpr2qy7v4z4b7x2056a4wsgrgy3-source/pkgs/by-name/zr/zrepl/package.nix   # 0.7.0
nix build .#nixosConfigurations.ser8.pkgs.sanoid   # /nix/store/52pp96...-sanoid-2.3.0, from cache.nixos.org
```

## Package Legitimacy Audit

This phase installs no packages from a mutable registry.
Both new packages are nixpkgs attribute paths resolved from a locked flake input by content hash, and both were built from `cache.nixos.org` this session.

| Package | Registry | Provenance | Verdict | Disposition |
|---------|----------|-----------|---------|-------------|
| `sanoid` (provides `sanoid`, `syncoid`, `findoid`) | nixpkgs `e4bae1bd10c9c57b2cf517953ab70060a828ee6f` | `pkgs/by-name/sa/sanoid/package.nix` read this session; derivation realised as `/nix/store/52pp96l26x1n086d3jhzf7ysy744q1k3-sanoid-2.3.0`; upstream `github.com/jimsalterjrs/sanoid` at `rev = "v2.3.0"` | OK | Approved |
| `zrepl` | nixpkgs same rev | `pkgs/by-name/zr/zrepl/package.nix` read this session | OK | **Not adopted** (see Alternatives) |
| `parted` | nixpkgs same rev | Referenced by upstream `nixos/tests/sanoid.nix` | OK | Approved, test-only |
| `sqlite3`, `pg_dump`, `pg_dumpall`, `pg_restore`, `msmtp`, `zstd`, `jq` | n/a | Already in ser8's system closure (`command -v`, 2026-08-26) | OK | Already installed |

**Packages removed due to SLOP verdict:** none.
**Packages flagged as suspicious:** none.

No slopsquatting surface exists: nixpkgs attribute paths resolve from a locked flake input by content hash, not from a mutable name registry.

## Architecture Patterns

### System architecture diagram

```
                       ser8 (source of truth)
  ┌────────────────────────────────────────────────────────────────────┐
  │                                                                    │
  │  PostgreSQL 17 ──────┐                                             │
  │  (catalog query)     │                                             │
  │                      ▼                                             │
  │            backup-pgdump.service        (Type=oneshot, root)       │
  │            pg_dumpall --globals-only                               │
  │            pg_dump -Fc <each non-template db>                      │
  │                      │  writes into the persisted tree             │
  │                      ▼                                             │
  │            /persist/var/lib/backup-dumps/*.dump                    │
  │                      │                                             │
  │                      │  Wants= / After=                            │
  │                      ▼                                             │
  │            sanoid.service   (timer: hourly; decides from pool state│
  │                              whether the 03:00 daily is due)       │
  │                      │                                             │
  │                      │  zfs snapshot -r rpool/safe/persist@autosnap_..._daily
  │                      ▼                                             │
  │   ┌──────────────────────────────────────────────┐                 │
  │   │ rpool/safe/persist            (parent: catch-all)              │
  │   │   ├── rpool/safe/persist/jellyfin  -> /var/lib/jellyfin        │
  │   │   ├── rpool/safe/persist/hass      -> /var/lib/hass            │
  │   │   ├── rpool/safe/persist/<svc>     -> /var/lib/<svc>           │
  │   │   └── (unregistered state stays in the parent)                 │
  │   └──────────────────────────────────────────────┘                 │
  │                      │                        │                    │
  │        zfs send -I   │                        │  read-only walk    │
  │                      ▼                        ▼                    │
  │            syncoid-*.service          backup-verify.service        │
  │            zfs recv -u -x mountpoint  (timer 03:30)                │
  │                      │                 ├─ newest daily snap fresh? │
  │                      │                 ├─ copy db/-wal/-shm to     │
  │                      │                 │  scratch, integrity_check │
  │                      │                 ├─ pg_restore --list dumps  │
  │                      │                 ├─ write MANIFEST           │
  │                      │                 ├─ write *.prom textfile    │
  │                      │                 └─ compose digest -> sendmail│
  │                      ▼                                             │
  │   ┌──────────────────────────────────────────────┐                 │
  │   │ backup/persist-replica  (canmount=noauto,     │                │
  │   │   readonly=on, dedup=off inherited)           │                │
  │   │   └── mirrors the source tree; snapshots      │                │
  │   │       browsable at .zfs/snapshot/<name>/      │                │
  │   └──────────────────────────────────────────────┘                 │
  │                      ▲                                             │
  │        second sanoid section (autosnap=no, autoprune=yes)          │
  │                                                                    │
  │  node_exporter :9100 ──── textfile dir ──┐                         │
  └──────────────────────────────────────────┼─────────────────────────┘
                                             │ scrape
                                             ▼
                       firebat: Prometheus rule group `homelab`
                       BackupSnapshotStale / BackupReplicaStale /
                       BackupVerifyStale  (each `... or absent(...)`)
                                             │
                                             ▼
                                Alertmanager -> email

  Restore path (D-11), same three steps for every service:
      backup-restore <svc> [--from source|replica] [--snapshot N] [--force] [--rollback]
          stop unit  ->  replace state from .zfs/snapshot  ->  start unit
```

### Recommended project structure

```
hosts/ser8/backup/
├── default.nix          # the one attrset of covered services; imports the rest
├── datasets.nix         # child dataset -> fileSystems + tmpfiles, generated from the attrset
├── policy.nix           # services.sanoid + services.syncoid configuration
├── dump.nix             # backup-pgdump.service (generic, catalog-driven)
├── verify.nix           # backup-verify.service + timer, manifest, digest, metrics
├── restore/
│   └── backup-restore   # the one parameterized tool (bash, set -euo pipefail)
└── README.md            # runbook indexing the tool; no planning terminology

scripts/smoketests/backup/
├── all.sh               # added to TESTS in scripts/smoketests/ser8/all.sh
├── test-snapshot-freshness.sh
├── test-replica-freshness.sh
├── test-verify-last-run.sh
├── test-manifest-coverage.sh
└── test-metrics.sh

tests/
├── backup-layout.nix    # disko makeDiskoTest over a reduced rpool config
└── backup-behavior.nix  # runNixOSTest: snapshot, prune, replicate, restore
```

### Pattern 1: sanoid policy that actually means "30 nightly, nothing else"

The single most important gotcha in the whole tool: **every period the NixOS module leaves `null` falls through to sanoid's shipped `[template_default]`, which is not empty.**
Verbatim from `sanoid.defaults.conf` in the built package:

```
autoprune = yes
frequently = 0
hourly = 48
daily = 90
weekly = 0
monthly = 6
yearly = 0
```
[VERIFIED: `/nix/store/52pp96l26x1n086d3jhzf7ysy744q1k3-sanoid-2.3.0/etc/sanoid/sanoid.defaults.conf`]

and

```
# daily - at 23:59 (most people expect a daily to contain everything done DURING that day)
daily_hour = 23
daily_min = 59
```
[VERIFIED: same file]

The NixOS module defaults `hourly`, `daily`, `monthly`, `yearly` to `null` and drops null keys from the generated INI [VERIFIED: `nixos/modules/services/backup/sanoid.nix:27-47` `default = null;`, and `:158-166` `if v == null then ""`].
So an under-specified policy silently produces 48 hourlies, 90 dailies, and 6 monthlies at 23:59.
Every period must be stated explicitly:

```nix
services.sanoid = {
  enable = true;
  # Run often; sanoid decides from pool state whether the daily is due.
  interval = "hourly";

  templates.persist = {
    autosnap = true;
    autoprune = true;
    frequently = 0;
    hourly = 0;
    daily = 30;          # 30-nightly sliding window
    weekly = 0;
    monthly = 0;
    yearly = 0;
    daily_hour = 3;      # freeform passthrough; overrides the 23:59 default
    daily_min = 0;
    script_timeout = 0;  # shipped default is 5 SECONDS
  };

  datasets."rpool/safe/persist" = {
    use_template = [ "persist" ];
    recursive = "zfs";   # -> zfs snapshot -r, one TXG across parent + children
  };

  # Receive-side retention: sanoid never snapshots here, only prunes.
  templates.replica = {
    autosnap = false;
    autoprune = true;
    frequently = 0;
    hourly = 0;
    daily = 90;          # longer on the backup pool; planner locks the number
    weekly = 0;
    monthly = 0;
    yearly = 0;
  };
  datasets."backup/persist-replica" = {
    use_template = [ "replica" ];
    recursive = "zfs";
  };
};
```

Retention semantics, verbatim from `sanoid`'s prune routine:

```perl
# if we say "daily=30" we really mean "don't keep any dailies more than 30 days old", etc
my $maxage = ( time() - $config{$section}{$type} * $period );
# but if we say "daily=30" we ALSO mean "don't get rid of ANY dailies unless we have more than 30".
my $minsnapsthistype = $config{$section}{$type};
```
[VERIFIED: `/nix/store/52pp96l26x1n086d3jhzf7ysy744q1k3-sanoid-2.3.0/bin/.sanoid-wrapped`, `sub prune_snapshots`]

Both conditions must hold before a snapshot is destroyed, so `daily = 30` is an age window with a hard floor of 30 - it cannot over-prune after an outage.

**Safety property worth stating in the plan:** sanoid only ever considers snapshots whose names match `^autosnap` and end in a period suffix:

```perl
my ($fs,$snapname,$snapdate) = ($snap =~ m/(.*)\@(.*ly)\t*creation\t*(\d*)/);
...
if ($snapname =~ /^autosnap/) {
```
[VERIFIED: same file, `sub getsnaps`]

`rpool/local/root@blank` (the impermanence rollback anchor that `scripts/smoketests/ser8/test-zfs-health.sh` guards) and `rpool/safe/persist@pre-26.05-2026-08-17T085547Z` are therefore structurally immune to sanoid pruning.

Snapshot naming is `autosnap_<sortable>_<type>`:

```perl
my $snapname = "autosnap_$datestamp{'sortable'}_$type";
```
[VERIFIED: same file, line 619]

### Pattern 2: child dataset migration under impermanence

D-02's target shape, declared in `hosts/ser8/disko-config.nix` alongside the existing `"safe/persist"` block:

```nix
"safe/persist" = {
  type = "zfs_fs";
  options = { mountpoint = "legacy"; };
  mountpoint = "/persist";
};
# one per covered service, generated from the backup module's attrset
"safe/persist/jellyfin" = {
  type = "zfs_fs";
  options = { mountpoint = "legacy"; };
  mountpoint = "/var/lib/jellyfin";
};
```

The existing parent block is verbatim:

```nix
          "safe/persist" = {
            type = "zfs_fs";
            options = {
              mountpoint = "legacy";
            };
            mountpoint = "/persist";
          };
```
[VERIFIED: `hosts/ser8/disko-config.nix:212-218`]

disko turns the disko-level `mountpoint` attribute into a NixOS `fileSystems` entry automatically:

```nix
    _config = lib.mkOption {
      internal = true;
      readOnly = true;
      default =
        lib.optional (config.options.mountpoint or "" != "none" && config.options.canmount or "" != "off")
          {
            fileSystems.${config.mountpoint} = {
              device = "${config._name}";
              fsType = "zfs";
```
[VERIFIED: `disko/lib/types/zfs_fs.nix:166-178`, flake input at `/nix/store/w2c23ykc12mswlg8hrrjzb5gv9gvkzwq-source`]

So declaring the child dataset with `options.mountpoint = "legacy"` and disko `mountpoint = "/var/lib/jellyfin"` yields `fileSystems."/var/lib/jellyfin" = { device = "rpool/safe/persist/jellyfin"; fsType = "zfs"; options = [ "defaults" ]; };` for free - the same mechanism that mounts `/persist` today.

**Why D-02's literal form (mount at `/var/lib/<svc>`, drop the impermanence entry) is also the safer form.**
The tempting lower-churn variant is to mount the child dataset at `/persist/var/lib/<svc>` and keep the impermanence bind mount.
That variant has a real ordering hazard: impermanence's stage-2 bind mounts are emitted as

```nix
                mkBindMount = { dirPath, persistentStoragePath, hideMount, allowTrash, ... }: {
                  wantedBy = [ "local-fs.target" ];
                  before = [ "local-fs.target" ];
                  where = concatPaths [ "/" dirPath ];
                  what = concatPaths [ persistentStoragePath dirPath ];
                  unitConfig.DefaultDependencies = false;
                  type = "none";
```
[VERIFIED: `impermanence/nixos.nix:290-303`, flake input at `/nix/store/3ib4ns4q84wcjfqim5wc0jsjw7v18lpd-source`]

with `DefaultDependencies = false` and no `RequiresMountsFor=` on the `what` path.
Bind-mounting a path that is itself a separate mount is then a race: if the bind unit wins, the service sees the pre-mount empty directory.
Mounting the dataset directly at `/var/lib/<svc>` and deleting the impermanence entry removes the bind layer entirely and the hazard with it.
Take the locked form.

**Per-service cutover sequence** (each step is a live-host mutation and needs the operator checkpoint):

```bash
SVC=jellyfin
DS=rpool/safe/persist/$SVC

sudo systemctl stop "$SVC.service"
sudo zfs create -u -o mountpoint=legacy "$DS"          # -u: do not mount yet
sudo mkdir -p /mnt/migrate && sudo mount -t zfs "$DS" /mnt/migrate
sudo cp -a --reflink=auto "/persist/var/lib/$SVC/." /mnt/migrate/
sudo diff -rq "/persist/var/lib/$SVC" /mnt/migrate      # must be empty
sudo umount /mnt/migrate
sudo umount "/var/lib/$SVC"                             # drop the old impermanence bind
sudo mount -t zfs "$DS" "/var/lib/$SVC"
sudo systemctl start "$SVC.service"
# only after the service is verified healthy:
sudo mv "/persist/var/lib/$SVC" "/persist/var/lib/$SVC.pre-dataset-$(date +%Y%m%d)"
```

Notes that matter:

- `zfs create -u` mirrors what disko itself does, and for the same reason. disko's create script says so verbatim: `# -u prevents mounting newly created datasets, which is important to prevent accidental shadowing of mount points since (create order != mount order)` [VERIFIED: `disko/lib/types/zfs_fs.nix:70-73`].
- The old `/persist/var/lib/<svc>` directory is **not** removed by dropping the impermanence entry. It must be moved aside explicitly, and only after the service is proven healthy on the new dataset. Leaving it in place doubles the space and silently doubles snapshot churn.
- The corresponding `environment.persistence."/persist".directories` entry and any `d /persist/var/lib/<svc> ...` tmpfiles rule must be removed in the same change; the `d /var/lib/<svc> <mode> <owner> <group>` rule takes over. Several already exist as duplicates (for example `"d /var/lib/jellyfin 0755 jellyfin media -"` sits next to `"d /persist/var/lib/jellyfin 0755 jellyfin media -"` in `hosts/ser8/impermanence.nix`).
- The disko declaration is a second, independent task from the imperative create. See *Pitfall 1*.
- Services that use `StateDirectory=` are safe: NixOS `fileSystems` entries are mounted before `local-fs.target`, and units are `After=local-fs.target` by default.
- `zfs snapshot -r rpool/safe/persist` covers parent and children in one TXG regardless of where the children are mounted, so the parent stays the coverage guarantee exactly as D-02 intends.

### Pattern 3: receive-side properties so a replica can never shadow live data

```nix
services.syncoid = {
  enable = true;
  commonArgs = [ "--no-sync-snap" ];   # sanoid owns snapshot creation
  interval = "hourly";                 # matches sanoid; a missed send catches up
  commands."rpool/safe/persist" = {
    target = "backup/persist-replica";
    recursive = true;
    recvOptions = "u x mountpoint";    # -> zfs recv -u -x mountpoint
  };
};
```

Three verified facts drive this:

1. **`-u` is mandatory, not stylistic.** The syncoid unit always passes `--no-privilege-elevation` [VERIFIED: `nixos/modules/services/backup/syncoid.nix:389`], so the receive runs as the unprivileged `syncoid` user with only delegated permissions. On Linux `mount` cannot be delegated at all - `mount(8)` restricts global-namespace changes to root - so any receive that would mount the new dataset fails. `zfs recv -u` leaves it unmounted and the problem disappears. [CITED: https://openzfs.github.io/openzfs-docs/man/master/8/zfs-allow.8.html]
2. **`-x mountpoint` prevents shadowing.** Local dataset properties travel in the send stream. Without `-x`, `backup/persist-replica/jellyfin` inherits `mountpoint=/var/lib/jellyfin` from its source and would mount over live data the moment anyone ran `zfs mount -a`. `-x mountpoint` makes the replica inherit from its own parent instead.
3. **The syntax is confirmed against syncoid's own parser.** `getoptionsline(\@recvoptions, ('h','o','x','u','v'))` whitelists exactly `h o x u v`, and `parsespecialoptions` treats `o`, `x`, and `X` as value-taking so `"u x mountpoint"` becomes `-u -x mountpoint`. [VERIFIED: `/nix/store/52pp96l26x1n086d3jhzf7ysy744q1k3-sanoid-2.3.0/bin/.syncoid-wrapped:908` and `sub parsespecialoptions`]

Replica dataset properties to set once, imperatively and in the disko declaration:

```bash
sudo zfs create -u -o mountpoint=/mnt/backup-replica \
                   -o canmount=noauto \
                   -o readonly=on \
                   -o "com.sun:auto-snapshot=false" \
                   backup/persist-replica
```

`canmount=noauto` keeps it out of `zfs mount -a`; `mountpoint` under `/mnt/backup-replica` means children inherit a harmless path; `readonly=on` blocks accidental writes without blocking `zfs recv` (a pool-level operation).
To browse a replica snapshot during a restore, mount the replica dataset explicitly (`zfs mount backup/persist-replica/<svc>`) and read `.zfs/snapshot/<name>/`.
`dedup` is `off` by inheritance from the `backup` pool root, satisfying BKP-01 without a local property.

Two syncoid defaults worth knowing before they surprise someone:

```perl
	if ($resume) { $recvoptions .= ' -s'; }
	...
	if (!defined $args{'no-rollback'}) { $recvoptions .= ' -F'; }
```
[VERIFIED: same file, lines 911 and 913]

Resume tokens are on by default (good; a partial multi-GB send resumes rather than restarting), and `-F` force-rollback of the target to its latest snapshot is on by default (also good on a `readonly=on` replica nobody writes to - it makes a divergent replica self-heal instead of wedging).
`--create-bookmark` is worth adding to `extraArgs`: it leaves a bookmark on the source for each sent snapshot, so the incremental chain survives the source snapshot being pruned before the next send. The upstream nixpkgs test uses exactly this flag for the sanoid-driven command [VERIFIED: `nixos/tests/sanoid.nix`, `extraArgs = [ "--no-sync-snap" "--create-bookmark" ];`].

### Pattern 4: dump before, verify after, without fighting sanoid's hardening

The obvious wiring is sanoid's `pre_snapshot_script`, and it is the wrong first choice.
The sanoid unit runs as a DynamicUser:

```nix
        User = "sanoid";
        Group = "sanoid";
        DynamicUser = true;
```
[VERIFIED: `nixos/modules/services/backup/sanoid.nix:282-284`]

so a hook cannot `sudo -u postgres pg_dump` or write into `/persist` without either a `mkForce` down-grade of the module's hardening or a polkit rule.
Both are more machinery than the problem deserves, and the shipped `script_timeout = 5` (seconds) would need raising too.

The boring wiring instead uses plain systemd ordering:

```nix
systemd.services.backup-pgdump = {
  description = "PostgreSQL logical dumps into the persisted tree";
  serviceConfig = { Type = "oneshot"; User = "postgres"; };
  onFailure = [ "backup-failure-mail@%n.service" ];
  script = /* see Code Examples */ "";
};

# Every sanoid invocation refreshes the dumps first. Wants=, not Requires=:
# a failed dump must never block the snapshot, which is still crash-consistent.
systemd.services.sanoid = {
  wants = [ "backup-pgdump.service" ];
  after = [ "backup-pgdump.service" ];
  onFailure = [ "backup-failure-mail@%n.service" ];
};
```

`Type=oneshot` means "started" equals "finished", so `After=` is a real completion barrier.
Because sanoid runs hourly and only snapshots when a period is due, the dump is at most one hour old relative to whichever snapshot is taken - including the post-outage catch-up snapshot, which is precisely the case a clock-separated 02:45 timer would miss.
Cost is 24 dumps a day of a 14 MB database; the dump lands at the same path each time, so 30 nightly snapshots pin roughly 30 copies of a few MB.

Verify runs on its own timer, ordered by the clock rather than by sanoid, because it must observe a snapshot that already exists:

```nix
systemd.timers.backup-verify.timerConfig.OnCalendar = "03:30";
systemd.services.backup-verify = {
  serviceConfig = { Type = "oneshot"; User = "root"; };
  onFailure = [ "backup-failure-mail@%n.service" ];
};
```

The verify job fails closed if the newest `rpool/safe/persist@autosnap_*_daily` is older than 26 h, which also catches "sanoid never ran" without any extra plumbing.
`OnFailure=` on a templated mail unit is the established pattern and rides the existing msmtp `sendmail` wrapper.

### Pattern 5: VM tests, using the upstream harness rather than inventing one

The pinned nixpkgs already ships a ZFS-in-a-VM test that exercises exactly this pair of services, and it uses a real virtio disk rather than loop devices:

```nix
  commonConfig =
    { pkgs, ... }:
    {
      virtualisation.emptyDiskImages = [ 2048 ];
      boot.supportedFilesystems = [ "zfs" ];
      environment.systemPackages = [ pkgs.parted ];
    };
```
[VERIFIED: `nixos/tests/sanoid.nix` in the pinned nixpkgs]

with the pool created in the test script:

```python
    source.succeed(
        "mkdir /mnt",
        "parted --script /dev/vdb -- mklabel msdos mkpart primary 1024M -1s",
        "udevadm settle",
        "zpool create pool -R /mnt /dev/vdb1",
        "zfs create pool/sanoid",
        ...
    )
```
[VERIFIED: same file]

Each node needs a distinct `networking.hostId` (the upstream test uses `"daa82e91"` and `"dcf39d36"`).
For this phase a **single node** is enough because source and target are the same host - create two pools on two `emptyDiskImages` and point syncoid at a local target, which removes the SSH key plumbing the upstream test needs.

For the layout half of D-14, disko's own harness is the right tool:

```nix
diskoLib.testLib.makeDiskoTest {
  inherit pkgs;
  name = "backup-layout";
  disko-config = ../tests/backup-layout-disko.nix;
  extraInstallerConfig.networking.hostId = "2d833f3e";
  extraSystemConfig.networking.hostId = "2d833f3e";
  extraTestScript = ''
    def assert_property(ds, property, expected_value):
        out = machine.succeed(f"zfs get -H {property} {ds} -o value").rstrip()
        assert out == expected_value, f"Expected {property}={expected_value} on {ds}, got: {out}"

    assert_property("rpool/safe/persist/jellyfin", "mountpoint", "legacy")
    machine.succeed("mountpoint /var/lib/jellyfin")
  '';
}
```
[VERIFIED: signature at `disko/lib/tests.nix:72-88`; `assert_property` helper copied verbatim from `disko/tests/zfs.nix`]

`makeDiskoTest` runs disko in an installer VM, installs a system, boots it, and then runs the assertions - which is exactly the "would the declarations recreate this from scratch?" question activation never answers.
Use a **reduced** disko config containing only `rpool` and the persist tree; ser8's real config declares seven physical disks and a full install of it in a VM is needlessly heavy.

### Anti-patterns to avoid

- **Leaving a sanoid period unset.** It does not mean "off", it means the shipped default (48/90/6). State every period.
- **`sqlite3 <snapshot-path>/x.db "PRAGMA integrity_check"`.** Read-only snapshot paths cannot host the `-shm` file a WAL database needs. See *Pitfall 6*.
- **Receiving without `-x mountpoint`.** A replica that inherits `mountpoint=/var/lib/<svc>` is a loaded gun.
- **Making the pg dump a `Requires=` of the snapshot.** A failed dump must not suppress the snapshot; the snapshot is still a complete crash-consistent image.
- **Deleting `/persist/var/lib/<svc>` in the same step as the dataset cutover.** Keep the old copy until the service is verified healthy, then move it aside, then delete.
- **A bare `time() - metric > 26*3600` alert.** Never fires on an absent series - the exact silent case D-09 exists to catch.
- **`zfs rollback` as the default restore.** It destroys every snapshot newer than the target, which on a failed restore removes the evidence and the retry options.

## Don't Hand-Roll

| Problem | Don't build | Use instead | Why |
|---------|-------------|-------------|-----|
| Deciding whether tonight's snapshot is due after an outage | A boot-time catch-up script, or `Persistent=true` plus persisting `/var/lib/systemd/timers` | sanoid's state-derived scheduling | sanoid derives due-ness from the pool, not from a stamp file: `if ( $newestage > $maxage )`. The impermanence rollback becomes irrelevant instead of being worked around. |
| Pruning to a 30-night window | A `zfs list -t snapshot \| sort \| tail -n +31 \| xargs zfs destroy` pipeline | sanoid `daily = 30` + `autoprune` | sanoid refuses to prune below the floor even when every snapshot is over-age, and only ever touches `autosnap_*` names, so the impermanence `@blank` anchor is structurally safe. The pipeline gets both wrong on its first bad day. |
| Incremental send with a correct base | `zfs send -i $(zfs list ... \| tail -2 \| head -1)` | syncoid | syncoid picks the common base, handles resume tokens (`-s` by default), creates bookmarks so a pruned source snapshot does not break the chain, and detects an in-flight receive by inspecting `ps`. |
| `zfs allow` lifecycle around a replication run | A manual `zfs allow` baked into the pool | `services.syncoid` `ExecStartPre` / `ExecStopPost` | The module grants the delegation before the run and revokes it after; the upstream test asserts `zfs allow <ds>` is empty before and after. Live check on ser8 confirms both `rpool/safe/persist` and `backup` currently have zero delegations, so this leaves no residue. |
| Getting a batch job's freshness into Prometheus | An HTTP push endpoint or Pushgateway | node_exporter textfile collector | Already enabled and scraping cleanly on ser8; Pushgateway has documented staleness-semantics problems and is meant for cross-host ephemeral jobs. |
| Detecting a failed unit | A custom polling script | `node_systemd_unit_state{state="failed"}` | The `systemd` collector is already enabled on ser8 and exports 1155 series including per-unit state. Zero new code. |
| Emailing on failure | A custom mail sender | `OnFailure=` + `/run/wrappers/bin/sendmail` | ZED already sends through that wrapper to `catgrep@sudomail.com`. A second MTA is a second thing that can silently stop working. |
| Verifying a WAL SQLite file from a snapshot | Opening the snapshot file with `immutable=1` and calling it verified | Copy the `db`/`-wal`/`-shm` triple to scratch and open read-write | `immutable=1` skips the WAL entirely and validates a stale main file - a green result that proves nothing about recent transactions. The copy-and-open path *is* the crash-recovery path being claimed. |
| Proving the disko declarations work | Reading them carefully | `disko lib/tests.nix` `makeDiskoTest` | Activation never runs disko's create script, so declarations drift undetected. The harness installs and boots from them. |

**Key insight:** with a snapshot-based design, almost all remaining hand-rolled code lives on the *consumption* side - discovery, verification, manifest, restore. That is exactly where the operator's framing puts it, and it is where the code should be reviewed hardest.

## Runtime State Inventory

Live-verified on ser8 (`bdhill@192.168.68.65`) on 2026-08-26 via passwordless-sudo SSH.
Inventory rows carried forward from the first pass are marked; everything else was re-probed this session.

### The coverage universe: 25 bind mounts from `rpool/safe/persist`

`findmnt -n -o TARGET,SOURCE,FSTYPE | grep "safe/persist"` returns exactly these targets [VERIFIED: live 2026-08-26]:

```
/var/lib/bazarr   /var/lib/dhcp   /var/lib/NetworkManager   /etc/NetworkManager/system-connections
/var/lib/actual   /var/lib/docker /etc/machine-id           /etc/ssh/ssh_host_ed25519_key(.pub)
/etc/ssh/ssh_host_rsa_key(.pub)   /var/lib/donetick        /var/lib/frigate  /var/lib/hass
/var/lib/homebox  /var/lib/jellyfin /var/lib/mealie        /var/lib/nzbget   /var/lib/postgresql
/var/lib/private  /var/lib/prowlarr /var/lib/radarr        /var/lib/sabnzbd  /var/lib/samba
/var/lib/samba/private (nested)    /var/lib/sonarr         /var/lib/systemd/coredump
/var/lib/systemd/network           /var/lib/tailscale      /etc/nixos        /var/lib/nixos
/var/log                           /persist (the dataset itself)
```

Two corrections to the first pass:

- **Samba is a real bind mount**, not a symlink. `findmnt /var/lib/samba` returns `rpool/safe/persist[/var/lib/samba]`, with `/var/lib/samba/private` nested inside it. The `"L /var/lib/samba - - - - /persist/var/lib/samba"` tmpfiles rule in `hosts/ser8/impermanence.nix` is dead - the bind mount wins. That rule is a D-16 deletion candidate.
- **`media/data@verified` is gone.** `zfs list -t snapshot` returns only `rpool/local/root@blank` and `rpool/safe/persist@pre-26.05-2026-08-17T085547Z`. The deferred operator action is already done; 32.9 GB was released.

Everything in that list is captured by `zfs snapshot -r rpool/safe/persist` in one TXG, whether or not it has a child dataset.
That is D-02's coverage-by-default property, and it means BKP-07's named app list is satisfied structurally.

### State store inventory (carried forward, journal modes re-verified)

| Service | State store | Path | Size | Journal mode (2026-08-26) |
|---------|-------------|------|------|---------------------------|
| PostgreSQL 17 | cluster | `/var/lib/postgresql/17` | 18 MB | n/a - databases live: `postgres`, `template1`, `template0`, `mealie` [VERIFIED live] |
| Mealie | file tree + pg | `/var/lib/mealie/{recipes,users,groups,templates}` | 396 KB (carried) | n/a |
| Homebox | SQLite | `/var/lib/homebox/data/homebox.db` | 260 KB (carried) | `wal` [VERIFIED live] |
| Actual | SQLite + blobs | `/var/lib/actual/server-files/account.sqlite`, `user-files/` | 68 KB + 16 KB (carried) | `delete` [VERIFIED live] |
| Donetick | SQLite | `/var/lib/donetick/donetick.db` | 448 KB (carried) | `delete` [VERIFIED live] |
| Home Assistant | SQLite + `.storage` | `/var/lib/hass/home-assistant_v2.db` | 178 MB (carried) | `wal` [VERIFIED live] |
| Frigate | SQLite | `/var/lib/frigate/frigate.db` | 175 MB (carried) | `wal` [VERIFIED live] |
| Sonarr / Radarr / Prowlarr / Bazarr | SQLite + config | `/var/lib/{sonarr/.config/NzbDrone,radarr/.config/Radarr,prowlarr,bazarr}` | 124 / 80 / 21 / 7.5 MB [VERIFIED live `du`] | `wal` (carried) |
| Jellyfin | SQLite + trees | `/var/lib/jellyfin/{data,config,metadata,plugins,root,playlists}` | metadata 1.7 GB, data 202 MB [VERIFIED live `du`] | `wal` (carried) |
| SABnzbd | SQLite + ini | `/var/lib/sabnzbd/{sabnzbd.ini,admin/history1.db}` | 258 MB total [VERIFIED live `du`] | `delete` (carried) |
| NZBGet | conf + queue | `/var/lib/nzbget/{nzbget.conf,queue,nzb}` | 97 MB [VERIFIED live `du`] | n/a |
| Samba | TDB | `/var/lib/samba/*.tdb`, `/var/lib/samba/private/*.tdb` | ~1.4 MB [VERIFIED live `ls`] | n/a - **no special handling needed under the pivot.** An atomic snapshot captures a tdb consistently; `tdbbackup` was a pass-1 artifact of the non-atomic-copy model and is now out of scope. |
| Tailscale | node identity | `/var/lib/tailscale` | 35 KB (carried) | n/a - covered by the parent snapshot without registration, which is exactly D-02's point |

### Churn measurement (new this pass)

```
rpool/safe/persist  written                                       9704439808  -
rpool/safe/persist  written@pre-26.05-2026-08-17T085547Z          9704439808  local
rpool/safe/persist  usedbysnapshots                              11277156352  -
rpool/safe/persist  logicalused                                  27292408832  -
```
[VERIFIED: `zfs get -Hp written,written@...,usedbysnapshots,logicalused rpool/safe/persist` on ser8, 2026-08-26]

Interpretation: 9.70 GB written in the 9.4 days since 2026-08-17.
The five Jellyfin activation tarballs created on 2026-08-25 (`1793606104`, `1801491620`, `1801497765`, `1801491848`, `1801495732` bytes [VERIFIED: `ls -la /var/lib/jellyfin/backups`]) account for 9.0 GB of that.
Residual churn is therefore ~0.7 GB / 9.4 days ≈ **75 MB/day**, projecting **~2.2 GB pinned by 30 nightly snapshots** once D-07's tarball deletion lands.

Churn hotspots found, in order:

| Path | Size | Assessment |
|------|------|------------|
| `/persist/var/lib/jellyfin/backups` | 8.4 GB | Dominant. D-07 deletes it and sets `backups = false`. |
| `/persist/var/lib/jellyfin/metadata` | 1.7 GB | Large but near-static; incremental snapshot cost is small. Leave in. |
| `/persist/var/lib/sabnzbd/backup` | 258 MB | SABnzbd's own config backups. Near-static, small absolute size. Leave in - it is the free app-consistent layer D-07 keeps. |
| `/var/lib/hass/home-assistant_v2.db` | 178 MB, WAL | The real recurring driver. Recorder rewrites pages continuously; expect tens of MB per night pinned. Within budget. |
| `/var/lib/frigate/frigate.db` | 175 MB, WAL | Same class. |
| `/persist/var/lib/prowlarr/Backups` | 7.6 MB | Trivial. |
| `/persist/var/lib/bazarr/backup` | 2.9 MB | Trivial. |

No path needs a non-snapshotted child dataset. Disable-at-source handles the only case that matters.

**Measurement plan to confirm the estimate (BKP-01 sizing):** after the first nightly snapshot exists, sample daily for one week:

```bash
zfs get -Hp -o value written@$(zfs list -H -t snapshot -o name -s creation -d1 rpool/safe/persist | tail -1 | cut -d@ -f2) rpool/safe/persist
zfs get -Hp -o value usedbysnapshots rpool/safe/persist
```

The verify job's manifest should record both numbers each night, which turns the estimate into an observed series with no extra tooling.

### Not persisted - nothing to back up until D-08 lands

| Path | Finding |
|------|---------|
| `/var/lib/mosquitto` | Still not persisted. `ls -la` shows `acl-0.conf`, `passwd-0`, and a live `mosquitto.db` of 9892 bytes last written 2026-08-26 17:34 [VERIFIED live], on `rpool/local/root`, which the stage-1 rollback returns to `@blank` every boot. D-08 fixes this. Simplest form consistent with D-02: give it a child dataset `rpool/safe/persist/mosquitto` mounted at `/var/lib/mosquitto` (same generated shape as every other service) rather than a bare impermanence entry - it keeps the attrset the single source of truth. |
| `/var/lib/systemd/timers` | Still not in the persistence list. **Under sanoid this no longer matters** for snapshot scheduling, because sanoid derives due-ness from pool state. It still matters for any other `Persistent=true` timer on the host; adding it remains a cheap, correct hygiene change but is no longer load-bearing for this phase. |

### Other runtime state categories

| Category | Items found | Action required |
|----------|-------------|-----------------|
| Stored data | 11 SQLite databases (8 WAL, 3 `delete`), one PostgreSQL cluster with one app DB, 8 Samba tdbs, one non-durable mosquitto persistence file | All covered by the recursive snapshot; pg additionally by the generic dump |
| Live service config | Arr apps' own weekly backup settings remain app-side and are deliberately untouched under D-07 | None - the whole API surface is deleted from scope |
| OS-registered state | 12 systemd timers; `nixos-upgrade.timer` NEXT 04:00 daily; five `zfs-snapshot-*.timer` units firing for nothing [VERIFIED: `systemctl list-timers` 2026-08-26] | D-16 removes the `autoSnapshot` block, which removes all five timers. Snapshot is near-instant; only the first full send is long - see *Pitfall 8*. |
| ZFS delegations | `zfs allow rpool/safe/persist` and `zfs allow backup` both return empty [VERIFIED live] | Clean slate; syncoid's grant/revoke lifecycle leaves no residue |
| Secrets and env vars | No new secret is required by this phase. `ZED_EMAIL_ADDR="catgrep@sudomail.com"` and `ZED_EMAIL_PROG="/run/wrappers/bin/sendmail"` already set [VERIFIED: `/etc/zfs/zed.d/zed.rc`] | None - the pivot eliminated the only candidate new secret (Bazarr's API key) |
| Build artifacts | none relevant | - |

## Common Pitfalls

### Pitfall 1: the disko declaration does not create the dataset (carried forward, now confirmed in source)

**What goes wrong:** the child datasets and the replica dataset are declared in `hosts/ser8/disko-config.nix`, the config is activated, and nothing exists.

**Why it happens:** disko's create logic lives in `_create`, which is only run by the disko scripts (`disko`, `disko-install`), never by `nixos-rebuild switch`. The logic itself is idempotent and would even fix properties:

```
if ! zfs get type "${config._name}" >/dev/null 2>&1; then
  zfs create -up "${config._name}" ...
else
  zfs set -u ... "${config._name}"
fi
```
[VERIFIED: `disko/lib/types/zfs_fs.nix:93-116`]

but activation never invokes it. This is the recorded Phase 13 Plans 05/07 fact, now with the source-level explanation.

**How to avoid:** treat every dataset as two tasks - a declaration change and an imperative `zfs create` with properties spelled out to match - and add a `makeDiskoTest` check so the declaration half is proven independently.

**Warning signs:** `zfs list` does not show the dataset after activation; the mountpoint exists as an ordinary directory and the service silently writes into the ephemeral root.

### Pitfall 2: unset sanoid periods are not "off"

**What goes wrong:** `services.sanoid.datasets."rpool/safe/persist" = { daily = 30; autoprune = true; };` produces 48 hourly snapshots, 90 dailies at 23:59, and 6 monthlies.

**Why it happens:** the NixOS module drops null-valued keys from the generated INI, so unset periods fall through to `[template_default]` in `sanoid.defaults.conf`, which ships `hourly = 48`, `daily = 90`, `monthly = 6`, `daily_hour = 23`, `daily_min = 59`.

**How to avoid:** set `frequently`, `hourly`, `weekly`, `monthly`, `yearly` to `0` explicitly, and `daily_hour`/`daily_min` to `3`/`0`. Assert the effective policy in a smoketest by counting snapshot types, not by reading the Nix.

**Warning signs:** snapshots named `autosnap_*_hourly` or `autosnap_*_monthly` appearing; the daily snapshot timestamped 23:59 instead of 03:00.

### Pitfall 3: sanoid's shipped `script_timeout` is five seconds

**What goes wrong:** a pre- or post-snapshot hook is added, works when tested by hand, and is killed in production.

**Why it happens:** `script_timeout = 5` in `sanoid.defaults.conf`; the NixOS option documents `<=0 for infinite` [VERIFIED: `nixos/modules/services/backup/sanoid.nix:91-95`].

**How to avoid:** if hooks are used at all, set `script_timeout = 0`. The recommended architecture (Pattern 4) avoids hooks entirely, which sidesteps this and the DynamicUser problem together.

### Pitfall 4: an unprivileged `zfs receive` that tries to mount fails, always

**What goes wrong:** `syncoid-*.service` fails with a permission error on the very first run even though `zfs allow` looks correct.

**Why it happens:** the syncoid unit always passes `--no-privilege-elevation`, and on Linux the `mount` permission cannot be delegated - `mount(8)` restricts global-namespace modification to root. The module's `localTargetAllow` default lists `mount` and `mountpoint`, which on Linux are simply inert:

```nix
    localTargetAllow = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "change-key"
        "compression"
        "create"
        "mount"
        "mountpoint"
        "receive"
        "rollback"
      ];
```
[VERIFIED: `nixos/modules/services/backup/syncoid.nix:170-180`]

**How to avoid:** `recvOptions = "u x mountpoint"`. Assert it in the VM test by checking the replica dataset's `mounted` property is `no` after a successful sync.

**Warning signs:** `cannot mount ...: Insufficient privileges` in the syncoid journal; a receive that creates the dataset then errors.

### Pitfall 5: a replica can inherit `mountpoint=/var/lib/<svc>` and shadow live data

**What goes wrong:** months later somebody runs `zfs mount -a` or reboots after a property change, and `backup/persist-replica/jellyfin` mounts over `/var/lib/jellyfin`, hiding the live state behind a stale replica.

**Why it happens:** local dataset properties travel in the send stream. Once the child datasets exist with `mountpoint` set to the service path, their replicas carry it.

**How to avoid:** three independent belts - `-x mountpoint` on receive, `canmount=noauto` on the replica root, and `readonly=on` on the replica tree. Assert all three in the VM test and in a smoketest.

**Warning signs:** `zfs get -r mountpoint backup/persist-replica` showing anything under `/var/lib`.

### Pitfall 6: reading a WAL SQLite database out of a read-only snapshot

**What goes wrong:** the verify job either errors with `unable to open database file` on the WAL databases, or - worse, if `immutable=1` is used to make the error go away - reports `ok` for a database whose recent transactions were never examined.

**Why it happens:** SQLite in WAL mode needs a `-shm` shared-memory file next to the database. A `.zfs/snapshot/...` path is read-only, so it cannot be created. `file:...?immutable=1` tells SQLite the file cannot change, which makes it skip the WAL and the shm entirely - so `PRAGMA integrity_check` validates only the pre-WAL main file. Eight of the eleven live databases are WAL mode, including the two largest.

**How to avoid:** copy the triple out of the snapshot into a scratch directory and open it read-write, which replays the WAL exactly as crash recovery would:

```bash
scratch=$(mktemp -d /var/tmp/backup-verify.XXXXXX)
for ext in "" "-wal" "-shm"; do
  [ -e "$snapdb$ext" ] && cp -- "$snapdb$ext" "$scratch/db$ext"
done
sqlite3 "$scratch/db" "PRAGMA integrity_check;"   # must print exactly: ok
rm -rf -- "$scratch"
```

This is not a workaround; it is the claim under test. If the triple does not recover, the snapshot is not a usable backup and the operator needs to know tonight.

**Cost note:** `integrity_check` is roughly linear in database size. For the 178 MB Home Assistant recorder and the 175 MB Frigate database, `PRAGMA quick_check` is the pragmatic choice (page-level structure without the full cross-index verification); reserve full `integrity_check` for the small ones. Record which check was used in the manifest so the evidence is honest.

**Warning signs:** every WAL database reporting `ok` in under a second; `unable to open database file` for exactly the WAL databases.

### Pitfall 7: the freshness alert never fires because the series is absent

**What goes wrong:** the rule is `time() - backup_last_snapshot_timestamp > 26*3600`, ser8 reboots or the job never ran, the series does not exist, and the rule evaluates over an empty vector - which never fires. Exactly the silent case D-09 exists to catch. (Carried forward from the first pass; the mechanism is unchanged.)

**How to avoid:** write every staleness rule with an explicit absence arm, and put the textfile directory on persisted storage:

```yaml
- alert: BackupSnapshotStale
  expr: |
    (time() - backup_last_snapshot_timestamp_seconds > 26 * 3600)
    or
    (absent(backup_last_snapshot_timestamp_seconds) == 1)
  for: 10m
  labels:
    severity: critical
  annotations:
    summary: "No fresh persist snapshot on {{ $labels.instance }} in over 26h"
```

Three such rules are needed (snapshot, replica, verify), added to the existing `homelab` group in `modules/gateway/prometheus.nix` alongside `ZFSPoolUnhealthy` and friends.

**Correction to the first pass:** the node_exporter textfile collector is **already enabled and healthy** on ser8 - `node_scrape_collector_success{collector="textfile"} 1` and `node_textfile_scrape_error 0` [VERIFIED: `curl localhost:9100/metrics` 2026-08-26]. The exporter is started with `--collector.cpu --collector.meminfo --collector.filesystem --collector.diskstats --collector.loadavg --collector.netdev --collector.systemd --collector.processes --collector.zfs` from `modules/servers/monitoring.nix:35-45`, and textfile is on because it is one of node_exporter's own defaults. Only `extraFlags = [ "--collector.textfile.directory=..." ]` is missing. The pass-1 claim that the collector needed enabling was wrong.

The exporter's hardening still constrains the directory choice: `ProtectHome = true` is set unconditionally by the node exporter module and the shared exporter wrapper sets `ProtectSystem = mkDefault "strict"`. The exporter only reads, so no `ReadWritePaths` is needed, but the directory must be outside `/home` and the `.prom` files must be world-readable.

**Bonus, no new code:** `node_systemd_unit_state{name="backup-verify.service",state="failed"} == 1` is already scrapeable - the `systemd` collector is enabled and exports 1155 series on ser8. That gives a second, independent alert path for loud failures without touching the textfile mechanism.

### Pitfall 8: the first replication send is not a nightly-sized job

**What goes wrong:** the first `syncoid` run has no common base and sends the entire 11.2 GB `referenced` of `rpool/safe/persist` plus every child. If it starts at 03:00 it may still be running when `nixos-upgrade.timer` fires at 04:00 and restarts services underneath it.

**Why it happens:** `nixos-upgrade.timer` is live with `NEXT = Thu 2026-08-27 04:00:00 PDT` [VERIFIED: `systemctl list-timers` 2026-08-26]. The margin from 03:00 is one hour.

**How to avoid:** run the first full send manually, out of band, before enabling the timer - it is a read-only operation on the source and it makes every subsequent run incremental. Record the duration in the manifest. If measured steady-state duration ever approaches the hour, either move the snapshot earlier or order `nixos-upgrade.service` `After=syncoid-rpool-safe-persist.service`.

**Mitigating fact:** after D-07's tarball deletion the initial send drops to roughly 2.8 GB, and steady-state incrementals are ~75 MB.

**Warning signs:** a syncoid unit killed mid-run with no failure of its own; a resume token present on the replica (`zfs get receive_resume_token backup/persist-replica`) the following morning.

### Pitfall 9: `nix flake check` on the workstation cannot build an x86_64-linux VM test today (carried forward)

**What goes wrong:** `checks.x86_64-linux.*` is added, `make check` runs `nix flake check`, and it fails on the developer machine.

**Why it happens:** the workstation is `aarch64-darwin` and both configured Linux build paths are broken with distinct, small, root-caused failures - a stale `firebat.local` host key at `/var/root/.ssh/known_hosts:3` breaking the SSH remote builders, and lapsed FlakeHub authentication breaking Determinate's native Linux builder (`Authentication token is invalid`).

**How to avoid:** repair Determinate first (`determinate-nixd login`) as D-14 specifies - it makes `nix flake check` self-sufficient with no fleet dependency - and clear the stale host key as separate hygiene. Treat this as an explicit early task, not a mid-plan discovery. Note that `checks` is the flake's first such output, so `make check`'s runtime changes materially once it exists.

**Warning signs:** `Failed to find a machine for remote build!` or `Failed to set up Native Linux Builder`.

### Pitfall 10: removing the impermanence entry does not remove the old data

**What goes wrong:** after the child-dataset cutover, `/persist/var/lib/jellyfin` still holds a full copy of the old state, silently doubling both the pool footprint and the snapshot churn, and confusing the next person who greps for the state directory.

**Why it happens:** `environment.persistence` creates and bind-mounts; it never deletes. Removing an entry just stops the bind mount.

**How to avoid:** make "move the old directory aside, verify, then delete" an explicit task per service, gated on the service being healthy on the new dataset. Add a smoketest asserting `/persist/var/lib/<svc>` does not exist for every migrated service.

**Warning signs:** `zfs list -o used rpool/safe/persist` staying flat after a migration that should have moved data into children; `du /persist/var/lib` showing directories for migrated services.

## Code Examples

### Generic PostgreSQL dump, catalog-driven, zero registration (D-06)

```bash
# hosts/ser8/backup/dump.nix -> systemd.services.backup-pgdump.script
set -euo pipefail
umask 0077

OUT=/persist/var/lib/backup-dumps
mkdir -p "$OUT"

# Globals first: roles and tablespaces are not in any per-database dump.
pg_dumpall --globals-only > "$OUT/globals.sql.partial"
mv -- "$OUT/globals.sql.partial" "$OUT/globals.sql"

# Every non-template database, discovered from the catalog. A database added
# in a future phase is covered the night it is created, with no edit here.
psql -Atc "select datname from pg_database where not datistemplate and datallowconn" |
while IFS= read -r db; do
  pg_dump -Fc --file="$OUT/$db.dump.partial" -- "$db"
  pg_restore --list "$OUT/$db.dump.partial" > /dev/null   # verify before publishing
  mv -- "$OUT/$db.dump.partial" "$OUT/$db.dump"
done

# Retire dumps for databases that no longer exist.
for f in "$OUT"/*.dump; do
  db=$(basename -- "$f" .dump)
  psql -Atc "select 1 from pg_database where datname = '$db'" | grep -q 1 || rm -f -- "$f"
done
```

Live catalog on ser8 today returns `postgres`, `template1`, `template0`, `mealie`; the filter yields `postgres` and `mealie` [VERIFIED: `sudo -u postgres psql -Atc "select datname from pg_database"` 2026-08-26].

### Generic verify walk over the new snapshot (D-06, D-10)

```bash
set -euo pipefail
umask 0077

DS_ROOT=rpool/safe/persist
MAX_AGE=$((26 * 3600))

# 1. Find the newest daily snapshot; fail closed if there is none or it is stale.
snap=$(zfs list -H -t snapshot -o name -s creation -r "$DS_ROOT" |
       grep -E "^${DS_ROOT}@autosnap_.*_daily$" | tail -1) || true
[ -n "$snap" ] || { echo "FAIL: no daily snapshot on $DS_ROOT" >&2; exit 1; }
name=${snap#*@}
created=$(zfs get -Hp -o value creation "$snap")
age=$(( $(date +%s) - created ))
[ "$age" -le "$MAX_AGE" ] || { echo "FAIL: newest daily is ${age}s old" >&2; exit 1; }

# 2. Enumerate every dataset in the tree and its snapshot view. The recursive
#    snapshot guarantees the same name exists on parent and every child.
zfs list -H -r -o name,mountpoint "$DS_ROOT" | while IFS=$'\t' read -r ds mp; do
  [ "$mp" = "none" ] && continue
  [ "$mp" = "legacy" ] && mp=$(findmnt -n -o TARGET -S "$ds" | head -1)
  [ -n "$mp" ] || continue
  root="$mp/.zfs/snapshot/$name"
  [ -d "$root" ] || { echo "FAIL: $root missing" >&2; exit 1; }

  # 3. Discover SQLite files by kind, not by a registry.
  find "$root" -type f \( -name '*.db' -o -name '*.sqlite' -o -name '*.sqlite3' \) \
       -not -name '*-wal' -not -name '*-shm' -print0 |
  while IFS= read -r -d '' db; do
    # Copy the triple to scratch so the WAL is replayed. See Pitfall 6.
    scratch=$(mktemp -d /var/tmp/backup-verify.XXXXXX)
    trap 'rm -rf -- "$scratch"' RETURN
    cp -- "$db" "$scratch/db"
    [ -e "$db-wal" ] && cp -- "$db-wal" "$scratch/db-wal"
    [ -e "$db-shm" ] && cp -- "$db-shm" "$scratch/db-shm"
    size=$(stat -c %s -- "$db")
    if [ "$size" -gt $((64 * 1024 * 1024)) ]; then check=quick_check; else check=integrity_check; fi
    result=$(sqlite3 "$scratch/db" "PRAGMA $check;" 2>&1 | head -1)
    printf '%s\t%s\t%s\t%s\n' "$db" "$check" "$result" "$size"
    rm -rf -- "$scratch"; trap - RETURN
    [ "$result" = "ok" ] || exit 1
  done

  # 4. Verify the pg dumps that rode inside this snapshot.
  find "$root" -type f -name '*.dump' -print0 |
  while IFS= read -r -d '' dump; do
    pg_restore --list "$dump" > /dev/null || exit 1
    printf '%s\tpg_restore --list\tok\t%s\n' "$dump" "$(stat -c %s -- "$dump")"
  done
done
```

Snapshot paths work under a legacy mountpoint: `sudo ls /persist/.zfs/snapshot/` returns `pre-26.05-2026-08-17T085547Z` on ser8 even with `snapdir=hidden` [VERIFIED live 2026-08-26] - `hidden` only removes `.zfs` from directory listings, it does not remove the path.

### Textfile metrics and the digest (D-09, D-10)

```bash
# written by the verify job, at the end, atomically
TEXTFILE_DIR=/persist/var/lib/node-exporter-textfile
tmp=$(mktemp "$TEXTFILE_DIR/backup.prom.XXXXXX")
{
  echo '# HELP backup_last_snapshot_timestamp_seconds Creation time of the newest daily persist snapshot.'
  echo '# TYPE backup_last_snapshot_timestamp_seconds gauge'
  echo "backup_last_snapshot_timestamp_seconds $created"
  echo '# HELP backup_last_replica_timestamp_seconds Creation time of the newest daily snapshot on the replica.'
  echo '# TYPE backup_last_replica_timestamp_seconds gauge'
  echo "backup_last_replica_timestamp_seconds $replica_created"
  echo '# HELP backup_last_verify_timestamp_seconds Completion time of the last successful verify run.'
  echo '# TYPE backup_last_verify_timestamp_seconds gauge'
  echo "backup_last_verify_timestamp_seconds $(date +%s)"
  echo '# HELP backup_verified_files Files verified in the last run, by kind and result.'
  echo '# TYPE backup_verified_files gauge'
  echo "backup_verified_files{kind=\"sqlite\",result=\"ok\"} $sqlite_ok"
  echo "backup_verified_files{kind=\"sqlite\",result=\"fail\"} $sqlite_fail"
  echo "backup_verified_files{kind=\"pgdump\",result=\"ok\"} $pg_ok"
} > "$tmp"
chmod 0644 "$tmp"
mv -- "$tmp" "$TEXTFILE_DIR/backup.prom"   # rename(2): the collector never sees a partial file
```

```nix
services.prometheus.exporters.node.extraFlags = [
  "--collector.textfile.directory=/persist/var/lib/node-exporter-textfile"
];
systemd.tmpfiles.rules = [
  "d /persist/var/lib/node-exporter-textfile 0755 root root -"
];
```

The directory sits under `/persist` so it survives the rollback, and is outside `/home` so `ProtectHome = true` does not hide it.

### The one parameterized restore tool (D-11)

```bash
# hosts/ser8/backup/restore/backup-restore
# usage: backup-restore <service> [--from source|replica] [--snapshot <name>]
#                       [--list] [--force] [--rollback] [--pg-database <db>]
#
# Same three steps for every service: stop unit, replace state, start unit.
set -euo pipefail

svc=$1; shift
from=source; snap=; force=0; rollback=0; pgdb=
# ... argument parsing ...

case "$from" in
  source)  ds="rpool/safe/persist/$svc"   ;;
  replica) ds="backup/persist-replica/$svc" ;;
esac

# --list: the snapshot listing IS the restore-time picker (D-10).
if [ "$list" = 1 ]; then
  exec zfs list -H -t snapshot -o name,creation,used -s creation "$ds"
fi

[ -n "$snap" ] || snap=$(zfs list -H -t snapshot -o name -s creation "$ds" | tail -1 | cut -d@ -f2)
mp=$(zfs get -H -o value mountpoint "$ds")
[ "$mp" = legacy ] && mp=$(findmnt -n -o TARGET -S "$ds" | head -1)
src="$mp/.zfs/snapshot/$snap"
[ -d "$src" ] || { echo "no such snapshot: $ds@$snap" >&2; exit 1; }

live="/var/lib/$svc"
unit="$svc.service"

systemctl stop "$unit"

if [ "$rollback" = 1 ]; then
  # Fast and destructive: zfs rollback -r DESTROYS every snapshot newer than
  # the target, including the ones you would retry from. Source only: rolling
  # back the replica breaks the incremental chain with the source.
  [ "$from" = source ] || { echo "--rollback refused against a replica" >&2; exit 1; }
  [ "$force" = 1 ]     || { echo "--rollback requires --force" >&2; exit 1; }
  zfs rollback -r "$ds@$snap"
else
  if [ -n "$(ls -A "$live" 2>/dev/null)" ] && [ "$force" != 1 ]; then
    echo "$live is not empty; pass --force to replace it" >&2; exit 1
  fi
  aside="$live.pre-restore-$(date +%Y%m%dT%H%M%S)"
  mv -- "$live" "$aside" 2>/dev/null || true
  mkdir -p -- "$live"
  cp -a --reflink=auto -- "$src/." "$live/"
  # ownership travels with cp -a; StateDirectory would re-stamp mode anyway
fi

# Optional single-database restore from the generic dump that rode inside the
# snapshot. This is the BKP-05 path and it is a flag, not a second tool.
if [ -n "$pgdb" ]; then
  dump="$src/../$snap/backup-dumps/$pgdb.dump"
  pg_restore --clean --if-exists -d "$pgdb" -- "$dump"
fi

systemctl start "$unit"
systemctl is-active --quiet "$unit"
echo "restored $svc from $ds@$snap (mechanism: ${rollback:+rollback}${rollback:+ }${rollback:-copy})"
echo "previous state preserved at: ${aside:-<rolled back, not preserved>}"
```

Design notes:

- **Copy is the default, rollback is the flag.** `zfs rollback -r` destroys newer snapshots; on a failed restore that removes both the evidence and the retry options. Copy leaves the previous state on disk under a dated name.
- **Rollback is refused against a replica.** Rolling back the receive side diverges it from the source; syncoid's default `-F` would repair it on the next run, but only by discarding the operator's rollback. Better to make it impossible.
- **`--list` before `--snapshot`.** The snapshot listing is already the picker; the manifest adds the verification evidence beside it.
- **Mealie is not special.** State-dir replacement covers `/var/lib/mealie`; `--pg-database mealie` covers the database. Two flags on one tool, not a Mealie script.

### VM behavior test skeleton (D-14)

```nix
# tests/backup-behavior.nix
{ pkgs, ... }:
pkgs.testers.runNixOSTest {
  name = "ser8-backup-behavior";
  nodes.machine = { pkgs, ... }: {
    virtualisation.emptyDiskImages = [ 2048 2048 ];
    boot.supportedFilesystems = [ "zfs" ];
    networking.hostId = "2d833f3e";
    environment.systemPackages = [ pkgs.parted pkgs.sqlite ];
    # the real hosts/ser8/backup policy, parameterised on pool names
  };
  testScript = ''
    machine.succeed(
      "parted --script /dev/vdb -- mklabel msdos mkpart primary 1024M -1s",
      "parted --script /dev/vdc -- mklabel msdos mkpart primary 1024M -1s",
      "udevadm settle",
      "zpool create rpool /dev/vdb1",
      "zpool create backup /dev/vdc1",
      "zfs create -o mountpoint=/persist rpool/safe/persist",
      "zfs create -o mountpoint=/var/lib/demo rpool/safe/persist/demo",
    )

    # atomicity: one recursive snapshot, identical name on parent and child
    machine.systemctl("start --wait sanoid.service")
    parent = machine.succeed("zfs list -H -t snapshot -o name rpool/safe/persist").strip()
    child  = machine.succeed("zfs list -H -t snapshot -o name rpool/safe/persist/demo").strip()
    assert parent.split("@")[1] == child.split("@")[1], "recursive snapshot names diverged"

    # replication leaves the replica unmounted and without a live mountpoint
    machine.systemctl("start --wait syncoid-rpool-safe-persist.service")
    assert machine.succeed("zfs get -H -o value mounted backup/persist-replica/demo").strip() == "no"
    assert "/var/lib" not in machine.succeed("zfs get -r -H -o value mountpoint backup/persist-replica")

    # delegation leaves no residue, mirroring the upstream nixpkgs assertion
    assert len(machine.succeed("zfs allow rpool/safe/persist")) == 0

    # parameterised restore, one case per covered service
    for svc in ["demo"]:
        machine.succeed(f"backup-restore {svc} --force")
        machine.succeed(f"systemctl is-active {svc}.service")
  '';
}
```

## State of the Art

| Old approach | Current approach | When changed | Impact here |
|--------------|------------------|--------------|-------------|
| Per-application dump scripts orchestrated by a scheduler | Filesystem-level atomic snapshot plus replication, with application dumps only where format portability demands it (PostgreSQL major versions) | Long settled on ZFS/btrfs hosts | This is the pivot itself. The residual pg dump is not a hedge against crash-consistency; it is a hedge against binary/version coupling. |
| `zfs-auto-snapshot` (`services.zfs.autoSnapshot`) | sanoid, or zrepl for daemon-style setups | sanoid 1.x onward | D-16's deletion is not merely tidying: `autoSnapshot` has no replication, no pruning policy beyond fixed counts, and no hooks. All five of its timers currently fire for nothing on ser8. |
| `Persistent=true` timers for missed-run replay | Policy tools that derive due-ness from stored state | sanoid's design from the start | Removes the `/var/lib/systemd/timers` dependency entirely rather than patching around it. |
| `tdbbackup` for Samba state | Atomic snapshot | - | Under a non-atomic-copy model `tdbbackup` was required because tdb mtimes do not change on write. Under an atomic snapshot the whole concern evaporates; this is a scope deletion, not a substitution. |
| Verifying a backup by checking the file exists | `PRAGMA integrity_check` on a WAL-replayed copy, `pg_restore --list` on the dump | - | D-06 reflects the current standard, and Pitfall 6 is the part most implementations get wrong. |
| nix-darwin `linux-builder` VM for Linux builds on macOS | Determinate Nix's native Linux builder via Apple's Virtualization framework | Determinate Nix 3.8.4 | Already installed and configured on the workstation for both Linux systems; only un-authenticated. Better answer than lima/colima because it needs no VM image management. |

**Deprecated / outdated in this repo:**

- `modules/servers/backup.nix` (49 lines) and its import at `modules/servers/default.nix:13` - stale borg/restic/rsync scaffolding with an unused `backup` user. D-16 deletes both.
- The `services.zfs.autoSnapshot` block at `hosts/ser8/configuration.nix:119-126` (`frequent = 4`, `hourly = 24`, `daily = 7`, `weekly = 4`, `monthly = 12`) - live-verified inert; no ser8 dataset opts in. D-16 removes it, which also removes five useless timers.
- The `/var/lib/docker` impermanence entry at `hosts/ser8/impermanence.nix:64-67` - `docker.service` is `not-found` on ser8.
- The `"L /var/lib/samba - - - - /persist/var/lib/samba"` tmpfiles rule - dead; `findmnt` shows the impermanence bind mount is what is actually in effect. New finding this pass; worth adding to the D-16 deletion list.
- `/var/lib/private/prowlarr` - empty, superseded by the forced `DynamicUser = false` in `modules/media/prowlarr.nix`.

## Assumptions Log

| # | Claim | Section | Risk if wrong |
|---|-------|---------|---------------|
| A1 | `zfs recv` succeeds into a dataset tree with `readonly=on` set on the parent | Pattern 3 | `readonly` is a dataset property and `zfs recv` is a pool-level operation, so this should hold, but it was not exercised. If wrong, drop `readonly=on` and rely on `canmount=noauto` plus `-x mountpoint`. The VM test should assert it directly. |
| A2 | Setting `daily_hour` / `daily_min` / `frequent_period` through the NixOS module's freeform attrset reaches sanoid's config file | Pattern 1 | The module's `datasetSettingsType` is a `freeformType` and the INI generator emits any non-null key, so this follows from the source - but it was not confirmed by inspecting a built `sanoid.conf`. Verify by reading the generated file during the first plan task. |
| A3 | `recursive = "zfs"` on a dataset whose children carry differing local properties still yields one `zfs snapshot -r` call | Pattern 1 | The module documents `"zfs"` as "handle datasets recursively in an atomic way without the possibility to override settings for child datasets", and the code path calls `zfs snapshot -r`. Differing *dataset* properties (mountpoint, quota) are unrelated to sanoid *policy* settings, so this should be fine. The VM test's name-equality assertion catches it if not. |
| A4 | `PRAGMA quick_check` on a 178 MB WAL database completes in the low tens of seconds | Pitfall 6 | Not measured. If the verify job runs long, it can be moved off the 03:30 slot or split per dataset. No correctness impact. |
| A5 | Steady-state churn on `rpool/safe/persist` is ~75 MB/day after the Jellyfin tarballs are removed | Runtime State Inventory | Derived by subtracting the five tarballs' exact byte sizes from the measured `written@` value over a 9.4-day window. A single window may not be representative (Home Assistant recorder purge cycles, Frigate event volume). The one-week `written@` sampling plan converts this into an observation. Backup pool has 21.1 T free, so even a 10x error is inconsequential. |
| A6 | `cp -a --reflink=auto` from a snapshot into the live dataset degrades gracefully on ZFS 2.4.3 | Pattern 4 / restore tool | `--reflink=auto` falls back to a full copy when `FICLONE` is unsupported, so the worst case is slower, not broken. |
| A7 | The workstation's Determinate builder works once re-authenticated | Pitfall 9 / Environment | The failure is a quotable auth error (`Authentication token is invalid`), and the builder is otherwise configured for both Linux systems, but the repaired path was not exercised end to end this session. |
| A8 | Removing the `services.zfs.autoSnapshot` block does not disturb `services.zfs.autoScrub` or ZED | State of the Art | They are sibling attributes under `services.zfs` with no interdependence, and no dataset opts into `com.sun:auto-snapshot`. Confirm with a dry-run build diff. |

## Open Questions

1. **Which services get child datasets in this phase?**
   - What we know: 25 paths are bind-mounted from `rpool/safe/persist`. Coverage is guaranteed by the parent regardless. Granularity buys per-service restore addressing and per-service `used`/`written` accounting.
   - What is unclear: whether the migration cost (one stop/copy/remount per service, each a live-host mutation needing an operator checkpoint) is worth paying for all of them at once.
   - Recommendation: migrate the services the restore drills actually exercise plus the churn-heavy ones - `mealie`, `donetick`, `actual`, `hass`, `frigate`, `jellyfin`, and the new `mosquitto` - and leave the rest riding in the parent. That is seven checkpointed migrations, it covers every BKP-05/06 drill, and it demonstrates the pattern the attrset generalises. Add the remainder incrementally, which is exactly what D-02 says granularity should permit.

2. **Receive-side retention number.**
   - What we know: the backup pool has 21.1 T free and steady-state incrementals project at ~75 MB/night. Even 365 nightlies would be under 30 GB.
   - What is unclear: whether longer receive-side retention is wanted for its own sake or only as insurance against a source-side accident.
   - Recommendation: `daily = 90` on the replica. Three months is a meaningful "we noticed late" window, it costs single-digit GB, and it is one number the planner can change later without touching anything else. CONTEXT gives the planner the lock.

3. **Where do the pg dumps live inside the persisted tree?**
   - What we know: they must be inside the snapshotted tree, and they should not be inside any single service's state directory (that would couple a generic artifact to one service's dataset and one service's restore).
   - Recommendation: `/persist/var/lib/backup-dumps`, in the parent dataset, not a child. It is generic, it rides the parent snapshot that always exists, and the restore tool addresses it through the parent's `.zfs/snapshot`. If a child dataset were used, a per-service restore would have to know about it.

4. **Does the verify job read the source snapshot, the replica, or both?**
   - What we know: D-06 says verification reads from the snapshot. D-15 says smoketests assert freshness on both sides.
   - What is unclear: whether integrity verification on the replica adds enough to justify mounting it nightly.
   - Recommendation: verify integrity on the **source** snapshot (it is already mounted and cheap to reach) and verify the **replica** by existence-and-freshness only. ZFS's own checksums make an integrity difference between source and replica essentially impossible without a pool error, which the existing `zfs-scrub.timer` and `ZFSPoolUnhealthy` alert already cover. Revisit if the manual restore drill from a replica ever surprises.

5. **Does the 03:30 verify slot need to move once real durations are known?**
   - What we know: `nixos-upgrade.timer` fires at 04:00. The snapshot is instantaneous, the steady-state send is small, and the verify duration is dominated by `quick_check` on two ~175 MB databases.
   - Recommendation: keep 03:30 for the first week, record durations in the manifest, and move only if the measurement demands it. Do not pre-optimise a slot nobody has timed.

## Environment Availability

### ser8 (backup host) - everything present or one config line away

| Dependency | Required by | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| OpenZFS with `zfs recv -x`, resume tokens, bookmarks | D-03 | yes | `zfs-2.4.3-1` / `zfs-kmod-2.4.3-1` | - |
| `backup` zpool capacity | BKP-01 | yes | 21.8 T total, 21.1 T free, 3% used, ONLINE | - |
| `rpool` capacity for 30 nightlies | D-05 | yes | 920 G, 882 G free, 4% used | - |
| `sanoid` / `syncoid` | D-04 | **not installed** | 2.3.0 in pinned nixpkgs, builds from cache | Enable `services.sanoid` / `services.syncoid` |
| `sqlite3` | D-06 | yes | 3.51.2, `/run/current-system/sw/bin/sqlite3` | - |
| `pg_dump` / `pg_dumpall` / `pg_restore` | D-06 | yes | PostgreSQL 17, system profile | - |
| PostgreSQL server | BKP-02 | yes, running | 17 | - |
| `sendmail` (msmtp) | D-09/D-10 | yes | `/run/wrappers/bin/sendmail`, already ZED's path | - |
| node_exporter textfile collector | D-09 | **yes, already enabled and healthy** | 1.11.1, `node_textfile_scrape_error 0` | Only `--collector.textfile.directory=` missing |
| node_exporter systemd collector | D-09 bonus | yes | 1155 `node_systemd_*` series exported | - |
| ZFS delegation state | D-03 | clean | `zfs allow` empty on both `rpool/safe/persist` and `backup` | - |
| Passwordless sudo over SSH from a sandboxed session | plan execution | yes | verified `bdhill@192.168.68.65` | SOPS editing still needs a human checkpoint; this phase adds no secret |

### firebat (alerting host)

| Dependency | Required by | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Prometheus + rule file | D-09 | yes | `modules/gateway/prometheus.nix`, group `homelab` with 8+ rules | Add three rules to the same group |
| Alertmanager with email routing | D-09 | yes | - | - |
| ser8 node_exporter scrape target | D-09 | yes | port 9100, `openFirewall = true` | - |

### Workstation (VM tests and restore drills)

| Dependency | Required by | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Nix | everything | yes | Determinate Nix | - |
| x86_64-linux build capability | D-14 | **configured but broken** | `external-builders` for both Linux systems | `determinate-nixd login` (primary), or repair `/var/root/.ssh/known_hosts:3` for `firebat.local` |
| KVM / nested virtualisation for `runNixOSTest` | D-14 | via the Determinate Linux builder | - | Falls back to TCG (slow but correct) |
| `colima` / `docker` | D-12 fallback | yes | `~/.nix-profile/bin/colima`, `/opt/homebrew/bin/docker` | - |
| Reference lima flake | D-12 fallback | yes | `~/github/experiments/nix/lima/` | - |

**Missing dependencies with no fallback:** none.

**Missing dependencies with fallback:**
- `sanoid`/`syncoid` on ser8 - a config change, no external dependency, cached binaries.
- Linux build capability on the workstation - two independent repair paths, both small, both root-caused.
- Textfile directory flag on ser8 - one `extraFlags` line.

## Validation Architecture

### Test framework

| Property | Value |
|----------|-------|
| Framework (repo-wide) | Bash smoketests via `scripts/smoketests/lib/fanout.sh` (`run_suite`), plus `nix flake check` + `statix` + per-host dry-run builds |
| New framework this phase | `pkgs.testers.runNixOSTest` and `disko.lib.testLib.makeDiskoTest` exposed as `checks.x86_64-linux.*`. `flake.nix` has **no** `checks` output today - this is the first. |
| Config file | `deploy.yaml` names exactly one script per host; `scripts/smoketests/ser8/all.sh` fans out to areas via its `TESTS` array |
| Quick run command | `./scripts/smoketests/backup/all.sh ser8` |
| Full suite command | `make smoketests-ser8`, and `make check` |

### Phase requirements -> test map

| Req | Behavior | Test type | Automated command | Exists? |
|-----|----------|-----------|-------------------|---------|
| BKP-01 | Replica dataset exists on the backup pool with `dedup=off`, `canmount=noauto`, `readonly=on`, and no `/var/lib` mountpoint anywhere in the tree; each source child carries locally-set `atime=off`, and the `postgresql` child locally-set `recordsize=16K` | smoke | `./scripts/smoketests/backup/test-dataset-properties.sh ser8` | Wave 0 |
| BKP-01 | Newest daily snapshot on `rpool/safe/persist` is fresher than 26 h | smoke | `./scripts/smoketests/backup/test-snapshot-freshness.sh ser8` | Wave 0 |
| BKP-01 | Newest daily snapshot on the replica is fresher than 26 h | smoke | `./scripts/smoketests/backup/test-replica-freshness.sh ser8` | Wave 0 |
| BKP-01 | The disko declarations recreate the dataset tree from scratch | integration (VM) | `nix build .#checks.x86_64-linux.backup-layout` | Wave 0 |
| BKP-02 | `mealie.dump` exists in the newest snapshot and `pg_restore --list` succeeds | smoke | `./scripts/smoketests/backup/test-pgdump.sh ser8` | Wave 0 |
| BKP-03 | Spot `PRAGMA integrity_check` on one snapshot-read SQLite file returns `ok` | smoke | `./scripts/smoketests/backup/test-spot-integrity.sh ser8` | Wave 0 |
| BKP-03 | The verify walk detects a deliberately corrupted SQLite file and fails | integration (VM) | `nix build .#checks.x86_64-linux.backup-behavior` | Wave 0 |
| BKP-04 | Actual's `server-files/account.sqlite` and every `user-files/` member are present in the newest snapshot | smoke | `./scripts/smoketests/backup/test-manifest-coverage.sh ser8` | Wave 0 |
| BKP-05 | Mealie restore into a scratch VM using `backup-restore mealie --pg-database mealie` | manual drill | documented in `hosts/ser8/backup/README.md`, executed once | Wave 0 |
| BKP-06 | Donetick and Actual restores using the same tool | manual drill | `backup-restore donetick --force`, `backup-restore actual --force` | Wave 0 |
| BKP-06 | Parameterised restore across every covered service | integration (VM) | `nix build .#checks.x86_64-linux.backup-behavior` | Wave 0 |
| BKP-07 | The manifest's covered set equals the declared attrset, and every declared service has state in the newest snapshot | smoke | `./scripts/smoketests/backup/test-manifest-coverage.sh ser8` | Wave 0 |
| D-01/D-02 | Recursive snapshot yields the identical snapshot name on parent and every child | integration (VM) | `nix build .#checks.x86_64-linux.backup-behavior` | Wave 0 |
| D-05 | Retention prunes to exactly the configured window and never below the floor | integration (VM) | `nix build .#checks.x86_64-linux.backup-behavior` | Wave 0 |
| D-05 | Post-outage catch-up: a snapshot is taken on the first sanoid run after a simulated gap | integration (VM) | `nix build .#checks.x86_64-linux.backup-behavior` | Wave 0 |
| D-06 | Last `backup-verify.service` run succeeded | smoke | `./scripts/smoketests/backup/test-verify-last-run.sh ser8` | Wave 0 |
| D-09 | `backup_last_snapshot_timestamp_seconds` and siblings are exposed on `:9100` | smoke | `./scripts/smoketests/backup/test-metrics.sh ser8` | Wave 0 |
| D-10 | Manifest for last night exists, parses, and names every declared service | smoke | `./scripts/smoketests/backup/test-manifest-coverage.sh ser8` | Wave 0 |
| Pitfall 10 | `/persist/var/lib/<svc>` no longer exists for any migrated service | smoke | `./scripts/smoketests/backup/test-no-stale-persist-dirs.sh ser8` | Wave 0 |

### Sampling rate

- **Per task commit:** `make fmt && statix check` on changed files; `nix build .#nixosConfigurations.ser8.config.system.build.toplevel --dry-run` for any Nix change.
- **Per wave merge:** `make check`. Once `checks.x86_64-linux.*` exists this also builds the VM tests, which is exactly why Pitfall 9's builder repair is a prerequisite rather than a nice-to-have.
- **Phase gate:** `make smoketests-ser8` green after at least one real nightly snapshot, replication, and verify cycle has completed, then `/gsd-verify-work`.

### Wave 0 gaps

- [ ] Workstation Linux build capability - see Pitfall 9. Blocks every VM test from ever running locally. **Do this first.**
- [ ] `checks` output in `flake.nix` - does not exist today
- [ ] `tests/backup-layout.nix` - `makeDiskoTest` over a reduced rpool config
- [ ] `tests/backup-behavior.nix` - `runNixOSTest` covering atomicity, retention, catch-up, replica properties, restore
- [ ] `scripts/smoketests/backup/all.sh` plus the ten `test-*.sh` scripts above, added to the `TESTS` array in `scripts/smoketests/ser8/all.sh`
- [ ] `hosts/ser8/backup/restore/backup-restore` - itself a tested artifact per D-11

**Anti-requirement, from a recorded repo sore point:** no smoketest may pass when the thing it checks is absent.
Five existing smoketests currently do (`test-caddy.sh` passing with zero routes extracted, `test-home-assistant.sh` treating SSH failure as "no errors", the media SABnzbd check passing while the unit is dead, pi4/pi5 entries that are the literal `test` builtin, gateway `tls_*` subtests that skip-as-pass).
`scripts/smoketests/ser8/test-zfs-health.sh` is the near-verbatim fail-closed template to clone: it asserts a specific snapshot exists and explains in a comment why that assertion is load-bearing.

## Security Domain

### Applicable ASVS categories

| ASVS category | Applies | Standard control |
|---------------|---------|-----------------|
| V2 Authentication | no (reduced from pass 1) | The pivot deletes the arr API integration entirely. No credential is read, stored, or transmitted by this phase. |
| V3 Session Management | no | All units are local and non-interactive. |
| V4 Access Control | **yes** | The snapshot tree contains everything the live tree does: Home Assistant's `.storage/auth` password hashes, Frigate's `.jwt_secret`, Samba's `secrets.tdb` machine account, Tailscale's node private key, Actual budget data, arr `config.xml` API keys, and now the PostgreSQL dumps. Snapshot access inherits the source directory's modes, which is correct. The **new** exposure is the dump directory and the replica mountpoint: `/persist/var/lib/backup-dumps` must be `0700 root root` with `0600` dumps (`umask 0077` in the unit), and `/mnt/backup-replica` must be `0700 root root`. |
| V5 Input Validation | yes | The verify job walks filenames from a snapshot. Use `find -print0` / `read -d ''` so a path with whitespace or a newline cannot split a field, and never `eval` a discovered path. The restore tool takes a service name that indexes into the declared attrset - reject anything not in it rather than interpolating it into a dataset name. |
| V6 Cryptography | yes (negative) | No encryption at rest. `rpool` and `backup` are both unencrypted; the replica is on the same physical host. This is a conscious accepted risk consistent with the deferred off-host phase, where it becomes a real decision. Raw sends (`-w`) are irrelevant with no encryption in play. |
| V7 Error Handling & Logging | yes | The verify job's journal output includes discovered paths. Paths are not secrets, but the digest email must not include file *contents*. No API keys pass through this phase at all now. |
| V12 File Handling | yes | `umask 0077` in every unit; textfile metrics published by `rename(2)` after `chmod 0644` so the collector never reads a partial file; dumps published by `rename(2)` after `pg_restore --list` passes. |

### Known threat patterns for this stack

| Pattern | STRIDE | Standard mitigation |
|---------|--------|---------------------|
| Replica mounts over live service state and the service serves stale data | Tampering / DoS | `zfs recv -x mountpoint`, `canmount=noauto`, `readonly=on`; assert in the VM test and a smoketest |
| Prune deletes the newest snapshot on a clock or sort bug | DoS | sanoid's floor condition (`numsnapsthistype > minsnapsthistype`) makes it structurally impossible; the hand-rolled pipeline this replaces would not have that property |
| Non-`autosnap` snapshots (the impermanence `@blank` anchor) destroyed by the retention tool | DoS - catastrophic | sanoid only considers `^autosnap` names ending in a period suffix; `test-zfs-health.sh` already asserts `rpool/local/root@blank` exists |
| A corrupted database silently replicates and ages out the good copies | Tampering | Nightly `integrity_check` on a WAL-replayed copy of the snapshot, within 24 h, well inside the 30-night window |
| Freshness metric stamped despite a failed verify | Repudiation | The metric write is the last statement in the verify script, after every check, under `set -euo pipefail` |
| Dumps or replica readable by a local unprivileged user | Information disclosure | `umask 0077`, `0700` on both directories, mode assertion in a smoketest |
| `zfs rollback` during a restore destroys the snapshots needed to retry | DoS | Copy is the default; `--rollback` requires `--force` and is refused against a replica; the previous live state is moved aside, not deleted |
| Restore run against the wrong service wipes live data | DoS | Service name must be a key of the declared attrset; non-empty target refused without `--force`; previous state preserved under a dated name |
| Stale `zfs allow` delegation left on a pool after a failed run | Elevation of privilege | `services.syncoid` revokes in `ExecStopPost`; the upstream nixpkgs test asserts the delegation set is empty before and after, and the same assertion belongs in the local VM test |

## Project Constraints (from CLAUDE.md)

| Directive | Consequence for this phase |
|-----------|----------------------------|
| Format Nix with `nixfmt-rfc-style`; do not hand-align against formatter output | `make fmt` before every commit touching `.nix` |
| Keep module filenames lowercase and kebab-case | `hosts/ser8/backup/policy.nix`, `tests/backup-behavior.nix` |
| Preserve `SPDX-License-Identifier: GPL-3.0-or-later` headers where present | Every new `.nix` and `.sh` file gets one |
| New Bash scripts start with `set -euo pipefail`; run `shellcheck` and `shfmt -d` | Applies to the verify script, the restore tool, and every smoketest. Note the existing convention: `scripts/smoketests/lib/*.sh` are *sourced* and deliberately set no shell options - the caller owns them |
| Keep area entry points named `all.sh` when referenced by `deploy.yaml` | `scripts/smoketests/backup/all.sh`, reached through `scripts/smoketests/ser8/all.sh`, which is the only path `deploy.yaml` names for ser8 - so `deploy.yaml` itself needs no edit |
| Add or update smoketests when changing deployed services, monitoring, or storage | D-15 requires it; the textfile flag also touches monitoring |
| Treat warnings from formatters, linters, evaluators, and tests as failures | `statix check` clean, `make check` green. Adding `checks` makes `make check` materially slower - budget for it |
| Never commit plaintext credentials or decrypted SOPS content | This phase adds no secret at all; the pivot deleted the only candidate |
| `make test-HOST` is safer than `switch`; interactive deploy commands prompt by default | Use `make test-ser8` for the first activation of the backup slice |
| Do not push directly to `main` | Recorded operator policy: planning docs commit locally; only PRs reach origin |
| Never reference planning terminology in code or docs outside `.planning/` | `hosts/ser8/backup/README.md` and every code comment must carry the plain-language rationale, never "D-06", "Phase 14", or "BKP-03" |
| Replace, don't deprecate | D-16's deletions are removals, not shims: `modules/servers/backup.nix` **and** its import at `modules/servers/default.nix:13`; the `autoSnapshot` block **and** the five timers it creates; the dead `/var/lib/samba` `L` tmpfiles rule |
| No premature abstraction; no speculative features | D-13's "keep it boring": one attrset, no method plugins, no compression knobs, no options nobody has asked for |
| Use `rg` and `fd`; use `sb` for structure-aware exploration; never `rm -rf` (use `trash`) | Applies to executor tooling |
| Long jobs run as detached systemd units with an async-job manifest | The first full `syncoid` send (~2.8 GB after tarball deletion) is minutes, not hours - a foreground run with a checkpoint is fine |
| Approval only for live-host mutations | Repo edits, doc writes, and read-only ser8 probes are auto-approved. Every `zfs create`, every dataset cutover, the tarball deletion, and every activation is a mutation needing the checkpoint |
| One docs squash plus component-grouped source commits; `gsd-pr-branch` for PRs | Commit shaping at phase close |

## Sources

### Primary (HIGH confidence) - live systems and pinned source, read this session

- ser8 (`bdhill@192.168.68.65`), 2026-08-26: `zfs version` (2.4.3-1), `zpool list`, `zfs list -o name,used,refer,avail,mountpoint,canmount,snapdir`, `zfs list -t snapshot`, `zfs list -t bookmark`, `zfs get all rpool/safe/persist`, `zfs get -Hp written,written@<snap>,usedbysnapshots,logicalused`, `zfs allow rpool/safe/persist`, `zfs allow backup`, `findmnt -n -o TARGET,SOURCE,FSTYPE`, `systemctl list-timers --all`, `du -x -d2 /persist/var/lib`, `ls -la /var/lib/jellyfin/backups`, `ls -la /var/lib/mosquitto`, `ls -la /var/lib/samba`, `ls /persist/.zfs/snapshot/`, `sqlite3 pragma journal_mode` on five databases, `psql -Atc "select datname from pg_database"`, `curl localhost:9100/metrics` (textfile and systemd collector state), `grep ZED_EMAIL /etc/zfs/zed.d/zed.rc`, `command -v sqlite3 pg_dump zfs zpool`.
- Pinned nixpkgs `github:NixOS/nixpkgs/nixos-26.05` @ `e4bae1bd10c9c57b2cf517953ab70060a828ee6f`, store path `/nix/store/5nkggxpr2qy7v4z4b7x2056a4wsgrgy3-source`: `nixos/modules/services/backup/sanoid.nix` (read in full), `.../syncoid.nix` (read in full), `.../zrepl.nix` (read in full), `nixos/tests/sanoid.nix` (read in full), `nixos/tests/zrepl.nix`, `pkgs/by-name/sa/sanoid/package.nix`, `pkgs/by-name/zr/zrepl/package.nix`.
- Built `sanoid` derivation `/nix/store/52pp96l26x1n086d3jhzf7ysy744q1k3-sanoid-2.3.0`: `etc/sanoid/sanoid.defaults.conf` (read in full), `bin/.sanoid-wrapped` (`take_snapshots` due logic, snapshot naming, `zfs snapshot -r` call, `prune_snapshots`, `getsnaps` name filter), `bin/.syncoid-wrapped` (`parsespecialoptions`, `getoptionsline`, recv option assembly, `--exclude-datasets`).
- disko flake input `/nix/store/w2c23ykc12mswlg8hrrjzb5gv9gvkzwq-source`: `lib/types/zfs_fs.nix` (read in full), `lib/tests.nix` (`makeDiskoTest` signature), `tests/zfs.nix`.
- impermanence flake input `/nix/store/3ib4ns4q84wcjfqim5wc0jsjw7v18lpd-source`: `nixos.nix` bind-mount generation for initrd and stage 2.
- Repository: `flake.nix`, `hosts/ser8/{configuration,disko-config,impermanence}.nix`, `modules/servers/{monitoring,default}.nix`, `modules/servers/backup.nix`, `modules/gateway/prometheus.nix`, `scripts/smoketests/ser8/{all.sh,test-zfs-health.sh}`, `.planning/REQUIREMENTS.md`.

### Secondary (MEDIUM confidence) - documentation and upstream issue trackers, cross-checked against source where possible

- OpenZFS `zfs-allow(8)`, delegation exceptions on Linux - https://openzfs.github.io/openzfs-docs/man/master/8/zfs-allow.8.html
- zrepl, Taking Snapshots (`periodic` / `cron` / `manual`, hooks, `err_is_fatal`) - https://zrepl.github.io/configuration/snapshotting.html
- zrepl, Monitoring (native Prometheus listener on `:9811`) - https://zrepl.github.io/configuration/monitoring.html
- zrepl issue #251, "Create all the snapshots at the same time" - https://github.com/zrepl/zrepl/issues/251
- zrepl issue #554, cron snapshotting - https://github.com/zrepl/zrepl/issues/554
- dsh2dsh/zrepl fork, `recursive: true` implemented as `zfs snapshot -r` - https://github.com/dsh2dsh/zrepl
- sanoid README, command-line options and script hooks - https://github.com/jimsalterjrs/sanoid
- nix.dev, integration testing with NixOS virtual machines - https://nix.dev/tutorials/nixos/integration-testing-using-virtual-machines.html
- Determinate Systems changelog, native Linux builder for macOS - https://determinate.systems/blog/changelog-determinate-nix-384/

### Tertiary (LOW confidence) - surveyed, not adopted

- znapzend (`nixos/modules/services/backup/znapzend.nix` exists in the pinned nixpkgs; not evaluated in depth)
- borgmatic / restic / Kopia - explicitly deferred to the future off-host phase by CONTEXT

### Carried forward from the first research pass (still valid, not re-derived)

- The full 16-service coverage inventory with paths and sizes, and the exclusion table with evidence.
- The workstation builder diagnosis: stale `firebat.local` host key at `/var/root/.ssh/known_hosts:3`; lapsed FlakeHub auth for `determinate-nixd`.
- The absent-series alerting failure mode and its `or absent(...)` fix.
- The node_exporter hardening constraints (`ProtectHome = true` unconditional; `ProtectSystem = mkDefault "strict"`; no first-class textfile directory option, must use `extraFlags`).
- The list of five always-pass smoketests that establishes the fail-closed anti-requirement.

## Metadata

**Confidence breakdown:**

- Tool selection (sanoid+syncoid over zrepl): **HIGH** - every decisive claim was read from the sanoid/syncoid source or the NixOS module source this session, and the zrepl atomicity limitation is confirmed by an open upstream issue plus the existence of a fork created specifically to fix it.
- sanoid policy semantics (retention, catch-up, naming, hook constraints): **HIGH** - read verbatim from `sanoid.defaults.conf` and the Perl source, including exact line-level quotes.
- syncoid receive-side mechanics (`-u`, `-x mountpoint`, `-F`, `-s`): **HIGH** for the option parsing and defaults (read from source), **MEDIUM** for the `readonly=on` interaction with `zfs recv` (see A1).
- Child-dataset migration mechanics: **HIGH** for the disko and impermanence behaviours (read from both inputs' source), **MEDIUM** for the cutover sequence, which is assembled from those facts but not executed.
- Live inventory and churn measurement: **HIGH** - every path, size, mount, journal mode, and byte count was probed on ser8 this session.
- Verification approach (WAL-replay copy): **HIGH** for the mechanism, **MEDIUM** for the runtime cost on the two ~175 MB databases (A4).
- VM test harness: **HIGH** for the templates (upstream `nixos/tests/sanoid.nix` and disko's `makeDiskoTest` read in full), **MEDIUM** for the end-to-end path, which depends on the un-exercised builder repair (A7).
- Restore tool shape: **MEDIUM-HIGH** - the mechanics are well understood and the safety properties are sound, but the tool does not exist yet and the drills are the real test.

**Research date:** 2026-08-26
**Valid until:** 2026-09-25 (30 days). Two things shorten it: a Nixflix cutover (Phase 15) moves the arr and Jellyfin state paths, and ser8 auto-upgrades nightly via `nixos-upgrade.timer`, so the pinned nixpkgs and the ZFS version drift on a weekly cadence.
