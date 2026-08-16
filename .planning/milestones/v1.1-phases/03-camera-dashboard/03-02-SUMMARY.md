---
phase: 03-camera-dashboard
plan: 02
subsystem: ui
tags: [home-assistant, frigate, lovelace, advanced-camera-card, verification, dashboard]

# Dependency graph
requires:
  - plan: 03-01
    provides: "Cameras dashboard with advanced-camera-card, detection controls, event gallery"
provides:
  - "Verified working camera dashboard on desktop"
  - "Lovelace resource registration fix for storage mode"
  - "HA auto-restart on dashboard config changes"
  - "Stationary object detection to prevent duplicate events"
  - "Persistent notifications in HA Notifications tab"
affects: []

# Tech tracking
tech-stack:
  added: [persistent_notification]
  patterns: [lovelace-resources-storage-mode, restartTriggers, stationary-detection]

key-files:
  created: []
  modified: [modules/automation/home-assistant.nix, modules/automation/frigate.nix]

key-decisions:
  - "Lovelace resources in storage mode: create .storage/lovelace_resources declaratively via tmpfiles C+"
  - "restartTriggers (not reloadTriggers) for HA — YAML dashboards only read at startup"
  - "Vertically stacked camera feeds instead of 3-column grid"
  - "Controls merged into Events tab (timeline + detection/motion toggles)"
  - "Notification tap opens /lovelace-cameras/events (deep-link to specific clip not supported by card)"
  - "Frigate stationary detection: threshold=300 frames (5min), interval=432000 frames (24hr)"
  - "persistent_notification.create for HA Notifications tab alongside mobile push"

patterns-established:
  - "Declarative lovelace_resources for storage mode via tmpfiles C+ rule"
  - "restartTriggers on Nix store paths for auto-restart on config changes"

# Metrics
duration: 45min
completed: 2026-02-10
---

# Phase 3 Plan 2: Dashboard Verification Summary

**Verified camera dashboard end-to-end, fixed multiple issues discovered during testing, added stationary detection and persistent notifications**

## Performance

- **Duration:** ~45 min (iterative fix cycle with user)
- **Completed:** 2026-02-10
- **Tasks:** 2 (Task 1: auto fixes, Task 2: user verification checkpoint)
- **Files modified:** 2

## Accomplishments
- Fixed Lovelace resource loading in storage mode (card was showing "Custom element doesn't exist")
- Fixed dashboard URL path (HA requires hyphen in dashboard key)
- Fixed card type from `custom:frigate-card` to `custom:advanced-camera-card` (v7.0.0+ rename)
- Changed layout from 3-column grid to vertical stack for better visibility
- Merged Controls into Events tab (timeline + detection/motion toggles)
- Added HA auto-restart via restartTriggers when dashboard config changes
- Added Frigate stationary object detection to prevent duplicate events from parked cars
- Added persistent notifications in HA Notifications tab
- Simplified notification tap URL to open events tab in HA

## Task Commits

1. **fix(03-02): fix dashboard URL path and card type** - `35d9ef1`
2. **fix(03): lovelace resource registration, dashboard layout, auto-restart** - `37a008a`
3. **fix(03): stationary detection, persistent notifications, notification tap URL** - `544650f`

## Files Modified
- `modules/automation/home-assistant.nix` — Lovelace resource registration, layout changes, restartTriggers, persistent notifications, notification URL
- `modules/automation/frigate.nix` — Stationary object detection config

## Issues Encountered
- `customLovelaceModules` auto-registration only works with `lovelace.mode = "yaml"` — NixOS HA module docs confirm this. Fixed by creating `.storage/lovelace_resources` declaratively.
- HA dashboard URL paths require a hyphen — `cameras` rejected, `lovelace-cameras` works.
- Card type renamed in v7.0.0: `custom:frigate-card` → `custom:advanced-camera-card`.
- `reloadTriggers` insufficient for YAML dashboard changes — HA only reads YAML dashboards at startup. Changed to `restartTriggers`.
- Frigate `detect.stationary.interval` must be > 0 (validation error on `interval = 0`).
- Advanced-camera-card does not support deep-linking to specific clip by event ID (open feature requests #1246, #2138).

## User Verification
- User approved dashboard functionality on desktop
- Live camera feeds working
- Events timeline with detection history
- Detection and motion controls with master toggles

## Self-Check: PASSED

- VERIFIED: Dashboard accessible at /lovelace-cameras/
- VERIFIED: Live Cameras tab shows 3 camera feeds
- VERIFIED: Events tab shows timeline + detection controls
- VERIFIED: Frigate running with stationary detection config
- VERIFIED: HA persistent notifications configured

---
*Phase: 03-camera-dashboard*
*Completed: 2026-02-10*
