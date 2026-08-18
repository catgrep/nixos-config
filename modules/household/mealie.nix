# SPDX-License-Identifier: GPL-3.0-or-later

{
  config,
  lib,
  ...
}:

{
  users.groups.mealie = lib.mkIf config.services.mealie.enable { };

  users.users.mealie = lib.mkIf config.services.mealie.enable {
    isSystemUser = true;
    group = "mealie";
    home = "/var/lib/mealie";
    description = "Mealie";
  };

  services.mealie.enable = lib.mkDefault false;

  # Upstream runs Mealie under DynamicUser, which relocates state to
  # /var/lib/private/mealie behind a 0700 directory and allocates a transient
  # UID. Same override as modules/media/prowlarr.nix so household state is
  # owned, persistable across an impermanence rollback, and readable by the
  # backup job. Group is set explicitly because upstream sets only User, which
  # would otherwise leave systemd to pick the primary group.
  systemd.services.mealie.serviceConfig = lib.mkIf config.services.mealie.enable {
    DynamicUser = lib.mkForce false;
    User = "mealie";
    Group = "mealie";
  };

  # services.mealie has no openFirewall option. The reverse proxy reaches this
  # port over the LAN, so a closed port yields a 502 at the proxy while a
  # loopback probe on this host still succeeds.
  networking.firewall.allowedTCPPorts = lib.mkIf config.services.mealie.enable [
    config.services.mealie.port
  ];
}
