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

    impermanence = {
      url = "github:nix-community/impermanence";
    };

    colmena = {
      url = "github:zhaofengli/colmena";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixos-raspberrypi = {
      url = "github:nvmd/nixos-raspberrypi/main";
      # Don't follow nixpkgs - let it use its own fork, since it extends the deprecated
      # boot.loader.raspberryPi option in nixpkgs with one provided by nixos-raspberrypi
    };

    nixos-images = {
      url = "github:nix-community/nixos-images";
    };
  };

  nixConfig = {
    extra-substituters = [
      "https://nixos-raspberrypi.cachix.org"
    ];
    extra-trusted-public-keys = [
      "nixos-raspberrypi.cachix.org-1:4iMO9LXa8BqhU+Rpg6LQKiGa2lsNh/j2oiYLNOQ5sPI="
    ];
  };

  outputs =
    {
      self,
      nixpkgs,
      nixpkgs-unstable,
      disko,
      impermanence,
      sops-nix,
      colmena,
      nixos-raspberrypi,
      nixos-images,
      ...
    }@inputs:
    let
      # Helper function to create a nixos system configuration
      mkSystem =
        {
          hostname,
          system ? "x86_64-linux",
          modules ? [ ],
        }:
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
            ./modules/common
            ./modules/servers
            disko.nixosModules.disko
            impermanence.nixosModules.impermanence
            sops-nix.nixosModules.sops
          ]
          ++ modules;
        };
    in
    {
      nixosConfigurations = {
        # Main media server (Beelink SER8)
        beelink-homelab = mkSystem {
          hostname = "beelink-homelab";
          modules = [
            ./modules/media
          ];
        };

        # Gateway/Load Balancer (Firebat)
        firebat = mkSystem {
          hostname = "firebat";
          modules = [
            ./modules/gateway
          ];
        };

        # DNS Server (Raspberry Pi 4B)
        pi4 = nixos-raspberrypi.lib.nixosSystem {
          specialArgs = {
            inherit inputs;
            inherit nixos-raspberrypi;
          };
          modules = [
            nixos-raspberrypi.nixosModules.raspberry-pi-4.base
            nixos-raspberrypi.nixosModules.raspberry-pi-4.display-vc4
            ./hosts/pi4/configuration.nix
            ./modules/common
            ./modules/servers
            ./modules/dns
            ./modules/raspberrypi/base.nix
            sops-nix.nixosModules.sops
          ];
        };

        # Extraneous Server (Raspberry Pi 5)
        pi5 = nixos-raspberrypi.lib.nixosSystem {
          specialArgs = {
            inherit inputs;
            inherit nixos-raspberrypi;
          };
          modules = [
            nixos-raspberrypi.nixosModules.raspberry-pi-5.base
            nixos-raspberrypi.nixosModules.raspberry-pi-5.display-vc4
            ./hosts/pi5/configuration.nix
            ./hosts/pi5/configtxt.nix
            ./modules/common
            ./modules/servers
            ./modules/raspberrypi/base.nix
            disko.nixosModules.disko
            sops-nix.nixosModules.sops
          ];
        };

        # Provisioning targets - just use the same configs
        # nixos-anywhere will handle the installation
        "provisioning-beelink-homelab" = self.nixosConfigurations.beelink-homelab;
        "provisioning-firebat" = self.nixosConfigurations.firebat;
        "provisioning-pi4" = self.nixosConfigurations.pi4;
        "provisioning-pi5" = self.nixosConfigurations.pi5;
      };

      # Colmena deployment configuration
      colmenaHive = colmena.lib.makeHive {
        meta = {
          nixpkgs = import nixpkgs-unstable {
            system = "x86_64-linux";
            overlays = [ ];
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
        beelink-homelab = {
          # Use the current hostname until migrated
          deployment = {
            targetHost = "192.168.68.89"; # static local ip for ez hostname transitions
            targetUser = "bdhill";
            buildOnTarget = true; # Build on the target to avoid arch issues
            allowLocalDeployment = true;
            # Override hostname during deployment
            # This allows us to deploy even if hostname doesn't match yet
            tags = [
              "media"
              "x86_64"
            ];
          };
          imports = self.nixosConfigurations.beelink-homelab._module.args.modules;
        };
        # Firebat gateway
        firebat = {
          deployment = {
            targetHost = "192.168.68.88"; # static local ip for ez hostname transitions
            targetUser = "bdhill";
            buildOnTarget = true;
            allowLocalDeployment = true;
            tags = [
              "gateway"
              "x86_64"
            ];
          };
          imports = self.nixosConfigurations.firebat._module.args.modules;
        };

        # Raspberry Pi 4 DNS - needs special handling for colmena
        pi4 = {
          deployment = {
            targetHost = "192.168.68.96";
            targetUser = "root";
            buildOnTarget = true;
            allowLocalDeployment = true;
            tags = [
              "dns"
              "arm"
              "raspberrypi"
            ];
          };
          imports = [
            nixos-raspberrypi.nixosModules.raspberry-pi-4.base
            nixos-raspberrypi.nixosModules.raspberry-pi-4.display-vc4
            ./hosts/pi4/configuration.nix
            ./modules/common
            ./modules/servers
            ./modules/dns
            ./modules/raspberrypi/base.nix
            sops-nix.nixosModules.sops
          ];
          nixpkgs.pkgs = nixos-raspberrypi.inputs.nixpkgs.legacyPackages.aarch64-linux;
        };

        pi5 = {
          deployment = {
            targetHost = "pi5.homelab";
            targetUser = "bdhill";
            buildOnTarget = true;
            allowLocalDeployment = true;
            tags = [
              "arm"
              "raspberrypi"
            ];
          };
          imports = [
            nixos-raspberrypi.nixosModules.raspberry-pi-5.base
            nixos-raspberrypi.nixosModules.raspberry-pi-5.display-vc4
            ./hosts/pi5/configuration.nix
            ./hosts/pi5/configtxt.nix
            ./modules/common
            ./modules/servers
            ./modules/raspberrypi/base.nix
            disko.nixosModules.disko
            sops-nix.nixosModules.sops
          ];
          nixpkgs.pkgs = nixos-raspberrypi.inputs.nixpkgs.legacyPackages.aarch64-linux;
        };

      };

      # Add minimally configured SD card image builders
      # (these are pre-builts provided by nixos-raspberrypi)
      installerConfigurations = {
        pi4 =
          (nixos-raspberrypi.lib.nixosInstaller {
            specialArgs = inputs;
            modules = [
              nixos-raspberrypi.nixosModules.raspberry-pi-4.base
              ./modules/raspberrypi/installer.nix
            ];
          }).config.system.build.sdImage;

        pi5 =
          (nixos-raspberrypi.lib.nixosInstaller {
            specialArgs = inputs;
            modules = [
              nixos-raspberrypi.nixosModules.raspberry-pi-5.base
              ./modules/raspberrypi/installer.nix
            ];
          }).config.system.build.sdImage;

        # kexec installers for nixos-anywhere
        aarch64-kexec = nixos-images.packages.aarch64-linux.kexec-installer-nixos-unstable;
        x86_64-kexec = nixos-images.packages.x86_64-linux.kexec-installer-nixos-unstable;
      };

      # Development shells - platform agnostic
      devShells =
        let
          makeDevShell =
            system:
            let
              pkgs = nixpkgs-unstable.legacyPackages.${system};
              # colmena is a flake input, not an attribute of pkgs, so add it here
              colmenaPkg = colmena.packages.${system}.colmena;

            in
            pkgs.mkShell {
              buildInputs =
                with pkgs;
                [
                  nixfmt-rfc-style
                  nixos-rebuild
                  git
                  jq
                  yq-go
                  sops
                  age
                  ssh-to-age
                  openssl
                  sshpass
                  mkpasswd
                  inetutils
                  shellcheck
                  nixos-anywhere
                  mkcert
                ]
                ++ [
                  colmenaPkg
                ];
            };
        in
        {
          x86_64-linux.default = makeDevShell "x86_64-linux";
          aarch64-darwin.default = makeDevShell "aarch64-darwin";
          x86_64-darwin.default = makeDevShell "x86_64-darwin";
          aarch64-linux.default = makeDevShell "aarch64-linux";
        };
    };
}
