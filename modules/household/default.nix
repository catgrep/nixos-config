# SPDX-License-Identifier: GPL-3.0-or-later

{ ... }:

{
  imports = [
    ./mealie.nix
    ./homebox.nix
    ./actual.nix
    ./donetick.nix
  ];
}
