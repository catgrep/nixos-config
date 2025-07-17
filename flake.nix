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
  };

  nixConfig = {
    extra-substituters = [
      "https://nixos-raspberrypi.cachix.org"
    ];
    extra-trusted-public-keys = [
      "nixos-raspberrypi.cachix.org-1:4iMO9LXa8BqhU+Rpg6LQKiGa2lsNh/j2oiYLNOQ5sPI="
    ];
  };

  outputs = { self, nixpkgs, nixpkgs-unstable, disko, impermanence, sops-nix, colmena, nixos-raspberrypi, ... }@inputs:
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
            impermanence.nixosModules.impermanence
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

        # DNS Server (Raspberry Pi 5)
        pi5 = nixos-raspberrypi.lib.nixosSystem {
          # Pass all inputs as specialArgs
          specialArgs = {
            inherit inputs;
            inherit nixos-raspberrypi disko impermanence sops-nix;
          };
          modules = [
            # Base Pi5 support
            nixos-raspberrypi.nixosModules.raspberry-pi-5.base
            nixos-raspberrypi.nixosModules.raspberry-pi-5.display-vc4

            # Your configuration
            ./hosts/pi5/configuration.nix
            ./hosts/pi5/configtxt.nix
            ./hosts/modules/common
            ./hosts/modules/servers
            ./hosts/modules/dns

            # Disko support
            disko.nixosModules.disko

            # Sops support
            sops-nix.nixosModules.sops

            # Optional: Use specific kernel version
            ({ config, pkgs, lib, ... }: let
              kernelBundle = pkgs.linuxAndFirmware.v6_6_74;  # Use a newer version
            in {
              boot = {
                loader.raspberryPi.firmwarePackage = kernelBundle.raspberrypifw;
                kernelPackages = kernelBundle.linuxPackages_rpi5;
              };
            })
          ];
        };

        # Provisioning targets - just use the same configs
        # nixos-anywhere will handle the installation
        "provisioning-beelink" = self.nixosConfigurations.beelink;
        "provisioning-firebat" = self.nixosConfigurations.firebat;
        "provisioning-pi5" = self.nixosConfigurations.pi5;
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
        # Raspberry Pi 5 DNS - needs special handling for colmena
        pi5 = {
          deployment = {
            targetHost = "pi5.local";
            targetUser = "bdhill";
            buildOnTarget = true;
            allowLocalDeployment = true;
            tags = [ "dns" "arm" "raspberrypi" ];
          };
          imports = [
            nixos-raspberrypi.nixosModules.raspberry-pi-5.base
            nixos-raspberrypi.nixosModules.raspberry-pi-5.display-vc4
            ./hosts/pi5/configuration.nix
            ./hosts/pi5/configtxt.nix
            ./hosts/modules/common
            ./hosts/modules/servers
            ./hosts/modules/dns
            disko.nixosModules.disko
            sops-nix.nixosModules.sops
          ];
          nixpkgs.pkgs = nixos-raspberrypi.inputs.nixpkgs.legacyPackages.aarch64-linux;
        };
      };

      # Add SD card image builder for Raspberry Pi 5
      # Add SD card image builder
      images = {
        pi5-installer = (nixos-raspberrypi.lib.nixosSystemInstaller {
          specialArgs = inputs;
          modules = [
            nixos-raspberrypi.nixosModules.raspberry-pi-5.base
            nixos-raspberrypi.nixosModules.sd-image
            ({ config, pkgs, lib, ... }: {
              users.users.nixos.openssh.authorizedKeys.keys = [
                "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDCleOKn5PTvChYNXoKIJ0bleq3EYn9ZyT0sL7qnc3jV4Gc2JoR0gk3yGL0FG/TGn5/cQ59bh8JPSQxmAG2DDzXhyztfK7bINCL+l7ESCciSdIOrhZHS+oeEZzrKyZFBJd0kC+YgoUMvMbyK/xqdMyc5uww50cAqORFX55g7sW0p6KGjVydQEU6Vbi9Dwmt9Ldt0sBBudLO0O+DDwFcort1l5hWurXFWxQWQQhhkm3OIk+5KPuwfbMgJp/YteD8UbsO9s7dhBMasqF8ybzYH7T7hBJNERZWMiyrkzdVY0kyytlFBDCQvCjlS3Vp8SfV+6XkGnHu9sl1bj72iaFYPj4QkggjhEBF6gumMpUBr95hDvECLKtfP2SZ3S5NXjIcJGEltgmd28CItLLYbqA3ENGrkunQyyowBFjMyxvcREFiTmr+FdKwYPdu23UAFQj5WrJPRjiuDuHK9jjW4jMzymaYnYqwsXp6lFAjfe0+mdY9/UqUNyfK7RUY9M+cwJ4YZ4E= bobby@bob-mac.local"
              ];
              users.users.root.openssh.authorizedKeys.keys = config.users.users.nixos.openssh.authorizedKeys.keys;
            })
          ];
        }).config.system.build.sdImage;
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
            nixos-rebuild
            git
            jq
            sops
            age
            ssh-to-age
            openssl
            sshpass
            mkpasswd
            inetutils
          ] ++ [
            colmenaPkg
          ];
        };
      in {
        x86_64-linux.default = makeDevShell "x86_64-linux";
        aarch64-darwin.default = makeDevShell "aarch64-darwin";
        x86_64-darwin.default = makeDevShell "x86_64-darwin";
        aarch64-linux.default = makeDevShell "aarch64-linux";
      };
    };
}
