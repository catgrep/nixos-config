{ config, lib, pkgs, inputs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    # Import the DNS services module
    ../modules/dns
    # Import server-specific configurations (adapted for ARM)
    ../modules/servers
     inputs.nixos-hardware.nixosModules.raspberry-pi-4
  ];

  # Host identification
  networking = {
    hostName = "pi4";
    hostId = "4f51b970"; # Generate with: head -c 4 /dev/urandom | od -A none -t x4 | tr -d ' '
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
  networking = {
    interfaces.eth0.useDHCP = true;  # Use DHCP for simplicity
    # Or use static IP:
    # interfaces.eth0 = {
    #   useDHCP = false;
    #   ipv4.addresses = [{
    #     address = "192.168.1.10";
    #     prefixLength = 24;
    #   }];
    # };
    # defaultGateway = "192.168.1.1";
    # nameservers = [ "127.0.0.1" ];
  };

  # DNS service is enabled by default from the module
  # Override AdGuard settings if needed
  services.adguardhome.settings = {
    # Override specific settings here if needed
  };

  # Pi-specific monitoring
  # services.pi-temp-monitor = {
  #   enable = true;
  # };

  # DNS-specific packages
  environment.systemPackages = with pkgs; [
    # DNS tools
    dig
    host

    # Network monitoring
    bandwhich
    nethogs
  ];

  # Enable hardware-specific features
  # Remove the non-existent raspberry-pi hardware module
  hardware = {
    raspberry-pi."4" = {
      fkms-3d.enable = true;
      audio.enable = true;
    };
  };

  # Enable I2C and SPI for potential sensor connectivity
  hardware.i2c.enable = true;

  # Enable GPIO support (if needed)
  hardware.deviceTree = {
    enable = true;
    overlays = [ ];
  };

  # Power management for Pi
  powerManagement = {
    enable = true;
    cpuFreqGovernor = "ondemand";
  };

  # System state version
  system.stateVersion = "24.11";
}
