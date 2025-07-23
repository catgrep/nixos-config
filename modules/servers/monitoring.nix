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
    ] ++ lib.optional (config.boot.supportedFilesystems.zfs or false) "zfs";
    openFirewall = true;
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
