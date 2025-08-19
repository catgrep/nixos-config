# SPDX-License-Identifier: GPL-3.0-or-later

{
  config,
  lib,
  pkgs,
  ...
}:

let
  bdhillUser = import ../../users/bdhill.nix { inherit config lib pkgs; };
in
{
  users = {
    mutableUsers = false;

    # Create media and samba and groups for Samba
    groups.media = {
      gid = 1100;
    };

    # Create jellyfin group
    groups.jellyfin = {
      gid = 1101;
    };

    users = {
      root = {
        # # Disable root login
        hashedPassword = "!";
      };

      # Import user config from dedicated user file
      bdhill = bdhillUser.systemConfig;

      # Media is for users uploading content to the media drives over SMB
      media = {
        isNormalUser = true;
        group = "media";
        home = "/var/empty";

        description = "Media user for Samba shares";
        uid = 1100;
      };
    };
  };

  # Enable zsh system-wide but let home-manager handle user configuration
  programs.zsh.enable = true;

  # Enable sudo for wheel group
  security.sudo.wheelNeedsPassword = false;
}
