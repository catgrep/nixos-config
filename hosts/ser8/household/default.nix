# SPDX-License-Identifier: GPL-3.0-or-later

{ config, ... }:

let
  inherit ((builtins.fromJSON (builtins.readFile ../../../multiverse.lock))) pins;
  nginxPkgs = config.multiverse.instance.at pins.nginx.rev;
in
{
  services.nginx.package = config.multiverse.locked.nginx;
  # Nginx loads compiled modules from the same package revision as its server.
  nixpkgs.overlays = [
    (_: _: {
      inherit (nginxPkgs) nginxModules;
    })
  ];

  imports = [
    ./postgresql.nix
    ./mealie.nix
    ./homebox.nix
    ./actual.nix
    ./donetick.nix
  ];
}
