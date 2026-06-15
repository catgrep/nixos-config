# SPDX-License-Identifier: GPL-3.0-or-later

{ config, lib, ... }:

let
  cfg = config.services.nzbget;
in
{
  config = lib.mkIf cfg.enable {
    users.users.nzbget = {
      extraGroups = [ "media" ];
    };

    networking.firewall.allowedTCPPorts = [ 6789 ];
  };
}
