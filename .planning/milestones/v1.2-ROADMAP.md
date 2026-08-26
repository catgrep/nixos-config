# Roadmap: NixOS Homelab Household Stack

## Milestones

- v1.0 Frigate-Home Assistant Integration - Phases 1-3 (shipped 2026-02-10)
- v1.1 Monitoring & Alerting - Phases 4-8 (partially shipped; phases 5-7 shelved, see PROJECT.md Deferred)
- **v1.2 Household Stack** - Phases 9-14 (in progress)

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

### v1.2 Household Stack (In Progress)

**Milestone Goal:** Four standalone self-hosted household services (Mealie, Donetick, Homebox, Actual Budget) on ser8, reachable through the firebat Caddy gateway on the tsnet pattern proven in Phase 10, with impermanence-safe persistence.

Backups, `.vofi` TLS, the Google Tasks import, and the access-control acceptance gate were descoped on 2026-08-20 (operator decision: apps first, ceremony later). Their requirements are parked as Deferred in REQUIREMENTS.md.

- [x] **Phase 9: Channel Bump to NixOS 26.05** - Move the flake off the EOL 25.11 channel and settle the Raspberry Pi input strategy
- [x] **Phase 10: Household Foundation and Mealie** - Module scaffold, pinned PostgreSQL, and Mealie in daily household use at `mealie.shad-bangus.ts.net`
- [x] **Phase 11: Homebox, Actual Budget, and Donetick** - All three remaining apps spun up on the Phase 10 household pattern (completed 2026-08-22)

## Phase Details

### Phase 9: Channel Bump to NixOS 26.05

**Goal**: The flake runs on a supported nixpkgs channel with all four hosts building cleanly, so the milestone can use the native 26.05 Mealie and Actual modules instead of overlay workarounds
**Depends on**: Nothing (first phase of v1.2)
**Requirements**: FOUND-01, FOUND-02
**Success Criteria** (what must be TRUE):

  1. `make check` passes on `nixos-26.05` and every host (ser8, firebat, pi4, pi5) dry-activates without evaluation errors
  2. Both Raspberry Pi hosts build under a recorded input strategy — either the retained `nixos-raspberrypi` pin or upstream support (nixos-hardware for pi4, upstream nixpkgs for pi5) — with the decision and its test evidence in PROJECT.md Key Decisions
  3. `services.actual` on ser8 evaluates with real `user`/`group`/`dataDir` options (the 26.05 module, not the 25.11 hard-coded `DynamicUser` one), confirming no unstable overlay is needed later in the milestone
  4. ser8 activates the bumped configuration and the existing media, Frigate, and Home Assistant smoketests still pass

**Plans**: 7/9 plans executed (2 gap-closure plans added after verification)

Plans:
**Wave 1**

- [x] 09-01-PLAN.md — Bump nixpkgs to nixos-26.05; both x86 hosts evaluate and complete a remote activation preview

**Wave 2** *(blocked on Wave 1 completion)*

- [x] 09-02-PLAN.md — Re-platform both Pi hosts from the third-party fork onto upstream nixpkgs plus nixos-hardware
- [x] 09-06-PLAN.md — Smoketest infrastructure: suite exit status, routine/disruptive VPN split, pi4 retirement from test and proxy paths

**Wave 3** *(blocked on Wave 2 completion)*

- [x] 09-03-PLAN.md — ser8 regression checks: ZFS health, real VAAPI transcode, Frigate MQTT freshness, Home Assistant
- [x] 09-04-PLAN.md — Align Home Manager with the channel, re-lock remaining inputs, and remove obsolete package-source workarounds

**Wave 4** *(blocked on Wave 3 completion)*

- [x] 09-05-PLAN.md — Activate ser8, with the camera-dashboard check gating the permanent switch

**Wave 5** *(blocked on Wave 4 completion)*

- [x] 09-07-PLAN.md — Activate firebat, confirm Grafana alert delivery before switching, record the FOUND-02 decision

**Gap closure** *(from 09-VERIFICATION.md, status gaps_found)*

- [ ] 09-08-PLAN.md — Remove the three always-passing checks from the regression gate: pi4/pi5 fake smoketest entries, the zero-route Caddy pass, the unreadable-journal pass
- [ ] 09-09-PLAN.md — Human gates: revoke the installed third-party cache trust, decide the SC1 pi4/pi5 evidence bar, settle the ser8 reboot proofs

### Phase 10: Household Foundation and Mealie

**Goal**: Both household members plan recipes and share one shopping list at `mealie.shad-bangus.ts.net`, on a module, persistence, and gateway pattern the remaining three services reuse
**Depends on**: Phase 9
**Requirements**: FOUND-03, FOUND-04, MEAL-01, MEAL-02, MEAL-03, MEAL-04, MEAL-05, IMP-01
**Success Criteria** (what must be TRUE):

  1. Both household members log in to `https://mealie.shad-bangus.ts.net` through the firebat Caddy Tailscale (tsnet) vhost, with default admin credentials changed and registration closed
  2. Both users see and edit the same single shared shopping list, and Foods and Units are seeded
  3. Recipes, images, and uploads created before two consecutive ser8 reboots are all still present afterward
  4. `modules/household/` plus `hosts/ser8/household/` exist following the reusable-module / host-policy split used by `modules/media/`, and PostgreSQL runs on ser8 on an explicitly pinned package version rather than one derived from `system.stateVersion`
  5. The Google Takeout Tasks export has been requested and the delivered archive's real JSON structure is recorded for the later import, with no import code written yet

**Plans**: 5/8 executed; 10-02, 10-07, 10-08 dropped at phase close (operator decision 2026-08-20)

**Closed as-is on 2026-08-20.** Mealie is live and in household use.
Dropped with the descope: the Google Takeout request/inspection (10-02, 10-08 — parked with IMP-01) and the formal two-reboot drill (10-07 — persistence is configured identically to the proven media services; MEAL-05's formal proof was waived).
Success criterion 5 (Takeout) was waived; criterion 3 (reboot proof) accepted on configuration evidence.
MEAL-04's shared list is proven server-side bidirectionally; the two-profile UI observation was accepted without formal re-verification.

Plans:

- [x] 10-01-PLAN.md — Tracer: household module scaffold, pinned PostgreSQL 17, Mealie 3.22.0, and the firebat tsnet vhost, locked behind an offline eval gate
- [ ] 10-02-PLAN.md — DROPPED: Google Takeout export request (parked with IMP-01)
- [x] 10-03-PLAN.md — Household smoketest area: service, endpoint, and both state stores, joined to the ser8 and gateway suites
- [x] 10-04-PLAN.md — Activate ser8: pre-flight the empty-PostgreSQL premise, cross the one-way version thresholds, confirm the live schema
- [x] 10-05-PLAN.md — Activate firebat, prove the mealie tsnet node registers, and confirm the endpoint end to end in a browser
- [x] 10-06-PLAN.md — Mealie bootstrap: two accounts in one household, dead default credentials, seeded Foods and Units, shared shopping lists
- [ ] 10-07-PLAN.md — DROPPED: formal two-reboot persistence drill (waived)
- [ ] 10-08-PLAN.md — DROPPED: Takeout archive inspection (parked with IMP-01)

### Phase 11: Homebox, Actual Budget, and Donetick

**Goal**: Homebox, Actual Budget, and Donetick run on ser8 and are reachable through the firebat gateway, each usable by both household members — the same shape as Mealie, three more times
**Depends on**: Phase 10
**Requirements**: HBX-01, HBX-02, HBX-03, ACT-01, ACT-02, ACT-03, DTK-01, DTK-02, DTK-03, DTK-04
**Success Criteria** (what must be TRUE):

  1. Homebox, Actual Budget, and Donetick each load at `<name>.shad-bangus.ts.net` through the firebat Caddy tsnet pattern proven in Phase 10 (supersedes the `.vofi`/AdGuard wording in the requirement text)
  2. Each service has both household members set up (one shared group/circle where the app has one) and self-signup closed
  3. Each service's state lives under the household persistence pattern (`modules/household/` + `hosts/ser8/household/`) and survives a ser8 reboot

**Plans**: 6/6 plans executed

Plans:
**Wave 1**

- [x] 11-01-PLAN.md — Homebox: module, secret, persistence, gateway, both members bootstrapped, registration closed

**Wave 2** *(blocked on Wave 1 completion)*

- [x] 11-02-PLAN.md — Actual: static user, persistence, gateway, server password set

**Wave 3** *(blocked on Wave 2 completion)*

- [x] 11-03-PLAN.md — Actual: create the one budget file (human-action), decline encryption, verify by SQL

**Wave 4** *(blocked on Wave 3 completion)*

- [x] 11-04-PLAN.md — Donetick: local package (`nix build .#donetick`), NixOS module, sops JWT secret, ser8 activation

**Wave 5** *(blocked on Wave 4 completion)*

- [x] 11-05-PLAN.md — Donetick: gateway vhost, both members bootstrapped into one circle, signup closed

**Wave 6** *(blocked on Wave 5 completion)*

- [x] 11-06-PLAN.md — Cross-app: reboot ser8 once, prove all three services' state survives

## Progress

**Execution Order:**
Phases execute in numeric order: 9 -> 10 -> 11.
Phases 11-14 of the original plan (backups, `.vofi` TLS, Tasks import, access-control gate) were descoped on 2026-08-20; their requirements are Deferred in REQUIREMENTS.md.

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 1. Integration Foundation | v1.0 | 2/2 | Complete | 2026-02-10 |
| 2. Push Notifications | v1.0 | 2/2 | Complete | 2026-02-10 |
| 3. Camera Dashboard | v1.0 | 2/2 | Complete | 2026-02-10 |
| 4. Alert Delivery & Service Probes | v1.1 | 2/2 | Complete | 2026-02-12 |
| 5. Hardware Alerts & Status Dashboard | v1.1 | 2/2 | Deferred (shelved to Future Requirements) | - |
| 6. Log Aggregation | v1.1 | 0/TBD | Deferred (shelved to Future Requirements) | - |
| 7. HA Monitoring | v1.1 | 0/TBD | Deferred (shelved to Future Requirements) | - |
| 8. Reorganize ser8 media.nix | v1.1 | 7/7 | Complete (2 verification gaps recorded) | - |
| 9. Channel Bump to NixOS 26.05 | v1.2 | 7/7 | Complete | 2026-08-17 |
| 10. Household Foundation and Mealie | v1.2 | 5/8 | Complete (3 plans dropped at close) | 2026-08-20 |
| 11. Homebox, Actual Budget, and Donetick | v1.2 | 6/6 | Complete    | 2026-08-22 |
