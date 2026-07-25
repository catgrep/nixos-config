# SPDX-License-Identifier: GPL-3.0-or-later

_:

{
  users.users.jellyfin = {
    isSystemUser = true;
    group = "jellyfin";
    home = "/var/empty";
    description = "Jellyfin";
    extraGroups = [
      "media"
      "render"
    ];
  };

  services.jellyfin = {
    user = "jellyfin";
    group = "jellyfin";
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
