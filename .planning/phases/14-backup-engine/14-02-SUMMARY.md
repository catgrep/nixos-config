---
phase: 14-backup-engine
plan: 02
subsystem: storage
tags: [zfs, disko, impermanence, vm-tests, snapshots]
status: complete

requires:
  - hosts/ser8/backup slice (from 14-01)
  - checks.x86_64-linux.backup-behavior (from 14-01)
provides:
  - sixteen rpool/safe/persist child dataset declarations, one per unit-backed service
  - checks.x86_64-linux.backup-layout
  - impermanence entries retired for every covered service
affects:
  - hosts/ser8/disko-config.nix
  - hosts/ser8/impermanence.nix
  - hosts/ser8/media/jellyfin.nix
  - flake.nix

tech-stack:
  added: []
  patterns:
    - membership by mechanical rule (has a unit, has a dataset) rather than a curated list
    - disko testLib.makeDiskoTest installing from a reduced mirror of the host's declarations
    - property assertions that check the source (local vs inherited) alongside the value

key-files:
  created:
    - tests/backup-layout.nix
    - tests/backup-layout-disko.nix
  modified:
    - hosts/ser8/backup/services.nix
    - hosts/ser8/backup/datasets.nix
    - hosts/ser8/disko-config.nix
    - hosts/ser8/impermanence.nix
    - hosts/ser8/media/jellyfin.nix
    - hosts/ser8/household/postgresql.nix
    - modules/media/sabnzbd.nix
    - tests/backup-behavior.nix
    - flake.nix
  deleted: []

decisions:
  - The ownership tmpfiles rules were retargeted from /persist/var/lib/<svc> to /var/lib/<svc> rather than deleted
  - Property assertions check the source field, not just the value, so an inherited value fails
  - x86_64-darwin removed from devShells and packages; the key threw rather than being absent

metrics:
  duration: ~4h
  completed: 2026-08-27

actuals:
  tokens: 18000
  tasks: 2
  commits: 2
---

# Phase 14 Plan 02: Full Coverage and Layout Proof Summary

Every service on ser8 that has a unit of its own now has a dataset of its own — sixteen, up from the tracer's one — and a VM test installs from those declarations and proves they build the tree, which is the question activation has never once answered here.

## Performance

| Metric | Value |
|--------|-------|
| Tasks | 2 of 2 |
| Commits | 2 |
| Files created | 2 |
| Files modified | 9 |
| VM test runs | 7 (3 deliberate mutations) |

## Accomplishments

- The covered-service set went from `donetick` alone to all sixteen unit-backed services, by a stated rule rather than a judgement call.
  Both units whose name does not follow from their directory (`hass` → `home-assistant.service`, `tailscale` → `tailscaled.service`) were read from the module that defines them and confirmed to resolve.
- Fifteen new `safe/persist/<name>` children in disko, each carrying `atime = "off"` locally, and `recordsize = "16K"` on the database child alone.
- Fifteen impermanence `directories` entries retired, so exactly one mechanism owns each `/var/lib` path.
- Mosquitto has durable storage for the first time; its state has been living on the filesystem the boot-time rollback wipes.
- Three dead entries removed alongside: the `/var/lib/docker` bind for a service that is not installed, the `/persist/var/lib/private/prowlarr` rule superseded by a forced static user, and the `/var/lib/samba` symlink that a real bind mount already wins over.
- `/var/lib/systemd/timers` added, which is unrelated to the datasets and fixes something separate: no persistent timer on this host has ever replayed a run missed while the machine was off, because the stamps systemd reads at boot were wiped before it looked.
- Jellyfin's activation tarballs are off. Five landed on one day at roughly 1.8 GB each; that churn would have dominated every snapshot delta and every replication stream.
- `checks.x86_64-linux.backup-layout` installs from a reduced mirror of ser8's disk configuration, boots the result, and asserts the full tree.

## Files Created/Modified

Created: `tests/backup-layout.nix`, `tests/backup-layout-disko.nix`.

Modified: `hosts/ser8/backup/services.nix` (fifteen new entries plus the membership rule and what it excludes), `hosts/ser8/backup/datasets.nix` (a note on why property checks cannot live beside the assertion), `hosts/ser8/disko-config.nix` (fifteen children and the two property rationales), `hosts/ser8/impermanence.nix` (four separate edits), `hosts/ser8/media/jellyfin.nix` (`backups = false`), `hosts/ser8/household/postgresql.nix` and `modules/media/sabnzbd.nix` (comments made accurate), `tests/backup-behavior.nix` (`forceImportRoot`), `flake.nix` (second check, x86_64-darwin removal).

## Decisions Made

**Property assertions check the source, not just the value.**
An `atime` of `off` inherited from a parent reads identically to one set on the child, right up until someone changes the parent — at which point the value flips with nothing to notice.
The layout test requires `local` on every child's `atime` and on the database child's `recordsize`, and requires `default` on every other child's record size.
The mutation below confirms this is not decoration.

**The record size is tuned on exactly one child.**
The record is this filesystem's copy-on-write unit and therefore its snapshot-pinning unit: at the 128K default, one row update inside an 8K database page pins 128K of snapshot space.
Every other child keeps 128K deliberately — their content is mixed, and a later change there should come from a churn measurement rather than from symmetry with the database case.

**The reduced test configuration diverges from the host in three places, each forced rather than chosen.**
One disk instead of seven; `cachefile = "none"` on the pool, without which it fails to import in the guest with an I/O error (disko's own ZFS example carries the same workaround); and no `@blank` snapshot hook, because the harness formats more than once per run and the host's unguarded hook would fail the second time.
All three are named in the file's header alongside the file it mirrors.

## Deviations from Plan

### 1. [Rule 2 - Missing critical functionality] The ownership tmpfiles rules had to be retargeted, not deleted

**Found during:** Task 1.
**Issue:** The plan reads "remove the paired `/persist/var/lib/<svc>` rules; the `/var/lib/<svc>` rules stay," and names the database directory's `0750` and Actual's `0700` as two that must remain.
Only Jellyfin actually had both halves of that pair.
For postgresql, mealie, homebox, actual, donetick, sonarr, radarr, bazarr, sabnzbd, nzbget and frigate, the `/persist/` rule was the only one there.
Deleting them as written would have removed the ownership authority the plan says must remain — including the two Actual rules whose comment explains that upstream never creates `server-files`/`user-files` and the unit fails at namespace setup without them.
**Fix:** Each rule was retargeted to `/var/lib/<svc>`, which is where the dataset now mounts and therefore where the ownership matters.
Jellyfin's `/persist` pair was deleted outright since its `/var/lib` pair already existed, and the Home Assistant rule was deleted since `modules/automation/home-assistant.nix` already owns that path.
The group on the media-stack rules is `media` rather than the service's own group, which `StateDirectory` would not reproduce, so those in particular could not simply be dropped.
**Files:** `hosts/ser8/impermanence.nix`. **Commit:** 12812a0.

### 2. [Rule 3 - Blocking] `nix flake show` could not evaluate at all

**Found during:** Task 2, checking the acceptance criteria.
**Issue:** Two of the criteria are `nix flake show --json | jq -r '.checks[...]'` invocations.
Both returned empty because `nix flake show` aborted: nixpkgs dropped x86_64-darwin after 26.05, and `nixpkgs-unstable` is past that, so `legacyPackages.x86_64-darwin` *throws* rather than being absent.
Both `devShells.x86_64-darwin` and the `sagent.packages` mapping walked into it.
Any command that enumerates every output — `nix flake show` and `nix flake check`, so `make check` too — died there.
Pre-existing and unrelated to this plan's subject, but it blocked the criteria outright.
**Fix:** Dropped the `x86_64-darwin` devShell and filtered the system out of `sagentPackages`, each with a comment saying why.
`nix flake show --json --all-systems` now exits 0 and lists exactly `backup-behavior` and `backup-layout` under exactly `x86_64-linux`.
**Files:** `flake.nix`. **Commit:** f949bbb.

### 3. [Rule 1 - Bug] Two comments became false, one was already false

**Found during:** Tasks 1 and 2.
`hosts/ser8/household/postgresql.nix` described the data directory as "impermanence-persisted ... under `/persist/var/lib/postgresql`", which this change makes wrong; it now names `/var/lib/postgresql` and its own dataset.
`modules/media/sabnzbd.nix` carried two references to planning artifacts (`evidence/sabnzbd-diagnosis.md`, `D-11`, `D-12`), which the repository rule forbids outside `.planning/` and which failed this plan's own no-planning-terminology criterion; the comment now carries the rationale itself.
Same class as plan 14-01's deviation 5.
**Commit:** 12812a0.

### 4. [Zero-warnings policy] `forceImportRoot` and `stdenv.isDarwin`

**Found during:** Task 2.
Evaluating either check warned that `boot.zfs.forceImportRoot` was using its default; ser8 sets it to `false`, so both guests now set it explicitly to match.
It changes no derivation in `backup-behavior` (that guest imports nothing at boot) and simply settles the warning.
Two uses of the deprecated `pkgs.stdenv.isDarwin` in `flake.nix` were switched to `pkgs.stdenv.hostPlatform.isDarwin`.
Two more remain in the `sagent` subflake and are deferred — see below.
**Commits:** 12812a0, f949bbb.

## Mutation Testing

The layout test passed on its first run, which on its own says nothing.
Three deliberate mutations, each reverted afterwards:

| Mutation | Result |
|----------|--------|
| Removed the `safe/persist/mosquitto` child from `tests/backup-layout-disko.nix` | Failed: `cannot open 'rpool/safe/persist/mosquitto': dataset does not exist` |
| Changed the database child's record size from `16K` to `32K` | Failed: `rpool/safe/persist/postgresql: expected recordsize=16K, got 32K` |
| Moved `atime = "off"` from the `tailscale` child up to the parent, leaving the value correct but inherited | Failed: `expected atime to be local, got inherited from rpool/safe/persist (value off is right for the wrong reason)` |

The third is the one worth having.
A value-only check passes that mutation, and would keep passing until the day someone changed the parent.

## Cost of the second check

Forced cold rebuilds, both remote on ser8: `backup-layout` 722s, `backup-behavior` 278s.
About seventeen minutes of guest tests now sit inside a cold `nix flake check`, and therefore inside `make check`.
That is the intended trade and needs no workaround, but it is a real change in what running the repository's main validation command costs.

## Requirements

`BKP-01`, `BKP-04` and `BKP-07` are listed in this plan's frontmatter and **have not been marked complete**, following plan 14-01's precedent.

All three describe a backup that runs.
BKP-01 wants a nightly snapshot replicated to the backup pool with a 30-night window; BKP-04 wants Actual's state captured by a snapshot; BKP-07 wants coverage of everything persisted on ser8.
Nothing in this plan touches ser8.
Not one of the sixteen datasets exists, no snapshot has been taken, and no replication has run.
What this plan produced is the declaration and its proof — necessary for all three, sufficient for none.
Marking them would read as "backups are running" while nothing runs.

BKP-04's path question specifically is settled in the repository: Actual's `server-files/account.sqlite` and its whole `user-files` tree sit inside the one `rpool/safe/persist/actual` dataset, so one snapshot will capture both once snapshots exist.

## Issues Encountered

The workstation still cannot build guest images locally — `/nix/store` is on a case-insensitive volume, so `make-initrd-ng` fails — and all seven VM runs went to ser8 through the remote builder.
Unchanged from 14-01 and still unaddressed.

## Known Stubs

None.

## Threat Flags

None.
T-14-06 is mitigated by removing the bind layer rather than sequencing it, and T-14-07 by the layout check, whose mutation evidence is above.
T-14-08 is deliberately left to the cutover plan: the entries are gone, the data under `/persist/var/lib/<svc>` is untouched and must be dealt with explicitly there.

## Deferred

Logged to `.planning/phases/14-backup-engine/deferred-items.md`:

- Four household smoketests assert against `/persist/var/lib/<service>` paths that the cutover makes stale. Retargeting them now would break them against the live host, which still has the old layout, so they must move in the same change that performs the cutover.
- `tools/sagent/outputs.nix` still uses the deprecated `pkgs.stdenv.isDarwin`, which warns on every evaluation of the root flake. It is a `path:` input with its own lock entry, and a lock update does not belong folded into a storage change.

## Next Phase Readiness

The declarations are complete and proven to build the tree from nothing.
Everything is still declaration only: no dataset exists on ser8, no data has moved, and the four smoketests above still describe the old layout.
The cutover plan owns all three, plus deleting the 8.4 GB of Jellyfin tarballs already on disk.

## Self-Check: PASSED

All twelve files named above exist on disk. Both commits (12812a0, f949bbb) are present in `git log`.
