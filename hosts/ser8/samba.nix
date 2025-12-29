# SPDX-License-Identifier: GPL-3.0-or-later

{
  config,
  pkgs,
  ...
}:

{
  # Samba for NAS functionality
  services.samba = {
    enable = true;
    openFirewall = true;

    # nmbd was starting before network interfaces were
    # up resulting in:
    #
    # NOTE: NetBIOS name resolution is not supported for Internet Protocol Version 6 (IPv6).
    #
    # We don't need to support NetBIOS names like '\\FILESERVER'
    nmbd.enable = false;

    # New settings format
    # See https://carlosvaz.com/posts/setting-up-samba-shares-on-nixos-with-support-for-macos-time-machine-backups/
    settings = {
      global = {
        workgroup = "WORKGROUP";
        "server string" = "NixOS NAS";
        "netbios name" = "nixnas";
        security = "user";
        # Use persistent location for Samba's private data
        "private dir" = "/persist/var/lib/samba/private";

        # Clients should only connect using the latest SMB3 protocol (e.g., on
        # clients running Windows 8 and later).
        # "server min protocol" = "SMB3_11";
        # # Require native SMB transport encryption by default.
        # "server smb encrypt" = "required";

        # Guest access configuration
        "guest account" = "nobody";
        "map to guest" = "bad user";

        # Performance optimizations for ZFS
        "use sendfile" = "yes";
        "min protocol" = "SMB2";
        "aio read size" = "16384";
        "aio write size" = "16384";
        "socket options" = "TCP_NODELAY IPTOS_LOWDELAY SO_RCVBUF=131072 SO_SNDBUF=131072";
        "kernel change notify" = "no";

        # NOTE: localhost is the ipv6 localhost ::1
        # "hosts allow" = "192.168.0. 127.0.0.1 localhost";
        # "hosts deny" = "0.0.0.0/0";

        # Critical macOS settings
        # See https://wiki.samba.org/index.php/Configure_Samba_to_Work_Better_with_Mac_OS_X
        "vfs objects" = "catia fruit streams_xattr";
        "fruit:metadata" = "stream";
        "fruit:model" = "MacSamba";
        "unix extensions" = "no"; # Disable UNIX extensions that confuse macOS
        "ea support" = "yes"; # Apple extensions support for extended attributes(xattr)
        # Enable Apple's SMB2+ extension.
        "fruit:aapl" = "yes";
        # Clean up unused or empty files created by the OS or Samba.
        "fruit:posix_rename" = "yes";
        "fruit:zero_file_id" = "yes";
        "fruit:veto_appledouble" = "no";
        "fruit:wipe_intentionally_left_blank_rfork" = "yes";
        "fruit:delete_empty_adfiles" = "yes";
        "fruit:nfs_aces" = "yes"; # Access Control Entry (ACE) is part of the Access Control List (ACL)
      };

      backups = {
        path = "/mnt/backups";
        browseable = "yes";
        writable = "yes";
        "read only" = "no";
        "guest ok" = "no";
        "valid users" = "bdhill"; # Explicitly allowed
        "create mask" = "0644";
        "directory mask" = "0755";
        comment = "Backup Storage (RAID-Z2)";
      };

      media = {
        path = "/mnt/media";
        browseable = "yes";
        writable = "yes";
        public = "yes";
        "read only" = "no";
        "guest ok" = "yes";
        # Force all operations to happen as the media user/group
        "force user" = "media";
        "force group" = "media";
        # macOS permission mappings
        "create mask" = "0664";
        "directory mask" = "0775";
        "force create mode" = "0664";
        "force directory mode" = "0775";
        comment = "Media Storage (MergerFS)";
      };
    };
  };

  # For OSX and windows discovery
  services.samba-wsdd = {
    enable = true;
    discovery = true;
    workgroup = "WORKGROUP"; # Match samba workgroup
  };

  # SOPS configuration
  sops = {
    defaultSopsFile = ../../secrets/ser8.yaml;
    defaultSopsFormat = "yaml";

    # Use SSH host key for decryption
    age.sshKeyPaths = [ "/persist/etc/ssh/ssh_host_ed25519_key" ];

    secrets = {
      "samba_bdhill_password" = {
        neededForUsers = true;
        owner = "root";
        group = "root";
        mode = "0600";
      };
      "samba_media_password" = {
        neededForUsers = true;
        owner = "root";
        group = "root";
        mode = "0600";
      };
    };
  };

  # Systemd service to set Samba passwords
  systemd.services.samba-password-sync = {
    description = "Sync Samba passwords from SOPS";
    after = [ "samba.service" ];
    wants = [ "samba.service" ];
    wantedBy = [ "multi-user.target" ];

    # Restart if samba restarts
    partOf = [ "samba.service" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      # Run as root to access smbpasswd
      User = "root";
    };

    script = ''
      # Ensure Samba is ready
      while ! ${pkgs.systemd}/bin/systemctl is-active samba-smbd.service; do
      sleep 1
      done

      # Set passwords
      echo "Setting Samba passwords from SOPS..."

      # media
      if ${pkgs.samba}/bin/smbpasswd -a -s media < <(
        cat ${config.sops.secrets.samba_media_password.path}
        echo
        cat ${config.sops.secrets.samba_media_password.path}
      ); then
        echo "✓ Set password for media user"
      fi

      # bdhill
      if ${pkgs.samba}/bin/smbpasswd -a -s bdhill < <(
        cat ${config.sops.secrets.samba_bdhill_password.path}
        echo
        cat ${config.sops.secrets.samba_bdhill_password.path}
      ); then
        echo "✓ Set password for bdhill user"
      fi
    '';
  };
}
