# SPDX-License-Identifier: GPL-3.0-or-later

{ ... }:

{
  imports = [
    ./jellyfin.nix
    ./sonarr.nix
    ./radarr.nix
    ./prowlarr.nix
    ./qbittorrent.nix
    ./alldebrid-proxy.nix
  ];
}
