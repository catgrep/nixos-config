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
  };

  jellyfinInitLog = "/var/log/jellyfin.txt";
  jellyfinInitMarker = "/var/lib/jellyfin/init-done";

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

  services.declarative-jellyfin = {
    enable = lib.mkDefault true;

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
    jellyfin_api_key = jellyfinCredentialSecret;
  };

  systemd = {
    services.jellyfin = {
      preStart = lib.mkBefore ''
        ${pkgs.coreutils}/bin/chmod 0600 ${jellyfinInitLog}
      '';

      postStart = ''
        set -euo pipefail

        while [ -e ${jellyfinInitMarker} ]; do
          ${pkgs.coreutils}/bin/sleep 0.1
        done

        attempts=0
        while [ ! -e ${jellyfinInitMarker} ] && [ "$attempts" -lt 180 ]; do
          ${pkgs.coreutils}/bin/sleep 1
          attempts=$((attempts + 1))
        done

        : >${jellyfinInitLog}
      '';
    };
  };
}
