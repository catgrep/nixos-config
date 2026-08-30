# SPDX-License-Identifier: GPL-3.0-or-later

{
  config,
  lib,
  pkgs,
  ...
}:

let
  # systemd units to monitor for per-service resource metrics
  # This list covers media services on ser8, gateway services on firebat, and DNS on pi4
  monitoredUnits = lib.concatStringsSep "|" [
    "jellyfin.service"
    "sonarr.service"
    "radarr.service"
    "prowlarr.service"
    "sabnzbd.service"
    "nzbget.service"
    "frigate.service"
    "home-assistant.service"
    "caddy.service"
    "grafana.service"
    "prometheus.service"
    "adguardhome.service"
    "nginx.service"
    "mosquitto.service"
  ];
in
{
  # Enable node exporter by default on all servers
  services.prometheus.exporters.node = {
    enable = lib.mkDefault true;
    port = 9100;
    enabledCollectors = [
      "cpu"
      "meminfo"
      "filesystem"
      "diskstats"
      "loadavg"
      "netdev"
      "systemd"
      "processes"
    ]
    ++ lib.optional (config.boot.supportedFilesystems.zfs or false) "zfs";
    openFirewall = true;

    # The textfile collector is one of the exporter's own defaults and is
    # already scraping on every host, so it is deliberately absent from the
    # list above. Only the directory it reads was missing.
    #
    # Two properties of this path are load-bearing and neither is visible from
    # here. It sits under the persisted tree because a host with a boot-time
    # rollback would otherwise erase the metrics on every reboot, which reads
    # downstream as "the batch job has not run since the reboot". And it sits
    # outside any home directory because this exporter runs with home
    # directories hidden, where it would simply find nothing and report no
    # error. The writer declares the same path; the two must not drift, because
    # a mismatch produces no metrics and no error anywhere.
    #
    # Harmless on a host that never writes there: the collector finds an empty
    # directory and exports nothing.
    extraFlags = lib.mkDefault [
      "--collector.textfile.directory=/persist/var/lib/node-exporter-textfile"
    ];
  };

  # systemd exporter for unit state, restart counts, and network traffic per service
  # Note: systemd-exporter does NOT provide CPU/memory metrics - use process-exporter for that
  services.prometheus.exporters.systemd = {
    enable = lib.mkDefault true;
    port = 9558;
    openFirewall = true;
    extraFlags = [
      "--systemd.collector.unit-include=${monitoredUnits}"
    ];
  };

  # process-exporter for per-service CPU/memory/IO metrics
  # This provides the granular resource usage that systemd-exporter doesn't
  # Metrics: namedprocess_namegroup_cpu_seconds_total, namedprocess_namegroup_memory_bytes, etc.
  services.prometheus.exporters.process = {
    enable = lib.mkDefault true;
    port = 9256;
    openFirewall = true;
    settings.process_names = [
      # Media services
      {
        name = "jellyfin";
        comm = [ "jellyfin" ];
      }
      {
        name = "sonarr";
        comm = [ "Sonarr" ];
      }
      {
        name = "radarr";
        comm = [ "Radarr" ];
      }
      {
        name = "prowlarr";
        comm = [ "Prowlarr" ];
      }
      {
        name = "sabnzbd";
        comm = [
          "SABnzbd.py"
          "sabnzbd"
        ];
      }
      {
        name = "nzbget";
        comm = [ "nzbget" ];
      }
      # Automation
      {
        name = "frigate";
        comm = [ "python3" ];
        cmdline = [ ".*frigate.*" ];
      }
      {
        name = "home-assistant";
        comm = [
          "hass"
          "python3"
        ];
        cmdline = [ ".*homeassistant.*" ];
      }
      {
        name = "mosquitto";
        comm = [ "mosquitto" ];
      }
      # Gateway services
      {
        name = "caddy";
        comm = [ "caddy" ];
      }
      {
        name = "grafana";
        comm = [
          "grafana"
          "grafana-server"
        ];
      }
      {
        name = "prometheus";
        comm = [ "prometheus" ];
      }
      # DNS
      {
        name = "adguardhome";
        comm = [ "AdGuardHome" ];
      }
      # Catch-all for other interesting processes
      {
        name = "{{.Comm}}";
        cmdline = [ ".+" ];
      }
    ];
  };

  # Log rotation
  services.logrotate = {
    enable = true;
    settings = {
      global = {
        rotate = 7;
        daily = true;
        compress = true;
        delaycompress = true;
        missingok = true;
        notifempty = true;
      };
    };
  };

  # Journal configuration
  services.journald.extraConfig = ''
    SystemMaxUse=1G
    SystemMaxFileSize=100M
    SystemMaxFiles=10
  '';

  # Common monitoring packages
  environment.systemPackages = with pkgs; [
    htop
    iotop
    nethogs
    sysstat
  ];

  # Open firewall for node exporter
  networking.firewall.allowedTCPPorts = [ 9100 ];
}
