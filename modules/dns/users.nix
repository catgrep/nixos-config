# SPDX-License-Identifier: GPL-3.0-or-later

{
  config,
  lib,
  pkgs,
  ...
}:

{
  users = {
    mutableUsers = false;

    users.adguardhome = {
      isSystemUser = true;
      group = "adguardhome";
      home = "/var/lib/private/AdGuardHome";
    };
    groups.adguardhome = { };
  };

  systemd.services.adguardhome.serviceConfig = {
    User = "adguardhome";
    Group = "adguardhome";
  };

}
