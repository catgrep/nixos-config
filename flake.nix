{
  description = "Bobby's Homelab NixOS configurations";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixos-hardware.url = "github:NixOS/nixos-hardware/daa628a725ab4948e0e2b795e8fb6f4c3e289a7a";

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    colmena = {
      url = "github:zhaofengli/colmena";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, nixpkgs-unstable, disko, sops-nix, colmena,... }@inputs:
    let
      # Helper function to create a nixos system configuration
      mkSystem = { hostname, system ? "x86_64-linux", modules ? [] }:
        nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = {
            inherit inputs;
            unstable = import nixpkgs-unstable {
              inherit system;
              config.allowUnfree = true;
            };
          };
          modules = [
            ./hosts/${hostname}/configuration.nix
            ./hosts/modules/common
            ./hosts/modules/servers
            disko.nixosModules.disko
            sops-nix.nixosModules.sops
          ] ++ modules;
        };

      # Helper for ARM systems (Raspberry Pi)
      mkArmSystem = { hostname, modules ? [] }:
        mkSystem {
          inherit hostname modules;
          system = "aarch64-linux";
        };
    in
    {
      nixosConfigurations = {
        # Main media server (Beelink SER8)
        beelink = mkSystem {
          hostname = "beelink";
          modules = [
            ./hosts/modules/media
          ];
        };

        # Gateway/Load Balancer (Firebat)
        firebat = mkSystem {
          hostname = "firebat";
          modules = [
            ./hosts/modules/gateway
          ];
        };

        # DNS Server (Raspberry Pi 4B)
        pi4 = mkArmSystem {
          hostname = "pi4";
          modules = [
            ./hosts/modules/dns
            inputs.nixos-hardware.nixosModules.raspberry-pi-4
          ];
        };

        # Keep existing nixhost for compatibility during transition
        nixhost = mkSystem {
          hostname = "nixhost";
        };
      };

      # Colmena deployment configuration
      colmenaHive = colmena.lib.makeHive {
        meta = {
          nixpkgs = import nixpkgs-unstable {
            system = "x86_64-linux";
            overlays = [];
          };
          specialArgs = {
            inherit inputs;
            unstable = import nixpkgs-unstable {
              system = "x86_64-linux";
              config.allowUnfree = true;
            };
          };
        };
        # Beelink media server
        beelink = {
          # Use the current hostname until migrated
          deployment = {
            targetHost = "beelink.local";
            targetUser = "bdhill";
            buildOnTarget = true; # Build on the target to avoid arch issues
            allowLocalDeployment = true;
            # Override hostname during deployment
            # This allows us to deploy even if hostname doesn't match yet
            tags = [ "media" "x86_64" ];
          };
          imports = self.nixosConfigurations.beelink._module.args.modules;
        };
        # Firebat gateway
        firebat = {
          deployment = {
            targetHost = "firebat.local";
            targetUser = "bdhill";
            buildOnTarget = true;
            allowLocalDeployment = true;
            tags = [ "gateway" "x86_64" ];
          };
          imports = self.nixosConfigurations.firebat._module.args.modules;
        };
        # Raspberry Pi 4 DNS
        pi4 = {
          deployment = {
            targetHost = "pi4.local"; # Assuming this one has correct hostname
            targetUser = "bdhill";
            buildOnTarget = true; # Essential for ARM
            allowLocalDeployment = true;
            tags = [ "dns" "arm" ];
          };
          imports = self.nixosConfigurations.pi4._module.args.modules;
        };
      };

      # Development shells - platform agnostic
      devShells = let
        makeDevShell = system: let
          pkgs = nixpkgs-unstable.legacyPackages.${system};
          # colmena is a flake input, not an attribute of pkgs, so add it here
          colmenaPkg = colmena.packages.${system}.colmena;
        in pkgs.mkShell {
          buildInputs = with pkgs; [
            nixfmt-rfc-style
            git
            jq
            sops
            age
            ssh-to-age
            openssh
            openssl
          ] ++ [ colmenaPkg ];

          shellHook = ''
            echo "NixOS Homelab deployment environment loaded (${system})"
            echo "Colmena ${colmenaPkg.version} is available for remote deployment"
          '';
        };
      in {
        x86_64-linux.default = makeDevShell "x86_64-linux";
        aarch64-darwin.default = makeDevShell "aarch64-darwin";
        x86_64-darwin.default = makeDevShell "x86_64-darwin";
        aarch64-linux.default = makeDevShell "aarch64-linux";
      };
    };
}
