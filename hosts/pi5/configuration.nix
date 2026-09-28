# SPDX-License-Identifier: GPL-3.0-or-later

{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:

{
  imports = [
    ./hardware-configuration.nix
    ./disko-config.nix
  ];

  # pi5 networking configuration
  networking = {
    # Host identification
    hostName = "pi5";
    hostId = "4c0630cf"; # Generate with: head -c 4 /dev/urandom | od -A none -t x4 | tr -d ' '
  };

  # custom internal settings
  networking.internal = {
    interface = "end0";
    adguard = {
      enabled = true;
      mode = "failover"; # default
    };
  };

  # Pi5-specific packages
  environment.systemPackages = with config.multiverse.locked; [
    pkgs.libraspberrypi # Follow the pinned board and boot configuration.
    pkgs.raspberrypi-eeprom # Follow the pinned board and boot configuration.

    # DNS tools
    dig
    host

    # Network monitoring
    bandwhich
    nethogs
  ];

  # System state version
  system.stateVersion = "24.11";
}
