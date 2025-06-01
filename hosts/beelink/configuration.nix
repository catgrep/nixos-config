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

  # Open ports for media services
  networking.firewall = {
    allowedTCPPorts = [
      8096  # Jellyfin
      8080  # General web services
      8989  # Sonarr
      7878  # Radarr
      9117  # Jackett
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

  # Media-specific packages
  environment.systemPackages = with pkgs; [
    # ZFS tools
    zfs
    zfstools
    sanoid
    syncoid

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
