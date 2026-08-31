# SPDX-License-Identifier: GPL-3.0-or-later

{ pkgs }:

let
  inherit (pkgs) lib;

  # The covered set, imported from the same file the engine reads. The guest
  # stands up one unit per entry under the entry's real unit name -- the two
  # names that do not follow from their directories (hass ->
  # home-assistant.service, tailscale -> tailscaled.service) are exactly the
  # ones a hand-written list drifts on -- and the test script derives its
  # service list from the same attrset, so a service added to services.nix
  # extends this suite without edits here.
  coveredServices = import ../hosts/ser8/backup/services.nix;

  # postgresql is covered but gets no stand-in: the guest runs the real
  # server, because the dump, archive-verification and single-database
  # restore paths need a live catalog behind them.
  standIns = lib.filterAttrs (_: cfg: cfg.unit != "postgresql.service") coveredServices;

  # Leaves a database behind with a live write-ahead log beside it. Closing the
  # last connection cleanly checkpoints the log and deletes it, so the writer is
  # killed instead. That is the only way to get a log into a snapshot, and it is
  # also exactly the state a real crash leaves for a restore to recover from --
  # which is the thing the verification claims it can do.
  seedWalDatabase = pkgs.writeShellScriptBin "seed-wal-database" ''
    set -euo pipefail
    db=$1
    rows=$2

    ${pkgs.sqlite}/bin/sqlite3 "$db" \
    	"PRAGMA journal_mode=WAL; CREATE TABLE IF NOT EXISTS t(id INTEGER PRIMARY KEY, v BLOB);"
    ${pkgs.sqlite}/bin/sqlite3 "$db" \
    	"WITH RECURSIVE c(x) AS (SELECT 1 UNION ALL SELECT x+1 FROM c WHERE x<$rows)
    	 INSERT INTO t(v) SELECT randomblob(4096) FROM c;"

    fifo=$(mktemp -u)
    mkfifo "$fifo"
    ${pkgs.sqlite}/bin/sqlite3 "$db" <"$fifo" >/dev/null &
    writer=$!
    exec 3>"$fifo"
    printf 'INSERT INTO t(v) VALUES (randomblob(4096));\n' >&3
    printf 'SELECT count(*) FROM t;\n' >&3
    sleep 2
    kill -9 "$writer" || true
    exec 3>&-
    rm -f "$fifo"

    # Fail closed. Without a log on disk the copy-and-open path is trivially
    # satisfied and every assertion built on it would be worthless.
    test -e "$db-wal"
  '';

  # There is no mail transport in the guest and none is wanted. The digest and
  # the failure paths still have to run end to end, and a delivery failure is a
  # failure of the verification run, so the wrapper has to exist and succeed.
  sendmailStub = pkgs.writeShellScriptBin "sendmail" ''
    exec ${pkgs.coreutils}/bin/cat >/dev/null
  '';
in

pkgs.testers.runNixOSTest {
  name = "backup-behavior";

  nodes.machine =
    { pkgs, ... }:
    {
      # The real host slice, imported unmodified -- these tests are worth
      # nothing if they exercise a copy of the policy rather than the policy.
      #
      # datasets.nix is deliberately absent. Its assertions read fileSystems
      # entries that disko generates from ser8's physical disk declarations, and
      # this machine has two scratch disks and no disko config, so including it
      # would fail the build for a reason unrelated to anything tested here.
      imports = [
        ../hosts/ser8/backup/dump.nix
        ../hosts/ser8/backup/mail.nix
        ../hosts/ser8/backup/policy.nix
        ../hosts/ser8/backup/restore.nix
        ../hosts/ser8/backup/verify.nix
      ];

      # Twelve gigabytes each: the interrupted-replication assertion sends a
      # gigabyte of incompressible data, the crash-during-verification one
      # spreads another gigabyte of database copies, and both pools have to
      # hold all of it alongside the snapshots the rest of the script
      # accumulates. The images are sparse, so the headroom costs nothing
      # until it is used.
      virtualisation.emptyDiskImages = [
        12288
        12288
      ];
      boot.supportedFilesystems = [ "zfs" ];
      # Matching the host's setting rather than the module default, which warns.
      # Nothing here is imported at boot -- the pools are created by the test
      # script on scratch disks -- so this only settles the warning.
      boot.zfs.forceImportRoot = false;
      networking.hostId = "2d833f3e";
      environment.systemPackages = [
        pkgs.parted
        pkgs.sqlite
        seedWalDatabase
      ];

      # The script moves the guest clock by weeks to reach retention and
      # catch-up behaviour. A time daemon that decided to correct it mid-test
      # would turn every one of those assertions into a coin flip.
      services.timesyncd.enable = false;

      # The destination the slice reads its recipient from. mail.nix refuses to
      # build without one, which is the point of that assertion.
      services.zfs.zed.settings.ZED_EMAIL_ADDR = [ "backup-test@example.invalid" ];

      # /run/wrappers/bin/sendmail, non-setuid, exactly the shape the mail
      # transport module uses on the real host.
      security.wrappers.sendmail = {
        source = "${sendmailStub}/bin/sendmail";
        owner = "root";
        group = "root";
        setuid = false;
        setgid = false;
      };

      # A real server, pinned to the same major the host pins, with one
      # non-template database so the catalog enumeration has something to find
      # beyond the superuser's own.
      services.postgresql = {
        enable = true;
        package = pkgs.postgresql_17;
        ensureDatabases = [ "mealie" ];
      };

      # One stand-in per covered service, under the covered unit's real name.
      # The restore path needs units it can stop and start and nothing more;
      # pulling in the real services would drag their packages along without
      # making any assertion here stronger. What matters is the name: the
      # restore tool stops the unit services.nix records, so a stand-in under
      # any other name would let the mapping rot while every test stayed green.
      systemd.services =
        lib.mapAttrs' (
          name: cfg:
          lib.nameValuePair (lib.removeSuffix ".service" cfg.unit) {
            description = "Stand-in for the ${name} service";
            wantedBy = [ "multi-user.target" ];
            serviceConfig = {
              ExecStart = "${pkgs.coreutils}/bin/sleep infinity";
              Restart = "always";
            };
          }
        ) standIns
        // {
          # The real server must not start before its covered dataset exists:
          # the script starts it once the pool is built, so the first start
          # runs initdb into the dataset rather than into a root filesystem
          # the test never snapshots. Emptying the service's own wantedBy is
          # not enough -- postgresql.target is what multi-user pulls in, and
          # the target drags the service with it, initdb and all; a dataset
          # mounted over that datadir leaves a running server writing through
          # open handles into a directory nothing can see or snapshot.
          postgresql.wantedBy = lib.mkForce [ ];
        };
      systemd.targets.postgresql.wantedBy = lib.mkForce [ ];

      # The script moves the clock by weeks and reboots the guest with crashes,
      # and the pass's persistent timer fires within seconds of every boot --
      # early enough to run a whole chain pass before any test code can stop
      # it, stamping metrics and consuming resume tokens the crash assertions
      # are about to read. The timer unit still exists (the wiring subtest
      # reads it), but nothing activates it: every pass in here is driven by
      # hand.
      systemd.timers.sanoid.wantedBy = lib.mkForce [ ];
    };

  testScript = ''
    import re

    METRICS = "/persist/var/lib/node-exporter-textfile/backup.prom"
    MANIFEST = "/persist/var/lib/backup-manifests/latest.tsv"
    DUMPS = "var/lib/backup-dumps"

    # Service name -> unit name, generated from services.nix itself. Every
    # per-service assertion below iterates this mapping, so the suite's
    # coverage is the covered set by construction, irregular unit names
    # included.
    SERVICES = ${builtins.toJSON (lib.mapAttrs (_: cfg: cfg.unit) coveredServices)}


    def settle_chain():
        """Wait until a started pass has fully drained.

        Starting the snapshot pass queues the copy behind it and the
        verification behind that, so the moment the snapshot unit returns is
        not the moment the night is over. Every assertion that reads state the
        chain writes has to wait for the queue to empty, or it measures a race
        instead of the engine.
        """
        machine.wait_until_succeeds(
            "! systemctl list-jobs | grep -qE 'sanoid|syncoid|backup-'",
            timeout=600,
        )


    def sanoid_pass():
        """One full pass of the chain: snapshot decision, copy, verification."""
        machine.systemctl("start --wait sanoid.service")
        settle_chain()


    def crash_and_boot():
        """Pull the power, then come back up.

        The clock is put back to the moment of the crash. The script has moved
        it forward by weeks and the emulated hardware clock has not, so a guest
        that booted on its own reckoning would believe every snapshot it owns
        came from the future -- and the policy, which decides from pool state,
        would conclude nothing had ever been due.
        """
        epoch = int(machine.succeed("date +%s").strip())
        machine.crash()
        machine.start()
        machine.wait_for_unit("multi-user.target")
        machine.succeed(f"date -s @{epoch}")
        # Neither pool is in the boot configuration -- both are built by this
        # script on scratch disks -- so nothing imports them automatically.
        machine.succeed("zpool import -f -a || true")
        machine.succeed("zfs mount -a")
        # The real server is started by this script, not by the boot, so a
        # reboot has to bring it back the same way.
        machine.succeed("systemctl start postgresql.target")
        machine.wait_for_unit("postgresql.service")


    def snapshot_names(dataset, prefix=""):
        out = machine.succeed(
            f"zfs list -H -t snapshot -o name -s creation {dataset} || true"
        )
        names = [line.split("@")[1] for line in out.split() if "@" in line]
        return [n for n in names if n.startswith(prefix)]


    def autosnaps(dataset):
        return sorted(snapshot_names(dataset, "autosnap"))


    def dailies(dataset="rpool/safe/persist"):
        return [n for n in snapshot_names(dataset, "autosnap") if n.endswith("_daily")]


    def newest_daily(dataset="rpool/safe/persist"):
        found = dailies(dataset)
        assert found, f"{dataset} has no daily snapshot"
        return found[-1]


    def tree_datasets():
        out = machine.succeed("zfs list -H -r -o name rpool/safe/persist")
        return out.split()


    def hold_of(dataset):
        """The snapshot this dataset's last-verified hold sits on, or None."""
        out = machine.succeed(
            f"zfs list -H -t snapshot -o name {dataset} || true"
        ).split()
        if not out:
            return None
        held = machine.succeed("zfs holds -H " + " ".join(out) + " || true")
        for line in held.splitlines():
            fields = line.split("\t")
            if len(fields) >= 2 and fields[1] == "last-verified":
                return fields[0].split("@")[1]
        return None


    def release_all_holds():
        """Unpin every last-verified hold.

        The verification pins the newest snapshot it proved good, and that
        pinning has subtests of its own. The retention assertions ask a
        different question -- what the window destroys -- and a hold left in
        place would answer it for them.
        """
        for dataset in tree_datasets():
            held = hold_of(dataset)
            if held:
                machine.succeed(f"zfs release last-verified {dataset}@{held}")


    def tree_fingerprint(service):
        """Content, not just presence. Two restores that produce the same bytes
        are the same restore; a listing or a preview that changed one byte is
        caught here rather than by inspection."""
        return machine.succeed(f"find /var/lib/{service} -type f | sort | xargs -r md5sum")


    def snapshot_fingerprint(dataset):
        return machine.succeed(f"zfs list -H -t snapshot -o name -s creation {dataset} || true")


    def manifest_header():
        out = machine.succeed(f"cat {MANIFEST}")
        header = {}
        for line in out.splitlines():
            if line.startswith("#"):
                key, _, value = line[1:].partition("=")
                header[key] = value
        return header


    def manifest_rows():
        out = machine.succeed(f"cat {MANIFEST}")
        return [line.split("\t") for line in out.splitlines() if not line.startswith("#")]


    def take_daily(name):
        """A recursive snapshot under the tool's own naming shape.

        Recursive because that is what the policy issues, and because the
        all-or-none assertion below would otherwise be testing this helper's
        sloppiness rather than the engine's behaviour.
        """
        machine.succeed(f"zfs snapshot -r rpool/safe/persist@{name}")


    def advance_clock(days):
        machine.succeed(f"date -s '+{days} days'")


    def nightly():
        """One night: the clock moves on and the pass runs -- snapshot, copy
        and verification in one chain. Returns the snapshot that night
        produced.

        The clock has to move. The policy decides from pool state whether a
        nightly is still due, so two runs inside the same day produce one
        snapshot -- and an assertion about "the new snapshot" would quietly be
        about the old one, which is how a test certifies a change it never saw.
        """
        before = set(dailies())
        advance_clock(1)
        sanoid_pass()
        taken = set(dailies()) - before
        assert taken, "the policy took no snapshot on a new night"
        return sorted(taken)[-1]


    def run_verification():
        """Run the verification on demand and return its status alongside its
        own account of what happened.

        The gate holds the verification to one run per replica snapshot by
        comparing against the latest manifest, so an on-demand re-run has to
        clear that memory first. The gate's own behaviour is asserted in its
        dedicated subtest; here it is deliberately opened so the assertions
        measure the verification, not the gate.

        The unit names the step it failed at, so carrying the journal into the
        assertion message is the difference between a failure that explains
        itself and one that needs a second run to investigate."""
        machine.succeed(f"rm -f {MANIFEST}")
        status, _ = machine.systemctl("start --wait backup-verify.service")
        journal = machine.succeed("journalctl -u backup-verify.service --no-pager -n 80")
        return status, journal


    def prune_only():
        """Run the prune half of the policy on its own.

        The scheduled invocation takes and prunes in the same pass, and it
        prunes against the snapshot list it read before taking -- so the
        snapshot the run itself creates survives on top of the window and the
        total reads one higher than the configured number. That is correct
        behaviour and not what the retention rule is being asked about here, so
        the assertions below drive the prune path directly. The invocation is
        read back off the real unit rather than written out again, because a
        second copy of the policy is a second thing to drift.
        """
        execstart = " ".join(
            machine.succeed("systemctl show -p ExecStart --value sanoid.service").split()
        )
        # Anchored at the store prefix on purpose: the property value repeats the
        # binary as "path=<store path>" before the argument vector, and a looser
        # pattern picks up that "path=" and turns the command into a shell
        # variable assignment that silently runs nothing.
        found = re.search(
            r"(/nix/store/[^\s;]+/bin/sanoid) --cron --configdir (/nix/store/[^\s;]+)",
            execstart,
        )
        assert found, f"could not read the policy invocation from the unit: {execstart}"
        return machine.execute(
            f"{found.group(1)} --prune-snapshots --configdir {found.group(2)} 2>&1"
        )


    def assert_snapshot_names_are_all_or_none(context):
        """Every nightly name is on every dataset in the tree, or on none.

        Scoped to the automatic names on purpose: the rollback anchor below is
        deliberately placed on one dataset only, and sweeping it in here would
        make this assertion fail for the one case that is supposed to look like
        that.
        """
        per_dataset = {ds: set(snapshot_names(ds, "autosnap")) for ds in tree_datasets()}
        every_name = set().union(*per_dataset.values())
        for name in every_name:
            holders = [ds for ds, names in per_dataset.items() if name in names]
            assert len(holders) == len(per_dataset), (
                f"{context}: {name} exists on {holders} but not on every dataset "
                f"in {sorted(per_dataset)}"
            )


    machine.wait_for_unit("multi-user.target")

    with subtest("the snapshot pass owns the only timer and pulls everything else"):
        # The nightly cycle is one chain hanging off one clock. Each edge is
        # asserted from the loaded units rather than from the configuration
        # that generated them, so a refactor that drops an edge fails here and
        # not on the host.
        machine.succeed("systemctl cat sanoid.timer > /dev/null")
        machine.fail("systemctl cat syncoid-rpool-safe-persist.timer 2> /dev/null")
        machine.fail("systemctl cat backup-verify.timer 2> /dev/null")

        wants = machine.succeed("systemctl show -p Wants --value sanoid.service")
        assert "backup-pgdump.service" in wants, "the pass does not pull the dumps"
        assert "syncoid-rpool-safe-persist.service" in wants, (
            "the pass does not pull the copy"
        )
        after = machine.succeed(
            "systemctl show -p After --value syncoid-rpool-safe-persist.service"
        )
        assert "sanoid.service" in after, "the copy is not ordered behind the snapshot"
        wants = machine.succeed(
            "systemctl show -p Wants --value syncoid-rpool-safe-persist.service"
        )
        assert "backup-verify.service" in wants, "the copy does not pull the verification"
        after = machine.succeed("systemctl show -p After --value backup-verify.service")
        assert "syncoid-rpool-safe-persist.service" in after, (
            "the verification is not ordered behind the copy"
        )

        # after= is a completion barrier only against a oneshot unit; against a
        # simple one it is a launch order, and the copy would start mid-snapshot
        # while the verification gate reads the replica mid-send and skips the
        # night. Every link in the chain therefore has to be oneshot.
        for unit in [
            "backup-pgdump.service",
            "sanoid.service",
            "syncoid-rpool-safe-persist.service",
            "backup-verify.service",
        ]:
            kind = machine.succeed(f"systemctl show -p Type --value {unit}").strip()
            assert kind == "oneshot", (
                f"{unit} is Type={kind}; the ordering behind it is a launch order, "
                f"not a completion barrier"
            )

    # Pin the guest to midday UTC before anything asks the policy for a
    # snapshot. The policy only takes a nightly once the clock is past its
    # configured hour, and the guest otherwise inherits whatever time the build
    # machine happened to be at -- so every assertion resting on "a night
    # passed" was silently conditional on the builder's wall clock being late
    # enough in the day. That made the whole suite fail for a few hours out of
    # every twenty-four, on a machine nobody was watching, for a reason that
    # looks nothing like a clock problem. Midday is comfortably past the
    # configured hour and far from either midnight, so the day arithmetic the
    # script does from here cannot land on a boundary either.
    today = machine.succeed("date -u +%Y-%m-%d").strip()
    machine.succeed(f"date -u -s '{today} 12:00:00'")

    # The pools are named rpool and backup, exactly as on the real host, so
    # every dataset path below is the production path verbatim. A parameterised
    # pool name would let the test keep passing while the real paths drifted.
    machine.succeed(
        "parted --script /dev/vdb -- mklabel msdos mkpart primary 1024M -1s",
        "parted --script /dev/vdc -- mklabel msdos mkpart primary 1024M -1s",
        "udevadm settle",
        "zpool create -O mountpoint=none -O compression=lz4 rpool /dev/vdb1",
        "zpool create -O mountpoint=none -O compression=lz4 backup /dev/vdc1",
        "zfs create rpool/safe",
        "zfs create -o mountpoint=/persist rpool/safe/persist",
    )
    # One dataset per covered service, exactly as the layout declares on the
    # host. The loop runs off the derived mapping, so a service added to the
    # covered set gets a dataset here without edits.
    for service in SERVICES:
        machine.succeed(
            f"zfs create -o mountpoint=/var/lib/{service} -o atime=off "
            f"rpool/safe/persist/{service}"
        )
    machine.succeed("udevadm settle")

    # The dump and manifest directories were created at boot under the root
    # filesystem, which the persist dataset has just mounted over. Re-run the
    # rules now that the real tree is there.
    machine.succeed("systemd-tmpfiles --create")

    # The mountpoint arrives root-owned from the pool, and the server's first
    # start refuses a data directory it cannot write. The target rather than
    # the service, so the setup unit that creates the declared databases runs
    # with it.
    machine.succeed("chown postgres:postgres /var/lib/postgresql")
    machine.succeed("systemctl start postgresql.target")
    machine.wait_for_unit("postgresql.service")

    # A snapshot whose name does not carry sanoid's automatic prefix. It stands
    # in for the impermanence rollback anchor on the real host, which must
    # survive every prune sanoid ever runs.
    machine.succeed("zfs snapshot rpool/safe/persist/donetick@keep-me-anchor")

    machine.succeed("echo original-state > /var/lib/donetick/sentinel")

    # Two databases with live write-ahead logs, sized either side of the
    # threshold that selects the check: donetick's takes the full structural
    # check, mealie's the page-level one. Both branches are then exercised by
    # every verification run below rather than by argument.
    machine.succeed("seed-wal-database /var/lib/donetick/app.db 2000")
    machine.succeed("seed-wal-database /var/lib/mealie/app.db 20000")

    with subtest("a restore with no verification evidence refuses rather than guessing"):
        # A snapshot exists, but nothing has ever verified one, so there is no
        # manifest and no hold for the default to resolve. The newest snapshot
        # is the one most likely to contain whatever went wrong, so the tool
        # must not silently fall back to it; refusing is the only honest
        # answer. This runs before the first pass on purpose -- the pass
        # verifies as part of its chain, and evidence, once written, cannot be
        # unwritten.
        probe = f"autosnap_{today}_00:00:01_daily"
        take_daily(probe)
        machine.fail("backup-restore donetick --force")
        machine.succeed(f"zfs destroy -r rpool/safe/persist@{probe}")

    with subtest("one recursive snapshot covers parent and child in one transaction group"):
        sanoid_pass()
        parent = autosnaps("rpool/safe/persist")
        child = autosnaps("rpool/safe/persist/donetick")
        assert parent, "sanoid took no snapshot of rpool/safe/persist"
        assert parent == child, (
            f"recursive snapshot names diverged: parent={parent} child={child}"
        )

    with subtest("one pass replicates and verifies with no further trigger, then the gate skips"):
        # Nothing here starts the copy or the verification; the pass above did.
        snap = newest_daily()
        assert snap in snapshot_names("backup/persist-replica", "autosnap"), (
            "the pass did not replicate its own snapshot"
        )
        header = manifest_header()
        assert header["snapshot"] == snap and header["status"] == "ok", (
            f"the pass did not verify its own snapshot: {header}"
        )

        # The same replica snapshot again: the gate must skip, and a skip is
        # not a failure -- the unit ends condition-failed, so the failure mail
        # hooked to OnFailure= stays quiet. The skip is read from the journal
        # rather than from unit properties: systemd unloads an idle unit, and
        # the properties of an unloaded unit read as defaults.
        def gate_skips():
            return int(machine.succeed(
                "journalctl -u backup-verify.service --no-pager "
                "| grep -c \"Skipped due to 'exec-condition'\" || true"
            ).strip())

        metrics_before = machine.succeed(f"cat {METRICS}")
        skips = gate_skips()
        machine.systemctl("start --wait backup-verify.service")
        assert gate_skips() == skips + 1, "the gate re-ran an already-recorded snapshot"
        machine.fail("systemctl is-failed --quiet backup-verify.service")
        metrics_after = machine.succeed(f"cat {METRICS}")
        assert metrics_before == metrics_after, "a skipped run still stamped the metrics"
        mail_started = machine.succeed(
            "systemctl show -p ActiveEnterTimestamp --value "
            "'backup-failure-mail@backup-verify.service.service'"
        ).strip()
        assert mail_started in ("", "n/a"), (
            f"a gate skip raised the failure mail at {mail_started}"
        )

    with subtest("replication leaves the replica unmounted"):
        machine.systemctl("start --wait syncoid-rpool-safe-persist.service")
        settle_chain()
        mounted = machine.succeed(
            "zfs get -H -o value mounted backup/persist-replica/donetick"
        ).strip()
        assert mounted == "no", f"replica is mounted ({mounted}); a receive mounted it"

    with subtest("no replica dataset can shadow a live service directory"):
        mountpoints = machine.succeed(
            "zfs get -r -H -o value mountpoint backup/persist-replica"
        )
        offenders = [m for m in mountpoints.split() if m.startswith("/var/lib")]
        assert not offenders, f"replica carries live mountpoints: {offenders}"

        # The check above states the outcome, and on its own it would pass for
        # the wrong reason: nothing is currently asking the send to carry
        # properties, so no mountpoint reaches the replica whether or not the
        # receive excludes one. This pins the mechanism instead. A mountpoint
        # that arrived with the data would show up here as "received" or
        # "local"; only one the replica worked out from its own parent reads as
        # "inherited". It is the assertion that starts failing the day someone
        # adds p or R to the send options and drops the receive-side exclusion.
        # Reported as "inherited from <dataset>", so match the prefix.
        source = machine.succeed(
            "zfs get -H -o source mountpoint backup/persist-replica/donetick"
        ).strip()
        assert source.startswith("inherited"), (
            f"replica mountpoint came from the send stream, not its parent: {source}"
        )

    with subtest("replication leaves no delegated permissions behind"):
        residue = machine.succeed("zfs allow rpool/safe/persist")
        assert len(residue) == 0, f"delegation residue on the source: {residue!r}"

    with subtest("pruning ignores snapshots it did not create"):
        sanoid_pass()
        machine.succeed("zfs list -H -t snapshot rpool/safe/persist/donetick@keep-me-anchor")

    with subtest("a service's state survives the round trip out of a snapshot"):
        machine.succeed("rm -f /var/lib/donetick/sentinel")
        machine.fail("test -e /var/lib/donetick/sentinel")

        # Named explicitly on purpose: this asserts the copy path on its own,
        # independent of how the default resolves a snapshot. The default has
        # its refusal asserted above and its resolution asserted further down.
        early_snapshot = newest_daily("rpool/safe/persist/donetick")
        machine.succeed(f"backup-restore donetick --force --snapshot {early_snapshot}")

        restored = machine.succeed("cat /var/lib/donetick/sentinel").strip()
        assert restored == "original-state", f"restored the wrong content: {restored!r}"
        machine.succeed("systemctl is-active donetick.service")

    with subtest("a restore refuses to overwrite live state or accept an unknown service"):
        before = machine.succeed("find /var/lib/donetick -type f | sort | xargs md5sum")
        machine.fail(f"backup-restore donetick --snapshot {early_snapshot}")
        after = machine.succeed("find /var/lib/donetick -type f | sort | xargs md5sum")
        assert before == after, "a refused restore modified the live directory anyway"

        machine.fail(f"backup-restore not-a-service --force --snapshot {early_snapshot}")

    with subtest("the dumps ride inside the snapshot"):
        # The dump job is ordered ahead of the snapshot rather than clocked
        # separately, so simply running the snapshot unit is what produces
        # them -- there is no dump timer to start here, and that is the point.
        sanoid_pass()
        snap = newest_daily()
        view = f"/persist/.zfs/snapshot/{snap}/{DUMPS}"

        catalog = machine.succeed(
            "sudo -u postgres psql -Atc "
            "\"select datname from pg_database where not datistemplate and datallowconn\""
        ).split()
        assert catalog, "the catalog returned no databases to look for"

        machine.succeed(f"test -s {view}/globals.sql")
        for database in catalog:
            machine.succeed(f"test -s {view}/{database}.dump")
            machine.succeed(f"pg_restore --list {view}/{database}.dump > /dev/null")

    # The retention assertions below measure the window on its own, so the
    # pinning the pass's verification has already applied is lifted first.
    release_all_holds()

    with subtest("retention destroys nothing while the floor is unmet"):
        # Every existing nightly is now well over the thirty-day window, and
        # there are far fewer than thirty of them. An implementation that
        # honours only the age half of the rule empties the window here, which
        # is precisely what an outage would otherwise cost.
        before_floor = dailies()
        assert 0 < len(before_floor) < 30, f"the floor case needs under 30, got {before_floor}"
        advance_clock(31)

        status, output = prune_only()
        assert status == 0, f"the prune run failed: {output}"

        survivors = dailies()
        missing = [n for n in before_floor if n not in survivors]
        assert not missing, f"over-age snapshots were destroyed below the floor: {missing}"

    with subtest("retention prunes down to the configured window"):
        for day in range(1, 41):
            take_daily(f"autosnap_2026-01-{day:02d}_03:00:00_daily")
        assert len(dailies()) > 30, "the window case needs more than 30 dailies"

        advance_clock(31)
        status, output = prune_only()
        assert status == 0, f"the prune run failed: {output}"

        survivors = dailies()
        assert len(survivors) == 30, f"expected 30 dailies after pruning, got {len(survivors)}"

        with subtest("a missed nightly is taken on the next run rather than at the next slot"):
            before_catchup = set(dailies())
            advance_clock(2)
            sanoid_pass()
            appeared = set(dailies()) - before_catchup
            assert appeared, "no snapshot was taken after a missed nightly slot"
            survivors = dailies()

        # The assertions from here on are about verification and holds, not
        # retention, and a full window would let pruning interfere with them.
        # Clear it deliberately rather than leaving the interaction implicit.
        # The catch-up pass just verified its own snapshot and holds it, so
        # the pins come off before the destroy.
        release_all_holds()
        for name in survivors:
            machine.succeed(f"zfs destroy -r rpool/safe/persist@{name}")


    with subtest("a healthy snapshot verifies, and is recorded"):
        clean_snapshot = nightly()

        status, journal = run_verification()
        assert status == 0, f"verification failed on a healthy snapshot:\n{journal}"

        header = manifest_header()
        assert header["status"] == "ok", f"manifest status is {header['status']!r}"
        assert header["snapshot"] == clean_snapshot, (
            f"manifest describes {header['snapshot']}, not {clean_snapshot}"
        )
        for service in SERVICES:
            assert service in header["covered"].split(), (
                f"{service} is missing from the covered set {header['covered']!r}"
            )

        metrics = machine.succeed(f"cat {METRICS}")
        for name in [
            "backup_last_snapshot_timestamp_seconds",
            "backup_last_replica_timestamp_seconds",
            "backup_last_verify_timestamp_seconds",
            "backup_verified_files",
            "backup_persist_written_bytes",
            "backup_persist_usedbysnapshots_bytes",
        ]:
            assert name in metrics, f"{name} is missing from the metrics file"

        # Both size branches were taken, which is what makes the recorded check
        # name evidence rather than decoration.
        checks = {row[2] for row in manifest_rows() if row[0] == "sqlite"}
        assert {"integrity_check", "quick_check"} <= checks, (
            f"only these checks ran: {checks}"
        )

    with subtest("a clean night advances every hold to the newest snapshot"):
        for dataset in tree_datasets():
            assert hold_of(dataset) == clean_snapshot, (
                f"{dataset} holds {hold_of(dataset)}, not {clean_snapshot}"
            )

        for row in manifest_rows():
            if row[0] == "dataset":
                assert row[5] == clean_snapshot, (
                    f"manifest records {row[1]} held at {row[5]}, not {clean_snapshot}"
                )

    with subtest("a corrupt database fails the verification and leaves the metrics alone"):
        metrics_before = machine.succeed(f"cat {METRICS}")

        # A snapshot is read-only, so the only honest way to get a corrupt
        # database into one is to damage the live file and then snapshot it.
        # The overwritten run sits well past the header, inside the page area,
        # and is far larger than the small live log can replay over.
        machine.succeed("systemctl stop donetick.service")
        machine.succeed(
            "dd if=/dev/urandom of=/var/lib/donetick/app.db bs=4096 seek=64 count=16 "
            "conv=notrunc"
        )
        machine.succeed("systemctl start donetick.service")

        # The night's own chained verification fails on the damage too; the
        # on-demand run below is what the assertions read, so the failure is
        # measured with the journal in hand.
        corrupt_snapshot = nightly()
        assert corrupt_snapshot != clean_snapshot, (
            "the damage never reached a snapshot, so nothing new was checked"
        )

        status, journal = run_verification()
        assert status != 0, (
            f"a corrupt database inside the snapshot verified as healthy:\n{journal}"
        )
        # Failing for the right reason. Without this the assertion above would
        # be satisfied by any failure at all, including one caused by the test
        # itself.
        assert "integrity_check" in journal and "app.db" in journal, (
            f"the run failed, but not on the damaged database:\n{journal}"
        )

        metrics_after = machine.succeed(f"cat {METRICS}")
        assert metrics_before == metrics_after, (
            "a failing verification refreshed the freshness metrics"
        )

        header = manifest_header()
        assert header["status"] == "fail", f"manifest status is {header['status']!r}"

    with subtest("a failed dataset keeps its hold while a clean sibling advances"):
        assert hold_of("rpool/safe/persist/donetick") == clean_snapshot, (
            "the damaged dataset's hold moved off the last snapshot it verified clean"
        )
        assert hold_of("rpool/safe/persist/mealie") == corrupt_snapshot, (
            "a clean dataset was held back by an unhealthy neighbour"
        )

        for row in manifest_rows():
            if row[0] == "dataset" and row[1] == "rpool/safe/persist/donetick":
                assert row[5] == clean_snapshot, (
                    f"the manifest points a restore at {row[5]}, not the last good snapshot"
                )

    with subtest("a held snapshot survives a prune driven past the retention window"):
        for day in range(1, 41):
            take_daily(f"autosnap_2026-02-{day:02d}_03:00:00_daily")
        advance_clock(31)

        # The prune's own result is asserted rather than only the snapshot list,
        # because whether a refused destroy is fatal to the run was the open
        # question here. Observed answer: it is not. The tool logs "cannot
        # destroy snapshot ...: it's being held" for each refusal and exits 0.
        #
        # That is worth knowing rather than worth changing. It means the
        # pathological case -- verification failing for a whole retention window
        # so that the hold sits on the oldest snapshot pruning wants -- produces
        # no noise from the prune at all. The only signal in that case is the
        # verification's own failure mail, which by then has fired every night
        # for thirty nights, so nothing is actually silent.
        prune_status, prune_output = machine.systemctl("start --wait sanoid.service")
        settle_chain()
        partial = [
            name
            for name in set().union(*(set(dailies(ds)) for ds in tree_datasets()))
            if any(name not in dailies(ds) for ds in tree_datasets())
        ]
        print(f"prune against a held snapshot: exit={prune_status} partial={sorted(partial)}")
        print(prune_output)

        survivors = dailies("rpool/safe/persist/donetick")
        assert clean_snapshot in survivors, (
            f"pruning destroyed the last proven-good snapshot (prune exited "
            f"{prune_status}: {prune_output})"
        )
        assert prune_status == 0, (
            f"the prune now treats a refused destroy as fatal (exit {prune_status}); "
            f"the comment above records it as survivable and needs revisiting"
        )
        assert partial, (
            "the prune destroyed a held nightly name cleanly across the tree, which "
            "the hold is supposed to make impossible"
        )

    # The prune above cannot finish cleanly, and it does not unwind what it
    # managed to do first, so some nightly names now exist on part of the tree.
    # That is a consequence of the hold doing its job and not a defect, but the
    # crash assertions below are about names landing on part of the tree, so the
    # tree is put back to one consistent state here rather than leaving them to
    # measure this.
    for dataset in tree_datasets():
        for name in dailies(dataset):
            machine.succeed(f"zfs release last-verified {dataset}@{name} || true")
            machine.succeed(f"zfs destroy {dataset}@{name} || true")

    # Back to a healthy tree, so the crash assertions below measure the crash
    # and not the damage.
    machine.succeed("systemctl stop donetick.service")
    machine.succeed("rm -f /var/lib/donetick/app.db /var/lib/donetick/app.db-wal")
    machine.succeed("rm -f /var/lib/donetick/app.db-shm")
    machine.succeed("seed-wal-database /var/lib/donetick/app.db 2000")
    machine.succeed("systemctl start donetick.service")

    with subtest("a verified night is what the restore tool resolves by default"):
        for service in SERVICES:
            machine.succeed(f"echo {service}-sentinel > /var/lib/{service}/restore-sentinel")

        # A row that will exist only inside the portable archive this night
        # writes. The database restore further down is then proven by data that
        # came back rather than by an exit status.
        machine.succeed(
            "sudo -u postgres psql -q -d mealie -c "
            "'create table if not exists drill(id int primary key, note text)'"
        )
        machine.succeed(
            "sudo -u postgres psql -q -d mealie -c "
            "\"insert into drill values (1, 'rode-inside-the-snapshot')\""
        )

        verified_snapshot = nightly()
        status, journal = run_verification()
        assert status == 0, f"the night every assertion below rests on failed:\n{journal}"
        assert manifest_header()["snapshot"] == verified_snapshot, (
            "the manifest does not describe the night just run"
        )
        for dataset in tree_datasets():
            assert hold_of(dataset) == verified_snapshot, (
                f"{dataset} is not held at {verified_snapshot}, so the default cannot resolve"
            )

    with subtest("the restore path round-trips every covered service"):
        # Every entry in the covered set, through its real unit name. The
        # postgresql entry restores a crash-consistent data directory under a
        # live server's feet -- stopped by the tool, recovered on start --
        # which is exactly the drill the manifest promises an operator.
        for service, unit in SERVICES.items():
            machine.succeed(f"rm -f /var/lib/{service}/restore-sentinel")
            # No --snapshot. The default has to reach the verified snapshot
            # through the manifest and prove the pool still holds it.
            status, out = machine.execute(f"backup-restore {service} --force 2>&1")
            assert status == 0, f"backup-restore {service} --force failed:\n{out}"
            restored = machine.succeed(f"cat /var/lib/{service}/restore-sentinel").strip()
            assert restored == f"{service}-sentinel", (
                f"{service} restored the wrong content: {restored!r}"
            )
            machine.succeed(f"systemctl is-active {unit}")
        machine.succeed("rm -rf /var/lib/*.pre-restore-*")

    with subtest("the default refuses when the manifest and the pool disagree"):
        # A hold released by hand is the realistic way these two drift apart,
        # and preferring either one silently is the failure this refusal exists
        # to prevent: the manifest would name a snapshot nothing is protecting.
        machine.succeed(
            f"zfs release last-verified rpool/safe/persist/donetick@{verified_snapshot}"
        )
        status, output = machine.execute("backup-restore donetick --force 2>&1")
        assert status != 0, "a restore proceeded on a snapshot the pool no longer holds"
        assert verified_snapshot in output and "hold" in output, (
            f"the refusal does not name what disagrees:\n{output}"
        )
        machine.succeed(
            f"zfs hold last-verified rpool/safe/persist/donetick@{verified_snapshot}"
        )
        machine.succeed("backup-restore donetick --force")
        machine.succeed("rm -rf /var/lib/*.pre-restore-*")

    with subtest("listing prints a service's snapshots in order and marks the verified one"):
        before_tree = tree_fingerprint("donetick")
        before_snaps = snapshot_fingerprint("rpool/safe/persist/donetick")

        listing = machine.succeed("backup-restore donetick --list")
        rows = [line for line in listing.splitlines() if line.startswith("autosnap")]
        assert rows, f"the listing produced no snapshot rows:\n{listing}"

        listed = [row.split()[0] for row in rows]
        expected = [
            line.split("@")[1]
            for line in machine.succeed(
                "zfs list -H -t snapshot -o name -s creation rpool/safe/persist/donetick"
            ).split()
            if "@" in line and line.split("@")[1].startswith("autosnap")
        ]
        assert listed == expected, f"the listing is not in creation order: {listed} vs {expected}"

        marked = [row for row in rows if "last verified" in row]
        assert len(marked) == 1 and marked[0].startswith(verified_snapshot), (
            f"the listing does not mark exactly the held snapshot:\n{listing}"
        )

        assert machine.succeed("systemctl is-active donetick.service").strip() == "active"
        assert tree_fingerprint("donetick") == before_tree, "the listing changed the live directory"
        assert snapshot_fingerprint("rpool/safe/persist/donetick") == before_snaps, (
            "the listing changed the snapshot list"
        )

        # The operator wants to know what the replica holds precisely when the
        # source is the problem, so the listing has to reach it too.
        replica_listing = machine.succeed("backup-restore donetick --list --from replica")
        assert verified_snapshot in replica_listing, (
            f"the replica listing is missing the verified snapshot:\n{replica_listing}"
        )

    with subtest("a restore from the replica produces what a restore from the source produces"):
        machine.succeed("rm -f /var/lib/donetick/restore-sentinel")
        machine.succeed("backup-restore donetick --force --from source")
        from_source = tree_fingerprint("donetick")

        machine.succeed("rm -f /var/lib/donetick/restore-sentinel")
        machine.succeed("backup-restore donetick --force --from replica")
        from_replica = tree_fingerprint("donetick")

        assert from_source == from_replica, (
            f"the replica restored different content:\n{from_source}\n{from_replica}"
        )
        machine.succeed("systemctl is-active donetick.service")

        # Reading the replica means mounting it, and the tool has to put it back
        # the way it found it -- otherwise the next receive lands on a mounted
        # dataset and the assertion above about live mountpoints starts failing
        # for a reason nobody would connect to a restore.
        mounted = machine.succeed(
            "zfs get -H -o value mounted backup/persist-replica/donetick"
        ).strip()
        assert mounted == "no", f"the tool left the replica mounted ({mounted})"
        origin = machine.succeed(
            "zfs get -H -o source mountpoint backup/persist-replica/donetick"
        ).strip()
        assert origin.startswith("inherited"), (
            f"the tool left a mountpoint behind on the replica: {origin}"
        )
        machine.succeed("rm -rf /var/lib/*.pre-restore-*")

    with subtest("the destructive rollback is unreachable without both of its flags"):
        before_snaps = snapshot_fingerprint("rpool/safe/persist/donetick")
        for command in [
            "backup-restore donetick --rollback",
            f"backup-restore donetick --rollback --snapshot {verified_snapshot}",
        ]:
            status, output = machine.execute(f"{command} 2>&1")
            assert status != 0, f"{command!r} reached the destructive path with one flag"
            assert "--force" in output, f"the refusal does not name the missing flag:\n{output}"
        assert snapshot_fingerprint("rpool/safe/persist/donetick") == before_snaps, (
            "a refused rollback destroyed a snapshot anyway"
        )
        machine.succeed("systemctl is-active donetick.service")

    with subtest("the destructive rollback is refused against the replica in every combination"):
        before_snaps = snapshot_fingerprint("backup/persist-replica/donetick")
        for extra in ["", "--force", f"--force --snapshot {verified_snapshot}"]:
            status, output = machine.execute(
                f"backup-restore donetick --rollback --from replica {extra} 2>&1"
            )
            assert status != 0, f"rollback against the replica was accepted with {extra!r}"
            assert "replica" in output, f"the refusal does not say why:\n{output}"
        assert snapshot_fingerprint("backup/persist-replica/donetick") == before_snaps, (
            "a refused rollback against the replica destroyed a snapshot anyway"
        )

    with subtest("a single database comes back from the archive that rode inside the snapshot"):
        machine.succeed("sudo -u postgres psql -q -d mealie -c 'delete from drill where id = 1'")
        remaining = machine.succeed(
            "sudo -u postgres psql -Atc 'select count(*) from drill' -d mealie"
        ).strip()
        assert remaining == "0", f"the row was still there before the restore: {remaining}"

        machine.succeed("backup-restore mealie --force --pg-database mealie")

        note = machine.succeed(
            "sudo -u postgres psql -Atc 'select note from drill where id = 1' -d mealie"
        ).strip()
        assert note == "rode-inside-the-snapshot", (
            f"the database restore did not repopulate the row: {note!r}"
        )
        machine.succeed("systemctl is-active mealie.service")
        machine.succeed("rm -rf /var/lib/*.pre-restore-*")

    with subtest("an unrecognised invocation refuses and explains itself"):
        before_tree = tree_fingerprint("donetick")
        for command in [
            "backup-restore donetick --nonsense",
            "backup-restore",
            "backup-restore donetick --from elsewhere",
        ]:
            status, output = machine.execute(f"{command} 2>&1")
            assert status != 0, f"{command!r} was accepted"
            assert "usage: backup-restore" in output, f"{command!r} printed no usage:\n{output}"
        assert tree_fingerprint("donetick") == before_tree, (
            "a refused invocation changed the live directory"
        )

        flags = [
            "--snapshot",
            "--force",
            "--list",
            "--from",
            "--rollback",
            "--pg-database",
            "--dry-run",
        ]
        usage = machine.succeed("backup-restore --help")
        for flag in flags:
            assert flag in usage, f"{flag} is missing from the usage output"

        examples = [
            line.strip()
            for line in usage.splitlines()
            if line.strip().startswith("backup-restore ")
        ]
        assert len(examples) >= 3, f"fewer than three worked examples in the usage:\n{usage}"
        for example in examples:
            for word in example.split():
                assert not word.startswith("--") or word in flags, (
                    f"the usage example names a flag the tool does not have: {word!r}"
                )

    with subtest("the preview resolves every mode and performs none of it"):
        def observable(service):
            return (
                tree_fingerprint(service),
                snapshot_fingerprint(f"rpool/safe/persist/{service}"),
                snapshot_fingerprint(f"backup/persist-replica/{service}"),
                machine.succeed(f"systemctl is-active {SERVICES[service]}").strip(),
                machine.succeed(
                    f"zfs get -H -o value mounted backup/persist-replica/{service}"
                ).strip(),
            )

        previews = [
            ("a copy from the source", "donetick", "backup-restore donetick --force --dry-run"),
            (
                "a copy from the replica",
                "donetick",
                "backup-restore donetick --force --from replica --dry-run",
            ),
            (
                "the destructive rollback",
                "donetick",
                "backup-restore donetick --force --rollback --dry-run",
            ),
            (
                "a database restore",
                "mealie",
                "backup-restore mealie --force --pg-database mealie --dry-run",
            ),
        ]

        for label, service, command in previews:
            before = observable(service)
            output = machine.succeed(command)
            assert observable(service) == before, f"the preview of {label} changed something"

            assert verified_snapshot in output, f"the preview of {label} names no snapshot:\n{output}"
            assert "last verified" in output, f"the preview of {label} does not say why:\n{output}"
            assert f"/var/lib/{service}" in output, f"the preview of {label} names no target:\n{output}"
            assert f"{service}.service" in output, f"the preview of {label} names no unit:\n{output}"

            if "--rollback" in command:
                assert "would destroy" in output, (
                    f"the rollback preview does not say what it would destroy:\n{output}"
                )
            else:
                assert "pre-restore-" in output, (
                    f"the preview of {label} names no move-aside destination:\n{output}"
                )

            if "--pg-database" in command:
                assert "backup-dumps/mealie.dump" in output, (
                    f"the database preview names no archive:\n{output}"
                )

        # An honest rehearsal fails exactly where the real run would.
        machine.fail("backup-restore donetick --force --dry-run --snapshot autosnap_1970-01-01_daily")
        machine.fail("backup-restore not-a-service --force --dry-run")

    with subtest("the destructive rollback replaces the state when both flags are given"):
        # The refusals above prove the guards. Without this the mechanism they
        # guard would never once have been executed, and a typo in it would
        # surface for the first time during an incident.
        machine.succeed("echo written-after-the-snapshot > /var/lib/donetick/post-snapshot")
        machine.succeed("backup-restore donetick --force --rollback")

        machine.fail("test -e /var/lib/donetick/post-snapshot")
        restored = machine.succeed("cat /var/lib/donetick/restore-sentinel").strip()
        assert restored == "donetick-sentinel", (
            f"the rollback restored the wrong content: {restored!r}"
        )
        machine.succeed("systemctl is-active donetick.service")

    with subtest("a file named like a database but holding something else is not a failure"):
        # The real host carries fifty of these: a GPU driver keeps its shader
        # cache as mesa_cache.db, and a message broker keeps its own format as
        # mosquitto.db. Neither is SQLite and neither ever will be, so a run
        # that reports them as corrupt fails every night on files that are
        # exactly as they should be.
        machine.succeed(
            "printf 'MESA_DB\\0\\1\\0\\0\\0' > /var/lib/donetick/mesa_cache.db"
        )

        nightly()
        status, journal = run_verification()
        assert status == 0, f"a file that is not a database failed the run:\n{journal}"

        rows = [r for r in manifest_rows() if r[0] == "sqlite" and r[1].endswith("mesa_cache.db")]
        assert len(rows) == 1, f"the non-database was not recorded at all: {rows}"
        assert "not-a-database" in rows[0][3], (
            f"it was recorded, but not as what it is: {rows[0]}"
        )
        assert "MESA_DB" in rows[0][3], (
            f"the row does not say what the file turned out to be: {rows[0]}"
        )

    with subtest("a database whose header is destroyed is still a failure"):
        # The cost of deciding by content is that a database damaged badly
        # enough to lose its header looks like a file that never was one. A
        # write-ahead log is created by SQLite and by nothing else, so a file
        # carrying one without the header was a database and no longer opens as
        # one -- which is the worst case, not an exemption from checking.
        machine.succeed("seed-wal-database /var/lib/donetick/wrecked.db 100")
        machine.succeed("test -e /var/lib/donetick/wrecked.db-wal")
        machine.succeed(
            "dd if=/dev/zero of=/var/lib/donetick/wrecked.db bs=16 count=1 conv=notrunc"
        )

        nightly()
        status, journal = run_verification()
        assert status != 0, (
            f"a database with a destroyed header passed as 'not a database':\n{journal}"
        )
        assert "wrecked.db" in journal and "sidecar" in journal, (
            f"the run failed, but not on the wrecked database:\n{journal}"
        )

        header = manifest_header()
        assert header["status"] == "fail", f"manifest status is {header['status']!r}"

        # And the harmless one beside it is still not being blamed.
        rows = [r for r in manifest_rows() if r[0] == "sqlite" and r[1].endswith("mesa_cache.db")]
        assert rows and "not-a-database" in rows[0][3], (
            f"the non-database was reclassified by an unrelated failure: {rows}"
        )

        # Put the tree back, so the run that follows measures the repair rather
        # than the damage.
        machine.succeed("rm -f /var/lib/donetick/wrecked.db /var/lib/donetick/wrecked.db-wal")
        machine.succeed("rm -f /var/lib/donetick/wrecked.db-shm")
        nightly()
        status, journal = run_verification()
        assert status == 0, f"the tree did not recover once the damage was removed:\n{journal}"

    # ------------------------------------------------------------------
    # Crash resilience.
    #
    # What is under test here is this engine's orchestration across an abrupt
    # stop: whether an interrupted transfer resumes, whether a freshness stamp
    # can outlive a run that did not finish, and whether a snapshot name can
    # land on part of the tree. The filesystem's own transaction-group
    # atomicity is inherited from the storage layer and is deliberately not
    # re-proven here. Each of these uses the guest crash facility rather than a
    # graceful stop, because the failure being modelled is power loss.
    # ------------------------------------------------------------------

    with subtest("an interrupted replication resumes rather than restarting"):
        # A gigabyte, and the size is the assertion's whole reliability. The
        # crash has to land inside *donetick's* receive, and the only signal
        # available for that is the replica growing -- which can only be polled
        # about once a second. A payload that transfers in under a second is
        # therefore over before the first poll returns, and whether a resume
        # token exists afterwards becomes luck rather than behaviour. At roughly
        # 300 MB/s in here a gigabyte takes several seconds, which is wide enough
        # that a poll cannot step over the whole window.
        machine.succeed("dd if=/dev/urandom of=/var/lib/donetick/bulk bs=1M count=1024")

        # Measured on the child rather than on the whole replica, and before
        # the pass starts: the copy is queued behind the snapshot by the chain
        # itself, so the transfer is already moving by the time the snapshot
        # unit returns. The tree is sent one dataset at a time, so growth of
        # the parent's total says only that some dataset is receiving -- and
        # the one being asserted about below may already be finished by then.
        used_before = int(
            machine.succeed(
                "zfs get -Hp -o value used backup/persist-replica/donetick"
            ).strip()
        )
        before = set(dailies())
        advance_clock(1)
        machine.systemctl("start --wait sanoid.service")
        pending = sorted(set(dailies()) - before)[-1]

        # Crash once data is provably in flight rather than after a guessed
        # delay, which in a virtual machine is not a signal at all.
        machine.wait_until_succeeds(
            "test $(zfs get -Hp -o value used backup/persist-replica/donetick) -gt "
            f"{used_before + 64 * 1024 * 1024}",
            timeout=300,
        )
        crash_and_boot()

        token = machine.succeed(
            "zfs get -H -o value receive_resume_token backup/persist-replica/donetick"
        ).strip()
        assert token != "-", "an interrupted receive left no resume token"

        machine.systemctl("start --wait syncoid-rpool-safe-persist.service")

        consumed = machine.succeed(
            "zfs get -H -o value receive_resume_token backup/persist-replica/donetick"
        ).strip()
        assert consumed == "-", f"the resume token was not consumed: {consumed}"
        assert pending in snapshot_names("backup/persist-replica/donetick"), (
            f"the replica never reached {pending}"
        )
        # The manual copy pulled the verification in behind it, exactly as the
        # nightly pass does; let it drain before the next subtest measures
        # anything.
        settle_chain()

        assert_snapshot_names_are_all_or_none("after the interrupted replication")

    with subtest("a crash before the verification finishes leaves the metric unstamped"):
        # A dozen more copies of the large database -- about a gigabyte -- so
        # the run has enough to copy out and check that it is unambiguously
        # still in flight when the power goes. With less, the caches are warm
        # from the night's own verification and the run finishes before the
        # crash lands, which would make this assertion pass without ever
        # testing anything.
        for extra in range(12):
            machine.succeed(f"cp /var/lib/mealie/app.db /var/lib/mealie/extra{extra:02d}.db")
        nightly()
        metrics_before = machine.succeed(f"cat {METRICS}")
        # The stamp just read was written seconds ago and the crash below cuts
        # power before the pool would commit it on its own; without forcing it
        # to stable storage, the comparison after boot measures transaction
        # rollback instead of the verification's stamping discipline.
        machine.succeed("sync && zpool sync")

        # The power goes immediately after the job is queued rather than after
        # waiting to observe it mid-run: any wait long enough to be reliable is
        # also long enough to miss the run. The gate is opened by hand first,
        # because the night's own pass has already recorded this replica
        # snapshot and would otherwise skip the run this crash needs to land in.
        #
        # Crashing early cannot make this pass vacuously. The metrics recorded
        # above carry the finished pass's verification timestamp, so a run that
        # did finish before the crash would have replaced them -- the
        # comparison below fails in exactly the case where the crash landed too
        # late to prove anything.
        machine.succeed(f"rm -f {MANIFEST}")
        machine.succeed("systemctl start --no-block backup-verify.service")
        crash_and_boot()

        metrics_after = machine.succeed(f"cat {METRICS} || true")
        assert metrics_after in ("", metrics_before), (
            "a verification that never finished still stamped the freshness metric"
        )

        assert_snapshot_names_are_all_or_none("after the crash during verification")

    with subtest("the pass after a crash heals the whole cycle with no timer involved"):
        # The catch-up case: after an outage, the first pass takes the
        # snapshot, the chain copies and verifies it, and the metrics come back
        # fresh -- with nothing having replayed a wall-clock trigger at boot.
        metrics_before = machine.succeed(f"cat {METRICS} || true")
        healed = nightly()
        assert healed in snapshot_names("backup/persist-replica", "autosnap"), (
            "the catch-up pass did not replicate its snapshot"
        )
        header = manifest_header()
        assert header["snapshot"] == healed and header["status"] == "ok", (
            f"the catch-up pass did not verify its snapshot: {header}"
        )
        metrics_after = machine.succeed(f"cat {METRICS}")
        assert metrics_after != metrics_before, (
            "the catch-up pass left the freshness metrics stale"
        )

    with subtest("a crash during the policy run leaves no snapshot on part of the tree"):
        advance_clock(1)
        machine.succeed("systemctl start --no-block sanoid.service")
        crash_and_boot()

        assert_snapshot_names_are_all_or_none("after the crash during the policy run")

  '';
}
