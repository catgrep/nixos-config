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

  # Gateway networking configuration
  networking = {
    # Host identification
    hostName = "firebat";
    hostId = "89e571c4"; # Generate with: head -c 4 /dev/urandom | od -A none -t x4 | tr -d ' '
  };

  # custom internal settings
  networking.internal = {
    interface = "eno1";
    forwarding = true;
    adguard = {
      enabled = true;
      mode = "strict"; # only use AdGuard, no fallback
    };
  };

  # Gateway-specific packages
  environment.systemPackages = with pkgs; [
    # Network tools
    iptables
    nftables
    tcpdump
    wireshark

    # Additional monitoring tools
    bandwhich
  ];

  # System state version
  system.stateVersion = "24.11";
}
