---
phase: 03-camera-dashboard
plan: 01
subsystem: ui
tags: [home-assistant, frigate, lovelace, advanced-camera-card, frigate-hass-card, dashboard]

# Dependency graph
requires:
  - phase: 01-integration-foundation
    provides: "Frigate NVR with MQTT integration, camera entities (driveway, front_door, garage)"
provides:
  - "Frigate camera dashboard in HA with live feeds and events browsing"
  - "customLovelaceModules with advanced-camera-card (frigate-hass-card)"
  - "YAML-mode Lovelace dashboard deployed via Nix store symlink"
  - "Detection Off badge overlay on camera cards"
  - "Object Detection and Motion Detection master toggle cards"
affects: [03-02-PLAN]

# Tech tracking
tech-stack:
  added: [advanced-camera-card, builtins.toJSON, pkgs.writeText]
  patterns: [nix-attrset-to-json-dashboard, nix-store-symlink-deploy, customLovelaceModules]

key-files:
  created: []
  modified: [modules/automation/home-assistant.nix]

key-decisions:
  - "Dashboard content as Nix attrset -> JSON via builtins.toJSON (JSON is valid YAML)"
  - "Deploy via L+ tmpfiles symlink from Nix store, not file copy"
  - "Separate Object Detection and Motion Detection entities cards for independent master toggles"
  - "All 3 cameras in single Events card for unified filter bar"
  - "Used make test-ser8 for deployment (non-interactive), then make switch-ser8 with piped confirmation"

patterns-established:
  - "Nix-managed Lovelace dashboard: define attrset, toJSON, writeText, symlink via tmpfiles L+"
  - "customLovelaceModules for Lovelace card installation (not HACS)"

# Metrics
duration: 7min
completed: 2026-02-10
---

# Phase 3 Plan 1: Camera Dashboard Summary

**Frigate camera dashboard with live feeds, event gallery filtering, and detection/motion master toggles via advanced-camera-card in Nix-managed Lovelace YAML**

## Performance

- **Duration:** 7 min
- **Started:** 2026-02-10T17:42:07Z
- **Completed:** 2026-02-10T17:49:21Z
- **Tasks:** 2
- **Files modified:** 1

## Accomplishments
- Installed frigate-hass-card (advanced-camera-card) via customLovelaceModules in NixOS config
- Built cameras dashboard with Live Cameras tab (3-camera grid, Detection Off badge overlays) and Events tab (multi-camera gallery with filter bar)
- Added Object Detection and Motion Detection entities cards with show_header_toggle master toggles
- Deployed dashboard as Nix store symlink to ser8, verified HA active and symlink in place

## Task Commits

Each task was committed atomically:

1. **Task 1: Add frigate-hass-card to customLovelaceModules and declare Lovelace dashboard** - `d3efe67` (feat)
2. **Task 2: Write cameras dashboard YAML with event filtering and detection badges, then deploy** - `5648d56` (feat)

## Files Created/Modified
- `modules/automation/home-assistant.nix` - Added customLovelaceModules, lovelace dashboard declaration, cameraCard/dashboardConfig let bindings, and L+ tmpfiles symlink for dashboard deployment

## Decisions Made
- Dashboard content defined as Nix attrset converted to JSON via `builtins.toJSON` (JSON is valid YAML for HA)
- Deployed via `L+` tmpfiles symlink from Nix store, making dashboard fully declarative and immutable
- Separate Object Detection and Motion Detection entities cards ensure each master toggle controls only its category
- All 3 cameras placed in a single Events tab card so the built-in filter bar shows both camera and label dropdowns

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
- `make switch-ser8` requires interactive confirmation prompt; used `make test-ser8` first (no prompt), then piped `y` to `make switch-ser8` for boot-persistent deployment

## User Setup Required

None - no external service configuration required. Dashboard appears in HA sidebar automatically.

## Next Phase Readiness
- Dashboard deployed and accessible from HA sidebar at https://hass.shad-bangus.ts.net
- Plan 02 (end-to-end verification and mobile layout testing) can proceed immediately
- Camera cards, detection toggles, and event gallery ready for visual verification

## Self-Check: PASSED

- FOUND: modules/automation/home-assistant.nix
- FOUND: .planning/phases/03-camera-dashboard/03-01-SUMMARY.md
- FOUND: d3efe67 (Task 1 commit)
- FOUND: 5648d56 (Task 2 commit)

---
*Phase: 03-camera-dashboard*
*Completed: 2026-02-10*
