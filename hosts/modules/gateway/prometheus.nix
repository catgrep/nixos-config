{ config, lib, pkgs, ... }:

{
  services.prometheus = {
    enable = lib.mkDefault true;
    port = 9090;

    # Scrape configs for monitoring homelab hosts
    scrapeConfigs = [
      {
        job_name = "prometheus";
        static_configs = [{
          targets = [ "localhost:9090" ];
        }];
      }
      {
        job_name = "node-exporter";
        static_configs = [{
          targets = [
            "beelink.local:9100"   # Beelink node exporter
            "firebat.local:9100"   # Firebat node exporter
            "pi4.local:9100"       # Pi4 node exporter
          ];
        }];
        scrape_interval = "15s";
        metrics_path = "/metrics";
      }
      {
        job_name = "zfs-exporter";
        static_configs = [{
          targets = [
            "beelink.local:9134"   # ZFS metrics from Beelink
          ];
        }];
        scrape_interval = "30s";
      }
      {
        job_name = "adguard";
        static_configs = [{
          targets = [
            "pi4.local:80"       # AdGuard Home built-in metrics
          ];
        }];
        scrape_interval = "30s";
        metrics_path = "/control/stats";
        # Note: You may need to configure authentication for AdGuard API
        # basic_auth = {
        #   username = "admin";
        #   password_file = "/run/secrets/adguard-prometheus-password";
        # };
      }
      {
        job_name = "jellyfin";
        static_configs = [{
          targets = [ "beelink.local:8096" ];
        }];
        scrape_interval = "60s";
        metrics_path = "/health";
      }
    ];

    # Retention
    extraFlags = [
      "--storage.tsdb.retention.time=30d"
      "--storage.tsdb.retention.size=10GB"
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

              - alert: HighDiskUsage
                expr: (node_filesystem_avail_bytes / node_filesystem_size_bytes) * 100 < 10
                for: 5m
                labels:
                  severity: warning
                annotations:
                  summary: "Disk usage is above 90% on {{ $labels.instance }}"

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
      '')
    ];
  };

  # Open firewall port for Prometheus
  networking.firewall.allowedTCPPorts = [ 9090 ];
}
