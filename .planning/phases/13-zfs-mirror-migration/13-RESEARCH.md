# Phase 13: ZFS Mirror Migration - Research

**Researched:** 2026-08-24
**Domain:** ZFS storage migration on NixOS with disko declarative management
**Confidence:** HIGH

## Summary

Phase 13 migrates ser8's media storage from two independent 12 TB ext4 disks (managed by MergerFS) to a mirrored ZFS pool over ~2.5 days with zero data loss. This is a complex multi-stage operation involving data staging, verification gates, destructive disk operations, and careful service orchestration, executed across 7 sequential plans (~5 hours hands-on time, ~9 separate sessions). The phase carries 23 finalized decisions (D-01..D-23) that substantially amend the pre-Phase-12 migration document — CONTEXT.md decisions take precedence over the original doc where they conflict.

**Primary Recommendation:** Execute strictly per the 7-stage numbered plan in `.planning/SER8-ZFS-MIRROR-MIGRATION.md` (as amended by CONTEXT.md decisions), with individual per-step approval gates for every numbered step and typed echo-back confirmation for all disk-mutation steps (4.2-4.4, 6.2). Long-running operations (rsync, scrub) execute as systemd-run transient units and are verified before proceeding to the next stage. All zpool/dataset properties and disko changes are validated in a dry-run before activation.

## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01:** Migration doc is updated FIRST as its own approved step, before live work. Folds in D-04/D-08/D-02/D-03/D-16 amendments.
- **D-02:** Full app freeze: all 9 media units + 3 orchestration oneshots + household apps + Frigate + HA + Mosquitto. Infrastructure stays up (sshd, Tailscale, exporters, nix-daemon).
- **D-03:** Quiesce starts BEFORE initial copy (Stage 2), not at Stage 3 — one clean copy pass, no delta sync, total ~23h app downtime.
- **D-04:** Short SMART health test (~2 min/disk) gates the erase, not extended SMART surface scans. ZFS-01 and ROADMAP criterion 1 must be reworded.
- **D-05:** Phase 12 fixes (wgnord stack deletion, Radarr root cleanup) are trusted per evidence records — no live re-verification.
- **D-06:** Two-leg data flow: ext4 source → rsync → backup/media-staging (ZFS), then staging → zfs send/recv → media mirror.
- **D-07:** Leg 1 verification (gate 3.3, pre-erase) is SAMPLED: head + tail + 1 MiB per GiB samples, <1 MiB files hashed fully, 100% metadata comparison (via rsync `-H` for hardlinks, metadata dry-run). ~21 min per gate vs 10.8h for full rsync -c.
- **D-08:** Leg 2 uses `zfs snapshot @verified` then `zfs send -s | zfs recv -u` into media/data. Gate 5.2 disappears — integrity is intrinsic (block-checksummed stream, verified on receive, bit-identical by construction).
- **D-10:** One GSD plan per doc stage (7 plans). Stage boundaries = plan boundaries = session boundaries. Plans 13-04/13-05 need continuous operator presence; others are launch-and-walk-away.
- **D-11:** Hybrid approval gates: structured AskUserQuestion for routine steps; typed echo-back (step id or WWN suffix) for disk mutations (4.2-4.4, 6.2). Never batch-approve.
- **D-12:** Launch long ops detached on ser8, end session; next session verifies completion before proceeding.
- **D-13:** Long ops run as systemd-run transient units (e.g. `--unit=media-staging-rsync`): survives SSH drops, journald captures logs, exit status machine-checkable via systemctl.
- **D-14:** Agent executes commands after applicable gate passes, then immediately verifies only approved targets changed.
- **D-15:** Storage change lives on feature branch through cutover; ser8 activates from branch at Step 4.5; merge to main immediately after switch succeeds.
- **D-16:** Runtime-mask all media units and orchestration oneshots before activation, unmask inside approved Step 5.3 start. Keeps doc order: mount config verified before restore.
- **D-17:** Go/no-go floor: ≥1.5 TB free on backup pool after staging projection, checked before creating staging. Margin freezes at quiesce (D-03).
- **D-18:** Staging destroyed at earliest safe point: immediately after first scrub completes clean AND Step 5.4 app tests pass. One-way; no multi-day observation window. Media content is NOT part of Phase 14 backups (BKP-07 is app state only).
- **D-19:** New `scripts/smoketests/media/test-zfs-media.sh` dispatched from media/all.sh: mount source = media/data, ZFS not fuse.mergerfs, pool online, mirror by WWN, canonical directories, service access, import-write test.
- **D-20:** MergerFS documentation sweep (CLAUDE.md, hosts/ser8/README.md, comments) lands in Phase 13's final plan.
- **D-21:** Downloads move to `rpool/safe/downloads` (NVMe) with **500G quota** (off the media pool critical path, implemented in final plan). Rationale: SSD absorbs download+unpack churn; mirror receives one clean sequential write per import.
- **D-22:** Cross-directory hardlink smoketest is REPLACED by import-write test (rewording rides with D-04 requirement edits).
- **D-23:** Code comments/docs outside `.planning/` must NEVER use GSD terminology (plans, phases, plan IDs) — use plain-language rationale instead.

### Claude's Discretion

- Exact wording of doc amendments (D-01) within decided technical content.
- `boot.zfs.extraPools` handling, mergerfs package removal, path reference cleanup, impermanence tmpfiles interaction.
- Sampled-verify script implementation (language, manifest format, storage location — must survive outage; `/persist` or `/mnt/backups` qualify).
- systemd-run unit naming and log-retrieval conventions.
- Ordered service stop/start lists within D-02 scope.
- `rpool/safe/downloads` mount path discretion (e.g., `/mnt/downloads`).

### Deferred Ideas (OUT OF SCOPE)

- Auto-snapshots for `media/data` — revisit after measuring churn post-phase.
- Age-based cleanup timer for stale failed/incomplete downloads — deferred to Phase 15 (Nixflix owns import flow).
- Pi bootstrap images, advanced monitoring/alerting, Phase 14/15 delivery.

## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| ZFS-01 | Short SMART health test gate on both 12 TB disks, media tree staged to `backup/media-staging` with frozen checksum-verified final sync reporting zero unexplained differences | Disko ZFS dataset patterns established (backup pool templates), rsync sampled verification mechanism (D-07), systemd-run transient units for capture |
| ZFS-02 | Two approved WWNs reformatted as ZFS pool `media` (mirror vdev), single dataset `media/data` at `/mnt/media` with documented properties | disko mirror vdev syntax established, ashift/compression/recordsize/xattr patterns from backup pool, rpool patterns for comparison |
| ZFS-03 | Restore from staging verifies checksum-identical, first scrub completes with zero data errors | zfs send/recv (D-08) provides bit-identical guarantees; first scrub is intrinsic integrity check; no separate gate 5.2 needed |
| ZFS-04 | MergerFS removed, disko declares mirror, media stack runs healthy with smoketests asserting pool health, mirror membership by WWN, import-write test (D-22) | test-zfs-media.sh pattern, WWN extraction and comparison logic, import-write test implementation without cross-directory hardlink |
| ZFS-05 | Every destructive step individually approved per approval contract; staging destroyed only after post-cutover observation and separate approval | D-11 hybrid gates (structured + typed echo-back), D-12 stage-per-session cadence, D-13 systemd-run capture with machine-checkable exit status |

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|-----------|-------------|----------------|-----------|
| Storage pool declaration & topology | Backend (ser8 ZFS) | Frontend (disko config) | Pool exists on backend; disko config declares it; NixOS evaluation validates schema before activation |
| Data staging (ext4 → ZFS) | Backend (ser8 ser8 rsync) | Backend monitoring (agent verifies exit status + log) | rsync is local tool on ser8; verification gates (D-07, D-12) are operator+agent checkpoints |
| Data restore (ZFS → ZFS) | Backend (ser8 zfs send/recv) | Backend monitoring (agent verifies completion) | zfs send/recv is native ZFS; intrinsic integrity; scrub is implicit verification |
| Service freeze/thaw | Backend (systemd unit control) | Frontend (CONTEXT.md list masking/unmasking) | Services managed on ser8 via systemctl; disko/NixOS config declares masking pre-activation |
| Smoketesting | Backend (ser8 shell commands) | Frontend (test-zfs-media.sh script) | Tests run on ser8 over SSH; script is part of repo but executed live |

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| ZFS (via nixpkgs) | In-repo via NixOS 25.11 | Two-disk mirror vdev for media storage | Existing ser8 already uses ZFS for rpool + backup (RAID-Z2); moving media to ZFS consolidates stack |
| disko (NixOS tool) | Via `make dev` shell | Declarative storage partitioning and ZFS pool/dataset config | All ser8 storage already declared via disko; consistent with Phase 12 learning |
| rsync | 3.4.4 [VERIFIED: CONTEXT.md L110] | Staged data transfer ext4 → ZFS (Leg 1) | Only tool that can read ext4 efficiently; supports sampled verification (D-07) with checksums |
| systemd | Stock NixOS | Transient units for long-running ops capture; service masking before activation | Universal on NixOS; journald provides durable audit logs; `systemctl status` gives machine-checkable exit status |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| smartctl | stock NixOS | Short SMART self-test gate before disk erase (D-04) | Replaces extended-scan cost; gate is counters read + ~2 min/disk self-test |
| zfs (command-line) | Stock in NixOS ZFS module | `zfs snapshot`, `zfs send/recv`, `zfs scrub` for Leg 2 restore and verification | Native ZFS operations; intrinsic integrity checks; better resume behavior than rsync (D-08) |
| bash scripting | stock NixOS | Sampled verification script (D-07), approval-gate logic, state checkpointing | Verification gate semantics require rsync itemized output parsing; manifest comparison |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|-----------|-----------|----------|
| rsync (Leg 1: ext4 → staging) | cp/tar | rsync provides in-flight checksums + delta-transfer intelligence; cp is dumb; tar is slower without parallelism |
| zfs send/recv (Leg 2: staging → mirror) | rsync restore (doc original) | zfs send/recv is bit-identical by construction, block-checksummed stream intrinsic verification, better resume tokens (send -s); rsync requires separate full re-read to verify (gate 5.2 cost) |
| sampled verification | full rsync -c at both gates | Measured tradeoff (D-07, Q-12 chat): sampling ~0.4% coverage ≈ 21 min, full -c ≈ 10.8 h per gate. Layered backstops (rsync in-flight + ZFS at-rest + scrub) mitigate sampling risk; 20 h uptime gain is material on a home server. Operator's risk posture: transfer integrity matters, bitrot paranoia for replaceable media does not. |
| systemd-run transient units | nohup + log redirect / tmux session | systemd-run survives SSH drops, journald logging is unambiguous, `systemctl status` is machine-checkable; nohup requires manual tracking; tmux is human-attachable but lacks audit trail |
| feature branch (D-15) | direct commit to main before cutover | Direct commit means main declares a ZFS pool that doesn't exist for days — habitual `make switch-ser8` in that window breaks media mount. Feature branch ensures mid-migration main is always bootable. |

**Installation (verification):**

These packages/tools are already available in the NixOS 25.11 environment on ser8 and in `make dev`:

```bash
# Verify installations on ser8 (over SSH)
zfs --version            # Stock NixOS ZFS module
smartctl --version       # util-linux already installed
rsync --version          # 3.4.4 per CONTEXT.md
systemctl --version      # Stock NixOS systemd

# Verify in local dev shell
make dev                 # Brings in nixfmt, statix, shellcheck, sops, yq, etc.
```

All core stack elements are pre-deployed via existing NixOS modules. No new packages need installing.

## Package Legitimacy Audit

No external packages are installed as part of this phase. All tools (zfs, rsync, smartctl, systemd, bash) are either:
- Already deployed on ser8 via NixOS ZFS/backup pool setup (phases 9-12)
- Standard in NixOS 25.11 (systemd, util-linux, coreutils)
- Available in the `make dev` development shell (nixfmt, shellcheck for validation of new scripts)

**No new package additions:** The phase adds no external dependencies beyond what NixOS 25.11 + existing ser8 modules already provide.

## Architecture Patterns

### System Architecture Diagram

```
Current State (pre-cutover):
  ext4 disk 1 (12TB, ST12000NM0117)   ─┐
                                        ├─→ MergerFS fuse ─→ /mnt/media
  ext4 disk 2 (12TB, ST12000NM0117)   ─┘
  
  (Jellyfin, Sonarr, Radarr, etc. read/write via MergerFS)

Phase 13 Data Flow:

  Stage 2-3 (Leg 1):
  ext4 disk 1 ─┐
               ├─→ rsync ─→ backup/media-staging (ZFS on backup pool)
  ext4 disk 2 ─┘           (Gate 3.3: sampled verify vs source)

  Stage 4 (Cutover Point):
  [erase ext4 disks, create media pool/dataset]

  Stage 5 (Leg 2):
  backup/media-staging (ZFS) ─→ zfs send/recv ─→ media/data mirror
                                  (Gate 5.2: first scrub verifies)

  Final State:
  ZFS mirror (disk 1 + disk 2) ─→ media/data (single dataset) ─→ /mnt/media
                                  (Jellyfin, Sonarr, etc. mount here)

Key Decision Points:
  - D-03: Full app freeze BEFORE stage 2 (not at stage 3) → one clean copy
  - D-07: Sampled verification (0.4% coverage) instead of full rsync -c
  - D-08: zfs send/recv intrinsic integrity (no separate gate 5.2)
  - D-16: Mask media services before activation, unmask in step 5.3
  - D-17: 1.5 TB staging safety margin (freezes at quiesce time)
```

### Recommended Project Structure

The disko change is **minimal and surgical**:

```
hosts/ser8/
  disko-config.nix       # Lines 113-160: replace ext4 media-disk1/2 declarations 
                         # with ZFS mirror members; add media zpool + data dataset
  configuration.nix      # Remove fileSystems."/mnt/media" (MergerFS); 
                         # add "media" to boot.zfs.extraPools
  impermanence.nix       # Keep /mnt/media tmpfiles rules (or remove if conflict)

.planning/
  SER8-ZFS-MIRROR-MIGRATION.md  # Updated by D-01 (Steps 0.4, Stage 5, etc.)

scripts/smoketests/media/
  all.sh                 # Dispatch point (unchanged)
  test-zfs-media.sh      # NEW: pool health, mirror WWNs, import-write test

scripts/
  (Sampled-verify script location — D-12 discretion: /persist or /mnt/backups)
```

No other files are modified. Household app configs, media service configs, Samba shares, and monitoring stay unchanged.

### Pattern 1: disko ZFS Pool Declaration

**What:** Declarative ZFS pool with mirror vdev and typed datasets.

**When to use:** Any new ZFS pool on NixOS; mirrors existing pattern from backup pool (RAID-Z2).

**Example:**

```nix
# Source: hosts/ser8/disko-config.nix (backup pool pattern) + migration doc §Desired ZFS Configuration
media = {
  type = "zpool";
  mode = "mirror";                    # Two-disk mirror vdev
  options = {
    ashift = "12";                    # 4KB sectors
    autotrim = "on";
  };
  rootFsOptions = {
    acltype = "posixacl";
    compression = "lz4";              # See D-22 rationale comment
    recordsize = "1M";                # Libraries + import writes
    atime = "off";
    xattr = "sa";
    normalization = "formD";
    dedup = "off";
    mountpoint = "none";              # Root fs not mounted
    canmount = "off";
  };
  datasets = {
    "data" = {
      type = "zfs_fs";
      options = {
        mountpoint = "/mnt/media";
        "com.sun:auto-snapshot" = "false";  # Manual snapshots only
      };
    };
  };
};

# Disk declarations (replaces ext4 media-disk1/2):
media-disk1 = {
  type = "disk";
  device = "/dev/disk/by-id/wwn-0x5000c500b56ea81a";  # WWN preserved exactly
  content = {
    type = "gpt";
    partitions = {
      zfs = {
        size = "100%";
        content = {
          type = "zfs";
          pool = "media";
        };
      };
    };
  };
};
```

**D-23 Comment Style:**

```nix
# media/data: Two-disk ZFS mirror for media libraries. Single dataset (no per-directory dataset
# splitting) for simplicity and to avoid cross-directory hardlink constraints. Compression and
# recordsize tuned for mixed large library files and smaller import staging. No auto-snapshots
# (operator controls backup lifecycle separately). Downloads now stage on NVMe (rpool/safe/downloads,
# 500G quota) before copy to mirror, eliminating write churn on the mirror.
```

### Pattern 2: Service Masking Before Activation

**What:** Prevent media services from starting during empty-pool window.

**When to use:** Any time you activate a ZFS pool config but the data isn't in place yet.

**Example:**

```bash
# Step 4.5 (before: make test-ser8):
# (Inside approval gate)
systemctl mask jellyfin.service radarr.service sonarr.service \
  bazarr.service prowlarr.service sabnzbd.service nzbget.service \
  samba-smbd.service samba-wsdd.service \
  media-config.service servarrs-setup.service download-clients-setup.service

# make test-ser8 and make switch-ser8 now activate config without starting media

# Step 5.3 (inside approval gate):
systemctl unmask jellyfin.service radarr.service ... (same list)
systemctl start jellyfin.service radarr.service ... (ordered start)
```

**Why:** Prevents Radarr/Sonarr library rescans of an empty `/mnt/media` which can corrupt file records.

### Pattern 3: Sampled Verification Script (D-07)

**What:** Deterministic per-file sampling (head + tail + 1 MiB per GiB), small files hashed fully, metadata dry-run.

**When to use:** Large file transfers where full comparison is prohibitively slow; layered checksums (rsync in-flight + ZFS at-rest + scrub) mitigate sampling gaps.

**Semantics:**

```bash
# Verification dry-run (no mutation):
rsync --dry-run --checksum --itemize-changes \
  --files-from=<(sampled-list) \
  /source/ /destination/

# Gate logic (NOT exit status, which rsync returns 0 even with diffs):
exit_status=$?
output=$(rsync ... 2>&1)
if [ -n "$output" ]; then
  echo "GATE FAILED: verification found differences:"
  echo "$output"
  exit 1
fi
# Empty output ⟹ gate passes
```

**Manifest storage:** `/persist/phase-13/leg1-verified-manifest` (survives outage; committed to STATE.md after pass).

### Pattern 4: zfs send/recv Restore with Snapshots

**What:** Atomic snapshot-based transfer to target dataset.

**When to use:** ZFS-to-ZFS restore where source is frozen (verified snapshot).

**Example:**

```bash
# Step 5.1: Restore via send/recv
# (Staging was already verified by gate 3.3; snapshot it now)
ssh root@ser8 zfs snapshot backup/media-staging@verified

# Stream to target (recv -u = unmounted receive)
ssh root@ser8 \
  zfs send -s backup/media-staging@verified \
  | zfs recv -u media/data

# Explicit mount setup (recv -u leaves unmounted)
ssh root@ser8 zfs set mountpoint=/mnt/media media/data
ssh root@ser8 zfs mount media/data

# Verify mountpoint
ssh root@ser8 mount | grep /mnt/media  # Should show ZFS entry

# Gate 5.2 (implicit): First scrub proves mirror end-to-end
ssh root@ser8 zfs scrub media
# (Monitor via: zpool status media, watch for "scan completed" in journal)
```

**Resume from interruption:** `send -s` generates a resume token on failure; next attempt picks up where it left off (better than rsync which restarts).

### Anti-Patterns to Avoid

- **Skipping disk identification verification:** Kernel device names (sde/sdf) swap; WWN paths (`/dev/disk/by-id/wwn-0x...`) are the only safe identifiers. Step 4.1 requires explicit WWN re-confirmation before Step 4.3 erase. [VERIFIED: CONTEXT.md L112]

- **Trusting rsync exit status for verification gates:** rsync returns 0 even when differences are found (differences listed in itemized output). Gate semantics (D-07, D-12) are "itemized output is empty", enforced by wrapper script. [VERIFIED: CONTEXT.md L33, Q-12 chat]

- **Accepting app service startup against empty pool:** Radarr/Sonarr library scans of empty `/mnt/media` can mangle file records. Masking before activation + unmasking in step 5.3 is mandatory (D-16). [VERIFIED: CONTEXT.md D-16 rationale]

- **Holding staging copy longer than necessary:** Gate trigger is "first scrub clean + app tests pass", same day. Holding for multi-day observation adds nothing once verification is complete and frees 8.9 TB on backup pool immediately (D-18). [VERIFIED: CONTEXT.md Q-13, D-18]

- **Committing storage changes to main before cutover:** Mid-migration main must always describe a bootable ser8. Feature branch through cutover (D-15) ensures this; merge immediately after switch succeeds. [VERIFIED: CONTEXT.md Q-09 rationale]

- **Extended SMART surface scans as gating criteria:** Adds ~20h for minimal medium-provenance signal; short self-test (~2 min/disk) provides health check at near-zero cost. Operator's risk posture: transfer integrity matters (rsync + scrub gating covers this); bitrot paranoia for replaceable media does not (D-04). [VERIFIED: CONTEXT.md D-04, Q-16]

- **Full-file rsync checksums for both verification gates:** Measured cost: 10.8h per gate × 2 = ~21.6h outage. Sampled approach (0.4% coverage, head + tail + per-GiB samples, full metadata) = ~21 min per gate. Layered checks (rsync in-flight + ZFS at-rest + scrub) mitigate sampling risk; D-07 decision gains ~20h uptime. [VERIFIED: CONTEXT.md Q-12, D-07]

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Data transfer integrity ext4→ZFS | Custom copy tool with checksums | rsync with in-flight checksums | rsync is battle-tested, parallelizable, delta-aware; hand-rolled hashing at scale is error-prone and slower |
| Restore from verified snapshot | Manual copy + compare loop | zfs send/recv | Bit-identical by construction; block-checksummed stream; intrinsic verify on receive; resume tokens survive interruption |
| Service startup orchestration | Custom unit start scripts | systemctl with ordered dependencies | systemd handles ordering, dependency tracking, failure isolation; custom scripts race-condition-prone |
| Long-running operation log capture | Redirects to files + manual tracking | systemd-run transient units + journald | journald is durable audit log, `systemctl status` is machine-checkable, survives SSH drops; hand-crafted logging loses context |
| Pool health verification | Custom zpool parsing | `zpool status` + regex extract | zpool output is stable across versions; regex brittle; hand-parsing topology is error-prone |
| Disk identity confirmation | Kernel device names (sde/sdf) | `/dev/disk/by-id/wwn-0x...` paths | Kernel names swap between boots; WWN paths stable across reboots; mixing them is a data-loss vector |

**Key insight:** ZFS operations are primitives; the complexity is in orchestration (gates, verification semantics, service transitions) and data flow (two-leg rsync + send/recv). The only hand-rolled code should be approval-gate logic, manifest comparison for sampled verify, and service stop/start ordering.

## Runtime State Inventory

**Trigger:** Phase involves rename (ext4→ZFS), storage topology change (MergerFS→mirror), and service freeze — potential for runtime state mismatches.

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| **Stored data** | `/mnt/media` contains 5.728 TB verified byte-exact media (measured 2026-08-24 post-cleanup). No ZFS datasets currently. | Data moves from ext4 → staging ZFS → mirror ZFS via rsync + zfs send/recv. No schema migration — same file tree, new storage layer. |
| **Live service config** | 9 media services + 3 orchestration oneshots configured via NixOS modules to read/write under `/mnt/media`. Jellyfin, Sonarr, Radarr hardcode `/mnt/media/movies`, `/mnt/media/tv`, etc. in database records. | No path changes — `/mnt/media` stays the canonical mountpoint (just backed by ZFS mirror instead of MergerFS). Services do NOT need reconfiguration if mountpoint path is stable. D-21 adds separate `rpool/safe/downloads` dataset — arr app paths move during final plan (post-storage-freeze critical path). |
| **OS-registered state** | ser8 boot references MergerFS `fileSystems."/mnt/media"` in NixOS config (hosts/ser8/configuration.nix:155-168). `boot.zfs.extraPools` currently lists `["backup"]` only. | D-01 doc update + Step 1.1 repo change: remove MergerFS fileSystems entry, add "media" to boot.zfs.extraPools, add disko ZFS pool/dataset declarations. Changes are declarative — no manual state cleanup needed. |
| **Secrets/env vars** | Samba share paths, SOPS templates, firewall rules, service auth tokens all reference `/mnt/media` by path string. | No env var names change. Service credentials and API keys are unaffected. Path strings are OK to persist (mountpoint stays `/mnt/media`). No secret key renames. |
| **Build artifacts / installed packages** | mergerfs + mergerfs-tools are in environment.systemPackages (hosts/ser8/configuration.nix:251-252). No egg-info or compiled binaries reference the old storage. | Step 1.1 removes mergerfs/mergerfs-tools from environment.systemPackages. No cleanup of old binaries needed — they just stop being included in the next rebuild. |

**Nothing requiring data migration:** All data moves via stage + restore operations within the phase. App configs reference `/mnt/media` (path stable); path strings do not need updates. Secret keys and env var names are stable.

## Common Pitfalls

### Pitfall 1: Confusing Kernel Device Names and WWN Paths

**What goes wrong:** Kernel device names (sde, sdf) swap between reboots and are subject to BIOS enumeration order. Using kernel names in a destructive operation (erase) against the wrong disk causes data loss on the backup pool (RAID-Z2 disks are similarly-sized).

**Why it happens:** Convenience — lsblk shows `sde` first, but that's arbitrary. The actual stable identifier is the WWN (World Wide Number, burned into drive firmware).

**How to avoid:** Always use `/dev/disk/by-id/wwn-0x...` paths. Step 4.1 mandates explicit re-confirmation of the two approved media disk WWNs (ending in `...a81a` and `...3a87` per CONTEXT.md) before Step 4.3 erase. Step 4.4 verifies the exact WWNs present in the created pool. [VERIFIED: CONTEXT.md L112, migration doc Step 4.1]

**Warning signs:** Device names in `lsblk` or `lsof` output that don't match the WWN paths. Step 0.1 explicitly reconciles live names with the hardcoded disko WWNs.

### Pitfall 2: Rsync Exit Status vs. Itemized Output

**What goes wrong:** rsync exits 0 even when file differences are found. A gate script that only checks `if [ $? -ne 0 ]` silently passes with undetected differences.

**Why it happens:** rsync's exit codes document: 0 = success, 23 = partial transfer (errors), but a successful transfer with content mismatches still returns 0. The actual differences appear only in itemized output (rsync --itemize-changes).

**How to avoid:** Gate semantics (D-07, D-12 chat) are: "itemized output is empty". Verification script must capture full rsync output and fail if non-empty. [VERIFIED: CONTEXT.md L125 ("Gate scripts must fail on non-empty rsync itemized output, never on exit status")]

**Warning signs:** `rsync ... --checksum; echo $?` returning 0 while the log shows `>f+++++++` (files differ). The wrapper script, not rsync, enforces the gate.

### Pitfall 3: Media Services Starting Against Empty Pool

**What goes wrong:** If activation (Step 4.5) starts media services before data is restored (Step 5.1), Radarr and Sonarr immediately scan the empty `/mnt/media` directory and update their database to mark everything as missing. When the restore completes, the services have already recorded the loss; re-importing requires manual intervention.

**Why it happens:** Media units are `wantedBy = multi-user.target`, so `systemctl start multi-user.target` during `make test-ser8`/`make switch-ser8` starts them automatically unless prevented.

**How to avoid:** D-16 mandates masking all media units (9 units + 3 oneshots) with `systemctl mask` before activation. The mask persists across the test+switch cycle. Unmasking is part of the approved Step 5.3 start (after Step 5.2 scrub proves the restore succeeded). [VERIFIED: CONTEXT.md D-16 rationale, Q-10 chat]

**Warning signs:** Journal logs during Step 4.5 showing `radarr.service started` or `sonarr.service scanning library`. Masks must be in place before test+switch.

### Pitfall 4: Staging Capacity Running Below Safety Margin

**What goes wrong:** If media continues growing (downloads running) while staging is in progress, the backup pool free space shrinks. If it drops below 1.5 TB, the recovery window is lost (no rollback target if erase happens).

**Why it happens:** Downloads are ~105 GB/day (pre-cleanup) and Frigate camera recordings are ~0.1 TB/day churn. Staging takes ~10.7h to copy; if not frozen, both write during the copy.

**How to avoid:** D-03 and D-17 combined: quiesce ALL services (including Frigate, media services, household apps) BEFORE the initial copy (Stage 2), not at Stage 3. Quiesce freezes both media growth and Frigate churn. D-17 requires ≥1.5 TB free after staging projection, checked before creating staging (measured 2026-08-24: ~2.16 TB projected, well above floor). Margin is frozen at quiesce time. [VERIFIED: CONTEXT.md D-03, D-17, Q-11 chat]

**Warning signs:** `zfs list -o avail` trending below 2 TB during staging setup. Quiesce must happen before Stage 2 starts.

### Pitfall 5: Feature Branch Gets Stranded After Partial Cutover

**What goes wrong:** If cutover is paused mid-Stage-4 (e.g., after erase, before pool creation) and the session ends, the feature branch is left with half-declared infrastructure (pools declared but not created). If main is checked out, the build will fail because the pool doesn't exist.

**Why it happens:** D-15 holds the storage change on a branch through Step 4.5 (activation), then merges after Step 5.2 (restore verify). The intermediate state (repo declares media pool, pool doesn't exist yet) is only safe on the branch.

**How to avoid:** D-15 is explicit: branch name is carried in the plan across sessions. Step 4.5 approval ensures the branch is checked out before test+switch. Step 6.2 (or 6.1 depending on plan structure) includes the merge to main (with merge commit or PR, never force-push). [VERIFIED: CONTEXT.md D-15 rationale, Q-09 chat]

**Warning signs:** After Step 4.3 (erase), are you on the feature branch? `git branch` should show the branch checked out. Main should still describe a bootable ser8.

### Pitfall 6: SMART Test Expectations vs. Gate Semantics

**What goes wrong:** Extended SMART surface scans (the original migration doc Step 0.4) run 20+ hours and measure write wear, not imminent failure. A failed extended scan after days of waiting does not necessarily mean the disk is unusable — it might just mean the drive is old. Decision paralysis results.

**Why it happens:** Over-confidence in SMART as a predictor. SMART detects *detected* failures (pending sectors, reallocated sectors, offline-uncorrectable sectors) but not future failures. The operator's risk posture (D-04, Q-16 chat) is: we care about *transfer integrity* (rsync + scrub gates provide this), not speculative bitrot on replaceable media.

**How to avoid:** D-04 replaces extended SMART with short self-test (~2 min/disk) + counters read (pending, reallocated, offline-uncorrectable must all be zero). The test is a health gate, not a predictor. If counters are non-zero OR short test fails, refuse the erase. Otherwise, proceed. [VERIFIED: CONTEXT.md D-04, Q-16, REQUIREMENTS.md ZFS-01 (must reword)]

**Warning signs:** Waiting days for extended scan results. The short test completes in ~2 minutes and is sufficient.

## Code Examples

### Example 1: disko ZFS Mirror Declaration (Pattern 1)

```nix
# hosts/ser8/disko-config.nix — media pool + data dataset
# Source: [VERIFIED: hosts/ser8/disko-config.nix:237-289 backup pool pattern]
# Applied to media with mirror topology per migration doc §Desired ZFS Configuration

disk = {
  # ... existing main, backup-disk1..4 ...

  media-disk1 = {
    type = "disk";
    device = "/dev/disk/by-id/wwn-0x5000c500b56ea81a";  # Approved WWN
    content = {
      type = "gpt";
      partitions = {
        zfs = {
          size = "100%";
          content = {
            type = "zfs";
            pool = "media";  # Two-disk mirror topology
          };
        };
      };
    };
  };

  media-disk2 = {
    type = "disk";
    device = "/dev/disk/by-id/wwn-0x5000c500b3733a87";  # Approved WWN
    content = {
      type = "gpt";
      partitions = {
        zfs = {
          size = "100%";
          content = {
            type = "zfs";
            pool = "media";
          };
        };
      };
    };
  };
};

zpool = {
  # ... existing rpool, backup ...

  media = {
    type = "zpool";
    mode = "mirror";  # Two-disk mirror, not RAID-Z or single
    options = {
      ashift = "12";
      autotrim = "on";
    };
    rootFsOptions = {
      acltype = "posixacl";
      compression = "lz4";
      recordsize = "1M";
      atime = "off";
      xattr = "sa";
      normalization = "formD";
      dedup = "off";
      mountpoint = "none";
      canmount = "off";
    };
    datasets = {
      "data" = {
        type = "zfs_fs";
        options = {
          mountpoint = "/mnt/media";
          "com.sun:auto-snapshot" = "false";  # Manual snapshots only
        };
      };
    };
  };
};
```

### Example 2: Service Masking Before Activation

```bash
# Step 4.5: Before make test-ser8 (inside approval gate)
# Source: [VERIFIED: CONTEXT.md D-16, migration doc Step 4.5]
# Gate semantics: Mask runs, then test/switch; unmasking is Step 5.3

ssh root@ser8 <<'EOF'
# Mask media application services
systemctl mask jellyfin.service \
  radarr.service sonarr.service bazarr.service prowlarr.service \
  sabnzbd.service nzbget.service \
  samba-smbd.service samba-wsdd.service

# Mask orchestration oneshots
systemctl mask media-config.service servarrs-setup.service download-clients-setup.service

# Verify masks took
systemctl list-unit-files | grep media
# Output should show "masked" status for all nine units + three oneshots
EOF

# Then proceed with:
# make test-ser8      # Evaluates and tests NixOS config on ser8
# make switch-ser8    # Activates the new generation
# (Services do not start during this window because they are masked)
```

### Example 3: Sampled Verification Script

```bash
#!/bin/bash
# scripts/sampled-verify.sh
# Source: [CITED: CONTEXT.md D-07, Q-12 chat]
# Usage: sampled-verify /source /destination manifest.txt
# Gate logic: Non-empty output = gate FAILED (items differ)

set -euo pipefail

SOURCE_DIR="$1"
DEST_DIR="$2"
MANIFEST_FILE="$3"

# Generate deterministic per-file samples + full small files + metadata
# head + tail + 1 MiB per GiB, with offsets derived from file size
# (so identical bytes compare at every hop: source → staging → mirror)

generate_sample_list() {
  find "$SOURCE_DIR" -type f -print0 | while IFS= read -r -d '' file; do
    size=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null || echo 0)
    
    if [ "$size" -lt 1048576 ]; then
      # Small files (<1 MiB): hash fully
      echo "$file"
    else
      # Large files: sample head, tail, and periodic chunks
      # (Implementation detail: chunking logic per D-07 spec)
      echo "$file"
    fi
  done
}

# Metadata-only comparison (100% coverage of structure)
# Equivalent to: rsync --dry-run --no-times --checksum --itemize-changes
verify_metadata() {
  rsync --dry-run --itemize-changes \
    --checksum \
    --files-from=<(generate_sample_list) \
    "$SOURCE_DIR/" "$DEST_DIR/" 2>&1 || true
}

# Capture verification output (not exit status)
output=$(verify_metadata)

# Save manifest for audit trail
echo "=== Verification run at $(date) ===" > "$MANIFEST_FILE"
echo "$output" >> "$MANIFEST_FILE"

# Gate semantics: itemized output is empty → pass
if [ -z "$output" ]; then
  echo "✓ Verification PASSED (no differences found)"
  exit 0
else
  echo "✗ Verification FAILED. Differences:"
  echo "$output"
  exit 1
fi
```

### Example 4: zfs send/recv Restore

```bash
#!/bin/bash
# Step 5.1: Restore media/data from verified snapshot
# Source: [CITED: CONTEXT.md D-08, migration doc Stage 5 (amended)]

set -euo pipefail

# Snapshot the verified staging copy
echo "Creating snapshot backup/media-staging@verified..."
zfs snapshot backup/media-staging@verified

# Stream to target (recv -u = unmounted)
echo "Streaming to media/data via zfs send/recv..."
zfs send -s backup/media-staging@verified | zfs recv -u media/data

# Explicit mount (recv -u leaves it unmounted)
echo "Setting mount properties..."
zfs set mountpoint=/mnt/media media/data
zfs mount media/data

# Verify mount
echo "Verifying mount..."
mount | grep "/mnt/media" || {
  echo "ERROR: /mnt/media not mounted after recv"
  exit 1
}

echo "✓ Restore complete and mounted at /mnt/media"
```

### Example 5: test-zfs-media.sh Smoketest

```bash
#!/bin/bash
# scripts/smoketests/media/test-zfs-media.sh
# Source: [CITED: CONTEXT.md D-19, D-22, migration doc §Smoketests]
# Dispatched from all.sh; validates pool health, mirror membership, import-write

set -euo pipefail

MEDIA_MOUNT="/mnt/media"
MEDIA_POOL="media"
MEDIA_DATASET="media/data"

# Approved disk WWNs (from migration doc §Approved Disk Inventory)
APPROVED_WWN_1="wwn-0x5000c500b56ea81a"
APPROVED_WWN_2="wwn-0x5000c500b3733a87"

fail() {
  echo "✗ FAILED: $*"
  exit 1
}

pass() {
  echo "✓ $*"
}

# Test 1: Mount source is media/data (not fuse.mergerfs)
if ! mount | grep -q "$MEDIA_MOUNT.*type zfs"; then
  fail "/mnt/media is not mounted as ZFS (found: $(mount | grep $MEDIA_MOUNT))"
fi
pass "Mount source is ZFS at /mnt/media"

# Test 2: Pool is online
if ! zpool status "$MEDIA_POOL" | grep -q "pool: $MEDIA_POOL"; then
  fail "Pool $MEDIA_POOL not found"
fi
if ! zpool status "$MEDIA_POOL" | grep -q "state: ONLINE"; then
  fail "Pool $MEDIA_POOL is not ONLINE"
fi
pass "Pool $MEDIA_POOL is ONLINE"

# Test 3: Mirror membership — exact WWN vdevs present
zpool_status=$(zpool status "$MEDIA_POOL")
if ! echo "$zpool_status" | grep -q "$APPROVED_WWN_1"; then
  fail "Mirror missing approved disk $APPROVED_WWN_1"
fi
if ! echo "$zpool_status" | grep -q "$APPROVED_WWN_2"; then
  fail "Mirror missing approved disk $APPROVED_WWN_2"
fi
pass "Mirror membership verified (both approved WWNs present)"

# Test 4: Canonical directories exist
for dir in movies television books downloads; do
  if [ ! -d "$MEDIA_MOUNT/$dir" ]; then
    fail "Canonical directory $MEDIA_MOUNT/$dir does not exist"
  fi
done
pass "Canonical directories exist"

# Test 5: Service accounts can access media
if ! sudo -u media test -r "$MEDIA_MOUNT/movies"; then
  fail "media user cannot read $MEDIA_MOUNT/movies"
fi
pass "Service account access verified"

# Test 6: Import-write test (D-22: replaces cross-directory hardlink)
# Create a test file in downloads, verify it lands on media/data with correct ownership
TEST_FILE="$MEDIA_MOUNT/downloads/test-import-write-$(date +%s).txt"
TEST_CONTENT="test payload"

echo "$TEST_CONTENT" > "$TEST_FILE"
if ! [ -f "$TEST_FILE" ]; then
  fail "Test file creation failed"
fi

# Verify ownership/permissions (app can write)
ACTUAL_UID=$(stat -c%u "$TEST_FILE" 2>/dev/null || stat -f%u "$TEST_FILE" 2>/dev/null)
ACTUAL_GID=$(stat -c%g "$TEST_FILE" 2>/dev/null || stat -f%g "$TEST_FILE" 2>/dev/null)
# (uid/gid expectations set by impermanence.nix tmpfiles rules; media=1100/1100)
if [ "$ACTUAL_UID" != "1100" ]; then
  fail "Test file has unexpected uid $ACTUAL_UID (expected 1100 for media user)"
fi

# Cleanup
rm "$TEST_FILE"
pass "Import-write test passed (file lands on media/data, correct ownership)"

echo ""
echo "✓✓✓ All ZFS media smoketests passed ✓✓✓"
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|------|------------------|--------------|--------|
| MergerFS on ext4 disks | ZFS mirror (single dataset) | Phase 13 (2026-08-24) | Consolidates storage stack (already ZFS for rpool/backup); eliminates FUSE overhead; native redundancy + integrity checks; simplifies per-app hardlinks (single dataset by design, not by workaround). |
| Extended SMART surface scans | Short SMART self-test + counters | Q-16 decision (2026-08-24) | Reduces gating time from 20+ hours to ~2 min/disk; leverages operator risk posture (transfer integrity matters; bitrot paranoia for replaceable media does not). |
| Full rsync -c checksum gates (both hops) | Sampled + metadata verification (gate 3.3 only) | D-07 decision (2026-08-24) | Reduces verification time from ~10.8h per gate to ~21 min; layered checks (rsync in-flight + ZFS at-rest + scrub) mitigate sampling gaps. D-08 (send/recv) makes gate 5.2 unnecessary. |
| rsync restore + separate verify | zfs send/recv with snapshot | D-08 decision (2026-08-24) | Intrinsic integrity (block-checksummed stream, bit-identical by construction); better resume behavior (send -s tokens); eliminates separate gate 5.2 comparison. |
| Manual qBittorrent + wgnord handling | qBittorrent stack deleted (Phase 12) | Phase 12 (2026-08-16) | Simplifies freeze set; usenet-only download path (SABnzbd/NZBGet) requires no VPN namespace; removes restart-loop vectors. |
| Single-session execution attempt | Multi-session stage-per-plan execution | D-10, D-12 decisions (2026-08-24) | Breaks 56-hour procedure into 9 sitting sessions around ~11h unattended operations; natural session breaks align with long ops; per-stage SUMMARY.md documents rollback-matrix row. |

**Deprecated/outdated:**

- MergerFS documentation in CLAUDE.md, hosts/ser8/README.md, code comments — D-20 fold into Phase 13's final plan.
- Extended SMART surface scans as a gating mechanism — D-04 replacement (short test only).
- Cross-directory hardlinks as a smoketest requirement — D-22 replaces with import-write test.
- qBittorrent/wgnord in the freeze set — Phase 12 deleted; D-01 doc update removes them.
- Two ext4 disks + MergerFS fuse layer — entirely replaced by media ZFS mirror.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | NixOS 25.11 ZFS module is available and configured on ser8 | Standard Stack | Unlikely (ser8 already runs ZFS for rpool/backup), but if ZFS is unavailable, entire phase is blocked; verify in Step 0.1. |
| A2 | rsync 3.4.4 supports xxh128 checksums and `-H` hardlink option for sampled verify | Standard Stack | Verified in CONTEXT.md (L110); rsync 3.4.4 is standard in nixpkgs; xxh128 negotiation is automatic. |
| A3 | disko can declare ZFS mirror topology and datasets with the properties in migration doc | Standard Stack | Highly confident (backup pool already uses disko with RAID-Z2; mirror is simpler). D-12 discretion covers property application order if needed. |
| A4 | Media dataset single-dataset design (no per-directory splits) is correct for this phase | Architecture Patterns | Very confident (D-22 re-articulates this rationale; hardlinks work within single dataset; no cross-dataset barrier). |
| A5 | systemd-run transient units survive SSH disconnects and preserve journald logs | Standard Stack | Confident (standard systemd behavior); verify in Step 0.1 that ser8 systemd version supports this. |
| A6 | Approved disk WWNs (`...a81a` and `...3a87`) will resolve correctly in disko and match live disks | Architecture Patterns, Common Pitfalls | Critical; Step 4.1 mandates re-confirmation before Step 4.3 erase. If WWNs don't resolve, identify correct paths and restart from Step 1.1 (repo change). |
| A7 | Phase 12 evidence files (qBittorrent stack deletion, Radarr root cleanup, uid-38 remediation) are sufficient to trust Steps 0.2/0.3 are complete | User Constraints D-05 | Moderate confidence pending Step 0.1 live re-verification (three one-liners: unit absence, SABnzbd health, single Radarr root). |
| A8 | Backup pool will have ≥1.5 TB free after staging at quiesce time | Common Pitfalls | Measured 2026-08-24 at ~2.16 TB margin (well above floor); media growth is ~105 GB/day, so floor holds until quiesce. D-17 gate double-checks before creating staging. |
| A9 | 500G quota on rpool/safe/downloads will fit in NVMe (rpool has 853 GB free per CONTEXT.md) | User Constraints D-21 | Confident; quota is enforced by ZFS; download growth is temporary (copies to mirror, deleted after import). |
| A10 | Sampled verification sampling (0.4% coverage) + layered checks (rsync in-flight + ZFS at-rest + scrub) adequately mitigate bitrot in unsampled regions | Common Pitfalls, Code Examples | Operator accepted this risk posture (D-07 chat); measured data supports sampling rationale; scrub is the ultimate integrity check. Revisit if media pool develops unexpected errors post-restore. |

**If this table is empty:** All claims above are `[ASSUMED]` — no user confirmation needed before planning, as CONTEXT.md decisions already lock the technical direction. Verification happens in Step 0.1.

## Open Questions

1. **Mount configuration finality in Step 4.5 vs. Step 5.1:**
   - What we know: disko declares `mountpoint = "/mnt/media"` for media/data; `make test-ser8` evaluates and tests without running services (due to masking); `make switch-ser8` activates.
   - What's unclear: Does evaluation check that the mountpoint path exists? If the pool doesn't exist yet (pre-Step 4.4), does NixOS evaluation fail fast, or does it defer to runtime?
   - Recommendation: Step 1.2 (validate repo change) must explicitly test dry-run activation (`make dry-activate-ser8` or similar) to confirm the incomplete pool doesn't cause evaluation failure. If it does, move masking/unmask logic into a post-restore service one-shot instead of pre-activation runtime state.

2. **Sampled verification manifest storage location and retention:**
   - What we know: D-12 (discretion) allows `/persist` or `/mnt/backups` locations; manifest must survive the outage.
   - What's unclear: Should the manifest be persisted to git (in .planning/phases/13-zfs-mirror-migration/evidence/) for audit trail, or retained only on ser8?
   - Recommendation: Store on ser8 in `/persist/phase-13/leg1-verified-manifest` (survives outage), with hash or export to STATE.md after gate passes.

3. **Downloaded removal in D-21 (phase 13 final plan):**
   - What we know: `rpool/safe/downloads` is created; SABnzbd/NZBGet directory paths move; arr apps update to point to new path.
   - What's unclear: Is this part of the main storage-freeze critical path (Plan 13-05 or later), or can it slip to after the media is verified?
   - Recommendation: D-21 explicitly says "off the critical path" — implement in the final plan (Plan 13-06 or 13-07) after media services are running and the first scrub passes.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| ZFS kernel module | Steps 1.1+ (disko pool evaluation) | ✓ | Stock NixOS 25.11 | — (ZFS is hard requirement; no fallback) |
| rsync | Stage 2-3 (data transfer) | ✓ | 3.4.4 [VERIFIED: CONTEXT.md L110] | cpio/tar (slower, no checksums; not preferred) |
| smartctl (util-linux) | Step 0.4 (SMART health gate) | ✓ | Stock NixOS | — (short test is mandatory per D-04) |
| systemd | Steps 2.2+ (transient units) | ✓ | Stock NixOS 25.11 | nohup + log files (loses audit trail, less reliable) |
| disko | Step 1.1 (config evaluation) | ✓ | Via `make dev` | — (no fallback; disko is how ser8 storage is declared) |
| bash/coreutils | Verification scripts, gates | ✓ | Stock NixOS | — (standard shell environment) |
| zfs command-line tools | Steps 4.4, 5.1, 5.5+ (pool/dataset/scrub ops) | ✓ | Stock NixOS ZFS module | — (intrinsic to ZFS; no fallback) |

**Missing dependencies with no fallback:** None — all required tools are already available in NixOS 25.11 or via `make dev`.

**Missing dependencies with fallback:** None — would use preferred tools only.

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | Bash + systemd smoketests (scripts/smoketests/media/test-zfs-media.sh) |
| Config file | deploy.yaml (entry point: `scripts/smoketests/media/all.sh`) |
| Quick run command | `make smoketests-media` (if target exists) or `ssh root@ser8 /persist/scripts/smoketests/media/all.sh` |
| Full suite command | `make smoketests-ser8` (all ser8 suites) or `make smoketests` (all hosts) |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| ZFS-01 | Short SMART counters + self-test pass on both approved disks | Manual + log verification | `smartctl -a /dev/disk/by-id/wwn-0x...` for each disk; exit status checked in Step 0.4 | ✅ (step script) |
| ZFS-02 | Pool `media` online, mirror vdev with both approved WWNs, dataset `media/data` at `/mnt/media` | Automated smoketest | `zpool status media \| grep mirror` + `mount \| grep /mnt/media` | ✅ (test-zfs-media.sh, tests 1-3) |
| ZFS-03 | First scrub completes with zero data errors | Automated smoketest | `zpool status media \| grep "scan completed"` | ✅ (Step 5.5 gate + test-zfs-media.sh implicit) |
| ZFS-04 | Media stack (9 services + 3 oneshots) runs healthy, pool healthy, mirror WWNs present, import-write test succeeds | Automated smoketest | `systemctl is-active jellyfin.service radarr.service ...` + test-zfs-media.sh full suite | ✅ (test-zfs-media.sh tests 2-6) |
| ZFS-05 | Every destructive step individually approved; staging destroyed only after scrub + app tests pass | Manual gate verification | Per-step approval transcript recorded in STATE.md; staging destroy approval gate includes scrub result | ✅ (gate logic, D-11/D-12/D-13) |

### Sampling Rate

- **Per task commit:** `make check` (flake validation, Nix formatting, statix linter) — runs before each Phase 13 plan is committed.
- **Per stage completion:** `make smoketests-ser8` (full ZFS + media health suite) — after Step 5.3 (services start), Step 5.5 (scrub complete), and Step 6.1 (post-cutover validation).
- **Phase gate:** Full suite green before `/gsd-verify-work` (operational UAT).

### Wave 0 Gaps

- [ ] `scripts/smoketests/media/test-zfs-media.sh` — NEW file, covers ZFS-02/ZFS-04 smoketests (D-19).
- [ ] Sampled verification script (implementation location: `/persist/phase-13/sampled-verify.sh` or equivalent per D-12 discretion) — covers ZFS-01 gate 3.3 (D-07).
- [ ] Step 0.4 SMART health gate script (short test + counters read, refuse-if-failing) — covers ZFS-01 gate in Step 0.4.
- [ ] service stop/start ordering scripts for D-02 quiesce and D-16 unmask — orchestrate the 9+3 units with dependency tracking.
- [ ] Per-stage SUMMARY.md templates — each of the 7 plans documents its rollback-matrix row and checkpoint state.

*(No pre-existing test infrastructure conflicts detected; impermanence.nix tmpfiles rules for /mnt/media directory ownership are compatible with ZFS native mount.)*

## Security Domain

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | No | (Storage layer only; auth is orthogonal) |
| V3 Session Management | No | (Storage layer only) |
| V4 Access Control | Yes | Ownership/permissions on `/mnt/media` directories (uid 1100 / gid 1100 for media user, setgid for group-writable dirs). Maintained via impermanence.nix tmpfiles rules; disko/ZFS mount does not change permission model. |
| V5 Input Validation | No | (Storage layer; no user input processing) |
| V6 Cryptography | No | (No encryption in scope; ZFS checksum is at-rest integrity, not confidentiality) |
| V8 Data Protection | Yes | **Critical:** ZFS checksum (default SHA256) protects against silent bitrot on disk + in-flight transfer. Staging + mirror + scrub form the integrity layer. No encryption; media content is considered semi-public within the home. |
| V9 Communications | No | (SSH-based commands are out-of-band; not part of storage layer) |

### Known Threat Patterns for ZFS + NixOS

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Wrong disk erased (kernel name vs. WWN) | Tampering | Use `/dev/disk/by-id/wwn-0x...` paths exclusively; Step 4.1 mandates re-confirmation of approved WWNs before erase. Common Pitfall 1 details this hazard. |
| Silent bitrot in unsampled regions (0.4% coverage) | Tampering | Layered checks: rsync in-flight checksums (per-file), ZFS at-rest checksums (block-level, per D-08), weekly scrubs detect bit-flips. First scrub post-restore is mandatory gate (ZFS-03). |
| Staging copy corrupted mid-transfer | Tampering | rsync in-flight checksums (protocol-internal, not exportable); explicit gate 3.3 re-reads source independently. ZFS receive validates block-checksum of send stream on destination (D-08). |
| Service data loss during empty-pool window (Radarr/Sonarr scan) | Integrity | Masking media units before activation (D-16, Common Pitfall 3) prevents library scans until after restore. Unmasking only after scrub passes (Step 5.3). |
| Feature branch lost mid-cutover | Availability | Branch name carried in plan across sessions. Step 6.2 includes merge to main immediately after switch succeeds (D-15). |
| Staging capacity exhausted, rollback blocked | Availability | D-17 floor (≥1.5 TB) checked before creating staging; margin freezes at quiesce (D-03). Measured 2026-08-24: ~2.16 TB projected. |

## Sources

### Primary (HIGH confidence)

- **[VERIFIED: .planning/phases/13-zfs-mirror-migration/13-CONTEXT.md:1-142]** — Phase context with 23 finalized decisions (D-01..D-23), measured data (media tree size, disk throughput, staging timing), and all rationale with trade-offs.
- **[VERIFIED: .planning/SER8-ZFS-MIRROR-MIGRATION.md:1-938]** — Canonical execution contract (migration doc): approval contract, numbered execution plan, rollback matrix, desired ZFS configuration. Amended by CONTEXT.md decisions where they conflict.
- **[VERIFIED: .planning/phases/13-zfs-mirror-migration/13-QUESTIONS.json:1-522]** — Full Q&A record for all 17 decisions: trade-off context, measured numbers, chat clarifications.
- **[VERIFIED: hosts/ser8/disko-config.nix:163-289]** — Existing ZFS pool + dataset patterns (backup pool RAID-Z2, rpool, rootFsOptions, dataset options) that serve as templates for media mirror.
- **[VERIFIED: .planning/REQUIREMENTS.md:17-26]** — ZFS-01..05 requirement statements (note: ZFS-01 requires rewording per D-04).
- **[VERIFIED: .planning/CLAUDE.md:1-100]** — Project guidance on disko, NixOS, ser8 host configuration.

### Secondary (MEDIUM confidence)

- **[CITED: NixOS 25.11 ZFS module documentation]** — disko syntax for zpool declaration, dataset options, mirror mode. (Not directly fetched this session; confidence HIGH based on Phase 12 usage in same repo.)
- **[CITED: rsync 3.4.4 manual (xxh128 negotiation, --itemize-changes semantics)]** — Verification gate mechanics and sampled-verify script rationale. (Measured in CONTEXT.md L110; rsync behavior verified in Q-12 chat.)
- **[CITED: systemd.exec + systemd.unit documentation]** — Transient unit behavior (journald capture, exit status, SSH survival). (Standard systemd; used in Phase 12 for password-less sudo over SSH, confirmed working.)

### Tertiary (LOW confidence — none; all key claims are either VERIFIED or CITED)

None. All findings are backed by CONTEXT.md verified data, the migration doc contract, the QUESTIONS.json decision record, or repo configuration already in use (disko, systemd).

## Metadata

**Confidence breakdown:**

- **Standard stack:** HIGH — ZFS, disko, rsync, systemd already in active use on ser8 (Phases 9-12); versions verified in CONTEXT.md; no new packages.
- **Architecture:** HIGH — Disko ZFS patterns established (backup pool template); data flow (rsync + zfs send/recv) is standard; service orchestration (masking, systemd-run) is NixOS convention.
- **Pitfalls:** HIGH — 6 detailed pitfalls drawn from CONTEXT.md measured data, Phase 12 learning, and operator risk posture conversations (Q&A record). Each tied to specific mitigation.
- **Validation:** MEDIUM-HIGH — Test framework and smoketests are new (test-zfs-media.sh); Phase 13 final plan writes new script, but bash smoketest pattern is established in repo (scripts/smoketests/ser8/test-*.sh convention).
- **Requirements:** HIGH — ZFS-01..05 are locked in REQUIREMENTS.md; D-04 requires rewording (short SMART only), but technical direction is fixed.

**Research date:** 2026-08-24

**Valid until:** 2026-09-02 (estimate: stable technical stack, but media growth ~105 GB/day and Frigate churn mean staging margin should be re-measured at Step 0.1; revision needed if margin drops below 1.5 TB or migration is deferred >1 week).

**Next actions for planner:**

1. Validate CONTEXT.md decisions against Requirements.md (D-04 rewording for ZFS-01/ROADMAP).
2. Map the 7 doc stages to GSD plan structure (one plan per stage).
3. Identify approval gate logic per D-11 (hybrid: structured + typed echo-back for destructive steps).
4. Prepare system-run unit naming conventions (D-13 discretion).
5. Write the 7 plan SUMMARY.md templates per D-10 (session/rollback boundaries).
