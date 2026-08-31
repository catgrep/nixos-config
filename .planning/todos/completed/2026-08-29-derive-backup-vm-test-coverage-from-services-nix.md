---
created: 2026-08-30T06:18:51.869Z
completed: 2026-08-30
title: Derive backup VM test coverage from services.nix
area: testing
severity: major
files:
  - tests/backup-behavior.nix:120-150
  - hosts/ser8/backup/services.nix
  - .planning/phases/14-backup-engine/14-UAT.md
---

## Problem

BKP-06 requires "a VM test suite exercises the restore path across every covered service," but tests/backup-behavior.nix stands up only 2 of the 16 covered services.
The suite is already generalized: the guest imports the real backup modules, services are stand-in units (sleep infinity), and every per-service assertion iterates the SERVICES list.
The gap is that the guest's stand-in units and the SERVICES list are hand-written instead of derived from hosts/ser8/backup/services.nix, so coverage can silently drift from the covered set.
The irregular unit names (hass -> home-assistant.service, tailscale -> tailscaled.service) are the drift-prone cases and are currently untested.
UAT decision recorded 2026-08-29 (14-UAT.md item 1): extend, do not accept as met by substance. BKP-06 stays open until this lands.

## Solution

Import hosts/ser8/backup/services.nix in tests/backup-behavior.nix, generate a stand-in unit per entry (using each entry's real unit name), and derive the test script's SERVICES list from the same attrset.
Coverage then tracks the covered set automatically; adding a service to services.nix extends the VM test without edits.
Expect VM test runtime to grow (16 datasets, seeds, and restore drills instead of 2) — minutes, not hours; flake.nix already documents the make-check cost trade.
Mark BKP-06 complete in REQUIREMENTS.md and close 14-UAT.md item 1 when it lands.

## Outcome (2026-08-30)

Landed: tests/backup-behavior.nix imports hosts/ser8/backup/services.nix, generates a stand-in unit per entry under the entry's real unit name (postgresql runs as a real server for the dump and archive paths), and derives the script's service mapping from the same attrset.
All sixteen covered services round-trip through backup-restore by default resolution, the irregular unit names (hass -> home-assistant.service, tailscale -> tailscaled.service) included.
The suite additionally covers the chained nightly pipeline: the single timer, the wants+after completion barriers, the verify gate running once per new replica snapshot and skipping without failure after, and the post-crash catch-up pass.
Landing it caught a real chain bug: sanoid and syncoid ship as Type=simple, making after= a launch order rather than a completion barrier; both are forced oneshot in policy.nix and the suite pins the requirement.
Guest script runs ≈11 minutes. BKP-06 marked complete in REQUIREMENTS.md; 14-UAT.md item 1 closed.
