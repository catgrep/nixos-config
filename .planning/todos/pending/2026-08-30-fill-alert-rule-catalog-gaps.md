---
created: 2026-08-31T01:45:00.000Z
title: Fill alert rule gaps from the v1.1 research catalog
area: gateway
severity: minor
files:
  - modules/gateway/prometheus.nix
---

## Problem

Originates from the v1.1 milestone research alert-rule catalog (FEATURES.md in .planning/milestones/v1.1-research/), partially absorbed by shelved Phase 5 (HW-01..05).
prometheus.nix today covers host-down, disk (graduated), memory (single 10% threshold), ZFS pool health, CPU temperature (single 80C), camera storage, sustained CPU, blackbox probe rules, Alertmanager self-monitoring, and backup staleness - but several catalog rules with real failure modes behind them are still missing.
The largest gap: systemd-exporter and process-exporter are scraped from every host (prometheus.nix:96) yet no rule consumes their metrics, so a non-HTTP service entering failed state or crash-looping is invisible unless a blackbox probe happens to cover it.
Also missing: OOM-kill detection, ZFS scrub errors, ZFS pool capacity thresholds (performance degrades past 80%), graduated memory (warn 15% / crit 5%) and temperature (warn 75C / crit 85C) severity, disk read latency (failing-disk early signal), a /mnt/media mount-specific rule, and Prometheus rule-evaluation-failure self-monitoring.

## Solution

Add the missing rules to prometheus.nix, but verify every metric name against the live Prometheus before writing the expression - the ZFSPoolUnhealthy incident (rule watched a nonexistent metric and silently never fired) is exactly the failure mode the research warned about, and the catalog's suggested names (zfs_scrub_errors_total, systemd_unit_state, node_vmstat_oom_kill) may not match what the deployed exporters emit.
Candidate set: unit failed state and restart-count crash-loop rules from systemd-exporter; OOM kills from node-exporter vmstat; ZFS scrub errors and pool capacity warn/crit; graduated memory and temperature pairs replacing the single-threshold rules; disk read latency; /mnt/media availability; increase(prometheus_rule_evaluation_failures_total).
Tune for: durations per the catalog (longer for warnings, shorter for criticals) and keep pi4-absent metrics scoped so rules do not fire on empty vectors.
Update scripts/smoketests/gateway/ if rule-count assertions exist, and route everything through the standalone Alertmanager path per the 2026-08-30 consolidation.
