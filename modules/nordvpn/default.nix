# SPDX-License-Identifier: GPL-3.0-or-later

{
  config,
  lib,
  pkgs,
  ...
}:

{
  imports = [
    ./service.nix
  ];

  options.nordvpn = {
    enable = lib.mkEnableOption "NordVPN WireGuard VPN";

    accessTokenFile = lib.mkOption {
      type = lib.types.path;
      description = "Path to file containing NordVPN access token";
    };
  };

  config = lib.mkIf config.nordvpn.enable {
    # Ensure required packages are available
    environment.systemPackages = with pkgs; [
      wireguard-tools
      iproute2
      iptables
      openresolv
      jq
      curl
      wgnord
    ];

    # Enable IP forwarding for network namespace isolation
    boot.kernel.sysctl = {
      "net.ipv4.ip_forward" = 1;
      "net.ipv6.conf.all.forwarding" = 1;
    };
  };
}
