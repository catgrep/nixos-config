# Phase 14: Backup Engine - Context

**Gathered:** 2026-08-26
**Revised:** 2026-08-26 - architecture pivot (operator chat, post-research review)
**Status:** Ready for re-research and re-planning

> **PIVOT NOTE (read first).**
> The original decision set (recorded in `14-QUESTIONS.json`) specified a six-method, per-target dump engine (`sqlite`, `pgdump`, `arr-api`, `tree`, `tdb`, `file`).
> After reviewing the first research pass, the operator redirected the architecture: **generation is dumb (atomic ZFS snapshots + replication); consumption is smart (one parameterized restore tool + generic verification)**.
> The first research pass (`14-RESEARCH.md` as of commit `da83a73`) and the eight plans built on it are superseded; its live inventory, exclusion evidence, and pitfalls remain valid inputs.
> `14-QUESTIONS.json` answers Q-01, Q-02, Q-06..Q-11, Q-13, Q-14, Q-17, Q-21 are superseded where they conflict with the decisions below; the chat notes and everything else still stand.

<domain>
## Phase Boundary

Every stateful service on ser8 - household apps, media apps, Home Assistant, Frigate, Mosquitto (once persisted, see D-08), Samba, and any misc persisted state - is protected by nightly **atomic ZFS snapshots of persisted state, replicated to the backup pool**, with generic integrity verification, staleness alerting, and a demonstrated, working restore path (Mealie into a scratch VM; one SQLite service; Actual Budget).
Requirements: BKP-01..07 (wording amendments required, see D-17).
Media CONTENT is explicitly out of scope (the two-disk mirror is its sole and sufficient home, per Phase 13 D-18); so are off-host/remote backups (this milestone's out-of-scope table).
No Nixflix work (Phase 15) - but the coverage model (whole-of-persist, kind-discovered) means Phase 15's path changes need no backup-side edits.

</domain>

<decisions>
## Implementation Decisions

### Rationale for the pivot (context for downstream agents)

- Every covered service's state lives under `/var/lib/<svc>`, bind-mounted from `rpool/safe/persist` via impermanence. One dataset (tree) holds everything.
- A ZFS snapshot is atomic (single TXG). The state it captures is exactly the crash/power-loss image that SQLite (WAL replay or rollback journal, both modes present on ser8) and PostgreSQL (WAL redo) are designed to recover from. No app cooperation or quiesce is needed.
- BKP-03's "never a raw copy" rule targets **non-atomic live file copies** (`cp`/`rsync` walking `db` + `-wal` + `-shm` at different instants), which genuinely corrupt. An atomic snapshot is not that failure mode. The requirement wording must be amended (D-17), not silently reinterpreted.
- Consequence: per-service backup failure as a class mostly evaporates, deleting the need for per-target failure domains, per-method dump code, the arr API dance, and the atomic-publish pattern. Engineering effort moves to restore tooling, verification, and VM tests - the parts that matter during an incident.
- The most likely restore trigger is logical/operator error (bad automation, botched app migration, fat-finger), which snapshots handle and `integrity_check` cannot; structural corruption (app bugs) is caught by the nightly verify job (D-06) before it ages out good copies; bit rot is already ZFS scrub territory.

### Storage and generation

- **D-01 (supersedes old D-01/D-06):** Backup generation is **atomic ZFS snapshots of persisted service state** - no per-service dump engine, no plain-dated-directory artifact format. The "zero extra tooling for restores" rationale survives: any snapshot's files are browsable at `.zfs/snapshot/<name>/...` and restorable with `cp`. - **Reversibility:** reversible in design (the old engine model can be revived from this file's history), but the child-dataset migration in D-02 is effortful to unwind once done.
- **D-02:** **Per-service child datasets**: `rpool/safe/persist/<svc>` mounted at `/var/lib/<svc>`, replacing the per-directory impermanence bind mounts for covered services. Generated from **one attrset** in the backup module (D-13) - service name in, dataset + mount + policy out. The parent `rpool/safe/persist` continues to be snapshotted so misc persisted state (Tailscale node identity, Samba tdbs, systemd bits, anything unregistered) is covered **without registration** - forgetting to add a child dataset degrades granularity, never coverage. Recursive snapshots (`zfs snapshot -r`, one TXG) keep the whole tree atomic across parent and children. Migration to child datasets is imperative per service (stop unit, `zfs create`, copy, remount, start) because disko declarations do not retro-create datasets on a live pool (Phase 13 Plans 05/07 precedent); mechanics are a research task. **Operator decision 2026-08-27: every unit-backed service gets a child dataset** (donetick, homebox, actual, mealie, postgresql, hass, frigate, jellyfin, sonarr, radarr, prowlarr, bazarr, sabnzbd, nzbget, mosquitto, tailscale - ~16); the parent remains the safety net for non-service and shared state (samba's multi-unit tdbs, systemd bits, dumps, manifests, anything untracked).
  - **Dataset properties (operator decision 2026-08-27):** all new children are created with explicit `atime=off`; the `postgresql` child additionally gets `recordsize=16K`, set at creation so the migration copy writes everything at that size (the record is the CoW unit and therefore the snapshot-pinning unit - 16K shrinks nightly deltas and matches two compressed 8K pages, the standard Postgres-on-ZFS guidance). Every other child keeps the 128K default: their content is mixed (databases beside images/config), 128K is the designed compromise, and speculative per-dataset tuning is exactly the cleverness the boring rule forbids. If post-deployment churn measurement fingers a SQLite-heavy dataset (HA's recorder is the candidate), dropping that one dataset to 16-32K is a sanctioned one-line follow-up. `ashift=12` is already correct pool-wide and immutable; `volblocksize` is irrelevant (no zvols exist).
- **D-03:** **Replication to the backup pool is the backup half.** Snapshots on `rpool` alone die with the NVMe. Each nightly snapshot is sent (`zfs send`/`recv`, incremental) to receive-side dataset(s) on the `backup` pool (RAID-Z2, 21.1 T free; dedup off is the inherited default there, satisfying BKP-01's dedup-off requirement). Replica files must remain browsable for restores (`.zfs/snapshot` on the received dataset); receive-side mount/property handling is a research task.
- **D-04 (supersedes old D-04):** Snapshot/prune/replication is driven by an **established policy tool, not hand-rolled units**: researcher compares **sanoid + syncoid vs zrepl** and recommends one (comparison criteria in Research tasks). The chosen tool is the retention authority. The legacy inert `services.zfs.autoSnapshot` block is **removed, not revived** (it is the older machinery; all five timers fire for nothing today).
- **D-05 (carries old D-02/D-03):** Nightly at **03:00**; source retention is a **30-nightly flat sliding window**. Receive-side retention on the backup pool may be longer (space is cheap there) - researcher recommends, planner locks. **Missed-run replay must be verified under the chosen tool** - note `/var/lib/systemd/timers` is NOT persisted on ser8, so `Persistent=true` stamps do not survive the impermanence rollback (first-research Pitfall 6); fix or tool-native equivalent required. The 04:00 `nixos-upgrade.timer` window interaction should be checked once real durations are known (snapshots are near-instant; the send and verify are the long poles).

### Consistency, verification, and dumps

- **D-06:** A generic nightly **verify + dump job with kind discovery, zero per-service registration** (operator constraint: no special-casing; adding a service must never require remembering to register it for verification):
  - **Pre-snapshot dump:** `pg_dumpall --globals-only` + `pg_dump -Fc` for **every non-template database discovered from the catalog** (old D-12's shape, kept because it is already generic), written INTO the persisted tree (exact location planner's discretion) and ordered before the snapshot - so the portable dumps ride inside every snapshot and replica. This generically solves PostgreSQL's major-version coupling on crash-consistent restores; no per-app dump wiring exists or is added.
  - **Post-snapshot verify:** walk the new snapshot's paths (`.zfs/snapshot/<name>/...`) and run `PRAGMA integrity_check` on **every discovered `*.db`/`*.sqlite*` file**, and `pg_restore --list` on the dumps. Structural corruption is detected within 24 h so it cannot age out the good copies. Verification reads from the snapshot, never the live files.
  - **Last-verified holds (operator decision 2026-08-27):** the verify job maintains a per-dataset `last-verified` `zfs hold` that advances only on clean verification - the last known good snapshot per service is indestructible (prune skips held snapshots) until verification succeeds again. The manifest records each dataset's hold position; a VM assertion covers advance-on-ok and stay-on-fail.
  - **Verify-unit hardening (operator decision 2026-08-27):** the verify service runs as root (required: snapshot trees preserve `0700` service-owned permissions across ~16 uids) but under a strict systemd sandbox - `ProtectSystem=strict` with `ReadWritePaths=` limited to scratch and the manifest dir, `NoNewPrivileges`, minimal capability set. Root that reads everything, writes almost nowhere.
- **D-07 (supersedes old D-09/D-10 mechanism):** **App-side backup rule: app-native backups stay on their defaults unless their churn dominates the dataset.** Concretely:
  - Arr apps' built-in weekly backups (Sonarr/Radarr/Prowlarr/Bazarr, ~1-10 MB zips, app-side retention) **stay on** - they land inside the state dirs and ride along in every snapshot as a free app-consistent bonus layer. **No API integration, no API keys, no Bazarr secret question** - that whole surface is deleted from scope.
  - `services.declarative-jellyfin.backups = false` and the existing **8.4 GB of activation tarballs in `/var/lib/jellyfin/backups` are deleted** - each activation tars the full state (~1.8 GB), five landed on 2026-08-25 alone, and this churn dominates persist (the 9-day-old `pre-26.05` snapshot pins 10.5 GB, ~1.2 GB/day, mostly these tarballs). Their config-rollback purpose is covered by ZFS snapshots + NixOS generations.
  - Path excludes are not a ZFS feature; where junk churn matters, the mechanism is disable-at-source (preferred) or a non-snapshotted child dataset (only if disabling is impossible).
- **D-08 (new):** **Persist Mosquitto**: `/var/lib/mosquitto` gets a persistence entry (or child dataset) - today it lives on `rpool/local/root` and is destroyed every boot, so "cover Mosquitto" was theatre. Accepted side effect: retained MQTT messages and session state now survive reboots, which is correct broker behavior. Verify Frigate/HA behave across a reboot after the change.

### Failure handling and observability

- **D-09 (carries old D-16):** Alerting on **both channels**: `OnFailure=` email (existing msmtp/ZED `sendmail` path, one mail mechanism fleet-wide) for loud failures of the snapshot/replication/verify units, plus a **staleness metric with a firebat alert at >26 h** that MUST be written absent-series-safe (`expr ... or absent(...)` - a bare `time() - metric > 26h` never fires on a missing series, which is exactly the silent-never-ran case). Metric source: **zrepl's native Prometheus endpoint if zrepl is chosen** (D-04), else the node-exporter textfile collector (textfile dir must be persisted and must respect the exporter's `ProtectHome`/strict hardening - first-research Pitfalls 7/8).
- **D-10 (carries old D-15/D-18, reduced):** The verify job (D-06) writes a **per-night manifest** (covered datasets/services, sizes, integrity results, dump list, durations) and composes **one digest email**. The snapshot listing is the restore-time picker; the manifest adds the verification evidence and feeds the smoketests.

### Restore

- **D-11 (carries old D-21's preferred shape, now uniform):** **One parameterized restore tool** - the same three steps for every service: stop unit → replace state from the chosen snapshot → start unit. Default mechanism is copy-from-snapshot (`.zfs/snapshot/...` on source or replica) into the live path; `zfs rollback` is available as an explicit fast destructive path (it destroys newer snapshots - gate it behind an explicit flag). The tool refuses to touch a non-empty target without an explicit flag, offers a **dry-run/preview flag** that resolves and prints the exact operations (snapshot, paths, unit, move-aside; for rollback, the snapshots that would be destroyed) without performing any, and its help output ends with **worked example invocations** (operator directive 2026-08-27). Runbook at `hosts/ser8/backup/README.md` indexes the tool; the drills execute it, so it is a tested artifact.
- **D-12 (carries old D-19/D-20, extended):** Restore drills (BKP-05/06) are demonstrated in a **workstation VM**: Mealie (via the generic pg dump), **Donetick** (SQLite; smallest DB, `delete` journal mode - planner's pick is now locked), and Actual (state-dir restore including `user-files/`). Additionally, the **VM test suite parameterizes restore verification across ALL covered services** (boot VM, inject snapshot state, start service, assert health) - the manual drills prove the human path; the VM suite proves generality. "Only checking Mealie" was an artifact of assuming drills are manual; with VM infra they are not.

### Module shape, testing, and repo hygiene

- **D-13 (carries old D-07):** Everything lives as a host slice under **`hosts/ser8/backup/`**: one attrset of covered services generating child datasets/mounts (D-02), tool policies (D-04), the verify/dump units (D-06), and the metric wiring (D-09). Promotion to `modules/backup/` deferred until a second host needs it. **Keep it boring**: no speculative options, no method plugins, no compression knobs.
- **D-14 (carries old D-17, extended):** **VM test infrastructure is a first-class deliverable**, not just a gate: repair the workstation Linux-build path first (Determinate `determinate-nixd login` as primary; fix the stale `firebat.local` host key in `/var/root/.ssh/known_hosts` as hygiene regardless - both breakages are root-caused in the first research pass), add the repo's **first `checks` flake output**, and build a `nixosTest` suite covering: disko dataset layout creation (closing the "declaration doesn't create the dataset" class pre-deployment), snapshot + prune behavior under the chosen tool, and the parameterized per-service restore flow (D-12). **Crash-resilience tests (operator decision 2026-08-27):** the suite also exercises `machine.crash()` scenarios - interrupted send resumes via the resume token on the next run; a crash between snapshot and verify leaves the metric unstamped so the staleness alert path fires; and after any crash, each nightly snapshot name exists on either all datasets or none (the orchestration is tested; ZFS's TXG atomicity itself is inherited, not re-proven). This seeds the standing todo of converting smoketests into NixOS integration tests.
- **D-15 (carries old D-08):** **Fail-closed smoketests** in `scripts/smoketests/backup/` (`all.sh` + `test-*.sh`), reached through `scripts/smoketests/ser8/all.sh` (the documented convention; `deploy.yaml` itself needs no change): snapshots fresher than 26 h on BOTH source and replica, last verify run succeeded, manifest complete and matching the declared coverage set, spot `integrity_check` on one snapshot-read file. Absent artifact, unreachable host, or unparseable manifest is a FAILURE, never a skip (recorded repo sore point: five existing always-pass smoketests).
- **D-16 (carries old D-05, extended):** Deletions this phase (replace-don't-deprecate): `modules/servers/backup.nix` + its import in `modules/servers/default.nix`; the inert `services.zfs.autoSnapshot` block in `hosts/ser8/configuration.nix`; the dead `/var/lib/docker` impermanence entry; the empty `/var/lib/private/prowlarr` leftover; the stale `*.reset-bak-20260822` files (Homebox, Donetick); the Jellyfin tarball directory (D-07). The legacy `backup/backups` dataset (`dedup=on`) is left alone after a contents check.
- **D-17 (carries old D-14's amendment duty, extended):** The planner amends requirement/roadmap wording to match the pivot (same pattern as Phase 13's D-04 requirement edits): BKP-01 (the dedup-off dataset on the backup pool is the **replication target**), BKP-02 (Mealie covered by snapshot + the generic pg dump; images are in the snapshot), BKP-03 (forbid **non-atomic live file copies**; atomic snapshot + snapshot-read `integrity_check` is the mechanism), BKP-04 (correct paths: `server-files/account.sqlite`; `user-files/` contains live SQLite + blobs - whole-state snapshot subsumes), BKP-07 (coverage = everything persisted, not a named app list).

### Claude's Discretion

- Child dataset naming/layout (D-02; the covered set itself is locked to all unit-backed services).
- Snapshot naming scheme, manifest format, digest composition, pg dump location within the persisted tree.
- Receive-side dataset layout and property overrides on the backup pool.
- Exact requirement/roadmap amendment wording (D-17).
- Whether Mosquitto gets a child dataset or a plain persistence entry (D-08).
- Ordering/dependency details between dump unit, snapshot, send, and verify under the chosen tool's hook model.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase record
- `.planning/phases/14-backup-engine/14-QUESTIONS.json` - full original Q&A. **Partially superseded by the pivot** (see PIVOT NOTE); chat notes (`chat_more` fields) still carry operator intent worth reading.
- `.planning/phases/14-backup-engine/14-RESEARCH.md` - first research pass. The architecture recommendation is superseded; the **live coverage inventory, exclusion evidence, journal-mode table, pitfalls, and builder diagnosis remain valid** and should be carried into the re-research rather than re-derived.

### Requirements and roadmap
- `.planning/REQUIREMENTS.md` - BKP-01..07; wording amendments required per D-17.
- `.planning/ROADMAP.md` - Phase 14 goal and success criteria (rewritten 2026-08-26 for the pivot); Phase 15 dependency note (pre-cutover snapshot/rollback rides on this machinery - the snapshot model serves it directly).

### Prior-phase facts
- `.planning/STATE.md` - Phase 09's "never cp/rsync a live SQLite" decision is amended by this pivot to "never a NON-ATOMIC copy" (atomic snapshots are the sanctioned mechanism); Phase 12 identity pins; Phase 13 storage decisions (D-18 media content out of scope, D-21 downloads on NVMe).
- `.planning/phases/13-zfs-mirror-migration/13-CONTEXT.md` - final ZFS topology this targets.

### Code surface
- `hosts/ser8/disko-config.nix` - pool layout; dataset-property patterns (`cameras` is the no-auto-snapshot shape); legacy `backups` dataset (`dedup=on`).
- `hosts/ser8/impermanence.nix` - the authoritative persisted-state list = the coverage universe; the entries child datasets will replace; the dead `/var/lib/docker` entry.
- `modules/servers/backup.nix` - stale scaffolding D-16 deletes (check the `modules/servers/default.nix` import).
- `modules/gateway/prometheus.nix` - alert-rule patterns for the D-09 staleness rule.
- `hosts/ser8/configuration.nix` lines ~119-126 - the inert `services.zfs.autoSnapshot` block D-16 removes.

### External reference
- `~/github/experiments/nix` - operator's lima-with-Nix experiment (D-12 VM fallback path; the Determinate native builder is the preferred path).

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- ZED mail path on ser8 (`catgrep@sudomail.com`) - D-09/D-10 emails ride the same msmtp `sendmail` wrapper.
- firebat Prometheus + Alertmanager with email routing - the staleness alert is one more rule in the established `homelab` group.
- `scripts/smoketests/` per-area convention (`all.sh` dispatching `test-*.sh`) - D-15 clones it; `scripts/smoketests/ser8/test-zfs-health.sh` is the near-verbatim fail-closed template (first pattern-mapping pass).
- Phase 13's `zfs send`/`recv` migration experience (`backup/media-staging@verified` → `media/data`) - the exact replication mechanism D-03 uses, already proven on this host.

### Established Facts (live-verified 2026-08-25/26)
- ser8 has exactly **2 snapshots**, none auto-created: `rpool/local/root@blank` and `rpool/safe/persist@pre-26.05-...` (pins 10.5 GB over 9 days ≈ 1.2 GB/day churn, dominated by Jellyfin activation tarballs; residual churn ~75 MB/day per the re-research `written@` measurement). `media/data@verified` was destroyed by the operator on 2026-08-26.
- `rpool/safe/persist`: 11.2 GB referenced, 21.7 GB used with the one snapshot. With Jellyfin tarballs disabled, 30 nightly snapshots are estimated to pin roughly 5-15 GB on rpool (measure with a week of real nightlies).
- All covered services persist under `/var/lib/*` via impermanence bind mounts from `rpool/safe/persist`. Mosquitto does NOT (D-08 fixes). `/var/lib/systemd/timers` does NOT (breaks `Persistent=true` replay).
- 11 live SQLite databases (8 WAL, 3 `delete`); PostgreSQL 17 with one app DB (Mealie); 8 Samba tdbs. Full inventory with paths/sizes in `14-RESEARCH.md`.
- Both workstation Linux-build paths are broken and root-caused: lapsed FlakeHub auth (`determinate-nixd login` fixes) and a stale `firebat.local` host key at `/var/root/.ssh/known_hosts:3`.
- Passwordless sudo over SSH works from sandboxed sessions (`bdhill@192.168.68.65`); SOPS editing does not (human checkpoint - though the pivot eliminates the only candidate new secret).

### Integration Points
- Child datasets declared in `hosts/ser8/disko-config.nix` AND created imperatively (declarations don't retro-create on a live pool); the VM disko test (D-14) proves the declarations would recreate the layout from scratch.
- Backup slice imported from ser8's host configuration like `./media` and `./household`; smoketests reached via `scripts/smoketests/ser8/all.sh`.
- Phase 15 consumes this machinery for its pre-cutover snapshot/rollback - a whole-dataset snapshot + tested restore tool is exactly its need, with no path declarations to update.

</code_context>

<specifics>
## Specific Ideas

- Operator's framing, verbatim intent: "dumb simple snapshots/backups (generate); sophisticated per-service restores (consume)", "This should be kept as boring as possible", "I don't like special casing", "when we add/remove apps I don't want to accidentally neglect adding this for a new service".
- The design must make coverage the default (whole-of-persist) and granularity the opt-in (child datasets), never the reverse.
- Preserve the evidence-first posture: verify tool behavior against the live host and the pinned nixpkgs module source, not docs.

### Research tasks (re-research; carry forward still-valid first-pass findings instead of re-deriving)

1. **sanoid+syncoid vs zrepl** (vs a thin hand-rolled send unit, only as a baseline): policy/retention expression for a 30-nightly window; pruning BOTH source and replica sides; missed-run/catch-up semantics across reboots (given the `/var/lib/systemd/timers` gap); pre/post hooks or ordering points for the D-06 dump/verify jobs; incremental send chains, resume tokens, bookmarks; NixOS module maturity (`services.sanoid`/`services.syncoid`/`services.zrepl`); zrepl's native Prometheus endpoint vs the textfile collector for D-09. Recommend one with the trade stated.
2. **Child-dataset migration mechanics on the live host**: per-service cutover sequence (stop → `zfs create` → copy → mount → start), interaction with the impermanence module when a bind-mount entry becomes a dataset mountpoint, `RequiresMountsFor` on service units, disko declaration shape for nested datasets, and how `zfs snapshot -r` + the chosen tool handle the parent+children tree.
3. **Replication details**: receive-side properties (`canmount`, `mountpoint`, `readonly`) so replicas don't mount over live paths yet stay browsable via `.zfs/snapshot`; whether raw sends matter here (no encryption in play); replica verification story.
4. **Dump/verify wiring under the chosen tool**: exact hook or systemd ordering for pre-snapshot pg dumps and post-snapshot `integrity_check` walks; how the manifest/digest unit fits; failure propagation into `OnFailure=`.
5. **VM test harness**: `nixosTest` with ZFS pools inside the VM (loop devices), disko's own test machinery for layout verification, the parameterized restore-test shape (inject snapshot state, start service, assert health per service), and what the repaired Determinate builder path needs end to end.
6. **Restore tool shape**: copy-from-snapshot vs `zfs clone` vs `zfs rollback` per scenario; safety guards; how it addresses source snapshots vs replica snapshots; runbook skeleton.
7. **Churn measurement**: confirm the 5-15 GB/30-night estimate once Jellyfin tarballs are disabled; identify any other churn hotspot worth a non-snapshotted child dataset.

</specifics>

<deferred>
## Deferred Ideas (OUT OF SCOPE)

- **Off-host/remote backup with indefinite retention** - out of scope this milestone. Borg/borgmatic (or restic/Kopia) become the interesting candidates HERE, pushing to non-ZFS storage from snapshot mounts; with ZFS on both ends on-site, snapshot+send dominates and borgmatic's repo format buys nothing now. Revisit at the remote phase.
- **Hourly snapshots of persist (oops-protection tier)** - under the chosen policy tool this becomes roughly one more policy line, but it is still its own decision (snapshot pinning behavior, alert tuning); not smuggled into this phase.
- **Automated periodic test-restore on a schedule** - the VM restore suite (D-12/D-14) covers regression; a scheduled production-artifact drill remains deferred until the manual drills prove the paths.
- **Rationalizing the legacy `backup/backups` dataset (`dedup=on`)** - left alone per D-16 after a contents check.
- **Age-based cleanup timer inside the downloads quota** - carried from Phase 13; best after Phase 15 (Nixflix owns the import flow).

</deferred>

---

*Phase: 14-Backup Engine*
*Context gathered: 2026-08-26; revised for the snapshot-model pivot the same day*
