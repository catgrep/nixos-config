---
phase: 02-push-notifications
plan: 01
subsystem: automation
tags: [home-assistant, frigate, mqtt, push-notifications, nix]

# Dependency graph
requires:
  - phase: 01-integration-foundation
    provides: Frigate entities, MQTT broker, HA with Frigate custom component
provides:
  - Frigate alert notification automation in HA via Nix
  - mobile_app integration enabled for Companion app push delivery
  - Companion app registered with notify.mobile_app_bobbo_dhillons_iphone service
affects: [02-push-notifications]

# Tech tracking
tech-stack:
  added: [mobile_app HA integration]
  patterns: [HA automation declared in Nix via "automation manual" list]

key-files:
  created: []
  modified:
    - modules/automation/home-assistant.nix

key-decisions:
  - "Added mobile_app = {} to HA config section (extraComponents alone insufficient, config section activates it)"
  - "Used detections[0] for snapshot/clip URLs, review ID only for notification tag dedup"
  - "Notification groups by camera name for clean notification stacking"

patterns-established:
  - "HA automations declared in Nix: add entries to 'automation manual' list in home-assistant.nix"
  - "Companion app device ID hardcoded in Nix config (single-user homelab)"

# Metrics
duration: 15min
completed: 2026-02-10
---

# Plan 02-01: Frigate Alert Notification Summary

**Frigate MQTT-triggered push notification automation with snapshot images, tag-based dedup, and tap-to-open-clip via HA Companion app**

## Performance

- **Duration:** 15 min
- **Completed:** 2026-02-10
- **Tasks:** 3
- **Files modified:** 1

## Accomplishments
- Frigate alert notification automation declared in Nix and deployed to ser8
- MQTT trigger on `frigate/reviews` with alert severity, filtering for person/car/package
- Push notifications with snapshot image, camera name, tag-based dedup, and tap-to-open-clip action
- HA Companion app installed, registered, and receiving notifications
- mobile_app integration enabled in HA config

## Task Commits

Each task was committed atomically:

1. **Task 1: Add Frigate notification automation** - `35ce8fe` (feat)
2. **Task 2: Set up HA Companion App** - checkpoint (user action)
3. **Task 3: Update device ID, deploy, verify** - `5028ad2` (feat)

## Files Created/Modified
- `modules/automation/home-assistant.nix` - Added mobile_app config, Frigate alert notification automation with real device ID

## Decisions Made
- Added `mobile_app = {}` to HA config section -- `extraComponents` makes the Python package available but the integration must also be activated in the config block
- Used `notify.mobile_app_bobbo_dhillons_iphone` as hardcoded target (single-user homelab, no need for dynamic device selection)

## Deviations from Plan

### Auto-fixed Issues

**1. mobile_app component not loaded**
- **Found during:** Task 2 (Companion app setup)
- **Issue:** Companion app reported "The mobile_app component is not loaded" when connecting
- **Fix:** Added `mobile_app = {}` to the HA config section in home-assistant.nix (extraComponents alone wasn't sufficient)
- **Files modified:** modules/automation/home-assistant.nix
- **Verification:** Companion app connected successfully after redeployment
- **Committed in:** 5028ad2

---

**Total deviations:** 1 auto-fixed (blocking integration issue)
**Impact on plan:** Essential fix for Companion app connectivity. No scope creep.

## Issues Encountered
- `make switch-ser8` requires interactive confirmation (piped "y" to stdin as workaround)
- HA Developer Tools "Services" tab renamed to "Actions" in newer HA versions

## User Setup Required
- HA Companion app installed on phone and connected via Tailscale URL
- Notification permissions granted in Companion app

## Next Phase Readiness
- Notification automation is deployed and active (confirmed firing on real Frigate events from HA logs)
- Ready for end-to-end verification in plan 02-02

---
*Phase: 02-push-notifications*
*Completed: 2026-02-10*
