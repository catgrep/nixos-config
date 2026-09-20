# SPDX-License-Identifier: GPL-3.0-or-later

{
  config,
  lib,
  pkgs,
  ...
}:

{
  imports = [
    ./banner.nix
    ./boot.nix
    ./multiverse.nix
    ./networking.nix
    ./nix.nix
    ./packages.nix
    ./service-monitoring.nix
    ./ssh.nix
    ./users.nix
    ./locale.nix
  ];
}
