# Phase 5: Hardware Alerts & Status Dashboard - Research

**Researched:** 2026-02-12
**Domain:** Grafana Unified Alerting (graduated hardware alerts), Prometheus PromQL, Grafana dashboard provisioning (status-history/state-timeline panels), node-exporter metrics, ZFS exporter metrics
**Confidence:** HIGH

## Summary

Phase 5 builds on the complete Phase 4 foundation (email delivery, blackbox probes, 9 provisioned Grafana alert rules) to add two capabilities: (1) graduated hardware alerts with proper severity levels for disk, ZFS, CPU, and memory, and (2) an uptime/status dashboard showing green/red availability for every probed service.

The existing Phase 4 alert rules already partially cover hardware monitoring but need refinement. The disk alert (`high_disk_usage`) fires only at 90% usage (single threshold) -- Phase 5 requires graduated warnings at 80% and critical at 90%. The memory alert (`high_memory_usage`) and temperature alert (`high_cpu_temp`) already satisfy HW-04 and HW-05 respectively. The ZFS pool health alert exists but there is no ZFS scrub error alert. CPU sustained usage alert (HW-03) is entirely missing. This phase modifies existing rules and adds new ones.

For the uptime dashboard (DASH-01), Grafana's `state-timeline` or `status-history` panel types can visualize `probe_success` metrics as green/red status bars over time, with `avg_over_time(probe_success[24h]) * 100` providing availability percentage. The dashboard should be built as a custom JSON file following the existing pattern of pre-downloaded dashboards in the `dashboards/` directory, then symlinked via `systemd.tmpfiles.rules`.

**Primary recommendation:** Modify the existing `homelab_infrastructure` alert rule group in `grafana.nix` to add graduated disk alerts and CPU usage alert, add a ZFS scrub errors alert, and create a new `dashboards/uptime.json` dashboard using state-timeline panels for service availability visualization.

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Grafana Unified Alerting | Built into Grafana 12.x | Graduated alert rules with severity labels | Already configured in Phase 4. Add/modify rules in existing `alerting.rules.settings` |
| node-exporter | Already running | `node_filesystem_*`, `node_cpu_seconds_total`, `node_memory_*`, `node_hwmon_temp_celsius` | Already deployed on all hosts. Provides all hardware metrics needed |
| zfs-exporter (pdf/zfs_exporter) | Already running on ser8:9134 | `zfs_pool_health`, `zfs_pool_free_bytes`, `zfs_pool_size_bytes` | Already deployed. Scraped by Prometheus. Provides ZFS pool-level metrics |
| Blackbox exporter | Already running on firebat | `probe_success`, `probe_duration_seconds` | Already configured in Phase 4. Provides service availability data for dashboard |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| Grafana state-timeline panel | Built into Grafana 12.x | Green/red service status visualization over time | DASH-01 uptime dashboard |
| Grafana stat panel | Built into Grafana 12.x | Current availability percentage display | DASH-01 uptime dashboard summary row |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| state-timeline panel | status-history panel | State-timeline merges consecutive same-state values into solid bars (cleaner). Status-history shows discrete time slices (more granular). State-timeline is better for uptime visualization. |
| Custom uptime dashboard JSON | Grafana.com dashboard ID 7587 or 21275 | Pre-built dashboards may not match our exact probe targets and naming. Custom JSON gives full control over layout and is consistent with existing dashboard pattern. |
| Two separate disk rules (warning + critical) | Single rule with dynamic severity label | Dynamic labels are more elegant but create complexity with Grafana notification routing and label changes between evaluations causing duplicate alerts. Two simple rules is clearer and more reliable. |

**Installation:**
No new packages or flake inputs needed. All components already deployed from Phase 4.

## Architecture Patterns

### Module Changes

```
modules/gateway/
  |-- grafana.nix       # MODIFY: add/modify alert rules (disk graduated, CPU, ZFS scrub)
  |-- prometheus.nix    # MODIFY: update ruleFiles to match (defense-in-depth)
  |-- blackbox.nix      # NO CHANGES
  |-- caddy.nix         # NO CHANGES
  |-- default.nix       # NO CHANGES
  |-- tailscale.nix     # NO CHANGES

dashboards/
  |-- uptime.json       # NEW: service uptime/status dashboard
```

### Pattern 1: Graduated Disk Alerts (Two Separate Rules)

**What:** Create two separate alert rules for disk space -- warning at 80% usage and critical at 90% usage -- rather than one rule with dynamic labels.
**When to use:** When graduated severity is needed for the same metric with different thresholds.
**Why two rules:** Grafana's dynamic label approach creates complexity -- if a disk goes from 80% to 91%, the severity label changes from "warning" to "critical", which creates a NEW alert instance (not an escalation). Two separate rules with distinct UIDs are simpler and more predictable.

**Example:**
```nix
# Warning: disk usage > 80%
{
  uid = "disk_usage_warning";
  title = "Disk Usage Warning (>80%)";
  condition = "C";
  data = [
    {
      refId = "A";
      relativeTimeRange = { from = 300; to = 0; };
      datasourceUid = "prometheus";
      model = {
        expr = ''(node_filesystem_avail_bytes{fstype!~"tmpfs|overlay",mountpoint!~"/boot.*"} / node_filesystem_size_bytes) * 100'';
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
          evaluator = { params = [ 20 ]; type = "lt"; };
        }];
        refId = "C";
      };
    }
  ];
  "for" = "5m";
  labels = { severity = "warning"; };
  annotations = {
    summary = "Disk usage above 80% on {{ $labels.instance }} mount {{ $labels.mountpoint }}";
  };
}

# Critical: disk usage > 90%
{
  uid = "disk_usage_critical";
  title = "Disk Usage Critical (>90%)";
  # Same structure but threshold at 10 (< 10% free)
  # ...
  labels = { severity = "critical"; };
}
```

### Pattern 2: CPU Sustained High Usage Alert

**What:** Alert when average CPU usage exceeds 90% sustained for 5 minutes.
**When to use:** HW-03 requirement.

**PromQL for CPU usage percentage:**
```
100 - (avg by(instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 90
```

**Key insight:** Use `rate()` not `irate()` for alert rules. `rate()` calculates per-second average over the range, giving a smoother signal suitable for alerting. `irate()` uses only the last two samples and is too noisy for alerts.

**Grafana alert rule pattern:**
```nix
{
  uid = "high_cpu_usage";
  title = "High CPU Usage (>90% sustained)";
  condition = "C";
  data = [
    {
      refId = "A";
      relativeTimeRange = { from = 600; to = 0; };
      datasourceUid = "prometheus";
      model = {
        expr = "100 - (avg by(instance) (rate(node_cpu_seconds_total{mode=\"idle\"}[5m])) * 100)";
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
          evaluator = { params = [ 90 ]; type = "gt"; };
        }];
        refId = "C";
      };
    }
  ];
  "for" = "5m";
  labels = { severity = "warning"; };
  annotations = {
    summary = "CPU usage is above 90% on {{ $labels.instance }}";
  };
}
```

### Pattern 3: ZFS Scrub Errors Alert

**What:** Alert when ZFS scrub reports errors.
**Complexity:** The standard zfs-exporter (pdf/zfs_exporter) on port 9134 does NOT expose scrub error metrics. The node_exporter ZFS collector also does not expose per-scrub error counts.

**Available approaches:**

1. **Use `zfs_pool_health` from zfs-exporter** (already covered by existing `zfs_pool_unhealthy` rule). A pool with scrub errors that cause data integrity issues will transition to degraded state.

2. **ZFS Event Daemon (zed)** can send email notifications for scrub completions with errors. This is a NixOS-level configuration, not Prometheus-based.

3. **node_exporter textfile collector** could be used with a cron job that runs `zpool status -p` and writes scrub error counts to a textfile. This is the most reliable approach for scrub-specific metrics.

**Recommendation:** Use approach 1 (existing health metric) plus approach 2 (zed email for scrub events) for comprehensive coverage. The health metric catches severe issues; zed catches scrub-specific errors including corrected ones. Do NOT invest in approach 3 (textfile collector) unless the simpler approaches prove insufficient.

### Pattern 4: Uptime Dashboard with State-Timeline Panels

**What:** Grafana dashboard showing green/red service status and availability percentage.
**Panel layout:**

```
Row 1: Stat panels showing current availability % per service
  - PromQL: avg_over_time(probe_success{job="blackbox-http",instance="..."}[24h]) * 100
  - Green > 99%, Yellow > 95%, Red < 95%

Row 2: State-timeline panel showing all HTTP service status over time
  - PromQL: probe_success{job="blackbox-http"}
  - Value mappings: 0 = "Down" (red), 1 = "Up" (green)
  - Each service as a separate row

Row 3: State-timeline panel showing host ICMP status over time
  - PromQL: probe_success{job="blackbox-icmp"}
  - Same value mappings

Row 4: Stat panels showing TLS certificate days remaining
  - PromQL: (probe_ssl_earliest_cert_expiry{job="blackbox-tls"} - time()) / 86400
  - Green > 14 days, Yellow > 7 days, Red < 7 days
```

**Value mappings configuration for state-timeline:**
```json
{
  "type": "value",
  "options": {
    "0": { "text": "DOWN", "color": "red" },
    "1": { "text": "UP", "color": "green" }
  }
}
```

### Pattern 5: Dashboard as Pre-Built JSON File

**What:** Follow existing pattern of storing dashboard JSON in `dashboards/` directory.
**When to use:** All new dashboards in this codebase.

The existing codebase stores dashboard JSON files directly in the repository and symlinks them into Grafana's dashboard directory:

```nix
# In grafana.nix
dashboards = {
  # ... existing dashboards ...
  uptime = ../../dashboards/uptime.json;
};

# In systemd.tmpfiles.rules
"L+ /var/lib/grafana/dashboards/uptime.json - - - - ${dashboards.uptime}"
```

### Anti-Patterns to Avoid

- **Single rule with dynamic severity for disk alerts:** Creates alert instance churn when disk usage crosses thresholds. Use two separate rules.
- **Using `irate()` instead of `rate()` for alert expressions:** `irate()` is too volatile for alerting. It calculates rate from only the last two samples, which can oscillate rapidly and cause flapping alerts.
- **Alerting on ZFS scrub errors without a metrics source:** The standard exporters (node_exporter, pdf/zfs_exporter) do not expose scrub error counts. Don't write an alert rule for a metric that doesn't exist.
- **Including tmpfs/overlay in disk alerts:** Will generate noise from ephemeral filesystems. Always filter with `fstype!~"tmpfs|overlay"`.
- **Forgetting to filter /boot from disk alerts:** Boot partitions are small and often >80% full. Filter with `mountpoint!~"/boot.*"`.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| ZFS scrub error notification | Custom Prometheus metric via textfile collector | ZFS Event Daemon (zed) email | zed is built into ZFS, fires on scrub completion, reports errors natively |
| Uptime percentage calculation | Custom recording rules | `avg_over_time(probe_success[period])` | Built-in Prometheus function, no recording rules needed |
| Service status visualization | Custom HTML/JS status page | Grafana state-timeline panel | Native Grafana panel with value mappings, thresholds, and time navigation |
| Dashboard provisioning | Grafana API calls | File provisioning via systemd.tmpfiles | Matches existing pattern, version-controlled, reproducible |

**Key insight:** The PromQL function `avg_over_time()` is the standard way to calculate availability percentage from binary probe_success metrics. No recording rules or pre-aggregation needed.

## Common Pitfalls

### Pitfall 1: Filesystem Alert Noise from Pseudo-Filesystems

**What goes wrong:** Disk alerts fire for tmpfs, overlay, squashfs, and other pseudo-filesystems that are either always near-empty or always near-full.
**Why it happens:** `node_filesystem_avail_bytes` reports ALL filesystems including tmpfs (/tmp, /run), overlay (Nix store layers), and squashfs.
**How to avoid:** Filter PromQL with `{fstype!~"tmpfs|overlay|squashfs|devtmpfs|rootfs"}` and `{mountpoint!~"/boot.*|/run.*|/sys.*|/proc.*|/dev.*"}`.
**Warning signs:** Multiple disk alerts from `/run`, `/tmp`, or `/boot` immediately after deployment.

### Pitfall 2: ser8 Impermanence Root Filesystem Alerts

**What goes wrong:** ser8's root filesystem (`/`) uses ZFS with "Erase Your Darlings" -- it rolls back to empty on each boot. Disk alerts may fire on root after boot if the dataset is small.
**Why it happens:** `rpool/local/root` is the rollback-target dataset. After boot it starts near-empty and grows. The root dataset is on ZFS (not a separate partition) so it shares pool space.
**How to avoid:** The root ZFS dataset shares pool space, so in practice this is unlikely to trigger. But if it does, filter with `mountpoint!="/"` for ser8-specific rules, or accept the alert as useful since root filling up IS a problem.
**Warning signs:** Disk alerts for `/` on ser8 immediately after reboot.

### Pitfall 3: ZFS Scrub Error Metrics Don't Exist in Standard Exporters

**What goes wrong:** You write an alert rule for `zfs_scrub_errors` or similar metric, deploy, and the rule evaluates to NoData forever.
**Why it happens:** Neither node_exporter's ZFS collector nor pdf/zfs_exporter expose scrub error counts as metrics. node_exporter provides `node_zfs_zpool_state`, and zfs_exporter provides `zfs_pool_health`, but neither tracks scrub-specific errors.
**How to avoid:** Use pool health state for degradation alerts (already exists). For scrub error notifications, use ZFS Event Daemon (zed) which is purpose-built for this.
**Warning signs:** Alert rule shows "NoData" state in Grafana.

### Pitfall 4: Existing Alert Rule UIDs Must Not Collide

**What goes wrong:** Adding new alert rules with UIDs that collide with existing Phase 4 rules causes provisioning failures or overwrites.
**Why it happens:** Grafana requires globally unique UIDs for alert rules within an org.
**How to avoid:** Use descriptive, unique UIDs: `disk_usage_warning`, `disk_usage_critical`, `high_cpu_usage`. The existing `high_disk_usage` rule needs to be REPLACED (removed and replaced with the two graduated rules), not duplicated.
**Warning signs:** Grafana fails to start, or alert rules are missing after deployment.

### Pitfall 5: Replacing Existing Alert Rules Requires UID Management

**What goes wrong:** Changing the existing `high_disk_usage` rule to two new rules while keeping the old UID causes confusion.
**Why it happens:** File-provisioned rules are managed by UID. Removing a UID from the provisioning file should delete the rule from Grafana on next restart.
**How to avoid:** Remove the old `high_disk_usage` rule entirely and add two new rules (`disk_usage_warning` and `disk_usage_critical`). Grafana will clean up the old rule on restart since its UID is no longer in the provisioning.
**Warning signs:** Three disk alerts firing (old + two new) instead of two.

### Pitfall 6: State-Timeline Panel Requires Correct Legend Format

**What goes wrong:** The state-timeline shows raw instance URLs like `http://192.168.68.65:8096` instead of friendly service names.
**Why it happens:** The `instance` label from blackbox probe targets contains the full URL.
**How to avoid:** Use Grafana panel overrides or PromQL `label_replace()` to create friendly display names. Alternatively, add Prometheus `relabel_configs` with `__meta_` labels during scraping to add a `service_name` label. The simplest approach is to use Grafana field display name overrides in the dashboard JSON.
**Warning signs:** Unreadable instance labels in the dashboard.

## Code Examples

### Graduated Disk Space Alerts (Complete Nix)

```nix
# Replace existing high_disk_usage rule with these two rules
# Warning: less than 20% free (80% used)
{
  uid = "disk_usage_warning";
  title = "Disk Usage Warning (>80%)";
  condition = "C";
  data = [
    {
      refId = "A";
      relativeTimeRange = { from = 300; to = 0; };
      datasourceUid = "prometheus";
      model = {
        expr = ''(node_filesystem_avail_bytes{fstype!~"tmpfs|overlay|squashfs",mountpoint!~"/boot.*"} / node_filesystem_size_bytes) * 100'';
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
          evaluator = { params = [ 20 ]; type = "lt"; };
        }];
        refId = "C";
      };
    }
  ];
  "for" = "5m";
  noDataState = "NoData";
  execErrState = "Alerting";
  labels = { severity = "warning"; };
  annotations = {
    summary = "Disk usage above 80% on {{ $labels.instance }} mount {{ $labels.mountpoint }}";
  };
  isPaused = false;
}

# Critical: less than 10% free (90% used)
{
  uid = "disk_usage_critical";
  title = "Disk Usage Critical (>90%)";
  condition = "C";
  data = [
    {
      refId = "A";
      relativeTimeRange = { from = 300; to = 0; };
      datasourceUid = "prometheus";
      model = {
        expr = ''(node_filesystem_avail_bytes{fstype!~"tmpfs|overlay|squashfs",mountpoint!~"/boot.*"} / node_filesystem_size_bytes) * 100'';
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
          evaluator = { params = [ 10 ]; type = "lt"; };
        }];
        refId = "C";
      };
    }
  ];
  "for" = "5m";
  noDataState = "NoData";
  execErrState = "Alerting";
  labels = { severity = "critical"; };
  annotations = {
    summary = "Disk usage above 90% on {{ $labels.instance }} mount {{ $labels.mountpoint }}";
  };
  isPaused = false;
}
```

### CPU Sustained Usage Alert (Complete Nix)

```nix
{
  uid = "high_cpu_usage";
  title = "High CPU Usage (>90% sustained)";
  condition = "C";
  data = [
    {
      refId = "A";
      relativeTimeRange = { from = 600; to = 0; };
      datasourceUid = "prometheus";
      model = {
        expr = ''100 - (avg by(instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)'';
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
          evaluator = { params = [ 90 ]; type = "gt"; };
        }];
        refId = "C";
      };
    }
  ];
  "for" = "5m";
  noDataState = "NoData";
  execErrState = "Alerting";
  labels = { severity = "warning"; };
  annotations = {
    summary = "CPU usage above 90% sustained for 5+ minutes on {{ $labels.instance }}";
  };
  isPaused = false;
}
```

### Uptime Dashboard Panel PromQL Queries

```promql
# Current availability percentage (24h window) -- for stat panels
avg_over_time(probe_success{job="blackbox-http",instance="http://192.168.68.65:8096"}[24h]) * 100

# Service status timeline -- for state-timeline panel
probe_success{job="blackbox-http"}

# Host reachability timeline -- for state-timeline panel
probe_success{job="blackbox-icmp"}

# TLS cert days remaining -- for stat panels
(probe_ssl_earliest_cert_expiry{job="blackbox-tls"} - time()) / 86400
```

### Friendly Service Names via label_replace()

```promql
# Transform raw instance URLs to friendly names in dashboard queries
label_replace(
  probe_success{job="blackbox-http"},
  "service",
  "$1",
  "instance",
  "http://[^:]+:(\\d+)"
)
```

Or use Grafana display name overrides in the dashboard JSON to map port numbers to service names:
- 8096 = Jellyfin
- 8989 = Sonarr
- 7878 = Radarr
- 9696 = Prowlarr
- 8080 = qBittorrent
- 8085 = SABnzbd
- 80 = Frigate
- 8123 = Home Assistant

## Gap Analysis: Existing Rules vs Phase 5 Requirements

| Requirement | Existing Rule | Phase 5 Action |
|-------------|---------------|----------------|
| HW-01: Disk 80% warning | `high_disk_usage` (90% only, no fstype filter) | REPLACE with `disk_usage_warning` (80%) + `disk_usage_critical` (90%), add fstype filter |
| HW-02: ZFS degraded | `zfs_pool_unhealthy` (exists) | KEEP existing rule, ADD ZFS scrub error coverage via zed |
| HW-02: ZFS scrub errors | None | ADD zed email notification for scrub events (not Prometheus-based) |
| HW-03: CPU >90% 5min | None | ADD `high_cpu_usage` rule |
| HW-04: Memory <10% | `high_memory_usage` (exists, correct) | KEEP as-is |
| HW-05: Temperature | `high_cpu_temp` (exists, correct) | KEEP as-is |
| DASH-01: Uptime dashboard | None | ADD `dashboards/uptime.json` with state-timeline panels |

## ZFS Scrub Error Monitoring Strategy

### Why Prometheus Metrics Won't Work

Neither the node_exporter ZFS collector nor the pdf/zfs_exporter expose scrub error counts as Prometheus metrics. The node_exporter exposes:
- `node_zfs_zpool_state{state="online|degraded|faulted|..."}` -- pool health, not scrub-specific
- ARC cache metrics, I/O metrics

The zfs-exporter (port 9134) exposes:
- `zfs_pool_health` -- numeric health (0=ONLINE, 1=DEGRADED, etc.)
- `zfs_pool_allocated_bytes`, `zfs_pool_free_bytes`, `zfs_pool_size_bytes` -- capacity
- No scrub-specific metrics

### Recommended Approach: ZFS Event Daemon (zed)

ZFS has a built-in event notification system called the ZFS Event Daemon (zed). NixOS supports configuring it via `services.zfs.zed`.

**Configuration:**
```nix
# In hosts/ser8/configuration.nix or a new module
services.zfs.zed = {
  enableMail = true;
  settings = {
    ZED_EMAIL_ADDR = [ "catgrep@sudomail.com" ];
    ZED_NOTIFY_VERBOSE = true;
    ZED_SCRUB_AFTER_RESILVER = true;
  };
};
```

**Events covered by zed:**
- `scrub_finish` -- scrub completion (reports error count)
- `resilver_finish` -- resilver completion
- `pool.state_change` -- pool transitions (online -> degraded)
- `vdev.state_change` -- individual vdev state changes
- `io_failure` -- I/O errors on vdevs

**Caveat:** zed requires a local MTA (mail transfer agent) to send email. On NixOS, this typically means configuring `msmtp` or `ssmtp` as a lightweight SMTP relay to Gmail. This adds a small dependency.

### Alternative: Accept Existing Coverage

The existing `zfs_pool_unhealthy` alert fires when a pool leaves the ONLINE state. Scrub errors that are severe enough to affect pool health WILL trigger this alert. Minor correctable scrub errors (which are informational, not actionable) would only be caught by zed or manual `zpool status` checks.

**Recommendation for Phase 5:** Keep the existing `zfs_pool_unhealthy` Grafana rule for degraded pool detection. Add zed configuration on ser8 for scrub error email notifications as a SEPARATE concern (not Grafana-managed). This requires setting up a lightweight MTA on ser8.

## Mount Points Reference (ser8)

These are the filesystem mount points that disk alerts should cover:

| Mount Point | Filesystem | Purpose | Alert? |
|-------------|-----------|---------|--------|
| `/` | ZFS (rpool/local/root) | Root (rolled back on boot) | Yes -- but may be transient |
| `/nix` | ZFS (rpool/local/nix) | Nix store | Yes -- critical |
| `/home` | ZFS (rpool/safe/home) | User homes | Yes |
| `/persist` | ZFS (rpool/safe/persist) | Persistent state | Yes -- critical |
| `/boot` | vfat (ESP) | Boot partition | No -- always high %, small |
| `/mnt/disk1` | ext4 | Media disk 1 (MergerFS member) | Yes |
| `/mnt/disk2` | ext4 | Media disk 2 (MergerFS member) | Yes |
| `/mnt/media` | fuse.mergerfs | Unified media view | No -- not a real filesystem |
| `/mnt/backups` | ZFS (backup/backups) | Backup storage | Yes |
| `/mnt/cameras` | ZFS (backup/cameras) | Camera recordings | Yes -- already has separate rule |
| `/tmp` | tmpfs | Build temp | No -- tmpfs |

**PromQL filter for meaningful mount points:**
```promql
node_filesystem_avail_bytes{
  fstype!~"tmpfs|overlay|squashfs|devtmpfs|fuse\\.mergerfs",
  mountpoint!~"/boot.*|/run.*|/sys.*|/proc.*|/dev.*"
}
```

Note: MergerFS (`fuse.mergerfs`) should be excluded since it's a virtual union of disk1 and disk2. The individual disks are already monitored.

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Single disk threshold | Graduated warnings (80%/90%) | Industry standard | Gives time to respond before critical |
| Prometheus Alertmanager for ZFS scrub | zed (native ZFS) for scrub, Grafana for pool health | Always available | Scrub events are better handled by ZFS itself |
| Manual uptime checks | Grafana state-timeline + blackbox | Grafana 8+ (2021) | Visual history of service availability |
| Singlestat panels (legacy) | Stat panels | Grafana 7+ | Modern replacement with better threshold coloring |
| `irate()` for CPU alerts | `rate()` for CPU alerts | Best practice | `rate()` is smoother and less prone to flapping |

## Open Questions

1. **ZFS scrub error notification via zed requires MTA on ser8**
   - What we know: zed can send email on scrub completion with errors. NixOS supports `services.zfs.zed.enableMail`.
   - What's unclear: ser8 does not currently have an MTA configured. Adding `msmtp` or similar is straightforward but adds a new dependency and requires Gmail app password on ser8 (currently only on firebat).
   - Recommendation: Add lightweight MTA (msmtp) on ser8 with shared SOPS secret for Gmail app password. If complexity is concerning, defer zed to a follow-up and rely on existing pool health alert.

2. **ZFS metric name verification needed**
   - What we know: The existing `zfs_pool_unhealthy` rule uses `node_zfs_zpool_health_state{state!="online"}`. This metric name appears to come from the zfs-exporter scraped on port 9134, but the pdf/zfs_exporter documentation suggests the metric is `zfs_pool_health` (numeric, 0=ONLINE).
   - What's unclear: The exact metric name exposed by the version of zfs-exporter in nixpkgs 25.05. node_exporter exposes `node_zfs_zpool_state` (with label-based state tracking).
   - Recommendation: During implementation, query Prometheus to verify the actual metric name: `curl http://firebat:9090/api/v1/label/__name__/values | grep -i zfs`. The existing rule has been deployed in Phase 4 and presumably working, so the metric name is likely correct.

3. **Dashboard instance label readability**
   - What we know: Blackbox probe targets use raw URLs as instance labels (e.g., `http://192.168.68.65:8096`).
   - What's unclear: Best approach for friendly names in dashboard -- Grafana overrides vs Prometheus relabel vs label_replace().
   - Recommendation: Use Grafana field display name overrides in the dashboard JSON. This keeps Prometheus configuration clean and is dashboard-specific.

## Sources

### Primary (HIGH confidence)
- [Awesome Prometheus Alerts](https://samber.github.io/awesome-prometheus-alerts/rules.html) -- Disk, CPU, memory alert PromQL patterns
- [Grafana Status History Documentation](https://grafana.com/docs/grafana/latest/panels-visualizations/visualizations/status-history/) -- Panel configuration, value mappings
- [Grafana State Timeline Documentation](https://grafana.com/docs/grafana/latest/panels-visualizations/visualizations/state-timeline/) -- Panel configuration, state merging
- [Grafana Uptime Status Dashboard Overview (ID 21275)](https://grafana.com/grafana/dashboards/21275-application-status-overview-agileos-consulting/) -- Reference dashboard for blackbox uptime
- [node_exporter ZFS Collector](https://deepwiki.com/prometheus/node_exporter/3.8-zfs-collector) -- ZFS metric names in node_exporter
- [pdf/zfs_exporter](https://github.com/pdf/zfs_exporter) -- ZFS pool health metric
- [Robust Perception: Understanding Machine CPU Usage](https://www.robustperception.io/understanding-machine-cpu-usage/) -- CPU PromQL patterns
- [Robust Perception: Reduce Noise from Disk Space Alerts](https://www.robustperception.io/reduce-noise-from-disk-space-alerts/) -- Filesystem filter best practices

### Secondary (MEDIUM confidence)
- [Uptime Monitoring with Prometheus and Grafana](https://sterba.dev/posts/uptime-monitoring/) -- probe_success dashboard pattern
- [Grafana Community: Graduated Severity Thresholds](https://community.grafana.com/t/one-alert-rule-with-severity-thresholds-warn-critical-etc/84261) -- Dynamic label tradeoffs
- [OneUptime: Grafana Status History](https://oneuptime.com/blog/post/2026-01-30-grafana-status-history/view) -- Status history panel setup

### Codebase (HIGH confidence)
- `modules/gateway/grafana.nix` -- Existing 9 alert rules, contact point, SMTP, dashboard provisioning pattern
- `modules/gateway/prometheus.nix` -- Existing ruleFiles, scrape configs, blackbox jobs
- `modules/gateway/blackbox.nix` -- Blackbox exporter configuration
- `modules/servers/monitoring.nix` -- node_exporter enabledCollectors, process-exporter
- `hosts/ser8/configuration.nix` -- ZFS config, zfs-exporter on port 9134, autoScrub settings
- `hosts/ser8/disko-config.nix` -- All mount points, ZFS pools, ext4 media disks

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- All components already deployed, no new services needed
- Architecture (alerts): HIGH -- Phase 4 research and implementation validated the Grafana alert rule pattern
- Architecture (dashboard): MEDIUM -- Dashboard JSON must be hand-crafted; pattern is established but exact panel config not yet validated
- Pitfalls: HIGH -- Filesystem filtering, ZFS scrub metric gap, and UID management verified against official docs and codebase
- ZFS scrub strategy: MEDIUM -- zed approach is well-documented but not yet implemented in this codebase; requires MTA setup

**Research date:** 2026-02-12
**Valid until:** 2026-03-14 (30 days -- stable components, well-established patterns)
