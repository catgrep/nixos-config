{ config, lib, pkgs, ... }:

{
  services.grafana = {
    enable = lib.mkDefault true;
    settings = {
      server = {
        http_addr = "0.0.0.0";
        http_port = 3000;
        domain = "grafana.homelab.local";
      };

      # Default admin credentials (change after first login)
      security = {
        admin_user = "admin";
        admin_password = "admin";
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
        datasources = [{
          name = "Prometheus";
          type = "prometheus";
          access = "proxy";
          url = "http://localhost:9090";
          isDefault = true;
        }];
      };

      dashboards.settings = {
        apiVersion = 1;
        providers = [{
          name = "default";
          orgId = 1;
          folder = "";
          type = "file";
          disableDeletion = false;
          updateIntervalSeconds = 10;
          allowUiUpdates = false;
          options = {
            path = "/var/lib/grafana/dashboards";
          };
        }];
      };
    };
  };

  # Create directory for custom dashboards
  systemd.tmpfiles.rules = [
    "d /var/lib/grafana/dashboards 0755 grafana grafana -"
  ];

  # Open firewall port for Grafana
  networking.firewall.allowedTCPPorts = [ 3000 ];
}
