# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-02-10)

**Core value:** The homelab runs reliably without manual intervention -- when something needs attention, I know about it before it becomes a problem.
**Current focus:** Phase 5 - Hardware Alerts & Status Dashboard

## Current Position

Phase: 5 of 7 (Hardware Alerts & Status Dashboard)
Plan: Not started
Status: Ready to plan
Last activity: 2026-02-12 -- Phase 4 executed (alert delivery + service probes)

Progress: [######░░░░] 57% (8/14 plans across both milestones)

## Performance Metrics

**Velocity:**
- Total plans completed: 8 (6 v1.0 + 2 v1.1)
- Average duration: ~19 min
- Total execution time: ~2.5 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 1. Integration Foundation | 2 | ~35 min | ~18 min |
| 2. Push Notifications | 2 | ~32 min | ~16 min |
| 3. Camera Dashboard | 2 | ~40 min | ~20 min |
| 4. Alert Delivery & Service Probes | 2 | ~45 min | ~23 min |

**Recent Trend:**
- Last 2 plans: Phase 4 execution (04-01, 04-02)
- Trend: Stable

*Updated after each plan completion*

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- [v1.1]: Grafana Unified Alerting for metrics alerts (not standalone Alertmanager)
- [v1.1]: Gmail SMTP for email notifications (app password via SOPS)
- [v1.1]: Loki on firebat (NOT ser8 -- impermanence would lose data)
- [v1.1]: Alloy replaces Promtail (EOL Feb 28 2026)
- [v1.1]: Blackbox exporter on firebat, probes direct service ports (not Caddy proxies)
- [Phase 4]: Alert recipient is catgrep@sudomail.com (sender shadbangus@gmail.com)
- [Phase 4]: Blackbox probe targets use direct IPs, not .local mDNS (exporter can't resolve mDNS)
- [Phase 4]: Prometheus ruleFiles kept as defense-in-depth alongside Grafana-managed rules

### Pending Todos

None.

### Blockers/Concerns

- Alloy NixOS module HCL config format needs verification during Phase 6 planning
- firebat impermanence status unclear -- verify Loki state persists naturally
- Grafana file-provisioned alerts are UI-locked (plan iteration workflow)

## Session Continuity

Last session: 2026-02-12
Stopped at: Phase 4 complete, ready for Phase 5 planning
Resume file: None
