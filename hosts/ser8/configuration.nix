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
    ./media
    ./household
  ];

  # Media server networking configuration
  networking = {
    # Host identification
    hostName = "ser8";
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
    # forwarding = true;
    # nat = {
    #   externalInterface = "enp1s0";
    #   internalInterfaces = [ "vpn-host" ];
    # };
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
      extraPools = [ "backup" ]; # Auto-import backup pool on boot
    };

    # Kernel parameters for ZFS
    kernelParams = [
      "zfs.zfs_arc_max=8589934592" # 8GB ARC max
      "amdgpu.cwsr_enable=0" # Prevents MES firmware hang on RDNA3 iGPU (780M) under ROCm
    ];

    # Bootloader
    loader = {
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = true;
    };

    tmp = {
      useTmpfs = lib.mkForce false; # Disable the common setting
    };

    # Implement "Erase Your Darlings" - rollback root on boot.
    #
    # NixOS 26.05 flipped boot.initrd.systemd.enable to true by default, and the
    # systemd stage-1 initrd ignores boot.initrd.postDeviceCommands entirely (it
    # asserts on the option rather than silently dropping it). The rollback is
    # therefore expressed as a stage-1 systemd oneshot: ordered after rpool is
    # imported and before the root filesystem is mounted, which is exactly the
    # window the old postDeviceCommands hook ran in.
    initrd.systemd.services.rollback = {
      description = "Roll back rpool/local/root to its blank snapshot";
      wantedBy = [ "initrd.target" ];
      after = [ "zfs-import-rpool.service" ];
      before = [ "sysroot.mount" ];
      path = [ pkgs.zfs ];
      unitConfig.DefaultDependencies = "no";
      serviceConfig.Type = "oneshot";
      script = ''
        zfs rollback -r rpool/local/root@blank
      '';
    };
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
    # ZFS Event Daemon -- sends email on scrub errors, resilver events, etc.
    zed = {
      enableMail = true;
      settings = {
        ZED_EMAIL_ADDR = [ "catgrep@sudomail.com" ];
        ZED_NOTIFY_VERBOSE = true;
        ZED_SCRUB_AFTER_RESILVER = true;
      };
    };
  };

  # Lightweight MTA for system email (used by ZFS zed for scrub error alerts)
  programs.msmtp = {
    enable = true;
    setSendmail = true;
    defaults = {
      auth = true;
      tls = true;
      tls_starttls = true;
      logfile = "/var/log/msmtp.log";
    };
    accounts.default = {
      host = "smtp.gmail.com";
      port = 587;
      from = "shadbangus@gmail.com";
      user = "shadbangus@gmail.com";
      passwordeval = "cat ${config.sops.secrets.gmail_smtp_password.path}";
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

  # NixOS build optimization
  nix.settings = {
    max-jobs = "auto";
    cores = 0; # Use all available cores
  };

  # Keep general temporary files on tmpfs.
  fileSystems."/tmp" = {
    device = "tmpfs";
    fsType = "tmpfs";
    options = [
      "mode=1777"
      "size=32G"
    ];
  };

  # Dedicated root-owned tmpfs for the shared Nix build-dir.
  fileSystems."/nix-builds" = {
    device = "tmpfs";
    fsType = "tmpfs";
    options = [
      "mode=0755"
      "size=32G"
    ];
  };

  sops = {
    defaultSopsFile = ../../secrets/ser8.yaml;
    defaultSopsFormat = "yaml";
    # Use SSH host key for decryption
    age.sshKeyPaths = [ "/persist/etc/ssh/ssh_host_ed25519_key" ];

    secrets = {
      # Gmail SMTP password for msmtp (ZFS zed email alerts)
      "gmail_smtp_password" = {
        mode = "0400";
      };
    };
  };

  # Enable specific media services
  services = {
    # Jellyfin is enabled by default in the media module
    # Enable additional services as needed
    flaresolverr.enable = true;

    # Home automation services
    home-assistant.enable = true;
    frigate.enable = true;
    mosquitto.enable = true; # MQTT broker for Frigate <-> Home Assistant
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

  # Hardware acceleration for media transcoding (AMD Ryzen 7 8845HS with Radeon 780M)
  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      # AMD VA-API driver (radeonsi via mesa)
      libvdpau-va-gl
      # ROCm OpenCL runtime for GPU compute
      rocmPackages.clr.icd
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

    # Filesystem storage metrics
    dust

    # VA-API diagnostics (for verifying hardware acceleration)
    libva-utils

    (fastfetch.override {
      zfsSupport = true;
    })
  ];

  # System state version
  system.stateVersion = "24.11";
}
