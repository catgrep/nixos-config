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

    vethBridge = {
      hostIp = lib.mkOption {
        type = lib.types.str;
        default = "192.168.100.1";
        description = "IP address for the host side of the veth bridge";
      };

      vpnIp = lib.mkOption {
        type = lib.types.str;
        default = "192.168.100.2";
        description = "IP address for the VPN namespace side of the veth bridge";
      };

      subnet = lib.mkOption {
        type = lib.types.str;
        default = "192.168.100.0/24";
        description = "Subnet for the veth bridge network";
      };
    };

    localNetworkAccess = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = "192.168.68.0/24";
      example = "192.168.68.0/24";
      description = ''
        Local network subnet that should be accessible from the VPN namespace.
        This is typically your LAN subnet. If null, no local network access is configured.
      '';
    };

    dnsServers = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "103.86.96.100"
        "103.86.99.100"
      ];
      description = "DNS servers to use in the VPN namespace";
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
