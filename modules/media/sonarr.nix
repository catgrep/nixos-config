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
    group = "media";
    home = "/var/lib/sonarr/.config/NzbDrone";
    description = "Sonarr";
  };

  services.sonarr = {
    enable = lib.mkDefault false;
    user = "sonarr";
    group = lib.mkForce "media";
  };

  # nixpkgs 26.05 sets UMask = "0022" in the servarr module. Force 0002 back: the
  # media pipeline hands files between services sharing the `media` group, so the
  # group-write bit must survive.
  systemd.services.sonarr.serviceConfig.UMask = lib.mkIf config.services.sonarr.enable (
    lib.mkForce "0002"
  );

  # Open Sonarr port when enabled
  networking.firewall.allowedTCPPorts = lib.mkIf config.services.sonarr.enable [ 8989 ];
}
