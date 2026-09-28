# SPDX-License-Identifier: GPL-3.0-or-later

{
  description = "Home Manager configuration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";
    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Share application pins with the hosts and development shell.
    mvs.url = "github:fzakaria/nixpkgs-multiverse";
  };

  outputs =
    {
      nixpkgs,
      home-manager,
      mvs,
      ...
    }:
    let
      system = "aarch64-darwin";
      pkgs = nixpkgs.legacyPackages.${system};
    in
    {
      homeConfigurations."bobby" = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        extraSpecialArgs.pinned = mvs.lib.readLock {
          inherit system;
          file = ../multiverse.lock;
        };
        modules = [
          (builtins.path {
            path = ./default.nix;
            name = "home-config";
          })
        ];
      };
    };
}
