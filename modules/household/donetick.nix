# SPDX-License-Identifier: GPL-3.0-or-later
#
# Donetick has no upstream nixpkgs module, so this declares a small
# first-class options interface matching this repo's established household
# service shape (Mealie/Homebox/Actual), backed by the locally packaged
# derivation in packages/donetick (see 11-04-SUMMARY.md).

{
  config,
  lib,
  ...
}:

let
  cfg = config.services.donetick;
in
{
  options.services.donetick = {
    enable = lib.mkEnableOption "donetick";

    package = lib.mkOption {
      type = lib.types.package;
      description = "The donetick package to run.";
    };
  };

  config = lib.mkIf cfg.enable {
    users.groups.donetick = { };

    users.users.donetick = {
      isSystemUser = true;
      group = "donetick";
      home = "/var/lib/donetick";
      description = "Donetick";
    };

    systemd.services.donetick = {
      description = "Donetick chore tracker";
      after = [
        "network.target"
        "sops-nix.service"
      ];
      wants = [ "sops-nix.service" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        ExecStart = "${cfg.package}/bin/donetick";
        EnvironmentFile = config.sops.templates."donetick.env".path;
        DynamicUser = false;
        User = "donetick";
        Group = "donetick";
        StateDirectory = "donetick";
        # systemd's own default for StateDirectoryMode is 0755, not 0750 --
        # confirmed the hard way in 11-01 (Homebox), where a 0750 tmpfiles
        # rule alone was cosmetic and got re-stamped to 0755 by systemd on
        # every service start. Forced explicitly here so the tmpfiles rule
        # in hosts/ser8/impermanence.nix isn't fighting systemd, narrowing
        # /var/lib/donetick (household task/chore data) to owner+group.
        StateDirectoryMode = "0750";
        Restart = "on-failure";
        RestartSec = "10s";

        # Security hardening, matching modules/media/jellyfin-exporter.nix
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadWritePaths = [ "/var/lib/donetick" ];
      };
    };

    networking.firewall.allowedTCPPorts = [ 2021 ];
  };
}
