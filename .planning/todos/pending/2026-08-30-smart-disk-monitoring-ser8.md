---
created: 2026-08-31T01:45:00.000Z
title: Add SMART disk monitoring on ser8
area: monitoring
severity: minor
files:
  - modules/servers/monitoring.nix
  - modules/gateway/prometheus.nix
  - dashboards/
---

## Problem

Originates from the v1.1 milestone research (FEATURES.md differentiators, SUMMARY.md "defer v2+" in .planning/milestones/v1.1-research/), folded into shelved Phase 5 (HW-01..05) and never implemented - no smartctl_exporter or smartd exists in modules/ or hosts/.
The case is stronger now than at research time: ser8 carries a two-disk 12TB spinning mirror (media), a RAID-Z2 backup pool, and NVMe system storage, and the v1.3 mirror migration (ZFS-01) ran manual SMART self-tests as a one-time gate with no continuous follow-up.
ZFS health rules catch corruption after the fact; SMART attributes (reallocated sectors, pending sectors, temperature) are the pre-failure signal for the spinning disks.

## Solution

Enable services.prometheus.exporters.smartctl on ser8, minding the nixpkgs quirks the research flagged (device permissions, NVMe autodiscovery); scrape it from prometheus.nix like the other ser8 exporters.
Add alert rules on smart status degraded, reallocated or pending sector growth, and disk temperature out of range, delivered through the standalone Alertmanager.
Provision a SMART dashboard in dashboards/ (Grafana dashboard 20204 is the research's candidate; follow the README download-and-substitute procedure and record it in the source table).
