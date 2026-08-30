# SPDX-License-Identifier: GPL-3.0-or-later

{
  config,
  lib,
  pkgs,
  ...
}:

{
  services.prometheus = {
    enable = lib.mkDefault true;
    port = 9090;

    # Scrape configs for monitoring homelab hosts
    # Where a firing rule is sent. Without this list Prometheus evaluates every
    # rule below, marks them firing, and delivers them nowhere -- a failure mode
    # that is invisible from the rules page, which shows exactly the same thing
    # either way.
    alertmanagers = [
      {
        static_configs = [ { targets = [ "127.0.0.1:9093" ]; } ];
      }
    ];

    scrapeConfigs = [
      {
        job_name = "prometheus";
        static_configs = [
          {
            targets = [ "localhost:9090" ];
          }
        ];
      }
      {
        job_name = "node-exporter";
        static_configs = [
          {
            targets = [
              "ser8.local:9100" # Beelink node exporter
              "firebat.local:9100" # Firebat node exporter
              "pi4.local:9100" # Pi4 node exporter
            ];
          }
        ];
        scrape_interval = "15s";
        metrics_path = "/metrics";
      }
      {
        job_name = "zfs-exporter";
        static_configs = [
          {
            targets = [
              "ser8.local:9134" # ZFS metrics from Beelink
            ];
          }
        ];
        scrape_interval = "30s";
      }
      # Frigate NVR metrics (via prometheus-frigate-exporter)
      {
        job_name = "frigate";
        static_configs = [
          {
            targets = [ "ser8.local:9710" ];
          }
        ];
        scrape_interval = "30s";
      }
      # Caddy reverse proxy metrics (admin API)
      {
        job_name = "caddy";
        static_configs = [
          {
            targets = [ "localhost:2019" ];
          }
        ];
        scrape_interval = "15s";
      }
      # systemd unit metrics from all hosts (state, restarts, network I/O per unit)
      {
        job_name = "systemd";
        static_configs = [
          {
            targets = [
              "ser8.local:9558"
              "firebat.local:9558"
              "pi4.local:9558"
            ];
          }
        ];
        scrape_interval = "30s";
      }
      # process-exporter for per-service CPU/memory/IO metrics
      {
        job_name = "process";
        static_configs = [
          {
            targets = [
              "ser8.local:9256"
              "firebat.local:9256"
              "pi4.local:9256"
            ];
          }
        ];
        scrape_interval = "15s";
      }
      # Jellyfin metrics (via jellyfin-exporter)
      {
        job_name = "jellyfin";
        static_configs = [
          {
            targets = [ "ser8.local:9711" ];
          }
        ];
        scrape_interval = "30s";
      }
      # Exportarr metrics for arr stack
      {
        job_name = "exportarr";
        static_configs = [
          {
            targets = [
              "ser8.local:9707" # Sonarr
              "ser8.local:9708" # Radarr
              "ser8.local:9709" # Prowlarr
            ];
          }
        ];
        scrape_interval = "60s";
      }
      # AdGuard Home DNS metrics
      {
        job_name = "adguard";
        static_configs = [
          {
            targets = [ "pi4.local:9618" ];
          }
        ];
        scrape_interval = "30s";
      }
      # Blackbox HTTP probes -- check service availability via direct HTTP ports
      {
        job_name = "blackbox-http";
        metrics_path = "/probe";
        params = {
          module = [ "http_2xx" ];
        };
        static_configs = [
          {
            targets = [
              "http://192.168.68.65:8096" # Jellyfin (ser8)
              "http://192.168.68.65:8989" # Sonarr (ser8)
              "http://192.168.68.65:7878" # Radarr (ser8)
              "http://192.168.68.65:9696" # Prowlarr (ser8)
              "http://192.168.68.65:8085" # SABnzbd (ser8)
              "http://192.168.68.65:6789" # NZBGet (ser8)
              "http://192.168.68.65:80" # Frigate via nginx (ser8)
              "http://192.168.68.65:8123" # Home Assistant (ser8)
            ];
          }
        ];
        scrape_interval = "60s";
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
      # Blackbox ICMP probes -- check host reachability via ping
      {
        job_name = "blackbox-icmp";
        metrics_path = "/probe";
        params = {
          module = [ "icmp_ping" ];
        };
        static_configs = [
          {
            targets = [
              "192.168.68.65" # ser8
              "192.168.68.63" # firebat
              "192.168.68.56" # pi4
            ];
          }
        ];
        scrape_interval = "60s";
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
      # Blackbox TLS probes -- check certificate expiry on Tailscale URLs
      {
        job_name = "blackbox-tls";
        metrics_path = "/probe";
        params = {
          module = [ "tls_connect" ];
        };
        static_configs = [
          {
            targets = [
              "https://jellyfin.shad-bangus.ts.net"
              "https://sonarr.shad-bangus.ts.net"
              "https://radarr.shad-bangus.ts.net"
              "https://bazarr.shad-bangus.ts.net"
              "https://prowlarr.shad-bangus.ts.net"
              "https://sabnzbd.shad-bangus.ts.net"
              "https://nzbget.shad-bangus.ts.net"
              "https://frigate.shad-bangus.ts.net"
              "https://hass.shad-bangus.ts.net"
              "https://grafana.shad-bangus.ts.net"
              "https://prom.shad-bangus.ts.net"
            ];
          }
        ];
        scrape_interval = "300s";
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
    ];

    # Retention and admin API
    extraFlags = [
      "--storage.tsdb.retention.time=30d"
      "--storage.tsdb.retention.size=10GB"
      "--web.enable-admin-api" # Enable admin API for series deletion
    ];

    # Rules for alerting
    ruleFiles = [
      (pkgs.writeText "homelab-rules.yml" ''
        groups:
          - name: homelab
            rules:
              - alert: HostDown
                expr: up == 0
                for: 5m
                labels:
                  severity: critical
                annotations:
                  summary: "Host {{ $labels.instance }} is down"

              - alert: HighDiskUsageWarning
                expr: (node_filesystem_avail_bytes{fstype!~"tmpfs|overlay|squashfs|devtmpfs|fuse.mergerfs",mountpoint!~"/boot.*|/run.*|/sys.*|/proc.*|/dev.*"} / node_filesystem_size_bytes) * 100 < 20
                for: 5m
                labels:
                  severity: warning
                annotations:
                  summary: "Disk usage above 80% on {{ $labels.instance }} mount {{ $labels.mountpoint }}"

              - alert: HighDiskUsageCritical
                expr: (node_filesystem_avail_bytes{fstype!~"tmpfs|overlay|squashfs|devtmpfs|fuse.mergerfs",mountpoint!~"/boot.*|/run.*|/sys.*|/proc.*|/dev.*"} / node_filesystem_size_bytes) * 100 < 10
                for: 5m
                labels:
                  severity: critical
                annotations:
                  summary: "Disk usage above 90% on {{ $labels.instance }} mount {{ $labels.mountpoint }}"

              - alert: HighMemoryUsage
                expr: (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) * 100 < 10
                for: 5m
                labels:
                  severity: warning
                annotations:
                  summary: "Memory usage is above 90% on {{ $labels.instance }}"

              - alert: ZFSPoolUnhealthy
                expr: node_zfs_zpool_health_state{state!="online"} > 0
                for: 5m
                labels:
                  severity: critical
                annotations:
                  summary: "ZFS pool {{ $labels.pool }} is not healthy on {{ $labels.instance }}"

              - alert: HighCPUTemperature
                expr: node_hwmon_temp_celsius > 80
                for: 5m
                labels:
                  severity: warning
                annotations:
                  summary: "CPU temperature is above 80°C on {{ $labels.instance }}"

              - alert: CameraStorageHigh
                expr: (node_filesystem_avail_bytes{mountpoint="/mnt/cameras"} / node_filesystem_size_bytes{mountpoint="/mnt/cameras"}) * 100 < 20
                for: 5m
                labels:
                  severity: warning
                annotations:
                  summary: "Camera storage is above 80% full"

              - alert: HighCPUSustained
                expr: 100 - (avg by(instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 90
                for: 5m
                labels:
                  severity: warning
                annotations:
                  summary: "CPU usage above 90% sustained for 5+ minutes on {{ $labels.instance }}"

              # The three rules below deliberately do NOT follow the shape of
              # every rule above them, and copying a neighbour here would
              # produce a rule that cannot fire in the case it was written for.
              #
              # Each of these watches a nightly batch job through a timestamp
              # the job itself writes. The interesting failure is not a job that
              # runs and reports a stale time -- that one also mails on failure.
              # It is a job that stops running and says nothing. When that
              # happens the series is not stale, it is gone: the job never wrote
              # it, or the host was rebuilt, or the writer and the exporter
              # disagree about the directory.
              #
              # A bare "time() - metric > threshold" evaluates over an empty
              # vector when the series is absent and yields nothing at all, so
              # it stays silent through exactly the outage it exists to catch.
              # Hence each expression is a disjunction: an age arm over whatever
              # host exports the series, and an absence arm scoped to the host
              # expected to export it. The absence arm carries the instance
              # matcher so absent() synthesises that label and the summary can
              # still name a host -- an unscoped absent() returns a series with
              # no labels and the alert arrives blaming nobody.
              #
              # 26h is the nightly interval plus two hours of margin for a long
              # replication run or a catch-up after an outage.

              - alert: BackupSnapshotStale
                expr: time() - backup_last_snapshot_timestamp_seconds > (26 * 3600) or absent(backup_last_snapshot_timestamp_seconds{instance="ser8.local:9100"})
                for: 5m
                labels:
                  severity: critical
                annotations:
                  summary: "No fresh persist snapshot on {{ $labels.instance }} in over 26 hours, or the snapshot job has stopped reporting entirely"

              - alert: BackupReplicaStale
                expr: time() - backup_last_replica_timestamp_seconds > (26 * 3600) or absent(backup_last_replica_timestamp_seconds{instance="ser8.local:9100"})
                for: 5m
                labels:
                  severity: critical
                annotations:
                  summary: "No fresh replica snapshot on {{ $labels.instance }} in over 26 hours, or replication has stopped reporting entirely"

              - alert: BackupVerifyStale
                expr: time() - backup_last_verify_timestamp_seconds > (26 * 3600) or absent(backup_last_verify_timestamp_seconds{instance="ser8.local:9100"})
                for: 5m
                labels:
                  severity: critical
                annotations:
                  summary: "No passing backup verification on {{ $labels.instance }} in over 26 hours, or the verification has stopped reporting entirely"
      '')
    ];
  };

  # Open firewall port for Prometheus
  networking.firewall.allowedTCPPorts = [ 9090 ];
}
