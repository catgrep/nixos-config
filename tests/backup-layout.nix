# SPDX-License-Identifier: GPL-3.0-or-later

{ pkgs, diskoLib }:

diskoLib.testLib.makeDiskoTest {
  inherit pkgs;
  name = "backup-layout";
  disko-config = ./backup-layout-disko.nix;

  # ZFS refuses to import a pool without a host id, and the installer and the
  # installed system are separate machines here, so both need one. Matching
  # them is also what lets the boot import the installer's pool without being
  # forced to, so forceImportRoot stays off exactly as it is on the host.
  extraInstallerConfig = {
    networking.hostId = "2d833f3e";
    boot.zfs.forceImportRoot = false;
  };
  extraSystemConfig = {
    networking.hostId = "2d833f3e";
    boot.zfs.forceImportRoot = false;
  };

  extraTestScript = ''
    # Every covered service, in the same order as the declarations. Driving the
    # assertions from one list is what keeps adding a service to a single edit.
    services = [
        "actual",
        "bazarr",
        "donetick",
        "frigate",
        "hass",
        "homebox",
        "jellyfin",
        "mealie",
        "mosquitto",
        "nzbget",
        "postgresql",
        "prowlarr",
        "radarr",
        "sabnzbd",
        "sonarr",
        "tailscale",
    ]


    def get_property(dataset, prop, field):
        return machine.succeed(f"zfs get -H {prop} {dataset} -o {field}").rstrip()


    def assert_property(dataset, prop, expected, source=None):
        """Check a property's value, and optionally where the value came from.

        The source matters as much as the value. A child that inherited
        atime=off from its parent reads identically to one that sets it, right
        up until someone changes the parent -- at which point the value flips
        with nothing to notice. Requiring "local" is how the declaration's
        intent gets checked rather than its coincidence.
        """
        actual = get_property(dataset, prop, "value")
        assert actual == expected, (
            f"{dataset}: expected {prop}={expected}, got {actual}"
        )
        if source is not None:
            actual_source = get_property(dataset, prop, "source")
            assert actual_source == source, (
                f"{dataset}: expected {prop} to be {source}, got {actual_source} "
                f"(value {actual} is right for the wrong reason)"
            )


    with subtest("the persist dataset exists and is mounted"):
        assert_property("rpool/safe/persist", "mountpoint", "legacy")
        machine.succeed("mountpoint /persist")
        source = machine.succeed("findmnt -n -o SOURCE /persist").rstrip()
        assert source == "rpool/safe/persist", f"/persist comes from {source}"

    with subtest("every covered service has its own dataset, mounted at its own path"):
        for service in services:
            dataset = f"rpool/safe/persist/{service}"
            path = f"/var/lib/{service}"
            machine.succeed(f"zfs list -H -o name {dataset}")
            assert_property(dataset, "mountpoint", "legacy")
            machine.succeed(f"mountpoint {path}")

            # Existing and mounted is not the same as mounted from the right
            # place. Without this, a stray dataset covering the path would pass
            # everything above while the service's state went somewhere nobody
            # snapshots.
            source = machine.succeed(f"findmnt -n -o SOURCE {path}").rstrip()
            assert source == dataset, f"{path} is mounted from {source}, not {dataset}"

    with subtest("nothing else lives under the persist dataset"):
        listed = machine.succeed(
            "zfs list -H -o name -r rpool/safe/persist"
        ).split()
        expected = ["rpool/safe/persist"] + [
            f"rpool/safe/persist/{service}" for service in services
        ]
        assert sorted(listed) == sorted(expected), (
            "the persist tree does not match the covered set: "
            f"unexpected={sorted(set(listed) - set(expected))} "
            f"missing={sorted(set(expected) - set(listed))}"
        )

    with subtest("access-time updates are off on every child, and set there"):
        for service in services:
            assert_property(
                f"rpool/safe/persist/{service}", "atime", "off", source="local"
            )

    with subtest("only the database child overrides the record size"):
        assert_property(
            "rpool/safe/persist/postgresql", "recordsize", "16K", source="local"
        )
        for service in services:
            if service == "postgresql":
                continue
            # "default", not merely 128K: an inherited 128K would read the same
            # while meaning someone had started tuning the parent.
            assert_property(
                f"rpool/safe/persist/{service}",
                "recordsize",
                "128K",
                source="default",
            )
  '';
}
