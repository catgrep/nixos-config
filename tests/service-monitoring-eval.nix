# SPDX-License-Identifier: GPL-3.0-or-later

# Pure-evaluation assertions over the homelab.monitoring.systemd.units schema
# (modules/common/service-monitoring.nix): merge behaviour, defaults, and
# validation messages, without pulling in a whole host configuration. A
# change to this schema fails `nix flake check` here instead of only
# surfacing later on a real host build.
{ pkgs }:

let
  inherit (pkgs) lib;

  schema = ../modules/common/service-monitoring.nix;

  # The schema module declares config.assertions using NixOS's own
  # convention, but that option is defined by NixOS's base modules, not by
  # evalModules itself -- without importing it here, assigning to
  # config.assertions is a definition for an option that doesn't exist.
  assertionsModule = pkgs.path + "/nixos/modules/misc/assertions.nix";

  eval =
    extraModules:
    lib.evalModules {
      modules = [
        schema
        assertionsModule
      ]
      ++ extraModules;
    };

  # evalModules never itself walks config.assertions and aborts -- that
  # enforcement lives in NixOS's own base modules, which are not part of
  # this evaluation. So a broken declaration below shows up as an ordinary
  # entry in config.assertions with assertion = false, not as a thrown
  # error, and this file can inspect it directly.
  fail = name: builtins.throw "service-monitoring-eval: ${name} failed";
  check = name: cond: if cond then true else fail name;

  emptyEval = eval [ ];

  mergeEval = eval [
    { homelab.monitoring.systemd.units."a.service".expectedRunning = true; }
    { homelab.monitoring.systemd.units."b.service".expectedRunning = true; }
  ];
  mergedUnits = mergeEval.config.homelab.monitoring.systemd.units;

  mkIfEval = eval [
    (
      { lib, ... }:
      {
        homelab.monitoring.systemd.units = lib.mkIf false {
          "c.service".expectedRunning = true;
        };
      }
    )
  ];

  defaultsEval = eval [ { homelab.monitoring.systemd.units."d.service" = { }; } ];
  dUnit = defaultsEval.config.homelab.monitoring.systemd.units."d.service";

  invalidNameEval = eval [ { homelab.monitoring.systemd.units."not-a-unit" = { }; } ];
  invalidNameFailure = lib.findFirst (a: !a.assertion) null invalidNameEval.config.assertions;

  contradictionEval = eval [
    {
      homelab.monitoring.systemd.units."e.service" = {
        expectedRunning = true;
        enable = false;
      };
    }
  ];
  contradictionFailure = lib.findFirst (a: !a.assertion) null contradictionEval.config.assertions;

  checks = [
    (check "zero declarations evaluate cleanly" (
      emptyEval.config.homelab.monitoring.systemd.units == { }
    ))
    (check "two modules declaring different units merge into both" (
      mergedUnits ? "a.service"
      && mergedUnits ? "b.service"
      && mergedUnits."a.service".expectedRunning
      && mergedUnits."b.service".expectedRunning
    ))
    (check "lib.mkIf false makes a declaration disappear" (
      !(mkIfEval.config.homelab.monitoring.systemd.units ? "c.service")
    ))
    (check "defaults are expectedRunning = false, enable = true" (
      dUnit.expectedRunning == false && dUnit.enable == true
    ))
    (check "an invalid unit name fails an assertion naming it" (
      invalidNameFailure != null && lib.hasInfix "not-a-unit" invalidNameFailure.message
    ))
    (check "expectedRunning = true with enable = false fails an assertion naming it" (
      contradictionFailure != null && lib.hasInfix "e.service" contradictionFailure.message
    ))
  ];

  allPass = builtins.all (x: x) checks;
in
pkgs.runCommand "service-monitoring-eval" { } (if allPass then "touch $out" else fail "unreachable")
