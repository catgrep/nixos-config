# SPDX-License-Identifier: GPL-3.0-or-later

{ ... }:

{
  imports = [
    ./cameras.nix
    ./home-assistant.nix
    ./frigate.nix
    ./frigate-exporter.nix
  ];
}
