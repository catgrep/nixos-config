# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-02-09)

**Core value:** When Frigate detects a person, car, or package, a push notification with a snapshot image arrives on my phone within seconds -- and I can review all events from the HA dashboard.
**Current focus:** All 3 phases complete — milestone done

## Current Position

Phase: 3 of 3 (Camera Dashboard)
Plan: 2 of 2 in current phase
Status: Milestone complete
Last activity: 2026-02-10 -- Completed 03-02-PLAN.md (dashboard verification + fixes)

Progress: [██████████] 100%

## Performance Metrics

**Velocity:**
- Total plans completed: 6
- Average duration: 15min
- Total execution time: 107min

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| Phase 01 P01 | 5min | 3 tasks | 2 files |
| Phase 01 P02 | 15min | 3 tasks | 0 files (deploy+verify) |
| Phase 02 P01 | 15min | 3 tasks | 1 file |
| Phase 02 P02 | 20min | 2 tasks | 1 file |
| Phase 03 P01 | 7min | 2 tasks | 1 file |
| Phase 03 P02 | 45min | 2 tasks | 2 files (iterative fix cycle) |

**Recent Trend:**
- Last 6 plans: 5min, 15min, 15min, 20min, 7min, 45min
- Trend: Phase 3 P02 longer due to multiple bug fixes during verification

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
- [Phase 03]: customLovelaceModules auto-registration only works with lovelace.mode = "yaml"
- [Phase 03]: Storage mode requires declarative .storage/lovelace_resources via tmpfiles C+
- [Phase 03]: restartTriggers (not reloadTriggers) needed — HA reads YAML dashboards at startup only
- [Phase 03]: Card type renamed in v7.0.0: custom:frigate-card -> custom:advanced-camera-card
- [Phase 03]: HA dashboard URL paths must contain a hyphen (lovelace-cameras, not cameras)
- [Phase 03]: Frigate stationary detection: threshold=300 (5min), interval=432000 (24hr) at 5fps
- [Phase 03]: Deep-link to specific clip by event ID not supported by advanced-camera-card (issues #1246, #2138)
- [Phase 03]: persistent_notification.create for HA Notifications tab alongside mobile push

### Pending Todos

None.

### Blockers/Concerns

- Phase 1: Two config entries (MQTT broker, Frigate integration) require one-time HA UI setup -- not fully declarative. Document in runbook.
- Phase 3: advanced-camera-card availability in nixpkgs needs verification during Phase 3 planning. **RESOLVED: confirmed available and builds.**

## Session Continuity

Last session: 2026-02-10
Stopped at: Milestone complete
Resume file: None
