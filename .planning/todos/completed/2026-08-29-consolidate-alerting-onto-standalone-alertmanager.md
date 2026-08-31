---
created: 2026-08-30T06:18:51.869Z
completed: 2026-08-30
title: Consolidate alerting onto the standalone Alertmanager
area: gateway
severity: minor
files:
  - modules/gateway/grafana.nix:183-196
  - modules/gateway/alertmanager.nix
  - modules/gateway/prometheus.nix:260-380
---

## Problem

Alert rules are evaluated twice on firebat: once by Prometheus (delivered through the standalone Alertmanager added in phase 14) and once as Grafana-managed mirrored rules (~400 lines in grafana.nix duplicating the same PromQL, delivered through Grafana's built-in alertmanager).
The mirror predates the standalone Alertmanager, when Prometheus rules could not notify anyone.
Now both paths reach the same recipient through the same Gmail SMTP credential, so the redundancy is homelab-internal only while the maintenance cost (every rule edited twice) is permanent.
grafana.nix's own comment says the mirrored rules should be removed together with any consolidation decision rather than left looking like an independent path.

## Solution

Make Prometheus→Alertmanager the single rule-evaluation path: delete the Grafana-managed mirrored rules, contact points, and notification policies from grafana.nix (use Grafana's deleteRules provisioning so file-provisioned rules are actually removed), or alternatively point Grafana at the external Alertmanager as a datasource.
Keep the ser8-local mail paths untouched: backup-failure-mail@ (loud unit failures, seconds latency, journal excerpt in body) and ZED (ZFS event detail) cover cases the firebat Alertmanager structurally cannot, such as ser8 failing while firebat or the network is down.
Update scripts/smoketests/gateway/test-alertmanager.sh if routing expectations change, and export the dashboard/rule JSON diff per repo PR guidance.
User assessment (2026-08-29): wants this next, considered easy.

## Outcome (2026-08-30)

Landed in `gateway: consolidate alerting onto standalone Alertmanager` and deployed (switch) to firebat.
Grafana carries zero alert rules (explicit deleteRules/deleteContactPoints/resetPolicies provisioning); Prometheus->Alertmanager is the single path.
The Grafana-only probe rules were ported to prometheus.nix (ServiceDown, HostUnreachable, TLSCertExpiringSoon, plus a new TLSProbeFailed guard).
Extras surfaced by the alert-history review, all fixed in the same pass:
ZFSPoolUnhealthy watched a nonexistent metric (now node_zfs_zpool_state); the tls_connect probe demanded HTTP 2xx (now a TCP+TLS handshake); NZBGet's 401 now probes through an auth-aware module; pi4 targets commented out while the host is disconnected; HostDown raised to 10m; SABnzbd host_whitelist/local_ranges fixed on ser8.
Smoketest test-alertmanager.sh now asserts Grafana evaluates zero rules.
