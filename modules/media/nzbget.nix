# SPDX-License-Identifier: GPL-3.0-or-later

{ config, lib, ... }:

let
  cfg = config.services.nzbget;
in
{
  config = lib.mkIf cfg.enable {
    services.nzbget.group = lib.mkForce "media";

    users.users.nzbget = {
      group = lib.mkForce cfg.group;
    };

    networking.firewall.allowedTCPPorts = [ 6789 ];
  };
}
