# SPDX-License-Identifier: GPL-3.0-or-later

{ ... }:

{
  imports = [
    ../media.nix
    ./sonarr.nix
    ./radarr.nix
  ];
}
