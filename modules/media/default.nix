# SPDX-License-Identifier: GPL-3.0-or-later

{ ... }:

{
  imports = [
    ./jellyfin.nix
    ./jellyfin-exporter.nix
    ./sonarr.nix
    ./radarr.nix
    ./bazarr.nix
    ./prowlarr.nix
    ./sabnzbd.nix
    ./nzbget.nix
  ];
}
