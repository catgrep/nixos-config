# SPDX-License-Identifier: GPL-3.0-or-later

{
  config,
  lib,
  ...
}:

{
  services.homebox.enable = lib.mkDefault false;

  # Unlike mealie.nix, no static user/group override is declared here.
  # Upstream's services.homebox module already creates a static system user
  # homebox/homebox (no DynamicUser) whenever services.homebox.user is left
  # at its default, so there is nothing to override.

  # Upstream's module never sets StateDirectoryMode, so systemd's own
  # default of 0755 applies to /var/lib/homebox -- unlike Mealie's DATA_DIR,
  # which is only 0750 because the PostgreSQL module explicitly sets that
  # mode for major >= 11. Homebox stores household inventory data (item
  # names, locations, attachment photos), so this narrows the state
  # directory to owner+group only, matching Mealie's and PostgreSQL's
  # posture rather than leaving it world-readable.
  systemd.services.homebox.serviceConfig.StateDirectoryMode =
    lib.mkIf config.services.homebox.enable "0750";

  # services.homebox.settings is a freeform attrsOf (nullOr str) with no
  # dedicated port option, and the module itself never sets HBOX_WEB_PORT at
  # all (it only documents 7745 as the *application's* internal default).
  # Host policy sets HBOX_WEB_PORT explicitly, so this firewall rule is a
  # literal that must be kept in sync with that value rather than read back
  # from config.
  networking.firewall.allowedTCPPorts = lib.mkIf config.services.homebox.enable [
    7745
  ];
}
