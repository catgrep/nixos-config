# SPDX-License-Identifier: GPL-3.0-or-later

{
  config,
  pkgs,
  lib,
  ...
}:

{
  imports = [
    ./installer.nix
  ];

  # USB-specific configurations for Pi5 with NVMe
  boot = {
    # NVMe and USB configuration handled by nixos-raspberrypi base module
    # Additional kernel modules for USB boot and NVMe support

    # Kernel modules for NVMe and USB
    kernelModules = [
      "nvme"
      "nvme_core" 
      "usb_storage"
      "uas"
    ];

    # Early load for NVMe
    initrd.kernelModules = [
      "nvme"
      "nvme_core"
    ];
  };

  # Enable additional services for USB/NVMe installer
  services = {
    # Enable hardware detection
    udev.enable = true;
    
    # USB automount support
    udisks2.enable = true;
  };

  # Additional packages for NVMe/USB management
  environment.systemPackages = with pkgs; [
    # NVMe tools
    nvme-cli
    
    # USB tools
    usbutils
    
    # Partitioning tools
    parted
    gptfdisk
    
    # File system tools
    e2fsprogs
    dosfstools
    
    # Disk tools
    smartmontools
    hdparm
    
    # Network tools for remote installation
    curl
    wget
    rsync
  ];

  # Network hostname - override the installer.nix default
  networking.hostName = lib.mkForce "pi5-usb-installer";
  
  # Enable automatic drive detection and mounting
  fileSystems = {
    # Auto-mount USB drives
    "/mnt/usb" = {
      device = "/dev/disk/by-label/USB";
      fsType = "auto";
      options = [ "noauto" "user" "rw" ];
    };
  };

  # Pre-configure for NVMe installation
  # This helps with detecting NVMe drives during installation
  hardware.enableRedistributableFirmware = true;
  
  # Optimize for installation process
  boot.kernelParams = [
    # Reduce boot time
    "quiet"
    "splash"
    
    # NVMe optimizations
    "nvme_core.default_ps_max_latency_us=0"
  ];
}