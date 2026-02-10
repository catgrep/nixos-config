# Roadmap: NixOS Homelab Monitoring & Alerting

## Milestones

- v1.0 MVP - Phases 1-3 (shipped 2026-02-10)
- **v1.1 Monitoring & Alerting** - Phases 4-7 (in progress)

## Phases

<details>
<summary>v1.0 Frigate-Home Assistant Integration (Phases 1-3) - SHIPPED 2026-02-10</summary>

### Phase 1: Integration Foundation
**Goal**: Frigate entities are auto-discovered in HA, update in real-time, and survive ser8 reboots
**Plans**: 2 plans

Plans:
- [x] 01-01: NixOS module changes: Frigate custom component, systemd ordering, automation split, detection zones
- [x] 01-02: Deploy to ser8, complete UI config flows, verify entity discovery and reboot persistence

### Phase 2: Push Notifications
**Goal**: A push notification with a snapshot image arrives on my phone within seconds of Frigate detecting a person, car, or package
**Plans**: 2 plans

Plans:
- [x] 02-01: Add Frigate notification automation to Nix, set up Companion app, deploy to ser8
- [x] 02-02: Verify end-to-end notification delivery with real detections

### Phase 3: Camera Dashboard
**Goal**: I can monitor all cameras live, browse detection events, and toggle detection per camera from an HA dashboard
**Plans**: 2 plans

Plans:
- [x] 03-01: Add advanced-camera-card to customLovelaceModules, declare YAML-mode cameras dashboard, deploy to ser8
- [x] 03-02: Verify dashboard rendering (live feeds, events, controls), fix issues, user approval on desktop and mobile

</details>

### v1.1 Monitoring & Alerting (In Progress)

**Milestone Goal:** Comprehensive monitoring with proactive alerting so I never discover problems by stumbling into them.

- [ ] **Phase 4: Alert Delivery & Service Probes** - Email notifications for existing alerts, HTTP/ICMP probes for all services
- [ ] **Phase 5: Hardware Alerts & Status Dashboard** - Hardware health alert rules, uptime dashboard showing service availability
- [ ] **Phase 6: Log Aggregation** - Centralized searchable logs from all hosts with log-based alerting
- [ ] **Phase 7: HA Monitoring** - HA automations for infrastructure alerts, HA dashboards for entity tracking

## Phase Details

### Phase 4: Alert Delivery & Service Probes
**Goal**: Every existing alert rule delivers an email notification, and every service is probed for availability so I know within minutes when something goes down
**Depends on**: Phase 3 (v1.0 complete)
**Requirements**: ALERT-01, ALERT-02, ALERT-03, ALERT-04, PROBE-01, PROBE-02, PROBE-03, PROBE-04
**Success Criteria** (what must be TRUE):
  1. Triggering a test alert in Grafana results in an email arriving in my Gmail inbox within 5 minutes
  2. Grafana Explore shows probe_success metrics for all 8 services (Jellyfin, Sonarr, Radarr, Prowlarr, qBittorrent, SABnzbd, Frigate, HA) plus ICMP for 3 hosts
  3. Stopping a service (e.g., Jellyfin) causes an email alert to arrive after the 2-minute threshold
  4. TLS certificate expiry dates for Tailscale URLs are visible as metrics in Grafana
  5. All alert rules and probe configuration are in Nix files (no UI click-ops required to reproduce from scratch)
**Plans**: TBD

Plans:
- [ ] 04-01: TBD
- [ ] 04-02: TBD

### Phase 5: Hardware Alerts & Status Dashboard
**Goal**: Hardware problems (disk space, ZFS degradation, CPU/memory/temp) trigger graduated alerts, and a single dashboard shows green/red status for every monitored service
**Depends on**: Phase 4
**Requirements**: HW-01, HW-02, HW-03, HW-04, HW-05, DASH-01
**Success Criteria** (what must be TRUE):
  1. Filling a disk past 80% triggers a warning email; past 90% triggers a critical email (per mount point)
  2. A degraded ZFS pool or scrub errors trigger an email alert
  3. Sustained high CPU (>90% for 5min) or low available memory (<10%) triggers an email alert
  4. Grafana uptime dashboard shows a green/red indicator for every probed service with availability history over time
**Plans**: TBD

Plans:
- [ ] 05-01: TBD

### Phase 6: Log Aggregation
**Goal**: Logs from all hosts are searchable in one place, and critical error patterns (OOM kills, ZFS errors, service crashes) trigger alerts automatically
**Depends on**: Phase 4
**Requirements**: LOG-01, LOG-02, LOG-03, LOG-04, LOG-05
**Success Criteria** (what must be TRUE):
  1. Grafana Explore with the Loki datasource returns journald logs from ser8, firebat, and pi4 when queried by host label
  2. Alloy positions file persists on ser8 across reboots (no duplicate log shipping after ZFS rollback)
  3. Searching for a specific service's logs (e.g., `{unit="jellyfin.service"}`) returns results within seconds
  4. An OOM kill or ZFS error in any host's journal triggers an email alert via Grafana
**Plans**: TBD

Plans:
- [ ] 06-01: TBD
- [ ] 06-02: TBD

### Phase 7: HA Monitoring
**Goal**: Home Assistant alerts me to infrastructure problems it detects (camera offline, MQTT down, integration failures), and Grafana dashboards show HA system health and entity status
**Depends on**: Phase 4
**Requirements**: HA-01, HA-02, HA-03, HA-04, DASH-02, DASH-03
**Success Criteria** (what must be TRUE):
  1. Disconnecting a camera from the network causes a push notification on my phone via HA automation
  2. Stopping Mosquitto causes a push notification about MQTT broker disconnect
  3. Grafana HA dashboard shows CPU, memory, uptime, and integration status for the HA instance
  4. Grafana HA dashboard shows camera online/offline status, automation counts, and entity availability
  5. HA entity metrics are visible in Prometheus (via /api/prometheus endpoint)
**Plans**: TBD

Plans:
- [ ] 07-01: TBD
- [ ] 07-02: TBD

## Progress

**Execution Order:**
Phases execute in numeric order: 4 -> 5 -> 6 -> 7
(Phases 5, 6, 7 depend on Phase 4. Phases 6 and 7 are independent of each other.)

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 1. Integration Foundation | v1.0 | 2/2 | Complete | 2026-02-10 |
| 2. Push Notifications | v1.0 | 2/2 | Complete | 2026-02-10 |
| 3. Camera Dashboard | v1.0 | 2/2 | Complete | 2026-02-10 |
| 4. Alert Delivery & Service Probes | v1.1 | 0/TBD | Not started | - |
| 5. Hardware Alerts & Status Dashboard | v1.1 | 0/TBD | Not started | - |
| 6. Log Aggregation | v1.1 | 0/TBD | Not started | - |
| 7. HA Monitoring | v1.1 | 0/TBD | Not started | - |
