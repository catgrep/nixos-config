# SPDX-License-Identifier: GPL-3.0-or-later

{
  config,
  lib,
  ...
}:

{
  # Create dedicated radarr system user
  users.users.radarr = lib.mkIf config.services.radarr.enable {
    isSystemUser = true;
    group = "media";
    home = "/var/lib/radarr/.config/Radarr";
    description = "Radarr";
  };

  services.radarr = {
    enable = lib.mkDefault false;
    user = "radarr";
    group = lib.mkForce "media";
  };

  # nixpkgs 26.05 sets UMask = "0022" in the servarr module. Force 0002 back: the
  # media pipeline hands files between services sharing the `media` group, so the
  # group-write bit must survive.
  systemd.services.radarr.serviceConfig.UMask = lib.mkIf config.services.radarr.enable (
    lib.mkForce "0002"
  );

  # Open Radarr port when enabled
  networking.firewall.allowedTCPPorts = lib.mkIf config.services.radarr.enable [ 7878 ];
}
