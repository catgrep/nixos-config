# SPDX-License-Identifier: GPL-3.0-or-later

{ config, lib, ... }:

let
  coveredServices = import ./services.nix;
in

{
  # Without this check, a service could be listed as covered while having no
  # dataset of its own, and nothing would say so. Its files would still be
  # captured -- the recursive snapshot of the parent sweeps up everything under
  # it -- so the failure would not show up as missing data. What would be
  # missing is the per-service granularity that makes a single service
  # restorable on its own, and that absence is invisible until the day someone
  # needs it. Turn it into a build failure instead.
  #
  # This checks that a dataset is declared and where it mounts, and nothing
  # about its properties. Do not extend it to cover them: properties are not
  # part of the evaluated configuration, and nothing at build time can read one
  # back off a pool that does not exist yet. The two layers that can see a real
  # pool own that job instead -- the layout test in tests/, which asserts
  # properties against a pool built from the declarations, and the
  # dataset-properties smoketest, which asserts them against the live host.
  assertions = lib.mapAttrsToList (svc: _: {
    assertion = (config.fileSystems."/var/lib/${svc}".device or null) == "rpool/safe/persist/${svc}";
    message = ''
      The backup coverage set lists "${svc}", but /var/lib/${svc} is not mounted
      from rpool/safe/persist/${svc}.

      Either remove it from hosts/ser8/backup/services.nix, or declare its
      dataset in hosts/ser8/disko-config.nix under the rpool datasets:

        "safe/persist/${svc}" = {
          type = "zfs_fs";
          options = {
            mountpoint = "legacy";
            atime = "off";
          };
          mountpoint = "/var/lib/${svc}";
        };
    '';
  }) coveredServices;
}
