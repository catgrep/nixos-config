# Requirements: NixOS Homelab Monitoring & Alerting

**Defined:** 2026-02-10
**Core Value:** The homelab runs reliably without manual intervention — when something needs attention, I know about it before it becomes a problem.

## v1.1 Requirements

Requirements for milestone v1.1. Each maps to roadmap phases.

### Alert Delivery

- [ ] **ALERT-01**: Grafana unified alerting enabled with Gmail SMTP contact point
- [ ] **ALERT-02**: Existing 6 Prometheus alert rules deliver email notifications
- [ ] **ALERT-03**: All alert rules provisioned declaratively in Nix (not UI click-ops)
- [ ] **ALERT-04**: SMTP credentials stored in SOPS using `$__file{}` pattern

### Service Probes

- [ ] **PROBE-01**: Blackbox exporter probes HTTP endpoints for all services (Jellyfin, Sonarr, Radarr, Prowlarr, qBittorrent, SABnzbd, Frigate, HA)
- [ ] **PROBE-02**: ICMP probes for host reachability (ser8, firebat, pi4)
- [ ] **PROBE-03**: TLS certificate expiry monitoring for Tailscale URLs
- [ ] **PROBE-04**: Alert fires when any service probe fails for >2 minutes

### Hardware Alerts

- [ ] **HW-01**: Disk space alerts with graduated severity (warning 80%, critical 90%) per mount
- [ ] **HW-02**: ZFS pool health alerts (degraded, scrub errors, capacity thresholds)
- [ ] **HW-03**: CPU sustained high usage alert (>90% for 5 minutes)
- [ ] **HW-04**: Memory pressure alert (available <10%)
- [ ] **HW-05**: Temperature alerts if thermal data available from node-exporter

### Log Monitoring

- [ ] **LOG-01**: Loki deployed on firebat for log aggregation
- [ ] **LOG-02**: Alloy deployed on all hosts (ser8, firebat, pi4) shipping journald to Loki
- [ ] **LOG-03**: Alloy positions file persisted on ser8 via impermanence
- [ ] **LOG-04**: Searchable log history in Grafana Explore via Loki datasource
- [ ] **LOG-05**: Log-based alert rules for OOM kills, ZFS errors, service crash patterns

### Dashboards

- [ ] **DASH-01**: Uptime/status dashboard showing green/red for every service with availability history
- [ ] **DASH-02**: HA monitoring dashboard: system health (CPU, memory, uptime, integration status)
- [ ] **DASH-03**: HA monitoring dashboard: entity tracking (camera online/offline, automation counts)

### HA Automations

- [ ] **HA-01**: HA automation: camera offline detection → push notification
- [ ] **HA-02**: HA automation: MQTT broker disconnect → push notification
- [ ] **HA-03**: HA automation: integration failure detection → push notification
- [ ] **HA-04**: HA Prometheus integration enabled for entity metrics export

## Future Requirements

Deferred to future milestone. Tracked but not in current roadmap.

### Hardware Deep Monitoring

- **SMART-01**: SMART disk monitoring via smartctl_exporter for predictive failure
- **SMART-02**: NVMe health metrics collection

### Advanced Alerting

- **ADV-01**: PagerDuty/Discord webhook integration for critical alerts
- **ADV-02**: Alert escalation policies (warning → critical → page)

## Out of Scope

Explicitly excluded. Documented to prevent scope creep.

| Feature | Reason |
|---------|--------|
| Standalone Alertmanager | Grafana Unified Alerting handles everything at homelab scale |
| Uptime Kuma / status page | Redundant with Blackbox + Grafana dashboard |
| Multi-tenant Loki | Single-operator homelab, auth_enabled: false is correct |
| Tracing / APM | Overkill for homelab, metrics + logs sufficient |
| External uptime monitoring | All internal, Tailscale-only access |
| SMART disk monitoring | Useful but nixpkgs smartctl_exporter has device permission quirks — defer |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| ALERT-01 | — | Pending |
| ALERT-02 | — | Pending |
| ALERT-03 | — | Pending |
| ALERT-04 | — | Pending |
| PROBE-01 | — | Pending |
| PROBE-02 | — | Pending |
| PROBE-03 | — | Pending |
| PROBE-04 | — | Pending |
| HW-01 | — | Pending |
| HW-02 | — | Pending |
| HW-03 | — | Pending |
| HW-04 | — | Pending |
| HW-05 | — | Pending |
| LOG-01 | — | Pending |
| LOG-02 | — | Pending |
| LOG-03 | — | Pending |
| LOG-04 | — | Pending |
| LOG-05 | — | Pending |
| DASH-01 | — | Pending |
| DASH-02 | — | Pending |
| DASH-03 | — | Pending |
| HA-01 | — | Pending |
| HA-02 | — | Pending |
| HA-03 | — | Pending |
| HA-04 | — | Pending |

**Coverage:**
- v1.1 requirements: 25 total
- Mapped to phases: 0
- Unmapped: 25 ⚠️

---
*Requirements defined: 2026-02-10*
*Last updated: 2026-02-10 after initial definition*
