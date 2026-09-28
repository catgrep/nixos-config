# SPDX-License-Identifier: GPL-3.0-or-later

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
# These run under `nix flake check`, and therefore under `make check`,
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
{
  nixpkgs,
  disko,
  pinnedFor,
  mvs,
  self,
}:

let
  vmChecks =
    system:
    let
      pkgs = nixpkgs.legacyPackages.${system};
    in
    {
      backup-behavior = import ./tests/backup-behavior.nix { inherit pkgs mvs; };
      backup-layout = import ./tests/backup-layout.nix {
        inherit pkgs;
        diskoLib = disko.lib;
      };
      service-monitoring-vm = import ./tests/service-monitoring-vm.nix {
        inherit pkgs;
        pinned = pinnedFor system;
      };
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
            nativeBuildInputs = [ (pinnedFor system).prometheus.cli ];
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

      # Building hm runs its Go tests in the check phase, so a regression in
      # the helper fails `make check` like any other check.
      hm = self.packages.${system}.hm;

      package-pins = import ./tests/package-pins.nix {
        inherit pkgs self system;
        pinned = pinnedFor system;
      };

      service-monitoring-eval = import ./tests/service-monitoring-eval.nix { inherit pkgs; };
    };
in
{
  x86_64-linux = vmChecks "x86_64-linux" // portableChecks "x86_64-linux";
  aarch64-darwin = portableChecks "aarch64-darwin";
}
