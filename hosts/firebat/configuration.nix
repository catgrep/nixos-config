{ config, lib, pkgs, inputs, ... }:

{
  imports = [
    ./hardware-configuration.nix
  ];

  # Host identification
  networking = {
    hostName = "firebat";
    hostId = "89e571c4"; # Generate with: head -c 4 /dev/urandom | od -A none -t x4 | tr -d ' '
  };

  # Gateway networking configuration
  networking = {
    interfaces.eno1.useDHCP = true;  # or wlp2s0, Update interface name as needed
    # Enable IP forwarding for gateway functionality
    firewall.enable = true;
    nat = {
      enable = true;
      externalInterface = "eno1";  # or wlp2s0, Update as needed
      internalInterfaces = [ ];  # Add internal interfaces if needed
    };
  };

  # Enable IP forwarding
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
