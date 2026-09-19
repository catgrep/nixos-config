---
created: 2026-09-19T08:45:00.000Z
title: Restructure the flake around dendritic flake-parts feature modules
area: common
severity: major
files:
  - flake.nix
  - modules/gateway/prometheus.nix
  - hosts/ser8/backup/services.nix
  - modules/gateway/Caddyfile
  - .planning/service-monitoring-proposal.md
---

## Problem

Cross-cutting service aspects live far from the services they describe, and each one is a hand-maintained pairing that drifts independently:

- **Alert rules**: rules for ser8 services sit in firebat's gateway module (`modules/gateway/prometheus.nix`, plus a Grafana mirror).
- **Backup registration**: coverage is a central list in `hosts/ser8/backup/services.nix`, guarded by a build-time drift assertion.
- **Reverse-proxy routes**: every service's route lives in `modules/gateway/Caddyfile` on firebat.
- **Secret-restart wiring**: sops-nix `restartUnits` restates by hand who consumes each secret; a 2026-09-19 audit found 20 stale-consumer gaps (fixed in 46fd7d4) after the same defect had already bitten frigate.env, alertmanager.env, sabnzbd.ini, and nzbget.conf separately. The consumer wiring (`EnvironmentFile=`, `LoadCredential=`, `.path` references) already encodes the relationship; `restartUnits` duplicates it, so the gap keeps reappearing.
- **Monitoring expectations**: `.planning/service-monitoring-proposal.md` designs per-service `homelab.monitoring.systemd.units` declarations merged into host policy - per-service wiring that today has no per-service home.
- **Dashboards and version pins**: per-service Grafana JSON is provisioned centrally from `dashboards/`, and per-service version pins live in `multiverse.lock` consumed via `config.multiverse.locked.<attr>`.

This todo supersedes SEED-001 (planted 2026-08-29, dormant). Its trigger condition - "a third cross-host aspect needs per-service wiring" - has now fired several times over, so the seed graduates to actionable work.

## Solution

Adopt the dendritic pattern (flake-parts, per [Doc-Steve's basics guide](https://github.com/Doc-Steve/dendritic-design-with-flake-parts/wiki/Basics)): invert the hierarchy from host -> services to features -> hosts.
Every file becomes a flake-parts module organized by feature; each feature declares `flake.modules.<class>.<aspect>` blocks for every context it touches.
One `frigate` feature would carry the ser8 service config, its firebat alert rules and Caddy route, its backup registration, its monitoring expectations, and its secret-restart wiring in a single evaluation - context-dependent settings co-located, shared across hosts without duplication.

### Folded: sops restartUnits (from 2026-09-19-implicit-sops-restartunits todo)

Interim, restructure-independent: an eval-time drift assertion that walks `config.systemd.services`, finds units whose serviceConfig strings reference a `config.sops.secrets.*.path` or template path, and fails the build when that unit is missing from the secret's `restartUnits` (same shape as the backup coverage assertion; needs an opt-out for runtime-read consumers like msmtp `passwordeval` and tailscaled-autoconnect).
Target state under dendritic: the secret, its consumer, and the restart wiring live in one feature module, and a shared aspect derives or enforces the pairing once for all hosts.
The memory note `sops-secrets-need-restartunits` covers agent behavior until either lands.

### Design annex: composable service monitoring

`.planning/service-monitoring-proposal.md` (kept in place) is the flagship aspect and is already dendritic in shape: each service declares monitoring expectations beside its own configuration, Nix merges them into host policy exported via node-exporter textfiles, and firebat consumes only the metric contract (host + unit name labels).
Its central constraint must survive the restructure: **firebat never evaluates other hosts' Nix configuration** - expectations stay host-local and cross the host boundary as metrics, not as Nix imports.
Dendritic changes where the declaration lives (feature module instead of per-host service file), not how it flows.

### Multiverse integration

`multiverse.lock` + `config.multiverse.locked.<attr>` (wired in `modules/common/multiverse.nix`) already proves the central-registry/per-service-consumption pattern this restructure generalizes.
A feature's version pin becomes one more context block the feature declares (which mvs attr it consumes), while `multiverse.lock` stays the single lock file edited only through `mvs lock`.
Evaluate whether the feature module can also carry pin metadata (e.g. which attr, upgrade cadence notes) so `mvs lock update` targets are discoverable from the feature.

### Sequencing

1. Evaluate the cheap middle step first (from SEED-001): extend the existing flake service metadata exports (`enabledServices`, `servicePackages`) to carry per-service alert/route/backup metadata without a full restructure. If it covers the aspects above cleanly, the full pattern may not earn its cost.
2. Prototype one feature end-to-end (frigate is the best candidate: service + exporter + alert rule + route + secrets + backup) before committing to whole-repo reorganization.
3. Whole-repo migration is milestone-scale, not a phase task - route through /gsd-new-milestone when picked up.

### Preserved guarantees

- The backup coverage drift assertion in `hosts/ser8/backup/services.nix` must survive in per-feature form: a forgotten registration stays a build failure, not a silent coverage hole.
- Host-local monitoring expectations (above).
- `deploy.yaml` remains the deployment source of truth; smoketest entry points keep their `all.sh` contract.

## Evidence and related work (kept standalone)

These ship near-term value under the current layout and double as motivating instances:

- `2026-09-18-frigate-camera-down-alerting-and-status-panel.md` - per-service alert authored in the central gateway module.
- `2026-08-30-fill-alert-rule-catalog-gaps.md` - systemd-exporter/process-exporter rule gaps; overlaps the monitoring proposal's failed-state and crash-loop coverage.
- `2026-08-30-grafana-dashboard-ui-edit-drift.md` - central dashboard provisioning contract.
- Completed: `2026-08-29-consolidate-alerting-onto-standalone-alertmanager.md`, `2026-08-29-derive-backup-vm-test-coverage-from-services-nix.md`.

## References

- https://github.com/Doc-Steve/dendritic-design-with-flake-parts/wiki/Basics
- https://github.com/hyperparabolic/nix-config - multi-host dendritic implementation (every modules/ file a flake-parts module, recursively imported) that also runs impermanence with ephemeral roots and encrypted secrets, so it is the closest structural analog to this repo.
- Reference implementations: github.com/mightyiam/dendritic, drupol's infra, vic's dendrix.
