{ config, lib, pkgs, inputs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    # Import the gateway services module
    ../modules/gateway
    # Import server-specific configurations
    ../modules/servers
  ];

  # Host identification
  networking = {
    hostName = "firebat";
    hostId = "39304e086daf8f14"; # Generate with: head -c 8 /dev/urandom | od -A none -t x8
  };

  # Gateway networking configuration
  systemd.network = {
    enable = true;
    networks."10-lan" = {
      matchConfig.Name = "enp1s0"; # Update with your interface name
      networkConfig = {
        DHCP = "yes";
        IPForward = true;
      };
      linkConfig.RequiredForOnline = "routable";
    };
  };

  # Enable IP forwarding for gateway functionality
  boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = 1;
    "net.ipv6.conf.all.forwarding" = 1;
  };

  # Gateway services are enabled by default from the module
  # Override or configure additional settings here if needed
  services = {
    # Traefik, Prometheus, and Grafana are enabled by default
    # Configure specific overrides here
  };

  # Additional firewall rules for gateway
  networking.firewall = {
    # Allow traffic forwarding
    extraCommands = ''
      iptables -A FORWARD -j ACCEPT
    '';
  };

  # Gateway-specific packages
  environment.systemPackages = with pkgs; [
    # Network tools
    iptables
    nftables
    tcpdump
    wireshark

    # Additional monitoring tools
    bandwhich
  ];

  # System state version
  system.stateVersion = "24.11";
}
