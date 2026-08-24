# SPDX-License-Identifier: GPL-3.0-or-later

# Temporary safety disable, in effect only during the media storage
# migration's data restore window.
#
# Every service below can write into the media library. Declaring them
# disabled here (rather than masking them at runtime with `systemctl mask`)
# means the disable is baked into the built system generation itself, so it
# survives an unplanned reboot during the multi-hour restore -- a live
# runtime mask does not, because this host wipes its root filesystem on
# every real boot.
#
# Remove this file (and its import in ./default.nix) once the restore is
# verified and the services are ready to start back up in their documented
# order. Do not remove it earlier, even if the restore appears to have
# finished -- the removal is itself the documented service-start step.
{ lib, ... }:

{
  systemd.services =
    lib.genAttrs
      [
        "jellyfin"
        "radarr"
        "sonarr"
        "bazarr"
        "prowlarr"
        "sabnzbd"
        "nzbget"
        "samba-smbd"
        "samba-wsdd"
        "media-config"
        "servarrs-setup"
        "download-clients-setup"
        "mealie"
        "homebox"
        "actual"
        "donetick"
        "frigate"
        "home-assistant"
        "mosquitto"
      ]
      (_name: {
        enable = lib.mkForce false;
      });
}
