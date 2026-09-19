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

let
  # Detection model location. This must stay under /var/lib/frigate (the
  # persisted, nightly-backed-up ZFS dataset): /var/cache is rolled back by
  # impermanence on reboot, which deletes anything placed there by hand.
  # /var/lib/frigate is also what Frigate's docs call /config, making
  # model_cache here the documented location.
  detectionModelPath = "/var/lib/frigate/model_cache/yolov8s.onnx";

  # Tapo camera addresses. Each camera yields these streams:
  #   <name>_main - record and live view, plus an on-demand opus
  #                 transcode (the cameras produce PCMA audio, which MSE
  #                 playback cannot decode)
  #   <name>_sub  - detection (RTSP low-res)
  #   <name>_talk - two-way talk (tapo:// only), for cameras not listed
  #                 in tapoMainCameras. Frigate shows the mic button only
  #                 for streams whose go2rtc producer currently reports
  #                 an "audio, sendonly" backchannel. go2rtc dials
  #                 sources lazily and forgets their tracks when idle, so
  #                 the tapo source needs a stream of its own that
  #                 viewing forces go2rtc to connect - and the button
  #                 still only shows up reliably when the producer is
  #                 already running (select the stream, then reload).
  cameraHosts = {
    driveway = "192.168.68.88";
    front_door = "192.168.68.86";
    garage = "192.168.68.66";
    backyard_side_gate = "192.168.68.52";
    backyard_charger = "192.168.68.58";
  };

  # Cameras whose main stream is sourced from tapo:// instead of RTSP.
  # Frigate's recorder consumes the main stream around the clock, which
  # keeps the tapo producer connected, so its two-way-audio backchannel
  # is always visible to Frigate: the mic button appears directly on the
  # Main live stream, with none of the _talk stream's warm-up dance.
  # The cost is that recording depends on TP-Link's proprietary protocol
  # instead of RTSP (RTSP remains as a fallback source). Trialing on
  # front_door only - prove recording stays stable there before
  # extending to other cameras.
  tapoMainCameras = [ "front_door" ];

  # The stream list is rendered twice because go2rtc and Frigate expand
  # environment variables with different syntaxes (${VAR} vs {VAR}):
  # go2rtc gets the real sources it connects to, and Frigate gets a mirror
  # so its live view knows the restreams exist - without it Frigate shows
  # "Restreaming is not enabled" and falls back to low-res jsmpeg with no
  # audio or two-way talk.
  mkStreams =
    wrap:
    lib.concatMapAttrs (
      name: host:
      let
        rtspMain = "rtsp://${wrap "FRIGATE_CAM_USER"}:${wrap "FRIGATE_CAM_PASS"}@${host}:554/stream1";
        tapo = "tapo://${wrap "FRIGATE_TAPO_PASS"}@${host}";
        tapoMain = lib.elem name tapoMainCameras;
      in
      {
        "${name}_main" =
          (
            if tapoMain then
              [
                tapo
                rtspMain
              ]
            else
              [ rtspMain ]
          )
          ++ [ "ffmpeg:${name}_main#audio=opus" ];
        "${name}_sub" = "rtsp://${wrap "FRIGATE_CAM_USER"}:${wrap "FRIGATE_CAM_PASS"}@${host}:554/stream2";
      }
      // lib.optionalAttrs (!tapoMain) { "${name}_talk" = tapo; }
    ) cameraHosts;

  go2rtcStreams = mkStreams (var: "\${${var}}");
  frigateGo2rtcStreams = mkStreams (var: "{${var}}");
in
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
    # TP-Link cloud account password, used by go2rtc's tapo:// source for
    # two-way audio. Auth happens directly against the camera on the LAN
    # (the camera stores a hash of the cloud password), so cloud 2FA does
    # not apply and nothing is sent to TP-Link.
    "tapo_cloud_pass" = {
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
        FRIGATE_TAPO_PASS=${config.sops.placeholder."tapo_cloud_pass"}
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

      # Object detection via ONNX on CPU
      # ROCm inference combined with VAAPI decode causes GPU context resets
      # on the Radeon 780M iGPU after ~5 days. VAAPI decode is kept (saves
      # more CPU) while inference runs on CPU (~18ms, acceptable).
      detectors = {
        onnx = {
          type = "onnx";
          device = "CPU";
        };
      };

      # YOLOv8s ONNX model (320x320, exported via ultralytics):
      #   nix shell --impure --expr \
      #     'with import <nixpkgs> {}; python3.withPackages (p: [ p.ultralytics p.onnx ])' \
      #     -c yolo export model=yolov8s.pt format=onnx imgsz=320
      # model_type "yolo-generic" supports v3/v4/v7/v8/v9 architectures
      model = {
        path = detectionModelPath;
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
          days = 7;
          mode = "motion";
        };
        alerts = {
          retain = {
            days = 36500;
            mode = "motion";
          };
        };
        detections = {
          retain = {
            days = 30;
            mode = "active_objects";
          };
        };
      };

      # Snapshot configuration
      snapshots = {
        enabled = true;
        bounding_box = true;
        retain = {
          default = 36500;
        };
      };

      # Detection: stop tracking stationary objects after 5 minutes
      # Prevents duplicate events from parked cars or idle objects
      detect = {
        stationary = {
          # frames without movement before marked stationary
          # 1500 frames = 5 min at 5 fps (5 min × 60 s × 5 fps)
          threshold = 1500;
          # frequency for running detection on stationary objects
          # 432000 frames = 24 h at 5 fps (24 h × 3600 s × 5 fps)
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
            max_area = 200000;
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
      # ui = {
      #   live_mode = "webrtc";
      #   timezone = "America/Los_Angeles";
      # };

      # Mirror of the go2rtc stream list (see mkStreams above). The actual
      # go2rtc process is configured by services.go2rtc below; Frigate only
      # reads this to offer the restreams in live view.
      go2rtc = {
        streams = frigateGo2rtcStreams;
      };

      # Camera configurations
      # Credentials injected via environment variables from SOPS:
      #   {FRIGATE_CAM_USER} - Camera RTSP username
      #   {FRIGATE_CAM_PASS} - Camera RTSP password
      # TP-Link Tapo C120 streams:
      #   stream1 = Main stream (2K/1080p for recording)
      #   stream2 = Sub stream (360p for detection)
      cameras = {
        driveway = {
          enabled = true;
          ffmpeg = {
            inputs = [
              {
                path = "rtsp://127.0.0.1:8554/driveway_main";
                input_args = "preset-rtsp-restream";
                roles = [ "record" ];
              }
              {
                path = "rtsp://127.0.0.1:8554/driveway_sub";
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
              days = 7;
              mode = "motion";
            };
          };
          snapshots = {
            enabled = true;
          };
          live = {
            streams = {
              Main = "driveway_main";
              Sub = "driveway_sub";
              "Two-way talk" = "driveway_talk";
            };
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
                path = "rtsp://127.0.0.1:8554/front_door_main";
                input_args = "preset-rtsp-restream";
                roles = [ "record" ];
              }
              {
                path = "rtsp://127.0.0.1:8554/front_door_sub";
                input_args = "preset-rtsp-restream";
                roles = [ "detect" ];
              }
            ];
          };
          detect = {
            enabled = true;
            width = 640;
            height = 360;
            fps = 10;
            stationary = {
              # 3000 frames = 5 min at 10 fps (5 min × 60 s × 10 fps)
              threshold = 3000;
              # 864000 frames = 24 h at 10 fps (24 h × 3600 s × 10 fps)
              interval = 864000;
            };
          };
          record = {
            enabled = true;
            retain = {
              days = 7;
              mode = "motion";
            };
          };
          snapshots = {
            enabled = true;
          };
          live = {
            # Main is tapo-sourced (see tapoMainCameras), so two-way talk
            # is available on it directly - no separate talk stream.
            streams = {
              Main = "front_door_main";
              Sub = "front_door_sub";
            };
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
            inputs = [
              {
                path = "rtsp://127.0.0.1:8554/garage_main";
                input_args = "preset-rtsp-restream";
                roles = [ "record" ];
              }
              {
                path = "rtsp://127.0.0.1:8554/garage_sub";
                input_args = "preset-rtsp-restream";
                roles = [ "detect" ];
              }
            ];
          };
          detect = {
            enabled = true;
            width = 640;
            height = 360;
            fps = 10;
            stationary = {
              # 3000 frames = 5 min at 10 fps (5 min × 60 s × 10 fps)
              threshold = 3000;
              # 864000 frames = 24 h at 10 fps (24 h × 3600 s × 10 fps)
              interval = 864000;
            };
          };
          record = {
            enabled = true;
            retain = {
              days = 7;
              mode = "motion";
            };
          };
          snapshots = {
            enabled = true;
          };
          live = {
            streams = {
              Main = "garage_main";
              Sub = "garage_sub";
              "Two-way talk" = "garage_talk";
            };
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

        backyard_side_gate = {
          enabled = true;
          ffmpeg = {
            inputs = [
              {
                path = "rtsp://127.0.0.1:8554/backyard_side_gate_main";
                input_args = "preset-rtsp-restream";
                roles = [ "record" ];
              }
              {
                path = "rtsp://127.0.0.1:8554/backyard_side_gate_sub";
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
              days = 7;
              mode = "motion";
            };
          };
          snapshots = {
            enabled = true;
          };
          live = {
            streams = {
              Main = "backyard_side_gate_main";
              Sub = "backyard_side_gate_sub";
              "Two-way talk" = "backyard_side_gate_talk";
            };
          };
          zones = {
            backyard_side_gate_zone = {
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
              required_zones = [ "backyard_side_gate_zone" ];
            };
          };
        };

        backyard_charger = {
          enabled = true;
          ffmpeg = {
            inputs = [
              {
                path = "rtsp://127.0.0.1:8554/backyard_charger_main";
                input_args = "preset-rtsp-restream";
                roles = [ "record" ];
              }
              {
                path = "rtsp://127.0.0.1:8554/backyard_charger_sub";
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
              days = 7;
              mode = "motion";
            };
          };
          snapshots = {
            enabled = true;
          };
          live = {
            streams = {
              Main = "backyard_charger_main";
              Sub = "backyard_charger_sub";
              "Two-way talk" = "backyard_charger_talk";
            };
          };
          zones = {
            backyard_charger_zone = {
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
              required_zones = [ "backyard_charger_zone" ];
            };
          };
        };
      };
    };
  };

  # go2rtc streaming server - single RTSP connection per camera, restreamed
  # internally so Frigate's record and detect roles share one connection.
  # Tapo cameras have a low concurrent-connection limit; this prevents
  # instability from multiple ffmpeg processes connecting simultaneously.
  #
  # Credentials come from the shared frigate.env via EnvironmentFile so no
  # separate SOPS template is needed.
  #
  # The _talk streams use tapo://, TP-Link's proprietary protocol, which
  # carries the audio backchannel the RTSP streams lack. It enables
  # two-way talk from Frigate's WebRTC live view (browser mic requires
  # HTTPS, which Caddy provides). Auth is the TP-Link cloud account
  # password, verified locally by the camera - nothing talks to the cloud.
  services.go2rtc = lib.mkIf config.services.frigate.enable {
    enable = true;
    settings.streams = go2rtcStreams;
  };

  # Override go2rtc service: run as frigate user so it can read frigate.env,
  # and wait for SOPS secrets before starting.
  systemd.services.go2rtc = lib.mkIf config.services.frigate.enable {
    after = [ "sops-nix.service" ];
    wants = [ "sops-nix.service" ];
    serviceConfig = {
      DynamicUser = lib.mkForce false;
      User = lib.mkForce "frigate";
      Group = lib.mkForce "frigate";
      EnvironmentFile = config.sops.templates."frigate.env".path;
    };
  };

  # Tmpfiles rules for directories
  systemd.tmpfiles.rules = lib.mkIf config.services.frigate.enable [
    "d /mnt/cameras 0755 frigate frigate -"
    "d /mnt/cameras/recordings 0755 frigate frigate -"
    "d /mnt/cameras/clips 0755 frigate frigate -"
    "d /var/lib/frigate 0755 frigate frigate -"
    "d /var/lib/frigate/model_cache 0755 frigate frigate -"
    "L+ /var/lib/frigate/recordings - - - - /mnt/cameras/recordings"
    "L+ /var/lib/frigate/clips - - - - /mnt/cameras/clips"
  ];

  # Open firewall ports
  networking.firewall.allowedTCPPorts = lib.mkIf config.services.frigate.enable [
    80 # Frigate web UI (nginx serves on port 80)
    8554 # RTSP restream
    8555 # WebRTC
  ];
  # WebRTC negotiates UDP first and only falls back to TCP; without this
  # port live view and two-way talk depend on the flakier TCP path.
  networking.firewall.allowedUDPPorts = lib.mkIf config.services.frigate.enable [
    8555 # WebRTC
  ];

  # Service dependencies - wait for MQTT broker, storage, and secrets
  systemd.services.frigate = lib.mkIf config.services.frigate.enable {
    after = [
      "mosquitto.service"
      "go2rtc.service"
      "zfs-mount.service"
      "network-online.target"
      "sops-nix.service"
    ];
    requires = [
      "mosquitto.service"
      "go2rtc.service"
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
      # Startup imports stay safe without a local overlay: since 26.05 nixpkgs
      # applies its own ai-edge-litert patch, so Frigate's TFLite modules import
      # ai_edge_litert (on PYTHONPATH) rather than tensorflow.
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
      Restart = "on-failure";
      RestartSec = 10;
      # Refuse to start without the detection model. A missing model does not
      # stop Frigate: the detector subprocess dies while cameras keep
      # streaming, so detection is silently gone and recordings degrade.
      # Failing the unit makes the problem loud and alertable instead.
      ExecStartPre = pkgs.writeShellScript "frigate-require-model" ''
        if [ ! -s "${detectionModelPath}" ]; then
          echo "detection model ${detectionModelPath} is missing or empty" >&2
          echo "regenerate it with the yolo export command in modules/automation/frigate.nix" >&2
          exit 1
        fi
      '';
    };
  };
}
