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
    nixai.url = "github:olafkfreund/nix-ai-help";
  };

  outputs = { nixpkgs, home-manager, nixai,... }:
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
            nixai.homeManagerModules.${system}.default
            {
              # Basic nixai configuration
              services.nixai = {
                enable = true;
                mcp = {
                  enable = true;
                  port = 8081;  # Different port to avoid conflicts
                };
              };
            }
        ];
    };
  };
}
