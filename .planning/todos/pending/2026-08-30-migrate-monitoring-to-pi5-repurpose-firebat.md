---
created: 2026-08-31T01:15:00.000Z
title: Migrate the monitoring stack to pi5 and repurpose firebat
area: infra
severity: major
files:
  - modules/gateway/
  - hosts/firebat/
  - hosts/pi5/
---

## Problem

firebat carries the whole gateway role (Caddy, Prometheus, Grafana, Alertmanager, blackbox) but that hardware could serve better as a general development host, while pi5 sits idle and could carry monitoring.

## Solution

Explore moving Prometheus, Grafana, Alertmanager, and the blackbox exporter to pi5 (all run fine on aarch64; dashboards and rules are already declarative so the move is mostly host wiring plus TSDB storage planning - 30d/10GB retention wants reliable storage, not a bare SD card).
Decide whether Caddy/Tailscale vhosts move too or stay on firebat.
Then define firebat's new role set: development host, code hosting (e.g. a Gerrit instance), nix build cache/remote builder, backup client (a second replica target for the ser8 backup engine would give off-host redundancy).
Keep the off-host property of alerting in mind: monitoring should not live on a host it primarily monitors.
