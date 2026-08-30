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

      # Nothing for the services that each have their own dataset. Those
      # datasets mount straight onto /var/lib/<service>, and an entry here would
      # bind the same path from a second source. The two layers have no ordering
      # relationship -- the generated bind units run with default dependencies
      # disabled and never wait on the dataset mount -- so keeping both is a
      # race, and the losing outcome is a service that starts against an empty
      # directory. One mechanism per path.
      #
      # What remains below is state that no single unit owns, which is why it
      # stays in the parent dataset rather than getting a child of its own.
      "/var/lib/samba"
      {
        directory = "/var/lib/samba/private"; # For storing samba user secrets
        mode = "0700";
      }

      # Add these for network persistence:
      "/var/lib/systemd/network" # Network state
      # Last-trigger stamps for timers. systemd reads these at boot to decide
      # whether a timer marked persistent missed a run while the machine was
      # off, and replays it if so. Left on the root filesystem the boot-time
      # rollback wipes, every stamp is gone by the time systemd looks, so no
      # persistent timer on this host has ever replayed a missed run.
      "/var/lib/systemd/timers"
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

    # Fix permissions for service directories after user creation.
    #
    # These name /var/lib/<service> rather than /persist/var/lib/<service>
    # because each of those paths is now the mountpoint of the service's own
    # dataset. The directory under /persist is no longer read by anything, so a
    # rule pointing at it would set ownership nothing consults.
    "d /var/lib/jellyfin 0755 jellyfin media -"
    "Z /var/lib/jellyfin 0755 jellyfin media -"
    # 0750, not 0700: the postgresql module sets StateDirectoryMode to 0750 for
    # any major >= 11, so a 0700 declarative rule would fight systemd on every
    # start. PostgreSQL accepts 0750 on PGDATA.
    "d /var/lib/postgresql 0750 postgres postgres -"

    # Mealie stores recipe images, user assets, and the session-signing secret
    # under DATA_DIR on disk, not in PostgreSQL.
    "d /var/lib/mealie 0750 mealie mealie -"

    # Homebox stores its SQLite database and uploaded attachments under
    # /var/lib/homebox. 0750, matching modules/household/homebox.nix's
    # explicit StateDirectoryMode override -- systemd's own default for
    # StateDirectory is 0755, so without that override this rule would be
    # cosmetic and get re-stamped to 0755 on every service start.
    "d /var/lib/homebox 0750 homebox homebox -"

    # Actual stores its SQLite account/budget databases and uploaded budget
    # files under /var/lib/actual. 0700, matching services.actual's own
    # StateDirectoryMode -- unlike Mealie/Homebox, the upstream Actual module
    # hardcodes StateDirectoryMode = "0700" unconditionally (not left at
    # systemd's 0755 default), so a 0750 rule here would fight it on every
    # service start.
    "d /var/lib/actual 0700 actual actual -"

    # Upstream's services.actual module sets ReadWritePaths to
    # cfg.settings.serverFiles / cfg.settings.userFiles
    # (/var/lib/actual/server-files, /var/lib/actual/user-files) but never
    # creates either subdirectory itself -- neither via preStart nor its own
    # tmpfiles rules. systemd's mount-namespace setup for ReadWritePaths
    # requires each path to already exist, so on a fresh /var/lib/actual the
    # unit fails at step NAMESPACE ("No such file or directory") before
    # ExecStartPre ever runs. Declared explicitly here rather than filed
    # upstream-only, since the household service must work today. Both sit
    # inside /var/lib/actual, so the one dataset mounted there captures the
    # account database and the uploaded budget files in a single snapshot.
    "d /var/lib/actual/server-files 0700 actual actual -"
    "d /var/lib/actual/user-files 0700 actual actual -"

    # Donetick stores its SQLite database under /var/lib/donetick. 0750,
    # matching modules/household/donetick.nix's explicit StateDirectoryMode
    # override -- systemd's own default for StateDirectory is 0755, so
    # without that override this rule would be cosmetic and get re-stamped
    # to 0755 on every service start (the exact defect found and fixed for
    # Homebox in 11-01).
    "d /var/lib/donetick 0750 donetick donetick -"

    # Ensure media directories have correct permissions
    "d /mnt/media 0775 media media -"
    "d /mnt/media/movies 2775 media media -"
    "d /mnt/media/tv 2775 media media -"
    "d /mnt/media/music 2775 media media -"
    "d /mnt/media/books 2775 media media -"

    # NVMe download staging (rpool/safe/downloads, 500G quota). SABnzbd
    # and NZBGet write here directly; Radarr/Sonarr import from here into
    # the media mirror, mirroring the category structure above.
    "d /mnt/downloads 2775 media media -"
    "d /mnt/downloads/incomplete 2775 media media -"
    "d /mnt/downloads/complete 2775 media media -"
    "d /mnt/downloads/complete/tv 2775 media media -"
    "d /mnt/downloads/complete/movies 2775 media media -"
    "d /mnt/downloads/complete/prowlarr 2775 media media -"
    "d /mnt/downloads/complete/default 2775 media media -"

    # Service-specific directories with proper permissions. The group is media
    # rather than the service's own group so the *arr stack and the download
    # clients can read each other's working directories.
    "d /var/lib/sonarr 0755 sonarr media -"
    "d /var/lib/radarr 0755 radarr media -"
    "d /var/lib/bazarr 0700 bazarr media -"
    "d /var/lib/sabnzbd 0755 sabnzbd media -"
    "d /var/lib/nzbget 0755 nzbget media -"
    "d /mnt/backups 0755 root root -"
    "d /persist 0755 root root -"

    # Frigate NVR
    "d /var/lib/frigate 0755 frigate frigate -"

    # Home Assistant needs no rule here: modules/automation/home-assistant.nix
    # already owns /var/lib/hass and the subdirectories under it.

    # Ensure Samba directories exist. Samba keeps its own entry in the
    # persistence list above rather than a dataset, because its tdb files are
    # written by smbd, nmbd and winbindd and belong to none of them.
    "d /persist/var/lib/samba 0755 root root -"
    "d /persist/var/lib/samba/private 0700 root root -"
  ];

  # Bind mount persistent directories
  fileSystems."/etc/nixos" = {
    device = "/persist/etc/nixos";
    fsType = "none";
    options = [ "bind" ];
    neededForBoot = true;
  };

  fileSystems."/var/log" = {
    device = "/persist/var/log";
    fsType = "none";
    options = [ "bind" ];
    neededForBoot = true;
  };
}
