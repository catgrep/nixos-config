{ config, lib, pkgs, ... }:

{
  services.sonarr = {
    enable = lib.mkDefault false;
    user = "bobby";
    group = "users";
  };

  # Open Sonarr port when enabled
  networking.firewall.allowedTCPPorts = lib.mkIf config.services.sonarr.enable [ 8989 ];

  # Ensure download directories exist
  systemd.tmpfiles.rules = lib.mkIf config.services.sonarr.enable [
    "d /mnt/downloads/tv 0755 bobby users -"
  ];
}
