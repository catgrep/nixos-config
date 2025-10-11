# SPDX-License-Identifier: GPL-3.0-or-later

{
  config,
  lib,
  pkgs,
  ...
}:

{
  # Create dedicated sabnzbd system user
  users.users.sabnzbd = lib.mkIf config.services.sabnzbd.enable {
    isSystemUser = true;
    group = "sabnzbd";
    home = "/var/lib/sabnzbd";
    description = "SABnzbd";
    extraGroups = [
      "media"
    ];
  };

  services.sabnzbd = {
    enable = lib.mkDefault false;
    user = "sabnzbd";
    group = "sabnzbd";
  };

  # Open SABnzbd port when enabled
  networking.firewall.allowedTCPPorts = lib.mkIf config.services.sabnzbd.enable [ 8080 ];
}
