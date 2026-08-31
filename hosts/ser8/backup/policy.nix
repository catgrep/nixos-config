# SPDX-License-Identifier: GPL-3.0-or-later

{ lib, ... }:

{
  services.sanoid = {
    enable = true;

    # Hourly, even though the only snapshot this keeps is a nightly one. sanoid
    # works out from the pool's own snapshot list whether the nightly is still
    # due, so waking it every hour is what lets it catch up after the machine
    # was off at the nightly hour.
    #
    # A once-a-day timer with Persistent=true would cover that same case, and it
    # would work here: the stamp directory those timers rely on is one of the
    # paths kept across the boot rollback. So this is the better of two workable
    # options rather than the only one. It is better because the two answer
    # different questions -- a stamp records whether this timer fired, the pool
    # records whether a nightly exists. Only the second is still right after a
    # snapshot is destroyed by hand or a restore rolls the tree back underneath
    # it. Deriving from the thing being protected beats deriving from a log of
    # past attempts.
    interval = "hourly";

    templates.persist = {
      autosnap = true;
      autoprune = true;

      # Every period is spelled out, including the zeros, and the zeros are the
      # reason this list exists. The NixOS module drops null-valued keys from
      # the config it generates, and sanoid then falls back to its own shipped
      # defaults -- 48 hourly, 90 daily and 6 monthly. An unset period does not
      # mean "none", it means "whatever sanoid ships"; only an explicit 0 means
      # none.
      frequently = 0;
      hourly = 0;
      daily = 30;
      weekly = 0;
      monthly = 0;
      yearly = 0;

      # Also a default worth fighting: sanoid ships daily_hour = 23 and
      # daily_min = 59, on the reasoning that a daily should contain everything
      # done during that day.
      #
      # Ten, and the number only makes sense once you know this unit's clock is
      # forced to UTC. That is upstream's doing and it is correct -- snapshot
      # names carry the timestamp, and naming them in a zone that jumps twice a
      # year produces two snapshots with the same name in autumn and a gap in
      # spring. The cost is that every hour written here is a UTC hour, so the
      # obvious-looking 3 does not mean three in the morning; on this host it
      # means eight in the evening, in the middle of the household using the
      # services being snapshotted. Ten UTC is local 03:00 in summer and 02:00
      # in winter, which is the quiet window this was always meant to be, and it
      # also makes the date in a snapshot's name agree with the local date it
      # was taken on rather than running a day ahead.
      #
      # Replication and verification hang off this same pass as unit
      # dependencies rather than owning clocks of their own, so the hour set
      # here is the only clock in the whole nightly cycle: move it and
      # everything downstream moves with it.
      daily_hour = 10;
      daily_min = 0;

      # Turns off sanoid's own deadline for hook scripts, which ships at five
      # seconds. No unit in this engine sets a timeout tighter than the systemd
      # default: a step that runs long is something the staleness alert should
      # report, whereas a step killed on a guessed deadline is an outage we
      # caused ourselves and then have to diagnose as though it were real.
      script_timeout = 0;
    };

    # A string, not a boolean, and the difference is the whole point. "zfs"
    # makes sanoid issue one recursive snapshot for the entire tree, so the
    # parent and every child are captured in a single transaction group under a
    # single name. Boolean recursion walks the children and snapshots them one
    # at a time, which is how one service ends up holding state from a
    # different instant than the service beside it.
    datasets."rpool/safe/persist" = {
      use_template = [ "persist" ];
      recursive = "zfs";
    };

    # Retention for the receiving side only. autosnap is off because sanoid must
    # never create a snapshot on the replica: snapshots there arrive inside the
    # send stream, and a locally created one has no counterpart on the source
    # for the next incremental to work from.
    #
    # Ninety nights against the source's thirty. The backup array has room to
    # spare and steady-state increments are small, so the extra sixty nights
    # cost little and buy the case that actually matters -- noticing damage
    # long after it happened.
    templates.replica = {
      autosnap = false;
      autoprune = true;
      frequently = 0;
      hourly = 0;
      daily = 90;
      weekly = 0;
      monthly = 0;
      yearly = 0;
    };

    datasets."backup/persist-replica" = {
      use_template = [ "replica" ];
      recursive = "zfs";
    };
  };

  services.syncoid = {
    enable = true;

    # sanoid owns snapshot creation. Without this, syncoid takes its own
    # snapshot before each send, leaving a second set of snapshots on a second
    # retention scheme that nothing is pruning.
    commonArgs = [ "--no-sync-snap" ];

    commands."rpool/safe/persist" = {
      target = "backup/persist-replica";
      recursive = true;

      # -u leaves the received dataset unmounted, and it is doing real work
      # today: the receive runs unprivileged, and on Linux the mount permission
      # cannot be delegated at all, so a receive that tries to mount does not
      # degrade gracefully, it fails outright.
      #
      # -x mountpoint guards a hazard that is latent rather than active. Dataset
      # properties only travel in a send stream when the send is asked to carry
      # them, and the send options here are empty, so today no mountpoint
      # arrives at all and the replica inherits mountpoint=none from the backup
      # pool root. Add p or R to those send options, though, and the source's
      # mountpoint starts arriving with the data -- at which point the replica
      # of /var/lib/donetick would carry that exact path and could mount over
      # the live directory, hiding running state behind a copy. Keeping -x means
      # that day stays a one-line change instead of an outage.
      #
      # There is deliberately no `o readonly=on` here, and it is worth recording
      # why not, because it looks like free defence in depth. Setting a property
      # on receive is a delegated permission, the receive runs unprivileged, and
      # nothing on this host delegates it -- so the receive emits one "cannot
      # receive readonly property: permission denied" per dataset, eighteen per
      # run, every hour, and the property never lands. That is worse than
      # omitting it: the errors are noise that trains the reader to ignore this
      # unit's logs, and the replica reads `readonly off` anyway, so anyone who
      # trusted the setting would be trusting nothing. Delegating the permission
      # to make it work would widen what the replication account can change on
      # the backup pool, to protect against a hazard -- a hand-run `zfs set
      # mountpoint` followed by an editing mistake -- that mountpoint=none and
      # the restore tool's own read-only mount already cover.
      recvOptions = "u x mountpoint";

      # Leaves a bookmark on the source for each snapshot sent, so the next
      # incremental still has a common ancestor to work from even when the
      # snapshot it would have used was pruned in the meantime.
      extraArgs = [ "--create-bookmark" ];
    };
  };

  # The copier follows the snapshot pass instead of owning a clock. sanoid
  # wakes hourly and decides from the pool whether tonight's snapshot is due,
  # so running the copy as a completion barrier behind that same pass means
  # the pass that produces a snapshot is the pass that copies it -- catch-up
  # after an outage included. Most passes find nothing new and exit in
  # seconds. Two independent hourly timers firing at the shared tick would
  # race, and the copy would slide a full hour past the snapshot -- far
  # enough for the verification behind it to read the replica as a day old.
  #
  # wants + after, the same idiom that orders the database dump ahead of the
  # snapshot in dump.nix. after= is only a completion barrier against a unit
  # whose start job lasts as long as its process, which is what Type=oneshot
  # means; both tools ship as simple services, whose start job ends the
  # moment the process forks. Left simple, the copy starts while the snapshot
  # is still being taken, and the verification behind the copy reads the
  # replica mid-send, finds nothing new, and skips the night -- so both are
  # forced oneshot, and the ordering below becomes real.
  systemd.services.sanoid = {
    wants = [ "syncoid-rpool-safe-persist.service" ];
    serviceConfig.Type = lib.mkForce "oneshot";
  };
  systemd.services."syncoid-rpool-safe-persist" = {
    after = [ "sanoid.service" ];
    serviceConfig.Type = lib.mkForce "oneshot";

    # An empty startAt is how "no timer of its own" is spelled: the syncoid
    # module derives a timer unit from this option, and the chain above is
    # the only trigger this unit is meant to have.
    startAt = lib.mkForce [ ];
  };
}
