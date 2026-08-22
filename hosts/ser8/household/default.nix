# SPDX-License-Identifier: GPL-3.0-or-later

{ ... }:

{
  imports = [
    ./postgresql.nix
    ./mealie.nix
    ./homebox.nix
    ./actual.nix
    ./donetick.nix
  ];
}
