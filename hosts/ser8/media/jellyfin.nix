# SPDX-License-Identifier: GPL-3.0-or-later

{
  config,
  lib,
  ...
}:

let
  householdUser =
    {
      isAdministrator,
      enableRemoteAccess,
      enableRemoteControlOfOtherUsers,
      subtitleMode,
      hashedPasswordFile,
    }:
    {
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
        enableRemoteAccess = false;
        enableRemoteControlOfOtherUsers = false;
        hashedPasswordFile = config.sops.secrets.jellyfin_jordan_password.path;
        subtitleMode = "default";
      };

      sawnia = householdUser {
        isAdministrator = false;
        enableRemoteAccess = false;
        enableRemoteControlOfOtherUsers = false;
        hashedPasswordFile = config.sops.secrets.jellyfin_sawnia_password.path;
        subtitleMode = "default";
      };
    };

    apikeys.jellyfinarr.keyPath = config.sops.secrets.jellyfin_api_key.path;
  };

  sops.secrets = {
    jellyfin_admin_password = {
      owner = "root";
      group = "root";
      mode = "0600";
    };
    jellyfin_jordan_password = {
      owner = "root";
      group = "root";
      mode = "0600";
    };
    jellyfin_sawnia_password = {
      owner = "root";
      group = "root";
      mode = "0600";
    };
    jellyfin_api_key = {
      owner = "root";
      group = "root";
      mode = "0600";
    };
  };
}
