---
id: SEED-001
status: dormant
planted: 2026-08-29
planted_during: v1.3 phase 14 (backup-engine)
trigger_when: next structural milestone after v1.3, or when a third cross-host aspect (alerting, backup registration, DNS, reverse-proxy routes) needs per-service wiring
scope: large
---

# SEED-001: Evaluate the dendritic pattern (flake-parts) for feature-organized modules

## Why This Matters

Cross-cutting service aspects currently live far from the service they describe: alert rules for ser8 services sit in firebat's gateway module (modules/gateway/prometheus.nix, plus a Grafana mirror), backup coverage is a central list (hosts/ser8/backup/services.nix), and Caddy routes live in modules/gateway/Caddyfile.
The user's instinct (2026-08-29): services should be defined in their own directories, with .nix files as options/features/toggles, so alerting rules and backup/restore registration sit beside the service.
The dendritic pattern (mightyiam, built on flake-parts) is the named version of this: every file is a flake-parts module, organized by feature; one jellyfin module can contribute the ser8 service, its backup registration, and its firebat alert rule and route in a single evaluation.

## When to Surface

**Trigger:** next structural milestone after v1.3, or when a third cross-host aspect needs per-service wiring.
Surface during /gsd-new-milestone scans.

## Scope Estimate

**Large** — whole-repo reorganization: hosts/ plus role-grouped modules/ become feature-organized flake-parts modules across all four hosts.
Matches the stated preference for long-term maintainability over development cost, but is milestone-scale, not a phase task.

## Breadcrumbs

- hosts/ser8/backup/services.nix — central covered-services list; its comments argue for rule-based membership with a build-time drift assertion. Any per-service registration design must keep that assertion so a forgotten registration stays a build failure, not a silent coverage hole.
- modules/gateway/prometheus.nix / modules/gateway/grafana.nix — alert rules living away from the services they watch (Grafana mirror has its own consolidation todo, 2026-08-29).
- flake.nix service metadata exports (enabledServices, servicePackages) — existing cross-host read-across that could carry per-service alert metadata without a full restructure; a cheap middle step to evaluate first.
- Reference implementations: github.com/mightyiam/dendritic, drupol's infra, vic's dendrix.

## Notes

Within a single host, plain NixOS module options achieve co-location without flake-parts; dendritic earns its cost only for the cross-host wiring (ser8 service -> firebat rules/routes).
Evaluate the middle step (extend flake service metadata) before committing to the full pattern.
