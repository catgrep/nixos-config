---
phase: 02-push-notifications
plan: 02
subsystem: automation
tags: [home-assistant, frigate, mqtt, push-notifications, verification]

# Dependency graph
requires:
  - phase: 02-push-notifications
    provides: Frigate alert notification automation deployed to ser8
provides:
  - End-to-end verified notification pipeline from Frigate detection to phone push notification
affects: [03-camera-dashboard]

# Tech tracking
tech-stack:
  added: []
  patterns: [trigger.payload | from_json instead of trigger.payload_json for HA 2025.5+]

key-files:
  created: []
  modified:
    - modules/automation/home-assistant.nix

key-decisions:
  - "Fixed trigger.payload_json -> trigger.payload | from_json for HA 2025.5.x compatibility"
  - "Used variables step to parse MQTT payload once and reuse in action templates"

patterns-established:
  - "HA 2025.5+ MQTT automations: use trigger.payload | from_json, NOT trigger.payload_json"
  - "Test notifications via: Developer Tools -> Actions -> YAML mode -> message: 'Test from HA'"

# Metrics
duration: 20min
completed: 2026-02-10
---

# Plan 02-02: End-to-End Notification Verification Summary

**Verified person detection push notifications with snapshots, in-place dedup, and tap-to-open-clip on all cameras**

## Performance

- **Duration:** 20 min
- **Completed:** 2026-02-10
- **Tasks:** 2
- **Files modified:** 1

## Accomplishments
- Fixed HA 2025.5.x template bug: trigger.payload_json replaced with trigger.payload | from_json
- Manual test notification delivered successfully to iPhone via Companion app
- Real Frigate person detection triggered push notification with snapshot image
- Notification deduplication confirmed (in-place updates, no duplicates)
- Tap-to-open-clip action verified

## Task Commits

Each task was committed atomically:

1. **Task 1: Verify automation active + fix template bug** - `58d9dcc` (fix)
2. **Task 2: End-to-end verification** - checkpoint (user physical verification)
3. **Docs: Add test instructions** - `a382623` (docs)

## Files Created/Modified
- `modules/automation/home-assistant.nix` - Fixed trigger.payload_json to trigger.payload | from_json, added test instructions

## Decisions Made
- Replaced all `trigger.payload_json` references with `trigger.payload | from_json` for HA 2025.5.x compatibility
- Added `variables` step in automation action to parse MQTT payload once and reuse via `review` variable
- Documented notification test procedure in module comments

## Deviations from Plan

### Auto-fixed Issues

**1. [Bug] trigger.payload_json UndefinedError in HA 2025.5.x**
- **Found during:** Task 1 (automation verification)
- **Issue:** HA logs showed `UndefinedError: 'dict object' has no attribute 'payload_json'` — MQTT trigger in HA 2025.5.x does not expose `payload_json` in action template context
- **Fix:** Replaced all `trigger.payload_json` with `trigger.payload | from_json` in conditions; added `variables` step in actions to parse once
- **Files modified:** modules/automation/home-assistant.nix
- **Verification:** Deployed, no automation errors in HA logs, notifications delivered successfully
- **Committed in:** 58d9dcc

---

**Total deviations:** 1 auto-fixed (blocking template bug)
**Impact on plan:** Essential fix for HA version compatibility. No scope creep.

## Issues Encountered
- Developer Tools Actions UI in HA 2024+ mangles service call format — use YAML mode with just `message:` field for testing
- `make switch-ser8` requires interactive confirmation — pipe "y" to stdin

## User Setup Required
None — Companion app was set up in plan 02-01.

## Next Phase Readiness
- Full notification pipeline verified end-to-end
- Phase 2 complete — ready for Phase 3 (Camera Dashboard)

---
*Phase: 02-push-notifications*
*Completed: 2026-02-10*
