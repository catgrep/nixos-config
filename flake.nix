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

    # alldebrid-proxy = {
    #   url = "path:/Users/bobby/github/catgrep/alldebrid-rs";
    #   inputs.nixpkgs.follows = "nixpkgs";
    # };

    home-manager = {
      url = "github:nix-community/home-manager/release-25.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Caddy with plugins support (cleaner than withPlugins)
    caddy-nix = {
      url = "github:vincentbernat/caddy-nix";
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
      # alldebrid-proxy,
      home-manager,
      caddy-nix,
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
        # alldebrid-proxy.nixosModules.default
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
              # Apply caddy-nix overlay to unstable for Caddy with plugins support
              overlays = [ caddy-nix.overlays.default ];
            };
          };
          modules = [
            # Apply caddy-nix overlay for Caddy with plugins support
            {
              nixpkgs.overlays = [ caddy-nix.overlays.default ];
            }
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

      # Service discovery - maps enabled services to their packages per host
      # Query with: nix eval '.#enabledServices.ser8' --json
      # Query with: nix eval '.#servicePackages.ser8' --json
      #
      # Note: We use options.*.isDefined to filter out renamed/deprecated options
      # before accessing config, avoiding uncatchable abort errors
      enabledServices = builtins.mapAttrs (
        hostname: cfg:
        let
          allServices = builtins.attrNames cfg.config.services;

          # Filter to services where enable option exists AND is actually defined
          # This avoids aborts from renamed options (e.g., redis -> redis.servers)
          isDefinedService =
            name:
            let
              tryResult = builtins.tryEval (
                (cfg.options.services.${name} ? enable) && cfg.options.services.${name}.enable.isDefined
              );
            in
            tryResult.success && tryResult.value;

          definedServices = builtins.filter isDefinedService allServices;
        in
        builtins.filter (name: cfg.config.services.${name}.enable) definedServices
      ) self.nixosConfigurations;

      servicePackages = builtins.mapAttrs (
        hostname: cfg:
        let
          allServices = builtins.attrNames cfg.config.services;

          isDefinedService =
            name:
            let
              tryResult = builtins.tryEval (
                (cfg.options.services.${name} ? enable) && cfg.options.services.${name}.enable.isDefined
              );
            in
            tryResult.success && tryResult.value;

          definedServices = builtins.filter isDefinedService allServices;
          enabledSvcs = builtins.filter (name: cfg.config.services.${name}.enable) definedServices;

          getPackage =
            name:
            let
              svc = cfg.config.services.${name};
            in
            if svc ? package then svc.package.pname or svc.package.name or null else null;
        in
        builtins.listToAttrs (
          builtins.filter (x: x.value != null) (
            map (name: {
              inherit name;
              value = getPackage name;
            }) enabledSvcs
          )
        )
      ) self.nixosConfigurations;

      # Combined package info - single evaluation for all package data
      # Query with: nix eval '.#packageInfo.ser8' --json
      packageInfo = builtins.mapAttrs (
        hostname: cfg:
        let
          pkgs = cfg.pkgs;

          # Get overlay packages with versions
          overlayPkgs =
            let
              tryGetOverlays = builtins.tryEval (
                builtins.concatMap (
                  ov:
                  builtins.attrNames (
                    ov (import nixpkgs { system = "x86_64-linux"; }) (import nixpkgs { system = "x86_64-linux"; })
                  )
                ) cfg.config.nixpkgs.overlays
              );
              names = if tryGetOverlays.success then tryGetOverlays.value else [ ];
            in
            builtins.listToAttrs (
              map (name: {
                inherit name;
                value =
                  let
                    tryVersion = builtins.tryEval (pkgs.${name}.version or null);
                  in
                  if tryVersion.success then tryVersion.value else null;
              }) names
            );

          # Get system packages with versions (first 50)
          systemPkgs =
            let
              tryGetPkgs = builtins.tryEval cfg.config.environment.systemPackages;
              allPkgs = if tryGetPkgs.success then tryGetPkgs.value else [ ];
              # Extract name and version, deduplicate by name
              pkgInfo = map (p: {
                name = p.pname or p.name or "unknown";
                version = p.version or null;
              }) allPkgs;
              # Sort by name and take first 50 unique
              sorted = builtins.sort (a: b: a.name < b.name) pkgInfo;
              unique = builtins.foldl' (
                acc: pkg: if builtins.any (x: x.name == pkg.name) acc then acc else acc ++ [ pkg ]
              ) [ ] sorted;
            in
            nixpkgs.lib.take 50 unique;

          # Get service packages with versions
          allServices = builtins.attrNames cfg.config.services;
          isDefinedService =
            name:
            let
              tryResult = builtins.tryEval (
                (cfg.options.services.${name} ? enable) && cfg.options.services.${name}.enable.isDefined
              );
            in
            tryResult.success && tryResult.value;
          definedServices = builtins.filter isDefinedService allServices;
          enabledSvcs = builtins.filter (name: cfg.config.services.${name}.enable) definedServices;

          servicePkgs = builtins.listToAttrs (
            builtins.filter (x: x.value != null) (
              map (name: {
                inherit name;
                value =
                  let
                    svc = cfg.config.services.${name};
                    pkg = if svc ? package then svc.package else null;
                    pkgName = if pkg != null then (pkg.pname or pkg.name or null) else null;
                    pkgVersion = if pkg != null then (pkg.version or null) else null;
                  in
                  if pkgName != null then
                    {
                      package = pkgName;
                      version = pkgVersion;
                    }
                  else
                    null;
              }) enabledSvcs
            )
          );
        in
        {
          overlays = overlayPkgs;
          systemPackages = systemPkgs;
          services = servicePkgs;
        }
      ) self.nixosConfigurations;
    };
}
