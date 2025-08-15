# SPDX-License-Identifier: GPL-3.0-or-later

{
  lib,
  ...
}:

{
  services.openssh = lib.mkForce {
    # Persist host keys
    hostKeys = [
      {
        path = "/persist/etc/ssh/ssh_host_ed25519_key";
        type = "ed25519";
      }
      {
        path = "/persist/etc/ssh/ssh_host_rsa_key";
        type = "rsa";
        bits = 4096;
      }
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
      "/var/lib/nixos" # to persist user/group IDs
      "/var/lib/systemd/coredump"
      {
        directory = "/var/lib/private";
        mode = "0700";
      }
      "/var/log"

      # Network
      "/etc/NetworkManager/system-connections"
      {
        directory = "/var/lib/NetworkManager";
        mode = "0700";
      }

      # Services - Don't specify user/group for services that might not exist yet
      "/var/lib/jellyfin"
      "/var/lib/sonarr"
      "/var/lib/radarr"
      "/var/lib/postgresql"
      {
        directory = "/var/lib/docker";
        mode = "0710";
      }

      "/var/lib/samba"
      {
        directory = "/var/lib/samba/private"; # For storing samba user secrets
        mode = "0700";
      }

      # Add these for network persistence:
      "/var/lib/systemd/network" # Network state
      {
        directory = "/var/lib/dhcp";
        mode = "0755";
      } # DHCP leases
    ];
    files = [
      "/etc/machine-id"
      "/etc/ssh/ssh_host_ed25519_key"
      "/etc/ssh/ssh_host_ed25519_key.pub"
      "/etc/ssh/ssh_host_rsa_key"
      "/etc/ssh/ssh_host_rsa_key.pub"
    ];
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
    "d /persist/var/lib/jellyfin 0755 jellyfin jellyfin -"
    "Z /persist/var/lib/jellyfin 0755 jellyfin jellyfin - -"
    "d /var/lib/jellyfin 0755 jellyfin jellyfin -"
    "Z /var/lib/jellyfin 0755 jellyfin jellyfin -"
    # "d /persist/var/lib/postgresql 0700 postgres postgres -"

    # Ensure media directories have correct permissions
    "d /mnt/media 0775 media media -"
    "d /mnt/media/movies 0775 media media -"
    "d /mnt/media/tv 0775 media media -"
    "d /mnt/media/music 0775 media media -"
    "d /mnt/media/books 0775 media media -"

    # Ensure download directories exist with proper media group permissions
    "d /mnt/downloads 0775 media media -"
    "d /mnt/downloads/tv 0775 sonarr media -"
    "d /mnt/downloads/movies 0775 radarr media -"

    # Service-specific directories with proper permissions
    "d /persist/var/lib/sonarr 0755 sonarr sonarr -"
    "d /persist/var/lib/radarr 0755 radarr radarr -"
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
}
