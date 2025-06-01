{ config, lib, pkgs, inputs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./disko-config.nix
    ./services
  ];

  # Host identification
  networking = {
    hostName = "beelink";
    hostId = "3febce3a8d94215"; # Generate with: head -c 8 /dev/urandom | od -A none -t x8
  };

  # ZFS support
  boot.supportedFilesystems = [ "zfs" ];
  boot.zfs = {
    forceImportRoot = false;
    requestEncryptionCredentials = true;
  };

  # ZFS services
  services.zfs = {
    autoScrub = {
      enable = true;
      interval = "monthly";
    };
    autoSnapshot = {
      enable = true;
      flags = "-k -p --utc";
    };
  };

  # Prometheus exporters for monitoring
  services.prometheus.exporters = {
    node = {
      enable = true;
      port = 9100;
      enabledCollectors = [
        "systemd"
        "processes"
        "cpu"
        "memory"
        "filesystem"
        "network"
        "diskstats"
        "loadavg"
        "zfs"
      ];
    };

    zfs = {
      enable = true;
      port = 9134;
    };
  };

  # Network configuration for media server
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

  # Open ports for media services and monitoring
  networking.firewall = {
    allowedTCPPorts = [
      8096  # Jellyfin
      8080  # General web services
      8989  # Sonarr
      7878  # Radarr
      9117  # Jackett
      9100  # Node exporter
      9134  # ZFS exporter
    ];
    allowedUDPPorts = [
      1900  # DLNA/UPnP
      7359  # Jellyfin autodiscovery
    ];
  };

  # Hardware acceleration for media transcoding
  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      intel-media-driver
      vaapiIntel
      vaapiVdpau
      libvdpau-va-gl
    ];
  };

  # MergerFS for unified media view
  fileSystems."/mnt/media" = {
    device = "/mnt/media1:/mnt/media2";
    fsType = "fuse.mergerfs";
    options = [
      "defaults"
      "allow_other"
      "use_ino"
      "cache.files=partial"
      "dropcacheonclose=true"
      "category.create=mfs"  # Most free space for new files
      "moveonenospc=true"    # Move files if no space
      "minfreespace=50G"     # Keep 50GB free on each drive
    ];
  };

  # Media-specific packages
  environment.systemPackages = with pkgs; [
    # ZFS tools
    zfs
    zfstools
    sanoid
    syncoid

    # MergerFS
    mergerfs

    # Media tools
    ffmpeg
    mediainfo
    exiftool

    # Storage tools
    smartmontools
    hdparm
    lsscsi
  ];

  # System state version
  system.stateVersion = "24.11";
}
