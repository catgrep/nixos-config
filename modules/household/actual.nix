# SPDX-License-Identifier: GPL-3.0-or-later

{
  config,
  lib,
  ...
}:

{
  users.groups.actual = lib.mkIf config.services.actual.enable { };

  users.users.actual = lib.mkIf config.services.actual.enable {
    isSystemUser = true;
    group = "actual";
    home = "/var/lib/actual";
    description = "Actual Budget";
  };

  # Unlike Mealie and Homebox, services.actual has no auto-create-user branch:
  # leaving cfg.user null (upstream's own default) yields DynamicUser = true
  # with a systemd-allocated transient user, but setting cfg.user to a
  # non-null value flips upstream's own config block straight to
  # DynamicUser = false without creating the user/group itself. Host policy
  # sets services.actual.user/group to "actual", so this module declares the
  # matching static system user/group rather than overriding DynamicUser
  # directly (no lib.mkForce needed here, unlike mealie.nix).
  services.actual.enable = lib.mkDefault false;
  services.actual.openFirewall = lib.mkDefault false;
}
