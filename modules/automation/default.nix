# SPDX-License-Identifier: GPL-3.0-or-later

{ ... }:

{
  imports = [
    ./home-assistant.nix
    ./frigate.nix
  ];
}
