# SPDX-License-Identifier: GPL-3.0-or-later

{
  config,
  lib,
  pkgs,
  ...
}:

{
  # Create dedicated prowlarr system group
  users.groups.prowlarr = lib.mkIf config.services.prowlarr.enable { };

  # Create dedicated prowlarr system user
  users.users.prowlarr = lib.mkIf config.services.prowlarr.enable {
    isSystemUser = true;
    group = "prowlarr";
    # Note: Prowlarr uses /var/lib/prowlarr/config.xml as its config file
    home = "/var/lib/prowlarr";
    description = "Prowlarr";
    extraGroups = [
      "media"
    ];
  };

  services.prowlarr = {
    enable = lib.mkDefault false;
  };

  # Override systemd service to use static user instead of DynamicUser
  systemd.services.prowlarr = lib.mkIf config.services.prowlarr.enable {
    serviceConfig = {
      DynamicUser = lib.mkForce false;
      User = "prowlarr";
      Group = "prowlarr";
    };
  };

  # Open Prowlarr port when enabled
  networking.firewall.allowedTCPPorts = lib.mkIf config.services.prowlarr.enable [ 9696 ];
}
