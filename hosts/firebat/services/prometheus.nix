{ config, lib, pkgs, ... }:

{
  services.prometheus = {
    enable = true;
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
            "beelink.local:9100"
            "firebat.local:9100"
            "pi4.local:9100"
          ];
        }];
      }
      {
        job_name = "jellyfin";
        static_configs = [{
          targets = [ "beelink.local:8096" ];
        }];
      }
    ];

    # Retention
    extraFlags = [
      "--storage.tsdb.retention.time=30d"
      "--storage.tsdb.retention.size=10GB"
    ];
  };

  # Node exporter for this host
  services.prometheus.exporters.node = {
    enable = true;
    port = 9100;
    enabledCollectors = [
      "systemd"
      "processes"
    ];
  };
}
