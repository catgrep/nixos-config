# SPDX-License-Identifier: GPL-3.0-or-later

{
  config,
  lib,
  pkgs,
  ...
}:

{
  # Add sabnzbd user to media group for shared file access
  users.users.sabnzbd = lib.mkIf config.services.sabnzbd.enable {
    extraGroups = [ "media" ];
  };

  services.sabnzbd = {
    enable = lib.mkDefault false;
  };

  # Open SABnzbd port when enabled
  networking.firewall.allowedTCPPorts = lib.mkIf config.services.sabnzbd.enable [ 8085 ];
}
