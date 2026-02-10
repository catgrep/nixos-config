# Domain Pitfalls

**Domain:** Frigate-Home Assistant Integration on NixOS with Impermanence
**Researched:** 2026-02-09

## Critical Pitfalls

Mistakes that cause rewrites or major issues.

### Pitfall 1: MQTT Integration Requires UI Config Flow, Not YAML

**What goes wrong:** You declare `mqtt:` in `services.home-assistant.config` expecting Frigate entities to appear. They never do. The MQTT integration in modern Home Assistant (2024+) must be configured through the UI config flow, not YAML. The `broker` key was removed from YAML configuration entirely. Declaring `mqtt:` in NixOS config generates a `configuration.yaml` entry that Home Assistant silently ignores for the actual integration setup.

**Why it happens:** Home Assistant has progressively migrated integrations from YAML to UI-based "config flows." MQTT is one of these. The NixOS `services.home-assistant.config` option maps to `configuration.yaml`, but MQTT broker connection settings are now stored in `.storage/core.config_entries` (a JSON file managed by the UI), not in `configuration.yaml`.

**Consequences:** Frigate publishes to MQTT, but Home Assistant never subscribes. No Frigate entities appear. No automations can fire. You chase phantom MQTT connectivity issues when the real problem is HA never connected to the broker at all.

**Prevention:**
1. Include `"mqtt"` in `extraComponents` (already done in current config -- good).
2. After first boot, configure MQTT through the HA web UI: Settings > Devices & Services > Add Integration > MQTT > enter `127.0.0.1:1883`.
3. This creates a config entry in `/var/lib/hass/.storage/core.config_entries` which persists across reboots via impermanence.
4. Accept this is a one-time manual step. Document it in a setup runbook.

**Detection:** After deployment, check `Settings > Devices & Services`. If MQTT does not appear as a configured integration (not just a component), it is not connected. Also check HA logs for `mqtt` -- absence of MQTT log lines means it was never set up.

**Phase:** Phase 1 (initial integration setup). This is the very first thing to get right.

**Confidence:** HIGH -- confirmed via [Home Assistant MQTT docs](https://www.home-assistant.io/integrations/mqtt), [NixOS Wiki](https://wiki.nixos.org/wiki/Home_Assistant), and [community reports](https://community.home-assistant.io/t/mqtt-integration-setup-in-configuration-yaml-does-not-work/480421).

---

### Pitfall 2: Frigate Integration Requires HACS Custom Component, Not Just MQTT Discovery

**What goes wrong:** You assume that because Frigate publishes to MQTT and HA has MQTT discovery, Frigate cameras/sensors will auto-appear as HA entities. They do not. Frigate's MQTT topics use Frigate's own topic structure (`frigate/<camera>/<object>`), not HA's MQTT discovery format (`homeassistant/<component>/<id>/config`). Without the dedicated `frigate-hass-integration` custom component, you get raw MQTT messages but no usable HA entities.

**Why it happens:** The project context says "Using MQTT auto-discovery (not HACS)" -- this is a misunderstanding of how Frigate-HA integration works. Frigate does not publish HA MQTT discovery messages. The Frigate HA integration (custom component) subscribes to Frigate's MQTT topics and creates HA entities from them.

**Consequences:** No camera entities, no binary sensors for person detection, no switches to toggle detection, no snapshot images. The entire integration is non-functional.

**Prevention:**
1. Install the Frigate custom component via NixOS declaratively:
   ```nix
   services.home-assistant.customComponents = [
     pkgs.home-assistant-custom-components.frigate
   ];
   ```
   This package exists in nixpkgs (confirmed via [nixpkgs PR #371866](https://github.com/NixOS/nixpkgs/pull/371866)).
2. After deployment, add the Frigate integration through the HA UI: Settings > Devices & Services > Add Integration > Frigate > enter `http://127.0.0.1:5000`.
3. The Frigate integration config is stored in `.storage/core.config_entries`, persisted via impermanence.

**Detection:** If you see MQTT messages flowing (check with `mosquitto_sub -t 'frigate/#'`) but no Frigate entities in HA, the custom component is missing or not configured.

**Phase:** Phase 1. This is a prerequisite for everything else.

**Confidence:** HIGH -- confirmed via [Frigate HA integration docs](https://docs.frigate.video/integrations/home-assistant/) and [nixpkgs](https://search.nixos.org/packages?channel=unstable&query=home-assistant-custom-components).

---

### Pitfall 3: Impermanence Wipes UI-Configured Integrations on Reboot

**What goes wrong:** After configuring MQTT and Frigate integrations through the HA UI, you reboot ser8. The ZFS root rollback (`zfs rollback -r rpool/local/root@blank`) wipes everything not in `/persist`. If `/var/lib/hass/.storage/` is not properly persisted, all UI-configured integrations, device registries, entity registries, auth tokens, and user accounts are destroyed.

**Why it happens:** HA stores all config-flow integration settings in `/var/lib/hass/.storage/core.config_entries`, user accounts in `/var/lib/hass/.storage/core.auth`, and device/entity registries in separate `.storage/` files. These are not in `configuration.yaml` and cannot be declared in NixOS config. If the bind mount from `/persist/var/lib/hass` to `/var/lib/hass` is not working correctly, or if the directory structure under `.storage/` is not being captured, you lose everything on each boot.

**Consequences:** Every reboot requires re-onboarding Home Assistant (creating user, configuring MQTT, adding Frigate integration). This makes the system completely unusable.

**Prevention:**
1. The current impermanence config already persists `/var/lib/hass` -- verify this is working by checking after a reboot that `/var/lib/hass/.storage/core.config_entries` still contains your integrations.
2. Ensure the impermanence bind mount is ready before `home-assistant.service` starts. Add explicit systemd ordering:
   ```nix
   systemd.services.home-assistant.after = [ "local-fs.target" ];
   ```
3. After first successful setup, verify persistence by rebooting and checking HA loads with all integrations intact.
4. Consider a backup mechanism: periodic copy of `.storage/` to a known-good location on ZFS.

**Detection:** After any reboot, if HA shows the onboarding screen instead of the login page, persistence failed. Check `ls -la /var/lib/hass/.storage/` -- if empty, the bind mount is not working.

**Phase:** Phase 1. Must be validated before any subsequent configuration.

**Confidence:** HIGH -- the current config does persist `/var/lib/hass`, but this must be explicitly tested. The impermanence setup is already in place per `hosts/ser8/impermanence.nix` line 75.

---

### Pitfall 4: Declarative Config Overwrites UI Changes on Every NixOS Rebuild

**What goes wrong:** You configure something in HA's web UI (e.g., add an automation, change logger level, modify recorder settings). On next `nixos-rebuild switch`, the NixOS module regenerates `configuration.yaml` from `services.home-assistant.config` and symlinks it into `/var/lib/hass/`. Your UI changes to `configuration.yaml`-managed settings are silently reverted.

**Why it happens:** Unless `configWritable` is set to `true`, the NixOS module creates a read-only symlink from `/var/lib/hass/configuration.yaml` to the Nix-generated config in `/etc/home-assistant/configuration.yaml`. Even if writable, the file is regenerated and overwritten on each activation.

**Consequences:** Confusion about why settings keep reverting. Risk of losing automation work if automations are defined in the wrong place.

**Prevention:**
1. Establish a clear boundary: NixOS config owns `configuration.yaml` (http, recorder, logger, homeassistant core settings). The HA UI owns everything in `.storage/` (integrations, device config, dashboards).
2. For automations, use the split pattern:
   ```nix
   services.home-assistant.config = {
     "automation manual" = []; # Nix-managed automations go here
     "automation ui" = "!include automations.yaml";
   };
   ```
3. Create the empty `automations.yaml` to prevent HA from crashing on first boot:
   ```nix
   systemd.tmpfiles.rules = [
     "f /var/lib/hass/automations.yaml 0644 hass hass"
   ];
   ```
4. Never edit `configuration.yaml` through the HA UI. Use NixOS for that layer.

**Detection:** After `nixos-rebuild switch`, check if any UI-configured yaml settings reverted. If automations defined via UI disappear, you likely put them in the wrong config section.

**Phase:** Phase 1 (config structure) and Phase 2 (automations).

**Confidence:** HIGH -- documented on [NixOS Wiki](https://wiki.nixos.org/wiki/Home_Assistant) and confirmed by reading the [NixOS HA module source](https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/services/home-automation/home-assistant.nix).

---

## Moderate Pitfalls

### Pitfall 5: Service Startup Race Between Mosquitto, Frigate, and Home Assistant

**What goes wrong:** After a reboot, Frigate starts before Mosquitto is fully accepting connections. Frigate fails to connect to MQTT and enters an error state. Alternatively, Home Assistant starts before Frigate has published its initial state to MQTT, causing entities to show as "unavailable" until the next state change.

**Why it happens:** The current `frigate.nix` defines `after = [ "zfs-mount.service" "network-online.target" "sops-nix.service" ]` but does not declare a dependency on `mosquitto.service`. Systemd does not guarantee startup order without explicit dependencies.

**Prevention:**
1. Add Mosquitto as a dependency for Frigate:
   ```nix
   systemd.services.frigate = {
     after = [ "mosquitto.service" /* ...existing deps... */ ];
     requires = [ "mosquitto.service" /* ...existing deps... */ ];
   };
   ```
2. Add Mosquitto as a dependency for Home Assistant:
   ```nix
   systemd.services.home-assistant = {
     after = [ "mosquitto.service" ];
     wants = [ "mosquitto.service" ];
   };
   ```
3. Add Frigate as a soft dependency for Home Assistant (so HA loads Frigate entities on startup):
   ```nix
   systemd.services.home-assistant = {
     after = [ "frigate.service" ];
     wants = [ "frigate.service" ];
   };
   ```

**Detection:** After reboot, check `systemctl status frigate` and `systemctl status home-assistant`. Look for MQTT connection errors in Frigate logs (`journalctl -u frigate | grep -i mqtt`). Check HA for "unavailable" Frigate entities.

**Phase:** Phase 1 (service wiring).

**Confidence:** HIGH -- this is a standard systemd ordering concern. The current config is missing Mosquitto ordering.

---

### Pitfall 6: Frigate URL Misconfiguration in HA Integration

**What goes wrong:** Camera entities appear in HA but show blank/black when viewed. Live streams fail to load. Snapshots work (via MQTT) but live video does not.

**Why it happens:** The Frigate HA integration needs two separate network paths: (1) the Frigate API URL (port 5000) for entity management and snapshots, and (2) direct RTSP access (port 8554) for live camera streams. If the Frigate URL is misconfigured (wrong port, using hostname instead of IP, pointing at proxy instead of direct), API calls work but streams fail. Additionally, since Frigate on NixOS uses nginx on port 80 internally, the integration URL should point to `http://127.0.0.1:5000` (the direct API port), not port 80 (the nginx frontend).

**Consequences:** Cameras appear as entities but are unusable for live viewing. Dashboard cards show thumbnails from snapshots but blank live views.

**Prevention:**
1. When adding Frigate integration in HA UI, use `http://127.0.0.1:5000` as the URL.
2. Ensure port 8554 (RTSP) is accessible. The current config already opens this port.
3. For the Frigate card (lovelace), ensure WebRTC candidates are configured (already done in current config: `192.168.68.65:8555`).
4. Do NOT point the integration at port 80 (nginx) or at the Caddy reverse proxy URL.

**Detection:** Camera entities exist but show blank in dashboard. Check browser network tab for failed requests to port 8554. Test RTSP directly: `ffplay rtsp://192.168.68.65:8554/driveway`.

**Phase:** Phase 1 (integration setup).

**Confidence:** HIGH -- confirmed via [Frigate HA integration docs](https://docs.frigate.video/integrations/home-assistant/) and multiple [community reports](https://community.home-assistant.io/t/frigate-mqtt-not-playing-nicely-together/688973).

---

### Pitfall 7: Notification Snapshots Require External URL and Unauthenticated Proxy

**What goes wrong:** Push notifications fire on your phone via the Companion App, but the snapshot image is missing or shows a broken image icon. The notification text works, but there is no visual of what triggered the alert.

**Why it happens:** Frigate notification snapshots are served through the HA Frigate integration's API proxy (`/api/frigate/notifications/<event_id>/thumbnail.jpg`). When your phone is on cellular (not local network), it needs to reach HA externally. Additionally, the Frigate integration has an "unauthenticated notification event proxy" option that must be explicitly enabled for snapshot images to work in push notifications (because the Companion App fetches the image without an auth header in the notification context).

**Consequences:** Notifications are text-only. You know "person detected on driveway" but cannot see the image, defeating the purpose of a visual security system.

**Prevention:**
1. Configure HA's external URL in the UI (Settings > System > Network). Use the Tailscale URL: `https://hass.shad-bangus.ts.net`.
2. In Frigate integration settings (requires Advanced Mode in user profile), enable "Unauthenticated notification event proxy."
3. Ensure the Companion App is configured with both internal URL (`http://192.168.68.65:8123`) and external URL (`https://hass.shad-bangus.ts.net`).
4. Install Tailscale on the mobile device for reliable external access.

**Detection:** Trigger a test detection event. If the notification arrives but the image is broken, check the image URL in the notification. If it points to `http://homeassistant.local:8123/...`, the external URL is not configured.

**Phase:** Phase 3 (notifications).

**Confidence:** MEDIUM -- confirmed via [Frigate notification guide](https://docs.frigate.video/guides/ha_notifications/) and [HA integration docs](https://docs.frigate.video/integrations/home-assistant/). Exact behavior with Tailscale-only setup needs validation.

---

### Pitfall 8: Stale MQTT Retained Messages After Camera Rename or Removal

**What goes wrong:** You rename a camera in Frigate config (e.g., `front_door` to `front_entrance`) or remove one. After restarting Frigate, the old camera's entities persist in Home Assistant as "unavailable" ghosts. Worse, if the old topic had retained messages, MQTT keeps delivering stale data.

**Why it happens:** Frigate publishes some messages with the MQTT retain flag. When a camera name changes, the old retained messages on `frigate/<old_camera_name>/#` topics remain in the Mosquitto broker. Home Assistant's MQTT integration sees these retained messages and keeps the old entities alive. Frigate does not clean up retained messages for removed/renamed cameras.

**Consequences:** Ghost entities clutter the HA interface. Automations referencing old entity IDs silently break. If you have automations triggering on `binary_sensor.front_door_person_occupancy`, renaming to `front_entrance` breaks all of them with no warning.

**Prevention:**
1. Before renaming cameras, manually clear retained messages:
   ```bash
   mosquitto_pub -h 127.0.0.1 -t 'frigate/front_door/detect/state' -n -r
   mosquitto_pub -h 127.0.0.1 -t 'frigate/front_door/recordings/state' -n -r
   # Repeat for all subtopics
   ```
2. After renaming, restart Mosquitto to flush all retained messages:
   ```bash
   systemctl restart mosquitto
   ```
3. In HA, manually delete orphaned entities: Settings > Devices & Services > Entities > filter "unavailable" > delete.
4. Plan camera names carefully upfront. The current config uses sensible names (`driveway`, `front_door`, `garage`, `side_gate`).

**Detection:** After any Frigate config change, check HA for "unavailable" entities from Frigate. Check `mosquitto_sub -t 'frigate/#' -v` for messages from cameras that no longer exist.

**Phase:** Ongoing operational concern. Document in runbook.

**Confidence:** HIGH -- confirmed via [Frigate GitHub issue #5295](https://github.com/blakeblackshear/frigate/issues/5295) and [community reports](https://community.home-assistant.io/t/overview-entities-unavailable-from-frigate/661939).

---

### Pitfall 9: Automation Blueprint Import Requires Manual UI Steps

**What goes wrong:** You plan to use the popular "Frigate Mobile App Notifications" blueprint by SgtBatten for push notifications. You expect to declare it in NixOS config. Blueprints cannot be declared in NixOS -- they must be imported through the HA UI and are stored in `/var/lib/hass/blueprints/`.

**Why it happens:** Blueprints are a Home Assistant feature stored as YAML files under the HA config directory, but they are managed through the UI import flow (entering a URL). The NixOS module does not have a mechanism to declaratively install blueprints.

**Consequences:** Either you manually import the blueprint (breaking the "everything in Nix" goal) or you write the notification automation from scratch in Nix (more work, harder to maintain as the community blueprint evolves).

**Prevention:**
1. Accept the manual import step. Import the blueprint URL via HA UI: `https://community.home-assistant.io/t/frigate-mobile-app-notifications-2-0/559732`.
2. The blueprint files land in `/var/lib/hass/blueprints/automation/` which is persisted via impermanence (`/var/lib/hass` is persisted).
3. Alternatively, use `systemd.tmpfiles.rules` to place the blueprint YAML file directly:
   ```nix
   systemd.tmpfiles.rules = [
     "d /var/lib/hass/blueprints/automation/SgtBatten 0755 hass hass -"
   ];
   ```
   Then fetch and place the YAML file via a systemd service or derivation.
4. Automations instantiated from blueprints are stored in `automations.yaml`, which should be included via `"automation ui" = "!include automations.yaml"`.

**Detection:** If the blueprint is not visible under Settings > Automations > Blueprints, it was not persisted or not imported.

**Phase:** Phase 2 (automations) or Phase 3 (notifications).

**Confidence:** MEDIUM -- blueprint persistence in `/var/lib/hass/` is logical based on HA architecture, but needs validation that impermanence correctly persists the `blueprints/` subdirectory.

---

## Minor Pitfalls

### Pitfall 10: Missing Empty automations.yaml Causes HA Boot Failure

**What goes wrong:** If `"automation ui" = "!include automations.yaml"` is in the NixOS config but `/var/lib/hass/automations.yaml` does not exist (e.g., fresh install, impermanence wipe of a file not explicitly created), Home Assistant fails to start entirely.

**Prevention:**
```nix
systemd.tmpfiles.rules = [
  "f /var/lib/hass/automations.yaml 0644 hass hass"
];
```
This creates an empty file if it does not exist, which HA parses as an empty list.

**Phase:** Phase 1 (initial config).

**Confidence:** HIGH -- [NixOS Wiki](https://wiki.nixos.org/wiki/Home_Assistant) explicitly documents this.

---

### Pitfall 11: Frigate Integration Version Must Match Frigate Server Version

**What goes wrong:** The `home-assistant-custom-components.frigate` package in nixpkgs may not match the Frigate server version (0.15.2). Version mismatches between the HA integration and the Frigate server can cause entity creation failures, missing features, or API errors.

**Prevention:**
1. Check the nixpkgs version of `home-assistant-custom-components.frigate` against the [Frigate HA integration releases](https://github.com/blakeblackshear/frigate-hass-integration/releases) to confirm compatibility with Frigate 0.15.2.
2. If the nixpkgs version is too new (targeting Frigate 0.16+), pin the package to a compatible version using an overlay or fetchFromGitHub.
3. The Frigate 0.16 database is not backward-compatible with 0.15, so avoid upgrading the server without checking integration compatibility.

**Detection:** After setup, check HA logs for Frigate integration errors. Version mismatches typically produce clear error messages.

**Phase:** Phase 1 (package selection).

**Confidence:** MEDIUM -- version compatibility is a general concern. The specific nixpkgs version needs to be checked at build time.

---

### Pitfall 12: Mosquitto Binding to 127.0.0.1 Blocks Frigate on Different Network Namespace

**What goes wrong:** The current Mosquitto config binds to `127.0.0.1:1883`. This works when Frigate runs in the host network namespace. But if Frigate were ever moved to a container or network namespace (like qBittorrent uses NordVPN namespace), it cannot reach `127.0.0.1` of the host.

**Prevention:**
1. For the current setup (Frigate on host network), `127.0.0.1` is correct and more secure. No change needed.
2. If Frigate is ever containerized or namespaced, change Mosquitto to bind to `0.0.0.0` or the specific bridge IP, and add ACLs or authentication.
3. Note: the Frigate config uses `host = "localhost"` which resolves to `127.0.0.1`. This is fine for same-host deployment.

**Phase:** Not currently applicable. Note for future architecture changes.

**Confidence:** HIGH -- straightforward networking fact.

---

### Pitfall 13: Home Assistant Companion App Registration Requires Specific Network Path

**What goes wrong:** You install the Companion App on your phone but it cannot find or register with Home Assistant. Or it registers but push notifications never arrive.

**Prevention:**
1. For initial registration, the phone must be on the same network as HA, or connected via Tailscale. Use the Tailscale URL `https://hass.shad-bangus.ts.net` for registration.
2. Push notifications use Firebase Cloud Messaging (Android) or APNs (iOS) -- they do not require direct network access to HA. But the notification payload includes URLs for snapshots that do require access.
3. Ensure `mobile_app` is in `extraComponents` (already present in current config).
4. After registration, the device appears in `.storage/core.config_entries` and `.storage/core.device_registry`. These persist via impermanence.

**Detection:** Check Settings > Companion App in the mobile app. Check Settings > Devices & Services in HA for the mobile_app integration. If the device is not listed, registration failed.

**Phase:** Phase 3 (notifications).

**Confidence:** MEDIUM -- general HA Companion App knowledge. Specific Tailscale interaction needs validation.

---

## Phase-Specific Warnings

| Phase Topic | Likely Pitfall | Mitigation |
|-------------|---------------|------------|
| Phase 1: Service Wiring | Mosquitto/Frigate/HA start order race | Add explicit systemd `after`/`requires` dependencies |
| Phase 1: Integration Setup | MQTT requires UI config flow | Accept one-time manual UI step, document in runbook |
| Phase 1: Integration Setup | Frigate needs custom component, not just MQTT | Use `customComponents` with nixpkgs package |
| Phase 1: Config Structure | Declarative vs UI boundary confusion | Establish clear ownership: Nix owns yaml, UI owns .storage |
| Phase 1: Impermanence | UI config lost on reboot | Verify `/var/lib/hass/.storage/` survives reboot before proceeding |
| Phase 2: Automations | Missing `automations.yaml` crashes HA | Create empty file via tmpfiles rule |
| Phase 2: Automations | Blueprint import is manual | Import via UI, ensure `/var/lib/hass/blueprints/` persists |
| Phase 3: Notifications | Snapshots require external URL + proxy | Configure Tailscale URL + enable unauthenticated proxy |
| Phase 3: Notifications | Companion App registration path | Register via Tailscale URL, verify device appears in HA |
| Ongoing: Maintenance | Camera rename leaves ghost entities | Clear retained MQTT messages before renaming |
| Ongoing: Upgrades | Frigate/integration version mismatch | Check compatibility before nixpkgs updates |

## Sources

- [Frigate Home Assistant Integration Docs](https://docs.frigate.video/integrations/home-assistant/) - HIGH confidence
- [Frigate MQTT Docs](https://docs.frigate.video/integrations/mqtt/) - HIGH confidence
- [Frigate Notification Guide](https://docs.frigate.video/guides/ha_notifications/) - HIGH confidence
- [Home Assistant MQTT Integration](https://www.home-assistant.io/integrations/mqtt) - HIGH confidence
- [NixOS Wiki: Home Assistant](https://wiki.nixos.org/wiki/Home_Assistant) - HIGH confidence
- [NixOS HA Module Source](https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/services/home-automation/home-assistant.nix) - HIGH confidence
- [nixpkgs frigate custom component PR](https://github.com/NixOS/nixpkgs/pull/371866) - HIGH confidence
- [Frigate MQTT retain issue #5295](https://github.com/blakeblackshear/frigate/issues/5295) - HIGH confidence
- [NixOS Discourse: Frigate into HA](https://discourse.nixos.org/t/frigate-into-home-assistant/62851) - MEDIUM confidence
- [HA Community: MQTT not working via YAML](https://community.home-assistant.io/t/mqtt-integration-setup-in-configuration-yaml-does-not-work/480421) - MEDIUM confidence
- [HA Community: Frigate MQTT issues](https://community.home-assistant.io/t/frigate-mqtt-not-playing-nicely-together/688973) - MEDIUM confidence
- [Frigate Mobile App Notifications Blueprint](https://community.home-assistant.io/t/frigate-mobile-app-notifications-2-0/559732) - MEDIUM confidence
