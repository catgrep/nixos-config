# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-02-10)

**Core value:** The homelab runs reliably without manual intervention -- when something needs attention, I know about it before it becomes a problem.
**Current focus:** Phase 5 - Hardware Alerts & Status Dashboard

## Current Position

Phase: 5 of 7 (Hardware Alerts & Status Dashboard)
Plan: 1 of 2 complete
Status: Executing
Last activity: 2026-02-13 -- Phase 5 plan 01 executed (graduated disk alerts + CPU alert)

Progress: [######░░░░] 64% (9/14 plans across both milestones)

## Performance Metrics

**Velocity:**
- Total plans completed: 9 (6 v1.0 + 3 v1.1)
- Average duration: ~18 min
- Total execution time: ~2.7 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 1. Integration Foundation | 2 | ~35 min | ~18 min |
| 2. Push Notifications | 2 | ~32 min | ~16 min |
| 3. Camera Dashboard | 2 | ~40 min | ~20 min |
| 4. Alert Delivery & Service Probes | 2 | ~45 min | ~23 min |
| 5. Hardware Alerts & Status Dashboard | 1 | ~10 min | ~10 min |

**Recent Trend:**
- Last 2 plans: Phase 5 plan 01 (graduated disk + CPU alerts)
- Trend: Faster (simple config change, no new modules)

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

### Pending Todos

None.

### Blockers/Concerns

- Alloy NixOS module HCL config format needs verification during Phase 6 planning
- firebat impermanence status unclear -- verify Loki state persists naturally
- Grafana file-provisioned alerts are UI-locked (plan iteration workflow)
- Grafana file provisioning doesn't auto-delete removed rules; must use deleteRules array

## Session Continuity

Last session: 2026-02-13
Stopped at: Completed 05-01-PLAN.md (graduated disk alerts + CPU alert)
Resume file: None
