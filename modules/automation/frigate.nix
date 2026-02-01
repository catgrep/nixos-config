# SPDX-License-Identifier: GPL-3.0-or-later

# Frigate NVR configuration for security cameras
# Provides AI-powered object detection with Home Assistant integration
{
  config,
  lib,
  pkgs,
  ...
}:

{
  # Allow insecure Frigate packages (has known CVE, but we're behind firewall/Tailscale)
  # See: https://github.com/blakeblackshear/frigate/security/advisories/GHSA-vg28-83rp-8xx4
  nixpkgs.config.permittedInsecurePackages = lib.mkIf config.services.frigate.enable [
    "frigate-0.15.2"
    "frigate-web-0.15.2"
  ];
  # Define frigate user/group explicitly
  users.users.frigate = {
    isSystemUser = true;
    group = "frigate";
    extraGroups = [
      "video"
      "render"
      "media"
    ];
  };
  users.groups.frigate = { };

  # Enable Frigate NVR service
  # Note: hostname must be set unconditionally as the NixOS module requires it
  services.frigate = {
    enable = lib.mkDefault false;
    hostname = "frigate";

    # AMD VA-API driver for hardware acceleration (Radeon 780M)
    vaapiDriver = "radeonsi";

    settings = {
      # MQTT for Home Assistant integration
      mqtt = {
        enabled = true;
        host = "localhost";
        port = 1883;
      };

      # Database configuration
      database = {
        path = "/var/lib/frigate/frigate.db";
      };

      # AMD GPU hardware acceleration
      ffmpeg = {
        hwaccel_args = "preset-vaapi";
        output_args = {
          record = "preset-record-generic-audio-aac";
        };
      };

      # Object detection configuration (CPU-based initially)
      detectors = {
        cpu = {
          type = "cpu";
          num_threads = 4;
        };
        # Future: OpenVINO on AMD GPU or dedicated TPU
      };

      # Recording configuration (global defaults)
      record = {
        enabled = true;
        retain = {
          days = 5;
          mode = "motion";
        };
        events = {
          retain = {
            default = 30;
            mode = "active_objects";
          };
        };
      };

      # Snapshot configuration
      snapshots = {
        enabled = true;
        retain = {
          default = 30;
        };
      };

      # Object tracking
      objects = {
        track = [
          "person"
          "car"
          "dog"
          "cat"
          "package"
        ];
        filters = {
          person = {
            min_area = 5000;
            max_area = 100000;
            threshold = 0.7;
          };
        };
      };

      # Logger configuration - reduce credential exposure
      logger = {
        logs = {
          "frigate.video" = "warning";
        };
      };

      # UI configuration
      ui = {
        live_mode = "webrtc";
        timezone = "America/Los_Angeles";
        use_experimental = false;
      };

      # go2rtc for WebRTC streaming
      go2rtc = {
        webrtc = {
          candidates = [
            "192.168.68.65:8555"
          ];
        };
      };

      # Camera configurations
      # Note: Camera-specific config with credentials should be added via SOPS template
      # These are placeholder entries - actual RTSP URLs come from secrets
      cameras = {
        # OUTDOOR CAMERAS (4x) - Detection enabled, 5-day retention
        front_door = {
          enabled = false; # Enable after adding SOPS credentials
          ffmpeg = {
            inputs = [
              {
                path = "rtsp://user:pass@192.168.68.101:554/stream1";
                roles = [ "record" ];
              }
              {
                path = "rtsp://user:pass@192.168.68.101:554/stream2";
                roles = [ "detect" ];
              }
            ];
          };
          detect = {
            enabled = true;
            width = 640;
            height = 360;
            fps = 5;
          };
          record = {
            enabled = true;
            retain = {
              days = 5;
              mode = "motion";
            };
          };
          snapshots = {
            enabled = true;
          };
        };

        backyard = {
          enabled = false;
          ffmpeg = {
            inputs = [
              {
                path = "rtsp://user:pass@192.168.68.102:554/stream1";
                roles = [ "record" ];
              }
              {
                path = "rtsp://user:pass@192.168.68.102:554/stream2";
                roles = [ "detect" ];
              }
            ];
          };
          detect = {
            enabled = true;
            width = 640;
            height = 360;
            fps = 5;
          };
          record = {
            enabled = true;
            retain = {
              days = 5;
              mode = "motion";
            };
          };
          snapshots = {
            enabled = true;
          };
        };

        driveway = {
          enabled = false;
          ffmpeg = {
            inputs = [
              {
                path = "rtsp://user:pass@192.168.68.103:554/stream1";
                roles = [ "record" ];
              }
              {
                path = "rtsp://user:pass@192.168.68.103:554/stream2";
                roles = [ "detect" ];
              }
            ];
          };
          detect = {
            enabled = true;
            width = 640;
            height = 360;
            fps = 5;
          };
          record = {
            enabled = true;
            retain = {
              days = 5;
              mode = "motion";
            };
          };
          snapshots = {
            enabled = true;
          };
        };

        side_gate = {
          enabled = false;
          ffmpeg = {
            inputs = [
              {
                path = "rtsp://user:pass@192.168.68.104:554/stream1";
                roles = [ "record" ];
              }
              {
                path = "rtsp://user:pass@192.168.68.104:554/stream2";
                roles = [ "detect" ];
              }
            ];
          };
          detect = {
            enabled = true;
            width = 640;
            height = 360;
            fps = 5;
          };
          record = {
            enabled = true;
            retain = {
              days = 5;
              mode = "motion";
            };
          };
          snapshots = {
            enabled = true;
          };
        };

        # INDOOR CAMERAS (2x) - No detection, 3-day retention
        living_room = {
          enabled = false;
          ffmpeg = {
            inputs = [
              {
                path = "rtsp://user:pass@192.168.68.105:554/stream1";
                roles = [ "record" ];
              }
            ];
          };
          detect = {
            enabled = false;
          };
          record = {
            enabled = true;
            retain = {
              days = 3;
            };
          };
        };

        basement = {
          enabled = false;
          ffmpeg = {
            inputs = [
              {
                path = "rtsp://user:pass@192.168.68.106:554/stream1";
                roles = [ "record" ];
              }
            ];
          };
          detect = {
            enabled = false;
          };
          record = {
            enabled = true;
            retain = {
              days = 3;
            };
          };
        };
      };
    };
  };

  # Tmpfiles rules for directories
  systemd.tmpfiles.rules = lib.mkIf config.services.frigate.enable [
    "d /mnt/cameras 0755 frigate frigate -"
    "d /mnt/cameras/recordings 0755 frigate frigate -"
    "d /mnt/cameras/clips 0755 frigate frigate -"
    "d /var/lib/frigate 0755 frigate frigate -"
  ];

  # Open firewall ports
  networking.firewall.allowedTCPPorts = lib.mkIf config.services.frigate.enable [
    5000 # Frigate web UI
    8554 # RTSP restream
    8555 # WebRTC
  ];

  # Service dependencies - wait for storage and secrets
  systemd.services.frigate = lib.mkIf config.services.frigate.enable {
    after = [
      "zfs-mount.service"
      "network-online.target"
      "sops-nix.service"
    ];
    requires = [ "zfs-mount.service" ];
    wants = [ "network-online.target" ];
  };
}
