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

- [x] **Phase 4: Alert Delivery & Service Probes** - Email notifications for existing alerts, HTTP/ICMP probes for all services
- [ ] **Phase 5: Hardware Alerts & Status Dashboard** - Hardware health alert rules, uptime dashboard showing service availability
- [ ] **Phase 6: Log Aggregation** - Centralized searchable logs from all hosts with log-based alerting
- [ ] **Phase 7: HA Monitoring** - HA automations for infrastructure alerts, HA dashboards for entity tracking
- [ ] **Phase 8: Reorganize ser8 media.nix** - Split the ~750-line host media config into per-service modules (independent refactor)

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

**Plans**: 2 plans

Plans:

- [x] 04-01-PLAN.md -- Grafana SMTP email delivery, contact point, notification policy, 6 migrated alert rules
- [x] 04-02-PLAN.md -- Blackbox exporter, HTTP/ICMP/TLS probes, 3 probe-based alert rules

### Phase 5: Hardware Alerts & Status Dashboard

**Goal**: Hardware problems (disk space, ZFS degradation, CPU/memory/temp) trigger graduated alerts, and a single dashboard shows green/red status for every monitored service
**Depends on**: Phase 4
**Requirements**: HW-01, HW-02, HW-03, HW-04, HW-05, DASH-01
**Success Criteria** (what must be TRUE):

  1. Filling a disk past 80% triggers a warning email; past 90% triggers a critical email (per mount point)
  2. A degraded ZFS pool or scrub errors trigger an email alert
  3. Sustained high CPU (>90% for 5min) or low available memory (<10%) triggers an email alert
  4. Grafana uptime dashboard shows a green/red indicator for every probed service with availability history over time

**Plans**: 2 plans

Plans:

- [ ] 05-01-PLAN.md -- Graduated disk alerts (warning 80%, critical 90%), CPU sustained usage alert, Prometheus ruleFiles update
- [ ] 05-02-PLAN.md -- Uptime/status dashboard with state-timeline panels, ZFS zed email via msmtp on ser8

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

### Phase 8: Reorganize ser8 media.nix into per-service modules

**Goal**: `hosts/ser8/media.nix` is decomposed into focused per-service files under `hosts/ser8/media/`, each owning its own SOPS secrets, templates, and systemd units, so a service's full configuration is discoverable in one place and adding a user or service is a self-contained change — with no change to the running system
**Depends on**: None (independent refactor; can run before or after Phases 5-7)
**Requirements**: N/A (maintainability / tech debt — not tied to a v1.1 monitoring requirement)
**Success Criteria** (what must be TRUE):

  1. `hosts/ser8/media.nix` is gone; ser8 imports a `hosts/ser8/media/` directory whose `default.nix` only lists per-service imports
  2. Each service (jellyfin, nzbget, qbittorrent, sabnzbd, sonarr, radarr, prowlarr) has its own file owning its enablement, host settings, SOPS secret declarations, SOPS template, and any proxy/deployment unit
  3. Jellyfin household users (admin, jordan, sawnia) live in host config, not the reusable `modules/media/jellyfin.nix`; the reusable module keeps only generic service/account/network/firewall config
  4. Genuinely cross-service behavior (Prowlarr↔Sonarr/Radarr wiring, download-client registration, `media-setup.target`, startup ordering) is isolated in one orchestration file
  5. `make check` passes and `make build-ser8` evaluates the ser8 system to the same store path as before the refactor, proving a pure behavior-preserving move

**Out of scope (decide during planning)**: renaming the shared `sabnzbd_usenet_*` secrets to neutral `usenet_*` names, and giving NZBGet its own `nzbget_admin_password` instead of reusing `sabnzbd_admin_password`. These change deployed credentials and the system derivation, so they break criterion 5 and belong in a follow-up.

**Plans**: 6/7 plans executed

Plans:
**Wave 1**

- [x] 08-01-PLAN.md -- Capture non-secret behavior baseline and establish the directory import seam

**Wave 2** *(blocked on Wave 1 completion)*

- [x] 08-02-PLAN.md -- Extract Sonarr, Radarr, and Prowlarr host slices with owned exporters

**Wave 3** *(blocked on Wave 2 completion)*

- [x] 08-03-PLAN.md -- Extract NZBGet, SABnzbd, and qBittorrent host slices

**Wave 4** *(blocked on Wave 3 completion)*

- [x] 08-04-PLAN.md -- Move Jellyfin household policy to ser8 and genericize the exporter

**Wave 5** *(blocked on Wave 4 completion)*

- [x] 08-05-PLAN.md -- Split helpers, extract orchestration and SOPS support, remove legacy aggregates

**Wave 6** *(blocked on Wave 5 completion)*

- [x] 08-06-PLAN.md -- Remove dead media modules and adjacent AllDebrid remnants

**Wave 7** *(blocked on Wave 6 completion)*

- [ ] 08-07-PLAN.md -- Audit active reusable providers and run final no-activation acceptance gates

## Progress

**Execution Order:**
Phases execute in numeric order: 4 -> 5 -> 6 -> 7
(Phases 5, 6, 7 depend on Phase 4. Phases 6 and 7 are independent of each other.)
Phase 8 is an independent refactor with no dependencies and can be scheduled at any time.

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 1. Integration Foundation | v1.0 | 2/2 | Complete | 2026-02-10 |
| 2. Push Notifications | v1.0 | 2/2 | Complete | 2026-02-10 |
| 3. Camera Dashboard | v1.0 | 2/2 | Complete | 2026-02-10 |
| 4. Alert Delivery & Service Probes | v1.1 | 2/2 | Complete | 2026-02-12 |
| 5. Hardware Alerts & Status Dashboard | v1.1 | 0/2 | Planned | - |
| 6. Log Aggregation | v1.1 | 0/TBD | Not started | - |
| 7. HA Monitoring | v1.1 | 0/TBD | Not started | - |
| 8. Reorganize ser8 media.nix | v1.1 | 6/7 | In Progress|  |
