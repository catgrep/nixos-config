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
    # Add sabnzbd user to media group for shared file access
    users.users.sabnzbd = lib.mkIf cfg.enable {
      extraGroups = [ "media" ];
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
