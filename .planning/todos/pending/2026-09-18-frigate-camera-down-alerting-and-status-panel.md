---
created: 2026-09-19T04:10:00.000Z
title: Frigate camera-down alerting and connection-status timeline panel
area: monitoring
severity: major
files:
  - modules/gateway/prometheus.nix
  - modules/gateway/alertmanager.nix
  - dashboards/frigate.json
---

## Problem

The front_door Tapo C120 (192.168.68.64) had its RTSP server unreachable from 2026-09-13 to 2026-09-18 (~8,600 go2rtc dial-timeout errors/day) and nobody was notified; the outage was found by reading journal logs five days in.
The signal needed to detect this is already collected: prometheus scrapes frigate-exporter (ser8.local:9710), which exposes `frigate_camera_fps` per camera, and it read 0 for front_door for the entire outage.
There is no alert rule on it and no dashboard visualization of per-camera connection state over time, so neither push nor glance surfaces a dead camera.
Alerts must not hammer during a long outage: a camera that stays down for days should produce periodic summary reminders, not a continuous stream.

## Solution

Add a `FrigateCameraDown` rule to the homelab rules in prometheus.nix: `frigate_camera_fps{camera_name=~"driveway|front_door|garage"} < 1` with `for: 10m`, so restart blips do not page.
The existing Alertmanager route already provides the summary behavior wanted: `group_by: alertname` collapses multiple dead cameras into one mail, `repeat_interval: 12h` limits reminders to twice a day, and `send_resolved: true` closes the loop when the camera returns.
If twice a day is still too chatty, add a camera-specific child route with a longer `repeat_interval` (e.g. 24h) instead of changing the global default.
Add a State timeline panel to dashboards/frigate.json: query `frigate_camera_fps{camera_name=~"driveway|front_door|garage"} > bool 0`, one lane per camera, value-mapped 1 = green "Connected", 0 = red "Down".
Prometheus already holds the metric history, so the panel shows past outages retroactively the moment it is provisioned.

Ship this under the current layout; it also serves as a motivating instance for 2026-09-19-dendritic-flake-parts-restructure.md (per-service alert authored in the central gateway module).
Also add rules for the silent-degradation class found on 2026-09-18 (model wiped, detection dead for 3 weeks, cameras "up" the whole time) — connectivity alerts alone can never see these:
`FrigateDetectStalled`: `frigate_skipped_fps > 0.9 * frigate_camera_fps` sustained for 30m catches a stalled detect pipeline regardless of cause (dead detector, wedged process).
`SystemdUnitFailed`: alert on failed units from the systemd exporter (ser8/firebat:9558, already scraped); frigate.nix now has an ExecStartPre that fails the unit when the detection model is missing, and this rule is what turns that fail-fast into an email — it also catches every other service that dies without its exporter noticing.
Together the layers are: fail-fast at startup (unit failure), stall detection at runtime (skipped_fps), and connectivity (camera_fps), each covering what the others cannot.
`FrigateRecordingsQuotaHigh` (added 2026-09-19): the recordings dataset `backup/cameras/recordings` has a 600G ZFS quota; alert when usage exceeds 80% (480G) via node exporter filesystem metrics for mountpoint `/mnt/cameras/recordings` (ZFS reports the quota as the filesystem size), with `for: 1h`.
When the quota fills, Frigate's storage maintainer silently evicts the oldest retained footage - including the 180-day alert archive - so quota pressure must page before eviction starts.
Sizing basis 2026-09-19: ~15-20G/day rolling 7-day window across five cameras plus 180-day alert retention; steady state estimated 300-450G.
The `FrigateCameraDown` rule and timeline panel predate the two backyard cameras; drop the `camera_name` filter entirely so current and future cameras are covered by default.
Complementary to 2026-08-30-revive-home-assistant-monitoring.md, which covers HA-side push notifications; this todo is the pure Prometheus/Grafana path with no new collection.
