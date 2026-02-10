---
phase: 01-integration-foundation
plan: 01
subsystem: automation
tags: [nix, home-assistant, frigate, mosquitto, mqtt, systemd, zones]

# Dependency graph
requires: []
provides:
  - Frigate custom component installed in Home Assistant via customComponents
  - Systemd service ordering: mosquitto -> frigate -> home-assistant
  - Automation manual/UI split with automations.yaml tmpfile
  - Detection zones on driveway, front_door, garage cameras (placeholder coordinates)
affects: [01-02, phase-2-automations, phase-3-dashboard]

# Tech tracking
tech-stack:
  added: [home-assistant-custom-components.frigate]
  patterns: [systemd-service-ordering, automation-manual-ui-split, detection-zones]

key-files:
  created: []
  modified:
    - modules/automation/home-assistant.nix
    - modules/automation/frigate.nix

key-decisions:
  - "Used wants (not requires) for HA -> Frigate dependency so HA starts even if Frigate is down"
  - "Used requires (not wants) for Frigate -> Mosquitto dependency since Frigate cannot function without MQTT"
  - "Zone coordinates are placeholders to be tuned via Frigate UI in Plan 02"

patterns-established:
  - "Automation split: 'automation manual' for Nix-declared, 'automation ui' for !include automations.yaml"
  - "Tmpfiles for HA include files: create empty files to prevent HA crash on boot"

# Metrics
duration: 5min
completed: 2026-02-10
---

# Phase 1 Plan 1: Integration Foundation Summary

**Frigate custom component wired into Home Assistant with systemd ordering (mosquitto -> frigate -> HA), per-camera detection zones, and automation manual/UI split for Phase 2 readiness**

## Performance

- **Duration:** 5 min
- **Started:** 2026-02-10T06:31:56Z
- **Completed:** 2026-02-10T06:37:14Z
- **Tasks:** 3
- **Files modified:** 2

## Accomplishments
- Frigate custom component installed declaratively via NixOS customComponents
- Full systemd service chain: mosquitto.service -> frigate.service -> home-assistant.service
- Detection zones configured for 3 outdoor cameras (driveway, front_door, garage) with review alerts
- Automation manual/UI split pattern established with automations.yaml tmpfile for Phase 2

## Task Commits

Each task was committed atomically:

1. **Task 1: Configure Home Assistant module for Frigate integration** - `881c7c9` (feat)
2. **Task 2: Add Mosquitto dependency and detection zones to Frigate module** - `25195af` (feat)
3. **Task 3: Build ser8 configuration and format code** - `3b15104` (chore)

## Files Created/Modified
- `modules/automation/home-assistant.nix` - Added customComponents (frigate), automation split, automations.yaml tmpfile, systemd ordering
- `modules/automation/frigate.nix` - Added mosquitto.service dependency, detection zones for driveway/front_door/garage cameras

## Decisions Made
- Used `wants` (not `requires`) for HA -> Frigate/Mosquitto: HA should start gracefully even if Frigate is temporarily down
- Used `requires` (not `wants`) for Frigate -> Mosquitto: Frigate cannot function without MQTT broker
- Zone coordinates are placeholders (rectangular approximations) -- will be tuned via Frigate UI zone editor in Plan 02
- Did not add `mqtt:` broker settings to HA config block -- MQTT broker connection is configured via UI config flow (per research Pitfall 1)

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None

## User Setup Required

None - no external service configuration required. The one-time HA UI config flows (MQTT broker, Frigate integration) are handled in Plan 02.

## Next Phase Readiness
- NixOS modules are ready for deployment to ser8 via `make switch-ser8`
- After deployment, Plan 02 handles HA UI config flows and zone coordinate tuning
- Automation manual/UI split is in place for Phase 2 automation declarations

## Self-Check: PASSED

All files exist. All commits verified.

---
*Phase: 01-integration-foundation*
*Completed: 2026-02-10*
