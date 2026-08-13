# SPDX-License-Identifier: GPL-3.0-or-later

{ ... }:

{
  imports = [
    ./sops.nix
    ./permissions.nix
    ./jellyfin.nix
    ./sonarr.nix
    ./radarr.nix
    ./bazarr.nix
    ./prowlarr.nix
    ./nzbget.nix
    ./sabnzbd.nix
    ./qbittorrent.nix
    ./orchestration.nix
  ];
}
