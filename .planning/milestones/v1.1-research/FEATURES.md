# Feature Landscape: Homelab Monitoring, Alerting & Log Aggregation

**Domain:** Infrastructure observability for NixOS homelab
**Researched:** 2026-02-10
**Context:** Existing Prometheus + Grafana stack on firebat. 11 dashboards already provisioned. 6 alert rules defined in Prometheus (HostDown, HighDiskUsage, HighMemoryUsage, ZFSPoolUnhealthy, HighCPUTemperature, CameraStorageHigh). No alerting delivery pipeline (no Alertmanager, no Grafana SMTP). No log aggregation. No HTTP service probes. 3 hosts (ser8, firebat, pi4), 12+ services.

---

## Table Stakes

Features users expect from a monitoring stack. Missing = "I still discover problems by stumbling into them."

| Feature | Why Expected | Complexity | Dependencies | Notes |
|---------|--------------|------------|--------------|-------|
| **Alert delivery (email)** | Alert rules exist but fire into the void. Without delivery, alerting is decorative. | Low | Grafana SMTP config or Alertmanager + SMTP relay | Grafana SMTP is simplest: `services.grafana.settings.smtp.*` in NixOS. Use Gmail app password or any SMTP relay. Avoids running a separate Alertmanager service. |
| **Service HTTP probes** | 12+ services run behind Caddy. Need to know if Jellyfin, Sonarr, Radarr, Prowlarr, SABnzbd, Frigate, HA, AdGuard, Grafana, Prometheus are actually responding, not just that the process is running. | Low | Blackbox exporter on firebat, Prometheus scrape config | `services.prometheus.exporters.blackbox` available in NixOS. Probes `http://ser8.local:PORT` for each service. Uses `probe_success` and `probe_http_duration_seconds` metrics. |
| **Disk space alerting (all mounts)** | Existing `HighDiskUsage` rule only fires at <10%. Need per-mount awareness: root (ZFS), `/mnt/media` (MergerFS), `/mnt/cameras`, boot partitions. Need warning at 20%, critical at 10%. | Low | Existing node-exporter | Refine existing rule. Add mount-specific rules for `/mnt/cameras` (already exists) and `/mnt/media`. Use `for: 15m` to avoid transient spikes. |
| **ZFS health alerting** | Existing `ZFSPoolUnhealthy` catches degraded pools. Missing: ZFS scrub errors, ARC miss ratio degradation, snapshot space bloat. | Low | Existing zfs-exporter on ser8 | `zfs_scrub_errors_total > 0`, `zfs_pool_allocated_bytes / zfs_pool_size_bytes > 0.85`. Critical for a server using "Erase Your Darlings" ZFS pattern. |
| **Service crash/restart alerting** | systemd-exporter already tracks restart counts. Need alert when a monitored service restarts unexpectedly or enters failed state. | Low | Existing systemd-exporter | `systemd_unit_state{state="failed"} == 1` or `increase(systemd_unit_restart_total[5m]) > 2`. Already have systemd exporter on all 3 hosts. |
| **Uptime status dashboard** | Single pane showing green/red for every service. First thing to check when "something feels broken." | Low | Blackbox exporter metrics | Pre-built Grafana dashboard (ID 7587 or 21275). Shows `probe_success`, response time, SSL cert expiry. Import and configure targets. |
| **Host down alerting with delivery** | `HostDown` rule already exists. Useless without notification delivery. This is table stakes once email works. | Low | Alert delivery (email) | Existing `up == 0 for 5m` rule is correct. Just needs to flow through to a notification channel. |
| **Memory pressure alerting** | Existing `HighMemoryUsage` at <10% available. ser8 runs 12+ services, so memory pressure is real. Need graduated severity. | Low | Existing node-exporter | Warning at <15%, critical at <5%. Use `node_memory_MemAvailable_bytes` not `MemFree`. Already correct in existing rule. |
| **CPU temperature alerting** | Existing `HighCPUTemperature` at >80C. ser8 has AMD 8845HS in compact chassis. Need graduated: warn 75C, critical 85C. | Low | Existing node-exporter hwmon | Refine thresholds. `node_hwmon_temp_celsius` metric. Pi4 may not expose hwmon -- only alert on hosts that have it. |

## Differentiators

Features that elevate the setup beyond "alerts work" to "observability is actually useful." Not expected, but make the homelab feel professionally operated.

| Feature | Value Proposition | Complexity | Dependencies | Notes |
|---------|-------------------|------------|--------------|-------|
| **Log aggregation (Loki + Alloy)** | Searchable log history across all 3 hosts. Currently logs are per-host in journald with 1GB retention. Cannot search "what happened on ser8 at 3am" from firebat. | Medium | Loki on firebat, Grafana Alloy on all hosts | Loki stores logs, Grafana Alloy replaces deprecated Promtail (EOL Feb 2026). Alloy reads systemd journal via `loki.source.journal`. Both available in nixpkgs: `services.loki` and `services.alloy`. |
| **Log-based error alerting** | Alert on patterns like repeated service failures, OOM kills, ZFS errors in dmesg, Frigate camera disconnect messages. Catches problems that metrics miss. | Medium | Loki + Grafana alerting | Loki ruler evaluates LogQL expressions: `count_over_time({unit="frigate.service"} \|= "error" [5m]) > 10`. Requires Loki to be running and Grafana Loki datasource configured. |
| **SMART disk monitoring** | Predict disk failures before they happen. ser8 has spinning disks in MergerFS + NVMe for ZFS. | Medium | smartctl_exporter on ser8 | `services.prometheus.exporters.smartctl` in NixOS. Exposes `smartctl_device_temperature`, `smartctl_device_smart_status`, reallocated sectors. Dashboard available (Grafana ID 20204). Some NixOS quirks with device permissions and NVMe autodiscovery. |
| **HA entity tracking dashboard** | Grafana dashboard showing HA entity states over time (camera online/offline, MQTT connected, automation success/failure). | Medium | HA Prometheus integration, long-lived access token | HA has built-in `/api/prometheus` endpoint. Add `prometheus:` to HA config, create long-lived token, add scrape job. Exposes all entity states as metrics. Requires SOPS for the HA token. |
| **HA system health dashboard** | HA's own health: database size, event bus throughput, integration load times, memory usage. | Medium | HA Prometheus integration | Same endpoint as entity tracking. Metrics like `homeassistant_entity_count`, `process_resident_memory_bytes`. Combine with process-exporter data already collected for `home-assistant`. |
| **HA automations for infrastructure alerts** | Camera offline detection, MQTT broker down, Frigate service crashed -- push notifications via HA Companion app (already proven with Frigate alerts). | Medium | HA automations in Nix config | Use HA `state` trigger on Frigate integration entities (cameras go `unavailable`). Or use `mqtt` trigger on `frigate/available` topic (publishes `online`/`offline`). Complements Prometheus alerting with mobile push. |
| **Grafana alerting provisioned as code** | Alert rules, contact points, and notification policies defined in YAML files under Grafana's provisioning directory. Declarative, version-controlled. | Medium | Grafana provisioning directory | Grafana supports file-based provisioning of all alerting resources. NixOS can deploy YAML files to `/var/lib/grafana/provisioning/alerting/`. Avoids click-ops in Grafana UI. |
| **Network connectivity monitoring** | ICMP probes to all hosts + DNS resolution checks against pi4 AdGuard. Catches network-level issues before service probes fail. | Low | Blackbox exporter ICMP + DNS modules | Blackbox exporter supports `icmp` and `dns` probers. ICMP needs `CAP_NET_RAW`. DNS prober can verify pi4 resolves expected records. |
| **Notification deduplication and grouping** | Group related alerts (e.g., "ser8 disk + memory + CPU" into one notification rather than 3). Suppress repeat notifications during ongoing incidents. | Low | Alertmanager or Grafana notification policies | Grafana unified alerting has grouping and repeat intervals. Or Alertmanager has `group_by`, `group_wait`, `repeat_interval`. Either works. |
| **Certificate expiry monitoring** | Monitor TLS cert expiry for Tailscale-issued certs and Caddy local CA certs. | Low | Blackbox exporter HTTPS probes | `probe_ssl_earliest_cert_expiry` metric from blackbox HTTPS probes. Alert when <14 days. Tailscale certs auto-renew but monitoring catches failures. |

## Anti-Features

Features to explicitly NOT build. These add complexity disproportionate to value, are enterprise overkill for a 3-host homelab, or introduce maintenance burden.

| Anti-Feature | Why Avoid | What to Do Instead |
|--------------|-----------|-------------------|
| **Standalone Alertmanager service** | Adds a separate service to configure, maintain, and debug. Grafana unified alerting handles alert routing, grouping, and notification natively. For a 3-host homelab, the additional operational surface is not justified. | Use Grafana unified alerting with file-provisioned rules and SMTP contact point. Grafana is already running. |
| **Promtail for log collection** | Deprecated Feb 2025, EOL Feb 2026. Will stop receiving security patches. | Use Grafana Alloy (`services.alloy`), its official replacement. Alloy also handles metrics and traces if needed later. |
| **Full ELK/OpenSearch stack** | Elasticsearch/OpenSearch + Kibana/OpenSearch Dashboards is massively over-engineered for 3 hosts. High memory footprint (2-4GB minimum), complex configuration, JVM tuning. | Use Loki. Designed for the Grafana ecosystem, log-first, index-free design uses far less resources. Already integrates with Grafana. |
| **Uptime Kuma / Gatus / separate status page** | Adds another service that duplicates what Blackbox exporter + Grafana dashboard already provides. More services = more things to monitor. | Blackbox exporter + a Grafana dashboard provides the same uptime/status view without additional infrastructure. |
| **PagerDuty / OpsGenie / incident management** | Enterprise incident response for a personal homelab is absurd. | Email notifications + HA mobile push. Check phone, fix it, done. |
| **Distributed tracing (Jaeger/Tempo)** | None of the services are instrumented for tracing. Homelab services are off-the-shelf (Jellyfin, Sonarr, etc.), not custom microservices. | Metrics + logs cover all debugging needs for pre-built services. |
| **Multi-tenant Loki / Mimir** | Multi-tenancy adds auth complexity for zero benefit when there is one operator. | Single-tenant Loki with `auth_enabled: false`. |
| **Grafana OnCall** | Enterprise on-call rotation for one person. | Email goes to one person. Done. |
| **Custom Prometheus exporters** | Writing Go/Python exporters for edge cases when existing exporters cover 99% of needs. | Use existing exporters: node, blackbox, systemd, process, zfs, smartctl, frigate, jellyfin, exportarr, adguard. |
| **Metrics-based anomaly detection / ML** | Grafana ML features require Grafana Cloud or significant setup. Low signal-to-noise for a homelab with predictable workloads. | Static thresholds with well-tuned `for` durations. Homelab workloads are predictable enough. |
| **Log shipping to external service (Datadog, Splunk, etc.)** | Monthly cost, data leaving the network, external dependency. | Self-hosted Loki. All data stays on the homelab network. |
| **Complex HA blueprints for monitoring** | Blueprints are UI-imported, opaque, harder to version-control in NixOS. Previous milestone established this pattern. | Write explicit automations in `services.home-assistant.config."automation manual"`. Use blueprints as reference only. |

## Feature Dependencies

```
FOUNDATION (no dependencies, enable first)
  |
  |-- Grafana SMTP configuration
  |     |-> Email contact point works
  |     |-> All Grafana alert rules can deliver notifications
  |
  |-- Blackbox exporter on firebat
  |     |-> HTTP probes for all services
  |     |-> ICMP probes for all hosts
  |     |-> DNS probes for pi4 AdGuard
  |     |-> probe_success metric available
  |     |-> Uptime dashboard can be built
  |
  |-- Refined Prometheus alert rules
  |     |-> Graduated severity (warning/critical)
  |     |-> Per-mount disk alerts
  |     |-> ZFS scrub error alerts
  |     |-> Service restart alerts
  |     |-> Blackbox probe failure alerts
  |
  +-- Grafana unified alerting (rules + contact points + policies)
        |-> Prometheus alert rules route to email
        |-> Alert grouping reduces noise
        |-> Notification policies control routing

LOG AGGREGATION (depends on foundation being stable)
  |
  |-- Loki on firebat
  |     |-> Log storage backend running
  |     |-> Grafana Loki datasource configured
  |
  |-- Grafana Alloy on ser8, firebat, pi4
  |     |-> systemd journal logs shipped to Loki
  |     |-> Labels: host, unit, priority
  |
  +-- Log-based alerting
        |-> LogQL alert rules in Loki or Grafana
        |-> Error pattern detection
        |-> Service crash detection from logs

HOME ASSISTANT MONITORING (depends on foundation + optional Loki)
  |
  |-- HA Prometheus integration
  |     |-> prometheus: in HA configuration.yaml
  |     |-> Long-lived access token in SOPS
  |     |-> Prometheus scrape job for HA metrics
  |     |-> HA entity metrics in Grafana
  |
  |-- HA entity tracking dashboard
  |     |-> Camera online/offline history
  |     |-> Automation trigger counts
  |     |-> MQTT broker status
  |
  |-- HA infrastructure automations
  |     |-> Camera offline -> mobile push
  |     |-> MQTT down -> mobile push
  |     |-> Frigate service down -> mobile push
  |     |-> These complement (not replace) Prometheus alerting

HARDWARE DEEP DIVE (independent, add when ready)
  |
  +-- SMART disk monitoring
        |-> smartctl_exporter on ser8
        |-> Dashboard (Grafana ID 20204)
        |-> Alert on SMART status degraded
        |-> Alert on temperature out of range
        |-> Alert on reallocated sectors
```

## Alert Rules Catalog

Concrete alert rules organized by category. These are the rules to implement, derived from the [awesome-prometheus-alerts](https://samber.github.io/awesome-prometheus-alerts/rules.html) collection and homelab best practices.

### Host Infrastructure

| Alert Name | Expression | For | Severity | Notes |
|------------|-----------|-----|----------|-------|
| HostDown | `up == 0` | 5m | critical | Already exists. Needs delivery. |
| HostHighCpuLoad | `1 - avg without(cpu)(rate(node_cpu_seconds_total{mode="idle"}[5m])) > 0.9` | 10m | warning | 90% sustained for 10min. Current setup has no CPU alert. |
| HostHighMemoryUsage | `node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes < 0.15` | 5m | warning | Refine existing <10% to graduated. |
| HostCriticalMemoryUsage | `node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes < 0.05` | 5m | critical | Escalation. |
| HostHighTemperature | `node_hwmon_temp_celsius > 75` | 5m | warning | Refine existing >80C. |
| HostCriticalTemperature | `node_hwmon_temp_celsius > 85` | 2m | critical | Shorter `for` at critical temp. |
| HostSwapUsage | `node_memory_SwapFree_bytes / node_memory_SwapTotal_bytes < 0.5` | 10m | warning | Swap over 50% = memory pressure. |
| HostOomKillDetected | `increase(node_vmstat_oom_kill[5m]) > 0` | 0m | critical | OOM kills need immediate attention. |

### Disk & Storage

| Alert Name | Expression | For | Severity | Notes |
|------------|-----------|-----|----------|-------|
| DiskSpaceWarning | `node_filesystem_avail_bytes{fstype!~"tmpfs\|fuse.*"} / node_filesystem_size_bytes < 0.20` | 15m | warning | 80% full, all mounts. |
| DiskSpaceCritical | `node_filesystem_avail_bytes{fstype!~"tmpfs\|fuse.*"} / node_filesystem_size_bytes < 0.10` | 5m | critical | 90% full. |
| CameraStorageHigh | `node_filesystem_avail_bytes{mountpoint="/mnt/cameras"} / node_filesystem_size_bytes{mountpoint="/mnt/cameras"} < 0.20` | 5m | warning | Already exists at <20%. Keep. |
| MediaStorageHigh | `node_filesystem_avail_bytes{mountpoint="/mnt/media"} / node_filesystem_size_bytes{mountpoint="/mnt/media"} < 0.15` | 15m | warning | MergerFS media pool. |
| DiskReadLatencyHigh | `rate(node_disk_read_time_seconds_total[5m]) / rate(node_disk_reads_completed_total[5m]) > 0.1` | 10m | warning | >100ms read latency = failing disk. |

### ZFS (ser8)

| Alert Name | Expression | For | Severity | Notes |
|------------|-----------|-----|----------|-------|
| ZFSPoolUnhealthy | `node_zfs_zpool_health_state{state!="online"} > 0` | 5m | critical | Already exists. Keep. |
| ZFSScrubErrors | `node_zfs_zpool_scrub_errors > 0` | 0m | critical | Any scrub error = data integrity issue. |
| ZFSPoolCapacityWarning | `zfs_pool_allocated_bytes / zfs_pool_size_bytes > 0.80` | 30m | warning | ZFS degrades past 80% capacity. |
| ZFSPoolCapacityCritical | `zfs_pool_allocated_bytes / zfs_pool_size_bytes > 0.90` | 10m | critical | Severe performance degradation. |
| ZFSARCHitRatioLow | `node_zfs_arc_hits / (node_zfs_arc_hits + node_zfs_arc_misses) < 0.80` | 30m | warning | ARC hit ratio below 80% = insufficient ARC size. |

### Service Health (Blackbox Probes)

| Alert Name | Expression | For | Severity | Notes |
|------------|-----------|-----|----------|-------|
| ServiceDown | `probe_success == 0` | 3m | critical | Any probed service unreachable. |
| ServiceSlowResponse | `probe_http_duration_seconds > 5` | 5m | warning | >5s response time. |
| ServiceSSLCertExpiringSoon | `probe_ssl_earliest_cert_expiry - time() < 86400 * 14` | 1h | warning | <14 days to cert expiry. |
| DNSResolutionFailed | `probe_success{job="blackbox-dns"} == 0` | 2m | critical | pi4 AdGuard not resolving. |

### Service Process Health

| Alert Name | Expression | For | Severity | Notes |
|------------|-----------|-----|----------|-------|
| ServiceFailed | `systemd_unit_state{state="failed"} == 1` | 1m | critical | Any monitored unit in failed state. |
| ServiceCrashLooping | `increase(systemd_unit_restart_total[10m]) > 3` | 0m | critical | >3 restarts in 10min = crash loop. |
| ServiceHighMemory | `namedprocess_namegroup_memory_bytes{memtype="resident"} > 2e9` | 15m | warning | Any service using >2GB RSS. Tune per-service. |
| HighProcessCPU | `rate(namedprocess_namegroup_cpu_seconds_total[5m]) > 2` | 10m | warning | >200% CPU (2 cores) sustained. |

### Prometheus Self-Monitoring

| Alert Name | Expression | For | Severity | Notes |
|------------|-----------|-----|----------|-------|
| PrometheusTargetDown | `up == 0` | 5m | critical | Same as HostDown but covers all scrape targets. |
| PrometheusTSDBFull | `prometheus_tsdb_storage_blocks_bytes / (10 * 1024^3) > 0.90` | 1h | warning | TSDB approaching 10GB retention limit. |
| PrometheusRuleFailures | `increase(prometheus_rule_evaluation_failures_total[5m]) > 0` | 5m | warning | Alert rules failing to evaluate. |

### Services to Probe (Blackbox Targets)

| Service | Probe URL | Host | Port | Protocol |
|---------|-----------|------|------|----------|
| Jellyfin | `http://ser8.local:8096` | ser8 | 8096 | HTTP |
| Sonarr | `http://ser8.local:8989` | ser8 | 8989 | HTTP |
| Radarr | `http://ser8.local:7878` | ser8 | 7878 | HTTP |
| Prowlarr | `http://ser8.local:9696` | ser8 | 9696 | HTTP |
| SABnzbd | `http://ser8.local:8085` | ser8 | 8085 | HTTP |
| qBittorrent | `http://ser8.local:8080` | ser8 | 8080 | HTTP |
| Frigate | `http://ser8.local:80` | ser8 | 80 | HTTP |
| Home Assistant | `http://ser8.local:8123` | ser8 | 8123 | HTTP |
| AdGuard Home | `http://pi4.local:3000` | pi4 | 3000 | HTTP |
| Grafana | `http://localhost:3000` | firebat | 3000 | HTTP |
| Prometheus | `http://localhost:9090` | firebat | 9090 | HTTP |
| Caddy | `http://localhost:2019/config/` | firebat | 2019 | HTTP |

## MVP Recommendation

Build in this order, each layer building on the previous. Each phase delivers standalone value.

### Phase 1: Alert Delivery + Refined Rules (must ship first)

Without alert delivery, nothing else matters. This phase makes existing alert rules actionable.

1. **Grafana SMTP configuration** -- Configure `services.grafana.settings.smtp` with Gmail app password (stored in SOPS). Create email contact point.
2. **Refine Prometheus alert rules** -- Graduated severity levels (warning/critical), per-mount disk alerts, service restart detection, OOM kill detection.
3. **Grafana unified alerting setup** -- Provision alert rules, contact points, and notification policies via YAML files in Grafana provisioning directory.
4. **Test delivery** -- Use Grafana's "Test" button on contact point. Verify email arrives.

### Phase 2: Service Health Probes + Uptime Dashboard

Know immediately when any service goes down, not when you try to use it.

5. **Blackbox exporter** -- Deploy on firebat with HTTP, ICMP, and DNS modules. Configure Prometheus scrape jobs for all 12 services.
6. **Service down alert rules** -- `probe_success == 0 for 3m` with email delivery.
7. **Uptime dashboard** -- Import Grafana dashboard (ID 7587 or 21275). Shows green/red status for every service, response times, cert expiry.

### Phase 3: Log Aggregation

Searchable log history. "What happened on ser8 at 3am?"

8. **Loki on firebat** -- `services.loki` with filesystem storage, 30-day retention.
9. **Grafana Alloy on all hosts** -- `services.alloy` reading systemd journal, shipping to Loki.
10. **Grafana Loki datasource** -- Provisioned alongside Prometheus datasource.
11. **Log-based alerts** -- LogQL rules for OOM patterns, service crash patterns, Frigate camera disconnect patterns.

### Phase 4: Home Assistant Monitoring

Complement Prometheus with HA-native monitoring and mobile push for camera/automation issues.

12. **HA Prometheus integration** -- Add `prometheus:` to HA config, long-lived access token, Prometheus scrape job.
13. **HA dashboards in Grafana** -- Entity tracking, system health, automation success rates.
14. **HA infrastructure automations** -- Camera offline detection, MQTT down, Frigate down. Mobile push via existing Companion app.

### Phase 5: Hardware Deep Dive (defer if time-constrained)

15. **SMART disk monitoring** -- smartctl_exporter on ser8, dashboard, alerting.

### Defer Indefinitely

- Standalone Alertmanager, ELK/OpenSearch, Uptime Kuma, PagerDuty, distributed tracing, anomaly detection ML, external log shipping, Node-RED.

## Sources

- [Grafana Alerting Documentation](https://grafana.com/docs/grafana/latest/alerting/) -- HIGH confidence, official docs
- [Grafana Alerting File Provisioning](https://grafana.com/docs/grafana/latest/alerting/set-up/provision-alerting-resources/file-provisioning/) -- HIGH confidence, official docs
- [Grafana Email Alert Configuration](https://grafana.com/docs/grafana/latest/alerting/configure-notifications/manage-contact-points/integrations/configure-email/) -- HIGH confidence, official docs
- [Grafana SMTP NixOS options (services.grafana.settings.smtp)](https://mynixos.com/options/services.grafana.settings.smtp) -- HIGH confidence, NixOS options reference
- [Prometheus Blackbox Exporter](https://github.com/prometheus/blackbox_exporter) -- HIGH confidence, official repo
- [NixOS Blackbox Exporter Module](https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/services/monitoring/prometheus/exporters/blackbox.nix) -- HIGH confidence, NixOS source
- [Awesome Prometheus Alerts](https://samber.github.io/awesome-prometheus-alerts/rules.html) -- HIGH confidence, community-standard collection
- [Grafana Loki Alerting Rules](https://grafana.com/docs/loki/latest/alert/) -- HIGH confidence, official docs
- [Grafana Alloy journal source](https://grafana.com/docs/alloy/latest/reference/components/loki/loki.source.journal/) -- HIGH confidence, official docs
- [Loki 3.4 Release: Promtail merging into Alloy](https://grafana.com/blog/2025/02/13/grafana-loki-3.4-standardized-storage-config-sizing-guidance-and-promtail-merging-into-alloy/) -- HIGH confidence, official blog
- [Promtail Deprecation Guide](https://techanek.com/promtail-deprecation-whats-next-for-log-collection-in-grafana/) -- MEDIUM confidence, technical blog
- [Home Assistant Prometheus Integration](https://www.home-assistant.io/integrations/prometheus/) -- HIGH confidence, official docs
- [Frigate MQTT Availability](https://docs.frigate.video/integrations/mqtt/) -- HIGH confidence, official docs
- [NixOS Alertmanager Module](https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/services/monitoring/prometheus/alertmanager.nix) -- HIGH confidence, NixOS source
- [smartctl_exporter](https://github.com/prometheus-community/smartctl_exporter) -- HIGH confidence, prometheus-community repo
- [NixOS Wiki: Grafana Loki](https://wiki.nixos.org/wiki/Grafana_Loki) -- HIGH confidence, NixOS wiki
- [Prometheus Alertmanager vs Grafana Alerts (2025)](https://medium.com/@mahernaija/prometheus-alertmanager-vs-grafana-alerts-which-one-should-you-use-in-2025-6df049a9b968) -- MEDIUM confidence, analysis article
- [Blackbox Exporter Grafana Dashboard 7587](https://grafana.com/grafana/dashboards/7587-prometheus-blackbox-exporter/) -- HIGH confidence, Grafana Labs
- [HA Unavailable Entity Detection Blueprint](https://community.home-assistant.io/t/unavailable-entity-detection-notification/337272) -- MEDIUM confidence, community pattern (reference only, not using blueprints)
