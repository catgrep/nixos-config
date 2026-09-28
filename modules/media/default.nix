# SPDX-License-Identifier: GPL-3.0-or-later

{ config, ... }:

{
  # The exportarr modules select this attribute directly.
  nixpkgs.overlays = [ (_: _: { inherit (config.multiverse.locked) exportarr; }) ];

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
