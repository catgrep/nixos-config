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
  };
in
{
  # SOPS secret for Grafana admin password
  sops.secrets.grafana_admin_password = {
    owner = "grafana";
    group = "grafana";
    mode = "0400";
  };

  # SOPS secret for Grafana SMTP password (Gmail App Password)
  sops.secrets.grafana_smtp_password = {
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

      # SMTP configuration for email alert delivery via Gmail
      smtp = {
        enabled = true;
        host = "smtp.gmail.com:587";
        user = "shadbangus@gmail.com";
        password = "$__file{${config.sops.secrets.grafana_smtp_password.path}}";
        from_address = "shadbangus@gmail.com";
        from_name = "Homelab Alerts";
        startTLS_policy = "MandatoryStartTLS";
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
            uid = "prometheus"; # Stable UID for alert rule datasource references
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

      # Alerting: Contact point for email delivery
      alerting.contactPoints.settings = {
        apiVersion = 1;
        contactPoints = [
          {
            orgId = 1;
            name = "email-alerts";
            receivers = [
              {
                uid = "email-alerts-uid";
                type = "email";
                settings = {
                  addresses = "catgrep@sudomail.com";
                  singleEmail = false;
                };
                disableResolveMessage = false;
              }
            ];
          }
        ];
      };

      # Alerting: Notification policy routing severity alerts to email
      alerting.policies.settings = {
        apiVersion = 1;
        policies = [
          {
            orgId = 1;
            receiver = "email-alerts";
            group_by = [
              "grafana_folder"
              "alertname"
            ];
            routes = [
              {
                receiver = "email-alerts";
                object_matchers = [
                  [
                    "severity"
                    "=~"
                    "critical|warning"
                  ]
                ];
              }
            ];
          }
        ];
      };

      # Alerting: Grafana-managed alert rules mirroring existing Prometheus ruleFiles
      # These rules query the Prometheus datasource with the same PromQL expressions.
      # Existing Prometheus ruleFiles are kept as defense-in-depth (visible in Prometheus UI)
      # but cannot deliver notifications without a standalone Alertmanager.
      # Grafana's built-in Alertmanager handles ONLY Grafana-managed rules.
      alerting.rules.settings = {
        apiVersion = 1;
        # Delete rules removed from provisioning (Grafana doesn't auto-delete file-provisioned rules)
        deleteRules = [
          {
            orgId = 1;
            uid = "high_disk_usage"; # Replaced by graduated disk_usage_warning + disk_usage_critical
          }
        ];
        groups = [
          {
            orgId = 1;
            name = "homelab_infrastructure";
            folder = "Alerting";
            interval = "1m";
            rules = [
              # 1. Host Down -- up{job="node-exporter"} == 0 for 5m (critical)
              {
                uid = "host_down";
                title = "Host Down";
                condition = "C";
                data = [
                  {
                    refId = "A";
                    relativeTimeRange = {
                      from = 300;
                      to = 0;
                    };
                    datasourceUid = "prometheus";
                    model = {
                      expr = ''up{job="node-exporter"} == 0'';
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
                      conditions = [
                        {
                          evaluator = {
                            params = [ 1 ];
                            type = "lt";
                          };
                        }
                      ];
                      refId = "C";
                    };
                  }
                ];
                "for" = "5m";
                noDataState = "NoData";
                execErrState = "Alerting";
                labels = {
                  severity = "critical";
                };
                annotations = {
                  summary = "Host {{ $labels.instance }} is down";
                };
                isPaused = false;
              }

              # 2. Disk Usage Warning -- less than 20% free for 5m (warning)
              {
                uid = "disk_usage_warning";
                title = "Disk Usage Warning (>80%)";
                condition = "C";
                data = [
                  {
                    refId = "A";
                    relativeTimeRange = {
                      from = 300;
                      to = 0;
                    };
                    datasourceUid = "prometheus";
                    model = {
                      expr = ''(node_filesystem_avail_bytes{fstype!~"tmpfs|overlay|squashfs|devtmpfs|fuse\\.mergerfs",mountpoint!~"/boot.*|/run.*|/sys.*|/proc.*|/dev.*"} / node_filesystem_size_bytes) * 100'';
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
                      conditions = [
                        {
                          evaluator = {
                            params = [ 20 ];
                            type = "lt";
                          };
                        }
                      ];
                      refId = "C";
                    };
                  }
                ];
                "for" = "5m";
                noDataState = "NoData";
                execErrState = "Alerting";
                labels = {
                  severity = "warning";
                };
                annotations = {
                  summary = "Disk usage above 80% on {{ $labels.instance }} mount {{ $labels.mountpoint }}";
                };
                isPaused = false;
              }

              # 3. Disk Usage Critical -- less than 10% free for 5m (critical)
              {
                uid = "disk_usage_critical";
                title = "Disk Usage Critical (>90%)";
                condition = "C";
                data = [
                  {
                    refId = "A";
                    relativeTimeRange = {
                      from = 300;
                      to = 0;
                    };
                    datasourceUid = "prometheus";
                    model = {
                      expr = ''(node_filesystem_avail_bytes{fstype!~"tmpfs|overlay|squashfs|devtmpfs|fuse\\.mergerfs",mountpoint!~"/boot.*|/run.*|/sys.*|/proc.*|/dev.*"} / node_filesystem_size_bytes) * 100'';
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
                      conditions = [
                        {
                          evaluator = {
                            params = [ 10 ];
                            type = "lt";
                          };
                        }
                      ];
                      refId = "C";
                    };
                  }
                ];
                "for" = "5m";
                noDataState = "NoData";
                execErrState = "Alerting";
                labels = {
                  severity = "critical";
                };
                annotations = {
                  summary = "Disk usage above 90% on {{ $labels.instance }} mount {{ $labels.mountpoint }}";
                };
                isPaused = false;
              }

              # 4. High Memory Usage -- less than 10% available for 5m (warning)
              {
                uid = "high_memory_usage";
                title = "High Memory Usage";
                condition = "C";
                data = [
                  {
                    refId = "A";
                    relativeTimeRange = {
                      from = 300;
                      to = 0;
                    };
                    datasourceUid = "prometheus";
                    model = {
                      expr = "(node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) * 100";
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
                      conditions = [
                        {
                          evaluator = {
                            params = [ 10 ];
                            type = "lt";
                          };
                        }
                      ];
                      refId = "C";
                    };
                  }
                ];
                "for" = "5m";
                noDataState = "NoData";
                execErrState = "Alerting";
                labels = {
                  severity = "warning";
                };
                annotations = {
                  summary = "Memory usage is above 90% on {{ $labels.instance }}";
                };
                isPaused = false;
              }

              # 5. ZFS Pool Unhealthy -- non-online state for 5m (critical)
              {
                uid = "zfs_pool_unhealthy";
                title = "ZFS Pool Unhealthy";
                condition = "C";
                data = [
                  {
                    refId = "A";
                    relativeTimeRange = {
                      from = 300;
                      to = 0;
                    };
                    datasourceUid = "prometheus";
                    model = {
                      expr = ''node_zfs_zpool_health_state{state!="online"}'';
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
                      conditions = [
                        {
                          evaluator = {
                            params = [ 0 ];
                            type = "gt";
                          };
                        }
                      ];
                      refId = "C";
                    };
                  }
                ];
                "for" = "5m";
                noDataState = "NoData";
                execErrState = "Alerting";
                labels = {
                  severity = "critical";
                };
                annotations = {
                  summary = "ZFS pool {{ $labels.pool }} is not healthy on {{ $labels.instance }}";
                };
                isPaused = false;
              }

              # 6. High CPU Temperature -- above 80C for 5m (warning)
              {
                uid = "high_cpu_temp";
                title = "High CPU Temperature";
                condition = "C";
                data = [
                  {
                    refId = "A";
                    relativeTimeRange = {
                      from = 300;
                      to = 0;
                    };
                    datasourceUid = "prometheus";
                    model = {
                      expr = "node_hwmon_temp_celsius";
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
                      conditions = [
                        {
                          evaluator = {
                            params = [ 80 ];
                            type = "gt";
                          };
                        }
                      ];
                      refId = "C";
                    };
                  }
                ];
                "for" = "5m";
                noDataState = "NoData";
                execErrState = "Alerting";
                labels = {
                  severity = "warning";
                };
                annotations = {
                  summary = "CPU temperature is above 80C on {{ $labels.instance }}";
                };
                isPaused = false;
              }

              # 7. Camera Storage High -- less than 20% free for 5m (warning)
              {
                uid = "camera_storage_high";
                title = "Camera Storage High";
                condition = "C";
                data = [
                  {
                    refId = "A";
                    relativeTimeRange = {
                      from = 300;
                      to = 0;
                    };
                    datasourceUid = "prometheus";
                    model = {
                      expr = ''(node_filesystem_avail_bytes{fstype!~"tmpfs|overlay|squashfs|devtmpfs|fuse\\.mergerfs",mountpoint="/mnt/cameras"} / node_filesystem_size_bytes{mountpoint="/mnt/cameras"}) * 100'';
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
                      conditions = [
                        {
                          evaluator = {
                            params = [ 20 ];
                            type = "lt";
                          };
                        }
                      ];
                      refId = "C";
                    };
                  }
                ];
                "for" = "5m";
                noDataState = "NoData";
                execErrState = "Alerting";
                labels = {
                  severity = "warning";
                };
                annotations = {
                  summary = "Camera storage is above 80% full";
                };
                isPaused = false;
              }

              # 8. High CPU Usage -- above 90% sustained for 5m (warning)
              {
                uid = "high_cpu_usage";
                title = "High CPU Usage (>90% sustained)";
                condition = "C";
                data = [
                  {
                    refId = "A";
                    relativeTimeRange = {
                      from = 600;
                      to = 0;
                    };
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
                      conditions = [
                        {
                          evaluator = {
                            params = [ 90 ];
                            type = "gt";
                          };
                        }
                      ];
                      refId = "C";
                    };
                  }
                ];
                "for" = "5m";
                noDataState = "NoData";
                execErrState = "Alerting";
                labels = {
                  severity = "warning";
                };
                annotations = {
                  summary = "CPU usage above 90% sustained for 5+ minutes on {{ $labels.instance }}";
                };
                isPaused = false;
              }
            ];
          }
          {
            orgId = 1;
            name = "homelab_probes";
            folder = "Alerting";
            interval = "1m";
            rules = [
              # 1. Service Down -- probe_success == 0 for 2m (critical)
              {
                uid = "service_down";
                title = "Service Down (Probe Failed)";
                condition = "C";
                data = [
                  {
                    refId = "A";
                    relativeTimeRange = {
                      from = 300;
                      to = 0;
                    };
                    datasourceUid = "prometheus";
                    model = {
                      expr = ''probe_success{job="blackbox-http"}'';
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
                      conditions = [
                        {
                          evaluator = {
                            params = [ 1 ];
                            type = "lt";
                          };
                        }
                      ];
                      refId = "C";
                    };
                  }
                ];
                "for" = "2m";
                noDataState = "NoData";
                execErrState = "Alerting";
                labels = {
                  severity = "critical";
                };
                annotations = {
                  summary = "Service {{ $labels.instance }} is unreachable";
                };
                isPaused = false;
              }

              # 2. Host Unreachable -- ICMP probe failed for 2m (critical)
              {
                uid = "host_unreachable";
                title = "Host Unreachable (ICMP Failed)";
                condition = "C";
                data = [
                  {
                    refId = "A";
                    relativeTimeRange = {
                      from = 300;
                      to = 0;
                    };
                    datasourceUid = "prometheus";
                    model = {
                      expr = ''probe_success{job="blackbox-icmp"}'';
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
                      conditions = [
                        {
                          evaluator = {
                            params = [ 1 ];
                            type = "lt";
                          };
                        }
                      ];
                      refId = "C";
                    };
                  }
                ];
                "for" = "2m";
                noDataState = "NoData";
                execErrState = "Alerting";
                labels = {
                  severity = "critical";
                };
                annotations = {
                  summary = "Host {{ $labels.instance }} is unreachable via ICMP";
                };
                isPaused = false;
              }

              # 3. TLS Certificate Expiring Soon -- less than 14 days until expiry (warning)
              {
                uid = "tls_cert_expiring";
                title = "TLS Certificate Expiring Soon";
                condition = "C";
                data = [
                  {
                    refId = "A";
                    relativeTimeRange = {
                      from = 600;
                      to = 0;
                    };
                    datasourceUid = "prometheus";
                    model = {
                      expr = ''(probe_ssl_earliest_cert_expiry{job="blackbox-tls"} - time()) / 86400'';
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
                      conditions = [
                        {
                          evaluator = {
                            params = [ 14 ];
                            type = "lt";
                          };
                        }
                      ];
                      refId = "C";
                    };
                  }
                ];
                "for" = "1h";
                noDataState = "NoData";
                execErrState = "Alerting";
                labels = {
                  severity = "warning";
                };
                annotations = {
                  summary = "TLS certificate for {{ $labels.instance }} expires in {{ $value }} days";
                };
                isPaused = false;
              }
            ];
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
    "L+ /var/lib/grafana/dashboards/services.json - - - - ${dashboards.services}"
    "L+ /var/lib/grafana/dashboards/uptime.json - - - - ${dashboards.uptime}"
  ];

  # Automatically restart Grafana when dashboard files change
  # This ensures provisioned dashboards are reloaded without manual intervention
  systemd.services.grafana.restartTriggers = builtins.attrValues dashboards;

  # Open firewall port for Grafana
  networking.firewall.allowedTCPPorts = [ 3000 ];
}
