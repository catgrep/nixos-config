{ config, lib, pkgs, inputs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./services
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

  # Open ports for gateway services
  networking.firewall = {
    allowedTCPPorts = [
      80    # HTTP
      443   # HTTPS
      8080  # Traefik admin
      9090  # Prometheus
      3000  # Grafana
    ];

    # Allow traffic forwarding
    extraCommands = ''
      iptables -A FORWARD -j ACCEPT
    '';
  };

  # Gateway and monitoring packages
  environment.systemPackages = with pkgs; [
    # Network tools
    iptables
    nftables
    tcpdump
    wireshark

    # Monitoring tools
    prometheus
    grafana

    # Load balancer
    traefik
  ];

  # System state version
  system.stateVersion = "24.11";
}
