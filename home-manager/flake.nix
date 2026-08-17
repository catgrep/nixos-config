# SPDX-License-Identifier: GPL-3.0-or-later

{
  description = "Home Manager configuration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";
    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    colmena = {
      url = "github:zhaofengli/colmena";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      nixpkgs,
      home-manager,
      ...
    }:
    let
      system = "aarch64-darwin";
      pkgs = nixpkgs.legacyPackages.${system};
    in
    {
      homeConfigurations."bobby" = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        modules = [
          (builtins.path {
            path = ./default.nix;
            name = "home-config";
          })
        ];
      };
    };
}
