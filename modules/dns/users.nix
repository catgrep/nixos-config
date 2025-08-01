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

  # Ensure AdGuard Home data directory has correct permissions
  systemd.tmpfiles.rules = [
    "d /var/lib/private/AdGuardHome 0700 adguardhome adguardhome -"
    "d /var/lib/AdGuardHome 0755 adguardhome adguardhome -"
  ];
}
