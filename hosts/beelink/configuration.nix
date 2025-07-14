{ config, lib, pkgs, inputs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./disko-config.nix
  ];

  # Enable the system banner
  # programs.system-banner = {
  #   enable = true;

  #   # Optional: Add custom commands to run after the banner is displayed
  #   shellHook = ''
  #     # You could add additional commands here, like:
  #     # echo "Welcome back, $(whoami)!"
  #     echo
  #     echo "Welcome back, $(whoami)!" | cowsay | lolcat
  #   '';

  #   # Optional: Set to false if you don't want the banner to show on every interactive shell
  #   showOnLogin = true;
  # };

  # Host identification
  networking = {
    hostName = "beelink";
    hostId = "2d833f3e"; # Generate with: head -c 4 /dev/urandom | od -A none -t x4 | tr -d ' '
  };

  # ZFS support
  # Boot configuration
  boot = {
    # Enable ZFS support
    supportedFilesystems = lib.mkForce [ "zfs" "ntfs" "btrfs" ];
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
      useTmpfs = lib.mkForce false;  # Disable the common setting
    };

    # Implement "Erase Your Darlings" - rollback root on boot
    # initrd.postDeviceCommands = lib.mkAfter ''
    #   zfs rollback -r rpool/local/root@blank
    # '';
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
      hourly = 24;  # Keep 24 hourly snapshots
      daily = 7;    # Keep 7 daily snapshots
      weekly = 4;   # Keep 4 weekly snapshots
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
      "use_ino"               # for better inode handling
      "cache.files=partial"
      "dropcacheonclose=true" # for memory management
      "category.create=mfs"   # Most free space for new files
      "moveonenospc=true"     # Move files if no space
      "minfreespace=50G"      # Keep 50GB free on each drive
    ];
  };

  # Ensure /persist is available early for impermanence
  fileSystems."/persist" = {
    neededForBoot = true;
  };

  # Persistence configuration for "Erase Your Darlings"
  # Note: We don't use impermanence for SSH keys since we're handling them explicitly
  environment.persistence."/persist" = {
    hideMounts = true;
    directories = [
      # System
      "/etc/nixos"
      "/var/lib/nixos"  # to persist user/group IDs
      "/var/lib/systemd/coredump"
      { directory = "/var/lib/private"; mode = "0700"; }
      "/var/log"

      # Network
      "/etc/NetworkManager/system-connections"
      { directory = "/var/lib/NetworkManager"; mode = "0700"; }

      # Services - Don't specify user/group for services that might not exist yet
      "/var/lib/jellyfin"
      "/var/lib/postgresql"
      { directory = "/var/lib/docker"; mode = "0710"; }
      "/var/lib/samba"
      # Add these for network persistence:
      "/etc/ssh"  # SSH host keys
      "/var/lib/systemd/network"  # Network state
      { directory = "/var/lib/dhcp"; mode = "0755"; }  # DHCP leases
    ];
    files = [
      "/etc/machine-id"
      "/etc/ssh/ssh_host_ed25519_key"
      "/etc/ssh/ssh_host_ed25519_key.pub"
      "/etc/ssh/ssh_host_rsa_key"
      "/etc/ssh/ssh_host_rsa_key.pub"
    ];
  };

  # Samba for NAS functionality
  services.samba = {
    enable = true;

    # New settings format
    settings = {
      global = {
        workgroup = "WORKGROUP";
        "server string" = "NixOS NAS";
        "netbios name" = "nixnas";
        security = "user";
        # Use persistent location for Samba's private data
        "private dir" = "/persist/var/lib/samba/private";

        # Performance optimizations for ZFS
        "use sendfile" = "yes";
        "min protocol" = "SMB2";
        "aio read size" = "16384";
        "aio write size" = "16384";
        "socket options" = "TCP_NODELAY IPTOS_LOWDELAY SO_RCVBUF=131072 SO_SNDBUF=131072";
      };

      backups = {
        path = "/mnt/backups";
        browseable = "yes";
        "read only" = "no";
        "guest ok" = "no";
        "create mask" = "0644";
        "directory mask" = "0755";
        comment = "Backup Storage (RAID-Z2)";
      };

      media = {
        path = "/mnt/media";
        browseable = "yes";
        "read only" = "no";
        "guest ok" = "yes";
        "create mask" = "0644";
        "directory mask" = "0755";
        comment = "Media Storage (MergerFS)";
      };
    };
  };

  # Ensure service directories have correct permissions after services are installed
  systemd.tmpfiles.rules = [
    # ACME certificates (if using Let's Encrypt)
    "L /var/lib/acme - - - - /persist/var/lib/acme"

    # NetworkManager
    "L /etc/NetworkManager/system-connections - - - - /persist/etc/NetworkManager/system-connections"

    # Create directories that need to exist before services start
    "d /persist/etc/ssh 0755 root root -"
    "d /persist/var/lib/acme 0755 root root -"

    # Fix permissions for service directories after user creation
    "z /persist/var/lib/jellyfin 0755 jellyfin jellyfin -"
    "z /persist/var/lib/postgresql 0700 postgres postgres -"

    # Ensure media directories have correct permissions
    "d /mnt/media 0755 jellyfin jellyfin -"
    "d /mnt/backups 0755 root root -"
    "d /persist 0755 root root -"

    # Ensure Samba directories exist
    "d /persist/var/lib/samba 0755 root root -"
    "d /persist/var/lib/samba/private 0700 root root -"

    # Symlink for Samba
    "L /var/lib/samba - - - - /persist/var/lib/samba"
  ];

  # Bind mount persistent directories
  fileSystems."/etc/nixos" = {
    device = "/persist/etc/nixos";
    options = [ "bind" ];
    neededForBoot = true;
  };

  fileSystems."/var/log" = {
    device = "/persist/var/log";
    options = [ "bind" ];
    neededForBoot = true;
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
    options = [ "mode=1777" "size=32G" ];
  };

  # Enable specific media services
  services = {
    # Jellyfin is enabled by default in the media module
    # Enable additional services as needed
    sonarr.enable = true;
    radarr.enable = true;
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

  # systemd.network.networks."10-enp1s0" = {
  #   matchConfig.Name = "enp1s0";
  #   networkConfig.DHCP = "yes";
  # };

  # Network configuration for media server
  networking = {
    interfaces.enp1s0.useDHCP = true;  # This works fine with useNetworkd
    firewall.enable = true;
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
  ];

  # System state version
  system.stateVersion = "24.11";
}
