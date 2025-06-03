{
  description = "Bobby's Homelab NixOS configurations";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixos-hardware.url = "github:NixOS/nixos-hardware/daa628a725ab4948e0e2b795e8fb6f4c3e289a7a";

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    colmena = {
      url = "github:zhaofengli/colmena";
      inputs.nixpkgs.follows = "nixpkgs";
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
      colmena = {
        meta = {
          nixpkgs = import nixpkgs {
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
            targetHost = "nixhost.local";
            targetUser = "root";
            buildOnTarget = true; # Build on the target to avoid arch issues
            # Override hostname during deployment
            # This allows us to deploy even if hostname doesn't match yet
            tags = [ "media" "x86_64" ];
          };
          imports = self.nixosConfigurations.beelink._module.args.modules;
        };
        # Firebat gateway
        firebat = {
          deployment = {
            targetHost = "nixhost0.local";
            targetUser = "root";
            buildOnTarget = true;
            tags = [ "gateway" "x86_64" ];
          };
          imports = self.nixosConfigurations.firebat._module.args.modules;
        };
        # Raspberry Pi 4 DNS
        pi4 = {
          deployment = {
            targetHost = "pi4.local"; # Assuming this one has correct hostname
            targetUser = "root";
            buildOnTarget = true; # Essential for ARM
            tags = [ "dns" "arm" ];
          };
          imports = self.nixosConfigurations.pi4._module.args.modules;
        };
      };

      # Development shells
      devShells.x86_64-linux.default = nixpkgs.legacyPackages.x86_64-linux.mkShell {
        buildInputs = with nixpkgs.legacyPackages.x86_64-linux; [
          nixfmt-rfc-style
          sops
          age
          ssh-to-age
        ];
      };
    };
}
