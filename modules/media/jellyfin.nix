# SPDX-License-Identifier: GPL-3.0-or-later

{ lib, ... }:

{
  users.users.jellyfin = {
    isSystemUser = true;
    group = "media";
    home = "/var/empty";
    description = "Jellyfin";
    extraGroups = [ "render" ];
  };

  services.jellyfin = {
    user = "jellyfin";
    group = lib.mkForce "media";
  };

  # Declarative Jellyfin configuration
  services.declarative-jellyfin = {
    # Network settings
    network = {
      enableUPnP = false;
      internalHttpPort = 8096;
      publicHttpPort = 8096;
      requireHttps = false;
      enableRemoteAccess = true;
      autoDiscovery = true;
    };
  };

  # Open Jellyfin ports
  networking.firewall.allowedTCPPorts = [ 8096 ];
}
