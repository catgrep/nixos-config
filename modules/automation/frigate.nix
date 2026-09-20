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

  # YOLOv8 uses 80 contiguous class IDs; the packaged default uses COCO-91
  # class ordering and would interpret cats as birds and dogs as cats.
  detectionLabelmap = pkgs.runCommand "frigate-coco-80-labelmap.txt" { } ''
    cp ${pkgs.frigate.src}/docker/main/rootfs/labelmap/coco-80.txt "$out"
  '';

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
    front_door = "192.168.68.64";
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

  yamlFormat = pkgs.formats.yaml { };

  # "backyard_side_gate" -> "Backyard Side Gate"
  homekitCameraName = name: lib.concatMapStringsSep " " lib.toSentenceCase (lib.splitString "_" name);

  # Apple Home export: go2rtc advertises every camera's _main stream as a
  # native HomeKit accessory. The cameras' H264 video passes through
  # unmodified and the opus transcode above satisfies HomeKit's OPUS-only
  # audio requirement. The integration is live view with listen-only
  # audio: go2rtc implements neither a motion sensor nor HomeKit Secure
  # Video recording, and its HomeKit output has no return-audio path, so
  # recordings stay in Frigate and two-way talk stays in Frigate's WebRTC
  # live view.
  #
  # Accessory identity (device id, device key, setup id) is derived
  # deterministically from the stream ID, so pairings survive restarts
  # and rebuilds without any key material here. Renaming a camera changes
  # the stream ID, which presents a brand-new accessory that must be
  # paired again in the Home app.
  homekitSettings = {
    homekit = lib.mapAttrs' (
      name: _:
      lib.nameValuePair "${name}_main" {
        # Expanded from frigate.env by go2rtc at config load. Eight
        # digits; Apple rejects trivial codes such as 12345678.
        pin = "\${FRIGATE_HOMEKIT_PIN}";
        name = homekitCameraName name;
      }
    ) cameraHosts;
  };

  # When an Apple device pairs, go2rtc records the pairing by patching
  # the first config file on its command line. The nix-generated config
  # is a read-only store path, so the homekit block lives in this
  # writable state file instead, refreshed from homekitSettings on every
  # start. It sits under /var/lib/frigate because that dataset survives
  # the impermanence rollback and rides the nightly backup, while
  # go2rtc's own /var/lib/go2rtc is wiped on reboot.
  homekitStateFile = "/var/lib/frigate/go2rtc-homekit.yaml";
  homekitDeclaredConfig = yamlFormat.generate "go2rtc-homekit.yaml" homekitSettings;

  # yq deep-merge: declared fields (pin, name) stay authoritative while
  # the pairings arrays go2rtc appended are preserved. Entries for
  # removed cameras also survive until the state file is deleted; go2rtc
  # logs a "missing stream" warning for them and carries on.
  mergeHomekitState = pkgs.writeShellScript "go2rtc-merge-homekit-state" ''
    set -euo pipefail
    if [ -s ${homekitStateFile} ]; then
      yq eval-all 'select(fileIndex == 0) * select(fileIndex == 1)' \
        ${homekitStateFile} ${homekitDeclaredConfig} > ${homekitStateFile}.next
      mv ${homekitStateFile}.next ${homekitStateFile}
    else
      install -m 0644 ${homekitDeclaredConfig} ${homekitStateFile}
    fi
  '';

  # The nixpkgs go2rtc module keeps its generated config file internal,
  # so the ExecStart override below regenerates an identical one to pass
  # alongside the writable state file.
  go2rtcConfigFile = yamlFormat.generate "go2rtc.yaml" config.services.go2rtc.settings;
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
    # HomeKit pairing PIN for go2rtc's accessory server. Kept out of the
    # repo, though its protection is thin by design: go2rtc's own API
    # shows the setup code for any accessory that is not yet paired.
    "homekit_pin" = {
      owner = "root";
      group = "root";
      mode = "0600";
    };
  };

  # SOPS template for Frigate environment file
  sops.templates = lib.mkIf config.services.frigate.enable {
    "frigate.env" = {
      # Credentials are read from the environment at service startup, so a
      # rendered-content change without a restart leaves both consumers
      # running on stale values.
      restartUnits = [
        "go2rtc.service"
        "frigate.service"
      ];
      content = ''
        FRIGATE_CAM_USER=${config.sops.placeholder."frigate_cam_user"}
        FRIGATE_CAM_PASS=${config.sops.placeholder."frigate_cam_pass"}
        FRIGATE_TAPO_PASS=${config.sops.placeholder."tapo_cloud_pass"}
        FRIGATE_HOMEKIT_PIN=${config.sops.placeholder."homekit_pin"}
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
        labelmap_path = "${detectionLabelmap}";
      };

      # Recording configuration (global defaults)
      record = {
        enabled = true;
        retain = {
          days = 7;
          mode = "motion";
        };
        # Alert footage is the largest unbounded growth source (~2-3G/day
        # accumulated before zones were tightened); 180 days keeps it well
        # inside the 600G quota of backup/cameras/recordings.
        alerts = {
          retain = {
            days = 180;
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
      # Snapshot retention matches alert retention - a snapshot has little
      # value once its alert footage is gone.
      snapshots = {
        enabled = true;
        bounding_box = true;
        retain = {
          default = 180;
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

      # With auth disabled, every request gets this role. Frigate 0.16+
      # falls back to viewer otherwise, which hides all admin UI
      # (settings, config editor, motion tuner).
      proxy = {
        default_role = "admin";
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
      #
      # Zone and motion-mask polygons are drawn in the Frigate UI, which
      # saves them to /run/frigate/frigate.yml - a tmpfs copy that every
      # deploy or service restart regenerates from this file. Copy UI
      # edits back here or they are lost.
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
              coordinates = "0.079,0.027,0.989,0.033,1,0.611,0.292,1";
              objects = [
                "person"
                "car"
              ];
              inertia = 3;
            };
          };
          motion = {
            mask = "0.025,0.163,0.118,0.118,0.207,0.183,0.313,0.12,0.325,0.012,0.005,0.006";
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
            # Main is tapo-sourced (see tapoMainCameras), so two-way talk
            # is available on it directly - no separate talk stream.
            streams = {
              Main = "front_door_main";
              Sub = "front_door_sub";
            };
          };
          zones = {
            front_door_zone = {
              coordinates = "0.013,0.189,0.919,0.034,0.97,0.835,0.105,0.988";
              objects = [
                "person"
                "dog"
                "cat"
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
              Main = "garage_main";
              Sub = "garage_sub";
              "Two-way talk" = "garage_talk";
            };
          };
          zones = {
            garage_zone = {
              coordinates = "0.144,0,1,0,1,1,0.158,1";
              objects = [
                "person"
                "car"
                "dog"
                "cat"
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
              coordinates = "0.053,0.023,0.953,0.023,0.833,0.829,0.428,0.982,0.114,0.361";
              objects = [
                "person"
                "dog"
                "cat"
              ];
              inertia = 3;
            };
          };
          motion = {
            mask = [
              "0.181,0.157,0.258,0.253,0.288,0.452,0.281,0.974,0.097,0.959,0.013,0.495"
              "0.811,0.986,0.994,0.568,0.998,0.994"
              "0.853,0.014,0.993,0.546,0.997,0.014"
            ];
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
              coordinates = "0.336,0.011,0.819,0.035,0.671,0.932,0.195,0.915";
              objects = [
                "person"
                "car"
                "cat"
                "dog"
              ];
              inertia = 3;
            };
          };
          motion = {
            mask = "0.717,0.874,0.829,0.841,0.937,0.809,0.935,0.301,0.782,0.254,0.689,0.446";
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
    after = [
      "sops-nix.service"
      # The HomeKit pairing state lives on the /var/lib/frigate dataset.
      "zfs-mount.service"
    ];
    wants = [ "sops-nix.service" ];
    requires = [ "zfs-mount.service" ];
    path = [
      pkgs.coreutils
      pkgs.yq-go
    ];
    serviceConfig = {
      DynamicUser = lib.mkForce false;
      User = lib.mkForce "frigate";
      Group = lib.mkForce "frigate";
      EnvironmentFile = config.sops.templates."frigate.env".path;
      ExecStartPre = "${mergeHomekitState}";
      # The upstream unit passes only the store config. HomeKit pairing
      # persistence needs the writable state file first on the command
      # line, because the first config file is the one go2rtc patches.
      ExecStart = lib.mkForce "${config.services.go2rtc.package}/bin/go2rtc -config ${homekitStateFile} -config ${go2rtcConfigFile}";
    };
  };

  # Tmpfiles rules for directories
  systemd.tmpfiles.rules = lib.mkIf config.services.frigate.enable [
    "d /mnt/cameras 0755 frigate frigate -"
    "d /mnt/cameras/recordings 0755 frigate frigate -"
    "d /mnt/cameras/clips 0755 frigate frigate -"
    # 0750, matching the frigate module's StateDirectoryMode -- a 0755
    # rule here would be cosmetic and get re-stamped on every start.
    "d /var/lib/frigate 0750 frigate frigate -"
    "d /var/lib/frigate/model_cache 0755 frigate frigate -"
    "L+ /var/lib/frigate/recordings - - - - /mnt/cameras/recordings"
    "L+ /var/lib/frigate/clips - - - - /mnt/cameras/clips"
  ];

  # Open firewall ports
  networking.firewall.allowedTCPPorts = lib.mkIf config.services.frigate.enable [
    80 # Frigate web UI (nginx serves on port 80)
    8554 # RTSP restream
    8555 # WebRTC
    # go2rtc API port; the HomeKit accessory protocol is served on it,
    # so Apple devices must be able to reach it. This also exposes the
    # unauthenticated go2rtc admin API to the LAN, consistent with
    # Frigate's own auth-disabled UI on port 80.
    1984
  ];
  # WebRTC negotiates UDP first and only falls back to TCP; without this
  # port live view and two-way talk depend on the flakier TCP path.
  # HomeKit discovery also needs mDNS (UDP 5353), which Avahi's default
  # openFirewall already opens on this host.
  networking.firewall.allowedUDPPorts = lib.mkIf config.services.frigate.enable [
    8555 # WebRTC
    8443 # HomeKit media (SRTP from go2rtc to Apple devices)
  ];

  # Units this module keeps running continuously, published to the
  # Prometheus alerting policy. nginx exists on ser8 solely as Frigate's
  # web frontend (see the frigate NixOS module), so it shares this guard.
  homelab.monitoring.systemd.units = lib.mkIf config.services.frigate.enable {
    "frigate.service".expectedRunning = true;
    "go2rtc.service".expectedRunning = true;
    "nginx.service".expectedRunning = true;
  };

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
