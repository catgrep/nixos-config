# Technology Stack

**Project:** Monitoring, Alerting & Log Aggregation for NixOS Homelab
**Researched:** 2026-02-10

## Existing Infrastructure (DO NOT re-add)

These are already deployed and working. Listed here to prevent duplication and to show integration points.

| Technology | Version | Where | Integration Point |
|------------|---------|-------|-------------------|
| Prometheus | 3.5.0 | firebat | Scrapes node-exporter, zfs-exporter, systemd-exporter, process-exporter, frigate, caddy, jellyfin, exportarr, adguard |
| Grafana | 12.0.7 | firebat | 11 provisioned dashboards, Prometheus datasource, anonymous viewer access |
| node-exporter | - | ser8, firebat, pi4 | Port 9100, system metrics |
| systemd-exporter | - | ser8, firebat, pi4 | Port 9558, unit state/restarts |
| process-exporter | - | ser8, firebat, pi4 | Port 9256, per-service CPU/memory/IO |
| Home Assistant | - | ser8 | MQTT, Companion app push notifications |
| Caddy | - | firebat | Reverse proxy for all services, metrics on :2019 |
| SOPS | - | all hosts | Secrets management with age encryption |

## Recommended Stack Additions

### 1. Grafana Loki (Log Aggregation Server)

| Technology | Version | Where | Purpose | Why |
|------------|---------|-------|---------|-----|
| Grafana Loki | 3.4.5 | firebat | Log aggregation backend, stores logs from all hosts | The standard log backend for the Grafana ecosystem. Already a native NixOS module (`services.loki`). Integrates seamlessly with existing Grafana for log exploration via LogQL. Lightweight single-binary deployment suitable for homelab scale. |

**Confidence:** HIGH -- verified package version 3.4.5 in nixpkgs nixos-25.05 via `nix eval`

**NixOS Module:** `services.loki`

Key options:
- `services.loki.enable` -- enable Grafana Loki
- `services.loki.configuration` -- Nix attribute set mapped to Loki's YAML config
- `services.loki.dataDir` -- data directory (default: `/var/lib/loki`)
- `services.loki.user` / `services.loki.group` -- service user (default: `loki`)

**Deployment location:** firebat (same host as Grafana/Prometheus). Firebat uses ext4 on a 512GB NVMe, no impermanence -- Loki data persists naturally at `/var/lib/loki`. No special persistence configuration needed.

**Configuration pattern:**
```nix
services.loki = {
  enable = true;
  configuration = {
    auth_enabled = false;  # Single-tenant homelab
    server.http_listen_port = 3100;

    common = {
      ring.instance_addr = "127.0.0.1";
      replication_factor = 1;
      path_prefix = "/var/lib/loki";
    };

    schema_config.configs = [{
      from = "2026-02-10";
      store = "tsdb";
      object_store = "filesystem";
      schema = "v13";
      index = {
        prefix = "index_";
        period = "24h";
      };
    }];

    storage_config.filesystem.directory = "/var/lib/loki/chunks";

    limits_config = {
      retention_period = "30d";  # Match Prometheus retention
      ingestion_burst_size_mb = 16;
    };

    compactor = {
      working_directory = "/var/lib/loki/compactor";
      compaction_interval = "10m";
      retention_enabled = true;
      delete_request_store = "filesystem";
    };
  };
};
```

### 2. Alloy (Log Collector -- Promtail Replacement)

| Technology | Version | Where | Purpose | Why |
|------------|---------|-------|---------|-----|
| Grafana Alloy | 1.8.3 | ser8, firebat, pi4 | Collects journald logs and ships to Loki | **Promtail is EOL March 2026** -- one month from now. Alloy is the official replacement, already has a NixOS module (`services.alloy`), and is the future-proof choice. Uses `loki.source.journal` component for systemd journal scraping. Supports HCL-based config with a built-in debugging UI. |

**Confidence:** HIGH -- verified package version 1.8.3 in nixpkgs nixos-25.05 via `nix eval`. Promtail EOL confirmed for March 2026 by Grafana Labs.

**Why Alloy over Promtail:**
- Promtail enters EOL March 2, 2026 -- installing it now would require a migration within weeks
- Alloy has a NixOS module (`services.alloy`) with `enable`, `configPath`, `extraFlags`, `environmentFile`, `package` options
- Alloy provides a debugging UI at port 12345 for inspecting pipeline state
- Alloy uses the same Loki write protocol, so Loki config is identical regardless of collector
- Alloy config uses HCL-like syntax, not YAML -- slightly different but well-documented migration path

**NixOS Module:** `services.alloy`

Key options:
- `services.alloy.enable` -- enable Grafana Alloy
- `services.alloy.configPath` -- path to directory containing `*.alloy` config files, or single file in Nix store
- `services.alloy.extraFlags` -- extra CLI flags
- `services.alloy.environmentFile` -- systemd EnvironmentFile for secrets
- `services.alloy.package` -- the grafana-alloy package

**Configuration pattern (Alloy HCL format):**
```hcl
// /etc/alloy/config.alloy -- journal scraping for NixOS host

loki.source.journal "journal" {
  forward_to = [loki.write.local.receiver]

  relabel_rules = loki.relabel.journal.rules
  labels = {
    job = "journal",
  }
}

loki.relabel "journal" {
  forward_to = []

  rule {
    source_labels = ["__journal__systemd_unit"]
    target_label  = "unit"
  }
  rule {
    source_labels = ["__journal__hostname"]
    target_label  = "hostname"
  }
  rule {
    source_labels = ["__journal_priority_keyword"]
    target_label  = "priority"
  }
  rule {
    source_labels = ["__journal_syslog_identifier"]
    target_label  = "syslog_identifier"
  }
}

loki.write "local" {
  endpoint {
    url = "http://firebat.local:3100/loki/api/v1/push"
  }
}
```

**NixOS integration pattern:**
```nix
# Write Alloy config as a Nix store path, reference via configPath
services.alloy = {
  enable = true;
  configPath = pkgs.writeTextDir "config.alloy" ''
    // ... Alloy HCL config here ...
  '' + "/config.alloy";
};
```

**Note on ser8 impermanence:** Alloy is stateless (it reads journal and pushes to Loki). No persistence directory needed. The journal itself is already persisted at `/var/log` on ser8 via bind mount to `/persist/var/log`.

### 3. Blackbox Exporter (HTTP Service Probing)

| Technology | Version | Where | Purpose | Why |
|------------|---------|-------|---------|-----|
| prometheus-blackbox-exporter | 0.27.0 | firebat | HTTP endpoint probes for service uptime/latency | Native NixOS module (`services.prometheus.exporters.blackbox`). Probes services from the gateway perspective (same host as Caddy). Provides `probe_success`, `probe_duration_seconds`, `probe_http_status_code`, `probe_ssl_earliest_cert_expiry` metrics. Enables uptime tracking dashboards. |

**Confidence:** HIGH -- verified package version 0.27.0 in nixpkgs nixos-25.05 via `nix eval`

**NixOS Module:** `services.prometheus.exporters.blackbox`

Key options:
- `services.prometheus.exporters.blackbox.enable`
- `services.prometheus.exporters.blackbox.port` (default: 9115)
- `services.prometheus.exporters.blackbox.configFile` -- probe module definitions
- `services.prometheus.exporters.blackbox.openFirewall`

**Configuration pattern:**
```nix
# On firebat -- blackbox exporter config
services.prometheus.exporters.blackbox = {
  enable = true;
  port = 9115;
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
      http_2xx_no_tls_verify = {
        prober = "http";
        timeout = "10s";
        http = {
          valid_http_versions = [ "HTTP/1.1" "HTTP/2.0" ];
          tls_config.insecure_skip_verify = true;
          preferred_ip_protocol = "ip4";
        };
      };
      icmp_ping = {
        prober = "icmp";
        timeout = "5s";
      };
    };
  });
};
```

**Prometheus scrape config addition (on firebat):**
```nix
# Added to services.prometheus.scrapeConfigs
{
  job_name = "blackbox-http";
  metrics_path = "/probe";
  params.module = [ "http_2xx_no_tls_verify" ];
  static_configs = [{
    targets = [
      "http://ser8.local:8096"    # Jellyfin
      "http://ser8.local:8989"    # Sonarr
      "http://ser8.local:7878"    # Radarr
      "http://ser8.local:9696"    # Prowlarr
      "http://ser8.local:8085"    # SABnzbd
      "http://ser8.local:80"      # Frigate
      "http://ser8.local:8123"    # Home Assistant
      "http://ser8.local:8080"    # qBittorrent (via nginx proxy)
      "http://pi4.local:3000"     # AdGuard Home
      "http://firebat.local:3000" # Grafana
      "http://firebat.local:9090" # Prometheus
    ];
  }];
  relabel_configs = [
    { source_labels = [ "__address__" ]; target_label = "__param_target"; }
    { source_labels = [ "__param_target" ]; target_label = "instance"; }
    { target_label = "__address__"; replacement = "localhost:9115"; }
  ];
  scrape_interval = "60s";
}
```

### 4. Grafana SMTP (Email Alerting)

| Technology | Version | Where | Purpose | Why |
|------------|---------|-------|---------|-----|
| Grafana SMTP config | N/A (Grafana setting) | firebat | Sends alert notification emails via Gmail | Built into Grafana -- no new service needed. Uses `services.grafana.settings.smtp` NixOS options. Gmail App Password stored in SOPS. Enables email contact points for Grafana Unified Alerting. |

**Confidence:** HIGH -- NixOS module has explicit `services.grafana.settings.smtp.*` options

**NixOS configuration pattern:**
```nix
# SOPS secret for Gmail App Password
sops.secrets.grafana_smtp_password = {
  owner = "grafana";
  group = "grafana";
  mode = "0400";
};

services.grafana.settings.smtp = {
  enabled = true;
  host = "smtp.gmail.com:587";
  user = "your-email@gmail.com";
  # Use $__file{} provider to avoid password in Nix store
  password = "$__file{${config.sops.secrets.grafana_smtp_password.path}}";
  from_address = "your-email@gmail.com";
  from_name = "Homelab Alerts";
  startTLS_policy = "MandatoryStartTLS";
};
```

**Gmail prerequisite:** Generate a Gmail App Password at https://myaccount.google.com/apppasswords (requires 2FA enabled). Store in SOPS as `grafana_smtp_password` in `secrets/firebat.yaml`.

### 5. Grafana Unified Alerting (Alert Rules + Contact Points)

| Technology | Version | Where | Purpose | Why |
|------------|---------|-------|---------|-----|
| Grafana Alerting Provisioning | N/A (Grafana 12.x built-in) | firebat | Declarative alert rules, contact points, notification policies | NixOS provides `services.grafana.provision.alerting.*` options. Alert rules can query both Prometheus AND Loki datasources. Enables fully declarative alerting without manual UI setup. |

**Confidence:** HIGH -- NixOS module `services.grafana.provision.alerting` confirmed with sub-options for `rules`, `contactPoints`, `policies`, `muteTimings`, `templates`

**NixOS Module options:**
- `services.grafana.provision.alerting.rules.settings` -- alert rule definitions (Nix attrset -> YAML)
- `services.grafana.provision.alerting.rules.path` -- or path to YAML file
- `services.grafana.provision.alerting.contactPoints.settings` -- contact point definitions
- `services.grafana.provision.alerting.contactPoints.path`
- `services.grafana.provision.alerting.policies.settings` -- notification routing policies
- `services.grafana.provision.alerting.policies.path`
- `services.grafana.provision.alerting.muteTimings.settings` -- mute windows
- `services.grafana.provision.alerting.templates.settings` -- notification templates

**Important:** Cannot set both `.settings` and `.path` for the same category. Choose one approach. Recommend `.settings` for full declarative control in Nix.

**Note:** The existing Prometheus `ruleFiles` with `alert:` definitions (in `modules/gateway/prometheus.nix`) define recording/alerting rules at the Prometheus level. These fire alerts but have no notification routing -- Prometheus alone cannot send emails. Grafana Unified Alerting replaces or complements this by:
1. Evaluating alert rules directly in Grafana (can query Prometheus AND Loki)
2. Routing fired alerts to contact points (email, etc.)
3. Supporting notification policies and mute timings

**Strategy:** Keep existing Prometheus alert rules for recording purposes. Add Grafana alerting rules that reference the same conditions but route to email contact points. This provides dual-layer alerting.

### 6. Home Assistant Prometheus Integration

| Technology | Version | Where | Purpose | Why |
|------------|---------|-------|---------|-----|
| HA Prometheus integration | Built into HA | ser8 | Exposes HA entity metrics for Prometheus scraping | Built-in HA integration -- just needs `prometheus:` in HA's `configuration.yaml`. Exposes all HA entity states as Prometheus metrics at `/api/prometheus` on port 8123. Enables dashboards for HA sensor data (temperature, humidity, device states, automation triggers). |

**Confidence:** HIGH -- official HA integration, documented at home-assistant.io/integrations/prometheus/

**HA configuration (declarative in Nix):**
```nix
services.home-assistant.config.prometheus = {};
# That's it -- minimal config exposes all entities
# Optional: filter with include/exclude domains
```

**Prometheus scrape config addition:**
```nix
{
  job_name = "homeassistant";
  scrape_interval = "60s";
  metrics_path = "/api/prometheus";
  bearer_token_file = "/path/to/ha-token";  # Long-lived access token
  static_configs = [{
    targets = [ "ser8.local:8123" ];
  }];
}
```

**Authentication:** Requires a Home Assistant Long-Lived Access Token. Generate in HA UI: Profile -> Security -> Long-Lived Access Tokens -> Create Token. Store in SOPS, make available to Prometheus on firebat.

**Alternative approach (no auth):** If HA's Prometheus endpoint is only accessed from the local network and HA has `trusted_proxies` configured (which it does for `192.168.68.0/24`), the bearer token may not be required for local scraping. Verify during implementation.

### 7. Grafana Loki Datasource

| Technology | Version | Where | Purpose | Why |
|------------|---------|-------|---------|-----|
| Grafana Loki datasource | N/A (provisioning config) | firebat | Connects Grafana to Loki for log exploration | Extends existing `services.grafana.provision.datasources` with a Loki entry. Enables Explore view for logs and LogQL-based alert rules. |

**Confidence:** HIGH -- standard Grafana provisioning, same pattern as existing Prometheus datasource

**Configuration pattern:**
```nix
# Add to existing datasources list in modules/gateway/grafana.nix
services.grafana.provision.datasources.settings.datasources = [
  {
    name = "Prometheus";
    type = "prometheus";
    access = "proxy";
    url = "http://localhost:9090";
    isDefault = true;
  }
  {
    name = "Loki";
    type = "loki";
    access = "proxy";
    url = "http://localhost:3100";
  }
];
```

## Complete Port Allocation

New ports introduced by this milestone:

| Port | Service | Host | Existing/New |
|------|---------|------|-------------|
| 3100 | Loki HTTP API | firebat | NEW |
| 9095 | Loki gRPC (internal) | firebat | NEW |
| 9115 | Blackbox exporter | firebat | NEW |
| 12345 | Alloy debug UI | each host | NEW |

## Alternatives Considered

| Category | Recommended | Alternative | Why Not |
|----------|-------------|-------------|---------|
| Log collector | Grafana Alloy | Promtail | Promtail EOL March 2026 -- installing it now would require migration within weeks. Alloy has a NixOS module, is the official successor, and supports the same journal scraping. |
| Log collector | Grafana Alloy | Fluentd / Fluent Bit | Not part of the Grafana ecosystem. Adds operational complexity without benefit when Loki + Alloy provide a fully integrated stack. |
| Log backend | Loki | Elasticsearch/OpenSearch | Massive resource overhead for a homelab. Loki's label-based indexing is far lighter. Native Grafana integration. NixOS module available. |
| Log backend | Loki | journald-remote (systemd) | Only centralizes journal files -- no query language, no Grafana integration, no alerting on log patterns. |
| Alerting | Grafana Unified Alerting | Prometheus Alertmanager | Alertmanager is a separate service. Grafana Unified Alerting is built into Grafana 12.x, supports both Prometheus and Loki datasources, and has NixOS provisioning support. Less infrastructure to manage. |
| Email provider | Gmail SMTP | Self-hosted SMTP / SES | Gmail App Passwords are simple and free for homelab volume. No DNS/SPF/DKIM setup needed. Self-hosted SMTP is unnecessary complexity. |
| HTTP probing | Blackbox exporter | Uptime Kuma | Blackbox exporter integrates natively with Prometheus/Grafana. Uptime Kuma is a standalone tool with its own UI -- redundant when Grafana already exists. |
| HA metrics | HA Prometheus integration | Custom exporter | HA has a built-in Prometheus integration. No external exporter needed. One line of config (`prometheus: {}`). |

## What NOT to Add

| Anti-Technology | Why Avoid |
|-----------------|-----------|
| **Prometheus Alertmanager** | Grafana Unified Alerting replaces this for our use case. Alertmanager would be a separate service to configure and maintain when Grafana already handles alert routing, grouping, and notification. |
| **Promtail** | EOL March 2, 2026. Would require immediate migration to Alloy. Start with Alloy directly. |
| **Uptime Kuma** | Standalone uptime monitor with its own web UI. Redundant since blackbox exporter + Grafana provides the same functionality within the existing stack. |
| **Elasticsearch / OpenSearch** | Orders of magnitude more resource-hungry than Loki. Designed for full-text search at enterprise scale. Loki's label-based approach is better suited to structured log queries from systemd journal. |
| **Grafana OnCall** | Enterprise-grade incident management. Overkill for a homelab. Email notifications via SMTP are sufficient. |
| **Thanos / Cortex** | Multi-cluster Prometheus backends. Single Prometheus instance is fine for 3-4 hosts. |

## Secrets Required (New SOPS Entries)

| Secret | SOPS File | Used By | Purpose |
|--------|-----------|---------|---------|
| `grafana_smtp_password` | `secrets/firebat.yaml` | Grafana SMTP | Gmail App Password for sending alert emails |
| `ha_prometheus_token` | `secrets/firebat.yaml` | Prometheus | HA Long-Lived Access Token for scraping `/api/prometheus` |

## Firewall Rules Required

| Host | Port | Protocol | Service | Direction |
|------|------|----------|---------|-----------|
| firebat | 3100 | TCP | Loki | Inbound from ser8, pi4 (Alloy pushes logs) |
| firebat | 9115 | TCP | Blackbox exporter | Localhost only (Prometheus scrapes) |

## Version Summary

All versions verified against nixpkgs nixos-25.05 (the flake's nixpkgs input) on 2026-02-10:

| Package | nixos-25.05 Version | Latest Upstream | Gap | Risk |
|---------|---------------------|-----------------|-----|------|
| grafana-loki | 3.4.5 | 3.6.5 | 2 minor versions | LOW -- stable API, filesystem storage unchanged |
| grafana-alloy | 1.8.3 | 1.13.0 | 5 minor versions | LOW -- journal scraping and loki.write stable since 1.x |
| prometheus-blackbox-exporter | 0.27.0 | 0.27.x | Patch at most | NONE |
| grafana | 12.0.7 | 12.x | Patches | NONE -- unified alerting stable since Grafana 10 |
| prometheus | 3.5.0 | 3.5.x | Current | NONE |

No packages require nixpkgs-unstable. Everything is available in the nixos-25.05 channel.

## Sources

- [NixOS Wiki: Grafana Loki](https://wiki.nixos.org/wiki/Grafana_Loki) -- NixOS module usage and configuration examples
- [NixOS Wiki: Grafana](https://wiki.nixos.org/wiki/Grafana) -- Grafana provisioning patterns including alerting
- [NixOS Wiki: Prometheus](https://wiki.nixos.org/wiki/Prometheus) -- Exporter module patterns
- [nixpkgs services/monitoring/loki.nix](https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/services/monitoring/loki.nix) -- Loki NixOS module source
- [nixpkgs exporters/blackbox.nix](https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/services/monitoring/prometheus/exporters/blackbox.nix) -- Blackbox exporter module source
- [MyNixOS: services.alloy options](https://mynixos.com/nixpkgs/options/services.alloy) -- Alloy NixOS module options
- [MyNixOS: services.grafana.settings.smtp](https://mynixos.com/options/services.grafana.settings.smtp) -- Grafana SMTP NixOS options
- [MyNixOS: services.grafana.provision.alerting.rules.settings](https://mynixos.com/nixpkgs/options/services.grafana.provision.alerting.rules.settings) -- Alerting provisioning options
- [Grafana Loki Releases](https://github.com/grafana/loki/releases) -- Version tracking (3.6.5 latest)
- [Grafana Alloy Releases](https://github.com/grafana/alloy/releases) -- Version tracking (1.13.0 latest)
- [Grafana Alloy: loki.source.journal](https://grafana.com/docs/alloy/latest/reference/components/loki/loki.source.journal/) -- Journal scraping component docs
- [Grafana Alloy: Migrate from Promtail](https://grafana.com/docs/alloy/latest/set-up/migrate/from-promtail/) -- Migration guide
- [Promtail EOL Announcement](https://community.grafana.com/t/promtail-end-of-life-eol-march-2026-how-to-migrate-to-grafana-alloy-for-existing-loki-server-deployments/159636) -- Official EOL timeline
- [Grafana: Configure email for alerts](https://grafana.com/docs/grafana/latest/alerting/configure-notifications/manage-contact-points/integrations/configure-email/) -- SMTP setup docs
- [Grafana: File provisioning for alerting](https://grafana.com/docs/grafana/latest/alerting/set-up/provision-alerting-resources/file-provisioning/) -- Provisioning format
- [Home Assistant: Prometheus Integration](https://www.home-assistant.io/integrations/prometheus/) -- HA metrics endpoint
- [Blackbox Exporter Configuration](https://github.com/prometheus/blackbox_exporter/blob/master/CONFIGURATION.md) -- Module configuration reference
- [Gmail SMTP with Grafana](https://community.grafana.com/t/setup-smtp-with-gmail/85815) -- Gmail App Password setup
