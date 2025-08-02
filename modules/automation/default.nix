# SPDX-License-Identifier: GPL-3.0-or-later

{ ... }:

{
  imports = [
    ./home-assistant.nix
    # Add other automation services here
    # ./node-red.nix
    # ./zigbee2mqtt.nix
  ];
}
