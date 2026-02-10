# Frigate–Home Assistant Integration

## What This Is

A declarative NixOS integration between Frigate NVR and Home Assistant on ser8, enabling real-time detection alerts with snapshots delivered via push notification and an HA dashboard showing live cameras, detection events, and event history. All configuration is in Nix, version controlled.

## Core Value

When Frigate detects a person, car, or package, a push notification with a snapshot image arrives on my phone within seconds — and I can review all events from the HA dashboard.

## Requirements

### Validated

<!-- Shipped and confirmed valuable. -->

- ✓ Frigate NVR running with 3 active cameras (driveway, front_door, garage) — existing
- ✓ Object detection enabled for person, car, dog, cat, package — existing
- ✓ Mosquitto MQTT broker running on localhost:1883 — existing
- ✓ Frigate MQTT publishing enabled — existing
- ✓ Home Assistant running with MQTT and mobile_app components — existing
- ✓ Snapshots and 30-day event recording in Frigate — existing
- ✓ Camera recordings on ZFS backup pool (/mnt/cameras) — existing
- ✓ Frigate and HA accessible via Caddy reverse proxy and Tailscale — existing
- ✓ Prometheus monitoring for Frigate metrics — existing

### Active

<!-- Current scope. Building toward these. -->

- [ ] Frigate entities auto-discovered in HA via MQTT
- [ ] HA automation sends push notification with snapshot on person detection (all cameras)
- [ ] HA automation sends push notification with snapshot on car detection (all cameras)
- [ ] HA automation sends push notification with snapshot on package detection (all cameras)
- [ ] HA dashboard with live camera feeds from all active Frigate cameras
- [ ] HA dashboard shows recent detection events with thumbnails
- [ ] HA dashboard shows detection event history
- [ ] Camera controls accessible in HA (e.g., enable/disable detection per camera)
- [ ] All HA automations and dashboard config declared in Nix

### Out of Scope

- Indoor cameras (living_room, basement) — currently disabled in Frigate, not part of this integration
- side_gate camera — currently disabled in Frigate
- Custom detection zones per camera — can be added later via Frigate config
- HA Companion app installation — manual phone setup, not NixOS-configurable
- Email or SMS notifications — push via Companion app is sufficient
- Two-way audio — not supported by current camera models in this setup

## Context

- ser8 runs Frigate 0.15.2, Home Assistant, and Mosquitto on the same host
- MQTT is on localhost only (127.0.0.1:1883), no auth needed since local-only
- Frigate uses CPU-based detection (4 threads) — no dedicated AI accelerator
- HA uses declarative configuration via NixOS `services.home-assistant.config`
- Existing planning docs in `.planning/codebase/` map the full architecture
- A prior design document exists at `.claude/plans/home-assistant-nvr.md` covering the broader NVR setup
- The Frigate HACS integration provides richer HA entities than raw MQTT, but HACS requires non-declarative setup — MQTT auto-discovery is the declarative path
- HA Companion app needs to be installed on phone and connected to HA (via Tailscale URL) for push notifications to work

## Constraints

- **Declarative**: All config must be in NixOS Nix files, not HA UI-only configuration
- **Impermanence**: ser8 uses ZFS root rollback — HA state in `/var/lib/hass` must persist via impermanence rules (already configured)
- **Local MQTT**: Broker is localhost-only, no network exposure
- **No HACS**: Frigate HACS integration requires manual HA UI setup — use MQTT auto-discovery instead for declarative compatibility

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| MQTT auto-discovery over HACS integration | HACS requires non-declarative HA UI setup; MQTT auto-discovery works with declarative NixOS config | — Pending |
| Push notifications via HA Companion app | Already have mobile_app component loaded; Companion app is the standard HA mobile notification path | — Pending |
| All automations in Nix | Matches repo pattern of declarative, version-controlled infrastructure | — Pending |

---
*Last updated: 2026-02-09 after initialization*
