---
created: 2026-09-19T08:25:00.000Z
title: Make secret-change restarts implicit instead of hand-listed restartUnits
area: common
severity: minor
files:
  - modules/automation/frigate.nix
  - modules/gateway/grafana.nix
  - hosts/ser8/media/sonarr.nix
  - .planning/seeds/SEED-001-dendritic-flake-parts-restructure.md
---

## Problem

sops-nix only restarts units named in a secret's or template's `restartUnits` when its content changes; consumers that read secrets at startup otherwise keep running on stale values.
A repo-wide audit (2026-09-19, fixed in commit 46fd7d4) found 20 such gaps across 42 secrets/templates, after the same defect had already bitten frigate.env, alertmanager.env, sabnzbd.ini, and nzbget.conf on separate occasions.

The root cause is duplication: the consumer wiring already encodes who reads each secret (`EnvironmentFile=`, `LoadCredential=`, `.path` references in ExecStart wrappers and generated configs), and `restartUnits` restates that relationship by hand in a different attrset.
Hand-maintained pairs drift every time a secret or consumer is added, so the gap keeps reappearing no matter how many audits run.

## Solution

TBD. Candidate shapes, roughly in order of increasing ambition:

- **Drift assertion (cheapest, matches repo philosophy):** an eval-time check that walks `config.systemd.services`, finds units whose `serviceConfig` strings reference a `config.sops.secrets.*.path` or template path, and fails the build when that unit is missing from the secret's `restartUnits`.
  Same shape as the backup coverage assertion in `hosts/ser8/backup/services.nix` — a forgotten registration becomes a build failure, not a silent staleness hole.
  Needs an opt-out marker for genuine runtime-read consumers (msmtp `passwordeval`, tailscaled-autoconnect).
- **Implicit derivation:** the same scan, but auto-populating `restartUnits` instead of asserting.
  Less boilerplate, more magic; spurious restarts for runtime-read consumers become the failure mode, so the opt-out is mandatory rather than advisory.
- **Co-location via SEED-001:** in the dendritic/flake-parts restructure, a service's secret, its consuming unit, and the restart wiring live in one feature module, and a shared aspect can derive or enforce the pairing once for all hosts.
  Secret-change restart wiring is exactly the kind of cross-cutting per-service aspect SEED-001 exists for — count it toward that seed's "third cross-host aspect" trigger.

Evaluate the drift assertion first: it is host-agnostic, needs no restructure, and turns the recurring failure mode into a build error immediately.
The memory note `sops-secrets-need-restartunits` covers agent behavior until either lands.
