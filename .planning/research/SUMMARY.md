# Project Research Summary

**Project:** Frigate-Home Assistant Integration
**Domain:** NVR-to-Home Automation Integration (NixOS, declarative)
**Researched:** 2026-02-09
**Confidence:** HIGH

## Executive Summary

This milestone integrates an existing Frigate 0.15.2 NVR installation (3 active cameras: driveway, front_door, garage) with Home Assistant to enable automated push notifications on person detection. The integration requires three components: (1) the Frigate custom component from nixpkgs to create HA entities, (2) MQTT broker (Mosquitto) for event messaging, and (3) declarative automations in Nix that trigger on Frigate review events and dispatch mobile notifications with snapshots.

The recommended approach follows a layered implementation: establish the integration foundation first (custom component + config entries), then build notification automations using the frigate/reviews MQTT topic, and finally polish with dashboard views using advanced-camera-card. The entire integration runs locally on ser8 (Frigate, Mosquitto, HA all on localhost), with external access via Tailscale for mobile notifications.

The primary risk is the hybrid declarative/imperative model inherent to modern Home Assistant on NixOS. Two critical config entries (MQTT broker connection, Frigate integration URL) cannot be declared in Nix and must be configured once through the HA web UI. These persist in /var/lib/hass/.storage/ via impermanence, but this creates a one-time manual setup step that breaks pure Nix reproducibility. Mitigate by (1) verifying impermanence correctly persists .storage/, (2) documenting the UI setup steps in a runbook, and (3) validating persistence survives reboots before building automations on top.

## Key Findings

### Recommended Stack

The stack is already determined by existing infrastructure: Frigate 0.15.2 NVR, Home Assistant (NixOS module), Mosquitto MQTT broker, all running on ser8. The missing piece is the Frigate custom component for Home Assistant, available in nixpkgs as `home-assistant-custom-components.frigate`.

**Core technologies:**
- **Frigate custom component** (nixpkgs): Creates HA entities from Frigate MQTT messages, proxies API for media access — official integration, HIGH confidence
- **Mosquitto MQTT** (already running): Message broker for Frigate-to-HA events and entity state — lightweight, localhost-only, already configured
- **home-assistant.config automations** (declarative Nix): Push notification logic with snapshot attachments — version-controlled, reproducible
- **advanced-camera-card** (customLovelaceModules): Dashboard for live feeds and event browsing — optional polish, verify nixos-25.05 availability
- **HA Companion App** (iOS/Android): Push notification endpoint with image support — requires manual device registration

### Expected Features

Research identified clear feature tiers based on official Frigate documentation and community patterns.

**Must have (table stakes):**
- Frigate entities in HA (cameras, motion sensors, detection switches) — without entities, the systems are disconnected
- MQTT connectivity between Frigate and HA — foundation for all entity creation and automation
- Push notifications on person detection with snapshot — the primary motivation for this milestone
- Per-camera identification — users need to know WHERE detection happened
- Notification deduplication — prevents spam from repeated review updates

**Should have (competitive):**
- Camera dashboard with live feeds — visual monitoring alongside home controls
- Zone-aware notifications — "person at front porch" vs "person detected anywhere"
- Severity-based filtering — Frigate 0.14+ has alert vs detection severity, only alert-level events push
- Quiet hours / Do Not Disturb — suppress notifications during sleep or when home
- Actionable notification buttons — tap to view live feed or clip

**Defer (v2+):**
- Zone configuration in Frigate (separate Nix change, requires per-camera zone definition)
- Birdseye overview dashboard (easy but not essential)
- Clip/event history browsing (provided by advanced-camera-card, polish tier)

**Explicitly avoid (anti-features):**
- HACS for any component — conflicts with NixOS declarative philosophy
- LLM/AI verification — adds latency, cost, complexity for marginal accuracy gain
- Facial recognition — privacy concern, high false-positive rate
- Node-RED flows — over-engineering for simple MQTT-to-notification patterns
- External notification services (Pushover, Telegram) — HA Mobile App already works

### Architecture Approach

All components run on ser8 localhost. The integration uses two communication paths: (1) the frigate-hass-integration custom component creates entities via MQTT subscription and proxies Frigate's HTTP API for media access, and (2) MQTT-triggered automations in HA respond to frigate/reviews events to dispatch push notifications via the mobile_app service.

**Major components:**
1. **Frigate NVR** — Camera ingestion, object detection, recording, MQTT event publishing. Owns detection logic and snapshot generation.
2. **Mosquitto** — Pure message broker routing frigate/reviews, frigate/events, and per-camera topics between Frigate and HA. No transformation.
3. **Home Assistant** — Automation hub, dashboard presentation, push notification dispatch. Owns when-to-notify logic.
4. **Frigate custom component** — Entity auto-creation from MQTT, /api/frigate/notifications/* proxy for media access. Runs inside HA process.
5. **HA Companion App** — Mobile push notification endpoint. Requires external URL access via Tailscale for snapshot images.
6. **Caddy** (firebat) — Reverse proxy for HTTPS access to both Frigate and HA. Not used for internal localhost integration.

**Data flow pattern for notifications:**
Camera RTSP → Frigate detects person → Publishes frigate/reviews (type: new, severity: alert, camera: driveway, detections: [event-id]) → HA automation triggers on MQTT → Conditions filter (type == new, severity == alert, "person" in objects) → Action: notify.mobile_app with image: /api/frigate/notifications/event-id/thumbnail.jpg, tag: frigate-review-id → Companion app shows notification with snapshot.

**Critical pattern:** Use frigate/reviews topic (not frigate/events) for notifications because reviews aggregate frame-level detections into incidents, provide severity filtering, and include detection IDs for media fetching. Using frigate/events causes notification floods.

### Critical Pitfalls

Research identified 13 pitfalls across critical/moderate/minor severity. Top 5 that directly impact roadmap:

1. **MQTT Integration Requires UI Config Flow, Not YAML** — Modern HA requires MQTT broker connection via web UI (Settings → Integrations → Add MQTT). Declaring mqtt: in NixOS config generates yaml entries that are silently ignored. Prevention: Accept one-time manual UI step, verify config entry persists in .storage/core.config_entries, document in runbook. CRITICAL for Phase 1.

2. **Frigate Integration Requires Custom Component, Not Just MQTT Discovery** — Frigate does not publish HA MQTT discovery messages. Without the frigate-hass-integration custom component, no entities appear. Prevention: Add pkgs.home-assistant-custom-components.frigate to customComponents, configure integration URL via UI (http://127.0.0.1:5000). CRITICAL for Phase 1.

3. **Impermanence Wipes UI-Configured Integrations on Reboot** — MQTT and Frigate config entries live in /var/lib/hass/.storage/. ZFS root rollback destroys these unless /var/lib/hass is properly persisted. Prevention: Verify impermanence bind mount works, test reboot before building automations. CRITICAL for Phase 1.

4. **Declarative Config Overwrites UI Changes on NixOS Rebuild** — configuration.yaml is symlinked from Nix store, regenerated on each activation. Prevention: Use split pattern: "automation manual" for Nix automations, "automation ui" = "!include automations.yaml" for UI-created ones. Create empty automations.yaml via tmpfiles to prevent boot failure. CRITICAL for Phase 2.

5. **Service Startup Race Between Mosquitto, Frigate, and HA** — Without explicit systemd dependencies, Frigate may start before Mosquitto accepts connections, or HA loads before Frigate publishes initial state. Prevention: Add after/requires dependencies: Frigate after mosquitto.service, HA after both. MODERATE for Phase 1.

## Implications for Roadmap

Based on research, this milestone naturally decomposes into 3 sequential phases driven by dependency ordering and pitfall mitigation.

### Phase 1: Integration Foundation (Service Wiring + Entity Creation)
**Rationale:** Must establish baseline connectivity before building automations. The 3 critical config-flow pitfalls all surface here. This phase validates impermanence, systemd ordering, and one-time UI setup before any code depends on it.

**Delivers:** Frigate entities appear in HA (cameras, motion sensors, detection switches, performance sensors). Manual verification that entities update in real-time and persist across reboots.

**Addresses:**
- Frigate custom component installation (customComponents)
- MQTT config entry (UI, one-time)
- Frigate config entry (UI, one-time)
- Verify entity creation (table stakes from FEATURES.md)
- Impermanence validation (reboot test)

**Avoids:**
- Pitfall 1 (MQTT config flow)
- Pitfall 2 (custom component requirement)
- Pitfall 3 (impermanence wipe)
- Pitfall 5 (startup race)
- Pitfall 10 (missing automations.yaml)

**Implementation notes:**
- Add systemd dependencies: frigate.service after/requires mosquitto.service, home-assistant.service after mosquitto + frigate
- Create empty automations.yaml via tmpfiles rule
- Document UI setup steps in .planning/research/RUNBOOK.md: (1) Add MQTT integration at localhost:1883, (2) Add Frigate integration at http://127.0.0.1:5000
- After deployment, reboot and verify entities persist
- Add "automation manual" and "automation ui" split to config structure

**Research flag:** No additional research needed. Well-documented patterns.

### Phase 2: Push Notifications (Primary Goal)
**Rationale:** Core value delivery. Once entities exist, notifications are pure MQTT automation logic. This phase implements the primary user story: "When Frigate detects a person, I get a push notification with a snapshot on my phone."

**Delivers:** Working push notifications with snapshots for person detection on all 3 cameras. Notifications include camera name, snapshot image, and deduplication via tags.

**Addresses:**
- Person detection notification automation (table stakes)
- Notification deduplication (table stakes)
- Per-camera identification (table stakes)
- Snapshot in notifications (table stakes)
- Severity-based filtering (differentiator, built into frigate/reviews)

**Avoids:**
- Pitfall 4 (declarative/UI boundary via automation manual section)
- Pitfall 7 (notification snapshots require external URL + unauthenticated proxy)

**Implementation notes:**
- Declare automation in services.home-assistant.config."automation manual"
- Trigger: MQTT frigate/reviews topic
- Condition: type == "new", severity == "alert", "person" in objects
- Action: notify.mobile_app_DEVICE with image: /api/frigate/notifications/.../thumbnail.jpg, tag: frigate-review-id
- Configure HA external URL in UI: https://hass.shad-bangus.ts.net
- Enable "Unauthenticated notification event proxy" in Frigate integration settings (Advanced Mode required)
- Register Companion App via Tailscale URL, verify device appears in .storage/core.device_registry

**Research flag:** No additional research needed. Official Frigate notification guide provides complete automation template.

### Phase 3: Dashboard Polish (Optional, Quality of Life)
**Rationale:** Notifications work, now add visual monitoring. This phase is entirely optional polish — the core functionality is complete without it. Dashboard iteration can happen in UI before codifying in Nix.

**Delivers:** Lovelace dashboard with live camera feeds, motion state indicators, detection toggle switches, and event browsing (if advanced-camera-card is available).

**Addresses:**
- Camera dashboard with live feeds (differentiator)
- Detection toggle switches (table stakes, already exist as entities, just need dashboard cards)
- advanced-camera-card for event timeline and clip browsing (differentiator)

**Avoids:**
- HACS anti-pattern (use customLovelaceModules if available)
- Over-engineering dashboard before validating notification UX

**Implementation notes:**
- Verify pkgs.home-assistant-custom-lovelace-modules.advanced-camera-card exists on nixos-25.05 branch
- If not packaged, defer dashboard polish or create via picture-entity cards
- Build dashboard iteratively in HA UI, do not attempt to declare Lovelace in Nix (complexity not worth it)
- Dashboard config lives in .storage/, persists via impermanence

**Research flag:** Need to verify advanced-camera-card availability in nixpkgs. If not available, document manual installation path or defer.

### Phase Ordering Rationale

- **Phase 1 must come first** because automations and dashboards require entities to exist. The integration foundation validates all config-flow setup and impermanence behavior. Without entity creation working and persisting, Phases 2-3 cannot proceed.

- **Phase 2 before Phase 3** because notifications are the stated goal and dashboard is polish. If advanced-camera-card is not packaged, Phase 3 can be deferred entirely without blocking core functionality.

- **Each phase is independently deployable and testable**, enabling incremental validation rather than big-bang integration.

- **Architecture naturally suggests this decomposition**: Phase 1 = entity layer, Phase 2 = automation layer, Phase 3 = presentation layer. Clean separation of concerns.

- **Pitfall mitigation drives phase structure**: All critical pitfalls surface in Phase 1 (config flow, impermanence, startup ordering). Phase 2 addresses moderate pitfalls (notification URLs, external access). Phase 3 has minimal risk.

### Research Flags

**Phases needing deeper research during planning:**
- **Phase 3:** Verify advanced-camera-card package availability on nixos-25.05. If not available, decide between (1) manual Lovelace card creation in UI, (2) defer dashboard polish, or (3) package it ourselves.

**Phases with standard patterns (skip research-phase):**
- **Phase 1:** Well-documented in Frigate HA integration docs, NixOS Wiki, and existing codebase (frigate.nix, home-assistant.nix). No unknowns.
- **Phase 2:** Official Frigate notification guide provides complete automation template. MQTT trigger patterns are standard HA. No unknowns.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | All components already running (Frigate, Mosquitto, HA). Only missing piece is frigate custom component, confirmed available in nixpkgs via PR #371866. |
| Features | HIGH | Feature requirements derived from official Frigate HA integration docs and notification guide. Table stakes are clearly documented, differentiators have community consensus. |
| Architecture | HIGH | Verified against official Frigate MQTT docs, HA integration docs, and existing codebase. Data flow patterns match recommended approach. |
| Pitfalls | HIGH | All critical pitfalls validated via official docs, NixOS Wiki, GitHub issues, and community reports. Impermanence behavior confirmed in existing ser8 config. |

**Overall confidence:** HIGH

Research covered all four areas comprehensively. Official Frigate documentation is excellent and covers the exact integration path (MQTT + custom component + notifications). NixOS-specific concerns (config flow vs declarative yaml, impermanence, customComponents pattern) are well-documented on NixOS Wiki and confirmed in existing codebase.

### Gaps to Address

Minor gaps that can be resolved during planning/execution:

- **advanced-camera-card availability**: Needs package search on nixos-25.05 branch during Phase 3 planning. If not available, document workaround (manual card creation) or defer dashboard polish.

- **Frigate integration version compatibility**: Check nixpkgs version of home-assistant-custom-components.frigate matches Frigate 0.15.2 during Phase 1 planning. Version mismatches can cause entity creation failures. Mitigation: pin package version if needed.

- **Mobile device name for notify service**: The automation needs the actual device name (notify.mobile_app_DEVICE_NAME). This is determined during Companion App registration in Phase 2. Placeholder in automation template, fill after registration.

- **Tailscale external URL validation**: Assumption that https://hass.shad-bangus.ts.net works for external notification image access needs validation during Phase 2. If images don't load, may need to adjust Caddy config or Tailscale settings.

All gaps are implementation details, not architectural unknowns. None block roadmap creation.

## Sources

### Primary (HIGH confidence)
- [Frigate Home Assistant Integration Docs](https://docs.frigate.video/integrations/home-assistant/) — integration setup, entity types, config flow requirements
- [Frigate MQTT Documentation](https://docs.frigate.video/integrations/mqtt/) — topic structure, payload formats, retained messages
- [Frigate HA Notification Guide](https://docs.frigate.video/guides/ha_notifications/) — complete automation templates, best practices
- [frigate-hass-integration GitHub](https://github.com/blakeblackshear/frigate-hass-integration) — custom component source, version compatibility
- [NixOS Wiki: Home Assistant](https://wiki.nixos.org/wiki/Home_Assistant) — customComponents pattern, config flow vs yaml, impermanence considerations
- [Home Assistant MQTT Integration](https://www.home-assistant.io/integrations/mqtt) — config flow requirement, YAML deprecation
- [NixOS HA Module Source](https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/services/home-automation/home-assistant.nix) — automation manual/ui coexistence pattern
- Existing codebase (modules/automation/frigate.nix, modules/automation/home-assistant.nix, hosts/ser8/impermanence.nix) — current configuration state

### Secondary (MEDIUM confidence)
- [nixpkgs PR #371866](https://github.com/NixOS/nixpkgs/pull/371866) — Frigate component package version
- [advanced-camera-card GitHub](https://github.com/dermotduffy/advanced-camera-card) — dashboard card features, renamed from frigate-hass-card
- [SgtBatten HA Blueprints](https://github.com/SgtBatten/HA_blueprints) — community notification automation patterns
- [Frigate GitHub issue #5295](https://github.com/blakeblackshear/frigate/issues/5295) — MQTT retained message cleanup
- [HA Community: MQTT YAML not working](https://community.home-assistant.io/t/mqtt-integration-setup-in-configuration-yaml-does-not-work/480421) — config flow requirement confirmation
- [HA Community: Frigate MQTT issues](https://community.home-assistant.io/t/frigate-mqtt-not-playing-nicely-together/688973) — integration URL troubleshooting
- [Frigate 0.14 Review Notifications](https://github.com/blakeblackshear/frigate/discussions/11554) — severity filtering introduction

---
*Research completed: 2026-02-09*
*Ready for roadmap: yes*
