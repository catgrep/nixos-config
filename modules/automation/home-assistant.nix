# SPDX-License-Identifier: GPL-3.0-or-later

# Home Assistant configuration
# Most settings should be configured via the web UI after first boot.
# This module provides minimal declarative infrastructure setup.
{
  config,
  lib,
  pkgs,
  ...
}:

{
  services.home-assistant = {
    enable = lib.mkDefault false;

    # Essential components - others can be added via UI
    extraComponents = [
      # Core (includes frontend, onboarding, config, etc.)
      "default_config"

      # Device tracking
      "mobile_app"

      # Integrations for this homelab
      "mqtt" # For Frigate integration

      # Cameras
      "generic"
      "ffmpeg"

      # Automation essentials
      "automation"
      "script"
      "scene"
    ];

    # Extra Python packages for integrations
    extraPackages =
      python3Packages: with python3Packages; [
        paho-mqtt
      ];

    # Frigate custom component for HA integration
    customComponents = with pkgs.home-assistant-custom-components; [
      frigate
    ];

    # Minimal declarative config - rest configured via UI
    config = {
      # Basic identification (location/timezone set via UI on first boot)
      homeassistant = {
        name = "Home";
        unit_system = "us_customary";
        time_zone = "America/Los_Angeles";
        country = "US";
      };

      # HTTP configuration for Caddy reverse proxy
      http = {
        use_x_forwarded_for = true;
        trusted_proxies = [
          "127.0.0.1"
          "::1"
          "192.168.68.0/24" # Local network including Caddy on firebat
        ];
      };

      # Recorder - SQLite with 30-day retention
      recorder = {
        purge_keep_days = 30;
      };

      # Logger - warning by default
      logger = {
        default = "warning";
      };

      # Automation split: manual (Nix-declared) + UI (automations.yaml)
      # Source: https://docs.frigate.video/guides/ha_notifications/
      # Source: https://companion.home-assistant.io/docs/notifications/notifications-basic/
      "automation manual" = [
        {
          alias = "Frigate Alert Notification";
          description = "Send push notification with snapshot when Frigate detects person, car, or package";
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
            # Only notify for person, car, package (not dog, cat, etc.)
            {
              condition = "template";
              value_template = "{{ trigger.payload_json['after']['data']['objects'] | select('in', ['person', 'car', 'package']) | list | length > 0 }}";
            }
            # Ensure detections array is not empty (defensive guard)
            {
              condition = "template";
              value_template = "{{ trigger.payload_json['after']['data']['detections'] | length > 0 }}";
            }
          ];
          action = [
            {
              # Replace PLACEHOLDER_DEVICE_ID with actual device ID after Companion app setup
              action = "notify.mobile_app_PLACEHOLDER_DEVICE_ID";
              data = {
                title = "{{ trigger.payload_json['after']['data']['objects'] | sort | join(', ') | title }} Detected";
                message = "{{ trigger.payload_json['after']['camera'] | replace('_', ' ') | title }}";
                data = {
                  # Snapshot image via Frigate proxy (uses detection event ID, NOT review ID)
                  image = "/api/frigate/notifications/{{ trigger.payload_json['after']['data']['detections'][0] }}/snapshot.jpg";
                  # Tag for deduplication (uses review ID -- same review replaces notification in-place)
                  tag = "{{ trigger.payload_json['after']['id'] }}";
                  # Timestamp for notification ordering
                  when = "{{ trigger.payload_json['after']['start_time'] | int }}";
                  # iOS: camera entity for live preview
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
      "automation ui" = "!include automations.yaml";
    };

    openFirewall = true;
  };

  # MQTT broker for Home Assistant <-> Frigate communication
  services.mosquitto = {
    enable = lib.mkDefault false;
    listeners = [
      {
        # Local-only MQTT broker (no auth needed for localhost)
        acl = [ "pattern readwrite #" ];
        omitPasswordAuth = true;
        settings.allow_anonymous = true;
        address = "127.0.0.1";
        port = 1883;
      }
    ];
  };

  # Ensure Home Assistant data directories and files exist
  systemd.tmpfiles.rules = [
    "d /var/lib/hass 0755 hass hass -"
    "d /var/lib/hass/custom_components 0755 hass hass -"
    "d /var/lib/hass/www 0755 hass hass -"
    "f /var/lib/hass/automations.yaml 0644 hass hass"
  ];

  # Service ordering: HA starts after Mosquitto and Frigate
  # Uses `wants` (not `requires`) so HA can start even if Frigate is temporarily down
  systemd.services.home-assistant = {
    after = [
      "mosquitto.service"
      "frigate.service"
    ];
    wants = [
      "mosquitto.service"
      "frigate.service"
    ];
  };

  # Required system packages
  environment.systemPackages = with pkgs; [
    ffmpeg # For camera streaming
  ];
}
