# SPDX-License-Identifier: GPL-3.0-or-later

# Declares the per-unit monitoring policy schema shared across hosts. This
# module only declares options and validates them; the collection machinery
# that turns a declaration into scraped metrics lives in
# modules/servers/service-monitoring.nix.
{ config, lib, ... }:

let
  cfg = config.homelab.monitoring.systemd.units;

  # Emitted verbatim as a Prometheus label value, so the charset excludes
  # quotes, backslashes, and whitespace that would break the exposition
  # format or let a unit name inject an unintended label.
  isValidUnitName = name: builtins.match "[A-Za-z0-9:_.@-]+\\.service" name != null;

  invalidNames = builtins.filter (name: !isValidUnitName name) (builtins.attrNames cfg);

  contradictoryNames = builtins.filter (name: cfg.${name}.expectedRunning && !cfg.${name}.enable) (
    builtins.attrNames cfg
  );
in
{
  options.homelab.monitoring.systemd.units = lib.mkOption {
    default = { };
    description = ''
      Per-unit systemd monitoring policy, keyed by unit name (for example
      "jellyfin.service"). Declaring a unit here publishes it into the
      generated Prometheus policy file so alerting rules can act on it
      without hardcoding unit names.
    '';
    type = lib.types.attrsOf (
      lib.types.submodule {
        options = {
          expectedRunning = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Whether this unit should remain active.";
          };
          enable = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Whether shared service alerts apply to this unit.";
          };
        };
      }
    );
  };

  config.assertions = [
    {
      assertion = invalidNames == [ ];
      message = ''
        homelab.monitoring.systemd.units has invalid unit name(s): ${toString invalidNames}.
        Each name must end in ".service" and contain only letters, digits, and ':_.@-'.
        Rename the attribute to match the real unit name.
      '';
    }
    {
      assertion = contradictoryNames == [ ];
      message = ''
        homelab.monitoring.systemd.units has unit(s) with expectedRunning = true and
        enable = false: ${toString contradictoryNames}.
        A unit cannot be both expected to run and excluded from alerts. Either drop
        expectedRunning or remove the enable = false exclusion.
      '';
    }
  ];
}
