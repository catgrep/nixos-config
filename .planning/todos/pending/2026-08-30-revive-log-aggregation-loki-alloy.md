---
created: 2026-08-31T01:45:00.000Z
title: Revive shelved log aggregation with Loki and Alloy
area: monitoring
severity: minor
files:
  - modules/gateway/
  - modules/servers/monitoring.nix
  - hosts/ser8/impermanence.nix
  - hosts/firebat/impermanence.nix
---

## Problem

Originates from the v1.1 milestone research (SUMMARY.md, ARCHITECTURE.md, PITFALLS.md in .planning/milestones/v1.1-research/); the corresponding Phase 6 was shelved to Future Requirements LOG-01..05 (ROADMAP.md) and nothing was ever built - no loki, promtail, or alloy reference exists anywhere in modules/ or hosts/.
Logs remain per-host in journald (SystemMaxUse=1G in modules/servers/monitoring.nix), so there is no cross-host search ("what happened on ser8 at 3am") and no log-based alerting for patterns metrics miss (OOM kills, crash loops, ZFS errors in dmesg).
The research's "start with Promtail, migrate later" advice is now obsolete: Promtail passed EOL in March 2026, so any implementation must use Grafana Alloy directly.

## Solution

Loki on the monitoring host with the v1.1 research pitfall mitigations baked in from day one: schema v13 + TSDB index + filesystem object store (Loki 3.x refuses to start otherwise), compactor with retention_enabled = true (retention_period alone is silently ignored), auth_enabled = false, monolithic mode, and an alert on loki_ingester_wal_disk_full_failures_total (WAL-full drops are silent).
Alloy on all hosts reading the systemd journal (systemd-journal group membership or the collector ships zero logs with no error), pushing to Loki on port 3100 (open that port on the monitoring host), with a host label from config.networking.hostName and max_age capped so a reboot does not replay the whole persisted journal.
Persist the collector positions and /var/lib/loki through impermanence - both ser8 and firebat roll back root (hosts/*/impermanence.nix), which the research only suspected for firebat.
Provision the Loki datasource in grafana.nix next to Prometheus; route log-based alert rules through Loki's ruler to the standalone Alertmanager, not Grafana alerting, honoring the 2026-08-30 consolidation (Grafana carries zero alert rules by design).
Coordinate with the pending monitoring-to-pi5 migration todo: decide the Loki host as part of that move rather than building on firebat and relocating - the TSDB/chunk storage wants reliable disk either way.
