# Architecture: Monitoring, Alerting, and Log Aggregation Integration

**Domain:** Observability stack for NixOS homelab (Loki, Promtail/Alloy, Blackbox Exporter, Grafana Alerting)
**Researched:** 2026-02-10
**Confidence:** HIGH (verified against NixOS module sources, Grafana official docs, existing codebase analysis)

## Current State Summary

The homelab already has a solid metrics foundation:

- **firebat** runs Prometheus (port 9090) and Grafana (port 3000) with declarative dashboard provisioning
- **All hosts** run node-exporter (9100), systemd-exporter (9558), process-exporter (9256)
- **ser8** additionally runs zfs-exporter (9134), frigate-exporter (9710), jellyfin-exporter (9711), exportarr (9707-9709)
- **pi4** runs adguard-exporter (9618)
- Prometheus already has basic alert rules (HostDown, HighDiskUsage, HighMemoryUsage, ZFSPoolUnhealthy, HighCPUTemperature, CameraStorageHigh) but **no alertmanager** to actually deliver them
- Grafana provisioning uses `services.grafana.provision` for datasources and file-based dashboards via tmpfiles symlinks
- Caddy on firebat proxies all services, including Tailscale-bound endpoints

**What is missing:**

1. **Log aggregation** -- no centralized logging. Logs only exist in each host's journald.
2. **Alert delivery** -- Prometheus rules exist but nothing sends notifications.
3. **Endpoint probing** -- no synthetic checks for service availability (HTTP, TCP, ICMP).
4. **Home Assistant metrics** -- HA has a built-in Prometheus integration that is not enabled.

## Recommended Architecture

### System Topology

```
                        firebat (192.168.68.63)                 ser8 (192.168.68.65)
                    +------------------------------+        +----------------------------+
                    |                              |        |                            |
                    |  Prometheus (:9090)           |        |  Promtail/Alloy            |
                    |    - scrapes all exporters    |  push  |    - scrapes journald      |
                    |    - scrapes blackbox         | -----> |    - labels: host=ser8     |
                    |    - scrapes HA prometheus    |  logs  |                            |
                    |    - alert rules evaluate     |        |  HA Prometheus (:8123)     |
                    |                              |        |    - /api/prometheus        |
                    |  Loki (:3100)                 |        |    - entity metrics         |
                    |    - receives logs from all   |        |                            |
                    |    - TSDB index + filesystem  |        |  (existing exporters)      |
                    |    - 30-day retention         |        +----------------------------+
                    |                              |
                    |  Blackbox Exporter (:9115)    |        pi4 (192.168.68.56)
                    |    - HTTP probes to services  |        +----------------------------+
                    |    - TCP probes              |        |                            |
                    |    - ICMP probes              |        |  Promtail/Alloy            |
                    |                              |  push  |    - scrapes journald      |
                    |  Grafana (:3000)              | <----- |    - labels: host=pi4      |
                    |    - Prometheus datasource    |  logs  |                            |
                    |    - Loki datasource (NEW)    |        |  (existing exporters)      |
                    |    - Alert rules (NEW)        |        +----------------------------+
                    |    - Contact points (NEW)     |
                    |    - Dashboards (existing+new)|
                    |                              |
                    |  Promtail/Alloy              |
                    |    - scrapes local journald   |
                    |    - labels: host=firebat     |
                    +------------------------------+
```

### Component Placement Rationale

| Component | Host | Why There |
|-----------|------|-----------|
| **Loki** | firebat | Co-locate with Grafana (datasource is localhost). firebat is the monitoring hub. Avoids cross-host queries for log viewing. firebat has impermanence like ser8 so persistent storage needs the same `/persist` treatment, but firebat has less workload pressure than ser8. |
| **Promtail/Alloy** | ALL hosts (ser8, firebat, pi4) | Each host pushes its own logs to Loki. This is the standard model -- log collectors run where logs originate. |
| **Blackbox Exporter** | firebat | Co-locate with Prometheus (avoids network hops for scrape). Probes from firebat test the same network path that users take (through the reverse proxy). |
| **Grafana Alerting** | firebat | Grafana already runs there. Alert rules, contact points, and notification policies are provisioned declaratively alongside existing dashboards. |
| **HA Prometheus** | ser8 | Home Assistant already runs on ser8. Just enable the built-in `prometheus:` integration in HA's configuration.yaml. Prometheus on firebat scrapes it like any other exporter. |

### Promtail vs Alloy Decision

**Use Promtail for now. Plan migration to Alloy for Phase 2.**

Rationale:
- Promtail has a mature, well-documented NixOS module (`services.promtail`) with `configuration` attribute set support
- Promtail LTS runs until February 28, 2026 -- that is close but still within support window
- Alloy has a NixOS module (`services.alloy`) but uses a file-based configuration format (HCL-like `.alloy` files), not Nix attribute sets
- For a homelab with 3 hosts doing journal scraping, Promtail is simpler and proven
- Alloy's 285MB binary size is a concern for pi4 (ARM, limited resources)
- Migration path exists: `alloy convert --source-format=promtail` converts configs automatically

**Confidence: MEDIUM** -- Promtail EOL is Feb 28, 2026 (18 days from today). If timeline slips, start with Alloy directly. The architecture is the same either way (push model to Loki).

## New Components Detail

### 1. Loki (on firebat)

**NixOS service:** `services.loki`

```
Module: modules/gateway/loki.nix (NEW)
Port: 3100
Storage: /var/lib/loki (filesystem, persisted)
Index: TSDB (recommended for Loki 2.8+, replaces deprecated boltdb-shipper)
Retention: 30 days (match Prometheus retention)
```

**Key configuration decisions:**
- `auth_enabled = false` -- single-tenant homelab, no need for multi-tenancy
- Monolithic deployment mode (`target = "all"`) -- appropriate for <20GB/day log volume
- TSDB index store -- boltdb-shipper is deprecated
- Filesystem object store for chunks -- simplest backend, no external dependencies
- Schema v13 (latest) with TSDB
- `compactor` enabled for retention enforcement

**Storage persistence:** firebat uses impermanence (disko + ZFS like ser8). Loki data directory `/var/lib/loki` needs to be added to firebat's persistence configuration. Check if firebat has an impermanence.nix -- if not, Loki data lives on root filesystem which may or may not be ephemeral.

**Important:** firebat's `hosts/firebat/configuration.nix` imports disko and impermanence modules (from x86Modules in flake.nix), but I did not find an impermanence.nix in hosts/firebat/. This means firebat may NOT have "Erase Your Darlings" enabled (unlike ser8 which has explicit `initrd.postDeviceCommands` for ZFS rollback). Verify before deployment -- if firebat does not rollback root on boot, `/var/lib/loki` persists naturally. If it does, add to persistence config.

### 2. Promtail (on ALL hosts)

**NixOS service:** `services.promtail`

```
Module: modules/servers/promtail.nix (NEW, in common servers module)
Port: 9080 (HTTP status/ready endpoint, not externally exposed)
Scrape: systemd journal
Push target: http://firebat.local:3100/loki/api/v1/push
```

**Key configuration decisions:**
- Scrape journald (primary log source on NixOS/systemd systems)
- Label with `host = config.networking.hostName` for multi-host filtering
- Relabel `__journal__systemd_unit` to `unit` label for per-service filtering
- Relabel `__journal_priority` to `priority` for severity filtering
- `max_age = "12h"` for journal scraping to avoid re-ingesting old logs on restart
- Positions file at `/var/lib/promtail/positions.yaml` (needs persistence on ser8)

**Pi4 consideration:** Promtail runs on ARM. The nixpkgs `promtail` package supports aarch64-linux. Verify this builds/cross-compiles for the pi4 target (which uses nixos-raspberrypi's nixosSystem, not standard nixpkgs).

### 3. Blackbox Exporter (on firebat)

**NixOS service:** `services.prometheus.exporters.blackbox`

```
Module: modules/gateway/blackbox.nix (NEW)
Port: 9115
Probes: HTTP, TCP, ICMP
```

**Probe targets (what to monitor):**

| Probe Type | Target | Purpose |
|------------|--------|---------|
| `http_2xx` | `http://ser8.local:8096` | Jellyfin availability |
| `http_2xx` | `http://ser8.local:8989` | Sonarr availability |
| `http_2xx` | `http://ser8.local:7878` | Radarr availability |
| `http_2xx` | `http://ser8.local:9696` | Prowlarr availability |
| `http_2xx` | `http://ser8.local:8085` | SABnzbd availability |
| `http_2xx` | `http://ser8.local:5000` | Frigate availability |
| `http_2xx` | `http://ser8.local:8123` | Home Assistant availability |
| `http_2xx` | `http://pi4.local:3000` | AdGuard Home availability |
| `http_2xx` | `http://localhost:3000` | Grafana self-check |
| `tcp_connect` | `ser8.local:1883` | Mosquitto MQTT broker |
| `icmp` | `ser8.local` | ser8 reachability |
| `icmp` | `pi4.local` | pi4 reachability |

**Prometheus scrape configuration pattern:**
Blackbox exporter uses the multi-target pattern: Prometheus sends the target as a query parameter, and the blackbox exporter probes it and returns metrics. This requires relabel_configs in the Prometheus scrape job.

```
scrape_configs:
  - job_name: 'blackbox-http'
    metrics_path: /probe
    params:
      module: [http_2xx]
    static_configs:
      - targets:
        - http://ser8.local:8096
        - http://ser8.local:8989
        - ...
    relabel_configs:
      - source_labels: [__address__]
        target_label: __param_target
      - source_labels: [__param_target]
        target_label: instance
      - target_label: __address__
        replacement: localhost:9115  # blackbox exporter address
```

### 4. Grafana Alerting (on firebat)

**NixOS integration:** `services.grafana.provision.alerting`

```
Module: modules/gateway/grafana.nix (MODIFY existing)
New files: alerting rules YAML, contact points YAML
Provisioning: Declarative via services.grafana.provision.alerting.*
```

**NixOS provides three alerting provisioning options:**

| Option | Purpose |
|--------|---------|
| `services.grafana.provision.alerting.rules.settings` | Alert rule groups as Nix attrset |
| `services.grafana.provision.alerting.contactPoints.settings` | Contact points (email, webhook, etc.) |
| `services.grafana.provision.alerting.policies.settings` | Notification routing policies |

**Alert delivery approach:**

Replace the current Prometheus-only alert rules (which have no delivery mechanism) with Grafana Unified Alerting. Grafana can evaluate both Prometheus queries and Loki log queries.

**Contact point options for a homelab:**
1. **Email via SMTP** -- requires SMTP credentials, adds complexity
2. **Pushover** -- simple push notifications, $5 one-time purchase, good for homelab
3. **Gotify** -- self-hosted push notifications, another service to run
4. **Webhook to Home Assistant** -- HA already sends push notifications to the Companion app
5. **Discord/Telegram webhook** -- free, simple webhook integration

**Recommendation:** Use **webhook to Home Assistant** as the primary contact point. HA already has the `notify.mobile_app_*` service configured and working for Frigate alerts. This avoids adding another notification dependency and reuses the existing push notification pipeline. For a secondary channel, add Discord or Telegram webhook (simple, no extra services).

### 5. Home Assistant Prometheus Integration (on ser8)

**Configuration:** Add to HA's declarative config in `modules/automation/home-assistant.nix`

```
Module: modules/automation/home-assistant.nix (MODIFY existing)
Endpoint: http://ser8.local:8123/api/prometheus
Auth: Long-lived access token (stored in SOPS)
```

**What it exposes:**
- Entity states as Prometheus metrics (sensor values, binary sensor states, switch states)
- Device tracker states
- Climate entity metrics
- Custom namespace support (e.g., `hass_sensor_temperature`)

**Prometheus scrape config addition** (on firebat in prometheus.nix):
```
{
  job_name = "home-assistant";
  metrics_path = "/api/prometheus";
  bearer_token_file = "/path/to/ha-token";
  static_configs = [{ targets = [ "ser8.local:8123" ]; }];
  scrape_interval = "30s";
}
```

**Secret management:** The HA long-lived access token needs to be available to Prometheus on firebat. Options:
1. Store in SOPS `secrets/firebat.yaml` and reference via `sops.secrets`
2. Store in SOPS `secrets/shared.yaml` (readable by all hosts)

Use option 1 (firebat-specific) since only Prometheus needs it.

## Data Flow Diagrams

### Flow 1: Log Aggregation (Journal to Loki to Grafana)

```
ser8 journald                    firebat
+-----------------+    push     +------------------+    query    +------------------+
| systemd-journal | --> Promtail --> Loki (:3100)    | <--------- | Grafana (:3000)  |
| (all services)  |   :9080     | TSDB + filesystem |            | Explore / Dash   |
+-----------------+             +------------------+            +------------------+
                                       ^
pi4 journald                           |
+-----------------+    push            |
| systemd-journal | --> Promtail ------+
+-----------------+

firebat journald                       |
+-----------------+    push            |
| systemd-journal | --> Promtail ------+
| (local)         |   (localhost)
+-----------------+
```

**Labels applied by Promtail:**
- `host` = hostname (ser8, firebat, pi4)
- `unit` = systemd unit name (jellyfin.service, caddy.service, etc.)
- `priority` = syslog priority (0-7)
- `job` = "systemd-journal"

**Example Grafana LogQL queries:**
- All ser8 logs: `{host="ser8"}`
- Jellyfin errors: `{host="ser8", unit="jellyfin.service"} |= "error"`
- All errors across hosts: `{job="systemd-journal"} | priority <= 3`

### Flow 2: Endpoint Probing (Blackbox to Prometheus to Grafana)

```
firebat
+---------------------+         +------------------+         +------------------+
| Blackbox Exporter   | <------ | Prometheus       | ------> | Grafana          |
| (:9115)             | scrape  | (:9090)          | query   | (:3000)          |
|                     |         |                  |         | Alert Rules      |
| Probes:             |         | Job: blackbox-*  |         | + Dashboard      |
|  HTTP -> ser8:8096  |         | relabel_configs  |         |                  |
|  HTTP -> ser8:8989  |         |                  |         |                  |
|  HTTP -> pi4:3000   |         |                  |         |                  |
|  TCP  -> ser8:1883  |         |                  |         |                  |
|  ICMP -> ser8       |         |                  |         |                  |
+---------------------+         +------------------+         +------------------+
```

**Key metrics from blackbox exporter:**
- `probe_success` (0 or 1) -- primary availability indicator
- `probe_duration_seconds` -- response time
- `probe_http_status_code` -- HTTP status for HTTP probes
- `probe_ssl_earliest_cert_expiry` -- certificate expiry (useful for Caddy certs)

### Flow 3: Alert Delivery Pipeline

```
                              firebat
+------------------+         +------------------+         +------------------+
| Prometheus       | ------> | Grafana          | ------> | Contact Points   |
| (data source)    | query   | Unified Alerting |         |                  |
|                  |         |                  | webhook | 1. HA webhook    |
| Loki             | ------> | Alert Rules      | ------> |    -> mobile push|
| (data source)    | query   |  - Metric alerts |         |                  |
|                  |         |  - Log alerts    | webhook | 2. Discord/Tg   |
+------------------+         | Notification     | ------> |    (secondary)   |
                             | Policies         |         |                  |
                             +------------------+         +------------------+
```

**Alert categories:**

| Category | Data Source | Example Alerts |
|----------|------------|----------------|
| Infrastructure | Prometheus | HostDown, HighDiskUsage, HighMemoryUsage, HighCPUTemp |
| ZFS Health | Prometheus | ZFSPoolUnhealthy, ZFSScrubErrors, CameraStorageHigh |
| Service Availability | Prometheus (blackbox) | ServiceDown (HTTP probe fails), SlowResponse |
| Service Health | Prometheus (exporters) | JellyfinTranscodeFailed, SonarrQueueStuck |
| Log Anomalies | Loki | ErrorRateSpike, ServiceCrashLoop (from journal) |
| Home Automation | Prometheus (HA) | CameraOffline, MQTTDisconnected |

### Flow 4: Home Assistant Metrics to Prometheus

```
ser8
+------------------+  scrape   +------------------+
| Home Assistant   | <-------- | Prometheus        |
| (:8123)          |           | (firebat:9090)    |
| /api/prometheus  |           |                   |
|                  |           | job: home-assistant|
| Metrics:         |           |                   |
|  - entity states |           |                   |
|  - sensor values |           |                   |
|  - camera status |           |                   |
+------------------+           +------------------+
       ^
       | long-lived access token
       | (from SOPS on firebat)
```

## NixOS Module Placement

### New Files

| File | Host(s) | Purpose |
|------|---------|---------|
| `modules/gateway/loki.nix` | firebat | Loki log aggregation server |
| `modules/gateway/blackbox.nix` | firebat | Blackbox exporter for endpoint probing |
| `modules/servers/promtail.nix` | ALL (ser8, firebat, pi4) | Journal log shipping to Loki |

### Modified Files

| File | Changes |
|------|---------|
| `modules/gateway/default.nix` | Add imports for `loki.nix`, `blackbox.nix` |
| `modules/gateway/grafana.nix` | Add Loki datasource, alerting provisioning (rules, contact points, policies) |
| `modules/gateway/prometheus.nix` | Add blackbox scrape jobs, HA scrape job, alertmanager reference |
| `modules/automation/home-assistant.nix` | Enable `prometheus:` integration in HA config |
| `hosts/ser8/impermanence.nix` | Add `/var/lib/promtail` to persistence |
| `hosts/firebat/configuration.nix` | Potentially add persistence for `/var/lib/loki` (investigate impermanence status) |
| `secrets/firebat.yaml` | Add `ha_prometheus_token` for Prometheus to scrape HA |
| `modules/gateway/Caddyfile` | Optionally add `loki.vofi` for internal Loki access |

### Module Dependency Graph

```
modules/gateway/default.nix
  |-- caddy.nix          (existing)
  |-- prometheus.nix     (MODIFY: add blackbox + HA scrape jobs)
  |-- grafana.nix        (MODIFY: add Loki datasource + alerting)
  |-- tailscale.nix      (existing)
  |-- loki.nix           (NEW)
  |-- blackbox.nix       (NEW)

modules/servers/default.nix
  |-- monitoring.nix     (existing, already on all hosts)
  |-- promtail.nix       (NEW, auto-included on all hosts)
  |-- ...

modules/automation/home-assistant.nix  (MODIFY: add prometheus integration)
```

## Patterns to Follow

### Pattern 1: Consistent Declarative Provisioning

**What:** All new Grafana alert rules, contact points, and notification policies are provisioned declaratively through `services.grafana.provision.alerting.*` -- never created manually in the UI.

**Why:** Matches existing pattern for dashboards and datasources. Reproducible across rebuilds. Version controlled.

**How:**
```nix
services.grafana.provision.alerting = {
  rules.settings = {
    apiVersion = 1;
    groups = [ ... ];
  };
  contactPoints.settings = {
    apiVersion = 1;
    contactPoints = [ ... ];
  };
  policies.settings = {
    apiVersion = 1;
    policies = [ ... ];
  };
};
```

### Pattern 2: Push Model for Logs (Not Pull)

**What:** Promtail pushes logs to Loki. Loki does not pull from hosts.

**Why:** This is Loki's design. Unlike Prometheus (pull-based for metrics), Loki receives log data via HTTP push. Each host runs its own Promtail instance that reads the local journal and pushes to the central Loki.

**Implication:** Promtail needs to know Loki's address. Use `http://firebat.local:3100/loki/api/v1/push`. mDNS works for Promtail since it runs on the LAN interface (unlike Caddy's Tailscale bindings which cannot resolve .local names).

### Pattern 3: Separate Alert Rules from Prometheus Rules

**What:** Migrate existing Prometheus `ruleFiles` alert rules to Grafana Unified Alerting.

**Why:** Current Prometheus rules (in prometheus.nix) define alerts but have no alertmanager to deliver them. Grafana Unified Alerting both evaluates rules AND delivers notifications without needing a separate Alertmanager service.

**Migration path:**
1. Keep existing Prometheus recording rules (if any) in Prometheus
2. Move alert rules to Grafana provisioned alerting
3. Remove unused `ruleFiles` from prometheus.nix (or keep as defense-in-depth with Alertmanager later)

### Pattern 4: Host Label Consistency

**What:** All Promtail instances add a `host` label matching `config.networking.hostName`.

**Why:** Enables filtering logs by host in Grafana. Must match the `instance` labels used by Prometheus exporters for correlation between metrics and logs.

**Implementation:**
```nix
services.promtail.configuration = {
  scrape_configs = [{
    job_name = "journal";
    journal = {
      max_age = "12h";
      labels = {
        job = "systemd-journal";
        host = config.networking.hostName;
      };
    };
    relabel_configs = [
      {
        source_labels = [ "__journal__systemd_unit" ];
        target_label = "unit";
      }
    ];
  }];
};
```

## Anti-Patterns to Avoid

### Anti-Pattern 1: Running Alertmanager Separately

**What:** Deploying Prometheus Alertmanager as a separate service alongside Grafana.

**Why bad:** Adds another service to maintain when Grafana Unified Alerting already provides alert evaluation and notification delivery. Alertmanager is the right choice for large-scale Prometheus deployments, but for a homelab with Grafana already running, it is redundant complexity.

**Instead:** Use Grafana's built-in alerting with provisioned rules and contact points.

### Anti-Pattern 2: Scraping Log Files Directly

**What:** Configuring Promtail to scrape files in `/var/log/` on NixOS.

**Why bad:** NixOS services write to journald, not to log files. The journal is the canonical log source. File-based scraping would miss most service logs and add unnecessary complexity.

**Instead:** Use Promtail's `journal` scrape config to read from systemd journal. This captures all service output (stdout/stderr) automatically.

### Anti-Pattern 3: Loki on ser8

**What:** Running Loki on ser8 alongside all the media and automation services.

**Why bad:** ser8 is already heavily loaded (Jellyfin transcoding, Frigate detection, HA, arr stack). Adding Loki's write path and compaction workload competes for resources. firebat is the monitoring host with Grafana and Prometheus -- Loki belongs there.

**Instead:** Run Loki on firebat. The only cross-host traffic is Promtail pushing logs (low bandwidth for journal logs).

### Anti-Pattern 4: Complex Loki Storage Backend

**What:** Setting up S3-compatible storage (MinIO) for Loki chunks.

**Why bad:** Massive over-engineering for a homelab. Adds another service dependency, configuration surface, and failure mode. Filesystem storage is perfectly adequate for <20GB/day.

**Instead:** Use filesystem storage with TSDB index. Simple, no dependencies, easy to backup (just tar the directory).

## Build Order (Dependency-Aware)

The components have the following dependency chain:

```
Phase 1: Loki (no dependencies, standalone)
    |
    v
Phase 2: Promtail (depends on Loki being reachable)
    |
    v
Phase 3: Grafana Loki Datasource (depends on Loki running)
    |
    v
Phase 4: Blackbox Exporter + Prometheus scrape configs (independent of Loki)
    |
    v
Phase 5: HA Prometheus Integration (independent of Loki, needs SOPS token)
    |
    v
Phase 6: Grafana Alerting (depends on datasources being configured, all metrics flowing)
    |
    v
Phase 7: Dashboards for new data sources (Loki logs dashboard, blackbox dashboard)
```

**Recommended build order within a single milestone:**

1. **Loki on firebat** -- deploy and verify it starts, accepts pushes at :3100
2. **Promtail on firebat** (local first) -- verify logs appear in Loki
3. **Grafana Loki datasource** -- verify Explore works with LogQL
4. **Promtail on ser8** -- deploy, verify multi-host logs
5. **Promtail on pi4** -- deploy, verify ARM works
6. **Blackbox exporter on firebat** -- deploy with HTTP/TCP/ICMP probes
7. **Prometheus blackbox scrape configs** -- verify probe metrics appear
8. **HA Prometheus integration** -- enable in HA config, create SOPS token, add scrape job
9. **Grafana alert rules** -- migrate existing Prometheus alerts + add new ones
10. **Grafana contact points** -- configure webhook to HA (and optionally Discord)
11. **Grafana notification policies** -- route alerts to contact points by severity
12. **New dashboards** -- Loki log explorer, blackbox status, HA entity overview

## Scalability Considerations

| Concern | Current (3 hosts) | 5-6 hosts | 10+ hosts |
|---------|-------------------|-----------|-----------|
| Loki storage | ~1-2GB/day journal logs | ~3-4GB/day | Consider S3 backend |
| Loki memory | ~256MB (monolithic) | ~512MB | Microservices mode |
| Promtail overhead | Negligible (<50MB RAM per host) | Same | Same |
| Blackbox probes | 12 targets, 15s interval | 20 targets | Fine up to 100s of targets |
| Grafana alert eval | <10 rules, trivial | <50 rules | Fine up to 1000s |
| Network (log push) | ~10KB/s per host | ~20KB/s total | Still negligible |
| Dashboard queries | <5 concurrent users | Same | Fine with caching |

## Firewall Ports Summary

### New ports to open

| Host | Port | Service | Direction |
|------|------|---------|-----------|
| firebat | 3100 | Loki (HTTP API) | Inbound from ser8, pi4 (Promtail push) |
| firebat | 9115 | Blackbox Exporter | Localhost only (Prometheus scrapes it) |

### Ports that do NOT need opening

| Port | Why |
|------|-----|
| Promtail 9080 | Only used for local health checks, not externally scraped |
| HA 8123 | Already open on ser8 for Caddy proxy -- Prometheus scrapes same port |

## Impermanence Considerations

### ser8 (has "Erase Your Darlings")

Add to `hosts/ser8/impermanence.nix`:
```
"/var/lib/promtail"  # Promtail positions file (tracks journal cursor)
```

### firebat (investigate)

firebat imports disko and impermanence modules via x86Modules but does NOT have a visible impermanence.nix with ZFS rollback. If firebat does NOT erase root on boot, no action needed. If it does, add:
```
"/var/lib/loki"      # Loki data (index + chunks)
"/var/lib/promtail"  # Promtail positions file
```

### pi4 (no impermanence)

pi4 runs from SD card without impermanence. No action needed -- `/var/lib/promtail` persists naturally.

## Sources

- [Grafana Loki NixOS Wiki](https://wiki.nixos.org/wiki/Grafana_Loki) -- HIGH confidence, official NixOS wiki
- [NixOS Loki module source](https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/services/monitoring/loki.nix) -- HIGH confidence
- [NixOS Promtail options](https://mynixos.com/options/services.promtail) -- HIGH confidence
- [NixOS Blackbox Exporter module](https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/services/monitoring/prometheus/exporters/blackbox.nix) -- HIGH confidence
- [NixOS Grafana Alerting Provisioning options](https://mynixos.com/nixpkgs/options/services.grafana.provision.alerting.rules.settings) -- HIGH confidence
- [Grafana File Provisioning for Alerting](https://grafana.com/docs/grafana/latest/alerting/set-up/provision-alerting-resources/file-provisioning/) -- HIGH confidence, official Grafana docs
- [Home Assistant Prometheus Integration](https://www.home-assistant.io/integrations/prometheus/) -- HIGH confidence, official HA docs
- [Loki Storage Documentation](https://grafana.com/docs/loki/latest/configure/storage/) -- HIGH confidence, official Grafana docs
- [TSDB Migration Guide](https://grafana.com/docs/loki/latest/setup/migrate/migrate-to-tsdb/) -- HIGH confidence
- [Blackbox Exporter GitHub](https://github.com/prometheus/blackbox_exporter) -- HIGH confidence
- [Promtail Deprecation Notice (Loki 3.4)](https://grafana.com/blog/2025/02/13/grafana-loki-3.4-standardized-storage-config-sizing-guidance-and-promtail-merging-into-alloy/) -- HIGH confidence
- [NixOS Alloy module](https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/services/monitoring/alloy.nix) -- HIGH confidence
- [Grafana Alloy package in nixpkgs](https://mynixos.com/nixpkgs/package/grafana-alloy) -- HIGH confidence
- Existing codebase analysis: `modules/gateway/prometheus.nix`, `modules/gateway/grafana.nix`, `modules/servers/monitoring.nix`, `modules/automation/home-assistant.nix`, `hosts/ser8/impermanence.nix`, `hosts/firebat/configuration.nix`, `modules/gateway/Caddyfile` -- HIGH confidence
