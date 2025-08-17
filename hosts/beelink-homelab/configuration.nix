# SPDX-License-Identifier: GPL-3.0-or-later

{
  config,
  lib,
  pkgs,
  ...
}:

{
  imports = [
    ./hardware-configuration.nix
    ./disko-config.nix
    ./media.nix
  ];

  # Enable the system banner
  programs.system-banner = {
    enable = true;
    shellHook = ''
      echo
      echo "Welcome back, $(whoami)!" | cowsay | lolcat
    '';
    showOnLogin = false;
  };

  # Media server networking configuration
  networking = {
    # Host identification
    hostName = "beelink-homelab";
    hostId = "2d833f3e"; # Generate with: head -c 4 /dev/urandom | od -A none -t x4 | tr -d ' '

    # Open additional ports for media services (base ports from modules)
    firewall = {
      allowedTCPPorts = [
        # Additional ports not in modules
        8080 # General web services
        9134 # ZFS exporter
        445 # SMB
        139 # NetBIOS
      ];
      allowedUDPPorts = [
        1900 # DLNA/UPnP
        7359 # Jellyfin autodiscovery
        137 # NetBIOS Name Service
        138 # NetBIOS Datagram Service
      ];
    };
  };

  # custom internal settings
  networking.internal = {
    interface = "enp1s0";
    adguard = {
      enabled = true;
      mode = "failover"; # default
    };
    # Network forwarding for VPN namespace
    forwarding = true;
    nat = {
      externalInterface = "enp1s0";
      internalInterfaces = [ "vpn-host" ];
    };
  };

  # ZFS support
  # Boot configuration
  boot = {
    # Enable ZFS support
    supportedFilesystems = lib.mkForce [
      "zfs"
      "ntfs"
      "btrfs"
    ];
    zfs = {
      forceImportRoot = false;
      devNodes = "/dev/disk/by-id/";
    };

    # Kernel parameters for ZFS
    kernelParams = [ "zfs.zfs_arc_max=8589934592" ]; # 8GB ARC max

    # Bootloader
    loader = {
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = true;
    };

    tmp = {
      useTmpfs = lib.mkForce false; # Disable the common setting
    };

    # Implement "Erase Your Darlings" - rollback root on boot
    initrd.postDeviceCommands = lib.mkAfter ''
      zfs rollback -r rpool/local/root@blank
    '';
  };

  # ZFS services
  services.zfs = {
    autoScrub = {
      enable = true;
      interval = "weekly";
    };
    autoSnapshot = {
      enable = true;
      frequent = 4; # Keep 4 15-minute snapshots
      hourly = 24; # Keep 24 hourly snapshots
      daily = 7; # Keep 7 daily snapshots
      weekly = 4; # Keep 4 weekly snapshots
      monthly = 12; # Keep 12 monthly snapshots
    };
  };

  # MergerFS for unified media view
  fileSystems."/mnt/media" = {
    device = "/mnt/disk1:/mnt/disk2";
    fsType = "fuse.mergerfs";
    options = [
      "defaults"
      "allow_other"
      "use_ino" # for better inode handling
      "cache.files=partial"
      "dropcacheonclose=true" # for memory management
      "category.create=mfs" # Most free space for new files
      "moveonenospc=true" # Move files if no space
      "minfreespace=50G" # Keep 50GB free on each drive
    ];
  };

  # NixOS build optimization - use fast NVMe for builds
  nix.settings = {
    max-jobs = "auto";
    cores = 0; # Use all available cores
    # Keep build directories on fast storage
    build-dir = "/tmp";
  };

  # Set up a large /tmp on tmpfs for builds
  fileSystems."/tmp" = {
    device = "tmpfs";
    fsType = "tmpfs";
    options = [
      "mode=1777"
      "size=32G"
    ];
  };

  sops = {
    defaultSopsFile = ../../secrets/beelink-homelab.yaml;
    defaultSopsFormat = "yaml";
    # Use SSH host key for decryption
    age.sshKeyPaths = [ "/persist/etc/ssh/ssh_host_ed25519_key" ];

    secrets = {
      # NordVPN WireGuard configuration
      "nordvpn_access_token" = {
        owner = "root";
        group = "root";
        mode = "0600";
      };
    };
  };

  # Enable NordVPN for anonymized torrenting
  nordvpn = {
    enable = true;
    accessTokenFile = config.sops.secrets.nordvpn_access_token.path;
  };

  # Enable specific media services
  services = {
    # Jellyfin is enabled by default in the media module
    # Enable additional services as needed
    sonarr.enable = true;
    radarr.enable = true;
    prowlarr = {
      enable = true;
      useVpnNamespace = false; # Keep on regular network to avoid tracker bans
    };
    qbittorrent-nox = {
      enable = true;
      openFirewall = true;
      useVpnNamespace = true; # Route through VPN
    };
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

    # MergerFS
    mergerfs
    mergerfs-tools

    # Media tools
    ffmpeg
    mediainfo
    exiftool

    # Storage tools
    smartmontools
    hdparm
    lsscsi

    # Access jellyfin DB
    sqlite
  ];

  # System state version
  system.stateVersion = "24.11";
}
