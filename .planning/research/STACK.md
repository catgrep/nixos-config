# Technology Stack

**Project:** Frigate-Home Assistant Integration on NixOS
**Researched:** 2026-02-09

## Recommended Stack

### Integration Layer (Frigate <-> Home Assistant)

| Technology | Version | Purpose | Why | Confidence |
|------------|---------|---------|-----|------------|
| `home-assistant-custom-components.frigate` | 5.6.0+ (nixpkgs) | HA custom component providing Frigate entities, sensors, switches, cameras | The only officially supported integration path. Creates camera entities, motion binary sensors, detection switches, and sensor entities per camera. Packaged in nixpkgs since NixOS 23.11 via `services.home-assistant.customComponents`, so no HACS needed. | HIGH |
| `home-assistant-custom-lovelace-modules.advanced-camera-card` | 7.x (nixpkgs) | Dashboard card for live camera views, clip/snapshot browsing | Renamed from `frigate-hass-card` in v7.0.0 (Feb 2025). Provides live view, mini-gallery, event browsing, WebRTC support. Available in nixpkgs as a Lovelace module via `customLovelaceModules`. | MEDIUM |

### Communication Layer (MQTT)

| Technology | Version | Purpose | Why | Confidence |
|------------|---------|---------|-----|------------|
| Mosquitto MQTT broker | Already deployed | Message bus between Frigate and Home Assistant | Already running on localhost:1883 with no auth. Frigate already publishes to MQTT. No changes needed to the broker. | HIGH |
| HA MQTT integration | Built-in | Subscribes to Frigate MQTT topics, discovers entities | Already listed in `extraComponents`. Requires one-time UI setup to point at localhost:1883. Cannot be fully declarative -- MQTT integration config entry must be created through HA UI on first boot. | HIGH |

### Notification Layer

| Technology | Version | Purpose | Why | Confidence |
|------------|---------|---------|-----|------------|
| HA Mobile App (`mobile_app` component) | Built-in | Push notifications to iOS/Android | Already in `extraComponents`. Standard approach for Frigate notifications. Provides `notify.mobile_app_<device>` service. | HIGH |
| HA Automations (declarative YAML in Nix) | N/A | Trigger notifications on detection events | Write automations directly in `services.home-assistant.config` as Nix attribute sets. Triggers on `frigate/reviews` MQTT topic with `payload: alert` for high-severity detections. | HIGH |

### Dashboard Layer

| Technology | Version | Purpose | Why | Confidence |
|------------|---------|---------|-----|------------|
| HA Lovelace dashboards | Built-in | Camera views, event history, detection controls | Configure via HA UI after integration entities are available. Cannot be fully declarative. | HIGH |
| `advanced-camera-card` (Lovelace module) | 7.x | Rich camera card with live view, clip browsing, WebRTC | Provides far better camera experience than built-in picture-entity card. Supports Frigate-native features like event scrubbing. | MEDIUM |

### Existing Infrastructure (No Changes Needed)

| Technology | Current State | Notes |
|------------|--------------|-------|
| Frigate NVR 0.15.2 | Running, MQTT enabled, snapshots enabled, 3 active cameras | Already publishes to `frigate/events`, `frigate/reviews`, `frigate/<camera>/person/snapshot` etc. |
| Mosquitto | Running on 127.0.0.1:1883, no auth | Frigate already connected |
| Home Assistant | Running, `mqtt` + `mobile_app` in extraComponents | Needs MQTT config entry + Frigate integration setup |
| Impermanence | `/var/lib/hass` persisted | HA state survives reboots. Config entries, automations stored here. |
| Caddy reverse proxy | Frigate and HA both proxied | `frigate.vofi`, `hass.vofi`, plus Tailscale URLs |

## NixOS-Specific Configuration

### Frigate Custom Component (Declarative)

```nix
services.home-assistant = {
  # Add Frigate integration as a custom component
  customComponents = with pkgs.home-assistant-custom-components; [
    frigate
  ];

  # Add camera card for dashboards
  customLovelaceModules = with pkgs.home-assistant-custom-lovelace-modules; [
    # Check availability: may be frigate-hass-card or advanced-camera-card
    # depending on nixpkgs version
  ];
};
```

### Automations in Nix (Declarative)

```nix
services.home-assistant.config = {
  # Declarative automations coexist with UI-created ones
  "automation manual" = [
    {
      alias = "Frigate - Person Alert";
      trigger = [
        {
          platform = "mqtt";
          topic = "frigate/reviews";
          payload = "alert";
          value_template = "{{ value_json['type'] }}";
        }
      ];
      condition = [
        {
          condition = "template";
          value_template = "{{ 'person' in trigger.payload_json['before']['data']['objects'] }}";
        }
      ];
      action = [
        {
          service = "notify.mobile_app_DEVICE_NAME";
          data = {
            title = "Person Detected";
            message = "{{ trigger.payload_json['before']['data']['objects'] | join(', ') }} detected on {{ trigger.payload_json['before']['camera'] }}";
            data = {
              image = "/api/frigate/notifications/{{ trigger.payload_json['before']['data']['detections'][0] }}/thumbnail.jpg";
            };
          };
        }
      ];
    }
  ];
  # Also allow UI-created automations
  "automation ui" = "!include automations.yaml";
};
```

### MQTT Integration (Partially Declarative)

The MQTT integration **cannot** be fully set up declaratively. It requires a config entry created through the HA UI. However, MQTT-based entities (sensors, binary sensors) and automations CAN be declared in Nix.

**First-boot procedure:** After deploying the Nix config, navigate to HA UI -> Settings -> Integrations -> Add MQTT -> broker: localhost, port: 1883, no auth.

This is a one-time step. The config entry persists in `/var/lib/hass/.storage/core.config_entries` which survives reboots via impermanence.

### Frigate Integration (UI Setup Required)

Similarly, the Frigate custom component requires a config entry via UI:
HA UI -> Settings -> Integrations -> Add Frigate -> URL: `http://localhost:5000`

This persists in the same config entries storage.

## Alternatives Considered

| Category | Recommended | Alternative | Why Not |
|----------|-------------|-------------|---------|
| Integration method | `customComponents` in Nix | HACS (Home Assistant Community Store) | HACS is imperative, not reproducible, requires GitHub tokens, and defeats the purpose of declarative NixOS config. nixpkgs has the frigate component packaged. |
| Notification trigger | `frigate/reviews` MQTT topic | `frigate/events` MQTT topic | `frigate/reviews` is the recommended approach since Frigate 0.14+. Reviews consolidate related detections (person + package = one review) and are the basis for the Frigate UI. `frigate/events` still works but produces more granular, noisier notifications. |
| Notification method | HA Mobile App push | Pushover / Telegram / Email | Mobile App is built-in, supports rich media (images, video), actionable notifications, and requires no external services. Already in extraComponents. |
| Dashboard card | `advanced-camera-card` | Built-in `picture-entity` card | The built-in card lacks clip browsing, event timeline, WebRTC support, and Frigate-native features. The advanced card is purpose-built for camera surveillance. |
| Automation approach | Declarative YAML in Nix | Blueprint (SgtBatten) | Blueprints are UI-imported and not declarative. However, the SgtBatten blueprint YAML can be used as a **reference** for writing the Nix automation. The blueprint handles edge cases (cooldowns, zones, update vs new messages) that are worth studying. |
| Camera card package | `advanced-camera-card` | `frigate-hass-card` (legacy name) | Same project, renamed in v7.0.0. The nixpkgs package may still use the old name depending on channel version. Check `nix search nixpkgs home-assistant-custom-lovelace-modules` for actual availability. |

## What NOT to Use

| Anti-Technology | Why Avoid |
|-----------------|-----------|
| **HACS** | Imperative package manager for HA. Downloads from GitHub at runtime, not reproducible, breaks declarative NixOS philosophy. Use `customComponents` instead. |
| **HA Add-ons** | Require HA OS or HA Supervised. NixOS runs HA Core only. Frigate runs as a native NixOS service, not an add-on. |
| **Node-RED** | Over-engineering for simple MQTT-trigger-to-notification flows. Adds another service to maintain. HA automations are sufficient. |
| **frigate/events MQTT topic** (as primary trigger) | Produces per-object events rather than consolidated reviews. Results in duplicate notifications (person + package = 2 notifications instead of 1). Use `frigate/reviews` instead. |
| **Webhooks for notifications** | Requires exposing HA externally. Frigate and HA are on the same host -- MQTT is the standard local communication path. |

## MQTT Topic Reference

Key topics Frigate publishes that the HA integration and automations consume:

| Topic | Purpose | Used By |
|-------|---------|---------|
| `frigate/available` | Frigate online/offline status | HA Frigate integration (availability) |
| `frigate/events` | Per-object detection lifecycle (new/update/end) | HA Frigate integration (entity updates) |
| `frigate/reviews` | Consolidated review items (alert/detection severity) | Notification automations |
| `frigate/<camera>/person/snapshot` | JPEG snapshot of detected person | Can be used in notifications |
| `frigate/<camera>/detect/state` | Detection enabled/disabled state | HA switch entities |
| `frigate/<camera>/recordings/state` | Recording enabled/disabled state | HA switch entities |

## Version Compatibility Matrix

| Component | Version | Requires |
|-----------|---------|----------|
| Frigate NVR | 0.15.2 (installed) | MQTT broker |
| frigate-hass-integration | 5.6.0+ | HA 2024.1+, MQTT integration configured, Frigate with MQTT enabled |
| Home Assistant | 2025.x (nixos-25.05 channel) | Python 3.12+ |
| advanced-camera-card | 7.x | frigate-hass-integration installed |
| Mosquitto | 2.x (installed) | N/A |

## Installation Summary

```nix
# In modules/automation/home-assistant.nix -- additions to existing config

services.home-assistant = {
  # NEW: Add Frigate custom component
  customComponents = with pkgs.home-assistant-custom-components; [
    frigate
  ];

  # NEW: Add camera dashboard card (verify package name for nixos-25.05)
  # customLovelaceModules = with pkgs.home-assistant-custom-lovelace-modules; [
  #   advanced-camera-card  # or frigate-hass-card depending on channel
  # ];

  # EXISTING extraComponents -- no changes needed
  # mqtt, mobile_app, generic, ffmpeg already listed

  # NEW: Add notification automations
  config = {
    # ... existing config ...

    # Automations for Frigate notifications
    "automation manual" = [
      # Per-camera notification automations go here
    ];
    "automation ui" = "!include automations.yaml";
  };
};
```

No new flake inputs needed. No new system packages needed. No infrastructure changes needed.

## Sources

- [Frigate Home Assistant Integration Docs](https://docs.frigate.video/integrations/home-assistant/) -- Official integration requirements and setup
- [Frigate MQTT Docs](https://docs.frigate.video/integrations/mqtt/) -- MQTT topic structure and payloads
- [Frigate HA Notifications Guide](https://docs.frigate.video/guides/ha_notifications/) -- Official notification patterns
- [frigate-hass-integration GitHub](https://github.com/blakeblackshear/frigate-hass-integration) -- Integration source, releases (v5.9.x latest upstream)
- [NixOS Wiki: Home Assistant](https://wiki.nixos.org/wiki/Home_Assistant) -- customComponents and customLovelaceModules usage
- [nixpkgs PR #371866](https://github.com/NixOS/nixpkgs/pull/371866) -- frigate custom component 5.3.0 -> 5.6.0 update
- [nixpkgs PR #371860](https://github.com/NixOS/nixpkgs/pull/371860) -- frigate-hass-card 6.1.2 init in nixpkgs
- [advanced-camera-card GitHub](https://github.com/dermotduffy/advanced-camera-card) -- Renamed from frigate-hass-card v7.0.0
- [SgtBatten HA Blueprints](https://github.com/SgtBatten/HA_blueprints) -- Reference notification automation patterns
- [Frigate 0.14 Review Notifications Guide](https://github.com/blakeblackshear/frigate/discussions/11554) -- frigate/reviews topic usage
- [NixOS Discourse: Frigate into Home Assistant](https://discourse.nixos.org/t/frigate-into-home-assistant/62851) -- NixOS-specific integration discussion
- [MyNixOS: services.home-assistant.customComponents](https://mynixos.com/nixpkgs/option/services.home-assistant.customComponents) -- Option documentation
