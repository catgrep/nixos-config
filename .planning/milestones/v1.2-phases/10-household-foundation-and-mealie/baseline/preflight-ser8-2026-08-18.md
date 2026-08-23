# Plan 10-04 Task 1 — ser8 pre-activation evidence

Captured 2026-08-18 from the development workstation, before any activation command was run.
Nothing on ser8 was changed by any command in this record: every probe is read-only.

## Reachability

`make status` reports **all four hosts offline** and this is an environmental artefact, not a ser8 finding.
The target pings `$(host).internal`, and that name resolves for none of the four hosts from this workstation (`ping: unknown host` for ser8, firebat, pi4, and pi5 alike).
Reachability was therefore proven against the address `deploy.yaml` actually records:

```
$ ssh -o BatchMode=yes bdhill@192.168.68.65 'echo SSH_OK; hostname; uname -sr'
SSH_OK
ser8
Linux 6.18.44
```

`deploy.yaml` entry under test: `targetHost: 192.168.68.65`, `targetUser: bdhill`.
RESEARCH.md Assumption A7 holds for ser8 (firebat is not contacted by this plan's tasks).

## FOUND-04 premise: PostgreSQL has never held data on this host

```
$ ls -la /persist/var/lib/postgresql
total 10
drwxr-xr-x  2 root root  2 Jul 13  2025 .
drwxr-xr-x 22 root root 22 Jul 26 10:57 ..

$ ls -1 /persist/var/lib/postgresql | grep -cE '^[0-9]+$'
0

$ ls -la /var/lib/postgresql
total 10
drwxr-xr-x  2 root root  2 Jul 13  2025 .
drwxr-xr-x 28 root root 30 Aug 18 10:00 ..
```

The persisted directory exists, is owned `root:root` at mode 755, was created 2025-07-13, and is **empty**: a link count of 2 and no entries.
The count of numeric major-version subdirectories is **0**, so no major — 16, 17, or otherwise — is present.
The premise "before any service data exists" is proven rather than assumed, and RESEARCH.md Open Question 5 is closed.
No delete, move, or initialise-over was performed or needed.

`/persist/var/lib` also carries **no `mealie` entry**, and neither `/var/lib/mealie` nor `/persist/var/lib/mealie` exists.
Mealie has never run on this host either.

## Neither unit exists yet

```
$ systemctl list-unit-files mealie.service postgresql.service
UNIT FILE STATE PRESET

0 unit files listed.
(exit 1)

$ systemctl is-active mealie.service postgresql.service
inactive
inactive

$ getent passwd mealie postgres
(no output, exit 2)
```

Neither unit file exists, and neither the `mealie` nor the `postgres` system user has been materialised.
A post-activation "the unit is active" observation therefore cannot be reading a leftover.

## Recovery path: generation numbers and bootloader entries

```
$ readlink /nix/var/nix/profiles/system
system-268-link

$ readlink -f /run/current-system
/nix/store/wxpn95cb5bhr66x81ny24jvs738jhnzl-nixos-system-ser8-26.05.20260817.0dd31db

$ nix-env --list-generations --profile /nix/var/nix/profiles/system | tail -6
 263   2026-07-25 17:04:13
 264   2026-07-26 10:57:50
 265   2026-07-29 18:39:48
 266   2026-08-12 23:54:35
 267   2026-08-13 00:27:51
 268   2026-08-17 11:30:50   (current)
```

**Pre-activation generation: 268** (NixOS 26.05.20260817.0dd31db, Linux 6.18.44, built 2026-08-17).

`bootctl list` confirms the entry is present on the ESP and is both the default and the selected entry:

| Entry | Title | Status |
|---|---|---|
| `nixos-generation-268.conf` | Generation 268 NixOS Yarara 26.05.20260817.0dd31db (Linux 6.18.44) | default, selected |
| `nixos-generation-267.conf` | Generation 267 NixOS Xantusia 25.11.20260518.687f05a (Linux 6.12.90) | selectable |
| `nixos-generation-266.conf` | Generation 266 NixOS Xantusia 25.11.20260518.687f05a (Linux 6.12.90) | selectable |
| `nixos-generation-265.conf` | Generation 265 NixOS Xantusia 25.11.20260518.687f05a (Linux 6.12.90) | selectable |

**The named recovery path for a bad activation is: select `nixos-generation-268.conf` in the systemd-boot menu.**
`make rollback-HOST` prints `TODO` and is not a recovery path.
Recovery restores the system closure only; it does not un-initialise a PostgreSQL data directory or un-run an Alembic migration.

### Supporting observation (not owned by this plan)

`(selected)` on generation 268 plus `up 16:27` means **ser8 has booted generation 268**, so the 26.05 closure and its stage-1 systemd initrd are proven bootable rather than merely activated.
`/IMPERMANENCE-MARKER-09-05` is **absent** (`No such file or directory`), which is the outcome the Phase 09 09-05 blocker required: the marker did not survive the first 26.05 boot, so the impermanence rollback migrated in 09-01 fired.
Recorded here because it is what makes the generation-268 recovery path credible.
Phase 09 verification owns the finding; this plan only observed it read-only.

## Pre-activation smoketest baseline

Transcript: `.planning/phases/10-household-foundation-and-mealie/baseline/smoketests-ser8-pre-activation.txt` (301 lines, top-level `EXIT=1`).
The top-level exit status is **not** usable as a gate — it is 1 for two reasons this plan does not own, plus the household area that this plan exists to turn green.
Per-area results:

| Area | Result | Notes |
|---|---|---|
| `media/all.sh` | **pass** | "All media services smoketests passed" |
| `household/all.sh` | **fail 0/2** | Expected. Mealie is not deployed: service test 1/12, endpoint test 2/7 |
| `nordvpn/all.sh` | **fail 3/4** | Pre-existing. Only `test-forwarding.sh` fails, on the retired pi4 resolver 192.168.68.56. The confinement suite passes 3/3 |
| `ser8/test-zfs-health.sh` | **pass** | all 7 |
| `ser8/test-vaapi.sh` | **pass** | all 5 |
| `ser8/test-frigate.sh` | **pass** | all 5 |
| `ser8/test-home-assistant.sh` | **pass** | all 3 |
| **top level** | **fail 5/7** | failing areas: household, nordvpn |

The post-activation comparison is per-area equality on media, nordvpn, zfs-health, vaapi, frigate, and home-assistant, plus a newly green household area.

No credential material appears in the transcript (`grep -inE 'password|api[_-]?key|token|secret|BEGIN .*PRIVATE'` returns nothing).

## Task 1 verdict

Premise holds. No blocking finding. Nothing was changed on ser8.
