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

  # SOPS secrets configuration
  sops = {
    defaultSopsFile = ../../secrets/firebat.yaml;
    defaultSopsFormat = "yaml";
    age.sshKeyPaths = [ "/persist/etc/ssh/ssh_host_ed25519_key" ];

    secrets = { };
  };

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
      mode = "failover"; # AdGuard primary, with fallback for Tailscale DNS bootstrap
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
