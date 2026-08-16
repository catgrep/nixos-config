# Phase 2: Push Notifications - Research

**Researched:** 2026-02-09
**Domain:** Home Assistant push notifications with Frigate NVR snapshots on NixOS
**Confidence:** HIGH

## Summary

Phase 2 declares HA automations in Nix that trigger on Frigate detection events and send push notifications with snapshot images to the HA Companion app. The implementation uses the `frigate/reviews` MQTT topic (introduced in Frigate 0.14) as the trigger source, the Companion app's `notify.mobile_app_<device_id>` service for delivery, and the Frigate custom component's `/api/frigate/notifications/` proxy endpoint for snapshot images.

The core technical challenge is translating HA automation YAML (with Jinja2 templates) into Nix attribute sets within `services.home-assistant.config."automation manual"`. Jinja2 `{{ }}` syntax passes through Nix's YAML generator as plain strings without conflict since Nix uses `${ }` for interpolation. The `frigate/reviews` MQTT topic provides a `before`/`after` change feed with severity levels (`alert` vs `detection`), camera names, detected object types, zone names, and detection event IDs -- all accessible via `trigger.payload_json` in Jinja2 templates.

Notification deduplication uses the Companion app's `tag` field: notifications with the same tag replace each other in-place. By setting `tag` to the review ID, repeated updates for the same Frigate review event update the existing notification rather than creating duplicates. Actionable notifications use `url` (iOS) and `clickAction` (Android) to open the Frigate event clip or dashboard when tapped. One prerequisite not automatable via Nix: the HA Companion app must be installed on the phone and connected to HA (via the Tailscale URL) before notifications can be received.

**Primary recommendation:** Declare 1-2 automations in `"automation manual"` that trigger on `frigate/reviews` MQTT with `alert` severity, send `notify.mobile_app_<device_id>` with snapshot image and tag for deduplication, and include actionable tap-to-open-clip behavior.

## Standard Stack

### Core

| Component | Version | Purpose | Why Standard |
|-----------|---------|---------|--------------|
| `services.home-assistant.config."automation manual"` | NixOS module | Declare automations in Nix that generate HA `configuration.yaml` | Only declarative path for HA automations on NixOS. Already set up in Phase 1. |
| HA Companion App (iOS/Android) | Latest | Receives push notifications via `notify.mobile_app_<device_id>` | Standard HA mobile notification path. `mobile_app` component already in `extraComponents`. |
| `frigate/reviews` MQTT topic | Frigate 0.14+ (0.15.2 deployed) | Aggregated detection events with severity, objects, zones | Recommended trigger source per Frigate docs. Aggregates detections into review items. |
| `/api/frigate/notifications/` proxy | frigate-hass-integration 5.9.2 | Serves snapshot/thumbnail/clip images through HA | Custom component creates these endpoints. Handles auth. No need to expose Frigate directly. |

### Supporting

| Component | Version | Purpose | When to Use |
|-----------|---------|---------|-------------|
| Mosquitto CLI | System package | Debug MQTT messages with `mosquitto_sub` | Troubleshooting trigger issues |
| HA Developer Tools | Built-in | Test automation triggers and notification payloads | Verifying automation fires correctly |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `frigate/reviews` trigger | `frigate/events` trigger | Events are per-tracked-object (noisier). Reviews aggregate detections into incidents with severity levels. Reviews are the recommended modern path. |
| Custom automation YAML | Frigate Notification Blueprint | Blueprints are UI-only, not declarative, and cannot be declared in Nix. They conflict with the "all automations in Nix" requirement. |
| `notify.mobile_app_<device>` | `notify.notify` (all devices) | Per-device targeting is more explicit and works reliably. `notify.notify` broadcasts to all registered devices. |

### Installation

No new packages needed. All components are already deployed from Phase 1:
- `mobile_app` in `extraComponents` (provides `notify.mobile_app_*` services)
- `mqtt` in `extraComponents` (provides MQTT trigger platform)
- `automation` in `extraComponents` (provides automation engine)
- Frigate custom component installed (provides `/api/frigate/notifications/` endpoints)
- `"automation manual"` split already configured

The only change is adding automation entries to the existing `"automation manual" = [ ];` list.

## Architecture Patterns

### Recommended File Structure Changes

```
modules/automation/
  home-assistant.nix     # ADD: automation entries to "automation manual" list
  frigate.nix            # NO CHANGES (already complete from Phase 1)
  default.nix            # NO CHANGES
```

### Pattern 1: Frigate Reviews MQTT Trigger in Nix

**What:** Trigger an automation when Frigate publishes an alert-severity review to `frigate/reviews`.
**When to use:** All Frigate notification automations.
**Example:**
```nix
# Source: https://docs.frigate.video/guides/ha_notifications/
# Nix attribute set that generates HA automation YAML
{
  alias = "Frigate Alert Notification";
  description = "Send push notification with snapshot on Frigate alert detection";
  mode = "parallel";
  max = 10;
  trigger = [
    {
      platform = "mqtt";
      topic = "frigate/reviews";
      payload = "alert";
      value_template = "{{ value_json['after']['severity'] }}";
    }
  ];
  # conditions and actions follow...
}
```

**Critical Nix/Jinja2 note:** Jinja2 `{{ }}` in Nix strings pass through to YAML as-is. Nix uses `${ }` for interpolation, so there is no conflict. Simply write Jinja2 templates as plain Nix strings.

### Pattern 2: Notification with Snapshot Image and Tag

**What:** Send a push notification with Frigate snapshot attached, using `tag` for deduplication.
**When to use:** The action block of every Frigate notification automation.
**Example:**
```nix
# Source: https://docs.frigate.video/guides/ha_notifications/
# https://companion.home-assistant.io/docs/notifications/notifications-basic/
action = [
  {
    # Use the service key format for HA 2024.x+
    action = "notify.mobile_app_<device_id>";
    data = {
      title = "{{ trigger.payload_json['after']['data']['objects'] | sort | join(', ') | title }} Detected";
      message = "{{ trigger.payload_json['after']['camera'] | replace('_', ' ') | title }}";
      data = {
        # Snapshot from Frigate via HA proxy (uses detection event ID, NOT review ID)
        image = "/api/frigate/notifications/{{ trigger.payload_json['after']['data']['detections'][0] }}/snapshot.jpg";
        # Tag for deduplication: same review ID replaces existing notification
        tag = "{{ trigger.payload_json['after']['id'] }}";
        # Timestamp for notification ordering
        when = "{{ trigger.payload_json['after']['start_time'] | int }}";
        # iOS: camera entity for live preview
        entity_id = "camera.{{ trigger.payload_json['after']['camera'] | replace('-','_') | lower }}";
        # Tap action: open clip (works on both iOS and Android)
        url = "/api/frigate/notifications/{{ trigger.payload_json['after']['data']['detections'][0] }}/clip.mp4";
        clickAction = "/api/frigate/notifications/{{ trigger.payload_json['after']['data']['detections'][0] }}/clip.mp4";
      };
    };
  }
];
```

**Key details:**
- `image`: Use `/api/frigate/notifications/{event_id}/snapshot.jpg` (relative path). The companion app handles auth and base URL resolution.
- `tag`: Set to `trigger.payload_json['after']['id']` (the review ID). All updates to the same review replace the notification in-place.
- `url`/`clickAction`: Both set so tapping works on iOS (`url`) and Android (`clickAction`).
- Detection event ID (`data.detections[0]`) is used for snapshots/clips, NOT the review ID. Using the review ID returns 404.

### Pattern 3: Filtering by Object Type or Camera

**What:** Use conditions to restrict which detections trigger notifications.
**When to use:** When you want person/car/package notifications but not dog/cat.
**Example:**
```nix
# Source: https://github.com/blakeblackshear/frigate/discussions/11554
condition = [
  {
    condition = "template";
    value_template = "{{ trigger.payload_json['after']['data']['objects'] | select('in', ['person', 'car', 'package']) | list | length > 0 }}";
  }
];
```

Or filter by camera:
```nix
condition = [
  {
    condition = "template";
    value_template = "{{ trigger.payload_json['after']['camera'] in ['driveway', 'front_door', 'garage'] }}";
  }
];
```

### Pattern 4: Actionable Notification Buttons

**What:** Add action buttons to notifications (e.g., "View Clip", "Dismiss").
**When to use:** NOTF-05 requirement for actionable notifications.
**Example:**
```nix
# Source: https://companion.home-assistant.io/docs/notifications/actionable-notifications/
data = {
  actions = [
    {
      action = "URI";
      title = "View Clip";
      uri = "/api/frigate/notifications/{{ trigger.payload_json['after']['data']['detections'][0] }}/clip.mp4";
    }
    {
      action = "URI";
      title = "View in Frigate";
      uri = "/lovelace/0";  # Or Frigate dashboard path if available
    }
  ];
};
```

### Pattern 5: Single vs Multiple Automations

**What:** Whether to use one automation for all object types or separate automations per type.
**When to use:** Design decision for NOTF-01/02/03.
**Recommendation:** Use a single automation with a condition that filters for person, car, and package. This is simpler, deduplicates code, and the notification message already includes the object type via the Jinja2 template. Separate automations only add value if different object types need different notification behavior (e.g., critical vs normal priority).

```nix
# ONE automation handles all three object types
"automation manual" = [
  {
    alias = "Frigate Detection Alert";
    trigger = [ { platform = "mqtt"; topic = "frigate/reviews"; payload = "alert"; value_template = "{{ value_json['after']['severity'] }}"; } ];
    condition = [
      { condition = "template"; value_template = "{{ trigger.payload_json['after']['data']['objects'] | select('in', ['person', 'car', 'package']) | list | length > 0 }}"; }
    ];
    action = [ /* notification action */ ];
    mode = "parallel";
    max = 10;
  }
];
```

### Anti-Patterns to Avoid

- **Using review ID for snapshot URL:** The `/api/frigate/notifications/{id}/snapshot.jpg` endpoint requires a detection event ID from `data.detections[0]`, NOT the review ID from `after.id`. Using the review ID returns HTTP 404.
- **Using `frigate/events` instead of `frigate/reviews`:** Events are per-tracked-object and much noisier. Reviews aggregate detections into review items with severity levels.
- **Declaring automations in HA UI only:** This conflicts with the NOTF-06 requirement. All automations must be in `"automation manual"` in Nix.
- **Using Blueprints:** Blueprints are UI-only artifacts stored in `.storage/`. They cannot be declared in Nix and would not survive configuration regeneration.
- **Hardcoding the HA base URL in image paths:** Use relative paths like `/api/frigate/notifications/...`. The companion app resolves them automatically. Hardcoding breaks when accessing via different URLs (Tailscale vs local).
- **Filtering on `type = "new"` only:** This would miss updated snapshots. The `frigate/reviews` topic sends `new`, `update`, and `end` messages. By triggering on all types (and using the `tag` for deduplication), the notification image updates as Frigate finds a better snapshot.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Snapshot delivery to phone | Custom webhook/script to push images | `notify.mobile_app_*` with `image` data field | Companion app handles auth, image download, rich notifications. Custom solutions miss platform-specific features. |
| Notification deduplication | Custom state tracking for "already notified" events | Companion app `tag` field | Setting `tag` to review ID makes the OS replace notifications automatically. Zero state management needed. |
| Frigate snapshot proxy | Exposing Frigate directly to internet for snapshot URLs | `/api/frigate/notifications/` proxy endpoint | The custom component already proxies with auth. No need to open Frigate ports externally. |
| Object type filtering | Separate automations per object type | Single automation with Jinja2 `select('in', [...])` condition | Less code, same result. Object type is in the notification message template. |

**Key insight:** The combination of the Frigate custom component's proxy endpoints and the Companion app's notification features means the automation itself is just glue code -- a trigger, a filter, and a notification service call. No custom infrastructure needed.

## Common Pitfalls

### Pitfall 1: Using Review ID Instead of Detection Event ID for Snapshots

**What goes wrong:** Notification shows no image or logs show HTTP 404 for the snapshot URL.
**Why it happens:** The `trigger.payload_json['after']['id']` is the review ID. The `/api/frigate/notifications/` endpoint expects a detection event ID from `trigger.payload_json['after']['data']['detections'][0]`.
**How to avoid:** Always use `data.detections[0]` for snapshot/thumbnail/clip URLs. Use `after.id` only for the notification `tag` (deduplication).
**Warning signs:** HTTP 404 errors in HA logs for `/api/frigate/notifications/` URLs.

**Confidence:** HIGH -- [Frigate Discussion #15972](https://github.com/blakeblackshear/frigate/discussions/15972)

### Pitfall 2: Companion App Not Registered

**What goes wrong:** Automation fires (visible in HA trace) but no notification arrives on phone.
**Why it happens:** The `notify.mobile_app_<device_id>` service only exists after the Companion app is installed, configured with the HA URL, and HA is restarted. If the app is not set up, the service does not exist and the action fails silently or logs an error.
**How to avoid:** Install Companion app, connect to HA via Tailscale URL (`https://hass.shad-bangus.ts.net`), grant notification permissions, then restart HA. Verify the service exists in Developer Tools > Services.
**Warning signs:** `notify.mobile_app_*` service not found in Developer Tools > Services. HA log shows "service not found" error.

**Confidence:** HIGH -- [Companion App Docs](https://companion.home-assistant.io/docs/notifications/notifications-basic/)

### Pitfall 3: Device ID Mismatch

**What goes wrong:** Automation YAML references `notify.mobile_app_iphone` but the actual service is `notify.mobile_app_bobbys_iphone` (or similar).
**Why it happens:** The device ID is derived from the device name in the Companion app settings, with spaces replaced by underscores and converted to lowercase. It is not predictable without checking.
**How to avoid:** After Companion app setup, check Developer Tools > Services for the exact `notify.mobile_app_*` service name. Use that exact name in the Nix config.
**Warning signs:** HA log shows service not found for the notify action.

**Confidence:** HIGH -- [Companion App Docs](https://companion.home-assistant.io/docs/notifications/notifications-basic/)

### Pitfall 4: Empty Detections Array

**What goes wrong:** Automation crashes with template error when accessing `detections[0]` on a review that has no detections yet.
**Why it happens:** The `frigate/reviews` topic may publish a `new` message before any detection event IDs are populated in the `data.detections` array.
**How to avoid:** Add a condition that checks `trigger.payload_json['after']['data']['detections'] | length > 0` before accessing `detections[0]`.
**Warning signs:** Template error in HA automation trace. Notification not sent.

**Confidence:** MEDIUM -- inferred from payload structure; the `new` message should have at least one detection, but defensive coding is prudent.

### Pitfall 5: Nix Rebuild Overwrites Manual Automation Changes

**What goes wrong:** Automations tweaked via HA UI in `configuration.yaml` revert after `make switch-ser8`.
**Why it happens:** NixOS regenerates `configuration.yaml` from `services.home-assistant.config` on every activation. The `"automation manual"` list is fully owned by Nix.
**How to avoid:** Only edit automations in the Nix config. Use `"automation ui"` for any quick experiments via the HA UI, then port successful experiments back to Nix.
**Warning signs:** Automations revert to previous state after deployment.

**Confidence:** HIGH -- documented behavior of NixOS HA module.

### Pitfall 6: Notification Flood During High Activity

**What goes wrong:** Dozens of notifications in rapid succession when multiple cameras detect activity simultaneously (e.g., delivery person walks from driveway to front door).
**Why it happens:** Each camera generates separate review events. The automation fires for each one independently.
**How to avoid:** The `tag` field helps by updating in-place per review. For cross-camera deduplication, consider adding a `cooldown` condition using `this.attributes.last_triggered` or use `mode: single` with a brief wait. However, for Phase 2, per-camera notifications with tag-based dedup is the correct baseline. Cross-camera dedup can be added later if noise is a problem.
**Warning signs:** Multiple simultaneous notifications from different cameras for the same person/event.

**Confidence:** MEDIUM -- depends on real-world usage patterns.

## Code Examples

Verified patterns from official sources:

### Complete Notification Automation in Nix

```nix
# modules/automation/home-assistant.nix
# Source: https://docs.frigate.video/guides/ha_notifications/
# Source: https://companion.home-assistant.io/docs/notifications/notifications-basic/
# Source: https://github.com/blakeblackshear/frigate/discussions/11554

services.home-assistant.config = {
  # Nix-declared automations (populated for Phase 2)
  "automation manual" = [
    {
      alias = "Frigate Alert Notification";
      description = "Send push notification with snapshot when Frigate detects person/car/package";
      mode = "parallel";
      max = 10;
      trigger = [
        {
          platform = "mqtt";
          topic = "frigate/reviews";
          payload = "alert";
          value_template = "{{ value_json['after']['severity'] }}";
        }
      ];
      condition = [
        # Only notify for person, car, package (not dog, cat)
        {
          condition = "template";
          value_template = "{{ trigger.payload_json['after']['data']['objects'] | select('in', ['person', 'car', 'package']) | list | length > 0 }}";
        }
        # Ensure detections array is not empty
        {
          condition = "template";
          value_template = "{{ trigger.payload_json['after']['data']['detections'] | length > 0 }}";
        }
      ];
      action = [
        {
          action = "notify.mobile_app_<DEVICE_ID>";  # Replace with actual device ID
          data = {
            title = "{{ trigger.payload_json['after']['data']['objects'] | sort | join(', ') | title }} Detected";
            message = "{{ trigger.payload_json['after']['camera'] | replace('_', ' ') | title }}";
            data = {
              # Snapshot image via Frigate proxy (uses detection event ID)
              image = "/api/frigate/notifications/{{ trigger.payload_json['after']['data']['detections'][0] }}/snapshot.jpg";
              # Tag for deduplication (uses review ID)
              tag = "{{ trigger.payload_json['after']['id'] }}";
              # Timestamp for notification ordering
              when = "{{ trigger.payload_json['after']['start_time'] | int }}";
              # iOS: live camera preview
              entity_id = "camera.{{ trigger.payload_json['after']['camera'] }}";
              # Tap to view clip (iOS)
              url = "/api/frigate/notifications/{{ trigger.payload_json['after']['data']['detections'][0] }}/clip.mp4";
              # Tap to view clip (Android)
              clickAction = "/api/frigate/notifications/{{ trigger.payload_json['after']['data']['detections'][0] }}/clip.mp4";
              # Group notifications by camera
              group = "frigate-{{ trigger.payload_json['after']['camera'] }}";
              # Action buttons
              actions = [
                {
                  action = "URI";
                  title = "View Clip";
                  uri = "/api/frigate/notifications/{{ trigger.payload_json['after']['data']['detections'][0] }}/clip.mp4";
                }
              ];
            };
          };
        }
      ];
    }
  ];

  # UI automations coexist (unchanged from Phase 1)
  "automation ui" = "!include automations.yaml";
};
```

### MQTT Debug Commands

```bash
# Monitor all Frigate review events in real-time
ssh bdhill@ser8 nix-shell -p mosquitto --command "mosquitto_sub -h 127.0.0.1 -t 'frigate/reviews' -v"

# Monitor all Frigate events (more verbose)
ssh bdhill@ser8 nix-shell -p mosquitto --command "mosquitto_sub -h 127.0.0.1 -t 'frigate/events' -v"

# Pretty-print review JSON payloads
ssh bdhill@ser8 nix-shell -p mosquitto jq --command "mosquitto_sub -h 127.0.0.1 -t 'frigate/reviews' | jq ."
```

### Verify Notification Service Exists

After Companion app setup:
```
HA Web UI > Developer Tools > Services > search "notify.mobile_app"
```
The exact service name (e.g., `notify.mobile_app_bobbys_iphone`) will be visible here.

### Test Notification Manually

In HA Developer Tools > Services:
```yaml
action: notify.mobile_app_<device_id>
data:
  title: "Test Notification"
  message: "Frigate notification test"
  data:
    image: "/api/frigate/notifications/<any_valid_event_id>/snapshot.jpg"
    tag: "test-notification"
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `frigate/events` for notifications | `frigate/reviews` for notifications | Frigate 0.14 (late 2024) | Reviews aggregate detections with severity levels. Less noise, better deduplication. |
| `service:` key in HA actions | `action:` key in HA actions | HA 2024.x | Both work, but `action:` is the modern syntax. |
| Separate automations per camera | Single automation with template conditions | Community best practice | Reduces maintenance. Camera name is in the payload. |
| Full URL for notification images | Relative `/api/` paths | Companion app improvements | Companion app handles base URL resolution and auth. |

**Deprecated/outdated:**
- `frigate/events` as notification trigger -- use `frigate/reviews` for aggregated, severity-aware alerts
- Hardcoded base URLs in notification image paths -- use relative `/api/frigate/notifications/` paths
- HA Blueprints for declarative Frigate notifications -- cannot be declared in Nix

## Open Questions

1. **Exact Companion App device ID**
   - What we know: The service will be `notify.mobile_app_<something>` where `<something>` is derived from the device name.
   - What's unclear: The exact device ID string until the Companion app is installed and registered.
   - Recommendation: Install Companion app as first step, check Developer Tools > Services for exact name, then put it in the Nix config. This is a one-time manual step.

2. **Relative vs full URL for notification images**
   - What we know: Official Frigate docs show full URLs (`https://your.public.hass.address.com/api/frigate/...`). The Companion app docs confirm relative paths work for `/media/local/` and `/api/camera_proxy/`. The Blueprint uses relative paths (`/api/frigate/notifications/...`).
   - What's unclear: Whether `/api/frigate/notifications/` relative paths work reliably on both iOS and Android Companion apps.
   - Recommendation: Start with relative paths (simpler, no URL maintenance). If images don't load, fall back to full Tailscale URL. Testing will resolve this quickly.

3. **Notification behavior during `type: end` messages**
   - What we know: `frigate/reviews` publishes `new`, `update`, and `end` messages. The `tag` field causes later messages to update the notification in-place.
   - What's unclear: Whether `end` messages have the same payload structure (specifically `data.detections[0]`).
   - Recommendation: Do not filter on `type`. Let all message types through. The `tag` ensures deduplication. If `end` messages cause issues (e.g., empty detections), add a condition for `detections | length > 0`.

4. **Clip availability at notification time**
   - What we know: Snapshots are available almost immediately. Clips are only available after the event ends (Frigate must finish recording and processing).
   - What's unclear: Whether the `/api/frigate/notifications/{id}/clip.mp4` URL in the tap action will work if the event is still in progress.
   - Recommendation: Use the clip URL anyway. If the event is ongoing when tapped, it may show a partial clip or redirect. The snapshot image in the notification is the primary content; the tap action is secondary.

## Sources

### Primary (HIGH confidence)
- [Frigate HA Notification Guide](https://docs.frigate.video/guides/ha_notifications/) -- Complete automation YAML examples for reviews-based notifications
- [Frigate MQTT Documentation](https://docs.frigate.video/integrations/mqtt/) -- `frigate/reviews` topic payload structure, lifecycle states
- [Frigate HA Integration Docs](https://docs.frigate.video/integrations/home-assistant/) -- `/api/frigate/notifications/` proxy endpoint URLs and formats
- [HA Companion App Basic Notifications](https://companion.home-assistant.io/docs/notifications/notifications-basic/) -- `notify.mobile_app_*` service format, `tag`, `url`/`clickAction`
- [HA Companion App Attachments](https://companion.home-assistant.io/docs/notifications/notification-attachments/) -- Image attachment format, URL requirements
- [HA Companion App Actionable Notifications](https://companion.home-assistant.io/docs/notifications/actionable-notifications/) -- Action buttons, URI actions, event handling
- [NixOS Wiki: Home Assistant](https://wiki.nixos.org/wiki/Home_Assistant) -- `"automation manual"` pattern, Nix attribute set to YAML conversion

### Secondary (MEDIUM confidence)
- [Frigate 0.14 Review Notifications Guide (Discussion #11554)](https://github.com/blakeblackshear/frigate/discussions/11554) -- Complete reviews-based automation YAML with variables and conditions
- [Frigate Discussion #15972 (HTTP 404)](https://github.com/blakeblackshear/frigate/discussions/15972) -- Confirmed review ID vs detection event ID distinction for snapshot URLs
- [Frigate Notification Blueprint Gist](https://gist.github.com/hunterjm/23c1588a9f2b8b9c2a62ffc364e17f8c) -- Reference implementation for tag, group, action buttons
- [ymatsiuk/nixos-config](https://github.com/ymatsiuk/nixos-config/blob/main/homeassistant.nix) -- Real-world NixOS HA automation declarations with templates

### Tertiary (LOW confidence)
- Relative path behavior for `/api/frigate/notifications/` in Companion app -- community usage suggests it works, but not explicitly documented for this specific endpoint
- `end` message payload structure for `frigate/reviews` -- assumed same schema as `new`/`update` but not verified

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- all components already deployed, notification service well-documented
- Architecture patterns: HIGH -- Frigate official docs + companion app docs provide complete examples
- Nix integration: HIGH -- `"automation manual"` pattern verified on NixOS Wiki + community configs; Jinja2 passes through YAML generation
- Pitfalls: HIGH -- review ID vs detection ID confirmed via GitHub discussion; companion app prerequisites documented
- Deduplication: HIGH -- `tag` field documented in companion app docs with explicit replacement behavior

**Research date:** 2026-02-09
**Valid until:** 2026-03-09 (stable domain, 30-day validity)
