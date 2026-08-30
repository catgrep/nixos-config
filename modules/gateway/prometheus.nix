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
      # pi4 has been physically disconnected since 2026-06-15. Its targets are
      # commented out rather than deleted so reconnecting it is an uncomment,
      # not an archaeology dig; a listed target for an unplugged host raises a
      # permanent HostDown from every job that scrapes it.
      {
        job_name = "node-exporter";
        static_configs = [
          {
            targets = [
              "ser8.local:9100" # Beelink node exporter
              "firebat.local:9100" # Firebat node exporter
              # "pi4.local:9100" # Pi4 node exporter (host disconnected)
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
              # "pi4.local:9558" # host disconnected
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
              # "pi4.local:9256" # host disconnected
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
      # {
      #   job_name = "adguard";
      #   static_configs = [
      #     {
      #       targets = [ "pi4.local:9618" ]; # host disconnected
      #     }
      #   ];
      #   scrape_interval = "30s";
      # }
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
      # Blackbox HTTP probes for services whose UI requires authentication.
      # Same liveness intent as blackbox-http, but through the module that
      # accepts 401: NZBGet demands credentials on every request, so 401 is
      # what "up" looks like from an unauthenticated prober.
      {
        job_name = "blackbox-http-auth";
        metrics_path = "/probe";
        params = {
          module = [ "http_2xx_401" ];
        };
        static_configs = [
          {
            targets = [
              "http://192.168.68.65:6789" # NZBGet (ser8)
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
              # "192.168.68.56" # pi4 (host disconnected)
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
      # Blackbox TLS probes -- check certificate expiry on Tailscale vhosts.
      # host:port form because the module is a TCP prober: it completes the
      # handshake, records the certificate, and asks nothing of HTTP.
      {
        job_name = "blackbox-tls";
        metrics_path = "/probe";
        params = {
          module = [ "tls_connect" ];
        };
        static_configs = [
          {
            targets = [
              "jellyfin.shad-bangus.ts.net:443"
              "sonarr.shad-bangus.ts.net:443"
              "radarr.shad-bangus.ts.net:443"
              "bazarr.shad-bangus.ts.net:443"
              "prowlarr.shad-bangus.ts.net:443"
              "sabnzbd.shad-bangus.ts.net:443"
              "nzbget.shad-bangus.ts.net:443"
              "frigate.shad-bangus.ts.net:443"
              "hass.shad-bangus.ts.net:443"
              "grafana.shad-bangus.ts.net:443"
              "prom.shad-bangus.ts.net:443"
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
              # 10m rather than 5m: a ser8 deploy restarts its exporters, and
              # the small ones (exportarr among them) take just over five
              # minutes to come back, so a tighter window pages on every
              # deploy. A genuinely dead exporter still alerts inside eleven
              # minutes.
              - alert: HostDown
                expr: up == 0
                for: 10m
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

              # node_zfs_zpool_state is one series per (pool, state) with the
              # active state at 1 -- so matching non-online states above zero
              # is the alert. A wrong metric name here fails silently: the
              # rule evaluates an empty vector and never fires, which is
              # indistinguishable from healthy pools.
              - alert: ZFSPoolUnhealthy
                expr: node_zfs_zpool_state{state!="online"} > 0
                for: 5m
                labels:
                  severity: critical
                annotations:
                  summary: "ZFS pool {{ $labels.zpool }} is {{ $labels.state }} on {{ $labels.instance }}"

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

              # Blackbox probe rules. These watch what a user would experience
              # (an HTTP answer, a ping reply, a valid certificate) rather
              # than what an exporter reports about itself, so they live
              # alongside the exporter rules instead of replacing them.

              - alert: ServiceDown
                expr: probe_success{job=~"blackbox-http|blackbox-http-auth"} == 0
                for: 2m
                labels:
                  severity: critical
                annotations:
                  summary: "Service {{ $labels.instance }} is unreachable"

              - alert: HostUnreachable
                expr: probe_success{job="blackbox-icmp"} == 0
                for: 2m
                labels:
                  severity: critical
                annotations:
                  summary: "Host {{ $labels.instance }} is unreachable via ICMP"

              - alert: TLSCertExpiringSoon
                expr: (probe_ssl_earliest_cert_expiry{job="blackbox-tls"} - time()) / 86400 < 14
                for: 1h
                labels:
                  severity: warning
                annotations:
                  summary: 'TLS certificate for {{ $labels.instance }} expires in {{ printf "%.1f" $value }} days'

              # Expiry above is measured from a metric the probe only writes
              # when its handshake succeeds, so a vhost that stops answering
              # TLS entirely would otherwise vanish from the expiry rule
              # rather than trip it.
              - alert: TLSProbeFailed
                expr: probe_success{job="blackbox-tls"} == 0
                for: 15m
                labels:
                  severity: warning
                annotations:
                  summary: "TLS handshake with {{ $labels.instance }} is failing"

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
