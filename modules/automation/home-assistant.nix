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

let
  # Camera dashboard configuration (Nix attrset -> JSON, which is valid YAML)
  # Deployed as a symlink from /var/lib/hass/cameras-dashboard.yaml -> /nix/store/...
  camerasDashboard = pkgs.writeText "cameras-dashboard.yaml" (builtins.toJSON dashboardConfig);

  # Helper: advanced-camera-card (formerly frigate-hass-card) for live camera view
  # Per user decision: live video stream default, click to fullscreen, no bounding boxes
  # Includes conditional "Detection Off" badge overlay when detection switch is off
  cameraCard = cameraName: displayName: {
    type = "custom:advanced-camera-card";
    cameras = [
      {
        camera_entity = "camera.${cameraName}";
        live_provider = "auto";
        title = displayName;
        frigate = {
          camera_name = cameraName;
        };
      }
    ];
    live = {
      controls = {
        builtin = true;
      };
    };
    menu = {
      buttons = {
        frigate = {
          enabled = true;
        };
        fullscreen = {
          enabled = true;
        };
      };
    };
    view = {
      default = "live";
    };
    # "Detection Off" overlay badge when detection is disabled (per user decision)
    elements = [
      {
        type = "conditional";
        conditions = [
          {
            entity = "switch.${cameraName}_detect";
            state = "off";
          }
        ];
        elements = [
          {
            type = "state-badge";
            entity = "switch.${cameraName}_detect";
            style = {
              top = "8%";
              right = "8%";
              left = "auto";
              color = "red";
              opacity = "0.8";
            };
          }
        ];
      }
    ];
  };

  advancedCameraCard = pkgs.home-assistant-custom-lovelace-modules.advanced-camera-card;

  # Lovelace resource registration for storage mode
  # When lovelace.mode = "storage", HA ignores lovelace.resources in configuration.yaml
  # and reads from .storage/lovelace_resources instead. We create this file declaratively.
  lovelaceResources = pkgs.writeText "lovelace_resources" (
    builtins.toJSON {
      version = 1;
      minor_version = 1;
      key = "lovelace_resources";
      data.items = [
        {
          id = "nixos-advanced-camera-card";
          type = "module";
          url = "/local/nixos-lovelace-modules/advanced-camera-card.js?${advancedCameraCard.version}";
        }
      ];
    }
  );

  # Admin-only dashboard for detection/motion controls
  adminDashboard = pkgs.writeText "camera-admin-dashboard.yaml" (
    builtins.toJSON adminDashboardConfig
  );

  adminDashboardConfig = {
    views = [
      {
        title = "Camera Controls";
        path = "controls";
        icon = "mdi:cog";
        cards = [
          {
            type = "entities";
            title = "Object Detection";
            show_header_toggle = true;
            entities = [
              {
                entity = "switch.driveway_detect";
                name = "Driveway";
              }
              {
                entity = "switch.front_door_detect";
                name = "Front Door";
              }
              {
                entity = "switch.garage_detect";
                name = "Garage";
              }
            ];
          }
          {
            type = "entities";
            title = "Motion Detection";
            show_header_toggle = true;
            entities = [
              {
                entity = "switch.driveway_motion";
                name = "Driveway";
              }
              {
                entity = "switch.front_door_motion";
                name = "Front Door";
              }
              {
                entity = "switch.garage_motion";
                name = "Garage";
              }
            ];
          }
        ];
      }
    ];
  };

  dashboardConfig = {
    views = [
      # Tab 1: Live Cameras
      {
        title = "Live Cameras";
        path = "live";
        icon = "mdi:camera";
        cards = [
          (cameraCard "driveway" "Driveway")
          (cameraCard "front_door" "Front Door")
          (cameraCard "garage" "Garage")
        ];
      }
      # Tab 2: Events timeline
      {
        title = "Events";
        path = "events";
        icon = "mdi:motion-sensor";
        cards = [
          # Timeline: compact static ratio to show just the timeline bars
          # Clicking an event expands the media preview within the card
          {
            type = "custom:advanced-camera-card";
            card_id = "events_card";
            cameras = [
              {
                camera_entity = "camera.driveway";
                title = "Driveway";
                frigate.camera_name = "driveway";
              }
              {
                camera_entity = "camera.front_door";
                title = "Front Door";
                frigate.camera_name = "front_door";
              }
              {
                camera_entity = "camera.garage";
                title = "Garage";
                frigate.camera_name = "garage";
              }
            ];
            dimensions = {
              aspect_ratio = "9:16";
              layout = {
                fit = "cover";
                position = {
                  x = 0;
                };
              };
            };
            view = {
              default = "timeline";
            };
            media_gallery = {
              controls = {
                filter.mode = "left";
                thumbnails = {
                  size = 200;
                  show_details = false;
                  show_download_control = true;
                  show_favorite_control = true;
                  show_timeline_control = true;
                };
              };
            };
          }
        ];
      }
      # Per-camera subviews for notification deep-linking
      # subview hides from tab bar; back button returns to live cameras
      {
        title = "Driveway";
        path = "camera_driveway";
        subview = true;
        cards = [ (cameraCard "driveway" "Driveway") ];
      }
      {
        title = "Front Door";
        path = "camera_front_door";
        subview = true;
        cards = [ (cameraCard "front_door" "Front Door") ];
      }
      {
        title = "Garage";
        path = "camera_garage";
        subview = true;
        cards = [ (cameraCard "garage" "Garage") ];
      }
    ];
  };
in
{
  # SOPS secrets for family HA user (only when HA is enabled)
  sops.secrets = lib.mkIf config.services.home-assistant.enable {
    "hass_family_username" = {
      owner = "hass";
      group = "hass";
      mode = "0400";
    };
    "hass_family_password" = {
      owner = "hass";
      group = "hass";
      mode = "0400";
    };
  };

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

    # Frigate Lovelace card (frigate-hass-card) for camera dashboard
    # Package renamed from frigate-hass-card to advanced-camera-card in v7.0.0
    customLovelaceModules = with pkgs.home-assistant-custom-lovelace-modules; [
      advanced-camera-card
    ];

    # Lovelace dashboard configuration
    config.lovelace = {
      mode = "storage"; # Keep default dashboard UI-editable
      dashboards = {
        lovelace-cameras = {
          mode = "yaml";
          filename = "cameras-dashboard.yaml";
          title = "Cameras";
          icon = "mdi:cctv";
          show_in_sidebar = true;
          require_admin = false;
        };
        lovelace-camera-admin = {
          mode = "yaml";
          filename = "camera-admin-dashboard.yaml";
          title = "Camera Admin";
          icon = "mdi:shield-lock";
          show_in_sidebar = true;
          require_admin = true;
        };
      };
    };

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

      # Mobile app integration for push notifications via Companion app
      # Test with: Developer Tools -> Actions -> notify.mobile_app_bobbo_dhillons_iphone
      #   YAML mode -> message: "Test from HA" -> Perform Action
      mobile_app = { };

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
              # Use from_json filter instead of trigger.payload_json (HA 2025.5+ compat)
              value_template = "{{ (trigger.payload | from_json)['after']['data']['objects'] | select('in', ['person', 'car', 'package']) | list | length > 0 }}";
            }
            # Ensure detections array is not empty (defensive guard)
            {
              condition = "template";
              value_template = "{{ (trigger.payload | from_json)['after']['data']['detections'] | length > 0 }}";
            }
          ];
          action = [
            # Parse MQTT payload once and store as variable for all templates below
            # This avoids relying on trigger.payload_json which is unavailable in
            # HA 2025.5.x action template context (UndefinedError)
            {
              variables = {
                review = "{{ trigger.payload | from_json }}";
              };
            }
            # Show in HA Notifications tab
            {
              action = "persistent_notification.create";
              data = {
                title = "{{ review['after']['data']['objects'] | sort | join(', ') | title }} Detected";
                message = "{{ review['after']['camera'] | replace('_', ' ') | title }} at {{ review['after']['start_time'] | int | timestamp_local }}";
                notification_id = "frigate_{{ review['after']['id'] }}";
              };
            }
            # Push notification to phone
            {
              action = "notify.mobile_app_bobbo_dhillons_iphone";
              data = {
                title = "{{ review['after']['data']['objects'] | sort | join(', ') | title }} Detected";
                message = "{{ review['after']['camera'] | replace('_', ' ') | title }}";
                data = {
                  # Snapshot image via Frigate proxy (uses detection event ID, NOT review ID)
                  image = "/api/frigate/notifications/{{ review['after']['data']['detections'][0] }}/snapshot.jpg";
                  # Tag for deduplication (uses review ID -- same review replaces notification in-place)
                  tag = "{{ review['after']['id'] }}";
                  # Timestamp for notification ordering
                  when = "{{ review['after']['start_time'] | int }}";
                  # iOS: camera entity for live preview
                  entity_id = "camera.{{ review['after']['camera'] }}";
                  # Tap to open specific camera live feed
                  url = "/lovelace-cameras/camera_{{ review['after']['camera'] }}";
                  clickAction = "/lovelace-cameras/camera_{{ review['after']['camera'] }}";
                  # Group notifications by camera
                  group = "frigate-{{ review['after']['camera'] }}";
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
    # Symlink dashboards from Nix store (JSON is valid YAML)
    "L+ /var/lib/hass/cameras-dashboard.yaml - - - - ${camerasDashboard}"
    "L+ /var/lib/hass/camera-admin-dashboard.yaml - - - - ${adminDashboard}"
    # Register Lovelace resources for storage mode (HA ignores configuration.yaml resources)
    "C+ /var/lib/hass/.storage/lovelace_resources 0600 hass hass - ${lovelaceResources}"
  ];

  # Service ordering: HA starts after Mosquitto and Frigate
  # Uses `wants` (not `requires`) so HA can start even if Frigate is temporarily down
  systemd.services.home-assistant = {
    # Restart HA when dashboard config or lovelace resources change
    # (HA only reads YAML dashboards at startup, not on reload)
    restartTriggers = [
      camerasDashboard
      adminDashboard
      lovelaceResources
    ];
    after = [
      "mosquitto.service"
      "frigate.service"
    ];
    wants = [
      "mosquitto.service"
      "frigate.service"
    ];
    # Create non-admin family user (idempotent: skips if user exists)
    preStart = lib.mkAfter ''
      HASS_USERNAME=$(cat ${config.sops.secrets."hass_family_username".path})
      HASS_PASSWORD=$(cat ${config.sops.secrets."hass_family_password".path})

      AUTH_FILE="/var/lib/hass/.storage/auth"
      if [ -f "$AUTH_FILE" ] && \
         ${pkgs.jq}/bin/jq -e \
           --arg user "$HASS_USERNAME" \
           '.data.users[] | select(.name == $user)' \
           "$AUTH_FILE" > /dev/null 2>&1; then
        echo "hass-family-user: already exists, skipping"
      else
        echo "hass-family-user: creating..."
        ${lib.getExe config.services.home-assistant.package} \
          --script auth \
          --config /var/lib/hass \
          add "$HASS_USERNAME" "$HASS_PASSWORD"
        echo "hass-family-user: created"
      fi
    '';
  };

  # Required system packages
  environment.systemPackages = with pkgs; [
    ffmpeg # For camera streaming
  ];
}
