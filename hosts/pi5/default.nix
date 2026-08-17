# SPDX-License-Identifier: GPL-3.0-or-later

{ ... }:

{
  imports = [
    ./configuration.nix
    ./configtxt.nix
  ];

  homelab.raspberryPi.variant = "5";
}
