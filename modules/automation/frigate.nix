# SPDX-License-Identifier: GPL-3.0-or-later

# Frigate NVR configuration for security cameras
# Provides AI-powered object detection with Home Assistant integration
#
# Camera credentials are injected via SOPS secrets using Frigate's
# environment variable substitution: {FRIGATE_CAM_USER}, {FRIGATE_CAM_PASS}
{
  config,
  lib,
  pkgs,
  ...
}:

{
  # SOPS secrets for camera credentials (only when Frigate is enabled)
  sops.secrets = lib.mkIf config.services.frigate.enable {
    # RTSP camera account credentials
    "frigate_cam_user" = {
      owner = "root";
      group = "root";
      mode = "0600";
    };
    "frigate_cam_pass" = {
      owner = "root";
      group = "root";
      mode = "0600";
    };
  };

  # SOPS template for Frigate environment file
  sops.templates = lib.mkIf config.services.frigate.enable {
    "frigate.env" = {
      content = ''
        FRIGATE_CAM_USER=${config.sops.placeholder."frigate_cam_user"}
        FRIGATE_CAM_PASS=${config.sops.placeholder."frigate_cam_pass"}
      '';
      owner = "frigate";
      group = "frigate";
      mode = "0600";
    };
  };

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
        path = "${pkgs.ffmpeg-headless}";
        hwaccel_args = "preset-vaapi";
        output_args = {
          record = "preset-record-generic-audio-aac";
        };
      };

      # Object detection via ONNX with ROCm on AMD GPU (Radeon 780M)
      # Hangs mitigated by: amdgpu.cwsr_enable=0 (kernel) + HSA_ENABLE_SDMA=0 (env)
      detectors = {
        onnx = {
          type = "onnx";
        };
      };

      # YOLOv8s ONNX model (320x320, exported via ultralytics)
      # model_type "yolo-generic" supports v3/v4/v7/v8/v9 architectures
      model = {
        path = "/var/cache/frigate/model_cache/yolov8s.onnx";
        model_type = "yolo-generic";
        width = 320;
        height = 320;
        input_tensor = "nchw";
        input_dtype = "float";
        labelmap_path = "${pkgs.frigate}/share/frigate/labelmap.txt";
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
        bounding_box = true;
        retain = {
          default = 30;
        };
      };

      # Detection: stop tracking stationary objects after 5 minutes
      # Prevents duplicate events from parked cars or idle objects
      detect = {
        stationary = {
          # frames without movement before marked stationary
          # 300 frames is a 5 minute stationary period for a 5 fps detection rate (5 m = 300 frames / 5 fps / 60 s)
          threshold = 300;
          # interval is defined as the frequency for running detection on stationary objects.
          # 432000 frames is a 24h interval for 5 fps detection rate (24 hr = 432000 frames / 5 fps / 60 s / 60 m)
          interval = 432000;
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

      # Disable TLS - Caddy handles HTTPS externally
      tls = {
        enabled = false;
      };

      # Auth disabled - Frigate is behind Tailscale
      auth = {
        enabled = false;
      };

      # UI configuration
      ui = {
        live_mode = "webrtc";
        timezone = "America/Los_Angeles";
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
      # Credentials injected via environment variables from SOPS:
      #   {FRIGATE_CAM_USER} - Camera RTSP username
      #   {FRIGATE_CAM_PASS} - Camera RTSP password
      # TP-Link Tapo C120 streams:
      #   stream1 = Main stream (2K/1080p for recording)
      #   stream2 = Sub stream (360p for detection)
      cameras = {
        # OUTDOOR CAMERAS (4x) - Detection enabled, 5-day retention
        driveway = {
          enabled = true;
          ffmpeg = {
            inputs = [
              {
                path = "rtsp://{FRIGATE_CAM_USER}:{FRIGATE_CAM_PASS}@192.168.68.86:554/stream1";
                roles = [ "record" ];
              }
              {
                path = "rtsp://{FRIGATE_CAM_USER}:{FRIGATE_CAM_PASS}@192.168.68.86:554/stream2";
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
          zones = {
            driveway_zone = {
              # PLACEHOLDER: Replace with actual coordinates from Frigate UI zone editor
              coordinates = "0.05,0.30,0.95,0.30,0.95,0.95,0.05,0.95";
              objects = [
                "person"
                "car"
                "package"
              ];
              inertia = 3;
            };
          };
          review = {
            alerts = {
              required_zones = [ "driveway_zone" ];
            };
          };
        };

        front_door = {
          enabled = true;
          ffmpeg = {
            inputs = [
              {
                path = "rtsp://{FRIGATE_CAM_USER}:{FRIGATE_CAM_PASS}@192.168.68.64:554/stream1";
                roles = [ "record" ];
              }
              {
                path = "rtsp://{FRIGATE_CAM_USER}:{FRIGATE_CAM_PASS}@192.168.68.64:554/stream2";
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
          zones = {
            front_door_zone = {
              # PLACEHOLDER: Replace with actual coordinates from Frigate UI zone editor
              coordinates = "0.10,0.35,0.90,0.35,0.90,0.90,0.10,0.90";
              objects = [
                "person"
                "package"
              ];
              inertia = 3;
            };
          };
          review = {
            alerts = {
              required_zones = [ "front_door_zone" ];
            };
          };
        };

        garage = {
          enabled = true;
          ffmpeg = {
            # Use TCP transport for stability with Tapo cameras
            # See: https://github.com/blakeblackshear/frigate/discussions/14888
            inputs = [
              {
                path = "rtsp://{FRIGATE_CAM_USER}:{FRIGATE_CAM_PASS}@192.168.68.66:554/stream1";
                input_args = "preset-rtsp-restream";
                roles = [ "record" ];
              }
              {
                path = "rtsp://{FRIGATE_CAM_USER}:{FRIGATE_CAM_PASS}@192.168.68.66:554/stream2";
                input_args = "preset-rtsp-restream";
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
          zones = {
            garage_zone = {
              # PLACEHOLDER: Replace with actual coordinates from Frigate UI zone editor
              coordinates = "0.10,0.25,0.90,0.25,0.90,0.90,0.10,0.90";
              objects = [
                "person"
                "car"
                "package"
              ];
              inertia = 3;
            };
          };
          review = {
            alerts = {
              required_zones = [ "garage_zone" ];
            };
          };
        };

        side_gate = {
          enabled = false;
          ffmpeg = {
            inputs = [
              {
                path = "rtsp://{FRIGATE_CAM_USER}:{FRIGATE_CAM_PASS}@192.168.68.104:554/stream1";
                roles = [ "record" ];
              }
              {
                path = "rtsp://{FRIGATE_CAM_USER}:{FRIGATE_CAM_PASS}@192.168.68.104:554/stream2";
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
                path = "rtsp://{FRIGATE_CAM_USER}:{FRIGATE_CAM_PASS}@192.168.68.105:554/stream1";
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
                path = "rtsp://{FRIGATE_CAM_USER}:{FRIGATE_CAM_PASS}@192.168.68.106:554/stream1";
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
    80 # Frigate web UI (nginx serves on port 80)
    8554 # RTSP restream
    8555 # WebRTC
  ];

  # Service dependencies - wait for MQTT broker, storage, and secrets
  systemd.services.frigate = lib.mkIf config.services.frigate.enable {
    after = [
      "mosquitto.service"
      "zfs-mount.service"
      "network-online.target"
      "sops-nix.service"
    ];
    requires = [
      "mosquitto.service"
      "zfs-mount.service"
    ];
    wants = [ "network-online.target" ];

    environment = {
      # Radeon 780M is gfx1103 (RDNA 3 iGPU), not officially supported
      # Override to gfx1100 (RX 7900 XT) which has compatible ISA
      HSA_OVERRIDE_GFX_VERSION = "11.0.0";
      # Use blit kernels instead of SDMA hardware for memory copies on APU.
      # On Infinity Fabric shared memory, this improves stability and bandwidth.
      HSA_ENABLE_SDMA = "0";
      # MIGraphX optimization flags (from Frigate's ROCm Dockerfile)
      MIGRAPHX_DISABLE_MIOPEN_FUSION = "1";
      MIGRAPHX_DISABLE_SCHEDULE_PASS = "1";
      MIGRAPHX_DISABLE_REDUCE_FUSION = "1";
      MIGRAPHX_ENABLE_HIPRTC_WORKAROUNDS = "1";
      # Prevent transformers library from importing tensorflow
      USE_TF = "0";
      # Remove tensorflow from PYTHONPATH to prevent protobuf
      # symbol collision with onnxruntime. tensorflow statically
      # links protobuf into libtensorflow_framework.so.2; when
      # loaded alongside onnxruntime (dynamic libprotobuf.so),
      # the competing symbols cause segfaults in forked detectors.
      # Build a clean PYTHONPATH: remove tensorflow (protobuf collision)
      # and fix frigate's self-reference (overrideAttrs doesn't update
      # the pythonPath passthru attribute's self-reference).
      PYTHONPATH = lib.mkForce (
        let
          paths = lib.splitString ":" pkgs.frigate.pythonPath;
          frigateSitePackages = "${pkgs.frigate}/${pkgs.frigate.python.sitePackages}";
          fixed = map (p: if lib.hasInfix "frigate-" p then frigateSitePackages else p) paths;
          filtered = builtins.filter (p: !(lib.hasInfix "tensorflow-" p)) fixed;
        in
        builtins.concatStringsSep ":" filtered
      );
    };

    serviceConfig = {
      EnvironmentFile = config.sops.templates."frigate.env".path;
    };
  };
}
