{ config, lib, pkgs, inputs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./disko-config.nix
  ];

  # Host identification
  networking = {
    hostName = "pi5";
    hostId = "4c0630cf"; # Generate with: head -c 4 /dev/urandom | od -A none -t x4 | tr -d ' '
  };

  # Network configuration
  networking = {
    interfaces.end0.useDHCP = true; # Pi5 uses 'end0' for ethernet
    firewall.enable = true;
  };

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

  # Pi5-specific packages
  environment.systemPackages = with pkgs; [
    libraspberrypi
    raspberrypi-eeprom

    # DNS tools
    dig
    host

    # Network monitoring
    bandwhich
    nethogs
  ];

  # System state version
  system.stateVersion = "24.11";
}
