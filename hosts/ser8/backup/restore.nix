# SPDX-License-Identifier: GPL-3.0-or-later

{
  config,
  lib,
  pkgs,
  ...
}:

let
  coveredServices = import ./services.nix;

  postgresqlPackage = config.services.postgresql.package;

  # One variable carries the allowlist and the service-to-unit map together, so
  # the tool has a single thing to validate against and never has to infer a
  # unit name from a directory name.
  coveredPairs = lib.concatStringsSep " " (
    lib.mapAttrsToList (svc: cfg: "${svc}=${cfg.unit}") coveredServices
  );

  backupRestore = pkgs.writeShellApplication {
    name = "backup-restore";
    runtimeInputs = [
      pkgs.zfs
      pkgs.coreutils
      pkgs.findutils
      # runuser, for dropping to the database superuser so the archive is
      # restored over the same peer-authenticated socket the dump job used.
      pkgs.util-linux
      pkgs.systemd
    ];
    text = ''
      BACKUP_COVERED_SERVICES=${lib.escapeShellArg coveredPairs}
      export BACKUP_COVERED_SERVICES

      # Named rather than found on the path, so the client that reads an archive
      # is always the same major version as the server that wrote it. A
      # pg_restore older than its archive refuses to run at all.
      PG_RESTORE_BIN=${lib.escapeShellArg "${postgresqlPackage}/bin/pg_restore"}
      export PG_RESTORE_BIN
      PG_SUPERUSER=${lib.escapeShellArg config.services.postgresql.superUser}
      export PG_SUPERUSER
    ''
    + builtins.readFile ./restore/backup-restore;
  };
in

{
  # On PATH so the operator can run it by name during an incident, which is the
  # only time it is ever run and not a moment to be hunting for a store path.
  environment.systemPackages = [ backupRestore ];
}
