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
in
{
  assertions = [
    {
      assertion = lib.all (account: config.users.users.${account}.group == "media") mediaAccounts;
      message = "Media-facing service accounts must use media as their primary group";
    }
  ];

  systemd.services.media-download-permissions = {
    description = "Normalize shared media download permissions";
    before = mediaServices;
    requiredBy = mediaServices;

    unitConfig.RequiresMountsFor = [ "/mnt/media" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };

    script = ''
      download_root=/mnt/media/downloads
      ${pkgs.findutils}/bin/find "$download_root" -xdev ! -group media \
        -exec ${pkgs.coreutils}/bin/chgrp media {} +
      ${pkgs.findutils}/bin/find "$download_root" -xdev -type d ! -perm 2775 \
        -exec ${pkgs.coreutils}/bin/chmod 2775 {} +
      ${pkgs.findutils}/bin/find "$download_root" -xdev -type f ! -perm 0664 \
        -exec ${pkgs.coreutils}/bin/chmod 0664 {} +
    '';
  };
}
