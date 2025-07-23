{
  config,
  lib,
  pkgs,
  ...
}:

{
  services.radarr = {
    enable = lib.mkDefault false;
    user = "bdhill";
    group = "users";
  };

  # Open Radarr port when enabled
  networking.firewall.allowedTCPPorts = lib.mkIf config.services.radarr.enable [ 7878 ];

  # Ensure download directories exist
  systemd.tmpfiles.rules = lib.mkIf config.services.radarr.enable [
    "d /mnt/downloads/movies 0755 bdhill users -"
  ];
}
