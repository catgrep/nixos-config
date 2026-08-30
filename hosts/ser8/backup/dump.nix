# SPDX-License-Identifier: GPL-3.0-or-later

{ config, ... }:

let
  postgresqlPackage = config.services.postgresql.package;
  superUser = config.services.postgresql.superUser;

  # Everything in this slice mails on failure through one templated unit. %n is
  # the failing unit's own name, so each unit below needs no per-unit message.
  onFailureMail = [ "backup-failure-mail@%n.service" ];
in

{
  # The dump directory belongs to the database superuser because that account
  # writes it, and the unit runs as that account so no password or socket
  # authentication has to be configured. It cannot create the directory itself:
  # /persist/var/lib is root-owned, so the first mkdir would fail on a fresh
  # host and take the whole run with it.
  #
  # Mode 0700 is the point of declaring it here rather than letting the script
  # settle for whatever it inherits. These archives are complete copies of every
  # database on the host, sitting in a tree that is snapshotted and replicated;
  # anything world-readable here is world-readable in thirty snapshots too.
  systemd.tmpfiles.rules = [
    "d /persist/var/lib/backup-dumps 0700 ${superUser} ${superUser} -"
  ];

  systemd.services.backup-pgdump = {
    description = "PostgreSQL logical dumps into the persisted tree";
    onFailure = onFailureMail;

    # Ordering only, no dependency. The snapshot timer fires on the hour, so a
    # machine that booted shortly before one can reach this job while the server
    # is still starting -- and the mail that failure sends would describe a
    # problem that does not exist. Ordering is enough because the server is part
    # of the same boot transaction; making it a requirement instead would mean a
    # backup job could start a database, which is not a side effect a backup job
    # should have.
    after = [ "postgresql.service" ];

    serviceConfig = {
      Type = "oneshot";
      User = superUser;

      # RemainAfterExit is deliberately unset. A oneshot that stays active after
      # a successful run is already active the next time something wants it, so
      # it would run once at boot and never again -- which is the opposite of
      # what the ordering below is for.

      # The whole filesystem read-only except the one directory this job
      # writes into. Smaller attack surface than backup-verify already, since
      # this runs unprivileged as the database superuser rather than root, but
      # there is no reason to leave it unrestricted when the write target is a
      # single known directory.
      ProtectSystem = "strict";
      ReadWritePaths = [ "/persist/var/lib/backup-dumps" ];
      PrivateTmp = true;
      NoNewPrivileges = true;
    };

    # Binaries come from the pinned server package rather than the path, so the
    # dump tools always match the major version of the server they are dumping.
    # A pg_dump older than its server refuses to run at all.
    script = ''
      export PG_DUMP_BIN="${postgresqlPackage}/bin/pg_dump"
      export PG_DUMPALL_BIN="${postgresqlPackage}/bin/pg_dumpall"
      export PG_RESTORE_BIN="${postgresqlPackage}/bin/pg_restore"
      export PSQL_BIN="${postgresqlPackage}/bin/psql"
      source ${./dump.sh}
    '';
  };

  # The dumps are refreshed by the snapshot job rather than by a timer of their
  # own, and the difference matters. A separately clocked timer fires at a wall
  # time; the snapshot job wakes hourly and acts only when a nightly is due, so
  # it is the only thing that knows which run is the one that will produce a
  # snapshot. Ordering the dump ahead of it means every snapshot carries dumps
  # no older than that hour -- including the catch-up snapshot taken after the
  # machine was off, which a fixed-time timer would miss by however long the
  # outage lasted.
  #
  # wants, not requires, and that is the load-bearing choice: a failed dump must
  # never suppress the night's snapshot. The snapshot is a complete
  # crash-consistent image of the whole tree with or without a portable archive
  # inside it, and losing it because a database was unreachable would trade the
  # backup for the nice-to-have. The failed dump still raises mail on its own.
  #
  # Type=oneshot means started equals finished, so after= here is a real
  # completion barrier rather than a launch order.
  #
  # Not the snapshot tool's own pre-snapshot hook, which is the obvious-looking
  # choice and the wrong one: that hook runs under a dynamic user that can reach
  # neither the database nor the persisted tree without either weakening the
  # unit's hardening or adding a policy rule, and it ships a five-second script
  # deadline. Plain unit ordering needs none of that.
  systemd.services.sanoid = {
    wants = [ "backup-pgdump.service" ];
    after = [ "backup-pgdump.service" ];
    onFailure = onFailureMail;
  };

  systemd.services.syncoid-rpool-safe-persist.onFailure = onFailureMail;
}
