# SPDX-License-Identifier: GPL-3.0-or-later

# A lock entry alone does not select a package: check the actual consumers.
{
  pkgs,
  self,
  pinned,
  system,
}:

let
  inherit (pkgs) lib;
  check = message: condition: if condition then true else throw "Package pins: ${message}";
  shellPackages = self.devShells.${system}.default.nativeBuildInputs;
  ser8 = self.nixosConfigurations.ser8.config;
  firebat = self.nixosConfigurations.firebat.config;
  pi4 = self.nixosConfigurations.pi4.config;

  sameVersion = pair: (builtins.head pair).version == (builtins.elemAt pair 1).version;
  sabnzbd = ser8.services.sabnzbd;
  sabnzbdUnit = ser8.systemd.services.sabnzbd;

  servicePins = [
    [
      ser8.services.actual.package
      ser8.multiverse.locked.actual-server
    ]
    [
      ser8.services.jellyfin.package
      ser8.multiverse.locked.jellyfin
    ]
    [
      ser8.services.home-assistant.package
      ser8.multiverse.locked.home-assistant
    ]
    [
      ser8.services.frigate.package
      ser8.multiverse.locked.frigate
    ]
    [
      ser8.services.sabnzbd.package
      ser8.multiverse.locked.sabnzbd
    ]
    [
      ser8.services.postgresql.package
      ser8.multiverse.locked.postgresql_17
    ]
    [
      firebat.services.caddy.package
      firebat.multiverse.locked.caddy
    ]
    [
      firebat.services.grafana.package
      firebat.multiverse.locked.grafana
    ]
    [
      firebat.services.prometheus.package
      firebat.multiverse.locked.prometheus
    ]
    [
      pi4.services.adguardhome.package
      pi4.multiverse.locked.adguardhome
    ]
  ];

  checks = [
    (check "the development shell must install the locked prek derivation" (
      builtins.any (package: package.outPath == pinned.prek.outPath) shellPackages
    ))
    (check "service versions must agree with their pins, including custom builds" (
      builtins.all sameVersion servicePins
    ))
    (check "SABnzbd must execute its selected package" (
      lib.hasPrefix "${lib.getExe sabnzbd.package} " sabnzbdUnit.serviceConfig.ExecStart
    ))
    (check "SABnzbd must merge the SOPS template through the supported startup path" (
      ser8.services.sabnzbd.configFile == null
      && builtins.elem ser8.sops.templates."sabnzbd.ini".path ser8.services.sabnzbd.secretFiles
      && lib.hasInfix ser8.sops.templates."sabnzbd.ini".path ser8.systemd.services.sabnzbd.preStart
    ))
  ];
in
assert builtins.all (result: result) checks;
pkgs.runCommand "package-pins" { } "touch $out"
