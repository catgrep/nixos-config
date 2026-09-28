# SPDX-License-Identifier: GPL-3.0-or-later

{
  description = "Bobby's Homelab NixOS configurations";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    # Pinned (not `master`): raspberry-pi/common/ is under active development and a
    # silent change there would alter Pi boot behaviour on an unrelated flake update.
    # ff178232 is master head as of 2026-08-16. Re-bump deliberately.
    nixos-hardware.url = "github:NixOS/nixos-hardware/ff17823245ab9ff7bcae6acf950bd89cba82c38c";

    nixos-images = {
      url = "github:nix-community/nixos-images";
    };

    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      # The integrated module deliberately shares the host package set.
      inputs.nixpkgs.follows = "nixpkgs";
    };

    sagent = {
      url = "path:./tools/sagent";
      # Local build tools follow the root; upstream tool inputs keep their own locks.
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

    omniflake.url = "github:fzakaria/omniflake";

    # Refresh package history independently of third-party flake updates.
    mvs = {
      url = "github:fzakaria/nixpkgs-multiverse";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      nixpkgs-unstable,
      nixos-hardware,
      nixos-images,
      home-manager,
      sagent,
      mvs,
      omniflake,
      ...
    }@inputs:
    let
      upstream = import ./omniflake.nix { inherit omniflake; };
      inherit (upstream)
        disko
        impermanence
        sops-nix
        declarative-jellyfin
        rust-overlay
        nix-darwin
        ;

      # No x86_64-darwin: nixpkgs dropped the platform after 26.05, and the
      # unstable input this shell is built from is past that. The key threw
      # on evaluation rather than producing anything, which took the whole
      # flake down with it whenever every output was walked.
      shellSystems = [
        "x86_64-linux"
        "aarch64-darwin"
        "aarch64-linux"
      ];

      pinnedFor =
        system:
        mvs.lib.readLock {
          inherit system;
          file = ./multiverse.lock;
          config.allowUnfree = true;
        };

      sagentFor =
        system:
        let
          pkgs = nixpkgs-unstable.legacyPackages.${system}.extend (
            _: _: {
              inherit ((pinnedFor system)) tmux;
            }
          );
        in
        sagent.lib.mkSagent {
          inherit system pkgs;
          extraReadPaths = [
            "~/.npm-global"
            "~/Library/Application Support"
            "~/AGENTS.md"
            "~/github/experiments"
            "~/.ssh"
            "/Users/bobby" # temporary
          ];
          extraWritePaths = [
            "~/github/catgrep/nixos-config"
            "~/Library/Application Support"
            "~/.docker"
            "~/scratch"
          ];
          unixSocketPaths = [
            "/nix/var/nix/daemon-socket/socket"
            "/var/run/nix-daemon.socket"
            "/private/var/run/nix-daemon.socket"
            "/var/run/docker.sock"
            "~/.docker/run/docker.sock"
          ];
          extraEnv = {
            AST_OUTLINE_MODEL_DIR = "~/.cache/ast-outline/models";
            AST_OUTLINE_TLS_STRICT = "1";
          };
        };

      # x86_64-darwin is dropped: nixpkgs stopped supporting it after 26.05, and
      # the unstable input these are built from is past that. Its legacyPackages
      # entry throws on evaluation rather than being absent, so leaving the key
      # in place took down every command that walks the whole flake, `nix flake
      # show` and `nix flake check` included.
      sagentPackages = builtins.mapAttrs (
        system: packages:
        let
          pkgs = nixpkgs-unstable.legacyPackages.${system};
          configuredSagent = sagentFor system;
        in
        packages
        // pkgs.lib.optionalAttrs pkgs.stdenv.hostPlatform.isDarwin {
          sagent = configuredSagent;
          default = configuredSagent;
        }
      ) (nixpkgs.lib.filterAttrs (system: _: system != "x86_64-darwin") sagent.packages);

      # hm is built on the pinned Go so the binary matches the toolchain the
      # home configuration installs; nh, git and the go-tools staticcheck
      # its check phase runs come from the same lock.
      hmFor =
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          pinned = pinnedFor system;
        in
        pkgs.callPackage ./tools/hm {
          inherit (pinned) nh git go-tools;
          buildGoModule = pkgs.buildGoModule.override { go = pinned.go_1_27; };
        };

      # Exported so `nix run .#hm` works before Home Manager has installed
      # it, and so hm can run the refreshed mvs through `nix run .#mvs`
      # after `nix flake update mvs`.
      toolPackagesFor = system: {
        hm = hmFor system;
        mvs = mvs.packages.${system}.mvs;
      };

      subgenPackagesFor =
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          stableTsWhisperless = pkgs.python312Packages.callPackage (./packages/stable-ts-whisperless) { };
        in
        {
          faster-whisper-medium = pkgs.callPackage ./packages/faster-whisper-medium { };
          stable-ts-whisperless = stableTsWhisperless;
          subgen = pkgs.callPackage ./packages/subgen {
            stable-ts-whisperless = stableTsWhisperless;
          };
          donetick = pkgs.callPackage ./packages/donetick { };
        };

      # Common module groups
      baseModules = [
        ./modules/common
        ./modules/servers
        sops-nix.nixosModules.sops
        home-manager.nixosModules.home-manager
        ({ config, ... }: {
          home-manager.extraSpecialArgs = {
            pinned = config.multiverse.locked;
            inherit mvs rust-overlay sagent;
          };
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.users.bdhill =
            {
              config,
              lib,
              pinned,
              ...
            }:
            (import ./users/bdhill.nix { inherit config lib pinned; }).homeConfig;
        })
      ];

      x86Modules = [
        disko.nixosModules.disko
        impermanence.nixosModules.impermanence
        declarative-jellyfin.nixosModules.default
        ./modules/subgen
      ];

      piModules = [
        ./modules/raspberrypi/base.nix
      ];

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
            inherit inputs upstream;
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
            ./modules/household
            ./modules/automation
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
        pi4 = mkSystem {
          hostname = "pi4";
          system = "aarch64-linux";
          useX86Modules = false;
          usePiModules = true;
          modules = [
            nixos-hardware.nixosModules.raspberry-pi-4
            ./modules/dns
          ];
        };

        # Extraneous Server (Raspberry Pi 5)
        pi5 = mkSystem {
          hostname = "pi5";
          system = "aarch64-linux";
          useX86Modules = false;
          usePiModules = true;
          modules = [
            nixos-hardware.nixosModules.raspberry-pi-5
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

      # Standalone Home Manager for the Mac. It receives the same special
      # arguments as the NixOS home-manager module above, so the shared
      # modules evaluate identically on every machine.
      homeConfigurations."bobby@bob-mac" = home-manager.lib.homeManagerConfiguration {
        pkgs = nixpkgs.legacyPackages.aarch64-darwin;
        extraSpecialArgs = {
          pinned = pinnedFor "aarch64-darwin";
          inherit mvs rust-overlay sagent;
        };
        modules = [ ./home-manager/users/bobby.nix ];
      };

      # The Mac's system layer: Homebrew lists and launchd agents. It gets
      # the same pinned set as the home configuration above.
      darwinConfigurations."bob-mac" = nix-darwin.lib.darwinSystem {
        system = "aarch64-darwin";
        specialArgs.pinned = pinnedFor "aarch64-darwin";
        modules = [ ./darwin ];
      };

      inherit (sagent) lib;

      packages = nixpkgs.lib.recursiveUpdate (nixpkgs.lib.recursiveUpdate sagentPackages (
        nixpkgs.lib.genAttrs shellSystems toolPackagesFor
      )) { x86_64-linux = subgenPackagesFor "x86_64-linux"; };

      # kexec installers for nixos-anywhere. The Raspberry Pi sd-image entries were
      # removed with the third-party fork that built them; a minimal upstream
      # bootstrap image has not been built to replace them yet.
      # Custom output consumed by provisioning scripts. Nix flake check reports
      # an unknown-output warning; installer derivations are checked explicitly.
      installerConfigurations = {
        aarch64-kexec = nixos-images.packages.aarch64-linux.kexec-installer-nixos-unstable;
        x86_64-kexec = nixos-images.packages.x86_64-linux.kexec-installer-nixos-unstable;
      };

      devShells = nixpkgs.lib.genAttrs shellSystems (system: {
        default = import ./dev.nix {
          pkgs = nixpkgs-unstable.legacyPackages.${system};
          pinned = pinnedFor system;
          inherit
            system
            sagent
            sagentFor
            mvs
            ;
        };
      });

      checks = import ./checks.nix {
        inherit
          self
          nixpkgs
          disko
          pinnedFor
          mvs
          ;
      };

      # Service discovery - maps enabled services to their packages per host
      # Query with: nix eval '.#enabledServices.ser8' --json
      # Query with: nix eval '.#servicePackages.ser8' --json
      #
      # Note: We use options.*.isDefined to filter out renamed/deprecated options
      # before accessing config, avoiding uncatchable abort errors
      # These custom metadata outputs support operational queries documented
      # above. Nix flake check reports unknown-output warnings for both names.
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
    };
}
