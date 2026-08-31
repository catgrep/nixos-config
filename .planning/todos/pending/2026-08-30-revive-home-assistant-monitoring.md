---
created: 2026-08-31T01:45:00.000Z
title: Revive shelved Home Assistant monitoring integration
area: automation
severity: minor
files:
  - modules/automation/home-assistant.nix
  - modules/gateway/prometheus.nix
  - dashboards/
---

## Problem

Originates from the v1.1 milestone research (SUMMARY.md phase 4, ARCHITECTURE.md section 5, PITFALLS.md pitfall 8 in .planning/milestones/v1.1-research/); the corresponding Phase 7 was shelved to Future Requirements HA-01..04 and DASH-02/03 (ROADMAP.md) and nothing landed.
modules/automation/home-assistant.nix has no prometheus integration (not in extraComponents, no config.prometheus block), prometheus.nix has no HA scrape job, and the only manual automation is the Frigate alert notification - no infrastructure automations exist for camera-gone-unavailable or MQTT-broker-down, and no HA entity or system-health dashboard exists in dashboards/.
HA internals (entity states, camera availability, automation runs, database growth) are therefore invisible to the monitoring stack; a camera dropping offline is only noticed when a detection is missed.

## Solution

Enable HA's built-in Prometheus endpoint: add "prometheus" to extraComponents and a services.home-assistant.config.prometheus block with an include_domains filter (sensor, binary_sensor, camera, automation, switch) to keep cardinality sane.
Creating the long-lived access token is a human checkpoint - Bobby generates it in the HA UI and provides it for sops (secrets/firebat.yaml); agents must not create credentials.
Add a bearer-token scrape job for ser8:8123/api/prometheus in prometheus.nix, then build the HA entity-tracking and system-health dashboards in dashboards/ following the existing provisioning pattern.
Add HA manual automations for infrastructure events (camera entity unavailable, MQTT down, Frigate down) delivering via the proven Companion-app push path - these complement, not replace, the Prometheus->Alertmanager rules, covering seconds-latency mobile push for household-visible failures.
