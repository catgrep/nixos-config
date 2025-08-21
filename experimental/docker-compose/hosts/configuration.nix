# SPDX-License-Identifier: GPL-3.0-or-later

{ config, pkgs, ... }:
{
  # Enable SSH daemon
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "yes";
      PasswordAuthentication = false;
      PubkeyAuthentication = true;
      UsePAM = false;
    };
    hostKeys = [
      {
        path = "/etc/ssh/ssh_host_rsa_key";
        type = "rsa";
        bits = 2048;
      }
    ];
  };

  # Configure users declaratively
  users = {
    mutableUsers = false;
    users.root = {
      isSystemUser = true;
      openssh.authorizedKeys.keyFiles = [ "/tmp/user_key.pub" ];
    };
  };

  # System packages needed for Nix building
  environment.systemPackages = with pkgs; [
    nix
    openssh
    coreutils
    findutils
    gnutar
    gzip
    git
  ];

  # Nix configuration
  nix = {
    settings = {
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      trusted-public-keys = [
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        "nixos-raspberrypi.cachix.org-1:4iMO9LXa8BqhU+Rpg6LQKiGa2lsN
      h/j2oiYLNOQ5sPI="
      ];
      substituters = [
        "https://cache.nixos.org"
        "https://nixos-raspberrypi.cachix.org"
      ];
    };
  };

  # Minimal system configuration
  boot.isContainer = true;
  networking.hostName = "nix-builder";
  system.stateVersion = "24.05";
}
