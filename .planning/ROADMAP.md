# Roadmap: Frigate-Home Assistant Integration

## Overview

This milestone connects the existing Frigate NVR (3 cameras: driveway, front_door, garage) to Home Assistant on ser8, delivering push notifications with snapshots on person/car/package detection and a dashboard for live monitoring and event review. The work progresses through three phases: establishing the integration foundation (entities + persistence), building notification automations (core value), and creating the monitoring dashboard (polish). Each phase is independently deployable and testable.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [x] **Phase 1: Integration Foundation** - Wire Frigate to HA so entities exist, persist, and update in real-time
- [ ] **Phase 2: Push Notifications** - Deliver snapshot notifications on person/car/package detection
- [ ] **Phase 3: Camera Dashboard** - Live camera feeds and detection event browsing in HA

## Phase Details

### Phase 1: Integration Foundation
**Goal**: Frigate entities are auto-discovered in HA, update in real-time, and survive ser8 reboots
**Depends on**: Nothing (first phase)
**Requirements**: INTG-01, INTG-02, INTG-03, INTG-04, INTG-05, INTG-06, INTG-07
**Success Criteria** (what must be TRUE):
  1. Frigate camera entities, binary sensors (motion/occupancy), and detection switches appear in HA entity list after deployment
  2. Entity states update in real-time when Frigate detects motion or objects (observable in HA developer tools)
  3. All Frigate entities and integration config entries persist after ser8 reboot (impermanence validated)
  4. Services start in correct order after reboot without manual intervention (Mosquitto before Frigate before HA)
  5. Detection zones are configured per camera so that irrelevant areas do not generate false positive events
**Plans:** 2 plans

Plans:
- [x] 01-01-PLAN.md -- NixOS module changes: Frigate custom component, systemd ordering, automation split, detection zones
- [x] 01-02-PLAN.md -- Deploy to ser8, complete UI config flows, verify entity discovery and reboot persistence

### Phase 2: Push Notifications
**Goal**: A push notification with a snapshot image arrives on my phone within seconds of Frigate detecting a person, car, or package
**Depends on**: Phase 1
**Requirements**: NOTF-01, NOTF-02, NOTF-03, NOTF-04, NOTF-05, NOTF-06
**Success Criteria** (what must be TRUE):
  1. Phone receives a push notification with camera name and snapshot image when a person is detected on any of the 3 cameras
  2. Phone receives a push notification with camera name and snapshot image when a car or package is detected on any of the 3 cameras
  3. Repeated detections from the same Frigate review event update the existing notification in-place rather than creating duplicates
  4. Tapping a notification opens the relevant clip or event detail in HA (actionable notification)
  5. All notification automations are declared in Nix configuration (not HA UI-only)
**Plans:** 2 plans

Plans:
- [ ] 02-01-PLAN.md -- Add Frigate notification automation to Nix, set up Companion app, deploy to ser8
- [ ] 02-02-PLAN.md -- Verify end-to-end notification delivery with real detections

### Phase 3: Camera Dashboard
**Goal**: I can monitor all cameras live, browse detection events, and toggle detection per camera from an HA dashboard
**Depends on**: Phase 1
**Requirements**: DASH-01, DASH-02, DASH-03, DASH-04
**Success Criteria** (what must be TRUE):
  1. HA dashboard shows live camera feeds from all 3 active Frigate cameras (driveway, front_door, garage)
  2. Recent detection events are displayed with snapshot thumbnails showing what was detected and when
  3. Detection can be enabled or disabled per camera directly from the HA dashboard
  4. Detection event history is browsable with the ability to filter by camera or object type
**Plans**: TBD

Plans:
- [ ] 03-01: TBD

## Progress

**Execution Order:**
Phases execute in numeric order: 1 -> 2 -> 3

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Integration Foundation | 2/2 | Complete | 2026-02-10 |
| 2. Push Notifications | 0/2 | Not started | - |
| 3. Camera Dashboard | 0/TBD | Not started | - |
