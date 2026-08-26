# Milestones

## v1.2 Household Stack (Shipped: 2026-08-23)

**Phases:** 3 (numbered 09–11)
**Plans executed:** 18 of 23 (3 dropped in the 2026-08-20 descope, 2 gap-closure plans deferred)
**Tasks:** 52
**Timeline:** 2026-08-16 → 2026-08-22 (7 days)
**Git range:** `f6d6607` → `97549e4` (259 files changed, +52,947 / −4,713)
**Closeout:** override_closeout — known verification overrides: 17 acknowledged items (see STATE.md Deferred Items)

**Key accomplishments:**

- Fleet moved off EOL NixOS 25.11 to 26.05: ser8 and firebat activated, switched, and reboot-proven; both Raspberry Pis re-platformed from the `nvmd` fork onto upstream nixpkgs plus pinned `nixos-hardware`, with the fork, its bundled nixpkgs, and its trusted cachix key removed from the flake.
- Two-layer household service pattern established (`modules/household/` + `hosts/ser8/household/`) on an explicitly pinned PostgreSQL 17, with static system users, impermanence-safe persistence, and mutation-tested offline eval gates in `make check`.
- Mealie 3.22.0 in daily household use at `https://mealie.shad-bangus.ts.net` through a firebat Caddy tsnet vhost with a real Let's Encrypt certificate — both members in one household, default credentials dead, registration closed, Foods and Units seeded.
- Homebox 0.25.0, Actual Budget, and Donetick live on the same pattern, each with both members in one shared group/circle and self-signup closed.
- Donetick packaged entirely from source — the repository's first Go (`buildGoModule`) and npm (`buildNpmPackage`) packages, with the frontend traced to the exact commit upstream's release build used.
- A real ser8 reboot proved all three new apps' state bit-for-bit identical pre/post, with the household smoketest suite 8/8 post-reboot; the activation work also surfaced and fixed a 64-day-latent revoked Tailscale auth key that would have taken down the whole gateway on any Caddy restart.

### Known Gaps

- Phase 09 verification remains `gaps_found`: pi4/pi5 validated at evaluation level only (both boards offline), the workstation still trusts `nixos-raspberrypi.cachix.org` (needs `sudo make update-nix-conf`), and gap-closure plans 09-08/09-09 (always-pass smoketest fixes, human gates) were deferred, not executed.
- 15 requirements (backups, TLS/`.vofi`, Google Tasks import, access-control gate) descoped 2026-08-20 and parked as Deferred.
- Pre-existing fleet issues acknowledged at close: ser8 NordVPN tunnel down, sabnzbd uid drift, media UID/GID drift, Frigate go2rtc 403. Full list in STATE.md Deferred Items.

---

## v1.0: Frigate–Home Assistant Integration

**Completed:** 2026-02-10
**Phases:** 3 (numbered 01–03)
**Plans executed:** 6
**Total execution time:** ~107min

### What Shipped

**Phase 01 — MQTT Integration & Service Dependencies**

- Frigate entities auto-discovered in HA via MQTT
- Service ordering: HA wants Frigate, Frigate requires Mosquitto
- MQTT broker configured (localhost-only, no auth)

**Phase 02 — Push Notification Automations**

- Person/car/package detection → push notification with snapshot
- Stationary object filtering (5min threshold)
- mobile_app integration with Companion app
- Persistent HA notifications alongside mobile push

**Phase 03 — Camera Dashboard**

- Live camera feeds via advanced-camera-card (Lovelace)
- Detection event history with thumbnails
- Camera controls (enable/disable detection per camera)
- Dashboard deployed via tmpfiles symlink from Nix store

### Key Learnings

- HA 2025.5+: use `trigger.payload | from_json`, NOT `trigger.payload_json`
- Dashboard content as Nix attrset → JSON via `builtins.toJSON` (JSON is valid YAML)
- `restartTriggers` needed for HA YAML dashboard changes (read at startup only)
- Two config entries (MQTT broker, Frigate integration) require one-time HA UI setup
- `customLovelaceModules` auto-registration only works with `lovelace.mode = "yaml"`
- Storage mode requires declarative `.storage/lovelace_resources` via tmpfiles `C+`

### Validated Requirements

All 9 active requirements from v1.0 shipped and confirmed working.
