# Requirements: Frigate-Home Assistant Integration

**Defined:** 2026-02-09
**Core Value:** When Frigate detects a person, car, or package, a push notification with a snapshot image arrives on my phone within seconds — and I can review all events from the HA dashboard.

## v1 Requirements

Requirements for initial release. Each maps to roadmap phases.

### Integration Foundation

- [ ] **INTG-01**: Frigate custom component installed via NixOS `customComponents`
- [ ] **INTG-02**: MQTT integration configured in HA (one-time UI config flow, documented in runbook)
- [ ] **INTG-03**: Frigate integration configured in HA (one-time UI config flow, documented in runbook)
- [ ] **INTG-04**: Systemd service ordering: Frigate and HA depend on Mosquitto
- [ ] **INTG-05**: Frigate entities auto-discovered in HA (cameras, binary sensors, switches)
- [ ] **INTG-06**: HA state persists across ser8 reboot (impermanence validation)
- [ ] **INTG-07**: Detection zones configured per camera to reduce false positives

### Notifications

- [ ] **NOTF-01**: Push notification with snapshot sent on person detection (all cameras)
- [ ] **NOTF-02**: Push notification with snapshot sent on car detection (all cameras)
- [ ] **NOTF-03**: Push notification with snapshot sent on package detection (all cameras)
- [ ] **NOTF-04**: Notifications deduplicated — same event updates in-place, no spam
- [ ] **NOTF-05**: Actionable notifications — tap to view clip or mark as reviewed
- [ ] **NOTF-06**: All notification automations declared in Nix

### Dashboard

- [ ] **DASH-01**: Live camera feeds from all active Frigate cameras in HA dashboard
- [ ] **DASH-02**: Recent detection events displayed with snapshot thumbnails
- [ ] **DASH-03**: Camera controls — enable/disable detection per camera from HA
- [ ] **DASH-04**: Detection event history browsing with filtering

## v2 Requirements

Deferred to future release. Tracked but not in current roadmap.

### Notifications

- **NOTF-07**: Quiet hours suppression (configurable time window, no alerts)
- **NOTF-08**: Presence-based suppression (no alerts when home)

### Detection

- **DETC-01**: Audio detection events (glass break, doorbell, etc.)
- **DETC-02**: Per-camera notification rules (different objects trigger on different cameras)

### Dashboard

- **DASH-05**: Birdseye combined camera overview

## Out of Scope

| Feature | Reason |
|---------|--------|
| HACS integration | Requires mutable state incompatible with NixOS impermanence; custom component via nixpkgs covers the functionality |
| Indoor cameras (living_room, basement) | Currently disabled in Frigate, not part of this integration |
| side_gate camera | Currently disabled in Frigate |
| HA Companion app installation | Manual phone setup, not NixOS-configurable |
| Email or SMS notifications | Push via Companion app is sufficient |
| Two-way audio | Not supported by current camera setup |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| INTG-01 | Phase 1 | Pending |
| INTG-02 | Phase 1 | Pending |
| INTG-03 | Phase 1 | Pending |
| INTG-04 | Phase 1 | Pending |
| INTG-05 | Phase 1 | Pending |
| INTG-06 | Phase 1 | Pending |
| INTG-07 | Phase 1 | Pending |
| NOTF-01 | Phase 2 | Pending |
| NOTF-02 | Phase 2 | Pending |
| NOTF-03 | Phase 2 | Pending |
| NOTF-04 | Phase 2 | Pending |
| NOTF-05 | Phase 2 | Pending |
| NOTF-06 | Phase 2 | Pending |
| DASH-01 | Phase 3 | Pending |
| DASH-02 | Phase 3 | Pending |
| DASH-03 | Phase 3 | Pending |
| DASH-04 | Phase 3 | Pending |

**Coverage:**
- v1 requirements: 17 total
- Mapped to phases: 17
- Unmapped: 0

---
*Requirements defined: 2026-02-09*
*Last updated: 2026-02-09 after roadmap creation*
