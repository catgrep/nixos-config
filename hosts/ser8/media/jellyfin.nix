# SPDX-License-Identifier: GPL-3.0-or-later

{
  config,
  lib,
  pkgs,
  ...
}:

let
  jellyfinCredentialSecret = {
    owner = config.services.jellyfin.user;
    group = config.services.jellyfin.group;
    mode = "0400";
    # declarative-jellyfin's init script reads every credential file at
    # service start; without a restart a rotated secret never reaches it.
    restartUnits = [ "jellyfin.service" ];
  };

  jellyfinInitLog = "/var/log/jellyfin.txt";
  jellyfinInitMarker = "/var/lib/jellyfin/init-done";
  jellyfinPluginsDir = "/var/lib/jellyfin/plugins";

  # Sonarr names episode files from TheTVDB, and TheMovieDb splits the same
  # series into different seasons, so Jellyfin has to read episode metadata
  # from TheTVDB or most anime episodes match nothing or the wrong episode.
  # nixpkgs packages no Jellyfin plugins and declarative-jellyfin never reads
  # its own `plugins` option, so the plugin is fetched and installed here.
  # Version 22 is the newest build whose target ABI (10.11.8.0) the pinned
  # Jellyfin loads; 23 and later target Jellyfin 12.
  tvdbPluginVersion = "22.0.0.0";
  tvdbPlugin = pkgs.fetchzip {
    url = "https://repo.jellyfin.org/files/plugin/thetvdb/thetvdb_${tvdbPluginVersion}.zip";
    hash = "sha256-X7XDq1rdwg5WrueKMI2NmZYvBGe0yzqe3QfF69+qgyE=";
    stripRoot = false;
  };
  tvdbPluginDir = "${jellyfinPluginsDir}/TheTVDB_${tvdbPluginVersion}";

  coreutils = config.multiverse.locked.coreutils;

  householdUser =
    {
      isAdministrator,
      enableRemoteAccess,
      enableRemoteControlOfOtherUsers,
      subtitleMode,
      hashedPasswordFile,
    }:
    {
      mutable = false;
      preferences.enabledLibraries = [ ];
      permissions = {
        inherit
          isAdministrator
          enableRemoteAccess
          enableRemoteControlOfOtherUsers
          ;
        enableMediaPlayback = true;
        enableAudioPlaybackTranscoding = true;
        enableVideoPlaybackTranscoding = true;
        enableContentDeletion = true;
        enableContentDownloading = true;
        enableSyncTranscoding = true;
        enableMediaConversion = true;
        enableAllFolders = true;
        enableAllDevices = true;
      };
      inherit hashedPasswordFile subtitleMode;
      enableAutoLogin = true;
      enableLocalPassword = true;
      enableNextEpisodeAutoPlay = true;
    };
in
{
  services.jellyfin.enable = true;

  services.jellyfin-exporter = {
    enable = true;
    apiKeyFile = config.sops.secrets.jellyfin_api_key.path;
  };

  homelab.monitoring.systemd.units = lib.mkMerge [
    (lib.mkIf config.services.jellyfin.enable {
      "jellyfin.service".expectedRunning = true;
    })
    (lib.mkIf config.services.jellyfin-exporter.enable {
      "jellyfin-exporter.service".expectedRunning = true;
    })
  ];

  services.declarative-jellyfin = {
    enable = lib.mkDefault true;

    # Off, because every activation tarred the whole Jellyfin state -- roughly
    # 1.8 GB a time, five of them on one day -- into the same tree that gets
    # snapshotted and replicated. That churn dominated everything else on the
    # persisted disk and would dominate every snapshot delta and every
    # replication stream. What the tarballs were for, rolling back a bad
    # configuration, is already covered by the snapshots of this state and by
    # the system's own generations.
    backups = false;

    users = {
      admin = householdUser {
        isAdministrator = true;
        enableRemoteAccess = true;
        enableRemoteControlOfOtherUsers = true;
        hashedPasswordFile = config.sops.secrets.jellyfin_admin_password.path;
        subtitleMode = "always";
      };

      jordan = householdUser {
        isAdministrator = false;
        enableRemoteAccess = true;
        enableRemoteControlOfOtherUsers = false;
        hashedPasswordFile = config.sops.secrets.jellyfin_jordan_password.path;
        subtitleMode = "default";
      };

      sawnia = householdUser {
        isAdministrator = false;
        enableRemoteAccess = true;
        enableRemoteControlOfOtherUsers = false;
        hashedPasswordFile = config.sops.secrets.jellyfin_sawnia_password.path;
        subtitleMode = "default";
      };
    };

    apikeys.jellyfinarr.keyPath = config.sops.secrets.jellyfin_api_key.path;
  };

  sops.secrets = {
    jellyfin_admin_password = jellyfinCredentialSecret;
    jellyfin_jordan_password = jellyfinCredentialSecret;
    jellyfin_sawnia_password = jellyfinCredentialSecret;
    # The exporter also snapshots the key at start via LoadCredential.
    jellyfin_api_key = jellyfinCredentialSecret // {
      restartUnits = [
        "jellyfin.service"
        "jellyfin-exporter.service"
      ];
    };
  };

  assertions = [
    {
      assertion =
        lib.versionAtLeast config.services.jellyfin.package.version "10.11.8"
        && lib.versionOlder config.services.jellyfin.package.version "12";
      message =
        "TheTVDB plugin ${tvdbPluginVersion} targets Jellyfin ABI 10.11.8.0 and is not loaded by"
        + " Jellyfin ${config.services.jellyfin.package.version}; moving Jellyfin to 12 needs"
        + " TheTVDB plugin 23 or later in hosts/ser8/media/jellyfin.nix";
    }
  ];

  systemd = {
    services.jellyfin = {
      # Runs as the jellyfin user with UMask=0077, so the copied files are
      # writable by the service and private to it. The plugin is copied rather
      # than linked from the store: Jellyfin rewrites meta.json whenever the
      # plugin changes state and fails plugin load when the directory is
      # read-only, and the dashboard deletes the directory on disable.
      # Copying only when missing keeps the status Jellyfin wrote into
      # meta.json across restarts, and removing every other TheTVDB_* directory
      # first means a version change in either direction never leaves two
      # copies loaded.
      preStart = lib.mkBefore ''
        ${coreutils}/bin/chmod 0600 ${jellyfinInitLog}

        ${coreutils}/bin/mkdir -p ${jellyfinPluginsDir}
        for plugin_dir in ${jellyfinPluginsDir}/TheTVDB_*; do
          if [ -d "$plugin_dir" ] && [ "$plugin_dir" != ${tvdbPluginDir} ]; then
            ${coreutils}/bin/rm -r "$plugin_dir"
          fi
        done
        if [ ! -d ${tvdbPluginDir} ]; then
          ${coreutils}/bin/cp -r --no-preserve=mode ${tvdbPlugin} ${tvdbPluginDir}
        fi
      '';

      postStart = ''
        set -euo pipefail

        while [ -e ${jellyfinInitMarker} ]; do
          ${coreutils}/bin/sleep 0.1
        done

        attempts=0
        while [ ! -e ${jellyfinInitMarker} ] && [ "$attempts" -lt 180 ]; do
          ${coreutils}/bin/sleep 1
          attempts=$((attempts + 1))
        done

        : >${jellyfinInitLog}
      '';
    };
  };

  services.jellyfin.package = config.multiverse.locked.jellyfin;
}
