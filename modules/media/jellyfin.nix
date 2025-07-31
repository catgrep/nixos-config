{
  config,
  lib,
  pkgs,
  ...
}:

{

  users.users.jellyfin = {
    isSystemUser = true;
    group = "media";
    home = "/var/empty";

    description = "Jellyfin";
    extraGroups = [
      "jellyfin"
      "render"
    ];
  };

  services.jellyfin = {
    enable = true;
    user = "jellyfin";
    group = "media";
  };

  # Open Jellyfin ports
  networking.firewall.allowedTCPPorts = [ 8096 ];
}
