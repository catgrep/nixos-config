# Requirements: NixOS Homelab Infrastructure — v1.3 ZFS Mirror + Nixflix Migration

**Defined:** 2026-08-23
**Core Value:** The homelab runs reliably without manual intervention — when something needs attention, I know about it before it becomes a problem.

## v1.3 Requirements

### Fleet Repair

Prerequisites sitting on the storage and cutover critical paths.

- [x] **FLEET-01**: Torrents are retired; the download path is usenet-only (SABnzbd/NZBGet). The NordVPN + qBittorrent stack is removed entirely from code and state with no restart loop recurrence
- [x] **FLEET-02**: sabnzbd's uid-drifted state is repaired; `sabnzbd.service` is active and the gateway `https_sabnzbd` route is healthy again
- [x] **FLEET-03**: Repo `media` user/group declarations are reconciled to live ser8 identities with no blind recursive re-chown; the drift resolution is recorded in Key Decisions
- [x] **FLEET-04**: Radarr root folders are cleaned via API to the single canonical `/mnt/media/movies` with no media files deleted

### Storage

MergerFS → two-disk ZFS mirror, per `.planning/SER8-ZFS-MIRROR-MIGRATION.md`.

- [x] **ZFS-01**: Short SMART health test (self-test + zero pending/reallocated/offline-uncorrectable sector counters) passes on both approved 12 TB disks, and the full media tree is staged to `backup/media-staging` with a frozen, checksum-verified final sync reporting zero unexplained differences
- [x] **ZFS-02**: The two approved WWNs are reformatted into ZFS pool `media` with one mirror vdev and a single dataset `media/data` mounted at `/mnt/media` with the documented properties
- [x] **ZFS-03**: The restore from staging via `zfs send/recv` verifies intrinsically checksum-clean and the first scrub completes with zero data errors
- [x] **ZFS-04**: MergerFS is removed from the active configuration, disko defines the mirror, and the full media stack runs healthy on ZFS with smoketests asserting pool health, mirror membership, and a working import-write ownership check
- [x] **ZFS-05**: Every destructive step follows the migration doc's per-step human approval contract, and `backup/media-staging` is destroyed only after post-cutover observation and separate approval

### Backups

BKP-01..06 unparked from the v1.2 descope, extended to the media stack.

**Amended 2026-08-26** after the Phase 14 architecture pivot from a per-service dump engine to atomic ZFS snapshots plus replication.
The original wording encoded the dump-engine mechanism into the requirement text; the amended wording states the outcome and names the mechanism the pivot actually adopts.
The substantive change is in BKP-03: the failure mode the original wording targeted is a **non-atomic** live file copy (`cp`/`rsync` walking `db`, `-wal`, and `-shm` at different instants), which corrupts.
An atomic ZFS snapshot is a single-transaction-group image — precisely the crash image SQLite and PostgreSQL are designed to recover from — and is therefore the sanctioned mechanism, not the forbidden one.
BKP-07 is broadened from a named application list to whole-of-persist coverage so that adding a service can never silently leave it unprotected.

- [x] **BKP-01**: A nightly atomic ZFS snapshot of ser8's persisted service state is replicated to a dedup-off dataset on the backup pool, with source retention pruned to a 30-night sliding window by an established snapshot policy tool rather than hand-rolled units
- [x] **BKP-02**: Mealie is covered by the nightly snapshot, including its recipe image and upload tree, and its PostgreSQL database is additionally captured as a portable `pg_dump -Fc` archive written inside the snapshotted tree by a generic catalog-driven job that requires no per-application registration
- [x] **BKP-03**: Service state is never captured by a non-atomic live file copy; the mechanism is an atomic ZFS snapshot, verified nightly by `PRAGMA integrity_check`/`quick_check` run against a copy taken out of the snapshot, never against the live file
- [x] **BKP-04**: Actual's state is captured whole by the snapshot of its persisted state directory, covering `server-files/account.sqlite` and the entire `user-files/` blob tree
- [x] **BKP-05**: A Mealie restore into a scratch VM is demonstrated and documented using the parameterized restore tool
- [ ] **BKP-06**: A restore of one SQLite-backed service (Donetick) and of Actual is demonstrated with that same tool, and a VM test suite exercises the restore path across every covered service
- [x] **BKP-07**: Backup coverage is everything persisted on ser8 rather than a named application list — household apps, media apps (Sonarr, Radarr, Prowlarr, Jellyfin, Bazarr, SABnzbd, NZBGet), Home Assistant, Frigate, Mosquitto, Samba, and any unregistered persisted state — so that adding a service never requires remembering to register it for backup

### Nixflix

Foundation and cutover, per `.planning/SER8-NIXFLIX-MIGRATION.md`.

- [ ] **NIX-01**: Nixflix is pinned as a flake input to a reviewed commit with a ser8 adapter forcing live identities and existing state paths; PostgreSQL, local proxy, VPN, and qBittorrent service management stay disabled; ser8 builds without activation
- [ ] **NIX-02**: The full API inventory (root folders, download clients, Prowlarr apps/indexers/proxies, Jellyfin) is exported, and a pre-cutover state snapshot with a tested state-aware rollback exists before reconciliation is enabled
- [ ] **NIX-03**: All retained root folders, download clients (NZBGet, SABnzbd), and Prowlarr objects are declared, and reconciliation is enabled for Sonarr, Radarr, and Prowlarr without removing any retained object
- [ ] **NIX-04**: The overlapping local orchestration units (`media-config`, `servarrs-setup`, `download-clients-setup`) are removed, with Nixflix owning that glue
- [ ] **NIX-05**: Post-cutover, existing databases, history, and monitored items are intact; imports succeed from both download clients with group/setgid permissions preserved; Bazarr reads imported files; a representative usenet import lands a verified copy on `media/data` (downloads stage on the NVMe pool, so imports copy — hardlinks cannot cross pools)
- [ ] **NIX-06**: Jellyfin runs under Nixflix with a dedicated SOPS API key, preserved database/users/libraries, firebat known-proxy handling, and a healthy exporter

### New Services

Simple standups on the migrated stack, separate paths.

- [ ] **SVC-01**: Recyclarr applies TRaSH-aligned quality profiles and custom formats to Sonarr and Radarr with unmanaged-profile cleanup disabled and scoring reviewed against representative media
- [ ] **SVC-02**: Seerr is live with Jellyfin authentication and connected to Sonarr/Radarr; household members can request content; firebat Caddy/Tailscale, monitoring, and smoketest coverage are in place
- [ ] **SVC-03**: Maintainerr runs in observation mode with all rules in preview/no-action, zero deletions, and visibility into what each rule would do

## Future Requirements

Deferred to later milestones. Tracked but not in the current roadmap.

### TLS & Domain

- **TLS-01**: TLS trust approach decided (Caddy root CA distribution vs public certs) and recorded in Key Decisions
- **TLS-02**: Household devices reach services over TLS with no browser warnings (`.vofi` → `vofi.dev` migration, pending todo)

### Google Tasks Import

- **IMP-01**: Google Takeout export requested early (async, hours-to-days) and the real archive inspected before any import code is written
- **IMP-02**: One-off todos imported into Donetick via the internal API with a dry-run mode and idempotency guard
- **IMP-03**: Recurring chores hand-authored in Donetick from a reviewed recurrence map

### Access Control & Verification

- **SEC-01**: No household service is reachable from outside Tailscale/LAN, verified by a negative access smoketest
- **SEC-02**: No secret for any household service appears in the Nix store
- **OBS-01**: All four household services have blackbox probes and smoketests wired into deploy.yaml
- **OBS-02**: All four household services retain their data across two consecutive ser8 reboots

### Media Expansion

- **MED-01**: Separate Sonarr anime instance with specialized naming, profiles, and release-group scoring
- **MED-02**: Lidarr automates the `/mnt/media/music` library
- **MED-03**: PostgreSQL backend for the arr suite, evaluated on operational merit

### Monitoring & Alerting (v1.1 remainder, shelved)

- Hardware alert rules (ZFS degraded, disk space, CPU/memory/temp), Loki + Promtail log aggregation, uptime dashboard, HA infrastructure-alert automations

## Out of Scope

Explicitly excluded. Documented to prevent scope creep.

| Feature | Reason |
|---------|--------|
| ZFS child datasets for movies/tv/downloads | Single `media/data` dataset kept for simplicity (per-dataset split buys nothing here); the original hardlink-crossing rationale is obsolete since torrent retirement — imports copy in from NVMe download staging (D-21/D-22) |
| ZFS deduplication | DDT costs ~GBs of RAM per TB and taxes every write/free; media blocks are unique and nightly DB dumps aren't block-stable, so realized ratio is ~1.0x — compression covers the real redundancy |
| RAID-Z2 media pool / adding the 6 TB disks | Final topology is the two-disk mirror only; backup pool stays as-is |
| Off-host backup | Same-host staging and backup pool only this milestone |
| Nixflix-managed VPN or qBittorrent service | Working NordVPN namespace topology preserved; repaired, not replaced |
| Bazarr replacement | Stays a local module until subtitle behavior is compared and verified |
| Maintainerr deletion rules | Observation mode only this milestone; deletions need reviewed evaluation cycles first |
| Mass SOPS secret rename | Deployment risk without improving the application contract; new secrets use the media namespace |
| PostgreSQL migration for arr/Jellyfin | Separate proposal after Nixflix is stable in production |
| Moving/renaming the media library | Layout already matches the TRaSH shared-namespace design |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| FLEET-01 | Phase 12 | Complete |
| FLEET-02 | Phase 12 | Complete |
| FLEET-03 | Phase 12 | Complete |
| FLEET-04 | Phase 12 | Complete |
| ZFS-01 | Phase 13 | Complete |
| ZFS-02 | Phase 13 | Complete |
| ZFS-03 | Phase 13 | Complete |
| ZFS-04 | Phase 13 | Complete |
| ZFS-05 | Phase 13 | Complete |
| BKP-01 | Phase 14 | Complete |
| BKP-02 | Phase 14 | Complete |
| BKP-03 | Phase 14 | Complete |
| BKP-04 | Phase 14 | Complete |
| BKP-05 | Phase 14 | Complete |
| BKP-06 | Phase 14 | Pending |
| BKP-07 | Phase 14 | Complete |
| NIX-01 | Phase 15 | Pending |
| NIX-02 | Phase 15 | Pending |
| NIX-03 | Phase 15 | Pending |
| NIX-04 | Phase 15 | Pending |
| NIX-05 | Phase 15 | Pending |
| NIX-06 | Phase 15 | Pending |
| SVC-01 | Phase 16 | Pending |
| SVC-02 | Phase 16 | Pending |
| SVC-03 | Phase 16 | Pending |

**Coverage:**

- v1.3 requirements: 25 total
- Mapped to phases: 25
- Unmapped: 0 ✓

---
*Requirements defined: 2026-08-23*
*Last updated: 2026-08-26 — BKP-01..07 reworded for the Phase 14 snapshot-model pivot (see the note under Backups)*
