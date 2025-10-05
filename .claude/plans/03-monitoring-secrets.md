# Monitoring & Secrets - Gap Analysis

## Current Monitoring State

### Prometheus (firebat)

**Location:** `modules/gateway/prometheus.nix`

**Working Exporters:**
- ✅ ser8 node exporter (port 9100)
- ✅ ser8 ZFS exporter (port 9134)
- ✅ pi4 node exporter (port 9100)
- ✅ firebat node exporter (local)
- ✅ Jellyfin metrics (port 9027)

**Missing/Incomplete:**
- ❌ **Line 51:** FIXME for AdGuard Home scraping
- ❌ qBittorrent metrics (no exporter configured)
- ❌ NordVPN connection status monitoring
- ❌ Sonarr metrics (needs API key)
- ❌ Radarr metrics (needs API key)
- ❌ Prowlarr metrics (needs API key)
- ❌ Backup pool health (ZFS exporter needs pools config)

**Current Configuration:**
```nix
# modules/gateway/prometheus.nix:51
# FIXME: Add AdGuard Home metrics
# AdGuard doesn't have a native exporter, but has API
```

### Grafana (firebat)

**Location:** `modules/gateway/grafana.nix`

**Status:**
- ✅ Service configured and running
- ✅ Prometheus datasource configured
- ❌ Dashboard directory likely empty
- ❌ No ZFS dashboards
- ❌ No media service dashboards
- ❌ No VPN monitoring dashboards

**Agent Found:** Dashboard directory appears empty

### Missing Dashboards

Based on available exporters but no dashboards:

1. **ZFS Pool Health** (for rpool and backup pool)
   - Pool status, capacity, fragmentation
   - Scrub status and errors
   - Dataset usage
   - ARC hit rates

2. **Media Services**
   - Jellyfin usage, streaming sessions
   - Sonarr/Radarr activity (when API keys added)
   - qBittorrent download stats (when exporter added)

3. **System Overview**
   - Node exporter metrics for all hosts
   - CPU, memory, disk, network per host
   - Service status across infrastructure

4. **Network & Security**
   - NordVPN connection status
   - qBittorrent namespace isolation verification
   - AdGuard DNS query stats (when exporter added)

## Secrets Management

### Current SOPS Configuration

**Working:**
- ✅ `secrets/ser8.yaml` - Samba passwords, service credentials
- ✅ `secrets/pi4.yaml` - AdGuard credentials
- ✅ `secrets/firebat.yaml` - Gateway service secrets
- ✅ Age encryption with SSH host keys
- ✅ SOPS properly configured in modules

**Structure:**
```
secrets/
├── keys/
│   ├── hosts/
│   │   ├── ser8.pub
│   │   ├── firebat.pub
│   │   └── pi4.pub
│   └── users/
│       └── bdhill.pub
├── ser8.yaml (encrypted)
├── firebat.yaml (encrypted)
└── pi4.yaml (encrypted)
```

### Missing Secrets (from TODO.md)

**Media Services on ser8:**
- ❌ Sonarr API key
- ❌ Radarr API key
- ❌ qBittorrent web UI password
- ❌ Prowlarr API key

**Monitoring:**
- ❌ AdGuard Home API key (for Prometheus)

**Potential Issues:**
- ⚠️ Media services might be sharing credentials
- ⚠️ Need to verify credential isolation

### Secrets Sharing Concern

From agent analysis: "Multiple media services might be sharing credentials"

**Need to audit:**
- Do Sonarr/Radarr/Prowlarr each have their own credentials?
- Are API keys unique per service?
- Is access properly scoped?

## Solutions

### 1. Add Missing Prometheus Exporters

#### AdGuard Home Exporter

Add to `modules/dns/adguard.nix`:

```nix
# AdGuard Home exporter for Prometheus
services.prometheus.exporters.adguard = {
  enable = true;
  port = 9617;
  # Will need API key from SOPS
  adguardHome = {
    url = "http://localhost:3000";
    # username/password or API token from secrets
  };
};

# Open firewall for Prometheus scraping
networking.firewall.allowedTCPPorts = [ 9617 ];
```

Update `modules/gateway/prometheus.nix`:

```nix
scrapeConfigs = [
  # ... existing configs ...

  {
    job_name = "adguard";
    static_configs = [{
      targets = [ "pi4.internal:9617" ];
      labels = {
        host = "pi4";
        service = "adguard";
      };
    }];
  }
];
```

#### qBittorrent Exporter

Add to `modules/media/qbittorrent.nix`:

```nix
# qBittorrent exporter
services.prometheus.exporters.qbittorrent = {
  enable = true;
  port = 9561;
  qbittorrentUrl = "http://localhost:8080";
  # Username/password from SOPS
};

networking.firewall.allowedTCPPorts = [ 9561 ];
```

Update Prometheus config:

```nix
{
  job_name = "qbittorrent";
  static_configs = [{
    targets = [ "ser8.internal:9561" ];
    labels = {
      host = "ser8";
      service = "qbittorrent";
    };
  }];
}
```

#### VPN Monitoring

Add custom script to check NordVPN connection:

`modules/nordvpn/monitoring.nix`:

```nix
{ config, pkgs, ... }:

{
  # Custom VPN status exporter
  systemd.services.nordvpn-status-exporter = {
    description = "NordVPN connection status exporter for Prometheus";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];

    serviceConfig = {
      Type = "simple";
      ExecStart = pkgs.writeShellScript "vpn-status-exporter" ''
        #!${pkgs.bash}/bin/bash

        # Simple HTTP server that returns VPN status as Prometheus metrics
        ${pkgs.python3}/bin/python3 - <<'EOF'
        import subprocess
        import time
        from http.server import HTTPServer, BaseHTTPRequestHandler

        class MetricsHandler(BaseHTTPRequestHandler):
            def do_GET(self):
                # Check if VPN namespace has connectivity
                try:
                    result = subprocess.run(
                        ['ip', 'netns', 'exec', 'vpn', 'ping', '-c', '1', '-W', '1', '8.8.8.8'],
                        capture_output=True,
                        timeout=2
                    )
                    vpn_up = 1 if result.returncode == 0 else 0
                except:
                    vpn_up = 0

                metrics = f"""# HELP nordvpn_connected VPN connection status
# TYPE nordvpn_connected gauge
nordvpn_connected {vpn_up}
"""
                self.send_response(200)
                self.send_header('Content-Type', 'text/plain')
                self.end_headers()
                self.wfile.write(metrics.encode())

        HTTPServer(('0.0.0.0', 9600), MetricsHandler).serve_forever()
        EOF
      '';
      Restart = "always";
    };
  };

  networking.firewall.allowedTCPPorts = [ 9600 ];
}
```

Add to Prometheus:

```nix
{
  job_name = "nordvpn";
  static_configs = [{
    targets = [ "ser8.internal:9600" ];
    labels = {
      host = "ser8";
      service = "nordvpn";
    };
  }];
}
```

#### Sonarr/Radarr/Prowlarr Exporters

Add to respective module files:

```nix
# modules/media/sonarr.nix (and similar for radarr, prowlarr)

services.prometheus.exporters.exportarr-sonarr = {
  enable = true;
  port = 9707;
  url = "http://localhost:8989";
  apiKeyFile = config.sops.secrets.sonarr_api_key.path;
};

networking.firewall.allowedTCPPorts = [ 9707 ];

# SOPS secret definition
sops.secrets.sonarr_api_key = {
  owner = "prometheus-exportarr";
  mode = "0400";
};
```

### 2. Create Grafana Dashboards

#### Option A: Import Community Dashboards

Many services have pre-built dashboards on grafana.com:

Add to `modules/gateway/grafana.nix`:

```nix
services.grafana = {
  # ... existing config ...

  provision = {
    enable = true;

    dashboards.settings = {
      providers = [
        {
          name = "default";
          options.path = "/var/lib/grafana/dashboards";
        }
      ];
    };
  };
};

# Systemd service to download dashboards on first run
systemd.services.grafana-dashboard-provision = {
  description = "Provision Grafana dashboards";
  wantedBy = [ "grafana.service" ];
  before = [ "grafana.service" ];

  serviceConfig = {
    Type = "oneshot";
    RemainAfterExit = true;
  };

  script = ''
    mkdir -p /var/lib/grafana/dashboards

    # Node Exporter Full dashboard
    ${pkgs.curl}/bin/curl -o /var/lib/grafana/dashboards/node-exporter.json \
      https://grafana.com/api/dashboards/1860/revisions/latest/download

    # ZFS dashboard
    ${pkgs.curl}/bin/curl -o /var/lib/grafana/dashboards/zfs.json \
      https://grafana.com/api/dashboards/7845/revisions/latest/download

    # Jellyfin dashboard (if available)
    # ... more dashboards ...

    chown -R grafana:grafana /var/lib/grafana/dashboards
  '';
};
```

#### Option B: Custom Dashboards in Git

Store dashboard JSON in repo:

```
modules/gateway/dashboards/
├── node-exporter.json
├── zfs.json
├── media-services.json
└── vpn-monitoring.json
```

Reference in Grafana config:

```nix
services.grafana.provision.dashboards.settings.providers = [
  {
    name = "nixos-homelab";
    options.path = ./dashboards;
  }
];
```

### 3. Add Missing Secrets

#### Generate API Keys

On ser8:

```bash
# Get Sonarr API key
curl -s http://localhost:8989/api/v3/system/status | jq -r '.apiKey'

# Get Radarr API key
curl -s http://localhost:7878/api/v3/system/status | jq -r '.apiKey'

# Get Prowlarr API key
curl -s http://localhost:9696/api/v1/system/status | jq -r '.apiKey'

# qBittorrent: Set via web UI or config file
```

#### Add to SOPS

```bash
# On your Mac
make sops-edit-ser8

# Add these keys:
# sonarr_api_key: "..."
# radarr_api_key: "..."
# prowlarr_api_key: "..."
# qbittorrent_web_password: "..."
```

For AdGuard (pi4):

```bash
make sops-edit-pi4

# Add:
# adguard_api_username: "admin"
# adguard_api_password: "..."
```

#### Use Secrets in Modules

Example for Sonarr (`modules/media/sonarr.nix`):

```nix
{
  # ... existing config ...

  sops = {
    defaultSopsFile = ../../secrets/ser8.yaml;
    secrets.sonarr_api_key = {
      owner = config.users.users.sonarr.name;
      mode = "0400";
    };
  };

  # Exporter can reference the secret
  services.prometheus.exporters.exportarr-sonarr = {
    enable = true;
    apiKeyFile = config.sops.secrets.sonarr_api_key.path;
  };
}
```

### 4. Verify Credential Isolation

Audit `secrets/ser8.yaml` to ensure:

- Each service has its own API key
- Passwords aren't shared between services
- API keys are scoped appropriately

If services are sharing credentials, regenerate unique ones:

```bash
# For each service, generate new API key
# Then update SOPS and restart services
```

## Implementation Checklist

### Phase 1: Secrets (Do First)
- [ ] Generate API keys for Sonarr, Radarr, Prowlarr, qBittorrent
- [ ] Generate AdGuard API credentials
- [ ] Add all secrets to SOPS (ser8.yaml, pi4.yaml)
- [ ] Update module configs to use SOPS secrets
- [ ] Deploy and verify: `make switch-ser8` and `make switch-pi4`

### Phase 2: Exporters
- [ ] Add qBittorrent exporter to ser8
- [ ] Add Sonarr/Radarr/Prowlarr exporters to ser8
- [ ] Add AdGuard exporter to pi4
- [ ] Add NordVPN monitoring to ser8
- [ ] Update ZFS exporter config to include backup pool
- [ ] Deploy and verify metrics endpoints

### Phase 3: Prometheus Config
- [ ] Update Prometheus scrape configs for new exporters
- [ ] Fix AdGuard FIXME at line 51
- [ ] Deploy firebat: `make switch-firebat`
- [ ] Verify all targets in Prometheus UI

### Phase 4: Grafana Dashboards
- [ ] Choose dashboard strategy (import vs git)
- [ ] Add Node Exporter dashboard
- [ ] Add ZFS dashboard
- [ ] Create media services dashboard
- [ ] Create VPN monitoring dashboard
- [ ] Deploy and verify in Grafana UI

## Testing Verification

After implementation:

```bash
# Check Prometheus targets
curl -s http://prometheus.vofi.app/api/v1/targets | jq '.data.activeTargets[] | {job: .labels.job, health: .health}'

# Should show all new exporters as "up"

# Check metrics are being collected
curl -s http://prometheus.vofi.app/api/v1/query?query=nordvpn_connected | jq .

# Access Grafana dashboards
open https://grafana.vofi.app

# Verify ZFS metrics
curl http://ser8.internal:9134/metrics | grep zfs_pool

# Verify qBittorrent metrics
curl http://ser8.internal:9561/metrics | grep qbittorrent
```

## Recommended Dashboard IDs (grafana.com)

- **Node Exporter Full:** 1860
- **ZFS:** 7845 or 11337
- **Jellyfin:** Search for "jellyfin" (multiple available)
- **Prometheus Stats:** 2
- **System Overview:** 11074

## Long-term Monitoring Improvements

### 1. Alerting

Add to `modules/gateway/prometheus.nix`:

```nix
services.prometheus.rules = [
  ''
    groups:
      - name: system
        rules:
          - alert: HostDown
            expr: up == 0
            for: 5m
            annotations:
              summary: "Host {{ $labels.instance }} is down"

          - alert: VPNDisconnected
            expr: nordvpn_connected == 0
            for: 2m
            annotations:
              summary: "NordVPN connection is down on {{ $labels.host }}"

          - alert: DiskSpaceLow
            expr: node_filesystem_avail_bytes / node_filesystem_size_bytes < 0.1
            for: 5m
            annotations:
              summary: "Disk space low on {{ $labels.instance }}"

          - alert: ZFSPoolDegraded
            expr: zfs_pool_health != 0
            for: 1m
            annotations:
              summary: "ZFS pool {{ $labels.pool }} is degraded"
  ''
];

# Configure alertmanager
services.prometheus.alertmanager = {
  enable = true;
  configuration = {
    route = {
      # For now, just log alerts
      # Later: add email, webhook, etc.
      receiver = "default";
    };
    receivers = [{
      name = "default";
    }];
  };
};
```

### 2. Backup Monitoring

Monitor backup job status:

```nix
# Add backup job exporter
# Track when last backup ran, if it succeeded, etc.
```

### 3. Log Aggregation

Consider adding Loki for log aggregation:

```nix
services.loki = {
  enable = true;
  # ... config ...
};

services.promtail = {
  enable = true;
  # Ship logs to Loki
};
```

## Summary

**Critical Gaps:**
1. Missing API keys for media service monitoring
2. No Grafana dashboards (exporters exist but unused)
3. AdGuard monitoring not configured
4. VPN status not monitored

**Implementation Priority:**
1. Add secrets (required for exporters)
2. Configure exporters
3. Update Prometheus
4. Add dashboards

**Estimated Time:** 4-6 hours total
- Secrets: 1 hour
- Exporters: 2 hours
- Dashboards: 1-2 hours
- Testing: 1 hour
