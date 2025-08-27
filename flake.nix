# SPDX-License-Identifier: GPL-3.0-or-later

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

    declarative-jellyfin = {
      url = "github:Sveske-Juice/declarative-jellyfin";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager/release-25.05";
      inputs.nixpkgs.follows = "nixpkgs";
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
      nixos-raspberrypi,
      nixos-images,
      declarative-jellyfin,
      home-manager,
      ...
    }@inputs:
    let
      # Common module groups
      baseModules = [
        ./modules/common
        ./modules/servers
        sops-nix.nixosModules.sops
        home-manager.nixosModules.home-manager
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.users.bdhill =
            {
              config,
              lib,
              pkgs,
              ...
            }:
            (import ./users/bdhill.nix { inherit config lib pkgs; }).homeConfig;
        }
      ];

      x86Modules = [
        disko.nixosModules.disko
        impermanence.nixosModules.impermanence
        declarative-jellyfin.nixosModules.default
      ];

      piModules = [
        ./modules/raspberrypi/base.nix
      ];

      # Helper function for Raspberry Pi systems using nixos-raspberrypi
      mkPiSystem =
        {
          hostname,
          piVersion ? "4", # "4" or "5"
          modules ? [ ],
        }:
        nixos-raspberrypi.lib.nixosSystem {
          specialArgs = {
            inherit inputs;
            inherit nixos-raspberrypi;
          };
          modules = [
            nixos-raspberrypi.nixosModules."raspberry-pi-${piVersion}".base
            nixos-raspberrypi.nixosModules."raspberry-pi-${piVersion}".display-vc4
            ./hosts/${hostname}/configuration.nix
          ]
          ++ baseModules
          ++ piModules
          ++ modules;
        };

      # Helper function to create a nixos system configuration
      mkSystem =
        {
          hostname,
          system ? "x86_64-linux",
          modules ? [ ],
          useX86Modules ? true,
          usePiModules ? false,
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
            ./hosts/${hostname}
          ]
          ++ baseModules
          ++ (if useX86Modules then x86Modules else [ ])
          ++ (if usePiModules then piModules else [ ])
          ++ modules;
        };
    in
    {
      nixosConfigurations = {
        # Main media server (Beelink SER8)
        ser8 = mkSystem {
          hostname = "ser8";
          modules = [
            ./modules/media
            ./modules/nordvpn
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
        pi4 = mkPiSystem {
          hostname = "pi4";
          piVersion = "4";
          modules = [
            ./modules/dns
          ];
        };

        # Extraneous Server (Raspberry Pi 5)
        pi5 = mkPiSystem {
          hostname = "pi5";
          piVersion = "5";
          modules = [
            ./hosts/pi5/configtxt.nix
            disko.nixosModules.disko
          ];
        };

        # Provisioning targets - just use the same configs
        # nixos-anywhere will handle the installation
        "provisioning-ser8" = self.nixosConfigurations.ser8;
        "provisioning-firebat" = self.nixosConfigurations.firebat;
        "provisioning-pi4" = self.nixosConfigurations.pi4;
        "provisioning-pi5" = self.nixosConfigurations.pi5;
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
            specialArgs = { inherit inputs nixos-raspberrypi; };
            modules = [
              nixos-raspberrypi.nixosModules.raspberry-pi-5.base
              ./modules/raspberrypi/usb-installer.nix
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
            in
            pkgs.mkShell {
              buildInputs = with pkgs; [
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
                addlicense
                dhcping
                caddy
                python3
                wireguard-tools
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
