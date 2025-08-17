# SPDX-License-Identifier: GPL-3.0-or-later

{
  config,
  lib,
  pkgs,
  ...
}:

{
  config = lib.mkIf config.nordvpn.enable {
    # Create dedicated wgnord system user
    users.users.wgnord = {
      isSystemUser = true;
      group = "wgnord";
      home = "/var/lib/wgnord";
      description = "NordVPN WireGuard service";
    };

    users.groups.wgnord = { };

    # Ensure wgnord state directory exists
    systemd.tmpfiles.rules = [
      "d /var/lib/wgnord 0755 wgnord wgnord -"
    ];

    # Simple wgnord service with isolated network namespace
    systemd.services.wgnord = {
      description = "NordVPN WireGuard connection";
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        # Create isolated network namespace for VPN
        PrivateNetwork = true;

        ExecStart = pkgs.writeShellScript "wgnord-start" ''
          set -e
          # Login to NordVPN
          "${pkgs.wgnord}/bin/wgnord" login "$(cat "${config.nordvpn.accessTokenFile}")"
          echo "Successfully logged into NordVPN account"

          # Connect to US server
          "${pkgs.wgnord}/bin/wgnord" connect us
          echo "Connected to NordVPN"

          # Test connection
          timeout 10 ping -c 1 8.8.8.8 >/dev/null
          echo "VPN connection verified"
        '';

        ExecStop = pkgs.writeShellScript "wgnord-stop" ''
          "${pkgs.wgnord}/bin/wgnord" disconnect || true
        '';

        # Restart policy
        Restart = "on-failure";
        RestartSec = "30s";
      };
    };

    # Health monitoring for VPN connection
    systemd.services.wgnord-monitor = {
      description = "Monitor NordVPN connection health";
      after = [ "wgnord.service" ];
      requires = [ "wgnord.service" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "simple";
        JoinsNamespaceOf = "wgnord.service";
        Restart = "always";
        RestartSec = "60s";

        ExecStart = pkgs.writeShellScript "wgnord-monitor" ''
          while true; do
            if ! timeout 10 ping -c 1 8.8.8.8 >/dev/null 2>&1; then
              echo "VPN connection lost, restarting..."
              systemctl restart wgnord.service
              sleep 30
            fi
            sleep 60
          done
        '';
      };
    };

    # Utility script to check VPN status
    environment.systemPackages = [
      (pkgs.writeShellScriptBin "nordvpn-status" ''
        echo "=== NordVPN Status ==="
        systemctl is-active wgnord.service
        "${pkgs.wgnord}/bin/wgnord" status || echo "wgnord not connected"
      '')
    ];
  };
}
