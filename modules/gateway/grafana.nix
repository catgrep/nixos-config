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
    services = ../../dashboards/services.json; # Per-service CPU/memory/IO from process-exporter
    uptime = ../../dashboards/uptime.json; # Service uptime, host reachability, TLS cert expiry
    alert-history = ../../dashboards/alert-history.json; # Hand-written: 30d ALERTS state timeline + active alerts
  };
in
{
  # SOPS secret for Grafana admin password
  sops.secrets.grafana_admin_password = {
    owner = "grafana";
    group = "grafana";
    mode = "0400";
  };

  # SOPS secret for Grafana secret_key. 26.05 removed the option's default; this
  # pins the LEGACY upstream constant so existing grafana.db ciphertext stays
  # decryptable. Compatibility pin, not a security decision.
  sops.secrets.grafana_secret_key = {
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
        secret_key = "$__file{${config.sops.secrets.grafana_secret_key.path}}";
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
            uid = "prometheus"; # Stable UID so dashboard JSON can reference it by uid
            isDefault = true;
          }
          # Read-only window onto the external Alertmanager so Grafana's
          # Alerting page can list currently active alerts and silences.
          # History is not here -- Alertmanager keeps none; the Alert History
          # dashboard reads the ALERTS series from Prometheus for that.
          {
            name = "Alertmanager";
            type = "alertmanager";
            access = "proxy";
            url = "http://localhost:9093";
            uid = "alertmanager";
            jsonData = {
              implementation = "prometheus";
              handleGrafanaManagedAlerts = false;
            };
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

      # Grafana carries no alerting of its own. Rule evaluation and delivery
      # live in prometheus.nix and alertmanager.nix; Grafana is dashboards.
      #
      # Grafana does not remove file-provisioned objects when they disappear
      # from provisioning files, so keeping alerting out of Grafana takes the
      # explicit deletions below rather than mere absence. The uids name every
      # alerting object this module ever provisioned; the deletions are
      # idempotent and stay so none of them can survive on a host provisioned
      # from an older configuration.
      alerting.contactPoints.settings = {
        apiVersion = 1;
        deleteContactPoints = [
          {
            orgId = 1;
            uid = "email-alerts-uid";
          }
        ];
      };

      alerting.policies.settings = {
        apiVersion = 1;
        resetPolicies = [ 1 ];
      };

      alerting.rules.settings = {
        apiVersion = 1;
        deleteRules =
          map
            (uid: {
              orgId = 1;
              inherit uid;
            })
            [
              "high_disk_usage"
              "host_down"
              "disk_usage_warning"
              "disk_usage_critical"
              "high_memory_usage"
              "zfs_pool_unhealthy"
              "high_cpu_temp"
              "camera_storage_high"
              "high_cpu_usage"
              "service_down"
              "host_unreachable"
              "tls_cert_expiring"
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
    "L+ /var/lib/grafana/dashboards/services.json - - - - ${dashboards.services}"
    "L+ /var/lib/grafana/dashboards/uptime.json - - - - ${dashboards.uptime}"
    "L+ /var/lib/grafana/dashboards/alert-history.json - - - - ${dashboards.alert-history}"
  ];

  # Automatically restart Grafana when dashboard files change
  # This ensures provisioned dashboards are reloaded without manual intervention
  systemd.services.grafana.restartTriggers = builtins.attrValues dashboards;

  # Open firewall port for Grafana
  networking.firewall.allowedTCPPorts = [ 3000 ];
}
