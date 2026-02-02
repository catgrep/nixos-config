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
    "qbittorrent-nox.service"
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
  };

  # systemd exporter for per-service CPU/memory/IO metrics via cgroups
  services.prometheus.exporters.systemd = {
    enable = lib.mkDefault true;
    port = 9558;
    openFirewall = true;
    extraFlags = [
      "--systemd.collector.unit-include=${monitoredUnits}"
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
