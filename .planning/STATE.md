# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-02-09)

**Core value:** When Frigate detects a person, car, or package, a push notification with a snapshot image arrives on my phone within seconds -- and I can review all events from the HA dashboard.
**Current focus:** Phase 2: Push Notifications

## Current Position

Phase: 2 of 3 (Push Notifications)
Plan: 1 of 2 in current phase
Status: Plan 02-01 complete, starting 02-02 (end-to-end verification)
Last activity: 2026-02-10 -- Completed 02-01-PLAN.md (notification automation + Companion app)

Progress: [█████░░░░░] 50%

## Performance Metrics

**Velocity:**
- Total plans completed: 3
- Average duration: 12min
- Total execution time: 35min

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| Phase 01 P01 | 5min | 3 tasks | 2 files |
| Phase 01 P02 | 15min | 3 tasks | 0 files (deploy+verify) |
| Phase 02 P01 | 15min | 3 tasks | 1 file |

**Recent Trend:**
- Last 5 plans: 5min, 15min, 15min
- Trend: stable

*Updated after each plan completion*

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- MQTT auto-discovery over HACS integration (declarative compatibility)
- Push notifications via HA Companion app (standard HA mobile path)
- All automations declared in Nix (matches repo pattern)
- [Phase 01]: Used wants (not requires) for HA->Frigate so HA starts even if Frigate is down
- [Phase 01]: Used requires for Frigate->Mosquitto since Frigate cannot function without MQTT
- [Phase 01]: Zone coordinates are placeholders to be tuned via Frigate UI in Plan 02
- [Phase 01]: MQTT broker configured without auth (local-only, behind Tailscale)
- [Phase 01]: Transient Frigate API 500s during startup are expected, self-resolve
- [Phase 02]: mobile_app = {} must be in HA config section (extraComponents alone insufficient)
- [Phase 02]: Device ID hardcoded in Nix (single-user homelab): bobbo_dhillons_iphone
- [Phase 02]: HA Developer Tools "Services" renamed to "Actions" in newer HA versions

### Pending Todos

None yet.

### Blockers/Concerns

- Phase 1: Two config entries (MQTT broker, Frigate integration) require one-time HA UI setup -- not fully declarative. Document in runbook.
- Phase 3: advanced-camera-card availability in nixpkgs needs verification during Phase 3 planning.

## Session Continuity

Last session: 2026-02-10
Stopped at: Plan 02-01 complete, starting Wave 2 (02-02 verification)
Resume file: None
