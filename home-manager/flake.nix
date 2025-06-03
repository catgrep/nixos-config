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

  outputs = { nixpkgs, home-manager, ... }:
    let
      system = "aarch64-darwin";
      pkgs = nixpkgs.legacyPackages.${system};
    in {
    homeConfigurations."bobby" = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        modules = [
            (builtins.path {
                path = ./default.nix;
                name = "home-config";
            })
        ];
    };
    devShells.${system}.default = pkgs.mkShell {
        buildInputs = with pkgs; [
            colmena
            nixfmt-rfc-style
            git
            jq
        ];
        shellHook = ''
        echo "Colmena deployment environment loaded"
        '';
    };
  };
}
