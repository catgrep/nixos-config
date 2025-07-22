{ config, lib, pkgs, inputs, ... }:

{
  nix = {
    settings = {
      experimental-features = [ "nix-command" "flakes" ];
      auto-optimise-store = true;
      trusted-users = [ "root" "@wheel" ];
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

  nixpkgs.config.allowUnfree = true;

  # Automatic system updates
  system.autoUpgrade = {
    enable = true;
    dates = "04:00";
    flake = "github:your-username/nixos-config";
    flags = [ "--update-input" "nixpkgs" ];
    allowReboot = false; # Set to true if you want automatic reboots
  };
}
