{ config, lib, pkgs, inputs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./disko-config.nix
    # Import the media services module
    ../modules/media
    # Import server-specific configurations
    ../modules/servers
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

  # Enable specific media services
  services = {
    # Jellyfin is enabled by default in the media module
    # Enable additional services as needed
    # sonarr.enable = true;
    # radarr.enable = true;
    # transmission.enable = true;
  };

  # Host-specific monitoring - extends the server monitoring module
  services.prometheus.exporters = {
    # Node exporter is already enabled by servers module
    # Add ZFS-specific monitoring
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

  # Open additional ports for media services (base ports from modules)
  networking.firewall = {
    allowedTCPPorts = [
      # Additional ports not in modules
      8080  # General web services
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
