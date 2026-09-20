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

    nixos-images = {
      url = "github:nix-community/nixos-images";
    };

    declarative-jellyfin = {
      url = "github:Sveske-Juice/declarative-jellyfin";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Caddy with plugins support (cleaner than withPlugins)
    caddy-nix = {
      url = "github:vincentbernat/caddy-nix";
    };

    sagent = {
      url = "path:./tools/sagent";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

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
      disko,
      impermanence,
      sops-nix,
      nixos-images,
      declarative-jellyfin,
      home-manager,
      caddy-nix,
      sagent,
      mvs,
      ...
    }@inputs:
    let
      sagentFor =
        system:
        let
          pkgs = nixpkgs-unstable.legacyPackages.${system};
        in
        sagent.lib.mkSagent {
          inherit system pkgs;
          extraReadPaths = [
            "~/.npm-global"
            "~/Library/Application Support"
            "~/AGENTS.md"
            "~/github/experiments"
            "~/.ssh"
          ];
          extraWritePaths = [
            "~/github/catgrep/nixos-config"
            "~/Library/Application Support"
            "~/.docker"
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
            inherit inputs;
            # Retained with no in-tree consumers: keeps an unstable package one
            # argument away from any host module, without rewiring specialArgs
            # at the point someone first needs it.
            unstable = import nixpkgs-unstable {
              inherit system;
              config.allowUnfree = true;
            };
          };
          modules = [
            # Apply caddy-nix overlay for Caddy with plugins support
            {
              nixpkgs.overlays = [
                caddy-nix.overlays.default
              ];
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

      inherit (sagent) lib;

      packages = nixpkgs.lib.recursiveUpdate sagentPackages {
        x86_64-linux = subgenPackagesFor "x86_64-linux";
      };

      # kexec installers for nixos-anywhere. The Raspberry Pi sd-image entries were
      # removed with the third-party fork that built them; a minimal upstream
      # bootstrap image has not been built to replace them yet.
      installerConfigurations = {
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
              buildInputs =
                with pkgs;
                [
                  nixfmt
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
                  shfmt
                  nixos-anywhere
                  mkcert
                  addlicense
                  dhcping
                  caddy
                  python3
                  statix
                  nurl
                  wireguard-tools
                  # ast-bro and treehouse (with the ast-bro source override)
                  # are owned and exported by the sagent subflake.
                  sagent.packages.${system}.ast-bro
                  sagent.packages.${system}.treehouse
                  # nixpkgs version-history queries and pinning (nixmultiverse.com)
                  mvs.packages.${system}.mvs
                ]
                ++ lib.optionals pkgs.stdenv.hostPlatform.isDarwin [
                  (sagentFor system)
                ];
            };
        in
        {
          x86_64-linux.default = makeDevShell "x86_64-linux";
          aarch64-darwin.default = makeDevShell "aarch64-darwin";
          aarch64-linux.default = makeDevShell "aarch64-linux";
          # No x86_64-darwin: nixpkgs dropped the platform after 26.05, and the
          # unstable input this shell is built from is past that. The key threw
          # on evaluation rather than producing anything, which took the whole
          # flake down with it whenever every output was walked.
        };

      # Virtual-machine tests. These boot a real NixOS guest with real ZFS pools,
      # so they answer questions activation never does.
      #
      # backup-behavior builds the pools by hand and exercises what the engine
      # does with them: whether a recursive snapshot really lands the whole tree
      # in one transaction group, whether a replicated dataset can mount over
      # live service state, and whether state copied out of a snapshot actually
      # comes back.
      #   nix build .#checks.x86_64-linux.backup-behavior
      #
      # backup-layout asks the prior question, and the one activation is worst
      # at: whether the storage declarations would build the tree at all. It
      # installs from a reduced copy of ser8's disk configuration, boots the
      # result, and checks every dataset, mountpoint and tuned property against
      # what was declared. Activation never runs the create logic, so a dataset
      # can be declared for months while nothing exists and the service quietly
      # writes to a root filesystem that gets rolled back at boot. That has
      # happened here twice.
      #   nix build .#checks.x86_64-linux.backup-layout
      #
      # service-monitoring-vm boots the collection layer on its own -- just
      # modules/common/service-monitoring.nix and
      # modules/servers/service-monitoring.nix, not a whole host -- against
      # real exporters and synthetic units (a steady daemon, a frigate-shaped
      # crash loop, an undeclared oneshot job, an excluded unit), and reads
      # the results back from the scraped metrics rather than from Nix
      # evaluation alone.
      #   nix build .#checks.x86_64-linux.service-monitoring-vm
      #
      # Both run under `nix flake check`, and therefore under `make check`,
      # which is materially slower for it. That is the trade.
      #
      # x86_64-linux only -- the tests need a Linux guest, and a darwin key that
      # can never evaluate is worse than no key at all.
      #
      # service-alert-rules and service-monitoring-eval below need neither a
      # guest nor Linux: one runs promtool over a plain YAML file, the other
      # is pure module evaluation. Both run on aarch64-darwin too, so a
      # rules regression fails `nix flake check` on this machine, not only
      # in whatever runs the VM checks.
      checks =
        let
          vmChecks =
            system:
            let
              pkgs = nixpkgs.legacyPackages.${system};
            in
            {
              backup-behavior = import ./tests/backup-behavior.nix { inherit pkgs; };
              backup-layout = import ./tests/backup-layout.nix {
                inherit pkgs;
                diskoLib = disko.lib;
              };
              service-monitoring-vm = import ./tests/service-monitoring-vm.nix { inherit pkgs; };
            };

          portableChecks =
            system:
            let
              pkgs = nixpkgs.legacyPackages.${system};
              monitoredHosts = import ./modules/gateway/monitored-hosts.nix;
              serviceAlertRules = import ./modules/gateway/service-alert-rules.nix {
                inherit pkgs;
                hosts = map (h: h.host) monitoredHosts;
              };
            in
            {
              # Checks the exact rules derivation modules/gateway/prometheus.nix
              # ships, not a copy, so this can never pass while the deployed
              # rules are broken.
              service-alert-rules =
                pkgs.runCommand "check-service-alert-rules"
                  {
                    # This nixpkgs splits promtool into prometheus's "cli"
                    # output; the default "out" output only carries the
                    # prometheus and migrate binaries.
                    nativeBuildInputs = [ pkgs.prometheus.cli ];
                  }
                  ''
                    # duplicate-rules is a known false positive here: several
                    # SystemdMonitoringDataMissing variants intentionally share
                    # an alertname (see modules/gateway/service-alert-rules.nix),
                    # and promtool's lint flags that pattern even though
                    # Prometheus itself accepts it.
                    promtool check rules --lint=none ${serviceAlertRules}

                    cp ${serviceAlertRules} rules.yml
                    cp ${./tests/service-alert-tests.yml} service-alert-tests.yml
                    promtool test rules service-alert-tests.yml

                    touch $out
                  '';

              service-monitoring-eval = import ./tests/service-monitoring-eval.nix { inherit pkgs; };
            };
        in
        {
          x86_64-linux = vmChecks "x86_64-linux" // portableChecks "x86_64-linux";
          aarch64-darwin = portableChecks "aarch64-darwin";
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
    };
}
