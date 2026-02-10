# Architecture: Frigate-Home Assistant Integration

**Domain:** Home automation NVR integration on NixOS
**Researched:** 2026-02-09
**Confidence:** HIGH (verified against official Frigate docs, nixpkgs, and existing codebase)

## Recommended Architecture

All components run on ser8 (localhost). The integration uses two paths: (1) the `frigate-hass-integration` custom component for automatic entity creation and media proxying, and (2) MQTT for event-driven automations and push notifications. Both paths rely on Mosquitto as the message broker.

```
 TP-Link Tapo Cameras (RTSP)
         |
         v
 +-------------------+       MQTT (localhost:1883)       +--------------------+
 |    Frigate NVR     | -----> Mosquitto Broker ------> | Home Assistant      |
 |   (port 5000)      |                                  |   (port 8123)       |
 |                     |                                  |                     |
 |  - Object detection |  frigate/events (entity updates) |  - Frigate custom   |
 |  - Recording        |  frigate/reviews (notifications) |    component        |
 |  - Snapshots        |  frigate/<cam>/<obj> (counts)    |  - MQTT integration |
 |  - go2rtc (WebRTC)  |  frigate/<cam>/motion            |  - Automations      |
 |                     |  frigate/available                |  - Dashboard        |
 +-------------------+                                  +--------------------+
         |                                                        |
         |  HTTP API (port 5000)                                   |
         +-----> Frigate integration entity updates                |  Push via
                 + /api/frigate/notifications/* proxy               |  mobile_app
                                                                   v
                                                          HA Companion App
                                                           (iOS/Android)
```

### Component Boundaries

| Component | Responsibility | Communicates With | Port | NixOS Config |
|-----------|---------------|-------------------|------|--------------|
| **Frigate NVR** | Camera ingestion, object detection, recording, snapshots, RTSP restream via go2rtc | Cameras (RTSP), Mosquitto (MQTT publish), HA (HTTP for API) | 5000 (web/API), 8554 (RTSP), 8555 (WebRTC) | `modules/automation/frigate.nix` |
| **Mosquitto** | MQTT message broker between Frigate and HA | Frigate (publisher), Home Assistant (subscriber) | 1883 (localhost only) | `modules/automation/home-assistant.nix` |
| **Home Assistant** | Entity management, automation hub, dashboard, notification dispatch | Mosquitto (MQTT), Frigate (HTTP API), Companion app (push) | 8123 | `modules/automation/home-assistant.nix` |
| **Frigate custom component** | Creates HA entities from Frigate MQTT data, proxies Frigate API for media access | Runs inside HA process. Uses MQTT for entity state and HTTP for media. | N/A (HA internal) | `customComponents` in HA NixOS config |
| **HA Companion App** | Receives push notifications with snapshots | Home Assistant (push notifications) | N/A (mobile) | Manual phone setup |
| **Caddy** (firebat) | Reverse proxy with HTTPS for both Frigate and HA | HA and Frigate (proxy upstream) | 443 | `modules/gateway/caddy.nix` |

### What Each Component Owns

**Frigate owns:**
- Camera RTSP connections
- Object detection (CPU-based, 4 threads)
- Recording management (5-day motion, 30-day events)
- Snapshot generation
- RTSP restreaming (go2rtc)
- MQTT state/event publishing
- Review item generation (alert vs detection severity)

**Frigate custom component owns:**
- Entity creation (cameras, binary sensors, switches, sensors)
- MQTT auto-discovery subscription
- `/api/frigate/notifications/*` proxy endpoints
- Media browser integration (clips, snapshots)
- Frigate WebSocket API connection

**Home Assistant owns:**
- Automation logic (when to notify, what to filter)
- Push notification dispatch (via mobile_app)
- Dashboard presentation
- Config entry storage (MQTT broker, Frigate URL)

**Mosquitto owns:**
- Message routing between Frigate and HA
- Topic-based pub/sub (no transformation, pure broker)

## Data Flow

### Flow 1: Object Detection to Push Notification

```
Camera RTSP stream
  --> Frigate detects object (e.g., person on driveway)
  --> Frigate publishes to MQTT: frigate/reviews
      Payload: {type: "new", after: {id, camera: "driveway", severity: "alert",
                data: {objects: ["person"], detections: ["event-id-123"]}}}
  --> Mosquitto routes to HA
  --> HA automation triggers (MQTT trigger on frigate/reviews)
  --> Automation conditions: type == "new", severity == "alert", "person" in objects
  --> Action: notify.mobile_app_<phone>
      title: "Person Detected"
      message: "Driveway camera"
      image: /api/frigate/notifications/event-id-123/thumbnail.jpg
      tag: frigate-<review-id>  (deduplication)
  --> Companion app shows push notification with snapshot
```

### Flow 2: Entity Auto-Creation

```
Frigate starts
  --> Publishes to frigate/available: "online"
  --> Publishes retained state to frigate/<camera>/detect/state: "ON"
  --> Frigate custom component receives MQTT messages
  --> Creates entities:
      - camera.driveway (live feed from Frigate API)
      - binary_sensor.driveway_motion (from frigate/driveway/motion)
      - switch.driveway_detect (from frigate/driveway/detect/state)
      - switch.driveway_recordings
      - switch.driveway_snapshots
      - sensor.driveway_person_count (from frigate/driveway/person)
      - image.driveway_person (latest detection snapshot)
      ... repeated for front_door, garage
```

### Flow 3: Camera Feature Control

```
User toggles detection switch in HA dashboard
  --> HA publishes to: frigate/driveway/detect/set
      Payload: "OFF"
  --> Frigate subscribes, disables detection for driveway
  --> Frigate publishes to: frigate/driveway/detect/state
      Payload: "OFF"
  --> switch.driveway_detect entity updates to OFF
  --> Dashboard reflects new state
```

### Flow 4: Snapshot Retrieval for Notification

```
Notification automation needs snapshot for event-id-123
  --> HA requests: /api/frigate/notifications/event-id-123/thumbnail.jpg
  --> Frigate custom component proxies to: http://localhost:5000/api/events/event-id-123/thumbnail.jpg
  --> Frigate returns JPEG from its event database
  --> HA includes in push notification data
  --> Companion app downloads and displays image
```

## MQTT Topic Structure

### Global Topics

| Topic | Direction | Payload | Retained | Purpose |
|-------|-----------|---------|----------|---------|
| `frigate/available` | Frigate -> HA | `"online"` / `"offline"` | Yes | Availability for HA entities |
| `frigate/events` | Frigate -> HA | JSON (before/after with type) | No | Individual tracked object state changes |
| `frigate/reviews` | Frigate -> HA | JSON (before/after with severity) | No | Review items (recommended for notifications) |
| `frigate/stats` | Frigate -> HA | JSON | No | System statistics (CPU, memory, detector FPS) |

### Per-Camera Topics (driveway, front_door, garage)

| Topic Suffix | Direction | Payload | Retained | Purpose |
|-------------|-----------|---------|----------|---------|
| `/<object>` | Frigate -> HA | Integer count | Yes | Object count (e.g., `frigate/driveway/person`) |
| `/<object>/snapshot` | Frigate -> HA | JPEG binary | No | Latest snapshot of detected object |
| `/motion` | Frigate -> HA | `"ON"` / `"OFF"` | No | Motion detection state |
| `/detect/set` | HA -> Frigate | `"ON"` / `"OFF"` | No | Toggle object detection |
| `/detect/state` | Frigate -> HA | `"ON"` / `"OFF"` | Yes | Current detection state |
| `/recordings/set` | HA -> Frigate | `"ON"` / `"OFF"` | No | Toggle recording |
| `/recordings/state` | Frigate -> HA | `"ON"` / `"OFF"` | Yes | Current recording state |
| `/snapshots/set` | HA -> Frigate | `"ON"` / `"OFF"` | No | Toggle snapshots |
| `/snapshots/state` | Frigate -> HA | `"ON"` / `"OFF"` | Yes | Current snapshot state |

### Reviews Payload Structure (frigate/reviews) -- Recommended for Notifications

```json
{
  "type": "new|update|end",
  "before": { ... },
  "after": {
    "id": "1732824558.096492-aj3xqr",
    "camera": "driveway",
    "start_time": 1732824558.096,
    "end_time": null,
    "severity": "alert",
    "thumb_path": "/path/to/thumb.webp",
    "data": {
      "detections": ["1732824582.81398-kx5432"],
      "objects": ["person"],
      "sub_labels": [],
      "zones": ["yard"],
      "audio": []
    }
  }
}
```

**Use `frigate/reviews` for notifications** because:
- Provides `severity` field for filtering (alert vs detection)
- Contains `data.detections` array with event IDs for fetching thumbnails
- Less noisy than `frigate/events` (one review per incident, not per frame update)
- Recommended by Frigate official documentation

## NixOS Declarative Configuration Pattern

### Core Integration Setup

```nix
# modules/automation/home-assistant.nix -- additions

services.home-assistant = {
  # Frigate custom component (creates entities automatically)
  customComponents = with pkgs.home-assistant-custom-components; [
    frigate
  ];

  # Dashboard camera card (verify package name on nixos-25.05)
  # customLovelaceModules = with pkgs.home-assistant-custom-lovelace-modules; [
  #   advanced-camera-card  # or frigate-hass-card
  # ];

  # Existing extraComponents already include what we need:
  # "default_config", "mobile_app", "mqtt", "generic", "ffmpeg",
  # "automation", "script", "scene"

  config = {
    # ... existing config (homeassistant, http, recorder, logger) ...

    # Notification automations -- declarative, version-controlled
    "automation manual" = [
      {
        alias = "Frigate - Person Alert";
        trigger = [{
          platform = "mqtt";
          topic = "frigate/reviews";
        }];
        condition = [{
          condition = "template";
          value_template = ''
            {{ trigger.payload_json["type"] == "new"
               and trigger.payload_json["after"]["severity"] == "alert"
               and "person" in trigger.payload_json["after"]["data"]["objects"] }}
          '';
        }];
        action = [{
          service = "notify.mobile_app_DEVICE_NAME";
          data = {
            title = "Person Detected";
            message = ''{{ trigger.payload_json["after"]["camera"] | replace("_", " ") | title }}'';
            data = {
              image = ''/api/frigate/notifications/{{ trigger.payload_json["after"]["data"]["detections"][0] }}/thumbnail.jpg'';
              tag = ''frigate-{{ trigger.payload_json["after"]["id"] }}'';
              # Actionable: tap opens Frigate event
              url = ''/api/frigate/notifications/{{ trigger.payload_json["after"]["data"]["detections"][0] }}/clip.mp4'';
            };
          };
        }];
      }
    ];

    # Also allow UI-created automations (coexistence)
    "automation ui" = "!include automations.yaml";
  };
};
```

### Key NixOS Patterns

**Pattern 1: "automation manual" + "automation ui" coexistence**

NixOS-declared automations live in `"automation manual"` and UI-created automations use `"automation ui" = "!include automations.yaml"`. Both sources are loaded. This allows iterating on automations in the UI first, then codifying them in Nix.

**Caveat:** If no automations have been created via UI, `automations.yaml` will not exist and HA will log a warning (not an error). To prevent this, create an empty file via tmpfiles:

```nix
systemd.tmpfiles.rules = [
  "f /var/lib/hass/automations.yaml 0644 hass hass - []"
];
```

**Pattern 2: One-time UI config entries persist via impermanence**

The MQTT and Frigate integration config entries are stored in `/var/lib/hass/.storage/core.config_entries`. Since `/var/lib/hass` is persisted via impermanence, these survive reboots. They only need to be created once after initial deployment.

**Pattern 3: Nix string escaping for Jinja2 templates**

Jinja2 templates in Nix use `''` (double single-quote) strings to avoid escaping `${}` which Nix would interpret as string interpolation. Curly braces in Jinja2 (`{{ }}`) do not conflict with Nix syntax.

## Patterns to Follow

### Pattern 1: Reviews-Based Notification Triggering

**What:** Trigger automations on `frigate/reviews` instead of `frigate/events`.
**When:** Always, for notification automations.
**Why:** Reviews aggregate multiple detection frames into a single incident. Events fire on every frame update. Reviews provide severity levels (alert vs detection) and detection IDs for fetching media.

### Pattern 2: Notification Tag for Deduplication

**What:** Set the notification `tag` to `frigate-<review_id>` so subsequent updates replace the existing notification rather than creating duplicates.
**When:** All push notification automations.
**Why:** Prevents notification spam when Frigate sends `type: "update"` messages for the same review item.

### Pattern 3: Snapshot via Frigate Integration Proxy

**What:** Use `/api/frigate/notifications/<event_id>/thumbnail.jpg` for notification images.
**When:** All push notifications that include images.
**Why:** This URL is proxied through HA by the Frigate custom component, making it accessible to the Companion App without exposing Frigate directly. The event-specific URL returns the best available image for that detection.

### Pattern 4: Separate Automations per Notification Behavior

**What:** Create distinct automations when different object types need different behavior.
**When:** Person = always notify, car = night only, package = once then stop.
**Why:** Keeps automation logic simple and debuggable. Start with one automation for all alerts, split later if needed.

## Anti-Patterns to Avoid

### Anti-Pattern 1: Using frigate/events for Notifications

**What:** Triggering notification automations on `frigate/events` topic.
**Why bad:** Events fire per-object per-frame (dozens per second during active tracking). Causes notification floods.
**Instead:** Use `frigate/reviews` which aggregates detections into incidents.

### Anti-Pattern 2: Direct Camera RTSP in HA

**What:** Configuring HA camera entities to connect directly to camera RTSP URLs.
**Why bad:** Opens a second RTSP connection. WiFi cameras (Tapo) drop connections under multiple simultaneous streams.
**Instead:** The Frigate custom component provides camera entities that use Frigate's API streams. For manual camera entities, use go2rtc restream at `rtsp://localhost:8554/<camera_name>`.

### Anti-Pattern 3: Generic Snapshot URL in Notifications

**What:** Using `/api/<camera>/latest.jpg` for notification images.
**Why bad:** By the time the notification is viewed, "latest" may show a different frame or empty scene.
**Instead:** Use event-specific thumbnail URL: `/api/frigate/notifications/<event_id>/thumbnail.jpg`.

### Anti-Pattern 4: HACS on NixOS

**What:** Installing HACS to manage the Frigate integration or camera card.
**Why bad:** Non-declarative, not reproducible, downloads at runtime, conflicts with impermanence.
**Instead:** Use `customComponents` and `customLovelaceModules` from nixpkgs.

## Scalability Considerations

| Concern | Current (3 cameras) | 6 cameras | 10+ cameras |
|---------|---------------------|-----------|-------------|
| MQTT throughput | Negligible | Negligible | Negligible -- MQTT payloads are tiny |
| Frigate CPU (detection) | ~30% of 4 cores | ~60% -- consider OpenVINO | Need dedicated TPU (Coral) |
| HA entity count | ~25 entities | ~50 entities | ~80+ entities -- still fine |
| Notification volume | Manageable | Add cooldowns per camera | Group notifications by area |
| Storage (recordings) | ~50GB/5 days | ~100GB/5 days | Consider reducing retention |
| Automation complexity | 1-3 automations | Per-camera automations | Template-based generation |

## Sources

- [Frigate MQTT Documentation](https://docs.frigate.video/integrations/mqtt/) -- HIGH confidence, official docs
- [Frigate Home Assistant Integration](https://docs.frigate.video/integrations/home-assistant/) -- HIGH confidence, official docs
- [Frigate HA Notifications Guide](https://docs.frigate.video/guides/ha_notifications/) -- HIGH confidence, official docs
- [frigate-hass-integration GitHub](https://github.com/blakeblackshear/frigate-hass-integration) -- HIGH confidence
- [NixOS Wiki: Home Assistant](https://wiki.nixos.org/wiki/Home_Assistant) -- HIGH confidence
- [Frigate 0.14 Review Notifications Guide](https://github.com/blakeblackshear/frigate/discussions/11554) -- MEDIUM confidence
- Existing codebase: `modules/automation/frigate.nix`, `modules/automation/home-assistant.nix`, `hosts/ser8/configuration.nix`, `hosts/ser8/impermanence.nix` -- HIGH confidence
