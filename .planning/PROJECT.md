# NixOS Homelab Infrastructure

## What This Is

A declarative NixOS homelab managing multiple hosts (ser8, firebat, pi4, pi5) with media services, security cameras, home automation, DNS, reverse proxy, monitoring, and self-hosted household apps (Mealie, Homebox, Actual Budget, Donetick). All configuration is version-controlled Nix with SOPS secrets, Tailscale networking, and ZFS storage.

## Core Value

The homelab runs reliably without manual intervention — when something needs attention, I know about it before it becomes a problem.

## Current State

**Phase 13 (ZFS Mirror Migration) complete (2026-08-25).**
ser8 media storage runs on a two-disk ZFS mirror (`media` pool, both approved 12 TB WWNs, first scrub clean with 0 errors); MergerFS is fully retired; the media tree was migrated with independently verified zero data loss (3,478 files byte-identical across staging, restore, and scrub); downloads relocated to `rpool/safe/downloads` on NVMe with a 500G quota.
Requirements ZFS-01 through ZFS-05 validated.
Next: Phase 14 (Backup Engine).

**Shipped: v1.2 Household Stack (2026-08-23).**
The whole fleet runs NixOS 26.05 (both x86 hosts activated and switched; both Pis re-platformed from the `nvmd` fork onto upstream nixpkgs + pinned `nixos-hardware`, evaluation-level only).
All four household services (Mealie, Homebox, Actual Budget, Donetick) run on ser8 behind the firebat Caddy tsnet pattern at `<name>.shad-bangus.ts.net`, each with both household members bootstrapped, self-signup closed, and persistence proven across a real ser8 reboot.
Donetick is packaged locally from source — the repository's first Go and first npm packages.

The 2026-08-20 descope deferred backups, `.vofi`/TLS migration, the Google Tasks import, and the access-control acceptance gate to a later milestone.
The v1.2 close acknowledged ~15 open issues as deferred (see STATE.md Deferred Items): NordVPN tunnel down on ser8, sabnzbd uid drift, six dishonest smoketests, Frigate go2rtc 403, and the workstation's lingering cachix trust, among others.

**v1.3 Phase 12 complete (2026-08-23):** Fleet Repair — NordVPN + qBittorrent stack removed from code and live ser8 state (archive-then-delete, usenet-only download path), sabnzbd uid pinned at 985 with the 38:194 drift repaired, media identity verified already-correct at 1100/1100 (planned 1002/992 adoption abandoned; D-07/D-08 corrected), Radarr cleaned to the single canonical `/mnt/media/movies` root with a zero-loss snapshot diff.

**Design constraints that shipped (firm, from proposal):**
- No integration layer or sync between the four services
- No inventory/pantry consumption tracking (Grocy rejected)
- Single shopping list (Mealie's)
- Tailscale/LAN-internal only; nothing exposed publicly
- Home Assistant integration deferred to a later milestone

## Current Milestone: v1.3 ZFS Mirror + Nixflix Migration

**Goal:** Rebuild ser8's media foundation in one milestone — storage first (MergerFS → two-disk ZFS mirror, paranoid and human-gated), then the full Nixflix migration through Recyclarr, Seerr, and Maintainerr, plus a nightly backup engine.

**Target features, in sequence:**
- Prereq fleet repairs: wgnord/qBittorrent restart loop (NordVPN tunnel), sabnzbd uid-drift repair, media UID/GID reconciliation (repo 1100 vs live 1002/992), Radarr root-folder drift cleanup
- ZFS mirror migration (paranoid, human-in-the-loop): stage ~7.8 TB to the backup pool, freeze, erase the two approved 12 TB WWNs, create single-dataset `media/data`, restore, checksum-verify, scrub — prior research in `.planning/SER8-ZFS-MIRROR-MIGRATION.md`
- Backup engine (BKP-01..06 unparked): nightly pg_dump + SQLite `.backup` to the ZFS backup pool for household apps and media app state, with demonstrated restores; doubles as the pre-cutover snapshot + tested rollback
- Nixflix foundation: pinned flake input, `hosts/ser8/media/nixflix.nix` adapter forcing live identities and existing state paths, written against the final ZFS topology — prior research in `.planning/SER8-NIXFLIX-MIGRATION.md`
- Cutover (careful): export full API inventory, declare all root folders/download clients/Prowlarr objects, enable reconciliation for Sonarr/Radarr/Prowlarr, remove local orchestration units; then Jellyfin with a dedicated SOPS API key and preserved database/users
- New services (simple standups, separate paths): Recyclarr (no unmanaged-profile deletion), Seerr (full gateway/monitoring/smoketest coverage), Maintainerr (observation mode, zero deletions)

**Key constraints:**
- Storage-first so Nixflix declarations target the final topology and hardlink validation can actually pass
- Mirror halves usable media capacity to ~12 TB (currently ~7.8 TB used, ~65%)
- Preserved as-is: firebat gateway topology, Bazarr, NZBGet, SQLite databases (qBittorrent + NordVPN were retired outright in Phase 12 per D-01/D-02, superseding the original repair-in-place constraint)
- Out of scope: anime Sonarr instance, Lidarr, PostgreSQL migration, Nixflix-managed VPN, Maintainerr deletion rules

## Requirements

### Validated

<!-- Shipped and confirmed valuable. -->

- ✓ Frigate NVR running with 3 active cameras (driveway, front_door, garage) — v1.0
- ✓ Object detection enabled for person, car, dog, cat, package — v1.0
- ✓ Mosquitto MQTT broker running on localhost:1883 — v1.0
- ✓ Frigate MQTT publishing enabled — v1.0
- ✓ Home Assistant running with MQTT and mobile_app components — v1.0
- ✓ Snapshots and 30-day event recording in Frigate — v1.0
- ✓ Camera recordings on ZFS backup pool (/mnt/cameras) — v1.0
- ✓ Frigate and HA accessible via Caddy reverse proxy and Tailscale — v1.0
- ✓ Prometheus monitoring for Frigate metrics — v1.0
- ✓ Frigate entities auto-discovered in HA via MQTT — v1.0
- ✓ HA push notifications with snapshot on person/car/package detection — v1.0
- ✓ HA dashboard with live camera feeds, detection events, event history — v1.0
- ✓ Camera controls in HA (enable/disable detection per camera) — v1.0
- ✓ All HA automations and dashboard config declared in Nix — v1.0
- ✓ Grafana unified alerting enabled with Gmail SMTP contact point — v1.1 Phase 4
- ✓ Prometheus blackbox exporter probing all services with service-down alerts — v1.1 Phase 4
- ✓ Mealie deployed on ser8 with PostgreSQL and household multi-user setup — v1.2 Phase 10
- ✓ Donetick deployed on ser8 with persisted SQLite state, packaged locally from source (Go + npm frontend) — v1.2 Phase 11
- ✓ Homebox deployed on ser8 with registration disabled after initial accounts — v1.2 Phase 11
- ✓ Actual Budget deployed on ser8 with server password set and one unencrypted budget file — v1.2 Phase 11
- ✓ All four household apps reachable at `<name>.shad-bangus.ts.net` through the firebat Caddy tsnet pattern, both members bootstrapped, self-signup closed, state reboot-proven — v1.2 Phase 11
- ✓ Prereq fleet repairs: NordVPN/qBittorrent stack retired (usenet-only path), sabnzbd uid drift fixed, media identity verified/reconciled, Radarr root-folder cleanup with zero media loss — v1.3 Phase 12
- ✓ ser8 media storage migrated from MergerFS/ext4 to a two-disk ZFS mirror (single dataset, zero data loss, first scrub clean, downloads on NVMe with 500G quota) — v1.3 Phase 13

### Active

<!-- Current scope. Building toward these. -->

Milestone v1.3 scope (REQ-IDs defined in REQUIREMENTS.md):

- Nightly backup engine to the ZFS backup pool with demonstrated restores (BKP-01..06 unparked from v1.2)
- Nixflix adopted as the declarative orchestration layer: pinned input, ser8 adapter, arr/Prowlarr/Jellyfin cutover with full data retention
- Recyclarr, Seerr, and Maintainerr (observation mode) stood up on the migrated stack

### Deferred (v1.2 descope, 2026-08-20)

- One-time Google Tasks import into Donetick (one-off todos + recurring chores)
- `.vofi` → `vofi.dev` migration with real TLS (tsnet pattern serves the household apps in the meantime)
- Negative access smoketest proving no service is reachable from outside Tailscale/LAN
- Secrets audit: all secrets via sops-nix, nothing secret in the Nix store
- Formal two-consecutive-reboot persistence drill (one real reboot proven in Phase 11)

### Deferred (v1.1 shelved with phases 5-7 incomplete)

- Hardware alert rules: ZFS degraded, disk space low, high CPU/memory/temp
- Loki + Promtail log aggregation, searchable history, log-based alerting
- Uptime dashboard showing service availability history
- HA monitoring dashboards and infrastructure-alert automations
- ser8 media.nix reorganization phase 08 verification gaps (2 must-have gaps, recorded in archive)

### Out of Scope

- Indoor cameras (living_room, basement) — currently disabled in Frigate
- side_gate camera — currently disabled in Frigate
- Custom detection zones per camera — can be added later via Frigate config
- Two-way audio — not supported by current camera models
- Tracing / APM — overkill for homelab, metrics + logs sufficient
- External uptime monitoring (e.g., UptimeRobot) — all internal, Tailscale-only access
- PagerDuty / OpsGenie integration — email alerts sufficient for homelab
- Grocy or any pantry/consumption inventory tracking — evaluated and rejected; drifts and gets abandoned
- Sync or glue between Mealie, Donetick, Homebox, Actual — standalone by design
- Second shopping list app — Mealie's list is the only one
- Barcode scanning, expiry tracking, stock levels, recipe-to-inventory decrement, meal-plan-to-calendar sync
- HA Mealie/Donetick integration — deferred to a later milestone
- SimpleFIN bank sync provisioned in Nix — configured in-app only

## Context

- Household services target ser8: it hosts all app services, has ZFS + the backup pool, and Caddy already proxies `ser8.local:<port>`
- Caddy (firebat) serves household apps as Tailscale tsnet nodes at `<name>.shad-bangus.ts.net` with Let's Encrypt certs; legacy `<service>.vofi` vhosts used a local CA with AdGuard DNS on pi4, which is now disconnected
- The shared `tailscale_authkey` must be reusable and non-ephemeral; a dead key takes the whole gateway down when Caddy restarts (proven by the 64-day-latent 2026-08-18 outage)
- Deployment is via `deploy.yaml` + Makefile targets (not Colmena, despite older proposal docs)
- ser8 runs Frigate 0.17.2, Home Assistant, Mosquitto, the media stack, PostgreSQL 17 (pinned), and the four household apps on the same host
- firebat runs Caddy reverse proxy, Grafana, and Prometheus
- Prometheus already scrapes node-exporter (ser8, firebat, pi4), zfs-exporter (ser8), and Prometheus self
- Grafana has provisioned dashboards (Node Exporter Full, ZFS, Prometheus Stats)
- Grafana admin password already in SOPS (`grafana_admin_password`)
- HA uses declarative config via NixOS `services.home-assistant.config`
- HA Companion app push notifications working (v1.0 milestone)
- MQTT broker on localhost:1883, no auth (local-only, behind Tailscale)
- Loki + Promtail are available in nixpkgs
- Prometheus blackbox exporter available in nixpkgs

## Constraints

- **Declarative**: All config must be in NixOS Nix files, not UI-only configuration
- **Impermanence**: ser8 uses ZFS root rollback — persistent state must be in impermanence rules
- **Local MQTT**: Broker is localhost-only, no network exposure
- **No HACS**: Use MQTT auto-discovery for HA integrations, not HACS
- **Monitoring on firebat**: Prometheus and Grafana run on firebat, not ser8
- **SMTP credentials in SOPS**: Gmail app password must not be in plaintext

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| MQTT auto-discovery over HACS integration | HACS requires non-declarative HA UI setup; MQTT auto-discovery works with declarative NixOS config | ✓ Good |
| Push notifications via HA Companion app | Already have mobile_app component loaded; Companion app is the standard HA mobile notification path | ✓ Good |
| All automations in Nix | Matches repo pattern of declarative, version-controlled infrastructure | ✓ Good |
| Grafana alerting + HA automations (dual path) | Grafana for metric-based alerts, HA for integration-level alerts — each system alerts on what it knows best | — Pending |
| Gmail SMTP for Grafana email alerts | User has Gmail/Google Workspace; app password approach is well-documented | — Pending |
| Loki + Promtail for log aggregation | Standard Grafana ecosystem stack, available in nixpkgs, integrates with existing Grafana | — Pending |
| [Phase 09, FOUND-02] Both Raspberry Pis build from upstream nixpkgs 26.05 + `nixos-hardware` pinned at `ff17823245ab9ff7bcae6acf950bd89cba82c38c` (2026-08-16), replacing the `nvmd/nixos-raspberrypi` fork | The fork's engineering (config.txt rendering, firmware staging, DTB pruning) was upstreamed into `nixos-hardware` with attribution, so this is a rename rather than a reimplementation; pinned rather than tracking master because `raspberry-pi/common/` is under active development and a flake update must not silently change how the boards start | ✓ Both hosts evaluate on the new inputs; fork input, its bundled nixpkgs, and its trusted cachix key are gone from `flake.lock` |
| [Phase 09, FOUND-02] Mainline kernel (`boot.kernelPackages = pkgs.linuxPackages`) forced on both Pis over `nixos-hardware`'s `mkDefault` vendor kernel | The vendor `linux-rpi` kernel has no Hydra binary-cache build and would compile from source on every bump; neither host needs board-specific peripherals (pi4 is a network utility box, pi5 is general purpose) | ✓ Gated permanently by `scripts/validation/test-pi-bootloader.sh` in `make check` |
| [Phase 09, FOUND-02] pi4 is disconnected and pending retirement or repurposing | Its AdGuard DNS box has been physically unplugged; this is why its DNS smoketests and its Caddy route were deleted in 09-06 rather than repaired | ✓ Recorded; `.vofi` DNS ownership is now an open Phase 10 question (below) |
| [Phase 09, FOUND-02] Pi evidence is evaluation-level only, recorded separately per host | D-13 sets a different bar per board and a single combined claim would be wrong for one of them; see the evidence subsection below for the exact commands | ✓ Neither Pi was switched, activated, or powered on in this phase |
| [Phase 09] Pi 5 bootstrap image and physical reflash deferred to a later phase | D-04 chose reflash-from-image over in-place bootloader migration, and stable 26.05's `sd-image-aarch64.nix` still lacks Pi 5 boot files | — Deferred; intended technical path recorded below so it is not re-researched |
| [Phase 09] `.vofi` DNS ownership is unresolved and must be answered in Phase 10 | pi4 served `.vofi` names via AdGuard Home and is retiring; no household service is reachable by name until a new owner exists | — Open; `SKIP_VOFI_DNS` defaults to `1` and holds the smoketests in the meantime |
| [v1.2, 2026-08-20] Descope backups, `.vofi` TLS, the Google Tasks import, and the access-control gate; ship the four apps first | Apps in daily use deliver value now; ceremony can follow in its own milestone | ✓ All four apps shipped 2026-08-22; deferred requirements parked with IDs intact |
| [Phase 10] Household apps exposed as firebat Caddy tsnet nodes at `<name>.shad-bangus.ts.net`, superseding the `.vofi`+AdGuard pattern | pi4 (the AdGuard `.vofi` resolver) is disconnected; tsnet gives per-app hostnames with real Let's Encrypt certs and no DNS server to own | ✓ Good — four apps live on the pattern; `.vofi` migration parked as a todo |
| [Phase 10] Mealie runs as a static system user with DynamicUser forced off; PostgreSQL pinned to `postgresql_17` by plain assignment | State must land at a real persisted path a backup job can address; stateVersion 24.11 would have silently selected major 16 | ✓ Good — pattern reused by all household services |
| [Phase 10] Household smoketests assert both state stores (DB rows AND persisted file tree) and unit state before ports | A row-count-only or HTTP-only check stays green while data is broken — proven by the media area's blind SABnzbd pass | ✓ Good — household suite 8/8 post-reboot |
| [Phase 11] Donetick packaged from source: `buildGoModule` backend + `buildNpmPackage` frontend from the separate `donetick/frontend` repo, pinned to the release build's exact commit | No usable upstream package; the backend repo's committed `frontend/dist` is an 88-byte placeholder | ✓ Good — repo's first Go and npm packages, full upstream test suite runs in checkPhase |
| [Phase 11] `sops.templates.<name>.restartUnits` set explicitly for any template whose content can change post-deploy | sops-install-secrets only restarts units named at diff time; otherwise a running process keeps stale env vars (found live: signup stayed open after the flag flipped) | ✓ Good — fixed live in 11-05 |
| [Phase 11] `StateDirectoryMode` forced to 0750 for every household service from the start | systemd's real default is 0755, not 0750; applied proactively after the Homebox lesson | ✓ Good |
| [v1.2 close, 2026-08-23] Override closeout: ~15 open issues acknowledged as deferred rather than fixed pre-close | All are pre-existing conditions or own-plan-sized work; none block the shipped household stack | — Pending; recorded in STATE.md Deferred Items |
| [Phase 12, D-07/D-08 corrected] FLEET-03 media identity: no `modules/common/users.nix` change made. Live ser8 verification found `media` is already uid 1100 / gid 1100 — matching the repo's existing declaration exactly. The originally planned adoption of uid 1002 / gid 992 is abandoned: gid 992 belongs to the live `mealie` service group, and uid 1002 is not a live account, so that identity was never ser8's real media identity. The identity census (D-10) extended to jellyfin/sonarr/radarr/bazarr/sabnzbd/nzbget found zero drift; all six share primary group `media` (1100) as declared. A separate, small ownership audit (D-09) found and individually chowned 18 stray files (uid 1002/755, mostly orphaned Samba-client or copy-tool ownership) to `media:media`; one large finding (1,443 files / ~3.27 TiB owned by non-existent uid 38, correlated with FLEET-02's sabnzbd 38:194 state drift) was deliberately left unfixed as out of this plan's targeted-audit scope | ✓ Corrected — see `.planning/phases/12-fleet-repair/evidence/identity-audit.md` and `evidence/ownership-audit.md` (plan 12-01) |
| [Phase 12, D-01/D-02/D-03/D-06] FLEET-01 retired: torrents are retired, the download path is usenet-only (SABnzbd/NZBGet). The NordVPN + qBittorrent stack (modules, host wiring, secrets, live state) is removed entirely from both code and ser8's running system via archive-then-delete, not disabled or shimmed. Live `/var/lib/qbittorrent` and `/var/lib/wgnord` were archived to `/mnt/backups/phase12-fleet-repair-archive/` on ser8's backup pool before deletion; the three orphaned SOPS secrets (`nordvpn_access_token`, `qbittorrent_admin_password`, `qbittorrent_admin_password_hash`) were removed from `secrets/ser8.yaml` | ✓ Good — `qbittorrent-nox.service`/`wgnord.service` confirmed absent on ser8, archive verified non-empty and spot-checked before deletion (plan 12-04) |

### Phase 09 Raspberry Pi evidence (FOUND-02)

Evidence is recorded per host because D-13 sets a different bar for each.
Both bars are local evaluation, and neither board was powered on or activated at any point in Phase 09.
The repository's `dry-activate` is a remote operation over SSH, so it cannot be performed against a board that does not answer.

**pi4** (disconnected, pending retirement or repurposing):

- `nix build --dry-run '.#nixosConfigurations.pi4.config.system.build.toplevel'` exits 0, planning 169 derivations and 1027 fetched paths.
- `./scripts/validation/test-pi-bootloader.sh` asserts `boot.loader.generic-extlinux-compatible.enable = true` and `boot.kernelPackages.kernel.pname = "linux"`.
- `ssh -o BatchMode=yes -o ConnectTimeout=5 bdhill@192.168.68.56 true` timed out (exit 255) on 2026-08-17, confirming rather than discovering the disconnection.

**pi5** (D-13's reachability conditional resolved to the FALLBACK branch, so `make dry-activate-pi5` was never run):

- `ssh -o BatchMode=yes -o ConnectTimeout=5 nixos@192.168.0.110 true` timed out (exit 255) on 2026-08-17; `nixos@pi5.local` and `nixos@pi5.shad-bangus.ts.net` both failed to resolve.
- A control run of `ssh -o BatchMode=yes -o ConnectTimeout=5 bdhill@192.168.68.65` (ser8) exited 0 in the same session, making the pi5 failures attributable to the host rather than to SSH.
- Fallback evidence: `nix build --dry-run '.#nixosConfigurations.pi5.config.system.build.toplevel'` exits 0 (162 derivations, 911 fetched paths), plus `./scripts/validation/test-pi-bootloader.sh` and `nix eval --raw '.#nixosConfigurations.pi5.config.hardware.raspberry-pi.configtxt.file.text'` for the rendered `config.txt`.
- pi5's `deploy.yaml` entry (`192.168.0.110`, `targetUser: nixos`) is the only one on `192.168.0.0/24` and uses the installer's default account, so it is very likely stale and needs correcting before any plan tries to reach that host.

**Deferred Pi work, with the path already established:**

- Build a minimal upstream sd-image with SSH keys baked in, flash pi5 once, then deploy the full configuration remotely (D-02).
- Bootstrap-image build targets replace the `make pi4-installer` / `make pi5-installer` targets removed in 09-02, which depended on the deleted fork input (D-08).
- Intended technical path: import `nixos-hardware.nixosModules.raspberry-pi-5` into the bootstrap image configuration. Its `raspberry-pi/common/firmware.nix` uses `lib.mkForce` on `sdImage.populateFirmwareCommands` to override `sd-image-aarch64.nix`, and its install script copies all vendor DTBs from `pkgs.raspberrypifw` plus `pkgs.ubootRaspberryPiAarch64`, supplying exactly the Pi 5 files stable 26.05 lacks. Fallbacks, in order: build the bootstrap image from the retained `nixpkgs-unstable` input, or wait for 26.11.
- Until the reflash happens, pi5's FAT `/boot/firmware` partition still holds fork-era U-Boot, which is why `make switch-pi5` must not be run against the migrated configuration.

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd-transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd-complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-08-25 — Phase 13 (ZFS Mirror Migration) complete*
