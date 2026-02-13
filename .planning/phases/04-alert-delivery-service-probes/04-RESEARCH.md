# Phase 4: Alert Delivery & Service Probes - Research

**Researched:** 2026-02-12
**Domain:** Grafana Unified Alerting, Blackbox Exporter, SMTP email delivery, NixOS declarative provisioning
**Confidence:** HIGH

## Summary

Phase 4 bridges the critical gap between "alerts fire" and "someone gets notified." The existing Prometheus configuration on firebat defines 6 alert rules (HostDown, HighDiskUsage, HighMemoryUsage, ZFSPoolUnhealthy, HighCPUTemperature, CameraStorageHigh) but has NO alertmanager configured -- these rules evaluate and fire into the void. This phase adds three capabilities: (1) Grafana SMTP for Gmail email delivery, (2) Blackbox Exporter for HTTP/ICMP/TLS probing of all services, and (3) Grafana Unified Alerting rules provisioned declaratively to replace the notification-less Prometheus rules.

A critical architectural finding: Grafana's built-in Alertmanager only handles Grafana-managed alerts, NOT Prometheus alertmanager-style alerts. This means the existing Prometheus `ruleFiles` alert rules cannot simply be "connected" to Grafana for notification. Instead, equivalent Grafana-managed alert rules must be created that query the Prometheus datasource with the same PromQL expressions. The existing Prometheus rules can remain as a defense-in-depth layer (they show in Prometheus UI) but email delivery requires Grafana-managed rules.

All components have mature NixOS modules. Blackbox exporter already sets `CAP_NET_RAW` via AmbientCapabilities for ICMP probes. Grafana provisioning supports declarative contact points, notification policies, and alert rules via `services.grafana.provision.alerting.*`. The main complexity is the Grafana alert rule data model (three-step: query -> reduce -> threshold), which is more verbose than Prometheus rule syntax but well-documented.

**Primary recommendation:** Create Grafana-managed alert rules that mirror the existing Prometheus rules, add blackbox probe alerts, configure Gmail SMTP via SOPS, and provision everything declaratively in Nix. Keep existing Prometheus ruleFiles as defense-in-depth but do NOT depend on them for notifications.

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Grafana SMTP settings | N/A (built into Grafana 12.x) | Email delivery for alert notifications | Built into existing Grafana, no new service. Uses `services.grafana.settings.smtp` NixOS options. |
| Grafana Unified Alerting | N/A (built into Grafana 12.x) | Alert rule evaluation + notification routing | Built into existing Grafana. Replaces need for standalone Alertmanager. Evaluates PromQL queries directly. |
| prometheus-blackbox-exporter | 0.27.0 | HTTP/ICMP/TLS endpoint probing | Native NixOS module. Provides `probe_success`, `probe_http_status_code`, `probe_ssl_earliest_cert_expiry` metrics. |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| Grafana alerting provisioning | N/A | Declarative alert rules, contact points, policies | `services.grafana.provision.alerting.*` -- same pattern as existing dashboard provisioning |
| SOPS secrets | Existing | Store Gmail App Password | `sops.secrets.grafana_smtp_password` on firebat, read via `$__file{}` pattern |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Grafana Unified Alerting | Standalone Alertmanager | Alertmanager is a separate service to configure and maintain. Grafana already runs on firebat. Alertmanager would be needed if Prometheus rules must remain the source of truth. |
| Grafana-managed rules | Prometheus rules + Alertmanager | Would keep existing rules format but adds Alertmanager service. At homelab scale, Grafana handles everything. |
| Gmail SMTP | Pushover / Discord webhook | Gmail is free and already decided. Pushover costs $5. Discord requires server setup. |

**Installation:**
No new flake inputs needed. All packages available in nixpkgs 25.05:
```bash
# Already available via NixOS modules:
# services.prometheus.exporters.blackbox (blackbox exporter)
# services.grafana.settings.smtp (SMTP)
# services.grafana.provision.alerting (alerting provisioning)
```

## Architecture Patterns

### Module Placement

```
modules/gateway/
  |-- default.nix      # MODIFY: add import for blackbox.nix
  |-- grafana.nix       # MODIFY: add SMTP, alerting provisioning, datasource UID
  |-- prometheus.nix    # MODIFY: add blackbox scrape jobs, keep existing ruleFiles
  |-- blackbox.nix      # NEW: blackbox exporter configuration
  |-- caddy.nix         # EXISTING: no changes
  |-- tailscale.nix     # EXISTING: no changes
```

### Pattern 1: Grafana Alert Rule Data Model (Three-Step Evaluation)

**What:** Grafana-managed alert rules use a three-step data pipeline: Query (A) -> Reduce (B) -> Threshold (C).
**When to use:** Every Grafana-managed alert rule that queries Prometheus.

**Example (verified from Grafana official provisioning-alerting-examples repo):**
```yaml
# Source: https://github.com/grafana/provisioning-alerting-examples
apiVersion: 1
groups:
  - orgId: 1
    name: homelab_alerts
    folder: Alerting
    interval: 1m
    rules:
      - uid: host_down_alert
        title: Host Down
        condition: C
        data:
          - refId: A
            relativeTimeRange:
              from: 300
              to: 0
            datasourceUid: prometheus
            model:
              expr: "up == 0"
              intervalMs: 1000
              maxDataPoints: 43200
              refId: A
          - refId: B
            datasourceUid: __expr__
            model:
              expression: A
              reducer: last
              type: reduce
              refId: B
          - refId: C
            datasourceUid: __expr__
            model:
              expression: B
              type: threshold
              conditions:
                - evaluator:
                    params: [0]
                    type: gt
              refId: C
        for: 5m
        noDataState: NoData
        execErrState: Alerting
        labels:
          severity: critical
        annotations:
          summary: "Host {{ $labels.instance }} is down"
```

**Key insight:** The `datasourceUid: prometheus` must match the UID set on the provisioned Prometheus datasource. The `__expr__` datasource is Grafana's built-in expression engine.

### Pattern 2: Datasource UID for Cross-Reference

**What:** Set a known, stable UID on provisioned datasources so alert rules can reference them.
**When to use:** Always when provisioning both datasources and alert rules.

**Example:**
```nix
# Source: https://grafana.com/docs/grafana/latest/administration/provisioning/
services.grafana.provision.datasources.settings = {
  apiVersion = 1;
  datasources = [
    {
      name = "Prometheus";
      type = "prometheus";
      access = "proxy";
      url = "http://localhost:9090";
      uid = "prometheus";  # Stable UID for alert rule references
      isDefault = true;
    }
  ];
};
```

### Pattern 3: SMTP Password via $__file{} Provider

**What:** Use Grafana's file provider to read secrets at runtime, avoiding Nix store exposure.
**When to use:** For any secret value in `services.grafana.settings`.

**Example (already proven in this codebase for admin password):**
```nix
# Source: Existing modules/gateway/grafana.nix line 60
sops.secrets.grafana_smtp_password = {
  owner = "grafana";
  group = "grafana";
  mode = "0400";
};

services.grafana.settings.smtp = {
  enabled = true;
  host = "smtp.gmail.com:587";
  user = "your-email@gmail.com";
  password = "$__file{${config.sops.secrets.grafana_smtp_password.path}}";
  from_address = "your-email@gmail.com";
  from_name = "Homelab Alerts";
  startTLS_policy = "MandatoryStartTLS";
};
```

### Pattern 4: Blackbox Multi-Target Exporter Relabeling

**What:** Blackbox exporter uses the Prometheus multi-target pattern requiring specific relabel_configs.
**When to use:** Every Prometheus scrape job targeting the blackbox exporter.

**Example:**
```nix
# Source: https://prometheus.io/docs/guides/multi-target-exporter/
{
  job_name = "blackbox-http";
  metrics_path = "/probe";
  params.module = [ "http_2xx" ];
  static_configs = [{
    targets = [
      "http://ser8.local:8096"   # Jellyfin
      "http://ser8.local:8989"   # Sonarr
      # ... more targets
    ];
  }];
  relabel_configs = [
    {
      source_labels = [ "__address__" ];
      target_label = "__param_target";
    }
    {
      source_labels = [ "__param_target" ];
      target_label = "instance";
    }
    {
      target_label = "__address__";
      replacement = "localhost:9115";
    }
  ];
}
```

### Pattern 5: Contact Points + Notification Policies Provisioning

**What:** Declarative email contact point and notification routing.
**When to use:** Setting up alerting delivery pipeline.

**Example (verified from Grafana official example repo):**
```nix
services.grafana.provision.alerting = {
  contactPoints.settings = {
    apiVersion = 1;
    contactPoints = [{
      orgId = 1;
      name = "email-alerts";
      receivers = [{
        uid = "email-alerts-uid";
        type = "email";
        settings = {
          addresses = "your-email@gmail.com";
          singleEmail = false;
        };
        disableResolveMessage = false;
      }];
    }];
  };
  policies.settings = {
    apiVersion = 1;
    policies = [{
      orgId = 1;
      receiver = "email-alerts";
      group_by = [ "grafana_folder" "alertname" ];
      routes = [{
        receiver = "email-alerts";
        object_matchers = [
          [ "severity" "=~" "critical|warning" ]
        ];
      }];
    }];
  };
};
```

### Anti-Patterns to Avoid

- **Configuring Prometheus `alertmanagers` to point at Grafana:** Grafana's built-in Alertmanager only handles Grafana-managed alerts. It does NOT accept alerts from Prometheus. Do not waste time configuring `services.prometheus.alertmanagers` to send to Grafana.
- **Putting SMTP password directly in Nix config:** The value ends up in the world-readable `/nix/store`. Always use `$__file{}` with SOPS.
- **Adding blackbox exporter to static_configs.targets directly:** This scrapes the exporter itself, not the probed targets. Must use the multi-target relabeling pattern.
- **Probing Caddy HTTPS endpoints with TLS verification:** Caddy uses `local_certs` (self-signed). Blackbox will show all probes as failed. Probe direct HTTP ports instead. Use Tailscale URLs for TLS cert monitoring.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Email notifications | Custom SMTP script/service | Grafana SMTP + contact points | Grafana handles retries, templating, resolve messages, grouping |
| HTTP health checks | cron + curl scripts | Blackbox exporter + Prometheus | Blackbox provides metrics, history, Grafana integration out of the box |
| Alert routing | Custom notification logic | Grafana notification policies | Policies handle grouping, muting, routing, repeat intervals |
| TLS cert monitoring | OpenSSL cron checks | Blackbox `probe_ssl_earliest_cert_expiry` | Metric is auto-generated when probing HTTPS endpoints |
| Alert rule management | Manual Grafana UI setup | `services.grafana.provision.alerting` | Declarative, version-controlled, reproducible |

**Key insight:** The entire alert delivery pipeline (rules -> evaluation -> routing -> delivery) is handled by Grafana's built-in capabilities. No additional services needed beyond the blackbox exporter.

## Common Pitfalls

### Pitfall 1: Grafana's Built-in Alertmanager Does NOT Accept Prometheus Alerts

**What goes wrong:** You configure `services.prometheus.alertmanagers` to send to Grafana's port 9093, expecting existing Prometheus rules to deliver email. Nothing happens.
**Why it happens:** Grafana's built-in Alertmanager only processes Grafana-managed alerts. It is NOT a drop-in replacement for standalone Alertmanager. Prometheus alert rules fire in Prometheus but have no delivery path through Grafana.
**How to avoid:** Create equivalent Grafana-managed alert rules that query the Prometheus datasource with the same PromQL expressions. Keep existing Prometheus ruleFiles as defense-in-depth (visible in Prometheus UI at `/alerts`).
**Warning signs:** Alerts show as "firing" in Prometheus UI but no emails arrive.

### Pitfall 2: SMTP Password in Nix Store is World-Readable

**What goes wrong:** Setting `services.grafana.settings.smtp.password = "actual-password"` exposes it in `/nix/store`.
**Why it happens:** NixOS renders all `services.grafana.settings` into a config file stored in the Nix store, which is readable by all users.
**How to avoid:** Use `$__file{${config.sops.secrets.grafana_smtp_password.path}}` -- same pattern already used for `grafana_admin_password` in this codebase.
**Warning signs:** `grep -r password /nix/store/*grafana*` shows plaintext credentials.

### Pitfall 3: Blackbox Exporter Multi-Target Relabeling

**What goes wrong:** Prometheus scrapes the blackbox exporter itself instead of probing targets. All probes show as "up" because the exporter is healthy.
**Why it happens:** Without the three-step relabel_configs, Prometheus treats the blackbox exporter like a normal scrape target.
**How to avoid:** Use the exact relabel_configs pattern: `__address__` -> `__param_target`, `__param_target` -> `instance`, `__address__` -> `localhost:9115`.
**Warning signs:** `probe_success` metric does not exist, or `instance` label shows `localhost:9115` instead of service URLs.

### Pitfall 4: Gmail App Password Format and TLS Requirements

**What goes wrong:** SMTP authentication fails with regular Gmail password, or emails silently fail with wrong TLS settings.
**Why it happens:** Gmail requires App Passwords (16-char format: `xxxx xxxx xxxx xxxx`) for third-party SMTP. Must use port 587 with STARTTLS, not port 465 or 25.
**How to avoid:** Generate App Password at Google Account > Security > 2-Step Verification > App Passwords. Use `host = "smtp.gmail.com:587"` and `startTLS_policy = "MandatoryStartTLS"`.
**Warning signs:** Grafana logs show SMTP authentication failure or TLS handshake error.

### Pitfall 5: Grafana File-Provisioned Alert Rules Are UI-Locked

**What goes wrong:** After provisioning alert rules via files, they cannot be edited in the Grafana UI. Every threshold change requires a NixOS rebuild.
**Why it happens:** Grafana intentionally locks file-provisioned alerting resources. Unlike dashboards (which have `allowUiUpdates`), alerting resources have no UI-edit escape hatch.
**How to avoid:** Accept that provisioned rules require rebuilds for changes. This is fine for stable rules. During initial tuning, consider creating rules via UI first, then migrating to provisioned once thresholds are validated. Alternatively, use the Grafana Alerting HTTP API for rules that need frequent adjustment.
**Warning signs:** "This resource is provisioned and cannot be edited" badge in Grafana UI.

### Pitfall 6: Blackbox TLS Verification Fails on Self-Signed Caddy Certificates

**What goes wrong:** Probing `https://jellyfin.vofi.app` via blackbox shows probe failure because Caddy uses self-signed certs from its local CA.
**Why it happens:** The Caddyfile uses `local_certs` (line 3). Blackbox does not trust Caddy's local CA.
**How to avoid:** Probe direct HTTP service ports for health (`http://ser8.local:8096`). Probe Tailscale HTTPS URLs (`https://jellyfin.shad-bangus.ts.net`) for TLS cert monitoring -- these have real Let's Encrypt certificates.
**Warning signs:** `probe_success{instance=~".*vofi.*"} == 0` with `probe_http_status_code == 0`.

### Pitfall 7: Blackbox ICMP Probes Require CAP_NET_RAW

**What goes wrong:** ICMP probes silently fail or return errors.
**Why it happens:** ICMP raw sockets require special capabilities.
**How to avoid:** NixOS blackbox exporter module already sets `AmbientCapabilities = [ "CAP_NET_RAW" ]` -- this is handled automatically. No action needed, but verify in systemd service config if ICMP probes fail.
**Warning signs:** ICMP probe metrics show `probe_success == 0` for all hosts.

### Pitfall 8: Missing Datasource UID Breaks Alert Rule References

**What goes wrong:** Alert rules reference `datasourceUid: prometheus` but the provisioned datasource has a different auto-generated UID. Alert rules fail to evaluate.
**Why it happens:** If no `uid` is set in datasource provisioning, Grafana generates a random one. Alert rule provisioning files reference a specific UID.
**How to avoid:** Explicitly set `uid = "prometheus"` in the datasource provisioning config. All alert rules then reference `datasourceUid: prometheus`.
**Warning signs:** Alert rules show "Data source not found" errors in Grafana alerting UI.

## Code Examples

### Complete Blackbox Exporter Configuration (NixOS)

```nix
# Source: NixOS module + Prometheus multi-target exporter guide
# modules/gateway/blackbox.nix
{ config, lib, pkgs, ... }:

{
  services.prometheus.exporters.blackbox = {
    enable = true;
    configFile = pkgs.writeText "blackbox.yml" (builtins.toJSON {
      modules = {
        http_2xx = {
          prober = "http";
          timeout = "10s";
          http = {
            valid_http_versions = [ "HTTP/1.1" "HTTP/2.0" ];
            preferred_ip_protocol = "ip4";
            follow_redirects = true;
          };
        };
        icmp_ping = {
          prober = "icmp";
          timeout = "5s";
        };
        tls_connect = {
          prober = "http";
          timeout = "10s";
          http = {
            preferred_ip_protocol = "ip4";
            valid_http_versions = [ "HTTP/1.1" "HTTP/2.0" ];
          };
        };
      };
    });
  };
  # No firewall port needed -- Prometheus scrapes localhost:9115
}
```

### Complete Prometheus Scrape Jobs for Blackbox

```nix
# Added to services.prometheus.scrapeConfigs in prometheus.nix
# HTTP service probes (direct ports, not Caddy proxies)
{
  job_name = "blackbox-http";
  metrics_path = "/probe";
  params.module = [ "http_2xx" ];
  static_configs = [{
    targets = [
      "http://ser8.local:8096"    # Jellyfin
      "http://ser8.local:8989"    # Sonarr
      "http://ser8.local:7878"    # Radarr
      "http://ser8.local:9696"    # Prowlarr
      "http://ser8.local:8080"    # qBittorrent (via nginx proxy)
      "http://ser8.local:8085"    # SABnzbd
      "http://ser8.local:80"      # Frigate
      "http://ser8.local:8123"    # Home Assistant
    ];
  }];
  relabel_configs = [
    { source_labels = [ "__address__" ]; target_label = "__param_target"; }
    { source_labels = [ "__param_target" ]; target_label = "instance"; }
    { target_label = "__address__"; replacement = "localhost:9115"; }
  ];
  scrape_interval = "60s";
}
# ICMP host reachability probes
{
  job_name = "blackbox-icmp";
  metrics_path = "/probe";
  params.module = [ "icmp_ping" ];
  static_configs = [{
    targets = [
      "ser8.local"
      "firebat.local"
      "pi4.local"
    ];
  }];
  relabel_configs = [
    { source_labels = [ "__address__" ]; target_label = "__param_target"; }
    { source_labels = [ "__param_target" ]; target_label = "instance"; }
    { target_label = "__address__"; replacement = "localhost:9115"; }
  ];
  scrape_interval = "60s";
}
# TLS certificate monitoring via Tailscale HTTPS URLs
{
  job_name = "blackbox-tls";
  metrics_path = "/probe";
  params.module = [ "tls_connect" ];
  static_configs = [{
    targets = [
      "https://jellyfin.shad-bangus.ts.net"
      "https://sonarr.shad-bangus.ts.net"
      "https://radarr.shad-bangus.ts.net"
      "https://prowlarr.shad-bangus.ts.net"
      "https://sabnzbd.shad-bangus.ts.net"
      "https://frigate.shad-bangus.ts.net"
      "https://hass.shad-bangus.ts.net"
      "https://grafana.shad-bangus.ts.net"
      "https://prom.shad-bangus.ts.net"
    ];
  }];
  relabel_configs = [
    { source_labels = [ "__address__" ]; target_label = "__param_target"; }
    { source_labels = [ "__param_target" ]; target_label = "instance"; }
    { target_label = "__address__"; replacement = "localhost:9115"; }
  ];
  scrape_interval = "300s";  # 5 minutes for cert checks
}
```

### Grafana-Managed Alert Rule for PromQL (NixOS Nix Attrset)

```nix
# Source: https://github.com/grafana/provisioning-alerting-examples + Grafana docs
# Translated to NixOS services.grafana.provision.alerting.rules.settings
services.grafana.provision.alerting.rules.settings = {
  apiVersion = 1;
  groups = [{
    orgId = 1;
    name = "homelab_probes";
    folder = "Alerting";
    interval = "1m";
    rules = [{
      uid = "service_down";
      title = "Service Down (Probe Failed)";
      condition = "C";
      data = [
        {
          refId = "A";
          relativeTimeRange = { from = 300; to = 0; };
          datasourceUid = "prometheus";
          model = {
            expr = "probe_success == 0";
            intervalMs = 1000;
            maxDataPoints = 43200;
            refId = "A";
          };
        }
        {
          refId = "B";
          datasourceUid = "__expr__";
          model = {
            expression = "A";
            reducer = "last";
            type = "reduce";
            refId = "B";
          };
        }
        {
          refId = "C";
          datasourceUid = "__expr__";
          model = {
            expression = "B";
            type = "threshold";
            conditions = [{
              evaluator = { params = [ 0 ]; type = "gt"; };
            }];
            refId = "C";
          };
        }
      ];
      "for" = "2m";
      noDataState = "NoData";
      execErrState = "Alerting";
      labels = { severity = "critical"; };
      annotations = {
        summary = "Service {{ $labels.instance }} is unreachable";
      };
      isPaused = false;
    }];
  }];
};
```

### firebat Impermanence Status

```
firebat disk: ext4 on 512GB NVMe (disko-config.nix)
firebat impermanence: MINIMAL -- only SSH keys persisted at /persist/etc/ssh
firebat does NOT use "Erase Your Darlings" ZFS rollback
Result: /var/lib/grafana persists naturally. No special impermanence config needed.
Grafana state (including alert rule database) survives reboots.
```

## Probe Target Reference

### HTTP Service Probes (8 services per PROBE-01)

| Service | Probe URL | Port | Notes |
|---------|-----------|------|-------|
| Jellyfin | `http://ser8.local:8096` | 8096 | Direct service port |
| Sonarr | `http://ser8.local:8989` | 8989 | Direct service port |
| Radarr | `http://ser8.local:7878` | 7878 | Direct service port |
| Prowlarr | `http://ser8.local:9696` | 9696 | Direct service port |
| qBittorrent | `http://ser8.local:8080` | 8080 | Via nginx proxy (VPN namespace) |
| SABnzbd | `http://ser8.local:8085` | 8085 | Direct service port |
| Frigate | `http://ser8.local:80` | 80 | Via nginx (Frigate web UI) |
| Home Assistant | `http://ser8.local:8123` | 8123 | Direct service port |

### ICMP Host Probes (3 hosts per PROBE-02)

| Host | Probe Target | Notes |
|------|--------------|-------|
| ser8 | `ser8.local` | Main media server |
| firebat | `firebat.local` | Gateway/monitoring |
| pi4 | `pi4.local` | DNS server |

### TLS Certificate Probes (9 URLs per PROBE-03)

| Service | Tailscale URL | Cert Authority |
|---------|---------------|----------------|
| Jellyfin | `https://jellyfin.shad-bangus.ts.net` | Let's Encrypt |
| Sonarr | `https://sonarr.shad-bangus.ts.net` | Let's Encrypt |
| Radarr | `https://radarr.shad-bangus.ts.net` | Let's Encrypt |
| Prowlarr | `https://prowlarr.shad-bangus.ts.net` | Let's Encrypt |
| SABnzbd | `https://sabnzbd.shad-bangus.ts.net` | Let's Encrypt |
| Frigate | `https://frigate.shad-bangus.ts.net` | Let's Encrypt |
| Home Assistant | `https://hass.shad-bangus.ts.net` | Let's Encrypt |
| Grafana | `https://grafana.shad-bangus.ts.net` | Let's Encrypt |
| Prometheus | `https://prom.shad-bangus.ts.net` | Let's Encrypt |

**Key metric:** `probe_ssl_earliest_cert_expiry` -- Unix timestamp of cert expiry. Alert when `(probe_ssl_earliest_cert_expiry - time()) < 86400 * 14` (less than 14 days).

## Alert Rules to Provision

### Migrated from Existing Prometheus Rules (ALERT-02)

These rules exist in `modules/gateway/prometheus.nix` lines 142-194 but have no notification delivery. Create Grafana-managed equivalents:

| Alert | PromQL | For | Severity |
|-------|--------|-----|----------|
| HostDown | `up{job="node-exporter"} == 0` | 5m | critical |
| HighDiskUsage | `(node_filesystem_avail_bytes / node_filesystem_size_bytes) * 100 < 10` | 5m | warning |
| HighMemoryUsage | `(node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) * 100 < 10` | 5m | warning |
| ZFSPoolUnhealthy | `node_zfs_zpool_health_state{state!="online"} > 0` | 5m | critical |
| HighCPUTemperature | `node_hwmon_temp_celsius > 80` | 5m | warning |
| CameraStorageHigh | `(node_filesystem_avail_bytes{mountpoint="/mnt/cameras"} / node_filesystem_size_bytes{mountpoint="/mnt/cameras"}) * 100 < 20` | 5m | warning |

### New Probe-Based Alerts (PROBE-04)

| Alert | PromQL | For | Severity |
|-------|--------|-----|----------|
| ServiceDown | `probe_success{job="blackbox-http"} == 0` | 2m | critical |
| HostUnreachable | `probe_success{job="blackbox-icmp"} == 0` | 2m | critical |
| TLSCertExpiringSoon | `(probe_ssl_earliest_cert_expiry{job="blackbox-tls"} - time()) < 86400 * 14` | 1h | warning |

## Secrets Required

| Secret | SOPS File | Used By | Purpose |
|--------|-----------|---------|---------|
| `grafana_smtp_password` | `secrets/firebat.yaml` | Grafana SMTP | Gmail App Password (16 chars, format: `xxxx xxxx xxxx xxxx`) |

**Existing secret pattern to follow:**
```nix
# Already in grafana.nix:
sops.secrets.grafana_admin_password = {
  owner = "grafana";
  group = "grafana";
  mode = "0400";
};
# New -- follow same pattern:
sops.secrets.grafana_smtp_password = {
  owner = "grafana";
  group = "grafana";
  mode = "0400";
};
```

## Firewall Rules

| Host | Port | Protocol | Service | Direction |
|------|------|----------|---------|-----------|
| firebat | 9115 | TCP | Blackbox exporter | Localhost only (Prometheus scrapes it) |

**No external firewall rules needed.** Blackbox exporter is only accessed by Prometheus on localhost. All probe targets are already network-accessible from firebat.

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Prometheus rules + Alertmanager | Grafana Unified Alerting | Grafana 9+ (2022) | Single service for rules + delivery, no separate Alertmanager |
| Manual UI alert creation | File provisioning | Grafana 10+ (2023) | Declarative, version-controlled alerting configuration |
| Prometheus alertmanager in Grafana | Grafana-managed rules only | Current | Built-in Alertmanager handles ONLY Grafana-managed alerts |

**Important version note:** Grafana 12.x (in nixpkgs 25.05) supports importing Prometheus rule files into Grafana-managed rules via the UI (Grafana 12 feature). However, file provisioning remains the recommended declarative approach for NixOS.

## Decision: Provisioning Strategy for Alert Rules (ALERT-03)

**Option A: Fully provisioned from day one (recommended)**
- All rules in `services.grafana.provision.alerting.rules.settings`
- Changes require NixOS rebuild (`make test-firebat`)
- Rules are version-controlled in git
- Rules are UI-locked (cannot edit thresholds in Grafana UI)

**Option B: UI-first, provision later**
- Create rules in Grafana UI during tuning phase
- Export to YAML once thresholds are stable
- Migrate to provisioned files
- Extra step but allows rapid iteration

**Recommendation: Option A.** The existing Prometheus alert rules have well-established thresholds that have been running (silently) for months. No tuning period needed -- just mirror them. New probe alerts use standard thresholds (probe_success == 0 for 2m). The small number of rules (9 total) makes rebuild iteration manageable.

## Decision: Prometheus ruleFiles Disposition

**Keep existing ruleFiles in prometheus.nix.** They serve as defense-in-depth and show alert state in the Prometheus UI (`/alerts`). They do not interfere with Grafana alerting. Do NOT configure `services.prometheus.alertmanagers` since Grafana's built-in Alertmanager does not accept external alerts.

Future phase (Phase 5) may add additional Prometheus rules for hardware alerts. The ruleFiles section is the right place for those if they are also mirrored as Grafana-managed rules.

## Tailscale HTTPS Probe Considerations

The Tailscale URLs (`*.shad-bangus.ts.net`) are served by Caddy instances bound to Tailscale network interfaces. Blackbox on firebat can probe these URLs IF firebat is on the Tailscale network (which it is -- `modules/gateway/tailscale.nix`). The probes will use Tailscale's network path and verify real Let's Encrypt certificates.

**Caveat:** Caddy's Tailscale-bound listeners use static IPs for reverse proxy backends (see Caddyfile comments at lines 74-94). The blackbox exporter does NOT have this issue because it connects to the Tailscale URL directly, not through a reverse proxy backend.

## Open Questions

1. **Gmail address for SMTP `from_address` and `user`**
   - What we know: Gmail App Password required, port 587, STARTTLS
   - What's unclear: The specific Gmail address to use
   - Recommendation: User provides this during plan execution (added to SOPS)

2. **Notification recipient email**
   - What we know: Contact point needs target email address(es)
   - What's unclear: Same as SMTP sender or different?
   - Recommendation: Use same Gmail address as sender for simplicity (homelab, single operator)

3. **Grafana alert evaluation interval**
   - What we know: Default is 1m, can be customized per group
   - What's unclear: Whether 1m is appropriate for all rules
   - Recommendation: Use 1m for probe alerts (fast detection), 1m for infrastructure alerts (consistent with existing Prometheus 15s scrape interval)

## Sources

### Primary (HIGH confidence)
- [Grafana File Provisioning for Alerting](https://grafana.com/docs/grafana/latest/alerting/set-up/provision-alerting-resources/file-provisioning/) -- YAML format for rules, contact points, policies
- [Grafana provisioning-alerting-examples repo](https://github.com/grafana/provisioning-alerting-examples) -- Official example YAML files, verified exact format
- [Grafana Configure Alertmanager](https://grafana.com/docs/grafana/latest/alerting/set-up/configure-alertmanager/) -- Confirmed built-in Alertmanager handles ONLY Grafana-managed alerts
- [Grafana Email Alert Configuration](https://grafana.com/docs/grafana/latest/alerting/configure-notifications/manage-contact-points/integrations/configure-email/) -- SMTP requirements
- [Grafana Datasource Provisioning](https://grafana.com/docs/grafana/latest/administration/provisioning/) -- UID field in datasource provisioning
- [Prometheus Multi-Target Exporter Guide](https://prometheus.io/docs/guides/multi-target-exporter/) -- Blackbox relabeling pattern
- [NixOS Blackbox Exporter Module](https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/services/monitoring/prometheus/exporters/blackbox.nix) -- AmbientCapabilities for CAP_NET_RAW
- [NixOS Grafana Module](https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/services/monitoring/grafana.nix) -- Provision alerting options
- [Blackbox Exporter Configuration](https://github.com/prometheus/blackbox_exporter/blob/master/CONFIGURATION.md) -- Module definitions
- [PromLabs: Monitoring TLS Certificate Expiration](https://promlabs.com/blog/2024/02/06/monitoring-tls-endpoint-certificate-expiration-with-prometheus/) -- probe_ssl_earliest_cert_expiry usage

### Secondary (MEDIUM confidence)
- [Grafana Community: Gmail SMTP Setup](https://community.grafana.com/t/setup-smtp-with-gmail/85815) -- Gmail App Password format
- [Grafana Community: Default Contact Point File Provision](https://community.grafana.com/t/how-to-change-default-contact-point-and-notification-policy-using-file-provision/84679) -- Override default contact point

### Tertiary (LOW confidence)
- None -- all findings verified against official sources

### Codebase (HIGH confidence)
- `modules/gateway/grafana.nix` -- Existing `$__file{}` pattern for admin password, provisioning structure
- `modules/gateway/prometheus.nix` -- Existing 6 alert rules, scrape configs, ruleFiles pattern
- `modules/gateway/Caddyfile` -- Tailscale URLs, local_certs, service ports
- `hosts/firebat/disko-config.nix` -- ext4 root, 512GB NVMe, no ZFS rollback
- `hosts/firebat/impermanence.nix` -- Minimal (SSH keys only), confirms no "Erase Your Darlings"
- `hosts/ser8/configuration.nix` -- qBittorrent VPN namespace with nginx proxy on port 8080
- `secrets/firebat.yaml` -- Existing `grafana_admin_password` secret
- `.sops.yaml` -- firebat secrets configuration

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- All components are built-in to existing Grafana or have native NixOS modules
- Architecture: HIGH -- Verified Grafana built-in Alertmanager limitation, confirmed firebat impermanence status
- Pitfalls: HIGH -- All pitfalls verified against official docs and codebase analysis
- Alert rule format: HIGH -- Verified against official Grafana provisioning examples repository

**Research date:** 2026-02-12
**Valid until:** 2026-03-14 (30 days -- stable components, well-documented patterns)
