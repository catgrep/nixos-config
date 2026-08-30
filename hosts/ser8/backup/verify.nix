# SPDX-License-Identifier: GPL-3.0-or-later

{
  config,
  lib,
  pkgs,
  ...
}:

let
  postgresqlPackage = config.services.postgresql.package;

  # The same destination the storage event daemon mails to. mail.nix asserts it
  # is set, so this cannot silently resolve to an empty recipient.
  recipients = config.services.zfs.zed.settings.ZED_EMAIL_ADDR or [ ];
  recipientLine = lib.concatStringsSep ", " (lib.toList recipients);

  manifestDir = "/persist/var/lib/backup-manifests";
  metricsDir = "/persist/var/lib/node-exporter-textfile";
in

{
  systemd.tmpfiles.rules = [
    # The nightly record of what was checked and which snapshot each service's
    # hold now sits on. World-readable directory, owner-only files: the
    # directory has to be traversable by whatever reads it later, and the files
    # themselves are written under a restrictive umask because they enumerate
    # every database path on the host.
    "d ${manifestDir} 0755 root root -"

    # Declared next to the only thing that writes into it, rather than beside
    # the exporter that reads it. Two properties are load-bearing and neither is
    # obvious: it must live under the persisted tree or the metrics are erased
    # by the boot-time rollback and the staleness alert fires on every reboot,
    # and it must sit outside any home directory because the exporter runs with
    # home directories hidden and would simply see nothing there.
    #
    # World-readable on purpose. The exporter runs as its own user and only
    # reads; the files carry timestamps, counts and byte totals, and nothing
    # that would matter if read.
    "d ${metricsDir} 0755 root root -"
  ];

  systemd.services.backup-verify = {
    description = "Verify the databases inside the newest persist snapshot";
    onFailure = [ "backup-failure-mail@%n.service" ];

    serviceConfig = {
      Type = "oneshot";

      # Root, and not negotiable. A snapshot preserves the live tree's
      # permissions, so this walk crosses owner-only directories belonging to
      # sixteen different service accounts. No single unprivileged user can read
      # all of them, and inventing one that could would mean either relaxing
      # those permissions or handing it an equivalent capability -- both worse
      # than root inside a tight sandbox. So the shape below is root that reads
      # everything and writes almost nowhere.
      User = "root";

      # The whole filesystem read-only by default. This job reads constantly and
      # writes to exactly two places, so strict costs nothing here and removes
      # everything else.
      ProtectSystem = "strict";

      # Both directories must be listed. Omitting the metrics directory breaks
      # the run at its final step -- which is the step whose absence the
      # staleness alert reports, so the failure would be detected correctly and
      # attributed to the wrong thing entirely.
      ReadWritePaths = [
        manifestDir
        metricsDir
      ];

      # The scratch space the database checks copy into. A private namespace
      # means no host path has to be writable for it and systemd cleans it up
      # however the run ends, including a kill.
      PrivateTmp = true;

      NoNewPrivileges = true;

      # Deliberately narrow, and each entry earns its place:
      #   DAC_READ_SEARCH  traverse and read the service directories inside the
      #                    snapshot, none of which root owns by mode
      #   DAC_OVERRIDE     read files whose mode excludes everyone but their
      #                    owner, which is most of what is being checked
      #   SYS_ADMIN        issue pool operations -- listing, reading snapshot
      #                    properties, and placing and releasing holds all go
      #                    through the pool control device, which refuses them
      #                    without it
      # Verified by running the unit rather than by copying a set from
      # elsewhere; a set that is too small fails in ways that read as file
      # permissions and cost an afternoon to trace.
      CapabilityBoundingSet = [
        "CAP_DAC_OVERRIDE"
        "CAP_DAC_READ_SEARCH"
        "CAP_SYS_ADMIN"
      ];

      # PrivateDevices is deliberately NOT set. It would hide the pool control
      # device this job needs, and the resulting failure looks exactly like a
      # permissions problem rather than a namespace one.
    };

    script = ''
      export ZFS_BIN="${pkgs.zfs}/bin/zfs"
      export SQLITE_BIN="${pkgs.sqlite}/bin/sqlite3"
      export PG_RESTORE_BIN="${postgresqlPackage}/bin/pg_restore"
      export FINDMNT_BIN="${pkgs.util-linux}/bin/findmnt"
      export MKTEMP_BIN="${pkgs.coreutils}/bin/mktemp"
      export CMP_BIN="${pkgs.diffutils}/bin/cmp"
      export SENDMAIL_BIN="/run/wrappers/bin/sendmail"
      export BACKUP_MAIL_TO=${lib.escapeShellArg recipientLine}
      source ${./verify.sh}
    '';
  };

  systemd.timers.backup-verify = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      # Half an hour after the nightly snapshot: enough for a steady-state
      # replication run to finish. Do not move it pre-emptively -- every run
      # records its own duration in the manifest, so move it when a measurement
      # asks for it.
      #
      # The timezone suffix is what makes "half an hour after" true, and leaving
      # it off is a mistake that hides rather than announces itself. The snapshot
      # tool's unit runs with the clock forced to UTC so its snapshot names stay
      # monotonic across daylight-saving changes, which means the nightly hour it
      # is configured with is a UTC hour. A bare time here would be read in local
      # time, and the two halves of one nightly cycle would sit seven or eight
      # hours apart -- far enough for the run to still pass its freshness window
      # and for nothing to ever report the drift.
      #
      # This must stay half an hour behind the snapshot hour in policy.nix. The
      # pair is local 03:30 in summer and 02:30 in winter, which is the quiet
      # window. Note the margin before the nightly upgrade is not fixed: that
      # timer is on local time and this one is not, so the gap is thirty minutes
      # in summer and ninety in winter. Judge it against the duration each run
      # records in the manifest rather than against this comment.
      OnCalendar = "10:30 UTC";

      # Only meaningful because the timer stamp directory is on persisted
      # storage. Before that, the stamps systemd reads at boot to notice a
      # missed run were erased before it looked, so a persistent timer here
      # quietly never replayed anything -- which reads as working.
      Persistent = true;
    };
  };
}
