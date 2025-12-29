# SPDX-License-Identifier: GPL-3.0-or-later

{
  config,
  lib,
  pkgs,
  unstable,
  ...
}:

{
  # Use jellyfin/jellyfin-web from unstable to work around npmDepsHash mismatch in 25.05
  # Keep jellyfin-ffmpeg from stable (unstable has broken lcevc_dec dependency)
  # See: https://github.com/NixOS/nixpkgs/issues - jellyfin-web npmDepsHash out of date
  nixpkgs.overlays = [
    (final: prev: {
      jellyfin = unstable.jellyfin;
      jellyfin-web = unstable.jellyfin-web;
      # jellyfin-ffmpeg intentionally NOT overridden - unstable build is broken
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
