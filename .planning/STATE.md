# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-02-10)

**Core value:** The homelab runs reliably without manual intervention -- when something needs attention, I know about it before it becomes a problem.
**Current focus:** Phase 5 - Hardware Alerts & Status Dashboard

## Current Position

Phase: 5 of 7 (Hardware Alerts & Status Dashboard) -- COMPLETE
Plan: 2 of 2 complete
Status: Phase Complete
Last activity: 2026-02-13 -- Phase 5 complete (uptime dashboard + ZFS zed email alerts)

Progress: [#######░░░] 71% (10/14 plans across both milestones)

## Performance Metrics

**Velocity:**
- Total plans completed: 10 (6 v1.0 + 4 v1.1)
- Average duration: ~17 min
- Total execution time: ~2.9 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 1. Integration Foundation | 2 | ~35 min | ~18 min |
| 2. Push Notifications | 2 | ~32 min | ~16 min |
| 3. Camera Dashboard | 2 | ~40 min | ~20 min |
| 4. Alert Delivery & Service Probes | 2 | ~45 min | ~23 min |
| 5. Hardware Alerts & Status Dashboard | 2 | ~21 min | ~11 min |

**Recent Trend:**
- Last 2 plans: Phase 5 plan 01 + 02 (graduated alerts + uptime dashboard + zed)
- Trend: Consistent (~11 min avg for Phase 5)

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
- [Phase 5]: Grafana deleteRules needed to remove deprecated file-provisioned alert rules
- [Phase 5]: rate() over irate() for alert PromQL expressions (smoother signal, fewer false positives)
- [Phase 5]: msmtp as lightweight MTA on ser8 (not full Postfix); only zed needs email capability
- [Phase 5]: Grafana field overrides for friendly display names in state-timeline panels

### Pending Todos

None.

### Blockers/Concerns

- Alloy NixOS module HCL config format needs verification during Phase 6 planning
- firebat impermanence status unclear -- verify Loki state persists naturally
- Grafana file-provisioned alerts are UI-locked (plan iteration workflow)
- Grafana file provisioning doesn't auto-delete removed rules; must use deleteRules array

## Session Continuity

Last session: 2026-02-13
Stopped at: Completed 05-02-PLAN.md (Phase 5 complete: uptime dashboard + ZFS zed email alerts)
Resume file: None
