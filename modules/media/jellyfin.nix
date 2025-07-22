{ config, lib, pkgs, ... }:

{
  services.jellyfin = {
    enable = lib.mkDefault true;
    user = "bdhill";
    group = "users";
  };

  # Add bdhill to render group for hardware acceleration
  users.users.bdhill.extraGroups = [ "render" ];

  # Ensure media directories exist and have proper permissions
  systemd.tmpfiles.rules = [
    "d /mnt/media 0755 bdhill users -"
    "d /mnt/media/movies 0755 bdhill users -"
    "d /mnt/media/tv 0755 bdhill users -"
    "d /mnt/media/music 0755 bdhill users -"
    "d /mnt/media/books 0755 bdhill users -"
  ];

  # Open Jellyfin ports
  networking.firewall.allowedTCPPorts = [ 8096 ];
}
