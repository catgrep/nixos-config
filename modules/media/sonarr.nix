# SPDX-License-Identifier: GPL-3.0-or-later

{
  config,
  lib,
  ...
}:

{
  # Create dedicated sonarr system user
  users.users.sonarr = lib.mkIf config.services.sonarr.enable {
    isSystemUser = true;
    group = "sonarr";
    home = "/var/lib/sonarr/.config/NzbDrone";
    description = "Sonarr";
    extraGroups = [
      "media"
    ];
  };

  services.sonarr = {
    enable = lib.mkDefault false;
    user = "sonarr";
    group = "sonarr";
  };

  systemd.services.sonarr.serviceConfig.UMask = lib.mkIf config.services.sonarr.enable "0002";

  # Open Sonarr port when enabled
  networking.firewall.allowedTCPPorts = lib.mkIf config.services.sonarr.enable [ 8989 ];
}
