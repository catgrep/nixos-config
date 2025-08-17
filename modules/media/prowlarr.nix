# SPDX-License-Identifier: GPL-3.0-or-later

{
  config,
  lib,
  pkgs,
  ...
}:

{
  options.services.prowlarr = {
    useVpnNamespace = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Run Prowlarr in NordVPN network namespace for anonymization";
    };
  };

  config = {
    # Create dedicated prowlarr system group
    users.groups.prowlarr = lib.mkIf config.services.prowlarr.enable { };

    # Create dedicated prowlarr system user
    users.users.prowlarr = lib.mkIf config.services.prowlarr.enable {
      isSystemUser = true;
      group = "prowlarr";
      # Note: Prowlarr uses /var/lib/prowlarr/config.xml as its config file
      home = "/var/lib/prowlarr";
      description = "Prowlarr";
      extraGroups = [
        "media"
      ];
    };

    services.prowlarr = {
      enable = lib.mkDefault false;
    };

    # Override systemd service to use static user instead of DynamicUser
    systemd.services.prowlarr = lib.mkIf config.services.prowlarr.enable (
      lib.mkMerge [
        {
          serviceConfig = {
            DynamicUser = lib.mkForce false;
            User = "prowlarr";
            Group = "prowlarr";
          };
        }

        # NordVPN namespace configuration
        (lib.mkIf config.services.prowlarr.useVpnNamespace {
          after = [ "wgnord.service" ];
          bindsTo = [ "wgnord.service" ];
          serviceConfig = {
            # Join NordVPN network namespace
            NetworkNamespacePath = "/var/run/netns/wgnord";
          };
        })
      ]
    );

    # Open Prowlarr port when enabled
    networking.firewall.allowedTCPPorts = lib.mkIf config.services.prowlarr.enable [ 9696 ];
  };
}
