---
gsd_state_version: 1.0
milestone: v1.1
milestone_name: Monitoring & Alerting
current_phase: 08
current_phase_name: reorganize-ser8-media-nix-into-per-service-modules
status: executing
stopped_at: Completed 08-04-PLAN.md
last_updated: "2026-07-25T22:21:26.272Z"
last_activity: 2026-07-25
last_activity_desc: Phase 08 execution started
progress:
  total_phases: 5
  completed_phases: 2
  total_plans: 11
  completed_plans: 8
  percent: 40
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-02-10)

**Core value:** The homelab runs reliably without manual intervention -- when something needs attention, I know about it before it becomes a problem.
**Current focus:** Phase 08 — reorganize-ser8-media-nix-into-per-service-modules

## Current Position

Phase: 08 (reorganize-ser8-media-nix-into-per-service-modules) — EXECUTING
Plan: 5 of 7
Status: Ready to execute
Last activity: 2026-07-25 — Phase 08 execution started

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
| Phase 08 P01 | 14min | 2 tasks | 9 files |
| Phase 08 P02 | 8min | 3 tasks | 7 files |
| Phase 08 P03 | 9min | 3 tasks | 6 files |
| Phase 08 P04 | 5min | 2 tasks | 6 files |

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
- [Phase 08]: Permit only the exact user-approved Home Manager mismatch baseline — Continue without changing dependency pins or disabling release checks; reject changed or new warnings.
- [Phase 08]: Normalize approved helper and generated unit-script store paths — Compare evaluated media behavior while allowing only documented structural derivation changes.
- [Phase 08]: Keep each Arr service's enablement, secrets, template, exporter instance, and deployment contribution together in one host module. - This makes each service a complete discoverable host-policy slice.
- [Phase 08]: Preserve Arr deployment order with explicit priorities 200, 300, and 400 rather than import ordering. - Explicit priorities keep generated deployment behavior deterministic across module boundaries.
- [Phase 08]: Keep SABnzbd as the single declaration owner for shared administrator and Usenet credentials consumed by NZBGet. — Preserves existing credential names and avoids duplicate SOPS declarations.
- [Phase 08]: Use dependency priorities 450, 500, and 550 independently from deployment-script priorities 500, 600, and 700. — Preserves both evaluated unit ordering and deployment command ordering.
- [Phase 08]: Keep all Jellyfin household identities, credentials, API key wiring, and enablement decisions in the ser8 host module. — This keeps concrete household authorization and secret ownership out of reusable modules.
- [Phase 08]: Expose only enable and apiKeyFile as reusable Jellyfin exporter host inputs. — This is the minimum typed interface needed to preserve systemd credential delivery without host-specific references.

### Pending Todos

None.

### Blockers/Concerns

- Alloy NixOS module HCL config format needs verification during Phase 6 planning
- firebat impermanence status unclear -- verify Loki state persists naturally
- Grafana file-provisioned alerts are UI-locked (plan iteration workflow)
- Grafana file provisioning doesn't auto-delete removed rules; must use deleteRules array

### Roadmap Evolution

- Phase 8 added: Reorganize ser8 media.nix into per-service modules (independent refactor; no dependencies)

## Session Continuity

Last session: 2026-07-25T22:21:26.267Z
Stopped at: Completed 08-04-PLAN.md
Resume file: None
