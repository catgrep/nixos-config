# SPDX-License-Identifier: GPL-3.0-or-later

{
  config,
  lib,
  pkgs,
  ...
}:

{
  services.home-assistant = {
    enable = lib.mkDefault false;

    # Extra components to include
    extraComponents = [
      # Core components
      "default_config"
      "met"
      "esphome"
      "shopping_list"

      # Device tracking
      "mobile_app"
      "device_tracker"

      # Integrations
      "tplink"
      "mqtt"
      "zha"
      "zwave_js"

      # Media
      "cast"
      "spotify"
      "jellyfin"

      # Weather
      "weather"
      "sun"

      # Utility
      "wake_on_lan"
      "ping"

      # Cameras
      "generic"
      "ffmpeg"

      # Smart home
      "light"
      "switch"
      "sensor"
      "binary_sensor"
      "climate"
      "humidifier"
      "fan"
      "cover"

      # Notifications
      "notify"
      "alert"

      # Energy monitoring
      "energy"
      "utility_meter"

      # Automation
      "automation"
      "script"
      "scene"
      "group"
      "timer"
      "input_boolean"
      "input_datetime"
      "input_number"
      "input_select"
      "input_text"
      "counter"
      "schedule"
    ];

    # Extra Python packages
    extraPackages =
      python3Packages: with python3Packages; [
        # Additional packages for integrations
        psycopg2
        aiohomekit
        pyatv
        paho-mqtt
      ];

    # Configuration
    config = {
      # Basic configuration
      homeassistant = {
        name = "Home";
        latitude = "37.3861"; # Los Altos, CA
        longitude = "-122.1140";
        elevation = 60;
        unit_system = "us_customary";
        time_zone = "America/Los_Angeles";
        currency = "USD";
        country = "US";

        # Customize entities
        customize = {
          "sensor.temperature" = {
            friendly_name = "Temperature";
            icon = "mdi:thermometer";
          };
        };

        # Auth providers
        auth_providers = [
          {
            type = "homeassistant";
          }
        ];
      };

      # Frontend configuration
      frontend = {
        themes = "!include_dir_merge_named themes";
      };

      # Enable configuration UI
      config = { };

      # HTTP configuration
      http = {
        # Uncomment and configure for external access
        # base_url = "https://homeassistant.homelab.local";
        # ssl_certificate = "/var/lib/acme/homeassistant.homelab.local/cert.pem";
        # ssl_key = "/var/lib/acme/homeassistant.homelab.local/key.pem";

        # Trusted networks
        trusted_proxies = [
          "127.0.0.1"
          "::1"
          "192.168.1.0/24"
        ];

        # CORS
        cors_allowed_origins = [
          "http://homeassistant.homelab.local:8123"
          "http://localhost:8123"
        ];
      };

      # Default dashboard
      lovelace = {
        mode = "storage";

        # Example dashboard configuration
        dashboards = {
          "lovelace-home" = {
            mode = "yaml";
            filename = "dashboards/home.yaml";
            title = "Home";
            icon = "mdi:home";
            show_in_sidebar = true;
            require_admin = false;
          };
        };
      };

      # Recorder - store data in PostgreSQL (optional)
      recorder = {
        db_url = "sqlite:////var/lib/hass/home-assistant_v2.db";
        purge_keep_days = 30;
        commit_interval = 5;

        # Exclude certain entities from recording
        exclude = {
          domains = [
            "automation"
            "updater"
          ];
          entity_globs = [
            "sensor.weather_*"
          ];
        };
      };

      # Logger
      logger = {
        default = "warning";
        logs = {
          "homeassistant.components.mqtt" = "debug";
          "homeassistant.components.tplink" = "debug";
        };
      };

      # Discovery
      discovery = { };

      # Map
      map = { };

      # System Health
      system_health = { };

      # Mobile app support
      mobile_app = { };

      # Person tracking
      person = { };

      # Sun tracking
      sun = { };

      # Weather
      weather = [
        {
          platform = "met";
          name = "Home";
        }
      ];

      # MQTT (if using)
      mqtt = {
        broker = "localhost";
        port = 1883;
        discovery = true;
        discovery_prefix = "homeassistant";
      };

      # Example automations
      automation = [
        {
          alias = "Turn on lights at sunset";
          trigger = {
            platform = "sun";
            event = "sunset";
            offset = "-00:30:00";
          };
          action = {
            service = "light.turn_on";
            entity_id = "group.all_lights";
          };
        }
      ];

      # Example groups
      group = {
        all_lights = {
          name = "All Lights";
          entities = [
            # Add your light entities here
          ];
        };
      };
    };

    # Open ports for Home Assistant
    openFirewall = true;
  };

  # MQTT broker for Home Assistant (optional)
  services.mosquitto = {
    enable = lib.mkDefault false;
    listeners = [
      {
        acl = [ "pattern readwrite #" ];
        omitPasswordAuth = true;
        settings.allow_anonymous = true;
        address = "127.0.0.1";
        port = 1883;
      }
    ];
  };

  # Ensure Home Assistant data directory has correct permissions
  systemd.tmpfiles.rules = [
    "d /var/lib/hass 0755 hass hass -"
    "d /var/lib/hass/custom_components 0755 hass hass -"
    "d /var/lib/hass/www 0755 hass hass -"
    "d /var/lib/hass/dashboards 0755 hass hass -"
    "d /var/lib/hass/themes 0755 hass hass -"
  ];

  # Required system packages
  environment.systemPackages = with pkgs; [
    ffmpeg # For camera streaming
    git # For HACS and custom components
  ];

  # Nginx reverse proxy configuration (optional)
  services.nginx.virtualHosts."homeassistant.homelab.local" = lib.mkIf config.services.nginx.enable {
    locations."/" = {
      proxyPass = "http://localhost:8123";
      proxyWebsockets = true;
      extraConfig = ''
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
      '';
    };
  };
}
