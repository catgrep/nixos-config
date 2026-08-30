# SPDX-License-Identifier: GPL-3.0-or-later

{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:

{
  nix = {
    settings = {
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      auto-optimise-store = true;
      trusted-users = [
        "root"
        "@wheel"
      ];
      # Nix rejects explicit build roots that are world-writable, such as /tmp.
      build-dir = lib.mkDefault "/nix-builds";
    };

    # Automatic garbage collection
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 30d";
    };

    # Add unstable channel
    registry.nixpkgs-unstable.flake = inputs.nixpkgs-unstable;
  };

  systemd.tmpfiles.rules = [
    "d /nix-builds 0755 root root -"
  ];

  nixpkgs.config.allowUnfree = true;
}
