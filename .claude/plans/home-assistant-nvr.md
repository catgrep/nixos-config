# Home Assistant NVR Security Camera System Design

## Executive Summary

This document describes the architecture for a Home Assistant-based security camera system on ser8, using Frigate NVR for AI-powered object detection with 6x TP-Link Tapo C120 cameras. The design leverages ser8's AMD Radeon 780M iGPU (VA-API) for hardware-accelerated video decoding, the RAIDZ2 backup pool for camera storage, and integrates with the existing Prometheus/Grafana monitoring stack.

**Camera Configuration:**
- **4 outdoor cameras**: AI object detection enabled (person, car, package), 5-day continuous retention
- **2 indoor cameras**: Recording/streaming only (no detection), 3-day retention
- **Resolution**: 1080p (vs 2K) to reduce storage and drive wear
- **Detection events**: 30-day retention for all detected objects

## Problem Statement

1. No security camera system currently exists in the homelab
2. 6x TP-Link Tapo C120 cameras need integration with NVR capabilities
3. The backup pool on ser8 is suitable for camera storage
4. Need AI-based object detection on outdoor cameras to reduce false positives
5. Retention requirements: 5 days continuous (outdoor), 3 days (indoor), 30 days detection events

## Architecture Overview

```
                              +-----------------------+
                              |    Caddy Gateway      |
                              |     (firebat)         |
                              +----------+------------+
                                         |
                    +--------------------+--------------------+
                    |                    |                    |
           +--------v--------+  +--------v--------+  +--------v--------+
           | frigate.vofi    |  | hass.vofi       |  | (existing)      |
           | RTSP/WebRTC     |  | Home Assistant  |  | jellyfin, etc.  |
           +-----------------+  +-----------------+  +-----------------+
                    |                    |
                    +----------+---------+
                               |
                    +----------v----------+
                    |       ser8          |
                    |  +--------------+   |
                    |  |   Frigate    |   |
                    |  |   (NVR)      |   |
                    |  +------+-------+   |
                    |         |           |
                    |  +------v-------+   |
                    |  |Home Assistant|   |
                    |  +--------------+   |
                    |         |           |
                    |  +------v-------+   |
                    |  | ZFS backup   |   |
                    |  | (RAIDZ2)     |   |
                    |  | 6x4TB HDDs   |   |
                    +--+--------------+---+
                               |
            +------------------+------------------+
            |         |        |        |        |
         +--v--+   +--v--+  +--v--+  +--v--+  ...
         |C120 |   |C120 |  |C120 |  |C120 |
         |  1  |   |  2  |  |  3  |  |  4  |
         +-----+   +-----+  +-----+  +-----+
             (6x cameras, RTSP streams)
```

## Hardware Specifications

### Cameras: TP-Link Tapo C120

| Specification | Value |
|--------------|-------|
| Resolution | 2K (2560x1440) |
| Frame Rate | Up to 15fps (to NVR) |
| Compression | H.264 |
| RTSP Port | 554 |
| ONVIF Port | 2020 |
| ONVIF Profile | Profile S |
| Stream URLs | `/stream1` (high), `/stream2` (low) |
| SD Card Slot | Yes (256GB each) |

**RTSP URL Format:**
```
rtsp://username:password@<camera_ip>:554/stream1  # 2560x1440
rtsp://username:password@<camera_ip>:554/stream2  # 640x360
```

### ser8 Relevant Hardware

| Component | Specification | Purpose |
|-----------|---------------|---------|
| CPU | AMD Ryzen 7 8845HS | General processing |
| iGPU | AMD Radeon 780M (RDNA3) | Note: Not Intel QuickSync |
| RAM | 64GB DDR5 | Shared with Frigate |
| NVMe | 1TB CT1000P3PSSD8 | System, temp recordings |
| Media HDDs | 2x12TB (MergerFS) | Jellyfin/media content |
| Backup HDDs | 6x4TB (RAIDZ2) | **Camera storage** |

**Correction:** ser8 uses AMD Ryzen, not Intel. The iGPU is AMD Radeon 780M with RDNA3 architecture. Frigate supports AMD VA-API for hardware acceleration.

## Storage Design

### Capacity Analysis

**RAIDZ2 Pool (6x4TB):**
- Raw capacity: 24TB
- Usable capacity (RAIDZ2): ~16TB (2 disks parity)
- Reserved for ZFS overhead: ~1TB
- Available for cameras: **~15TB**

### Storage Calculations

**Per-Camera Daily Storage (1080p, H.264, 15fps continuous):**

| Quality | Resolution | Bitrate | Daily GB | Notes |
|---------|------------|---------|----------|-------|
| High (stream1) | 1920x1080 | ~2 Mbps | ~21 GB | Continuous recording |
| Low (stream2) | 640x360 | ~0.5 Mbps | ~5.4 GB | Detection analysis |

**Note:** Using 1080p instead of 2K reduces storage by 50% and extends drive lifespan.

**Total Daily Storage:**

| Camera Type | Count | Daily Storage | Retention | Total |
|-------------|-------|---------------|-----------|-------|
| Outdoor (detection) | 4 | 4 × 21 GB = 84 GB | 5 days | **420 GB** |
| Indoor (no detection) | 2 | 2 × 21 GB = 42 GB | 3 days | **126 GB** |
| Detection events | 4 | ~10-15 GB/day | 30 days | **~400 GB** |
| **Total Required** | - | - | - | **~1 TB** |

**Conclusion:** ~1TB total storage requirement, well within the backup pool's capacity.

### ZFS Dataset Structure

```nix
# Proposed dataset structure within backup pool
zpool.backup.datasets = {
  "cameras" = {
    type = "zfs_fs";
    options = {
      mountpoint = "/mnt/cameras";
      compression = "lz4";
      recordsize = "1M";        # Optimal for video files
      atime = "off";            # Reduce write overhead
      xattr = "sa";
      acltype = "posixacl";
    };
  };
  "cameras/recordings" = {
    type = "zfs_fs";
    options = {
      mountpoint = "/mnt/cameras/recordings";
      quota = "600G";           # ~1TB with headroom
    };
  };
  "cameras/clips" = {
    type = "zfs_fs";
    options = {
      mountpoint = "/mnt/cameras/clips";
      quota = "600G";           # Detection events
    };
  };
};
```

### SD Card Strategy

**Recommendation: Use for edge buffering, not primary storage.**

| Use Case | Recommendation | Rationale |
|----------|---------------|-----------|
| Primary recording | No | SD cards wear out faster, slower than HDDs |
| Edge buffer | Yes | 30-60 second buffer for network interruption |
| Redundancy | Optional | Cameras can record locally if NVR is down |

**Frigate Configuration for SD Cards:**
The cameras' SD cards can provide a fallback recording mechanism. If the RTSP stream to Frigate drops, the camera continues recording locally. This is configured in the Tapo app, not Frigate.

## NixOS Module Design

### Module Structure

```
modules/automation/
  default.nix           # Imports all automation modules
  home-assistant.nix    # Home Assistant configuration (existing)
  frigate.nix           # NEW: Frigate NVR configuration
  mosquitto.nix         # NEW: MQTT broker (optional, HA has embedded)
```

### Frigate Module (`modules/automation/frigate.nix`)

```nix
# SPDX-License-Identifier: GPL-3.0-or-later
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.frigate;
in
{
  options.services.frigate = {
    # Extend existing options with custom ones
    storageDir = lib.mkOption {
      type = lib.types.path;
      default = "/mnt/cameras";
      description = "Base directory for Frigate recordings";
    };

    cameras = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          ip = lib.mkOption {
            type = lib.types.str;
            description = "Camera IP address";
          };
          credentialsFile = lib.mkOption {
            type = lib.types.path;
            description = "Path to file containing camera credentials";
          };
        };
      });
      default = {};
      description = "Camera configurations";
    };
  };

  config = lib.mkIf cfg.enable {
    # Frigate service configuration
    services.frigate = {
      enable = true;
      hostname = "frigate";

      # AMD VA-API driver for hardware acceleration
      # Note: ser8 has AMD Radeon 780M, not Intel
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

        # Object detection configuration
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
            days = 5;           # 5 days for outdoor cameras
            mode = "motion";
          };
          events = {
            retain = {
              default = 30;     # 30 days for detection events
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
          track = [ "person" "car" "dog" "cat" "package" ];
          filters = {
            person = {
              min_area = 5000;
              max_area = 100000;
              threshold = 0.7;
            };
          };
        };

        # Camera configurations (template - actual IPs from SOPS)
        cameras = {
          # OUTDOOR CAMERAS (4x) - Detection enabled, 5-day retention
          front_door = {
            enabled = true;
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
              retain = { days = 5; mode = "motion"; };
            };
            events = {
              retain = { default = 30; };
            };
            snapshots = {
              enabled = true;
            };
            zones = {
              front_porch = {
                coordinates = "0,360,640,360,640,200,0,200";
                objects = [ "person" "package" ];
              };
            };
          };
          # backyard, garage, driveway follow same pattern...

          # INDOOR CAMERAS (2x) - No detection, 3-day retention
          living_room = {
            enabled = true;
            ffmpeg = {
              inputs = [
                {
                  path = "rtsp://user:pass@192.168.68.105:554/stream1";
                  roles = [ "record" ];
                }
              ];
            };
            detect = {
              enabled = false;  # No AI detection for indoor cameras
            };
            record = {
              enabled = true;
              retain = { days = 3; };  # Shorter retention for indoor
            };
          };
          # basement follows same pattern...
        };

        # UI configuration
        ui = {
          live_mode = "webrtc";
          timezone = "America/Los_Angeles";
          use_experimental = false;
        };

        # go2rtc for WebRTC streaming
        go2rtc = {
          streams = {
            front_door = [
              "rtsp://user:pass@192.168.68.101:554/stream1"
            ];
          };
          webrtc = {
            candidates = [
              "192.168.68.65:8555"
              "stun:8555"
            ];
          };
        };
      };
    };

    # Ensure Frigate has access to camera storage
    systemd.tmpfiles.rules = [
      "d /mnt/cameras 0755 frigate frigate -"
      "d /mnt/cameras/continuous 0755 frigate frigate -"
      "d /mnt/cameras/events 0755 frigate frigate -"
      "d /var/lib/frigate 0755 frigate frigate -"
    ];

    # Open firewall ports
    networking.firewall.allowedTCPPorts = [
      5000  # Frigate web UI
      8554  # RTSP restream
      8555  # WebRTC
    ];

    # Add frigate user to video group for GPU access
    users.users.frigate.extraGroups = [ "video" "render" ];
  };
}
```

### Updated Home Assistant Module

The existing `home-assistant.nix` needs updates to integrate with Frigate:

```nix
# Add to extraComponents
extraComponents = [
  # ... existing components ...
  "frigate"        # Frigate NVR integration
  "stream"         # For camera streams
  "camera"         # Camera platform
  "image_processing"
];

# Add Frigate integration to config
config = {
  # ... existing config ...

  # Frigate integration
  frigate = {
    url = "http://localhost:5000";
  };

  # Camera automation examples
  automation = [
    {
      alias = "Person detected - Send notification";
      trigger = {
        platform = "mqtt";
        topic = "frigate/events";
      };
      condition = {
        condition = "template";
        value_template = "{{ trigger.payload_json['after']['label'] == 'person' }}";
      };
      action = {
        service = "notify.mobile_app";
        data = {
          title = "Person Detected";
          message = "Person detected at {{ trigger.payload_json['after']['camera'] }}";
        };
      };
    }
  ];
};
```

### SOPS Secrets Configuration

Add to `hosts/ser8/media.nix` or create `hosts/ser8/cameras.nix`:

```nix
sops.secrets = {
  # Camera credentials (shared across all cameras or per-camera)
  "camera_rtsp_username" = {
    owner = "frigate";
    group = "frigate";
    mode = "0400";
  };
  "camera_rtsp_password" = {
    owner = "frigate";
    group = "frigate";
    mode = "0400";
  };
  # Per-camera if different credentials
  "camera_front_door_password" = {
    owner = "frigate";
    group = "frigate";
    mode = "0400";
  };
};

sops.templates."frigate-cameras.yaml" = {
  content = ''
    cameras:
      front_door:
        ffmpeg:
          inputs:
            - path: rtsp://${config.sops.placeholder.camera_rtsp_username}:${config.sops.placeholder.camera_front_door_password}@192.168.68.101:554/stream1
              roles:
                - record
            - path: rtsp://${config.sops.placeholder.camera_rtsp_username}:${config.sops.placeholder.camera_front_door_password}@192.168.68.101:554/stream2
              roles:
                - detect
  '';
  owner = "frigate";
  group = "frigate";
  mode = "0400";
};
```

## Monitoring Integration

### Prometheus Configuration

Add to `modules/gateway/prometheus.nix`:

```nix
scrapeConfigs = [
  # ... existing configs ...
  {
    job_name = "frigate";
    static_configs = [
      {
        targets = [ "ser8.internal:5000" ];
      }
    ];
    scrape_interval = "30s";
    metrics_path = "/api/metrics";
  }
  {
    job_name = "home-assistant";
    static_configs = [
      {
        targets = [ "ser8.internal:8123" ];
      }
    ];
    scrape_interval = "60s";
    metrics_path = "/api/prometheus";
    # Requires long-lived access token
    authorization = {
      type = "Bearer";
      credentials_file = "/run/secrets/hass-prometheus-token";
    };
  }
];
```

### Frigate Metrics Available

Frigate exposes the following Prometheus metrics at `/api/metrics`:

| Metric | Description |
|--------|-------------|
| `frigate_cpu_usage_percent` | CPU usage percentage |
| `frigate_mem_usage_percent` | Memory usage percentage |
| `frigate_gpu_usage_percent` | GPU usage (if available) |
| `frigate_camera_fps` | FPS per camera |
| `frigate_detection_fps` | Detection processing FPS |
| `frigate_process_fps` | Overall process FPS |
| `frigate_skipped_fps` | Skipped frames |
| `frigate_detection_enabled` | Detection status per camera |

### Prometheus Alert Rules

Add to Prometheus rules:

```yaml
groups:
  - name: frigate
    rules:
      - alert: FrigateCameraDown
        expr: frigate_camera_fps == 0
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Camera {{ $labels.camera }} is not receiving frames"

      - alert: FrigateHighCPU
        expr: frigate_cpu_usage_percent > 80
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "Frigate CPU usage is above 80%"

      - alert: FrigateDetectionSlow
        expr: frigate_detection_fps < 5
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Frigate detection FPS is below 5"

      - alert: CameraStorageHigh
        expr: (node_filesystem_avail_bytes{mountpoint="/mnt/cameras"} / node_filesystem_size_bytes{mountpoint="/mnt/cameras"}) * 100 < 20
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Camera storage is above 80% full"
```

### Grafana Dashboard

Create a Frigate monitoring dashboard with panels for:

1. **Camera Status Grid** - Live status of all cameras
2. **Detection Events Timeline** - Events over time
3. **Storage Usage** - Current usage and trend
4. **Performance Metrics** - CPU, memory, GPU, FPS
5. **Event Distribution** - Objects detected by type and camera

Reference dashboard: [Grafana Dashboard #18226](https://grafana.com/grafana/dashboards/18226-frigate/)

## Caddy Reverse Proxy Configuration

Add to `modules/gateway/Caddyfile`:

```caddyfile
frigate.vofi {
    reverse_proxy ser8.local:5000
}

hass.vofi {
    reverse_proxy ser8.local:8123 {
        # WebSocket support for Home Assistant
        header_up Upgrade {http.request.header.Upgrade}
        header_up Connection "Upgrade"
    }
}

# Tailscale-exposed for external access
https://frigate.shad-bangus.ts.net {
    log tailscale {
        level DEBUG
    }
    bind tailscale/frigate
    reverse_proxy ser8.local:5000
}

https://hass.shad-bangus.ts.net {
    log tailscale {
        level DEBUG
    }
    bind tailscale/hass
    reverse_proxy ser8.local:8123
}
```

## Impermanence Configuration

Add to `hosts/ser8/impermanence.nix`:

```nix
environment.persistence."/persist" = {
  directories = [
    # ... existing directories ...

    # Frigate
    "/var/lib/frigate"  # Database, config cache

    # Home Assistant
    "/var/lib/hass"     # HA state, automations, integrations
  ];
};

# Camera recordings are on ZFS backup pool, not impermanence
# /mnt/cameras is mounted from backup pool
```

## Security Considerations

### IoT VLAN Design (Future Implementation)

**Current State:** Cameras on main LAN (192.168.68.0/24)

**Recommended Future State:**

```
+-------------------+     +-------------------+
|   Main LAN        |     |   IoT VLAN        |
|  192.168.68.0/24  |     |  192.168.69.0/24  |
+--------+----------+     +--------+----------+
         |                         |
    +----v----+               +----v----+
    |   ser8  |<--------------+  Cameras |
    | Frigate |  RTSP only    |  C120x6  |
    +---------+               +----------+
```

**Firewall Rules for IoT VLAN:**

| Direction | Source | Destination | Port | Action |
|-----------|--------|-------------|------|--------|
| Inbound | IoT VLAN | ser8 | 554 (RTSP) | Allow |
| Inbound | IoT VLAN | Any | * | Deny |
| Outbound | Main LAN | IoT VLAN | 80, 443, 554 | Allow |
| Outbound | IoT VLAN | Internet | * | Deny |

**Implementation Notes:**
- Requires VLAN-capable switch (not currently documented in homelab)
- Router/firewall configuration needed (AdGuard on pi4 is DNS only)
- Consider Ubiquiti UniFi or TP-Link Omada for VLAN support

### Camera Hardening

1. **Disable cloud features** - Tapo cameras should not phone home
2. **Strong passwords** - Unique password per camera, stored in SOPS
3. **Firmware updates** - Keep cameras updated
4. **Disable UPnP** - Prevent cameras from punching holes in firewall
5. **Local storage only** - Configure SD cards for local backup, not cloud

### Frigate Security

1. **No direct internet exposure** - Access via Caddy/Tailscale only
2. **RTSP stream encryption** - Not supported by Tapo C120, rely on network security
3. **Home Assistant authentication** - Use HA's built-in auth for API access

## Implementation Plan

### Phase 1: Storage Preparation (1-2 hours)

1. Create ZFS datasets for camera storage:
   ```bash
   zfs create backup/cameras
   zfs create backup/cameras/continuous
   zfs create backup/cameras/events
   zfs set quota=2T backup/cameras/continuous
   zfs set quota=2T backup/cameras/events
   zfs set recordsize=1M backup/cameras
   zfs set compression=lz4 backup/cameras
   ```

2. Update `hosts/ser8/disko-config.nix` with dataset definitions

3. Update `hosts/ser8/impermanence.nix` for Frigate persistence

### Phase 2: Frigate Installation (2-3 hours)

1. Create `modules/automation/frigate.nix` module

2. Add secrets to SOPS:
   ```bash
   make sops-edit-ser8
   # Add camera credentials
   ```

3. Test single camera configuration

4. Verify hardware acceleration with AMD VA-API

### Phase 3: Home Assistant Integration (2-3 hours)

1. Enable Home Assistant service on ser8

2. Configure Frigate integration in HA

3. Set up basic automations (person detection notifications)

4. Test MQTT communication

### Phase 4: Full Camera Deployment (2-3 hours)

1. Configure all 6 cameras with unique names and zones

2. Define detection zones per camera

3. Configure SD card fallback recording on cameras

4. Test failover scenarios

### Phase 5: Monitoring Integration (1-2 hours)

1. Add Frigate scrape config to Prometheus

2. Import Grafana dashboard

3. Configure alert rules

4. Test alerting

### Phase 6: Documentation and Testing (1-2 hours)

1. Update CLAUDE.md with new services

2. Add smoketests for Frigate and HA

3. Document camera IPs and credentials location

4. Test full system recovery from reboot

### Future Phase: IoT VLAN (Separate Project)

1. Procure VLAN-capable network equipment

2. Configure VLANs and firewall rules

3. Migrate cameras to IoT VLAN

4. Update Frigate configuration for new IPs

## Dependencies and Prerequisites

### System Dependencies

- `ffmpeg` with VA-API support (already on ser8)
- AMD GPU drivers for VA-API (ROCm or amdgpu)
- Go2rtc for WebRTC (bundled with Frigate)

### NixOS Flake Dependencies

No new flake inputs required. Frigate and Home Assistant are in nixpkgs.

### External Dependencies

- Camera accounts created in Tapo app (RTSP credentials)
- Camera static IPs or DHCP reservations
- Network access from ser8 to cameras on port 554

## Risks and Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| AMD VA-API issues | High CPU usage | Fall back to CPU decoding; research AMD-specific Frigate config |
| Camera RTSP drops | Missing recordings | SD card fallback; health monitoring alerts |
| ZFS pool failure | Data loss | RAIDZ2 tolerates 2 disk failures; consider offsite backup |
| Frigate database corruption | Lost events | Regular database backups; SQLite is resilient |
| NixOS Frigate module issues | Service failures | Test in VM first; have Docker fallback ready |

## Alternatives Considered

### NVR Options

| Option | Pros | Cons | Decision |
|--------|------|------|----------|
| Frigate | AI detection, HA integration, active development | Requires more resources | **Selected** |
| Motion | Lightweight, mature | No AI, dated UI | Rejected |
| ZoneMinder | Full-featured | Heavy, complex | Rejected |
| Shinobi | Web-based, lightweight | Less HA integration | Rejected |

### Storage Options

| Option | Pros | Cons | Decision |
|--------|------|------|----------|
| Existing backup pool (RAIDZ2) | Already available, redundant | Shared with backups | **Selected** |
| New dedicated pool | Isolated workload | No spare disks | Rejected |
| Camera SD cards only | Simple, distributed | Wear, capacity, access | Rejected |
| NAS (external) | Offload from ser8 | Latency, complexity | Future consideration |

### Detection Hardware

| Option | Pros | Cons | Decision |
|--------|------|------|----------|
| CPU only | Simple, no extra hardware | High CPU usage | Initial approach |
| AMD GPU (OpenVINO) | Uses existing hardware | Limited model support | Future investigation |
| Google Coral TPU | Fast, efficient | Deprecated product line | Not recommended |
| Hailo AI accelerator | Modern, efficient | New purchase required | Future consideration |

## References

- [Frigate NVR Documentation](https://docs.frigate.video/)
- [TP-Link Tapo RTSP/ONVIF FAQ](https://www.tp-link.com/us/support/faq/2680/)
- [NixOS Frigate Options](https://mynixos.com/options/services.frigate)
- [NixOS Home Assistant Wiki](https://wiki.nixos.org/wiki/Home_Assistant)
- [Frigate Grafana Dashboard](https://grafana.com/grafana/dashboards/18226-frigate/)
- [prometheus-frigate-exporter](https://github.com/bairhys/prometheus-frigate-exporter)
- [Network Segmentation for IoT](https://www.bitdefender.com/en-gb/blog/hotforsecurity/network-segmentation)

## Appendix A: Camera IP Assignments (TBD)

**Outdoor Cameras (4x) - Detection Enabled:**

| Camera | Location | IP Address | Detection Objects |
|--------|----------|------------|-------------------|
| front_door | Front entrance | 192.168.68.101 | person, package |
| backyard | Back patio | 192.168.68.102 | person, car |
| driveway | Front driveway | 192.168.68.103 | person, car |
| side_gate | Side entrance | 192.168.68.104 | person, package |

**Indoor Cameras (2x) - Recording Only:**

| Camera | Location | IP Address | Notes |
|--------|----------|------------|-------|
| living_room | Main living area | 192.168.68.105 | No detection |
| basement | Basement area | 192.168.68.106 | No detection |

## Appendix B: Frigate Detection Zones Example

```yaml
# Example zone configuration for front_door camera
zones:
  porch:
    coordinates: 0,360,640,360,640,200,0,200
    objects:
      - person
      - package
    filters:
      person:
        min_area: 3000
  driveway:
    coordinates: 640,360,640,200,400,200,400,360
    objects:
      - car
      - person
```

## Appendix C: Retention Policy Implementation

Frigate handles retention natively. Different retention per camera type:

**Outdoor cameras (detection enabled):**
```yaml
record:
  enabled: true
  retain:
    days: 5        # Keep all recordings for 5 days
    mode: motion   # Only keep segments with motion after 5 days
  events:
    retain:
      default: 30  # Keep event clips for 30 days
      mode: active_objects  # Only segments with detected objects
```

**Indoor cameras (no detection):**
```yaml
record:
  enabled: true
  retain:
    days: 3        # Shorter retention for indoor
detect:
  enabled: false   # No AI detection
```

When disk space is low (< 1 hour remaining), Frigate automatically deletes the oldest 2 hours of recordings.
