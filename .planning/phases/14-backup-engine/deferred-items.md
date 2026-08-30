# Deferred items — phase 14

Out-of-scope discoveries logged during execution rather than fixed in place.

## `stdenv.isDarwin` deprecation warning from the sagent subflake

Found during plan 14-02, task 2.

`tools/sagent/outputs.nix:105` (and the example in `tools/sagent/README.md:34`)
still use `pkgs.stdenv.isDarwin`, which nixpkgs deprecated in favour of
`pkgs.stdenv.hostPlatform.isDarwin`. The warning prints on every evaluation of
the root flake, including every `nix build`, `nix eval` and `make check`.

The two uses in the root `flake.nix` were fixed in this plan because they sat in
a file being edited. The subflake's were not: `sagent` is a `path:` input with
its own lock entry, so changing it means re-locking, and a lock update is not
something to fold silently into a storage change.

## Prometheus rule unit tests are not wired into `make check`

Found during plan 14-04, task 2.

The three staleness alert rules were validated with `promtool test rules`
against a hand-written test file, including a mutation run proving the absence
arm is load-bearing: stripping `or absent(...)` makes the never-ran case return
no alert at all. That test file was not committed, because there is no harness
for Prometheus rule tests in this repository and building one is its own
change.

The rules therefore carry a comment explaining why they must not be written as
a bare threshold, and nothing mechanical stops a future edit from removing the
absence arm. A `checks.x86_64-linux.prometheus-rules` output running
`promtool test rules` over the rendered rule file would close that gap.

## `CLAUDE.md` lists an `overlays/` directory that does not exist

Found during plan 14-06, task 3 preparation.

The repository layout section of `CLAUDE.md` (and therefore `AGENTS.md`, which
is a symlink to it) says "`overlays/` contains package overrides". There is no
`overlays/` directory in the tree and no reference to one anywhere. Harmless to
a human reader, but it sends an agent looking for package overrides in a place
that cannot hold them, which is exactly the kind of drift that guide is meant to
prevent. A one-line deletion, deferred because it belongs with a pass over the
whole layout section rather than as a drive-by edit inside a storage change.

## Chain the nightly cycle by unit completion instead of by wall-clock gap

Operator decision, 2026-08-29. Follow-up work, deliberately not this plan
("fine for now").

The cycle currently couples its three steps two different ways: the dump is
ordered ahead of the snapshot by a unit relation, and the verification is
ordered after it by being on a clock half an hour later. The second kind of
coupling is a guess about duration dressed up as a schedule. It was already
wrong once — the two halves sat seven hours apart because one unit reads its
hour in UTC and the other read it locally — and even correct it only holds while
the snapshot and replication keep finishing inside thirty minutes.

The intended shape is one nightly anchor that triggers dump, then snapshot, then
verification, each on the previous one's completion, so the cycle stretches with
however long the work actually takes instead of racing a fixed gap.

The obstacle to design around is the snapshot tool's own unit. It is woken
hourly and decides from pool state whether a nightly is due, so "the snapshot
finished" and "a nightly was taken" are not the same event, and the twenty-three
runs a day that take nothing must not trigger a verification.

## Alert on the verification relative to the snapshot, not on a flat window

Operator decision, 2026-08-29. Follow-up work.

`BackupVerifyStale` fires on a flat twenty-six hour window, which cannot
distinguish "the verification is late" from "the snapshot it verifies is late" —
and it is silent for a full day either way. The better signal is relative: alert
when a snapshot exists and no verification has followed it within some hours.
That reports the real failure, a snapshot nothing has checked, and reports it in
hours rather than a day.

The fast arm already exists and is live: every unit in the slice raises mail
through `backup-failure-mail@` on failure, so an outright failure is reported
immediately. This is about the slow arm, which is the one that catches a job
that stopped running rather than one that ran and failed.

## An orphaned `backup` user and group, and the directory they left

Found during plan 14-06 when firebat was deployed.

Activation removed a `backup` user and group dating from July 2025, left behind
by the retired snapshot machinery. Their `/var/lib/backup` directory is still on
disk and is now owned by a numeric id with no account behind it. Worth looking
at before removing it, in case anything was written there that nobody has missed
yet.

Recorded alongside it: that activation exited 4 on a transient `dbus-broker`
reload failure while nonetheless applying the switch in full. An activation that
reports failure after succeeding is the same class of problem as the reboot
target below — it teaches the operator to discount an exit status.

## Every host auto-upgrades nightly from an unclaimed GitHub namespace

Found during plan 14-06, task 2, while establishing what margin the nightly
verification actually has before the upgrade window.

`modules/common/nix.nix:45-54` enables `system.autoUpgrade` on every host with
`flake = "github:your-username/nixos-config"` — the upstream template's
placeholder, never replaced. All four machines therefore run a root rebuild at
04:00 local against a repository name that does not exist, and every one of
those runs has been failing:

    error: unable to download
    'https://api.github.com/repos/your-username/nixos-config/commits/HEAD':
    HTTP error 404

Two separate problems sit on top of each other.

The benign one: automatic updates have never worked on any host, so the 04:00
window the backup schedule was designed around is currently a no-op. Any
reasoning about margin against it is reasoning about something that does not
run.

The one that matters: `your-username` is an unregistered GitHub account name,
and the flake reference is unpinned. Anyone who registers that account and
creates a repository called `nixos-config` would have all four machines fetch
and activate their configuration as root the following night, without
interaction. `allowReboot = false` limits the blast radius to activation rather
than boot, which is not much of a limit.

**Resolved 2026-08-29: the block was removed entirely**, per the repository's
convention of replacing rather than deprecating. Nothing on any host now
auto-upgrades, which is a change in name only — it never worked.

What remains deferred is the deliberate version: an auto-upgrade pointed at the
real repository, pinned to a reference someone chose, with a decision about
whether activation without a human is wanted on a host that runs the household's
services. That is a design question, not a typo fix, which is why the broken one
was deleted rather than corrected in place.

## Remove pi4 from the alerting targets while it is decommissioned

Operator decision 2026-08-29: pi4 being down is **expected**. It is
decommissioned until it is re-provisioned, not broken.

Both Pis were unreachable during this plan, on their LAN addresses and over
Tailscale:

    pi4  192.168.68.56   Host is down
    pi5  192.168.0.110   Operation timed out

The monitoring host has been reporting `HostDown` for all four of pi4's
exporters since **2026-08-17**. Now that alerts actually reach a person, four
permanently firing alerts about a host nobody intends to fix is the fastest way
to teach everyone to ignore the mail — which would undo the point of adding
delivery at all.

So: drop pi4 from firebat's scrape targets in `modules/gateway/prometheus.nix`
(it appears in several jobs, including a dedicated one on `pi4.local:9618`), and
narrow Grafana's host-down rule to match, until the host returns. Put them back
as part of re-provisioning rather than leaving the alerting permanently blind to
that address.

Left undone here because deciding what the monitoring should watch is a separate
change from the backup engine, and doing it inside this phase would bury it.

## The auto-upgrade removal has not reached either Pi

The `system.autoUpgrade` block was removed from `modules/common/nix.nix`, which
covers every host, and deployed to ser8 and firebat. Neither Pi could be reached,
so both are still running a configuration that carries it.

Harmless in the meantime: it fails with a 404 rather than doing anything, and
both hosts are off. Deploy when they come back:

    make switch-pi4
    make switch-pi5

## Two preserved state directories from the restore drills

Kept deliberately, operator decision 2026-08-29:

    /var/lib/donetick.pre-restore-20260829T102300
    /var/lib/actual.pre-restore-20260829T102327

Each holds the service's state as it was immediately before its drill, which is
the only copy of whatever those two services wrote between the 03:00 UTC snapshot
and the drills a few hours later. Nothing else has that window: the snapshot
predates it and the next one postdates the restore.

Remove them once that window stops mattering — a day or two of normal use is
enough, since anything worth keeping will have been written again. They sit on
the root filesystem rather than in the persisted tree, so they are not
snapshotted and not replicated, and a reboot's rollback would take them anyway.

## Replication fails with permission denied after a crash mid-policy-run

Observed 2026-08-29 in the virtual machine suite, not on the host.

Running a replication immediately after the guest is crashed during a snapshot
run produces:

    cannot hold: permission denied
    cannot send 'rpool/safe/persist': permission denied
    CRITICAL ERROR: zfs send -I ... failed: 256

The replication account is granted its permissions by a step that runs before
each send and revoked by one that runs after, so the reading is that a crash
leaves the grant absent while the revoke has already happened, or that the grant
step did not take effect on the run after an unclean boot. The visible
consequence is that the replica silently stops advancing, and the next
verification fails on replica freshness rather than on anything it checked —
which points at the wrong thing.

Not chased here because it was found at the end of a long crash sequence in a
guest and has not been reproduced on the host, whose hourly replications have
run cleanly throughout. Worth reproducing deliberately: crash during a snapshot
run, boot, then replicate, and read what `zfs allow` holds at each step.

## `make reboot-ser8` reports failure on a successful reboot

Carried forward from plan 14-05.

The target gives up waiting at roughly fifty seconds; ser8 comes back at about
two minutes. Every successful reboot through this target therefore reports as a
failure, which trains the operator to ignore its exit status. The fix is a
longer wait with a clearer progress message, in the reboot target rather than in
any host configuration.

