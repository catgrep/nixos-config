# SPDX-License-Identifier: GPL-3.0-or-later

{ config, lib, ... }:

let
  # The address the ZFS event daemon already mails to. Read from there rather
  # than written here, so the host keeps one mail destination and one place to
  # change it.
  recipients = config.services.zfs.zed.settings.ZED_EMAIL_ADDR or [ ];
  recipientLine = lib.concatStringsSep ", " (lib.toList recipients);
in

{
  # An unconfigured destination would leave every unit below mailing nowhere,
  # which is indistinguishable from a night on which nothing failed. Turn it
  # into a build failure instead.
  assertions = [
    {
      assertion = recipientLine != "";
      message = ''
        The backup slice sends its failure mail to the same address the ZFS
        event daemon uses, and that address is unset.

        Set services.zfs.zed.settings.ZED_EMAIL_ADDR on this host, or remove
        ./mail.nix from hosts/ser8/backup/default.nix along with every
        onFailure that names it.
      '';
    }
  ];

  # A batch job that fails at three in the morning and says nothing is
  # indistinguishable from one that never ran. The staleness alerting added
  # later covers absence -- a metric that stopped being stamped -- which is the
  # quiet case. This covers the loud one, and it covers it within seconds
  # rather than at the next scrape.
  #
  # Templated on the failing unit's name, so every unit in this slice hangs its
  # failure handling on one implementation: onFailure = [
  # "backup-failure-mail@%n.service" ] and nothing else to write per unit.
  systemd.services."backup-failure-mail@" = {
    description = "Mail the status of %i after it failed";

    serviceConfig = {
      Type = "oneshot";
      User = "root";

      # The delivery path the storage event daemon already uses. Naming it here
      # rather than inside the script body keeps it visible in the rendered
      # unit, where anyone debugging a missing mail will look first.
      Environment = [ "SENDMAIL_BIN=/run/wrappers/bin/sendmail" ];
    };

    # %i is the failing unit's full name, expanded by systemd in the command
    # line. Specifiers are not expanded inside the script body, so it arrives
    # as an argument.
    scriptArgs = "%i";

    script = ''
      failed_unit=$1

      {
        printf 'To: %s\n' ${lib.escapeShellArg recipientLine}
        printf 'Subject: [%s] %s failed\n' ${lib.escapeShellArg config.networking.hostName} "$failed_unit"
        printf '\n'
        # Bounded deliberately. An unbounded tail of a unit that failed in a
        # loop is a mail nobody reads, and the journal has the rest.
        systemctl status --full --lines=50 -- "$failed_unit" || true
      } | "$SENDMAIL_BIN" -t
    '';
  };
}
