# Milestones

## v1.0: Frigate–Home Assistant Integration

**Completed:** 2026-02-10
**Phases:** 3 (numbered 01–03)
**Plans executed:** 6
**Total execution time:** ~107min

### What Shipped

**Phase 01 — MQTT Integration & Service Dependencies**
- Frigate entities auto-discovered in HA via MQTT
- Service ordering: HA wants Frigate, Frigate requires Mosquitto
- MQTT broker configured (localhost-only, no auth)

**Phase 02 — Push Notification Automations**
- Person/car/package detection → push notification with snapshot
- Stationary object filtering (5min threshold)
- mobile_app integration with Companion app
- Persistent HA notifications alongside mobile push

**Phase 03 — Camera Dashboard**
- Live camera feeds via advanced-camera-card (Lovelace)
- Detection event history with thumbnails
- Camera controls (enable/disable detection per camera)
- Dashboard deployed via tmpfiles symlink from Nix store

### Key Learnings

- HA 2025.5+: use `trigger.payload | from_json`, NOT `trigger.payload_json`
- Dashboard content as Nix attrset → JSON via `builtins.toJSON` (JSON is valid YAML)
- `restartTriggers` needed for HA YAML dashboard changes (read at startup only)
- Two config entries (MQTT broker, Frigate integration) require one-time HA UI setup
- `customLovelaceModules` auto-registration only works with `lovelace.mode = "yaml"`
- Storage mode requires declarative `.storage/lovelace_resources` via tmpfiles `C+`

### Validated Requirements

All 9 active requirements from v1.0 shipped and confirmed working.
