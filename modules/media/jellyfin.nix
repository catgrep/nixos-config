# SPDX-License-Identifier: GPL-3.0-or-later

{
  config,
  lib,
  pkgs,
  unstable,
  ...
}:

{
  # Use jellyfin stack from unstable to work around build issues in 25.05:
  # - jellyfin-web: npmDepsHash mismatch
  # - lcevcdec: 25.05 has 3.3.5, but jellyfin-ffmpeg requires >= 4.0.0
  # See: https://github.com/NixOS/nixpkgs/pull/369159
  nixpkgs.overlays = [
    (final: prev: {
      jellyfin = unstable.jellyfin;
      jellyfin-web = unstable.jellyfin-web;
      jellyfin-ffmpeg = unstable.jellyfin-ffmpeg;
      lcevcdec = unstable.lcevcdec;
    })
  ];
  users.users.jellyfin = {
    isSystemUser = true;
    group = "jellyfin";
    home = "/var/empty";
    description = "Jellyfin";
    extraGroups = [
      "media"
      "render"
    ];
  };

  services.jellyfin = {
    enable = true;
    user = "jellyfin";
    group = "jellyfin";
  };

  # Declarative Jellyfin configuration
  services.declarative-jellyfin = {
    enable = lib.mkDefault true;

    # Network settings
    network = {
      enableUPnP = false;
      internalHttpPort = 8096;
      publicHttpPort = 8096;
      requireHttps = false;
      enableRemoteAccess = true;
      autoDiscovery = true;
    };

    # Users configuration
    users = {
      admin = {
        preferences = {
          enabledLibraries = [ ];
        };
        permissions = {
          isAdministrator = true;
          enableRemoteAccess = true;
          enableMediaPlayback = true;
          enableAudioPlaybackTranscoding = true;
          enableVideoPlaybackTranscoding = true;
          enableContentDeletion = true;
          enableContentDownloading = true;
          enableRemoteControlOfOtherUsers = true;
          enableSyncTranscoding = true;
          enableMediaConversion = true;
          enableAllFolders = true;
          enableAllDevices = true;
        };
        # Hash generated before adding it to sops with './scripts/sops/genhash.py'
        hashedPasswordFile = lib.mkIf (config ? sops) config.sops.secrets.jellyfin_admin_password.path;
        enableAutoLogin = true;
        enableLocalPassword = true;
        subtitleMode = "always";
        enableNextEpisodeAutoPlay = true;
      };

      jordan = {
        preferences = {
          enabledLibraries = [ ];
        };
        permissions = {
          isAdministrator = false;
          enableRemoteAccess = false;
          enableMediaPlayback = true;
          enableAudioPlaybackTranscoding = true;
          enableVideoPlaybackTranscoding = true;
          enableContentDeletion = true;
          enableContentDownloading = true;
          enableRemoteControlOfOtherUsers = false;
          enableSyncTranscoding = true;
          enableMediaConversion = true;
          enableAllFolders = true;
          enableAllDevices = true;
        };
        # Hash generated before adding it to sops with './scripts/sops/genhash.py'
        hashedPasswordFile = lib.mkIf (config ? sops) config.sops.secrets.jellyfin_jordan_password.path;
        enableAutoLogin = true;
        enableLocalPassword = true;
        subtitleMode = "default";
        enableNextEpisodeAutoPlay = true;
      };
    };
  };

  # Open Jellyfin ports
  networking.firewall.allowedTCPPorts = [ 8096 ];
}
