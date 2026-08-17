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
