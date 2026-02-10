# NixOS Homelab Infrastructure

## What This Is

A declarative NixOS homelab managing multiple hosts (ser8, firebat, pi4, pi5) with media services, security cameras, home automation, DNS, reverse proxy, and monitoring. All configuration is version-controlled Nix with SOPS secrets, Tailscale networking, and ZFS storage.

## Core Value

The homelab runs reliably without manual intervention — when something needs attention, I know about it before it becomes a problem.

## Current Milestone: v1.1 Monitoring & Alerting

**Goal:** Comprehensive monitoring with proactive alerting so I never discover problems by stumbling into them.

**Target features:**
- Grafana alerting with email notifications (Gmail SMTP)
- Service health probes via Prometheus blackbox exporter
- Hardware alerts (ZFS, disk space, CPU/memory/temp)
- Log monitoring via Loki + Promtail (searchable history + error alerting)
- Uptime dashboard showing service availability history
- HA monitoring dashboard (system health + entity tracking)
- HA-side alerting automations (camera offline, MQTT disconnect, integration failures)

## Requirements

### Validated

<!-- Shipped and confirmed valuable. -->

- ✓ Frigate NVR running with 3 active cameras (driveway, front_door, garage) — v1.0
- ✓ Object detection enabled for person, car, dog, cat, package — v1.0
- ✓ Mosquitto MQTT broker running on localhost:1883 — v1.0
- ✓ Frigate MQTT publishing enabled — v1.0
- ✓ Home Assistant running with MQTT and mobile_app components — v1.0
- ✓ Snapshots and 30-day event recording in Frigate — v1.0
- ✓ Camera recordings on ZFS backup pool (/mnt/cameras) — v1.0
- ✓ Frigate and HA accessible via Caddy reverse proxy and Tailscale — v1.0
- ✓ Prometheus monitoring for Frigate metrics — v1.0
- ✓ Frigate entities auto-discovered in HA via MQTT — v1.0
- ✓ HA push notifications with snapshot on person/car/package detection — v1.0
- ✓ HA dashboard with live camera feeds, detection events, event history — v1.0
- ✓ Camera controls in HA (enable/disable detection per camera) — v1.0
- ✓ All HA automations and dashboard config declared in Nix — v1.0

### Active

<!-- Current scope. Building toward these. -->

- [ ] Grafana unified alerting enabled with Gmail SMTP contact point
- [ ] Hardware alert rules: ZFS degraded, disk space low, high CPU/memory/temp
- [ ] Prometheus blackbox exporter probing all services (Jellyfin, Sonarr, Radarr, Prowlarr, qBittorrent, SABnzbd, Frigate, HA)
- [ ] Service down alerts when any probe fails
- [ ] Loki + Promtail deployed for log aggregation from journald
- [ ] Searchable log history in Grafana
- [ ] Alert rules on error patterns in service logs
- [ ] Uptime dashboard showing service availability history
- [ ] HA monitoring dashboard: system health (CPU, memory, uptime, integration status, automation counts)
- [ ] HA monitoring dashboard: entity tracking (availability, battery levels, sensor history)
- [ ] HA automations for camera offline / MQTT disconnect detection → push notification
- [ ] All monitoring config declared in Nix, credentials in SOPS

### Out of Scope

- Indoor cameras (living_room, basement) — currently disabled in Frigate
- side_gate camera — currently disabled in Frigate
- Custom detection zones per camera — can be added later via Frigate config
- Two-way audio — not supported by current camera models
- Tracing / APM — overkill for homelab, metrics + logs sufficient
- External uptime monitoring (e.g., UptimeRobot) — all internal, Tailscale-only access
- PagerDuty / OpsGenie integration — email alerts sufficient for homelab

## Context

- ser8 runs Frigate 0.15.2, Home Assistant, Mosquitto, and media stack on the same host
- firebat runs Caddy reverse proxy, Grafana, and Prometheus
- Prometheus already scrapes node-exporter (ser8, firebat, pi4), zfs-exporter (ser8), and Prometheus self
- Grafana has provisioned dashboards (Node Exporter Full, ZFS, Prometheus Stats)
- Grafana admin password already in SOPS (`grafana_admin_password`)
- HA uses declarative config via NixOS `services.home-assistant.config`
- HA Companion app push notifications working (v1.0 milestone)
- MQTT broker on localhost:1883, no auth (local-only, behind Tailscale)
- Loki + Promtail are available in nixpkgs
- Prometheus blackbox exporter available in nixpkgs

## Constraints

- **Declarative**: All config must be in NixOS Nix files, not UI-only configuration
- **Impermanence**: ser8 uses ZFS root rollback — persistent state must be in impermanence rules
- **Local MQTT**: Broker is localhost-only, no network exposure
- **No HACS**: Use MQTT auto-discovery for HA integrations, not HACS
- **Monitoring on firebat**: Prometheus and Grafana run on firebat, not ser8
- **SMTP credentials in SOPS**: Gmail app password must not be in plaintext

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| MQTT auto-discovery over HACS integration | HACS requires non-declarative HA UI setup; MQTT auto-discovery works with declarative NixOS config | ✓ Good |
| Push notifications via HA Companion app | Already have mobile_app component loaded; Companion app is the standard HA mobile notification path | ✓ Good |
| All automations in Nix | Matches repo pattern of declarative, version-controlled infrastructure | ✓ Good |
| Grafana alerting + HA automations (dual path) | Grafana for metric-based alerts, HA for integration-level alerts — each system alerts on what it knows best | — Pending |
| Gmail SMTP for Grafana email alerts | User has Gmail/Google Workspace; app password approach is well-documented | — Pending |
| Loki + Promtail for log aggregation | Standard Grafana ecosystem stack, available in nixpkgs, integrates with existing Grafana | — Pending |

---
*Last updated: 2026-02-10 after v1.1 milestone start*
