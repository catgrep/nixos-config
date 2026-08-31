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

  # The unit's ExecCondition: exit 0 starts the verification, exit 1 skips it
  # without marking the unit failed, so OnFailure= stays quiet on the passes
  # that carry nothing. The copier pulls verification in behind every pass,
  # and most passes are no-ops; this guard is what keeps the heavy walk to
  # one run per new replica snapshot.
  #
  # It keys on the #replica_snapshot line of the latest manifest because the
  # manifest records which replica snapshot the last run saw. Comparing
  # against that makes verification idempotent per snapshot -- one attempt
  # per nightly, even when that attempt failed, since a failing run still
  # writes its manifest. A missing manifest reads as "nothing verified yet",
  # which runs the verification.
  #
  # No replica snapshot at all is a skip, not a failure: a copy that never
  # lands is the copier's own failure mail and the staleness alert's absence
  # arm, and a verification of nothing would bury that signal under a second
  # one. A gate that cannot run at all also lands on the skip side, and the
  # verify-staleness alert is what reports that within a day.
  verifyGate = pkgs.writeShellScript "backup-verify-gate" ''
    set -euo pipefail

    newest=$(${pkgs.zfs}/bin/zfs list -H -t snapshot -o name -s creation backup/persist-replica 2>/dev/null | grep '@autosnap_.*_daily$' | tail -1 || true)
    if [ -z "$newest" ]; then
      echo "no replica daily snapshot exists; skipping verification"
      exit 1
    fi
    newest=''${newest#*@}

    last=$(grep -m1 '^#replica_snapshot=' ${manifestDir}/latest.tsv 2>/dev/null | cut -d= -f2 || true)

    if [ "$newest" = "$last" ]; then
      echo "replica snapshot $newest is already recorded; skipping verification"
      exit 1
    fi
  '';
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

  # The copier pulls verification in behind itself, completing the nightly
  # chain: dump, snapshot, copy, verify -- one sequence hanging off sanoid's
  # hourly pass, with the guard above deciding which pass pays for the heavy
  # walk. This ordering is also what covers a machine that was off over the
  # nightly hour: the catch-up snapshot triggers a copy and then a
  # verification minutes after boot, at the moment there is something real to
  # verify, where a wall-clock trigger fires blind and can land before the
  # catch-up snapshot exists.
  systemd.services."syncoid-rpool-safe-persist".wants = [ "backup-verify.service" ];

  systemd.services.backup-verify = {
    description = "Verify the databases inside the newest persist snapshot";
    onFailure = [ "backup-failure-mail@%n.service" ];
    after = [ "syncoid-rpool-safe-persist.service" ];

    serviceConfig = {
      Type = "oneshot";
      ExecCondition = "${verifyGate}";

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

}
