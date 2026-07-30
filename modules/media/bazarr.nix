# SPDX-License-Identifier: GPL-3.0-or-later

{
  config,
  lib,
  ...
}:

{
  services.bazarr = {
    enable = lib.mkDefault false;
    user = "bazarr";
    group = "bazarr";
  };

  users.users.bazarr = lib.mkIf config.services.bazarr.enable {
    description = "Bazarr";
    extraGroups = [ "media" ];
  };

  systemd.services.bazarr.serviceConfig.UMask = lib.mkIf config.services.bazarr.enable "0002";

  networking.firewall.allowedTCPPorts = lib.mkIf config.services.bazarr.enable [
    config.services.bazarr.listenPort
  ];
}
