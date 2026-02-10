# Phase 1: Integration Foundation - Research

**Researched:** 2026-02-09
**Domain:** Frigate NVR <-> Home Assistant integration on NixOS with impermanence
**Confidence:** HIGH

## Summary

Phase 1 wires Frigate NVR (0.15.2, 3 active cameras) to Home Assistant on ser8 so that Frigate entities (cameras, binary sensors, switches) auto-appear in HA, update in real-time via MQTT, persist across ZFS root rollback reboots, and start in the correct systemd order. It also adds per-camera detection zones in Frigate to reduce false positive events.

The integration requires three NixOS-level changes: (1) installing the `frigate` custom component via `customComponents`, (2) adding systemd service ordering dependencies for Mosquitto/Frigate/HA, and (3) configuring detection zones in `services.frigate.settings.cameras`. Two one-time manual UI steps are unavoidable -- adding the MQTT integration (localhost:1883) and the Frigate integration (http://127.0.0.1:5000) through the HA web UI. Both config entries persist in `/var/lib/hass/.storage/` via the existing impermanence configuration. Additionally, the automation split pattern (`"automation manual"` + `"automation ui"`) and an empty `automations.yaml` file must be set up to support Phase 2 automations.

**Primary recommendation:** Add `pkgs.home-assistant-custom-components.frigate` to `customComponents`, wire systemd dependencies, configure zones, deploy, then complete the two UI config flows and validate persistence with a reboot.

## Standard Stack

### Core

| Component | Version | Purpose | Why Standard |
|-----------|---------|---------|--------------|
| `home-assistant-custom-components.frigate` | 5.9.2 (nixos-25.05) | Creates HA entities from Frigate MQTT topics, proxies Frigate API for media access | Official integration. Only supported path for Frigate entities in HA. Packaged in nixpkgs, no HACS needed. |
| Mosquitto | Already deployed (127.0.0.1:1883) | MQTT broker between Frigate and HA | Already running, no config changes needed to broker itself |
| Frigate NVR | 0.15.2 (already deployed) | Object detection, recording, MQTT publishing | Already running with MQTT enabled and 3 active cameras |
| Home Assistant | nixos-25.05 channel version | Automation hub, entity management, config entry storage | Already running with `mqtt` and `mobile_app` in `extraComponents` |

### Supporting

| Component | Version | Purpose | When to Use |
|-----------|---------|---------|-------------|
| `paho-mqtt` Python package | Already in `extraPackages` | MQTT client library for HA | Already configured, no change needed |
| `mosquitto` CLI tools | System package | Debug MQTT topics with `mosquitto_sub`/`mosquitto_pub` | Troubleshooting entity creation and MQTT message flow |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `customComponents` (frigate) | HACS | HACS is imperative, not reproducible, conflicts with NixOS impermanence. Never use on NixOS. |
| MQTT auto-discovery alone | frigate custom component | Frigate does NOT publish HA MQTT discovery messages. Without the custom component, no entities are created. The custom component is mandatory. |

### Installation

No new flake inputs needed. No new system packages needed. Changes are to existing Nix module files only:

```nix
# In modules/automation/home-assistant.nix
services.home-assistant = {
  customComponents = with pkgs.home-assistant-custom-components; [
    frigate
  ];
};
```

## Architecture Patterns

### Recommended File Structure Changes

```
modules/automation/
  home-assistant.nix     # Add customComponents, automation split, tmpfiles, systemd ordering
  frigate.nix            # Add zones config, add mosquitto systemd dependency
  frigate-exporter.nix   # No changes
  default.nix            # No changes
```

### Pattern 1: Frigate Custom Component via customComponents

**What:** Install the Frigate HA integration declaratively through NixOS rather than HACS.
**When to use:** Always on NixOS. This is the only supported declarative path.
**Example:**
```nix
# Source: https://wiki.nixos.org/wiki/Home_Assistant
services.home-assistant = {
  customComponents = with pkgs.home-assistant-custom-components; [
    frigate
  ];
};
```

### Pattern 2: Automation Manual/UI Split

**What:** Declare Nix-managed automations in `"automation manual"` while allowing UI-created automations via `"automation ui"`.
**When to use:** Any HA config that will have declarative automations (Phase 2 depends on this being set up in Phase 1).
**Example:**
```nix
# Source: https://wiki.nixos.org/wiki/Home_Assistant
services.home-assistant.config = {
  # Nix-managed automations (Phase 2 will populate this)
  "automation manual" = [ ];
  # UI-created automations coexist
  "automation ui" = "!include automations.yaml";
};
```

Must also create the empty automations.yaml to prevent HA boot failure:
```nix
# Source: https://wiki.nixos.org/wiki/Home_Assistant
systemd.tmpfiles.rules = [
  "f ${config.services.home-assistant.configDir}/automations.yaml 0644 hass hass"
];
```

### Pattern 3: Systemd Service Ordering (Mosquitto before Frigate before HA)

**What:** Explicit systemd `after`/`requires`/`wants` to ensure correct startup order.
**When to use:** Always. Without this, race conditions cause MQTT connection failures on boot.
**Example:**
```nix
# Frigate depends on Mosquitto (hard dependency)
systemd.services.frigate = lib.mkIf config.services.frigate.enable {
  after = [
    "mosquitto.service"
    # ...existing deps (zfs-mount.service, network-online.target, sops-nix.service)
  ];
  requires = [
    "mosquitto.service"
    # ...existing (zfs-mount.service)
  ];
};

# Home Assistant depends on Mosquitto (soft) and Frigate (soft)
systemd.services.home-assistant = {
  after = [ "mosquitto.service" "frigate.service" ];
  wants = [ "mosquitto.service" "frigate.service" ];
};
```

Note: Use `requires` for Frigate->Mosquitto (Frigate cannot function without MQTT). Use `wants` for HA->Mosquitto and HA->Frigate (HA can start without them and reconnect, but ordering prevents initial unavailable entities).

### Pattern 4: Frigate Zone Configuration in Nix

**What:** Define detection zones per camera as Nix attribute sets that map to Frigate YAML.
**When to use:** INTG-07 requirement. Reduces false positives by constraining where detections count.
**Example:**
```nix
# Source: https://docs.frigate.video/configuration/zones/
services.frigate.settings.cameras = {
  driveway = {
    # ...existing config...
    zones = {
      driveway_area = {
        coordinates = "0.1,0.3,0.9,0.3,0.9,0.95,0.1,0.95";
        objects = [ "person" "car" "package" ];
      };
    };
    review = {
      alerts = {
        required_zones = [ "driveway_area" ];
      };
    };
  };
  front_door = {
    # ...existing config...
    zones = {
      porch = {
        coordinates = "0.2,0.4,0.8,0.4,0.8,0.9,0.2,0.9";
        objects = [ "person" "package" ];
      };
    };
    review = {
      alerts = {
        required_zones = [ "porch" ];
      };
    };
  };
  garage = {
    # ...existing config...
    zones = {
      garage_area = {
        coordinates = "0.1,0.2,0.9,0.2,0.9,0.9,0.1,0.9";
        objects = [ "person" "car" "package" ];
      };
    };
    review = {
      alerts = {
        required_zones = [ "garage_area" ];
      };
    };
  };
};
```

**Important:** Zone coordinates are normalized (0.0-1.0) fractions of frame dimensions. The exact values must be determined using Frigate's web UI zone editor. On NixOS, the Frigate config file is read-only, so the workflow is:
1. Draw zone in Frigate UI (Settings > camera > Zones)
2. Save in UI (Frigate stores it internally even though it cannot write to config)
3. Copy the coordinates from the UI using the copy button
4. Paste coordinates into the Nix config
5. Rebuild and deploy

Source: [Frigate NixOS zone workflow](https://github.com/blakeblackshear/frigate/discussions/13770)

### Pattern 5: One-Time UI Config Entries (Persist via Impermanence)

**What:** MQTT and Frigate integration config entries cannot be declared in Nix. They must be created once through the HA web UI and persist in `/var/lib/hass/.storage/core.config_entries`.
**When to use:** After first deployment. One-time only.
**Steps:**
1. Navigate to HA web UI (https://hass.shad-bangus.ts.net)
2. Settings > Devices & Services > Add Integration > MQTT
3. Enter broker: `127.0.0.1`, port: `1883`, no username/password
4. Settings > Devices & Services > Add Integration > Frigate
5. Enter URL: `http://127.0.0.1:5000`
6. Reboot ser8 and verify both integrations are still present

### Anti-Patterns to Avoid

- **Declaring `mqtt:` in NixOS config for broker connection:** Modern HA ignores MQTT broker settings in `configuration.yaml`. The broker connection must be configured via UI config flow. Declaring `mqtt:` only sets up MQTT-based sensors/automations, not the broker connection itself.
- **Pointing Frigate integration at port 80 or Caddy proxy URL:** Use `http://127.0.0.1:5000` (direct API), not port 80 (nginx frontend) or Caddy reverse proxy.
- **Installing HACS for any reason:** Conflicts with NixOS declarative philosophy and impermanence.
- **Using `requires` for HA's dependency on Frigate:** HA should use `wants` for Frigate so it can start even if Frigate is temporarily down. Use `requires` only for Frigate->Mosquitto where Frigate truly cannot function without MQTT.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Frigate entity creation in HA | Custom MQTT sensors for each Frigate camera/state | `home-assistant-custom-components.frigate` | The custom component creates 8+ entity types per camera (camera, binary sensors, switches, sensors, images) automatically. Hand-rolling means maintaining dozens of MQTT sensor definitions. |
| Notification snapshot proxy | Custom nginx proxy for Frigate API | Frigate custom component's `/api/frigate/notifications/*` proxy | The component handles auth, caching, and URL mapping. Building a proxy misses edge cases. |
| Service startup ordering | Bash scripts or manual systemd overrides | NixOS `systemd.services.*.after`/`requires`/`wants` | Native NixOS module pattern. Survives rebuilds, integrates with module system. |
| Empty automations.yaml creation | Manual file placement or activation script | `systemd.tmpfiles.rules` | Standard NixOS pattern for ensuring files exist. Idempotent, runs early in boot. |

**Key insight:** The Frigate custom component replaces hundreds of lines of manual MQTT sensor configuration with a single package addition and one UI config flow.

## Common Pitfalls

### Pitfall 1: MQTT Integration Requires UI Config Flow, Not YAML

**What goes wrong:** You add `"mqtt"` to `extraComponents` and assume HA connects to Mosquitto. It does not. No Frigate entities appear.
**Why it happens:** Modern HA (2024+) moved MQTT broker configuration from `configuration.yaml` to UI-based config flows. The `extraComponents` line loads the component code but does not configure the broker connection.
**How to avoid:** After deployment, manually add MQTT integration via UI (Settings > Integrations > MQTT > localhost:1883). This creates a config entry in `.storage/core.config_entries` which persists via impermanence.
**Warning signs:** No MQTT-related log lines in HA journal. No Frigate entities. MQTT integration not listed under configured integrations in HA UI.

**Confidence:** HIGH -- [HA MQTT docs](https://www.home-assistant.io/integrations/mqtt), [NixOS Wiki](https://wiki.nixos.org/wiki/Home_Assistant)

### Pitfall 2: Custom Component Is Mandatory (Not Just MQTT Discovery)

**What goes wrong:** You assume Frigate's MQTT messages will auto-discover in HA like other MQTT devices. They do not. Frigate uses its own topic structure (`frigate/<camera>/<object>`), not HA's MQTT discovery format (`homeassistant/<component>/<id>/config`).
**Why it happens:** The project context mentions "MQTT auto-discovery" which is technically correct -- the custom component subscribes to MQTT and creates entities -- but the custom component itself is the required piece.
**How to avoid:** Always install `home-assistant-custom-components.frigate` via `customComponents`. Then add the Frigate integration via UI (http://127.0.0.1:5000).
**Warning signs:** MQTT messages flow (visible via `mosquitto_sub -t 'frigate/#'`) but no Frigate entities in HA.

**Confidence:** HIGH -- [Frigate HA docs](https://docs.frigate.video/integrations/home-assistant/)

### Pitfall 3: Impermanence Must Persist .storage/ Subdirectory

**What goes wrong:** After configuring MQTT and Frigate integrations via UI, a reboot wipes them because ZFS root rollback destroys `/var/lib/hass/.storage/`.
**Why it happens:** Config flow entries live in `/var/lib/hass/.storage/core.config_entries`. If the impermanence bind mount for `/var/lib/hass` is not working correctly, these are lost on every boot.
**How to avoid:** The current `impermanence.nix` already persists `/var/lib/hass` (line 75). Verify after first setup by rebooting and checking that integrations are still present.
**Warning signs:** HA shows onboarding screen after reboot instead of login. Integrations disappear after reboot.

**Confidence:** HIGH -- verified in `hosts/ser8/impermanence.nix`

### Pitfall 4: Missing automations.yaml Crashes HA

**What goes wrong:** If `"automation ui" = "!include automations.yaml"` is in config but the file does not exist, HA fails to start entirely.
**Why it happens:** HA's YAML parser throws an error when an `!include` target is missing. On fresh installs or after impermanence wipe of individual files, this file may not exist.
**How to avoid:** Create it via tmpfiles: `"f /var/lib/hass/automations.yaml 0644 hass hass"`. This creates an empty file if absent.
**Warning signs:** HA service fails to start. Journal shows YAML parse error referencing `automations.yaml`.

**Confidence:** HIGH -- [NixOS Wiki](https://wiki.nixos.org/wiki/Home_Assistant)

### Pitfall 5: Service Startup Race Condition

**What goes wrong:** Frigate starts before Mosquitto is accepting connections. Frigate logs MQTT connection errors. HA starts before Frigate has published initial state, causing entities to show "unavailable."
**Why it happens:** Current `frigate.nix` has `after = [ "zfs-mount.service" "network-online.target" "sops-nix.service" ]` but no dependency on `mosquitto.service`. Systemd does not guarantee ordering without explicit dependencies.
**How to avoid:** Add `after` and `requires`/`wants` dependencies as described in Pattern 3 above.
**Warning signs:** Frigate journal shows MQTT connection refused errors on boot. HA shows Frigate entities as "unavailable" until Frigate reconnects.

**Confidence:** HIGH -- standard systemd ordering concern, confirmed missing in current config

### Pitfall 6: Frigate URL Must Be Direct API (Port 5000), Not Nginx (Port 80)

**What goes wrong:** Camera entities appear but show blank/black in HA. Snapshots work but live streams do not.
**Why it happens:** Frigate on NixOS runs nginx on port 80 as a frontend, but the HA integration needs the direct API on port 5000 for proper entity management and media proxying.
**How to avoid:** When adding Frigate integration in HA UI, use `http://127.0.0.1:5000`.
**Warning signs:** Camera entity exists but shows blank. API calls partially work. Check browser network tab for failed requests.

**Confidence:** HIGH -- [Frigate HA docs](https://docs.frigate.video/integrations/home-assistant/), [NixOS Discourse](https://discourse.nixos.org/t/frigate-into-home-assistant/62851)

### Pitfall 7: Zone Coordinates Are Read-Only on NixOS

**What goes wrong:** You try to define zones through Frigate's web UI but the config file cannot be saved because NixOS makes it read-only.
**Why it happens:** Frigate 0.14+ attempts to write zone/mask data back to the config file, which is a Nix store symlink on NixOS.
**How to avoid:** Use the Frigate UI to draw zones and get coordinates, then copy coordinates into Nix config. The workflow is: draw in UI > save (Frigate stores internally) > copy coordinates via copy button > paste into Nix > rebuild.
**Warning signs:** Frigate UI shows "failed to save config" when editing zones. This is expected on NixOS.

**Confidence:** HIGH -- [Frigate NixOS Discussion #13770](https://github.com/blakeblackshear/frigate/discussions/13770)

### Pitfall 8: Declarative Config Overwrites UI Changes on Rebuild

**What goes wrong:** Changes made in HA web UI to `configuration.yaml`-managed settings (logger, recorder, http) are silently reverted on `nixos-rebuild switch`.
**Why it happens:** NixOS generates `configuration.yaml` from `services.home-assistant.config` and symlinks it. It is regenerated on every activation.
**How to avoid:** Establish clear ownership boundary: Nix owns `configuration.yaml` (core settings). HA UI owns `.storage/` (integrations, devices, dashboards). Use the `"automation manual"` + `"automation ui"` split for automations.
**Warning signs:** Settings revert after `make switch-ser8`.

**Confidence:** HIGH -- [NixOS Wiki](https://wiki.nixos.org/wiki/Home_Assistant)

## Code Examples

Verified patterns from official sources:

### Complete Home Assistant Module Additions

```nix
# modules/automation/home-assistant.nix -- additions to existing config
# Source: https://wiki.nixos.org/wiki/Home_Assistant, https://docs.frigate.video/integrations/home-assistant/

services.home-assistant = {
  # NEW: Frigate custom component for entity auto-creation
  customComponents = with pkgs.home-assistant-custom-components; [
    frigate
  ];

  config = {
    # ... existing config (homeassistant, http, recorder, logger) stays unchanged ...

    # NEW: Automation split pattern (prepares for Phase 2)
    "automation manual" = [ ];
    "automation ui" = "!include automations.yaml";
  };
};

# NEW: Ensure automations.yaml exists (prevents HA boot failure)
# Note: Merge with existing tmpfiles.rules using lib.mkAfter or list append
systemd.tmpfiles.rules = [
  # ... existing tmpfiles rules stay unchanged ...
  "f /var/lib/hass/automations.yaml 0644 hass hass"
];

# NEW: Service ordering -- HA waits for Mosquitto and Frigate
systemd.services.home-assistant = {
  after = [ "mosquitto.service" "frigate.service" ];
  wants = [ "mosquitto.service" "frigate.service" ];
};
```

### Complete Frigate Module Additions

```nix
# modules/automation/frigate.nix -- additions to existing systemd config
# Source: Standard systemd ordering pattern

# Add mosquitto.service to existing dependency lists
systemd.services.frigate = lib.mkIf config.services.frigate.enable {
  after = [
    "mosquitto.service"  # NEW
    "zfs-mount.service"
    "network-online.target"
    "sops-nix.service"
  ];
  requires = [
    "mosquitto.service"  # NEW
    "zfs-mount.service"
  ];
  wants = [ "network-online.target" ];

  serviceConfig = {
    EnvironmentFile = config.sops.templates."frigate.env".path;
  };
};
```

### Zone Configuration Example

```nix
# modules/automation/frigate.nix -- zone additions to camera config
# Source: https://docs.frigate.video/configuration/zones/
# Note: Coordinates below are PLACEHOLDERS. Actual values must be
# determined using Frigate's web UI zone editor per camera.

services.frigate.settings.cameras = {
  driveway = {
    # ...existing driveway config stays unchanged...
    zones = {
      driveway_zone = {
        # Placeholder -- replace with actual coordinates from Frigate UI
        coordinates = "0.05,0.30,0.95,0.30,0.95,0.95,0.05,0.95";
        objects = [ "person" "car" "package" ];
        inertia = 3;
      };
    };
    review = {
      alerts = {
        required_zones = [ "driveway_zone" ];
      };
    };
  };

  front_door = {
    # ...existing front_door config stays unchanged...
    zones = {
      porch_zone = {
        coordinates = "0.10,0.35,0.90,0.35,0.90,0.90,0.10,0.90";
        objects = [ "person" "package" ];
        inertia = 3;
      };
    };
    review = {
      alerts = {
        required_zones = [ "porch_zone" ];
      };
    };
  };

  garage = {
    # ...existing garage config stays unchanged...
    zones = {
      garage_zone = {
        coordinates = "0.10,0.25,0.90,0.25,0.90,0.90,0.10,0.90";
        objects = [ "person" "car" "package" ];
        inertia = 3;
      };
    };
    review = {
      alerts = {
        required_zones = [ "garage_zone" ];
      };
    };
  };
};
```

### Verifying MQTT Message Flow (Debug)

```bash
# Subscribe to all Frigate MQTT topics to verify messages are flowing
ssh bdhill@ser8 nix-shell -p mosquitto --command "mosquitto_sub -h 127.0.0.1 -t 'frigate/#' -v"

# Check specific entity state
ssh bdhill@ser8 nix-shell -p mosquitto --command "mosquitto_sub -h 127.0.0.1 -t 'frigate/available' -v"

# Verify per-camera detection state
ssh bdhill@ser8 nix-shell -p mosquitto --command "mosquitto_sub -h 127.0.0.1 -t 'frigate/driveway/detect/state' -v"
```

### Verifying Entities After Setup

After UI config flows are complete, verify in HA:
1. Settings > Devices & Services > MQTT should show as configured integration
2. Settings > Devices & Services > Frigate should show as configured integration
3. Settings > Devices & Services > Frigate > N entities should list:
   - `camera.driveway`, `camera.front_door`, `camera.garage`
   - `binary_sensor.driveway_motion`, etc.
   - `switch.driveway_detect`, `switch.driveway_recordings`, `switch.driveway_snapshots`, etc.
   - `sensor.driveway_person_count`, etc.
4. Developer Tools > States > filter "frigate" should show all entities with non-"unavailable" states

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| MQTT broker config in YAML | UI config flow for MQTT broker | HA 2024.x | Cannot declare broker connection in Nix. One-time UI step required. |
| `frigate/events` for notifications | `frigate/reviews` for notifications | Frigate 0.14 (late 2024) | Reviews aggregate detections into incidents with severity levels. Less noise. |
| `frigate-hass-card` Lovelace module | `advanced-camera-card` (renamed) | v7.0.0 (Feb 2025) | Same project, new name. Check nixpkgs for actual package name. |
| Manual zone coordinates in YAML | Frigate UI zone editor + copy to config | Frigate 0.14+ | Frigate tries to write config (fails on NixOS). Copy workflow documented. |

**Deprecated/outdated:**
- `mqtt:` broker settings in `configuration.yaml` -- ignored by modern HA for broker connection
- `frigate/events` for notification automations -- `frigate/reviews` is the recommended trigger
- `frigate-hass-card` package name -- renamed to `advanced-camera-card` in v7.0.0

## Open Questions

1. **Exact zone coordinates for each camera**
   - What we know: Coordinates are normalized 0.0-1.0 fractions of frame dimensions. The zone editor in Frigate's web UI can generate them.
   - What's unclear: The actual coordinate values for each camera's detection zone. These are camera-specific and depend on the physical view.
   - Recommendation: Deploy with placeholder coordinates, then use Frigate UI to draw accurate zones, copy coordinates, and update Nix config in a follow-up rebuild.

2. **frigate-hass-integration 5.9.2 compatibility with Frigate 0.15.2**
   - What we know: v5.9.2 includes "Fixed handling of older Frigate versions using int type" and "Corrected access of version 0.16-specific properties" -- both suggesting backward compatibility with 0.15.x. New features (face recognition, license plate) require Frigate 0.16+ but are additive.
   - What's unclear: No explicit compatibility matrix exists in the integration docs.
   - Recommendation: Proceed with v5.9.2 (the nixos-25.05 version). Check HA logs after deployment for any version mismatch errors. If issues arise, the integration version can be pinned via overlay.

3. **Lovelace customLovelaceModules for storage mode**
   - What we know: NixOS Wiki notes that in `storage` mode (the default), custom lovelace modules must be manually added through the HA UI Resources tab with path `/local/nixos-lovelace-modules/<module-entrypoint>`.
   - What's unclear: Whether this is needed for Phase 1 (it is not -- dashboard is Phase 3).
   - Recommendation: Defer to Phase 3 research. Not relevant for Phase 1.

## Sources

### Primary (HIGH confidence)
- [Frigate Home Assistant Integration Docs](https://docs.frigate.video/integrations/home-assistant/) -- Integration setup, entity types, config flow requirements
- [Frigate MQTT Documentation](https://docs.frigate.video/integrations/mqtt/) -- Topic structure, payload formats, retained messages
- [Frigate Zone Configuration](https://docs.frigate.video/configuration/zones/) -- Zone YAML schema, coordinates, required_zones, inertia, loitering_time
- [Frigate Full Reference Config](https://docs.frigate.video/configuration/reference/) -- Complete YAML schema for all settings including zones
- [NixOS Wiki: Home Assistant](https://wiki.nixos.org/wiki/Home_Assistant) -- customComponents, automation split, tmpfiles pattern
- [Home Assistant MQTT Integration](https://www.home-assistant.io/integrations/mqtt) -- Config flow requirement confirmation
- Existing codebase: `modules/automation/frigate.nix`, `modules/automation/home-assistant.nix`, `hosts/ser8/impermanence.nix`, `hosts/ser8/configuration.nix` -- Current configuration state
- [frigate-hass-integration v5.9.2 release](https://github.com/blakeblackshear/frigate-hass-integration/releases/v5.9.2) -- Version and changelog on nixos-25.05
- [nixpkgs frigate custom component (nixos-25.05)](https://github.com/NixOS/nixpkgs/tree/nixos-25.05/pkgs/servers/home-assistant/custom-components) -- Package confirmed present

### Secondary (MEDIUM confidence)
- [Frigate NixOS Zone Workflow Discussion #13770](https://github.com/blakeblackshear/frigate/discussions/13770) -- NixOS read-only config workaround for zones
- [NixOS Discourse: Frigate into HA](https://discourse.nixos.org/t/frigate-into-home-assistant/62851) -- NixOS-specific integration discussion, URL guidance
- [nixpkgs PR #371866](https://github.com/NixOS/nixpkgs/pull/371866) -- Frigate component version history
- [MyNixOS: services.frigate.settings](https://mynixos.com/nixpkgs/option/services.frigate.settings) -- NixOS frigate module option type documentation

### Tertiary (LOW confidence)
- Zone placeholder coordinates in code examples -- Must be replaced with actual values from Frigate UI

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- All components verified in nixpkgs, versions confirmed, existing codebase already has 90% of infrastructure
- Architecture: HIGH -- Patterns verified against NixOS Wiki, official Frigate docs, and existing codebase conventions
- Pitfalls: HIGH -- All 8 pitfalls validated via official docs, NixOS Wiki, GitHub issues, and community reports
- Zone configuration: MEDIUM -- YAML schema verified but actual coordinates are camera-specific placeholders

**Research date:** 2026-02-09
**Valid until:** 2026-03-09 (stable domain, 30-day validity)
