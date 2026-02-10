# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-02-09)

**Core value:** When Frigate detects a person, car, or package, a push notification with a snapshot image arrives on my phone within seconds -- and I can review all events from the HA dashboard.
**Current focus:** Phase 3 in progress -- camera dashboard

## Current Position

Phase: 3 of 3 (Camera Dashboard)
Plan: 1 of 2 in current phase
Status: Plan 01 complete
Last activity: 2026-02-10 -- Completed 03-01-PLAN.md (camera dashboard config + deploy)

Progress: [████████░░] 83%

## Performance Metrics

**Velocity:**
- Total plans completed: 5
- Average duration: 12min
- Total execution time: 62min

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| Phase 01 P01 | 5min | 3 tasks | 2 files |
| Phase 01 P02 | 15min | 3 tasks | 0 files (deploy+verify) |
| Phase 02 P01 | 15min | 3 tasks | 1 file |
| Phase 02 P02 | 20min | 2 tasks | 1 file |
| Phase 03 P01 | 7min | 2 tasks | 1 file |

**Recent Trend:**
- Last 5 plans: 5min, 15min, 15min, 20min, 7min
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
- [Phase 02]: HA 2025.5+: use trigger.payload | from_json, NOT trigger.payload_json
- [Phase 02]: HA Developer Tools "Services" renamed to "Actions" in newer versions
- [Phase 02]: Test notifications via Actions UI YAML mode with just message: field
- [Phase 03]: Dashboard content as Nix attrset -> JSON via builtins.toJSON (JSON is valid YAML)
- [Phase 03]: Deploy dashboard via L+ tmpfiles symlink from Nix store
- [Phase 03]: Separate entities cards for detection vs motion master toggles
- [Phase 03]: advanced-camera-card confirmed available in nixpkgs

### Pending Todos

None yet.

### Blockers/Concerns

- Phase 1: Two config entries (MQTT broker, Frigate integration) require one-time HA UI setup -- not fully declarative. Document in runbook.
- Phase 3: advanced-camera-card availability in nixpkgs needs verification during Phase 3 planning. **RESOLVED: confirmed available and builds.**

## Session Continuity

Last session: 2026-02-10
Stopped at: Completed 03-01-PLAN.md
Resume file: None
