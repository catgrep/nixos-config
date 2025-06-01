{ config, lib, pkgs, ... }:

{
  # Node exporter for monitoring
  services.prometheus.exporters.node = {
    enable = true;
    port = 9100;
    enabledCollectors = [
      "systemd"
      "processes"
      "filesystem"
      "cpu"
      "memory"
      "network"
    ];
  };

  # Custom script to monitor Pi temperature
  systemd.services.pi-temp-monitor = {
    description = "Raspberry Pi Temperature Monitor";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.writeShellScript "pi-temp-check" ''
        temp=$(cat /sys/class/thermal/thermal_zone0/temp)
        temp_c=$((temp / 1000))

        if [ $temp_c -gt 70 ]; then
          echo "Warning: Pi temperature is $temp_c°C" | ${pkgs.systemd}/bin/systemd-cat -t pi-temp
        fi
      ''}";
    };
  };

  systemd.timers.pi-temp-monitor = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "5min";
      OnUnitActiveSec = "5min";
    };
  };
}
