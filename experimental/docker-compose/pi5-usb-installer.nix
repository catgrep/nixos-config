# SPDX-License-Identifier: GPL-3.0-or-later

{
  lib,
  inputs,
  nixos-raspberrypi,
  ...
}:

# Build Pi5 USB installer image for NVMe boot
(nixos-raspberrypi.lib.nixosInstaller {
  specialArgs = { inherit inputs nixos-raspberrypi; };
  modules = [
    nixos-raspberrypi.nixosModules.raspberry-pi-5.base
    ../modules/raspberrypi/usb-installer.nix
  ];
}).config.system.build.sdImage