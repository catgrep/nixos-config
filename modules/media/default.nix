# SPDX-License-Identifier: GPL-3.0-or-later

{ ... }:

{
  imports = [
    ./jellyfin.nix
    ./jellyfin-exporter.nix
    ./sonarr.nix
    ./radarr.nix
    ./prowlarr.nix
    ./qbittorrent.nix
    ./sabnzbd.nix
    ./exportarr.nix
    # ./alldebrid-proxy.nix
  ];
}
