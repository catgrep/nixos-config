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
      "automation manual" = [ ];
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
