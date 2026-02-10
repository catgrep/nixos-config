# Feature Landscape: Frigate-Home Assistant Integration

**Domain:** NVR-to-Home Automation Integration (NixOS, declarative)
**Researched:** 2026-02-09
**Context:** Frigate 0.15.2 with 3 active cameras (driveway, front_door, garage), MQTT broker running, Home Assistant with mqtt and mobile_app components. All integration via nixpkgs `customComponents` and declarative HA configuration. No HACS.

## Table Stakes

Features users expect. Missing = the integration feels broken or pointless.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Frigate entities in HA (cameras, sensors, switches) | Core purpose of the integration. Without entities, HA and Frigate are disconnected systems. The `frigate` custom component creates camera entities, binary sensors for motion/occupancy, switches for detect/record/snapshot toggles, and performance sensors. | Low | Provided by `home-assistant-custom-components.frigate` via nixpkgs `customComponents`. Config entry created once via UI (Settings -> Integrations -> Add Frigate -> URL: http://localhost:5000). |
| MQTT connectivity between Frigate and HA | Foundation for all entity creation and automation. Frigate publishes events/state to MQTT, HA subscribes. | Low | Mosquitto already running. MQTT integration config entry created once via UI (broker: localhost, port: 1883). Persists in `/var/lib/hass/.storage/`. |
| Push notifications on person detection | Primary motivation for this milestone. Detection without notification is useless for security. | Medium | MQTT automation triggers on `frigate/reviews` topic. Uses `notify.mobile_app_<device>` service with snapshot attachment via Frigate's `/api/frigate/notifications/<event_id>/thumbnail.jpg` endpoint. |
| Snapshot in notifications | A text-only "person detected" alert has low value. Users expect to see what was detected. | Low | The frigate-hass-integration provides `/api/frigate/notifications/<event_id>/thumbnail.jpg` and `/snapshot.jpg` endpoints accessible through HA's proxy. Mobile App supports `image` in notification data. |
| Per-camera identification | Users need to know WHERE the detection happened (driveway vs front door vs garage). | Low | Camera name is in the MQTT payload. Template it into notification title/message. |
| Detection toggle switches | Users need to disable detection from HA without opening Frigate UI (e.g., during yard work). | Low | Provided automatically by the Frigate integration: `switch.<camera>_detect`, `switch.<camera>_recordings`, `switch.<camera>_snapshots`. |
| Notification cooldown/deduplication | Without cooldown, a lingering person generates notification spam from repeated Frigate review updates. | Medium | Use `frigate/reviews` topic with `type: new` filter (ignore `update`/`end`). Set notification `tag` to review ID so updates replace rather than duplicate. |

## Differentiators

Features that elevate the setup beyond "works" to "polished." Not expected, but highly valued.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Camera dashboard with live feeds | Visual monitoring from HA alongside other home controls. Single-pane security view. | Medium | Use `advanced-camera-card` Lovelace module (available in nixpkgs as `customLovelaceModules`). Provides live view, event timeline, clip browsing, WebRTC support. |
| Zone-aware notifications | "Person at front porch" vs "Person detected." Reduces alert fatigue by filtering to relevant areas (e.g., ignore street traffic on driveway camera). | Medium | Requires defining zones in Frigate config per camera. MQTT payload includes zone data in `after.data.zones`. Automation condition filters by zone. |
| Severity-based filtering | Frigate 0.14+ has "alert" (person, package) and "detection" (car, animal) severity levels. Only alert-level events push notifications; detections log silently. | Low | Built into `frigate/reviews` topic. Filter on `after.severity == "alert"`. Already the recommended trigger approach. |
| Actionable notification buttons | Tap to view live feed, view clip, or silence alerts for 30 minutes. Makes notifications interactive. | Medium | iOS and Android companion apps support `actions` in notification data. Requires Frigate URL accessible from phone (via Tailscale). |
| Updating notifications (progressive refinement) | As Frigate finds a better snapshot, the notification updates in-place with higher quality image. | Medium | Set `tag` field in notify call to `frigate-<event_id>`. Trigger on both `new` and `update` event types. Same-tag notifications replace the previous one. |
| Quiet hours / Do Not Disturb | Suppress notifications during sleep or when household is present. | Low | HA time condition in automation (`before: "07:00"`, `after: "22:00"`). Or combine with HA presence detection. |
| Per-camera notification scheduling | Different rules per camera and time: driveway only at night, front door always, garage only when away. | Low | Separate automation per camera with distinct conditions. Fully declarative in Nix. |
| Clip/event history in dashboard | Review past detections without opening Frigate directly. | Medium | `advanced-camera-card` provides mini-gallery and event browsing. The Frigate integration also adds media browser support. |
| Birdseye overview in dashboard | Single combined view of all cameras with activity highlighting. | Low | Frigate's birdseye stream available at `rtsp://localhost:8554/birdseye`. Can add as camera entity in HA. |

## Anti-Features

Features to explicitly NOT build. These add complexity without proportional value, or conflict with the declarative NixOS approach.

| Anti-Feature | Why Avoid | What to Do Instead |
|--------------|-----------|-------------------|
| HACS for any component | Imperative, not reproducible, downloads from GitHub at runtime, breaks NixOS declarative philosophy. | Use `customComponents` and `customLovelaceModules` in nixpkgs. Both `frigate` integration and `advanced-camera-card` are packaged. |
| LLM/AI verification of detections | Adds latency, cloud dependency, cost, complexity. Experimental. | Tune Frigate's detection thresholds (already 0.7 for person), use zones, use severity filtering. |
| Facial recognition notifications | Privacy concern, high false-positive rate, experimental in Frigate. | Stick to object-type detection (person, car, package). |
| Multi-camera person re-identification | Frigate 0.16+ feature. High CPU cost, complexity for 3 cameras. | Treat each camera independently. Zone filtering is sufficient. |
| Node-RED flows | Over-engineering for MQTT-trigger-to-notification patterns. Adds another service to maintain. | HA automations declared in Nix. |
| External notification services (Pushover, Telegram) | Adds external dependencies and accounts when HA Mobile App already works. | Use `notify.mobile_app_<device>`. |
| Email notifications for detections | Too slow for security alerts, poor image display, requires SMTP. | Push notifications only. |
| Two-way audio through HA | Requires specific camera support, WebRTC backchannel, high complexity. | Use camera's native app or Frigate UI directly when needed. |
| Recording management from HA | Frigate handles retention natively. Duplicating adds complexity with no benefit. | Let Frigate manage recordings. View from Frigate UI or advanced-camera-card. |
| Complex blueprint automations | HA Blueprints are UI-imported, opaque, harder to version-control in NixOS. | Write explicit automations in `services.home-assistant.config`. Use blueprints as reference only. |

## Feature Dependencies

```
Frigate custom component installed (customComponents)
  + MQTT config entry (UI, one-time)
  + Frigate config entry (UI, one-time)
  |
  |--> Camera entities created automatically
  |--> Binary sensors (motion/occupancy) created
  |--> Switch entities (detect/record/snapshot) created
  |--> Performance sensor entities created
  |--> /api/frigate/notifications/* endpoints available
  |
  |--> Notification automations can reference entities
  |     |--> MQTT trigger on frigate/reviews
  |     |--> Snapshot attachment via /api/frigate/ endpoint
  |     |--> Per-camera, per-object filtering
  |     |--> Cooldown via notification tags
  |     |--> Zone-aware filtering (requires Frigate zone config)
  |     |--> Quiet hours (HA time conditions)
  |     |--> Actionable buttons (requires Tailscale URL access)
  |
  |--> Dashboard (HA UI configuration)
        |--> Live camera views (via integration camera entities)
        |--> advanced-camera-card (customLovelaceModules)
        |     |--> Event timeline
        |     |--> Clip browsing
        |     |--> WebRTC live view
        |--> Entity cards (detection counts, motion state)
        |--> Switch cards (toggle detection/recording)

Mobile App device registration (phone setup)
  |--> notify.mobile_app_<device> service available
  |--> Push notifications work
  |--> Actionable notification callbacks work
```

## MVP Recommendation

Build in this order, each layer building on the previous:

### Phase 1: Integration Foundation (must ship)
1. **Frigate custom component** -- Add `home-assistant-custom-components.frigate` to `customComponents` in Nix config, deploy.
2. **MQTT config entry** -- One-time UI setup: Settings -> Integrations -> Add MQTT -> localhost:1883, no auth.
3. **Frigate config entry** -- One-time UI setup: Settings -> Integrations -> Add Frigate -> http://localhost:5000.
4. **Verify entities** -- Confirm camera entities, motion binary sensors, and detection switches appear in HA.

### Phase 2: Notifications (primary goal)
5. **Person detection notification** -- Declarative automation in Nix triggering on `frigate/reviews`, filtering for `severity: alert` + `person` in objects, pushing to mobile_app with snapshot thumbnail.
6. **Notification deduplication** -- Use `tag` field set to review ID to prevent spam.
7. **Multi-object notifications** -- Add car and package detection automations (may be same automation with object-type in message).

### Phase 3: Dashboard (polish)
8. **advanced-camera-card** -- Add to `customLovelaceModules` if available on nixos-25.05 channel. Configure via HA UI.
9. **Camera dashboard** -- Build Lovelace dashboard with camera cards for each camera plus detection state cards.

### Defer to Later
- **Zone configuration** -- Requires per-camera zone definition in Frigate config (separate Nix change).
- **Actionable notifications** -- Nice to have, requires Tailscale URL configuration.
- **Quiet hours** -- Low complexity but lower priority than core notifications.
- **Birdseye view** -- Easy but not essential.

### Defer Indefinitely
- HACS anything, LLM verification, facial recognition, person re-ID, Node-RED, two-way audio.

## Sources

- [Frigate Home Assistant Integration Docs](https://docs.frigate.video/integrations/home-assistant/) -- HIGH confidence, official docs
- [Frigate MQTT Documentation](https://docs.frigate.video/integrations/mqtt/) -- HIGH confidence, official docs
- [Frigate HA Notification Guide](https://docs.frigate.video/guides/ha_notifications/) -- HIGH confidence, official docs
- [frigate-hass-integration GitHub](https://github.com/blakeblackshear/frigate-hass-integration) -- HIGH confidence, official repo
- [NixOS Wiki: Home Assistant](https://wiki.nixos.org/wiki/Home_Assistant) -- HIGH confidence, customComponents docs
- [nixpkgs PR #371866](https://github.com/NixOS/nixpkgs/pull/371866) -- Frigate component 5.3.0 -> 5.6.0
- [advanced-camera-card GitHub](https://github.com/dermotduffy/advanced-camera-card) -- HIGH confidence, renamed from frigate-hass-card
- [SgtBatten HA Blueprints](https://github.com/SgtBatten/HA_blueprints) -- Reference for notification automation patterns
