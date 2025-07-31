{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:

{
  imports = [
    ./hardware-configuration.nix
  ];

  # Host identification
  networking = {
    hostName = "pi4";
    hostId = "7406fd88"; # Generate with: head -c 4 /dev/urandom | od -A none -t x4 | tr -d ' '
  };

  # Network configuration
  networking = {
    interfaces.end0.useDHCP = true; # Pi5 uses 'end0' for ethernet
    firewall.enable = true;
  };

  networking.firewall = {
    allowedTCPPorts = [
      53 # DNS
      80 # AdGuard Home web interface
      3000 # AdGuard Home initial setup
      9100 # Node exporter
      9617 # AdGuard Home exporter
    ];
    allowedUDPPorts = [
      53 # DNS
    ];
  };

  # Enable specific services based on your needs
  # For example, if this will be another DNS server:
  services.adguardhome.enable = true;

  # Raspberry Pi packages
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

  # https://github.com/nvmd/nixos-raspberrypi/issues/8#issuecomment-2804912881
  # We're just going to boot off the SD card, not a separate installation media.
  # We don't need nixos-anywhere for this.
  fileSystems = {
    "/boot/firmware" = {
      device = "/dev/disk/by-label/FIRMWARE";
      fsType = "vfat";
      options = [
        "umask=0077"
        "noatime"
        "noauto"
        "x-systemd.automount"
        "x-systemd.idle-timeout=1min"
      ];
    };
    "/" = {
      device = "/dev/disk/by-label/NIXOS_SD";
      fsType = "ext4";
      options = [ "noatime" ];
    };
  };

  # System state version
  system.stateVersion = "24.11";
}
