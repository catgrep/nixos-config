# SPDX-License-Identifier: GPL-3.0-or-later

{
  config,
  lib,
  pkgs,
  ...
}:

{
  # Create dedicated radarr system user
  users.users.radarr = lib.mkIf config.services.radarr.enable {
    isSystemUser = true;
    group = "radarr";
    home = "/var/lib/radarr/.config/Radarr";
    description = "Radarr";
    extraGroups = [
      "media"
    ];
  };

  services.radarr = {
    enable = lib.mkDefault false;
    user = "radarr";
    group = "radarr";
  };

  # Open Radarr port when enabled
  networking.firewall.allowedTCPPorts = lib.mkIf config.services.radarr.enable [ 7878 ];
}
