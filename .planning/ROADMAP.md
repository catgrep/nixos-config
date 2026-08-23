# Roadmap: NixOS Homelab Household Stack

## Milestones

- ✅ v1.0 Frigate-Home Assistant Integration - Phases 1-3 (shipped 2026-02-10)
- ✅ v1.1 Monitoring & Alerting - Phases 4-8 (partially shipped; phases 5-7 shelved, see PROJECT.md Deferred)
- ✅ v1.2 Household Stack - Phases 9-11 (shipped 2026-08-23)

## Phases

**Phase Numbering:**

- Integer phases (9, 10, 11): Planned milestone work
- Decimal phases (10.1, 10.2): Urgent insertions (marked with INSERTED)

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

## Progress

| Milestone | Phases | Plans | Status | Shipped |
|-----------|--------|-------|--------|---------|
| v1.0 Frigate-HA Integration | 1-3 | 6/6 | Complete | 2026-02-10 |
| v1.1 Monitoring & Alerting | 4-8 | 9/9 executed (phases 5-7 shelved) | Partial | 2026-02-12 |
| v1.2 Household Stack | 9-11 | 18/23 (3 dropped, 2 deferred) | Complete | 2026-08-23 |

Next milestone: not yet defined — run `/gsd-new-milestone`.
