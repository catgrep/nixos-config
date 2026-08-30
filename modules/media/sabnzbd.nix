# SPDX-License-Identifier: GPL-3.0-or-later

{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.sabnzbd;
in
{
  config = {
    services.sabnzbd.group = lib.mkIf cfg.enable (lib.mkForce "media");

    users.users.sabnzbd = lib.mkIf cfg.enable {
      group = lib.mkForce cfg.group;
      # Pinned to the live-confirmed identity (uid 985) after this account's
      # files were found owned by 38:194: with no static pin, NixOS's
      # declarative id allocator can reassign an auto-allocated uid whenever
      # the fleet's declared user/group set changes elsewhere, even though
      # nothing here changed. That has happened twice on ser8. Pinning the
      # identity fixes it at the source; a standing re-chown rule would only
      # paper over each recurrence.
      #
      # No `gid` field here: `users.users.<name>` has no such option in
      # NixOS (only `users.groups.<name>.gid` does). The primary group is
      # forced to "media" above, and modules/common/users.nix already pins
      # `groups.media.gid = 1100`, so the effective gid is already static
      # via that group -- adding a nonexistent `gid` field here would be a
      # hard NixOS eval error, not a no-op.
      uid = 985;
    };

    systemd.services.sabnzbd = lib.mkIf cfg.enable {
      serviceConfig = {
        ExecStart = lib.mkForce "${pkgs.sabnzbd}/bin/sabnzbd --log-all --disable-file-log -f ${cfg.configFile}";
        StandardOutput = "journal";
        StandardError = "journal";
        Type = lib.mkForce "simple";
        GuessMainPID = lib.mkForce "yes";
      };
    };
    # Open SABnzbd port when enabled
    networking.firewall.allowedTCPPorts = lib.mkIf cfg.enable [ 8085 ];
  };
}
