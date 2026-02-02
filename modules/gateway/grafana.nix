# SPDX-License-Identifier: GPL-3.0-or-later

{
  config,
  lib,
  pkgs,
  ...
}:

let
  # Use local dashboard files from dashboards/ directory
  # Dashboards are pre-downloaded and have ${DS_*} variables already replaced with "Prometheus"
  # This allows easy inspection, version control, and customization
  #
  # Dashboard sources:
  # - node-exporter: https://grafana.com/grafana/dashboards/1860 (rev 37)
  # - zfs: https://grafana.com/grafana/dashboards/7845 (rev 4)
  # - prometheus: https://grafana.com/grafana/dashboards/3662 (rev 2)
  # - frigate: https://grafana.com/grafana/dashboards/24165 (rev 1)
  # - jellyfin: https://github.com/rebelcore/jellyfin_grafana
  # - sonarr: https://grafana.com/grafana/dashboards/12530 (rev 1)
  # - radarr: https://grafana.com/grafana/dashboards/12896 (rev 1)
  # - systemd: https://grafana.com/grafana/dashboards/1617 (rev 1)
  # - adguard: https://grafana.com/grafana/dashboards/13330 (rev 3)
  # - caddy: https://grafana.com/grafana/dashboards/22870 (rev 3)
  dashboards = {
    node-exporter = ../../dashboards/node-exporter.json;
    zfs = ../../dashboards/zfs.json;
    prometheus = ../../dashboards/prometheus.json;
    frigate = ../../dashboards/frigate.json;
    jellyfin = ../../dashboards/jellyfin.json;
    sonarr = ../../dashboards/sonarr.json;
    radarr = ../../dashboards/radarr.json;
    systemd = ../../dashboards/systemd.json;
    adguard = ../../dashboards/adguard.json;
    caddy = ../../dashboards/caddy.json;
  };
in
{
  # SOPS secret for Grafana admin password
  sops.secrets.grafana_admin_password = {
    owner = "grafana";
    group = "grafana";
    mode = "0400";
  };

  services.grafana = {
    enable = lib.mkDefault true;
    settings = {
      server = {
        http_addr = "0.0.0.0";
        http_port = 3000;
        domain = "grafana.homelab";
      };

      # Secure admin credentials via SOPS
      security = {
        admin_user = "admin";
        admin_password = "$__file{${config.sops.secrets.grafana_admin_password.path}}";
      };

      # Anonymous access for viewing dashboards
      "auth.anonymous" = {
        enabled = true;
        org_name = "Main Org.";
        org_role = "Viewer";
      };
    };

    provision = {
      enable = true;
      datasources.settings = {
        apiVersion = 1;
        datasources = [
          {
            name = "Prometheus";
            type = "prometheus";
            access = "proxy";
            url = "http://localhost:9090";
            isDefault = true;
          }
        ];
      };

      dashboards.settings = {
        apiVersion = 1;
        providers = [
          {
            name = "default";
            orgId = 1;
            folder = "";
            type = "file";
            disableDeletion = false;
            updateIntervalSeconds = 10;
            allowUiUpdates = true;
            options = {
              path = "/var/lib/grafana/dashboards";
            };
          }
        ];
      };
    };
  };

  # Create directory and symlink dashboards
  systemd.tmpfiles.rules = [
    "d /var/lib/grafana/dashboards 0755 grafana grafana -"
    "L+ /var/lib/grafana/dashboards/node-exporter.json - - - - ${dashboards.node-exporter}"
    "L+ /var/lib/grafana/dashboards/zfs.json - - - - ${dashboards.zfs}"
    "L+ /var/lib/grafana/dashboards/prometheus.json - - - - ${dashboards.prometheus}"
    "L+ /var/lib/grafana/dashboards/frigate.json - - - - ${dashboards.frigate}"
    "L+ /var/lib/grafana/dashboards/jellyfin.json - - - - ${dashboards.jellyfin}"
    "L+ /var/lib/grafana/dashboards/sonarr.json - - - - ${dashboards.sonarr}"
    "L+ /var/lib/grafana/dashboards/radarr.json - - - - ${dashboards.radarr}"
    "L+ /var/lib/grafana/dashboards/systemd.json - - - - ${dashboards.systemd}"
    "L+ /var/lib/grafana/dashboards/adguard.json - - - - ${dashboards.adguard}"
    "L+ /var/lib/grafana/dashboards/caddy.json - - - - ${dashboards.caddy}"
  ];

  # Open firewall port for Grafana
  networking.firewall.allowedTCPPorts = [ 3000 ];
}
