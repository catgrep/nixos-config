# Domain Pitfalls

**Domain:** Monitoring, Alerting, and Log Aggregation on NixOS Homelab
**Researched:** 2026-02-10

## Critical Pitfalls

Mistakes that cause rewrites, data loss, or major issues.

### Pitfall 1: Loki State Lost on ser8 Reboot (Impermanence) -- But Loki Runs on firebat

**What goes wrong:** You instinctively deploy Loki on ser8 (where most services live) and forget that ser8 rolls back root on every boot. Loki's index, chunks, WAL, and compactor state all live under `/var/lib/loki/` by default. After reboot, every log ever ingested is gone. Promtail's positions file on ser8 is also wiped, causing it to re-send all journald logs on next boot, creating massive duplicates in Loki.

**Why it happens:** ser8 uses ZFS "Erase Your Darlings" (`zfs rollback -r rpool/local/root@blank` in `initrd.postDeviceCommands`). Only directories explicitly listed in `environment.persistence."/persist".directories` survive. firebat has a standard ext4 root with no rollback -- state naturally persists there.

**Consequences:** Complete log data loss on every ser8 reboot. If Loki is on firebat (correct) but Promtail runs on ser8 without persisting its positions file, you get duplicate log ingestion after every reboot -- potentially millions of duplicate entries flooding Loki.

**Prevention:**
1. Deploy Loki on firebat (where Prometheus and Grafana already run). firebat has persistent ext4 storage with no rollback.
2. Deploy Promtail on ALL hosts (ser8, firebat, pi4) to ship their local journald logs to Loki on firebat.
3. On ser8, persist Promtail's positions file through impermanence:
   ```nix
   # In hosts/ser8/impermanence.nix
   environment.persistence."/persist".directories = [
     # ... existing entries ...
     "/var/lib/promtail"  # Promtail positions file
   ];
   ```
4. Configure Promtail to store positions in a persistent path:
   ```nix
   services.promtail.configuration.positions.filename = "/var/lib/promtail/positions.yaml";
   ```
5. Do NOT use `/tmp/positions.yaml` (default in many examples) -- this is wiped on every boot even without impermanence.

**Detection:** After ser8 reboot, check `wc -l /var/lib/promtail/positions.yaml`. If empty or missing, positions were not persisted. Check Loki for duplicate timestamps from ser8 after reboot.

**Phase:** Phase 1 (Loki + Promtail infrastructure). This is the single most impactful decision -- wrong host = data loss on every reboot.

**Confidence:** HIGH -- confirmed from examining `hosts/ser8/impermanence.nix` and `hosts/ser8/configuration.nix` (ZFS rollback at line 86). The positions file behavior is documented in [Grafana Loki troubleshooting docs](https://grafana.com/docs/loki/latest/send-data/promtail/troubleshooting/).

---

### Pitfall 2: Loki 3.x Requires TSDB + v13 Schema or Refuses to Start

**What goes wrong:** You copy a Loki configuration from an older blog post or the NixOS wiki that uses `boltdb-shipper` index type and `v11` or `v12` schema. Loki 3.x (which is what nixpkgs 25.05 ships) starts up but immediately fails with a configuration error because structured metadata is enabled by default in Loki 3.x and requires TSDB index with v13 schema.

**Why it happens:** Loki 3.0 made breaking changes: structured metadata is enabled by default, `boltdb-shipper` is deprecated, and the `shared_store` config was removed from shipper configuration. Most NixOS Loki examples online were written for Loki 2.x and use the old schema. The [NixOS wiki Grafana Loki page](https://wiki.nixos.org/wiki/Grafana_Loki) may still show v11/boltdb-shipper examples.

**Consequences:** Loki refuses to start entirely. The error message is somewhat opaque -- it mentions structured metadata configuration requirements without clearly stating "use TSDB + v13." You can spend hours debugging a configuration that simply needs a schema version bump.

**Prevention:**
1. For any new Loki deployment on nixpkgs 25.05+, use this schema config:
   ```nix
   services.loki.configuration = {
     schema_config.configs = [{
       from = "2024-01-01";
       store = "tsdb";
       object_store = "filesystem";
       schema = "v13";
       index = {
         prefix = "index_";
         period = "24h";
       };
     }];
   };
   ```
2. Do NOT copy `boltdb-shipper` configurations from older guides.
3. If you must disable structured metadata (not recommended), set `limits_config.allow_structured_metadata = false`.
4. Always check the Loki version in nixpkgs before choosing a config template: `nix eval nixpkgs#loki.version`.

**Detection:** Loki service fails to start. `journalctl -u loki` shows errors mentioning structured metadata, schema version, or TSDB requirements.

**Phase:** Phase 1 (Loki deployment). Wrong schema config = Loki will not start at all.

**Confidence:** HIGH -- confirmed via [Loki 3.0 release notes](https://grafana.com/docs/loki/latest/release-notes/v3-0/) and [Loki upgrade guide](https://grafana.com/docs/loki/latest/setup/upgrade/).

---

### Pitfall 3: Grafana SMTP Password in Nix Store is World-Readable

**What goes wrong:** You configure Grafana's SMTP settings for Gmail alerting using `services.grafana.settings.smtp.password = "your-app-password"`. This works, but the password is written in plaintext to `/nix/store/...grafana.ini` which is world-readable by every user on the system and persisted forever in the Nix store.

**Why it happens:** The NixOS Grafana module renders all `services.grafana.settings` into a Grafana configuration file in the Nix store. The Nix store is readable by all users by design. The `services.grafana.settings.smtp.password` option even has a documentation warning: "The contents of this option will end up in a world-readable Nix store."

**Consequences:** Your Gmail App Password is exposed to any user on firebat and in every Nix store garbage collection snapshot. If the server is ever compromised, the attacker gets SMTP credentials trivially.

**Prevention:**
1. Use Grafana's `$__file{/path}` provider to read the password from a file at runtime:
   ```nix
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
     startTLS_policy = "MandatoryStartTLS";
   };
   ```
2. This follows the same pattern already used for `grafana_admin_password` in the existing config (line 60 of `modules/gateway/grafana.nix`).
3. Add the Gmail App Password to `secrets/firebat.yaml` via `make sops-edit-firebat`.

**Detection:** Run `grep -r 'smtp' /nix/store/*grafana*` -- if you see a plaintext password, you have the problem. With `$__file{}`, you will see only the file path.

**Phase:** Phase 2 (Grafana alerting setup). Must be done before configuring email contact points.

**Confidence:** HIGH -- confirmed by [MyNixOS documentation](https://mynixos.com/nixpkgs/option/services.grafana.settings.smtp.password) which explicitly warns about world-readable Nix store.

---

### Pitfall 4: Promtail Cannot Read journald Without systemd-journal Group Membership

**What goes wrong:** Promtail starts on all hosts, connects to Loki, but sends zero log entries. No errors in Promtail logs -- it silently produces nothing. The journal scrape config looks correct but no logs flow.

**Why it happens:** On NixOS, the systemd journal files under `/var/log/journal/` (or `/run/log/journal/` for volatile storage) are owned by `root:systemd-journal`. The Promtail service runs as the `promtail` user, which by default is NOT a member of the `systemd-journal` group. Promtail [fails silently](https://github.com/grafana/loki/issues/7836) when it cannot read journal files -- it does not log an error, it just produces no output.

**Consequences:** You think the logging pipeline is working (Promtail running, Loki running, Grafana datasource connected) but Loki is completely empty. You waste hours debugging Loki configuration when the problem is a simple Unix permission issue on Promtail.

**Prevention:**
1. Add the promtail user to the `systemd-journal` group:
   ```nix
   users.users.promtail.extraGroups = [ "systemd-journal" ];
   ```
2. Apply this on EVERY host running Promtail (ser8, firebat, pi4).
3. Alternatively, configure the Promtail systemd service to run with supplementary groups:
   ```nix
   systemd.services.promtail.serviceConfig.SupplementaryGroups = [ "systemd-journal" ];
   ```
4. Verify journal path: on NixOS with persistent journal (which ser8 has via `/var/log` bind mount to `/persist/var/log`), journals are in `/var/log/journal/`. On hosts with volatile journal, they are in `/run/log/journal/`.

**Detection:** Run as promtail user: `sudo -u promtail journalctl --no-pager -n 1`. If "Permission denied" or empty, the group is missing. Also check `id promtail` for group membership.

**Phase:** Phase 1 (Promtail deployment). Without this, no logs are collected at all.

**Confidence:** HIGH -- confirmed via [Grafana Loki issue #7836](https://github.com/grafana/loki/issues/7836) (silent failure on permission denied) and [NixOS journal permissions discussion](https://github.com/NixOS/nixpkgs/issues/2865).

---

## Moderate Pitfalls

### Pitfall 5: Blackbox Exporter Requires Unintuitive Prometheus Relabeling Config

**What goes wrong:** You add `services.prometheus.exporters.blackbox` and a simple scrape job to Prometheus. Prometheus scrapes the blackbox exporter itself instead of using it to probe your target URLs. All probes show the blackbox exporter as healthy, but you have no data about your actual services.

**Why it happens:** The blackbox exporter uses the "multi-target exporter pattern." It does not scrape targets itself -- Prometheus must pass the target URL as a `?target=` parameter. This requires a specific relabel_configs sequence that is not intuitive: (1) copy `__address__` to `__param_target`, (2) copy `__param_target` to `instance`, (3) replace `__address__` with the blackbox exporter's address. Getting any step wrong results in either scraping the exporter itself or broken target resolution.

**Consequences:** Your "uptime monitoring" shows everything as up (because it is only probing the blackbox exporter, which is running). You have no actual HTTP health data for any services. You discover this during an outage when the monitoring was supposed to alert you.

**Prevention:**
1. Use the exact relabeling pattern from the [Prometheus multi-target exporter guide](https://prometheus.io/docs/guides/multi-target-exporter/):
   ```nix
   services.prometheus.scrapeConfigs = [{
     job_name = "blackbox-http";
     metrics_path = "/probe";
     params.module = [ "http_2xx" ];
     static_configs = [{
       targets = [
         "http://ser8.local:8096"  # Jellyfin
         "http://ser8.local:8989"  # Sonarr
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
         replacement = "localhost:9115";  # blackbox exporter address
       }
     ];
   }];
   ```
2. After deploying, verify with `curl 'http://localhost:9115/probe?target=http://ser8.local:8096&module=http_2xx'` -- you should see `probe_success 1`.
3. Do NOT just add the blackbox exporter to `static_configs.targets` as you would a normal exporter -- this is the #1 mistake.

**Detection:** In Grafana, query `probe_success`. If the metric does not exist, the relabeling is wrong. If the `instance` label shows `localhost:9115` instead of your service URLs, the relabeling is wrong.

**Phase:** Phase 2 (blackbox exporter setup). The relabeling config is correct-or-broken, no middle ground.

**Confidence:** HIGH -- confirmed via [Prometheus official guide](https://prometheus.io/docs/guides/multi-target-exporter/) and [blackbox exporter README](https://github.com/prometheus/blackbox_exporter/blob/master/README.md).

---

### Pitfall 6: Grafana File-Provisioned Alert Rules Cannot Be Edited in the UI

**What goes wrong:** You declaratively provision Grafana alert rules, notification policies, and contact points via NixOS `services.grafana.provision.alerting`. The rules deploy successfully. Later, you need to tweak an alert threshold or add a label matcher. You open Grafana's UI to edit -- but every provisioned resource is locked and shows "This resource is provisioned and cannot be edited."

**Why it happens:** Grafana intentionally locks file-provisioned alerting resources to prevent the UI from making changes that would be overwritten on next restart. This is by design in Grafana's [file provisioning system](https://grafana.com/docs/grafana/latest/alerting/set-up/provision-alerting-resources/file-provisioning/). Unlike dashboards (which have an `allowUiUpdates` option), alerting resources have no such escape hatch when provisioned via files.

**Consequences:** Every alert rule change requires a NixOS rebuild and deployment. This is fine for mature, stable rules but terrible during the initial tuning phase where you are adjusting thresholds, silence windows, and notification routing daily. The iteration cycle goes from "click save" to "edit nix, rebuild, deploy, wait for restart."

**Prevention:**
1. **Phase the approach:** Start with alert rules defined ONLY in the Grafana UI during the initial tuning period. Once rules are stable, migrate them to NixOS provisioning for version control.
2. **Keep Prometheus alert rules in Prometheus** (as already done in `prometheus.nix` lines 142-194). Prometheus `ruleFiles` are hot-reloaded and not subject to this UI-locking issue.
3. **For Grafana-specific alerts** (Loki log queries, multi-datasource alerts), provision only the contact points and notification policies via NixOS. Create the actual alert rules via the UI until they stabilize.
4. **If you must provision everything:** Accept that iteration requires rebuilds, and use `make test-firebat` for rapid testing.

**Detection:** Try editing a provisioned alert rule in Grafana UI. If you see "provisioned" badge and edit is disabled, this is working as designed. Plan your workflow accordingly.

**Phase:** Phase 2 (alerting setup). Decide the provisioning strategy before writing any rules.

**Confidence:** HIGH -- confirmed by [Grafana provisioning docs](https://grafana.com/docs/grafana/latest/alerting/set-up/provision-alerting-resources/file-provisioning/) and [Grafana blog post](https://grafana.com/blog/2023/09/11/how-to-provision-a-notification-policy-in-grafana-alerting-and-keep-it-editable-in-the-ui/) which documents the API-only workaround.

---

### Pitfall 7: Loki Retention Does Not Work Without Compactor Configuration

**What goes wrong:** You set `limits_config.retention_period = "30d"` in Loki and expect old logs to be deleted after 30 days. Months later, Loki's storage directory has grown to fill the disk. Retention never ran.

**Why it happens:** Loki's retention is handled by the compactor component, and by default `compactor.retention_enabled` is `false`. Setting `retention_period` without enabling the compactor's retention does nothing -- the config value is ignored. This is a [well-documented surprise](https://grafana.com/docs/loki/latest/operations/storage/retention/) that catches many users.

**Consequences:** Unbounded disk growth on firebat. Eventually firebat's 512GB NVMe fills up, Loki crashes, and potentially takes Grafana and Prometheus down with it (shared filesystem). A homelab with 4 hosts generating continuous journald logs can produce 1-5 GB/day of compressed log data.

**Prevention:**
1. Always configure the compactor alongside retention:
   ```nix
   services.loki.configuration = {
     compactor = {
       working_directory = "/var/lib/loki/compactor";
       compaction_interval = "10m";
       retention_enabled = true;
       retention_delete_delay = "2h";
       retention_delete_worker_count = 150;
       delete_request_store = "filesystem";
     };
     limits_config = {
       retention_period = "30d";
     };
   };
   ```
2. Monitor disk usage with the existing node-exporter filesystem metrics. Add an alert for Loki's data directory.
3. Start with a conservative retention period (14d) and adjust based on actual disk usage.
4. Set `storage_config.filesystem.directory` explicitly to a known location so you can monitor it.

**Detection:** Check `du -sh /var/lib/loki/chunks/` periodically. If it grows without bound, retention is not running. Check `journalctl -u loki | grep compactor` for compaction activity.

**Phase:** Phase 1 (Loki deployment). Configure retention from day one -- retrofitting is harder.

**Confidence:** HIGH -- confirmed by [Loki retention documentation](https://grafana.com/docs/loki/latest/operations/storage/retention/) and multiple [community forum posts](https://community.grafana.com/t/loki-k8s-single-binary-log-retention-configuration-not-deleting-logs/78734).

---

### Pitfall 8: Home Assistant Prometheus Integration Requires Manual configuration.yaml Entry on ser8

**What goes wrong:** You add a Prometheus scrape job on firebat targeting `http://ser8.local:8123/api/prometheus`. Prometheus gets 404 errors. The `/api/prometheus` endpoint does not exist.

**Why it happens:** Home Assistant's Prometheus integration must be explicitly enabled by adding `prometheus:` to `configuration.yaml`. Unlike many HA integrations, this one IS configured via YAML (not the UI config flow). However, on NixOS, `configuration.yaml` is managed by `services.home-assistant.config`. You must add the `prometheus` key to the Nix config. Additionally, the endpoint requires a Long-Lived Access Token for authentication from external scrapers.

**Consequences:** No Home Assistant metrics in Prometheus. You cannot monitor entity states, automation execution counts, or HA internal performance. The scrape job silently fails with 401/404 errors.

**Prevention:**
1. Add the Prometheus integration to the HA NixOS config:
   ```nix
   services.home-assistant.config.prometheus = {
     namespace = "hass";
     filter = {
       include_domains = [
         "sensor"
         "binary_sensor"
         "switch"
         "automation"
         "camera"
       ];
     };
   };
   ```
2. Include `"prometheus"` in `extraComponents`:
   ```nix
   services.home-assistant.extraComponents = [
     # ... existing ...
     "prometheus"
   ];
   ```
3. For Prometheus scraping from firebat, create a Long-Lived Access Token in HA (user profile > Security > Long-Lived Access Tokens) and configure the scrape job with bearer auth:
   ```nix
   {
     job_name = "home-assistant";
     bearer_token_file = config.sops.secrets.hass_prometheus_token.path;
     static_configs = [{
       targets = [ "ser8.local:8123" ];
     }];
     metrics_path = "/api/prometheus";
     scheme = "http";
   }
   ```
4. Store the token in SOPS for the firebat host.

**Detection:** `curl -H "Authorization: Bearer <token>" http://ser8.local:8123/api/prometheus` -- if 404, the integration is not enabled. If 401, the token is wrong.

**Phase:** Phase 3 (HA monitoring integration). Not blocking for core logging/alerting but needed for complete monitoring.

**Confidence:** HIGH -- confirmed via [Home Assistant Prometheus integration docs](https://www.home-assistant.io/integrations/prometheus/).

---

### Pitfall 9: Grafana Unified Alerting vs Prometheus Alertmanager Confusion

**What goes wrong:** You have existing Prometheus alert rules in `prometheus.nix` (HostDown, HighDiskUsage, ZFSPoolUnhealthy, etc.). You add Grafana unified alerting. Now you have two separate alerting systems that do not talk to each other. Prometheus fires alerts to nowhere (no alertmanager configured), and Grafana evaluates its own rules independently. You get duplicate alerts for some conditions and no alerts for others.

**Why it happens:** The existing Prometheus config defines `ruleFiles` with alert rules but does NOT configure an alertmanager to send them to. Grafana's unified alerting includes its own built-in Alertmanager. These are separate systems. Adding Grafana alerting does not automatically pick up Prometheus alert rules -- you have to connect them explicitly or choose one approach.

**Consequences:** Alert rules fire in Prometheus but nobody is notified (no alertmanager). Grafana alerts fire separately. Confusion about which system is authoritative. Potential for "alert fatigue" from duplicates or "alert blind spots" from gaps.

**Prevention:**
1. **Choose one approach for notifications.** Recommended: Use Grafana's built-in Alertmanager for ALL notifications. Configure Prometheus to forward its alerts to Grafana's Alertmanager.
   ```nix
   services.prometheus.alertmanagers = [{
     static_configs = [{
       targets = [ "localhost:9093" ];  # Grafana's built-in Alertmanager
     }];
   }];
   ```
   Note: Grafana's internal Alertmanager listens on port 9093 when unified alerting is enabled.
2. **Alternatively**, keep Prometheus rules as the source of truth for metric-based alerts, and use Grafana alerting ONLY for Loki log-based alerts. This avoids duplication but requires configuring a separate Alertmanager for Prometheus.
3. **Migrate gradually**: Keep existing Prometheus rules during the transition. Add Grafana alerting for NEW alert types (log-based, multi-datasource). Once Grafana alerting is proven, consider migrating Prometheus rules into Grafana.
4. The key question to decide upfront: "Where do alert notifications originate?" Pick one answer.

**Detection:** Check `http://localhost:9090/alerts` (Prometheus) -- if alerts are firing but nobody is notified, alertmanager is not configured. Check `Grafana > Alerting > Alert Rules` -- if Grafana rules exist for the same conditions as Prometheus rules, you have duplication.

**Phase:** Phase 2 (alerting strategy). Must be decided before writing any alert rules.

**Confidence:** HIGH -- confirmed via [Grafana alerting architecture docs](https://grafana.com/docs/grafana/latest/alerting/set-up/configure-alertmanager/) and examination of current `prometheus.nix` (alert rules defined but no alertmanager configured).

---

### Pitfall 10: Loki Datasource Must Be Provisioned Separately in Grafana

**What goes wrong:** You deploy Loki, confirm it is receiving logs, but when you go to Grafana to query logs, Loki does not appear as a datasource. You can only query Prometheus (the existing provisioned datasource).

**Why it happens:** The current Grafana provisioning in `modules/gateway/grafana.nix` only provisions a Prometheus datasource (lines 72-84). Adding Loki as a service does not automatically add it as a Grafana datasource. You must explicitly provision it.

**Consequences:** Loki is collecting logs but you cannot visualize or search them in Grafana. The entire logging pipeline is invisible.

**Prevention:**
1. Add Loki to the existing datasource provisioning:
   ```nix
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
       jsonData = {
         maxLines = 1000;
       };
     }
   ];
   ```
2. Since both Loki and Grafana run on firebat, use `localhost:3100` (Loki's default port).
3. Open the firewall for Loki only if Promtail on remote hosts needs to reach it (port 3100). For firebat-local Grafana access, no firewall rule needed.

**Detection:** In Grafana, go to Connections > Data Sources. If Loki is not listed, it was not provisioned.

**Phase:** Phase 1 (Loki deployment). Without this, you deploy the logging stack but cannot use it.

**Confidence:** HIGH -- confirmed by examining existing `modules/gateway/grafana.nix` which only provisions Prometheus.

---

### Pitfall 11: Promtail on Remote Hosts Needs Network Access to Loki on firebat

**What goes wrong:** Promtail starts on ser8 and pi4 but cannot push logs to Loki. Connection refused or timeout errors. Logs accumulate in Promtail's WAL but never reach Loki.

**Why it happens:** Loki on firebat listens on a port (default 3100) but firebat's firewall does not allow incoming connections on that port. The current `modules/gateway` config only opens ports 80, 443, 2019 (Caddy), 9090 (Prometheus), and 3000 (Grafana). Port 3100 is not exposed. Additionally, Promtail on remote hosts must be configured with `http://firebat.local:3100` (or the IP), not `http://localhost:3100`.

**Consequences:** Logs from ser8 (media stack, Frigate, HA) and pi4 (AdGuard) never reach Loki. Only firebat's own logs are ingested. You think the system works because Grafana shows some logs (firebat's), but you are missing the most important ones (ser8 services).

**Prevention:**
1. Open port 3100 on firebat's firewall:
   ```nix
   networking.firewall.allowedTCPPorts = [ 3100 ];
   ```
2. Configure Promtail on ser8 and pi4 to push to firebat:
   ```nix
   services.promtail.configuration.clients = [{
     url = "http://firebat.local:3100/loki/api/v1/push";
   }];
   ```
3. Use `firebat.local` (mDNS) rather than static IP -- the existing Prometheus scrape configs already use `.local` names successfully (line 30-33 of `prometheus.nix`).
4. Verify connectivity from ser8: `curl http://firebat.local:3100/ready` should return "ready".

**Detection:** On ser8, `journalctl -u promtail | grep -i error` will show connection failures. On firebat, `curl http://localhost:3100/loki/api/v1/tail` should stream incoming logs when Promtail is pushing.

**Phase:** Phase 1 (Promtail deployment). This is a multi-host networking concern.

**Confidence:** HIGH -- confirmed by examining `modules/gateway/caddy.nix` firewall rules and the existing pattern of cross-host communication via `.local` mDNS.

---

## Minor Pitfalls

### Pitfall 12: Gmail App Password Has 16-Character Format and TLS Requirements

**What goes wrong:** You configure Grafana SMTP with your regular Gmail password. Authentication fails. Or you use an App Password but set the wrong TLS policy, and emails silently fail to send.

**Why it happens:** Gmail requires App Passwords (not regular passwords) when accessed by third-party SMTP clients. App Passwords are 16 characters with spaces (format: `xxxx xxxx xxxx xxxx`). Additionally, Gmail requires STARTTLS on port 587 -- using port 465 (implicit TLS) or port 25 (no TLS) will not work.

**Prevention:**
1. Generate an App Password: Google Account > Security > 2-Step Verification > App Passwords.
2. Use the exact SMTP config:
   - Host: `smtp.gmail.com:587`
   - `startTLS_policy = "MandatoryStartTLS"`
   - `skip_verify = false`
3. Store the App Password in SOPS, not in Nix config (see Pitfall 3).
4. If the App Password contains special characters (`#`, `;`), ensure Grafana's config file handles quoting correctly. The `$__file{}` provider avoids this issue entirely since it reads raw file content.

**Detection:** After configuring SMTP, use Grafana's "Test" button on the email contact point. If it fails, check `journalctl -u grafana` for SMTP errors (auth failure, TLS handshake failure, connection refused).

**Phase:** Phase 2 (alerting contact points).

**Confidence:** HIGH -- confirmed via [Grafana community forums](https://community.grafana.com/t/setup-smtp-with-gmail/85815) and [Grafana email alerting docs](https://grafana.com/docs/grafana/latest/alerting/configure-notifications/manage-contact-points/integrations/configure-email/).

---

### Pitfall 13: Loki WAL Disk Full Causes Silent Log Loss (No Error, No Crash)

**What goes wrong:** firebat's disk fills up. Loki does not crash -- it keeps running and accepting writes. But the WAL (Write Ahead Log) cannot persist incoming data. If Loki restarts while in this state, all unwritten logs are lost permanently. There is no visible error in the Loki API -- incoming push requests still return 200 OK.

**Why it happens:** Loki's WAL has an explicit design decision: "When the underlying WAL disk is full, Loki will not fail incoming writes, but neither will it log them to the WAL." This means Promtail thinks delivery was successful, but the data was silently dropped.

**Prevention:**
1. Monitor firebat's disk usage and set an aggressive threshold. Add a Prometheus alert:
   ```yaml
   - alert: LokiStorageHigh
     expr: (node_filesystem_avail_bytes{instance=~"firebat.*",mountpoint="/"} / node_filesystem_size_bytes{instance=~"firebat.*",mountpoint="/"}) * 100 < 20
     for: 10m
     labels:
       severity: warning
     annotations:
       summary: "firebat disk is above 80% - Loki data at risk"
   ```
2. Set Loki's data directory to a known location and configure conservative retention (see Pitfall 7).
3. Monitor the Prometheus metric `loki_ingester_wal_disk_full_failures_total` -- any non-zero value means data was silently dropped.
4. firebat has a 512GB NVMe with ext4. With Prometheus (30d retention, ~10GB), Grafana, and Caddy already on this disk, budget Loki's storage carefully. Start with 14d retention and 50GB cap.

**Detection:** The ONLY way to detect this is via the `loki_ingester_wal_disk_full_failures_total` metric. Check it periodically or set an alert on it.

**Phase:** Phase 1 (Loki deployment). Set retention and monitoring from day one.

**Confidence:** HIGH -- confirmed via [Loki WAL documentation](https://grafana.com/docs/loki/latest/operations/storage/wal/).

---

### Pitfall 14: Blackbox Exporter TLS Verification Fails on Self-Signed Caddy Certificates

**What goes wrong:** You configure the blackbox exporter to probe HTTPS endpoints like `https://jellyfin.vofi.app`. The probes fail because Caddy uses `local_certs` (self-signed certificates from Caddy's local CA). The blackbox exporter does not trust this CA.

**Why it happens:** The current Caddyfile (line 3) uses `local_certs`, meaning Caddy generates certificates signed by its own CA. These are not trusted by the system's certificate store. The blackbox exporter's `http_2xx` module verifies TLS by default.

**Consequences:** All HTTPS probes show as failed, making the uptime dashboard useless for local services.

**Prevention:**
1. Configure blackbox probes against the HTTP (non-TLS) endpoints directly:
   ```
   http://ser8.local:8096     # Jellyfin (skip Caddy entirely)
   http://ser8.local:8989     # Sonarr
   ```
2. Or add a blackbox module that disables TLS verification:
   ```nix
   services.prometheus.exporters.blackbox.configFile = pkgs.writeText "blackbox.yml" ''
     modules:
       http_2xx:
         prober: http
         timeout: 10s
       http_2xx_insecure:
         prober: http
         timeout: 10s
         http:
           tls_config:
             insecure_skip_verify: true
   '';
   ```
3. For Tailscale endpoints (`*.shad-bangus.ts.net`), TLS verification WILL work because these use real Let's Encrypt certificates. Probe these endpoints to verify external accessibility.
4. Best approach: probe the direct service ports (HTTP) for health, and probe Tailscale HTTPS URLs for external accessibility.

**Detection:** `probe_success{instance=~".*vofi.*"} == 0` with `probe_http_status_code == 0` (connection failed, not a 4xx/5xx).

**Phase:** Phase 2 (blackbox exporter configuration).

**Confidence:** HIGH -- confirmed by examining `modules/gateway/Caddyfile` line 3 (`local_certs`) and standard TLS verification behavior.

---

### Pitfall 15: NixOS Promtail Module Has Limited Configuration Options

**What goes wrong:** You try to use NixOS `services.promtail` options for fine-grained control (setting the user, configuring systemd service properties, adding supplementary groups). The module is minimal -- it only provides `enable`, `configuration`, `configFile`, and `extraFlags`. There is no `user`, `group`, or `serviceConfig` override.

**Why it happens:** The NixOS Promtail module at `nixos/modules/services/monitoring/promtail.nix` is intentionally minimal. It creates a systemd service that runs as a DynamicUser (or the promtail user) with hardcoded service settings. Customizing beyond what the module exposes requires systemd service overrides.

**Consequences:** You cannot simply set `services.promtail.user = "root"` or add group memberships through the module. You must use `systemd.services.promtail.serviceConfig` overrides and `users.users.promtail` to customize the runtime environment.

**Prevention:**
1. Use `systemd.services.promtail.serviceConfig` for service-level customizations:
   ```nix
   systemd.services.promtail.serviceConfig = {
     SupplementaryGroups = [ "systemd-journal" ];
   };
   ```
2. Define the user explicitly if needed:
   ```nix
   users.users.promtail = {
     isSystemUser = true;
     group = "promtail";
     extraGroups = [ "systemd-journal" ];
   };
   users.groups.promtail = {};
   ```
3. Check if the NixOS module creates a DynamicUser (which complicates group membership). If so, you may need to disable DynamicUser and manage the user yourself.

**Detection:** After deployment, `systemctl show promtail | grep -i user` reveals how the service runs. `id promtail` shows group memberships.

**Phase:** Phase 1 (Promtail deployment on all hosts).

**Confidence:** MEDIUM -- based on NixOS module structure patterns. The exact module behavior should be verified at deployment time by checking `nixpkgs/nixos/modules/services/monitoring/promtail.nix`.

---

### Pitfall 16: Existing Prometheus Alert Rules Fire But Nobody Is Notified

**What goes wrong:** Your existing Prometheus config (`modules/gateway/prometheus.nix`) already defines alert rules (HostDown, HighDiskUsage, HighMemoryUsage, ZFSPoolUnhealthy, HighCPUTemperature, CameraStorageHigh). These rules ARE being evaluated. They ARE firing (visible at `http://localhost:9090/alerts`). But nobody receives any notification because there is no alertmanager configured.

**Why it happens:** Prometheus alert rules define WHEN to alert. An Alertmanager defines HOW to notify. The current config has rules but no `alertmanagers` configuration pointing to any notification system. The rules are decorative.

**Consequences:** You already have monitoring blind spots. If ser8's ZFS pool becomes unhealthy TODAY, the alert fires in Prometheus, but you will not know until you happen to check the Prometheus UI.

**Prevention:**
1. This is not a new pitfall -- it is a pre-existing gap that this milestone addresses.
2. The first priority of this milestone should be connecting the existing Prometheus rules to a notification path (Gmail via Grafana alerting).
3. See Pitfall 9 for the decision about Grafana vs Prometheus Alertmanager.

**Detection:** Visit `http://firebat.local:9090/alerts`. If any alerts show as "firing" or "pending," they have been detected but not notified.

**Phase:** Phase 2 (alerting infrastructure). This should be one of the first things configured.

**Confidence:** HIGH -- confirmed by examining `modules/gateway/prometheus.nix` lines 140-196 (rules defined) with no `alertmanagers` configuration anywhere in the file.

---

### Pitfall 17: Promtail Sends Massive Backlog After ser8 Reboot If Journal Is Large

**What goes wrong:** After a ser8 reboot, Promtail starts and reads from the beginning of its configured `max_age` window in the journal. If `max_age` is set to a large value (or not set at all, defaulting to 7 years), Promtail reads and sends the ENTIRE persisted journal history to Loki. Since ser8 persists `/var/log` via bind mount (line 176-179 in impermanence.nix), the journal can be substantial.

**Why it happens:** On a fresh Promtail start with no positions file (or a stale one), `max_age` determines how far back to read. The journal at `/persist/var/log/journal/` accumulates continuously. ser8's journald config keeps up to 1GB of journal data (`SystemMaxUse=1G` in monitoring.nix line 160).

**Consequences:** After reboot, Promtail floods Loki with up to 1GB of log data, which may include logs that were already ingested before the reboot. This causes duplicate entries and a spike in Loki resource usage. On a small homelab, this can temporarily overwhelm Loki.

**Prevention:**
1. Set a conservative `max_age` in Promtail's journal scrape config:
   ```nix
   services.promtail.configuration.scrape_configs = [{
     job_name = "journal";
     journal = {
       max_age = "12h";  # Only send logs from last 12 hours on fresh start
       labels.job = "systemd-journal";
     };
   }];
   ```
2. Persist the positions file on ser8 (see Pitfall 1). This is the primary prevention.
3. Consider `services.journald.extraConfig = "SystemMaxUse=500M"` to limit journal size.
4. With the positions file persisted, Promtail resumes from where it left off -- no backlog.

**Detection:** After reboot, check `journalctl -u promtail --since "5min ago"` for rapid log shipping activity. Check Loki ingestion rate metric `loki_distributor_bytes_received_total` for a spike.

**Phase:** Phase 1 (Promtail on ser8). Directly related to Pitfall 1.

**Confidence:** HIGH -- confirmed by examining impermanence config (journal is persisted) and [Promtail journal configuration docs](https://grafana.com/docs/loki/latest/send-data/promtail/configuration/).

---

## Phase-Specific Warnings

| Phase Topic | Likely Pitfall | Mitigation |
|-------------|---------------|------------|
| Phase 1: Loki Deployment | Wrong host (ser8 vs firebat) | Deploy on firebat where state naturally persists (Pitfall 1) |
| Phase 1: Loki Deployment | boltdb-shipper schema in old examples | Use TSDB + v13 schema for Loki 3.x (Pitfall 2) |
| Phase 1: Loki Deployment | No retention configured | Enable compactor + retention from day one (Pitfall 7) |
| Phase 1: Loki Deployment | WAL silent data loss on disk full | Monitor disk, set retention caps (Pitfall 13) |
| Phase 1: Promtail Deployment | Journal permission denied (silent) | Add promtail to systemd-journal group on all hosts (Pitfall 4) |
| Phase 1: Promtail Deployment | Positions file lost on ser8 reboot | Persist `/var/lib/promtail` via impermanence (Pitfall 1) |
| Phase 1: Promtail Deployment | Massive backlog after reboot | Set max_age + persist positions file (Pitfall 17) |
| Phase 1: Promtail Deployment | Cannot reach Loki on firebat | Open port 3100 on firebat firewall (Pitfall 11) |
| Phase 1: Grafana Datasource | Loki not visible in Grafana | Provision Loki as datasource alongside Prometheus (Pitfall 10) |
| Phase 2: SMTP Setup | Password in Nix store | Use $__file{} with SOPS secret (Pitfall 3) |
| Phase 2: Gmail Config | Wrong TLS settings or regular password | Use App Password + STARTTLS on port 587 (Pitfall 12) |
| Phase 2: Alert Strategy | Prometheus + Grafana alerting confusion | Choose one notification path, decide before writing rules (Pitfall 9) |
| Phase 2: Alert Rules | File-provisioned rules locked in UI | Start with UI rules, provision after stabilizing (Pitfall 6) |
| Phase 2: Blackbox Exporter | Wrong relabeling pattern | Use exact multi-target pattern from Prometheus docs (Pitfall 5) |
| Phase 2: Blackbox Exporter | TLS failures on self-signed certs | Probe HTTP ports directly or skip TLS verify (Pitfall 14) |
| Phase 2: Existing Rules | Current Prometheus rules fire silently | Connect to Grafana Alertmanager as first priority (Pitfall 16) |
| Phase 3: HA Monitoring | Prometheus endpoint not enabled | Add prometheus integration to HA NixOS config (Pitfall 8) |
| Phase 3: HA Monitoring | Auth token needed for external scraping | Create Long-Lived Access Token, store in SOPS (Pitfall 8) |

## Sources

- [Loki 3.0 Release Notes](https://grafana.com/docs/loki/latest/release-notes/v3-0/) - HIGH confidence
- [Loki Upgrade Guide](https://grafana.com/docs/loki/latest/setup/upgrade/) - HIGH confidence
- [Loki Retention Documentation](https://grafana.com/docs/loki/latest/operations/storage/retention/) - HIGH confidence
- [Loki WAL Documentation](https://grafana.com/docs/loki/latest/operations/storage/wal/) - HIGH confidence
- [Loki TSDB Documentation](https://grafana.com/docs/loki/latest/operations/storage/tsdb/) - HIGH confidence
- [Promtail Troubleshooting](https://grafana.com/docs/loki/latest/send-data/promtail/troubleshooting/) - HIGH confidence
- [Promtail Configuration](https://grafana.com/docs/loki/latest/send-data/promtail/configuration/) - HIGH confidence
- [Promtail Silent Journal Permission Failure - Issue #7836](https://github.com/grafana/loki/issues/7836) - HIGH confidence
- [NixOS Journal Permissions - Issue #2865](https://github.com/NixOS/nixpkgs/issues/2865) - HIGH confidence
- [Prometheus Multi-Target Exporter Guide](https://prometheus.io/docs/guides/multi-target-exporter/) - HIGH confidence
- [Blackbox Exporter README](https://github.com/prometheus/blackbox_exporter/blob/master/README.md) - HIGH confidence
- [Grafana File Provisioning Docs](https://grafana.com/docs/grafana/latest/alerting/set-up/provision-alerting-resources/file-provisioning/) - HIGH confidence
- [Grafana SMTP Password NixOS Warning](https://mynixos.com/nixpkgs/option/services.grafana.settings.smtp.password) - HIGH confidence
- [Grafana Email Alert Configuration](https://grafana.com/docs/grafana/latest/alerting/configure-notifications/manage-contact-points/integrations/configure-email/) - HIGH confidence
- [Grafana Alertmanager Configuration](https://grafana.com/docs/grafana/latest/alerting/set-up/configure-alertmanager/) - HIGH confidence
- [Home Assistant Prometheus Integration](https://www.home-assistant.io/integrations/prometheus/) - HIGH confidence
- [NixOS Wiki - Grafana Loki](https://wiki.nixos.org/wiki/Grafana_Loki) - MEDIUM confidence (may have outdated examples)
- [NixOS Wiki - Grafana](https://wiki.nixos.org/wiki/Grafana) - MEDIUM confidence
- [Loki Configuration Verification - NixOS Issue #293088](https://github.com/NixOS/nixpkgs/issues/293088) - MEDIUM confidence
- [Gmail SMTP Grafana Setup](https://community.grafana.com/t/setup-smtp-with-gmail/85815) - MEDIUM confidence
- [Grafana Blog: Provisioning Notification Policies](https://grafana.com/blog/2023/09/11/how-to-provision-a-notification-policy-in-grafana-alerting-and-keep-it-editable-in-the-ui/) - MEDIUM confidence
- [NixOS Observability Stack Example](https://github.com/shinbunbun/nixos-observability) - LOW confidence (third-party example)
