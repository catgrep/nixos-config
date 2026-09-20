# SPDX-License-Identifier: GPL-3.0-or-later

{
  config,
  lib,
  pkgs,
  ...
}:

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
    # Textfile-directory flags live in service-monitoring.nix, which owns
    # both the collection scope and the generated policy file that gets
    # published into one of those directories.
  };

  # systemd exporter for unit state, restart counts, and network traffic per service
  # Note: systemd-exporter does NOT provide CPU/memory metrics - use process-exporter for that
  # Unit-collection scope (extraFlags) lives in service-monitoring.nix.
  services.prometheus.exporters.systemd = {
    enable = lib.mkDefault true;
    port = 9558;
    openFirewall = true;
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
