# SPDX-License-Identifier: GPL-3.0-or-later

{
  description = "Home Manager configuration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
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
