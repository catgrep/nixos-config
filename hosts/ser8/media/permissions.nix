# SPDX-License-Identifier: GPL-3.0-or-later

{
  config,
  lib,
  pkgs,
  ...
}:

let
  mediaAccounts = [
    "bazarr"
    "jellyfin"
    "nzbget"
    "qbittorrent"
    "radarr"
    "sabnzbd"
    "sonarr"
  ];
  mediaServices = [
    "bazarr.service"
    "jellyfin.service"
    "nzbget.service"
    "qbittorrent-nox.service"
    "radarr.service"
    "sabnzbd.service"
    "sonarr.service"
  ];
  mediaRoots = [
    "/mnt/media/downloads"
    "/mnt/media/movies"
    "/mnt/media/tv"
  ];
in
{
  assertions = [
    {
      assertion = lib.all (account: config.users.users.${account}.group == "media") mediaAccounts;
      message = "Media-facing service accounts must use media as their primary group";
    }
  ];

  systemd.services.media-permissions = {
    description = "Normalize shared media permissions";
    before = mediaServices;
    requiredBy = mediaServices;

    unitConfig.RequiresMountsFor = [ "/mnt/media" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };

    script = ''
      for media_root in ${lib.escapeShellArgs mediaRoots}; do
        ${pkgs.findutils}/bin/find "$media_root" -xdev ! -group media \
          -exec ${pkgs.coreutils}/bin/chgrp --no-dereference media {} +
        ${pkgs.findutils}/bin/find "$media_root" -xdev -type d ! -perm 2775 \
          -exec ${pkgs.coreutils}/bin/chmod 2775 {} +
        ${pkgs.findutils}/bin/find "$media_root" -xdev -type f ! -perm 0664 \
          -exec ${pkgs.coreutils}/bin/chmod 0664 {} +
      done
    '';
  };
}
