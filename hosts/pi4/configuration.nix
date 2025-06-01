{ config, lib, pkgs, inputs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./services
  ];

  # Host identification
  networking = {
    hostName = "pi4";
    hostId = "4f51b97037da22b5"; # Generate with: head -c 8 /dev/urandom | od -A none -t x8
  };

  # Raspberry Pi specific configuration
  boot = {
    loader = {
      grub.enable = false;
      generic-extlinux-compatible.enable = true;
    };

    # Raspberry Pi 4 specific kernel
    kernelPackages = pkgs.linuxPackages_rpi4;
  };

  # Network configuration for DNS server
  systemd.network = {
    enable = true;
    networks."10-lan" = {
      matchConfig.Name = "eth0";
      networkConfig = {
        DHCP = "yes";
        IPForward = false;
      };
      linkConfig.RequiredForOnline = "routable";
      # Set static IP for DNS server reliability
      address = [ "192.168.1.10/24" ]; # Adjust to your network
      gateway = [ "192.168.1.1" ];     # Adjust to your gateway
    };
  };

  # Open DNS ports and monitoring
  networking.firewall = {
    allowedTCPPorts = [
      53    # DNS
      80    # AdGuard Home web interface
      3000  # AdGuard Home initial setup
      9100  # Node exporter
      9617  # AdGuard Home exporter
    ];
    allowedUDPPorts = [
      53    # DNS
    ];
  };

  # DNS and monitoring packages
  environment.systemPackages = with pkgs; [
    # DNS tools
    dig
    nslookup
    host

    # Network monitoring
    bandwhich
    nethogs
  ];

  # Enable hardware-specific features
  hardware = {
    raspberry-pi."4" = {
      fkms-3d.enable = true;
      audio.enable = true;
    };

    # Enable I2C and SPI for potential sensor connectivity
    i2c.enable = true;
  };

  # Power management for Pi
  powerManagement = {
    enable = true;
    cpuFreqGovernor = "ondemand";
  };

  # System state version
  system.stateVersion = "24.11";
}
