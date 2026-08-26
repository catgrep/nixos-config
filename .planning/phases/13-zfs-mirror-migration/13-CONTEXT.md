# Phase 13: ZFS Mirror Migration - Context

**Gathered:** 2026-08-24
**Status:** Ready for planning

<domain>
## Phase Boundary

ser8 media storage moves from two independent ext4 disks + MergerFS to a two-disk ZFS mirror (`media` pool, single `media/data` dataset at `/mnt/media`), with zero data loss and MergerFS fully retired.
Execution follows the human-gated procedure in `.planning/SER8-ZFS-MIRROR-MIGRATION.md`, as amended by the decisions below (D-01).
Every destructive step keeps its own individually-scoped approval per that doc's Approval Contract — nothing here weakens the gating.
No backup engine work (Phase 14), no Nixflix (Phase 15).

</domain>

<decisions>
## Implementation Decisions

All 17 discussion questions were answered (see `13-QUESTIONS.json` for the full Q&A record with trade-off context).
Several decisions amend the migration doc; D-01 makes that amendment the first approved step.

### Migration doc reconciliation

- **D-01 (Q-01):** The migration doc is updated FIRST, as its own approved repo-writing step, before any live work. It still reflects the pre-Phase-12 world (qBittorrent/wgnord/nginx in the freeze set, Steps 0.2/0.3 targeting already-fixed blockers, qBittorrent tests in 5.4, stale Handoff Status). The amendment also folds in D-04 (short SMART), D-08 (send/recv restore), D-02/D-03 (freeze set and quiesce timing), and D-16 (staging destroy trigger). Safety and approval-contract language is not weakened.
- **D-02 (Q-02):** Freeze scope is ALL APP services on ser8 — the media stack (jellyfin, radarr, sonarr, bazarr, prowlarr, sabnzbd, nzbget, samba-smbd, samba-wsdd), the three orchestration oneshots (`media-config`, `servarrs-setup`, `download-clients-setup`), household apps (Mealie, Homebox, Actual, Donetick), Frigate, Home Assistant, and Mosquitto. Infrastructure stays up: sshd, networking, Tailscale, node/zfs exporters, nix-daemon. Camera recording pauses while Frigate is down; the operator accepts this.
- **D-03 (Q-02 timing):** The quiesce starts BEFORE the initial copy (Stage 2), not at the doc's Stage 3 freeze. Consequences: one clean copy pass against a frozen source, the delta-sync step disappears, any verification difference is a real error (no "expected live-write drift" category), and the staging capacity margin freezes at quiesce time. Total app downtime ~23 h with both large transfers running overnight.
- **D-04 (Q-16):** Extended SMART surface scans are dropped. The gate is a counters read plus the SHORT self-test (~2 min/disk) on both approved 12 TB disks before the erase step. The refuse-if-failing rule stays: nonzero pending/reallocated/offline-uncorrectable sectors or a failed short test blocks the erase. ZFS-01 and ROADMAP Phase 13 criterion 1 must be reworded to say "short SMART health test gate" explicitly.
- **D-05 (Q-03):** Phase 12's fixes (wgnord loop elimination via stack deletion, Radarr root cleanup) are trusted via their evidence records — no live re-verification step. Link `.planning/phases/12-fleet-repair/` evidence in the amended doc.

### Data flow and verification

- **D-06:** The migration has two legs with different mechanisms: Leg 1 ext4 source → `backup/media-staging` via rsync (source is ext4, no ZFS-aware option), Leg 2 staging → `media` mirror via `zfs send/recv`.
- **D-07 (Q-12):** Leg 1 verification (gate 3.3, the last check before the ext4 disks are erased) is SAMPLED: deterministic per-file samples — head + tail + 1 MiB per GiB of file, offsets derived from file size so the identical bytes compare at every hop — plus files <1 MiB hashed fully, plus a 100% metadata comparison (size, mtime, mode, numeric uid/gid, type, symlink targets, hardlink grouping via `-H`, ACLs, xattrs — not literal inode numbers). Measured cost ~21 min vs ~10.8 h for full `rsync -c`. Layered backstops: rsync in-flight checksums during the copy, ZFS at-rest checksums on staging, the scrub. **Gate semantics: the verification dry-run reports differences with exit 0 — the gate is "itemized output is empty", enforced by the wrapper script, never the exit status.**
- **D-08 (Q-17):** Leg 2 is `zfs snapshot backup/media-staging@verified` (after gate 3.3 passes) then `zfs send -s | zfs recv` into `media/data`. Restore integrity is intrinsic (block-checksummed stream, verified on receive, bit-identical by construction) — the doc's gate 5.2 comparison disappears, replaced by "first scrub clean". `@verified` is a named rollback point; `send -s` resume tokens survive interruption. Receive unmounted (`recv -u`), set `mountpoint=/mnt/media` as an explicit step. Amends the doc's Stage 5 rsync procedure.
- **D-09:** rsync's in-flight checksums are protocol-internal and cannot be exported to a manifest — the explicit gate 3.3 is an independent re-read, which is its actual value. Local-transfer risk is dominated by *detected* failures (disk UREs ~7%/full pass on these Exos drives, SATA CRC — both surface as errors); the silent vector is non-ECC-protected RAM, which sampling + layered checksums proportionately covers for media data.

### Plan structure and approval mechanics

- **D-10 (Q-04):** One GSD plan per doc stage (~7 plans): 0 preflight + doc update, 1 repo change, 2 staging + initial copy, 3 gate 3.3 verification, 4 destructive cutover, 5 send/recv restore + startup, 6 scrub + staging destroy + cleanup. Plan boundaries = stage boundaries = session boundaries; each SUMMARY.md documents one rollback-matrix row. Estimated ~5 h hands-on across ~9 sittings, ~2.5 days elapsed. Plans 13-04 and 13-05 (freeze-to-erase arc) need continuous operator presence; the rest are launch-and-walk-away or quick reviews.
- **D-11 (Q-05):** Approval gates are hybrid: structured AskUserQuestion gates (purpose / exact commands / targets / mutation class / rollback, options Approve-Modify-Abort) for routine steps; typed echo-back (operator types the step id or WWN suffix) for disk-mutation steps 4.2-4.4 and the staging destroy. Mirrors the doc's two-tier contract. Never batch-approve numbered steps.
- **D-12 (Q-06):** Stage-per-session cadence: launch long ops detached, end the session; the next session starts by verifying the completed op (exit status + journal log) before requesting the next gate.
- **D-13 (Q-07):** Long-running ops run as `systemd-run` transient units on ser8 (e.g. `--unit=media-staging-rsync`): survives SSH drops, journald captures the complete log, exit status machine-checkable via `systemctl status`.
- **D-14 (Q-08):** The agent executes commands (including destructive ones) over SSH after the applicable gate passes, then immediately verifies only the approved targets changed. Phase 12 proved SSH + passwordless sudo works from the sandboxed session.

### Repo strategy and cutover sequencing

- **D-15 (Q-09):** The storage change lives on a feature branch through the cutover; ser8 builds/tests/switches from the branch at Step 4.5; merge to main immediately after the switch succeeds. Rationale: after Step 1.1 the repo declares a `media` pool that does not exist until Step 4.4 — mid-migration, main must always describe a bootable ser8. The plan carries the branch name across sessions.
- **D-16 (Q-10):** Before activation, runtime-mask all media units and orchestration oneshots (everything is `wantedBy = multi-user.target` and would start against the empty mirror — Radarr/Sonarr rescans of an empty root can mangle file records). Unmask inside the approved service-start step. Activation precedes restore because (a) mount/import config fails fast against the empty pool, (b) after the erase, the boot default must not reference the dead ext4 mounts (an unexpected reboot mid-restore recovers into a consistent state with a `send -s` resume token), (c) the doc's own "evaluated and live mount configuration agree" criterion. `make test-ser8` then `make switch-ser8` as separately approved steps.

### Capacity and staging lifecycle

- **D-17 (Q-11):** Go/no-go floor: ≥1.5 TB free on the backup pool after the staging projection, checked before creating staging. Measured 2026-08-24: media 8.94 TB (growing ~105 GB/day until quiesce), backup avail 11.11 TB → ~2.16 TB projected margin. The margin freezes at quiesce (D-03 stops both download growth and Frigate camera churn).
- **D-18 (Q-13):** `backup/media-staging` is destroyed at the earliest safe point: immediately after the first scrub completes clean AND the Step 5.4 application tests pass — same day services return, no multi-day observation window. The destroy remains its own individually-approved step with the scrub result presented in the approval. — **Reversibility:** one-way once executed — after the destroy, the mirror is the sole copy of the media; recovery from any later fault is limited to whatever ZFS redundancy provides. Clarified: media CONTENT is never part of Phase 14 backups (BKP-07 is app state only); the 2×12 TB mirror is the media's sole and sufficient home by design.

### Storage layout: downloads relocation (added 2026-08-24, post-finalize)

- **D-21:** Downloads move OFF the media pool to a dedicated `rpool/safe/downloads` dataset on the NVMe with a **500G quota** (mountpoint at planner's discretion, e.g. `/mnt/downloads`). Imports COPY from SSD to `media/data`; usenet has no seeding, so the download copy is deleted after import per the arr apps' completed-download handling. Rationale: the hardlink design became vestigial when torrents were retired (Phase 12); the SSD absorbs the ~2x download+unpack write churn and its random I/O; the mirror receives one clean sequential write per import; the quota IS the hard-cap downloads governance the operator asked for; failed imports can never again bloat the media pool. Measured basis: rpool 853 GB free, NVMe at 6% wear (22.3 TB written of ~220 TBW rated). Implemented in Phase 13's FINAL plan — off the storage-freeze critical path. Surface: `zfs create` + disko declaration parity, SABnzbd/NZBGet directory moves, arr download-client path updates, impermanence rule updates. — **Reversibility:** reversible — moving downloads back onto the mirror later is a config change plus a data move.
- **D-22:** Ripples folded into existing deliverables: the migration doc's "one dataset so hardlinks can cross" rationale is rewritten (`media/data` stays a single dataset for simplicity, no longer out of hardlink necessity); the cross-directory hardlink smoketest in ZFS-04 and ROADMAP criterion 4 is REPLACED by the import-write test (rewording rides with D-04's requirement edits); Phase 15's Nixflix download-client declarations must use the new paths from day one.
- **D-23 (documentation style — operator instruction, applies beyond this phase):** Code comments and documentation outside `.planning/` and agent-specific files must NEVER use GSD terminology (plans, phases, plan IDs) — translate to human-readable rationale, since GSD terms force context switches on human readers. Specifically here: the storage configuration (`disko-config.nix`, `configuration.nix`) gets detailed comments explaining the design in plain terms — `media/data` (two-disk ZFS mirror, single dataset, media libraries, one sequential write per import) and `rpool/safe/downloads` (NVMe staging for downloads, 500G quota as the size cap, temporary data on the fast disposable tier, imports copy to the mirror instead of hardlinking because nothing seeds anymore).

### Validation and cleanup

- **D-19 (Q-14):** New `scripts/smoketests/media/test-zfs-media.sh` dispatched from `media/all.sh` (deploy.yaml entry point unchanged): mount source is `media/data`, fstype ZFS not fuse.mergerfs, pool online, mirror membership by exact WWN, canonical directories exist, service access, and a controlled import-write test (test file lands on `media/data` with correct ownership/permissions, then removed) — the cross-directory hardlink assertion is dropped per D-22.
- **D-20 (Q-15):** The MergerFS documentation sweep (CLAUDE.md host description, `hosts/ser8/README.md`, code comments) lands in this phase's final plan — Phases 14/15 sessions read those files.

### Claude's Discretion

- Exact wording of the doc amendments (D-01) within the decided technical content.
- `boot.zfs.extraPools` handling, mergerfs package removal, `/mnt/disk1`//`/mnt/disk2` reference cleanup, impermanence tmpfiles interaction — per the doc's Repository Changes section.
- Sampled-verify script implementation (language, manifest format, storage location — must survive the outage; `/persist` or `/mnt/backups` both qualify).
- systemd-run unit naming and log-retrieval conventions.
- Ordered service stop/start lists within the D-02 scope.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Execution contract
- `.planning/SER8-ZFS-MIRROR-MIGRATION.md` — THE migration procedure: approval contract, approved disk inventory (WWNs, serials), safety rules, numbered execution plan, rollback matrix. Written 2026-08-13 and stale in known ways; D-01 amends it as the first approved step. Until amended, the decisions in this CONTEXT.md override it where they conflict (freeze set, Step 0.4, Stage 5 mechanism, quiesce timing).
- `.planning/phases/13-zfs-mirror-migration/13-QUESTIONS.json` — full Q&A record: all 17 decisions with trade-off context, measured data, and chat clarifications.

### Requirements and roadmap (targets of D-04 rewording)
- `.planning/REQUIREMENTS.md` — ZFS-01..05; ZFS-01 "extended SMART" must become "short SMART health test gate"; ZFS-03's restore-verification wording must reflect send/recv + scrub.
- `.planning/ROADMAP.md` — Phase 13 goal and success criteria; criterion 1 needs the same SMART rewording.

### Prior-phase facts
- `.planning/phases/12-fleet-repair/12-CONTEXT.md` and `evidence/` — trusted per D-05: qBittorrent/wgnord stack deleted, Radarr roots clean, media identity confirmed 1100/1100 (not the doc-era 1002/992 hypothesis), uid-38 ownership remediated post-phase.
- `.planning/STATE.md` — Phase 12 decision log entries (sabnzbd uid pin 985, orchestration history).

</canonical_refs>

<code_context>
## Existing Code Insights

### Change surface
- `hosts/ser8/disko-config.nix:113-160` — `media-disk1`/`media-disk2` ext4 declarations to replace with ZFS members of pool `media` (WWNs preserved exactly); `backup` zpool block is the in-repo pattern for zpool declarations.
- `hosts/ser8/configuration.nix:155-168` — MergerFS `fileSystems."/mnt/media"` to remove; `:251-252` mergerfs packages; `boot.zfs.extraPools = [ "backup" ]` gains `"media"`; ZFS services (scrub, ZED, exporter) already enabled.
- `hosts/ser8/impermanence.nix:160-175` — `/mnt/media` tmpfiles directory rules; keep unless they conflict with the ZFS-native mount.
- `hosts/ser8/media/orchestration.nix` — the three oneshots, all `wantedBy = multi-user.target` (the D-16 masking hazard).
- `scripts/smoketests/media/all.sh` — single 106-line file; new checks go in `test-zfs-media.sh` per D-19 (ser8 suite shows the all.sh-dispatches-test-*.sh convention).

### Measured facts (ser8, 2026-08-24 — re-verify at Step 0.1)
- Media disks (both ST12000NM0117): sequential read 245-255 outer / 211-216 middle / 144-146 MB/s inner; random 1 MiB read ~39 ms.
- Backup pool disks ~180-200 MB/s; RAID-Z2 streaming ~380 MB/s effective; new-mirror write ≈ single-disk ~230 MB/s.
- Media tree: 11,847 files / 8.94 TB (1,267 files <1 MiB; 6,615 >100 MiB; avg big file 1.35 GB). Grew from 7.788 TB on 08-13 (~105 GB/day).
- Backup pool: 11.11 TB avail, cameras 394 GB. Projected post-staging margin ~2.16 TB vs the 1.5 TB floor.
- rsync 3.4.4 (negotiates xxh128 — hash choice is never the bottleneck; md5sum measured 930 MB/s single-thread).
- Passwordless sudo works over SSH from the sandboxed session; SOPS editing does not (Phase 12 finding).
- Kernel names have SWAPPED vs the doc snapshot (sde ↔ sdf); WWN paths are the only valid identifiers — live demonstration of the doc's safety rule.

### Timing model (from measurements)
- Each full 8.94 TB pass ≈ 10.7 h; scrub ≈ 11.7 h. With sampled gate 3.3 + send/recv: ~23 h app downtime, ~2.5 days elapsed, both large transfers overnight.

</code_context>

<specifics>
## Specific Ideas

- The operator drove every major optimization from measured data: demanded real disk benchmarks before accepting duration claims, proposed sampled verification, and asked the question that led to send/recv. The planner should preserve this evidence-first posture — present measured numbers in gates, not estimates.
- Sampling insight worth preserving: sampled effective throughput is ~27 MB/s (seek-bound) vs 231 MB/s sequential, so sampling only beats a full read below ~12% coverage — there is no useful middle ground between ~0.4% sampled and 100%.
- The operator's risk posture, stated explicitly: transfer integrity matters; medium provenance and bitrot paranoia for replaceable media do not. Uptime during the migration also explicitly does not matter (full app quiesce accepted).
- Gate scripts must fail on non-empty rsync itemized output, never on exit status (rsync exits 0 with differences).

</specifics>

<deferred>
## Deferred Ideas

- **Downloads tree size governance**: ABSORBED into D-21 (2026-08-24) — the 500G quota on `rpool/safe/downloads` is the hard cap, made possible because torrent retirement removed the hardlink constraint. Still deferred: an age-based cleanup timer for stale failed/incomplete items *inside* the quota'd dataset, best after Phase 15 (Nixflix owns the import flow).
- The doc's existing note stands: revisiting auto-snapshots for `media/data` after measuring churn is a post-phase consideration.

**Pre-phase cleanup record (2026-08-24, before planning):** the operator deleted large titles via Radarr/Sonarr and pruned the entire downloads tree (1.98 TB of verified failed imports / torrent-era leftovers, zero hardlinks into libraries). Media payload is now 5.728 TB (verified byte-exact) → per-pass ~6.9 h, app downtime ~16 h, staging margin ~5.4 TB. One casualty: `movies/Tenet (2020)` was a manual symlink into downloads (now dangling; removal/re-grab is the operator's call). The measured-facts section above predates this cleanup — Step 0.1 re-measures live.

</deferred>

---

*Phase: 13-ZFS Mirror Migration*
*Context gathered: 2026-08-24*
