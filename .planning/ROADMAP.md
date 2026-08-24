# Roadmap: NixOS Homelab Infrastructure

## Milestones

- ✅ v1.0 Frigate-Home Assistant Integration - Phases 1-3 (shipped 2026-02-10)
- ✅ v1.1 Monitoring & Alerting - Phases 4-8 (partially shipped; phases 5-7 shelved, see PROJECT.md Deferred)
- ✅ v1.2 Household Stack - Phases 9-11 (shipped 2026-08-23)
- 🚧 v1.3 ZFS Mirror + Nixflix Migration - Phases 12-16 (in progress)

## Phases

**Phase Numbering:**

- Integer phases (12, 13, 14): Planned milestone work
- Decimal phases (12.1, 12.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

<details>
<summary>v1.0 Frigate-Home Assistant Integration (Phases 1-3) - SHIPPED 2026-02-10</summary>

- [x] **Phase 1: Integration Foundation** - Frigate entities auto-discovered in HA via MQTT, surviving reboots
- [x] **Phase 2: Push Notifications** - Snapshot push notifications on person/car/package detection
- [x] **Phase 3: Camera Dashboard** - Live feeds, event history, and per-camera detection controls in HA

Phase artifacts archived under `.planning/milestones/v1.1-phases/`.

</details>

<details>
<summary>v1.1 Monitoring & Alerting (Phases 4-8) - PARTIAL, phases 5-7 shelved</summary>

- [x] **Phase 4: Alert Delivery & Service Probes** - Email notifications for existing alerts, HTTP/ICMP probes for all services
- [ ] **Phase 5: Hardware Alerts & Status Dashboard** - Shelved to Future Requirements (HW-01..05, DASH-01)
- [ ] **Phase 6: Log Aggregation** - Shelved to Future Requirements (LOG-01..05)
- [ ] **Phase 7: HA Monitoring** - Shelved to Future Requirements (HA-01..04, DASH-02, DASH-03)
- [x] **Phase 8: Reorganize ser8 media.nix** - Per-service host modules under `hosts/ser8/media/` (2 verification gaps recorded in archive)

Phase artifacts archived under `.planning/milestones/v1.1-phases/`.

</details>

<details>
<summary>v1.2 Household Stack (Phases 9-11) - SHIPPED 2026-08-23</summary>

- [x] **Phase 9: Channel Bump to NixOS 26.05** - Fleet off the EOL 25.11 channel; Pis re-platformed onto upstream nixpkgs + nixos-hardware (7/9 plans; gap-closure plans 09-08/09-09 deferred) — completed 2026-08-17
- [x] **Phase 10: Household Foundation and Mealie** - Module scaffold, pinned PostgreSQL 17, Mealie in daily household use at `mealie.shad-bangus.ts.net` (5/8 plans; 3 dropped in the 2026-08-20 descope) — completed 2026-08-20
- [x] **Phase 11: Homebox, Actual Budget, and Donetick** - All three remaining apps live on the Phase 10 household pattern, persistence proven by a real ser8 reboot (6/6 plans) — completed 2026-08-22

Backups, `.vofi` TLS, the Google Tasks import, and the access-control acceptance gate were descoped on 2026-08-20 (operator decision: apps first, ceremony later).
Closed 2026-08-23 as an override closeout with 17 acknowledged deferred items (see STATE.md Deferred Items).
Phase details archived in `.planning/milestones/v1.2-ROADMAP.md`; phase artifacts under `.planning/milestones/v1.2-phases/`.

</details>

### 🚧 v1.3 ZFS Mirror + Nixflix Migration (Phases 12-16, in progress)

**Milestone Goal:** Rebuild ser8's media foundation in one milestone — storage first (MergerFS → two-disk ZFS mirror, paranoid and human-gated), then the full Nixflix migration through Recyclarr, Seerr, and Maintainerr, plus a nightly backup engine.

- [x] **Phase 12: Fleet Repair** - Durably fix the wgnord/qBittorrent loop, sabnzbd uid drift, media UID/GID drift, and Radarr root-folder drift before the storage freeze (completed 2026-08-23)
- [ ] **Phase 13: ZFS Mirror Migration** - Migrate ser8 media storage from MergerFS to a two-disk ZFS mirror, human-gated per the migration doc's approval contract
- [ ] **Phase 14: Backup Engine** - Nightly application-aware backups to the ZFS backup pool for household and media app state, with demonstrated restores
- [ ] **Phase 15: Nixflix Migration** - Adopt Nixflix as the declarative orchestration layer for Sonarr, Radarr, Prowlarr, and Jellyfin with full data retention
- [ ] **Phase 16: New Services** - Stand up Recyclarr, Seerr, and Maintainerr (observation mode) on the migrated stack

## Phase Details

### Phase 12: Fleet Repair

**Goal**: The pre-existing fleet issues sitting on the storage and cutover critical paths are diagnosed and durably fixed in Nix, not just manually cleared.
**Depends on**: Nothing (first phase of v1.3; builds on the v1.2-shipped fleet)
**Requirements**: FLEET-01, FLEET-02, FLEET-03, FLEET-04
**Success Criteria** (what must be TRUE):

  1. The NordVPN + qBittorrent stack is removed from code and state; the download path is usenet-only (SABnzbd/NZBGet) with no drift or restart-loop recurrence
  2. `sabnzbd.service` is active and the firebat gateway's `https_sabnzbd` route is healthy again
  3. Live ser8 media user/group identities match the repo's declarations with no blind recursive re-chown, and the reconciliation approach is recorded in PROJECT.md Key Decisions
  4. Radarr reports `/mnt/media/movies` as its only root folder, with every previously registered movie file still present

**Plans**: 5/5 plans executed
**Wave 1**

- [x] 12-01-PLAN.md — Reconcile media user/group identity to live ser8 values (uid 1002 / gid 992) and audit for drift elsewhere
- [x] 12-02-PLAN.md — Diagnose and repair sabnzbd's uid-drifted state with a static identity pin
- [x] 12-03-PLAN.md — Delete the NordVPN + qBittorrent stack from code, wiring, monitoring, and docs

**Wave 2** *(blocked on Wave 1 completion)*

- [x] 12-04-PLAN.md — Deploy the removal to ser8, archive-then-delete live state, remove secrets

**Wave 3** *(blocked on Wave 2 completion)*

- [x] 12-05-PLAN.md — Clean Radarr root folders and de-register dead qBittorrent download clients

### Phase 13: ZFS Mirror Migration

**Goal**: ser8 media storage runs on a two-disk ZFS mirror with zero data loss, and MergerFS is fully retired, executed per the human-gated procedure in `.planning/SER8-ZFS-MIRROR-MIGRATION.md`.
**Depends on**: Phase 12 (fleet must be stable and API-clean before the storage freeze)
**Requirements**: ZFS-01, ZFS-02, ZFS-03, ZFS-04, ZFS-05
**Success Criteria** (what must be TRUE):

  1. Both approved 12 TB disks pass a short SMART health test gate (self-test plus zero pending/reallocated/offline-uncorrectable sectors), and the full media tree is staged to `backup/media-staging` with a frozen, checksum-verified final sync reporting zero unexplained differences
  2. `zpool status media` shows one online `mirror-0` vdev with exactly the two approved WWNs, and `media/data` is mounted at `/mnt/media` with the documented pool and dataset properties
  3. The restore from staging into the new mirror verifies checksum-identical against the frozen source, and the first scrub completes with zero data errors
  4. MergerFS is gone from the active configuration, disko declares the mirror, and the full media stack (Jellyfin, Sonarr, Radarr, Bazarr, SABnzbd, NZBGet, Samba) runs healthy on ZFS with smoketests asserting pool health, mirror membership, and a working cross-directory hardlink
  5. Every destructive step was individually approved per the migration doc's per-step approval contract, and `backup/media-staging` is destroyed only after post-cutover observation and a separate approval

**Plans**: 1/7 plans executed (one per migration-doc stage, per D-10 — session boundaries align with the multi-hour unattended operations)
**Wave 1** *(sequential — each plan gates the next; this is a strictly sequential live storage migration, not a parallelizable phase)*

- [x] 13-01-PLAN.md — Preflight & doc reconciliation: amend the migration doc first (D-01), short SMART gate, source inventory manifest
- [ ] 13-02-PLAN.md — Repository storage declaration: disko/configuration/impermanence changes on a feature branch, new pool-health smoketest
- [ ] 13-03-PLAN.md — Freeze the app stack and run the single frozen staging copy (D-03 quiesce timing)
- [ ] 13-04-PLAN.md — Gate 3.3: sampled + metadata verification of staging vs the frozen source (D-07)
- [ ] 13-05-PLAN.md — Destructive cutover: disk erase, mirror creation, masked activation, branch merge
- [ ] 13-06-PLAN.md — zfs send/recv restore, ordered service startup, application/storage tests (D-08)
- [ ] 13-07-PLAN.md — First scrub, staging destroy, MergerFS doc sweep, downloads relocation to NVMe (D-19/D-20/D-21)

**Human gate**: yes — every destructive step in this phase requires individual, separately-scoped approval per `.planning/SER8-ZFS-MIRROR-MIGRATION.md`'s Approval Contract; no step may be batch-approved.

### Phase 14: Backup Engine

**Goal**: Every stateful service on ser8 — household apps and media apps alike — is protected by a nightly, application-aware backup with a demonstrated, working restore path.
**Depends on**: Phase 13 (backup dataset properties and media-state coverage target the final ZFS topology)
**Requirements**: BKP-01, BKP-02, BKP-03, BKP-04, BKP-05, BKP-06, BKP-07
**Success Criteria** (what must be TRUE):

  1. A nightly backup job runs on ser8 against a dedicated dedup-off dataset on the backup pool, covering Mealie (pg_dump plus the recipe image/upload directory), every SQLite-backed service (via `sqlite3 .backup`/`VACUUM INTO` with `PRAGMA integrity_check`, never a raw copy), and Actual Budget (`account.sqlite` plus the entire `user-files/` tree)
  2. Media application state (Sonarr, Radarr, Prowlarr, Jellyfin, Bazarr, SABnzbd, NZBGet) is covered by the same nightly engine using the correct backup method per state store
  3. A Mealie restore into a scratch instance has been performed and documented
  4. A restore of one SQLite-backed service and of Actual Budget has been demonstrated

**Plans**: TBD

### Phase 15: Nixflix Migration

**Goal**: Nixflix is the declarative orchestration layer for Sonarr, Radarr, Prowlarr, and Jellyfin on ser8, with full data retention and no removed configuration, executed per the staged plan in `.planning/SER8-NIXFLIX-MIGRATION.md`.
**Depends on**: Phase 14 (the pre-cutover snapshot and tested rollback ride on the backup engine; declarations target the final ZFS topology)
**Requirements**: NIX-01, NIX-02, NIX-03, NIX-04, NIX-05, NIX-06
**Success Criteria** (what must be TRUE):

  1. Nixflix is pinned as a flake input to a reviewed commit with a ser8 adapter forcing live identities and existing state paths; PostgreSQL, local proxy, VPN, and qBittorrent service management stay disabled, and ser8 builds without activation
  2. A full pre-cutover API inventory (root folders, download clients, Prowlarr apps/indexers/proxies, Jellyfin) is exported, a state snapshot exists, and a tested state-aware rollback has been proven before reconciliation is enabled
  3. All retained root folders, download clients (NZBGet, SABnzbd), and Prowlarr objects are declared, reconciliation is enabled for Sonarr/Radarr/Prowlarr with no retained object removed, and the overlapping local orchestration units (`media-config`, `servarrs-setup`, `download-clients-setup`) are gone
  4. Post-cutover, existing databases, history, and monitored items are intact; imports succeed from both download clients with group/setgid permissions preserved; Bazarr reads imported files; a representative usenet import creates a verified hardlink on `media/data`
  5. Jellyfin runs under Nixflix with a dedicated SOPS API key, preserved database/users/libraries, firebat known-proxy handling, and a healthy exporter

**Plans**: TBD
**Human gate**: yes — the cutover (criteria 2-4) requires a full inventory export, a state snapshot, and a tested rollback proven before reconciliation is enabled; treat enabling reconciliation as its own approved step, not implied by earlier declaration work.

### Phase 16: New Services

**Goal**: Recyclarr, Seerr, and Maintainerr are live on the migrated Nixflix stack, each conservatively scoped per its low-ceremony standup.
**Depends on**: Phase 15 (all three attach to the Nixflix-managed Sonarr/Radarr/Jellyfin stack)
**Requirements**: SVC-01, SVC-02, SVC-03
**Success Criteria** (what must be TRUE):

  1. Recyclarr applies TRaSH-aligned quality profiles and custom formats to Sonarr and Radarr, with unmanaged-profile cleanup disabled, and scoring has been reviewed against representative media
  2. Seerr is live with Jellyfin authentication and connected to Sonarr/Radarr; household members can request content, with firebat Caddy/Tailscale routing, monitoring, and smoketest coverage in place
  3. Maintainerr runs in observation mode with all rules in preview/no-action, zero deletions, and visibility into what each rule would do

**Plans**: TBD

## Progress

| Milestone | Phases | Plans | Status | Shipped |
|-----------|--------|-------|--------|---------|
| v1.0 Frigate-HA Integration | 1-3 | 6/6 | Complete | 2026-02-10 |
| v1.1 Monitoring & Alerting | 4-8 | 9/9 executed (phases 5-7 shelved) | Partial | 2026-02-12 |
| v1.2 Household Stack | 9-11 | 18/23 (3 dropped, 2 deferred) | Complete | 2026-08-23 |
| v1.3 ZFS Mirror + Nixflix Migration | 12-16 | 0/TBD | Not started | - |

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 12. Fleet Repair | 0/TBD | Not started | - |
| 13. ZFS Mirror Migration | 0/7 | Not started | - |
| 14. Backup Engine | 0/TBD | Not started | - |
| 15. Nixflix Migration | 0/TBD | Not started | - |
| 16. New Services | 0/TBD | Not started | - |

Milestone in progress: v1.3 ZFS Mirror + Nixflix Migration (Phases 12-16). Next: `/gsd-plan-phase 12`.
