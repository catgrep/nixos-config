# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-02-10)

**Core value:** The homelab runs reliably without manual intervention — when something needs attention, I know about it before it becomes a problem.
**Current focus:** Milestone v1.1 — Monitoring & Alerting

## Current Position

Phase: Not started (defining requirements)
Plan: —
Status: Defining requirements
Last activity: 2026-02-10 — Milestone v1.1 started

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- MQTT auto-discovery over HACS integration (declarative compatibility) — ✓ Good
- Push notifications via HA Companion app (standard HA mobile path) — ✓ Good
- All automations declared in Nix (matches repo pattern) — ✓ Good
- [v1.1]: Grafana alerting for metrics + HA automations for integration-level alerts (dual path)
- [v1.1]: Gmail SMTP for Grafana email notifications
- [v1.1]: Loki + Promtail for log aggregation

### Pending Todos

None.

### Blockers/Concerns

- Loki + Promtail availability and NixOS module quality needs verification during research
- Blackbox exporter NixOS module configuration needs research
- HA Prometheus exporter or equivalent needed for HA monitoring dashboard
- Gmail app password SOPS integration for Grafana SMTP needs verification

## Session Continuity

Last session: 2026-02-10
Stopped at: Milestone v1.1 initialization — defining requirements
Resume file: None
