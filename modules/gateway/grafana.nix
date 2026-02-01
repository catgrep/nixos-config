# SPDX-License-Identifier: GPL-3.0-or-later

{
  config,
  lib,
  pkgs,
  ...
}:

let
  # Fetch dashboards from grafana.com at build time
  fetchedDashboards = {
    node-exporter = pkgs.fetchurl {
      url = "https://grafana.com/api/dashboards/1860/revisions/37/download";
      hash = "sha256-1DE1aaanRHHeCOMWDGdOS1wBXxOF84UXAjJzT5Ek6mM=";
    };
    zfs = pkgs.fetchurl {
      url = "https://grafana.com/api/dashboards/7845/revisions/4/download";
      hash = "sha256-zJD1o7oQY711mZqNUKjqKBixN88lAjXDAiWCpUEut9c=";
    };
    prometheus = pkgs.fetchurl {
      url = "https://grafana.com/api/dashboards/3662/revisions/2/download";
      hash = "sha256-+nsi8/dYNvGVGV+ftfO1gSAQbO5GpZwW480T5mHMM4Q=";
    };
  };

  # Replace ${DS_*} datasource template variables with our Prometheus datasource
  # Grafana.com dashboards use these placeholders which aren't resolved during provisioning
  # See: https://github.com/grafana/grafana/issues/10786
  processDashboard =
    name: src:
    pkgs.runCommand "dashboard-${name}.json" { } ''
      sed -E 's/\$\{DS_[A-Z_]+\}/Prometheus/g' ${src} > $out
    '';

  dashboards = builtins.mapAttrs processDashboard fetchedDashboards;
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
  ];

  # Open firewall port for Grafana
  networking.firewall.allowedTCPPorts = [ 3000 ];
}
