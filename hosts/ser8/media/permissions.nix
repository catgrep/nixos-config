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
    "radarr"
    "sabnzbd"
    "sonarr"
  ];
  mediaServices = [
    "bazarr.service"
    "jellyfin.service"
    "nzbget.service"
    "radarr.service"
    "sabnzbd.service"
    "sonarr.service"
  ];
  mediaRoots = [
    "/mnt/downloads"
    "/mnt/media/books"
    "/mnt/media/movies"
    "/mnt/media/music"
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

    unitConfig.RequiresMountsFor = [
      "/mnt/media"
      "/mnt/downloads"
    ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };

    # Paths under these roots carry POSIX ACLs, and on an ACL-bearing path
    # the group bits that chmod sets and that -perm reads are the ACL mask,
    # not the owning group's own entry. A directory can therefore show as
    # 2775 while the media group is still limited to r-x by its group::
    # entry, which is what decides whether a media service can write there.
    # setfacl is the only tool that sets that entry, and it also recomputes
    # the mask from every group entry, so it runs first and the chmod passes
    # below then pin the mask (and with it the visible mode) to 2775 and 0664.
    # On a path without an extended ACL setfacl is a plain group-bit change.
    script = ''
      for media_root in ${lib.escapeShellArgs mediaRoots}; do
        ${pkgs.findutils}/bin/find "$media_root" -xdev ! -group media \
          -exec ${pkgs.coreutils}/bin/chgrp --no-dereference media {} +
        ${pkgs.findutils}/bin/find "$media_root" -xdev -type d \
          -exec ${pkgs.acl}/bin/setfacl --modify g::rwx {} +
        ${pkgs.findutils}/bin/find "$media_root" -xdev -type f \
          -exec ${pkgs.acl}/bin/setfacl --modify g::rw- {} +
        ${pkgs.findutils}/bin/find "$media_root" -xdev -type d ! -perm 2775 \
          -exec ${pkgs.coreutils}/bin/chmod 2775 {} +
        ${pkgs.findutils}/bin/find "$media_root" -xdev -type f ! -perm 0664 \
          -exec ${pkgs.coreutils}/bin/chmod 0664 {} +
      done
    '';
  };
}
