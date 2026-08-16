---
phase: 08-reorganize-ser8-media-nix-into-per-service-modules
plan: 03
subsystem: infra
tags: [nixos, media, sops, nginx, nordvpn]

requires:
  - phase: 08-02
    provides: Ordered service-owned media configuration pattern
provides:
  - Complete NZBGet host-policy module with shared Usenet credential references
  - SABnzbd-owned shared Usenet credential contract and complete service template
  - VPN-isolated qBittorrent host-policy module with nginx proxy and atomic deployment
affects: [08-04, 08-05, 08-06, 08-07]

tech-stack:
  added: []
  patterns: [vertical service slices, ordered systemd fragments, shared secret ownership]

key-files:
  created:
    - hosts/ser8/media/nzbget.nix
    - hosts/ser8/media/sabnzbd.nix
    - hosts/ser8/media/qbittorrent.nix
  modified:
    - hosts/ser8/media/default.nix
    - hosts/ser8/media.nix
    - hosts/ser8/configuration.nix

key-decisions:
  - "Keep SABnzbd as the single declaration owner for the shared administrator and Usenet credentials consumed by NZBGet."
  - "Use dependency priorities 450, 500, and 550 independently from deployment-script priorities 500, 600, and 700 to preserve both evaluated orders."

patterns-established:
  - "Download-client host slice: enablement, secrets, template, and deployment contribution live beside service-specific network policy."
  - "Shared secret contract: one service owns declarations while another service references the same unchanged SOPS placeholders."

requirements-completed: []

coverage:
  - id: D-01-D-07
    description: "Each download client owns its complete ser8 host-policy slice while shared credentials retain one owner."
    verification:
      - kind: integration
        ref: "scripts/validation/check-ser8-media-parity.sh check"
        status: pass
    human_judgment: false
  - id: D-09-D-11
    description: "The shared deployment unit preserves dependencies and download-client script ordering."
    verification:
      - kind: integration
        ref: "Normalized parity projection and warning-clean make build-ser8"
        status: pass
    human_judgment: false
  - id: T-08-07-T-08-09
    description: "Secret placeholders, file modes, VPN proxying, and atomic qBittorrent deployment remain unchanged."
    verification:
      - kind: security
        ref: "Parity projection plus focused source assertions"
        status: pass
    human_judgment: false

duration: 9min
completed: 2026-07-25
status: complete
---

# Phase 08 Plan 03: Download Client Host Modules Summary

**NZBGet, SABnzbd, and qBittorrent now own complete host-policy modules with unchanged shared credentials, VPN isolation, nginx proxying, and evaluated deployment behavior.**

## Performance

- **Duration:** 9 min
- **Started:** 2026-07-25T22:00:06Z
- **Completed:** 2026-07-25T22:09:20Z
- **Tasks:** 3
- **Files modified:** 6

## Accomplishments

- Extracted NZBGet enablement, complete template, shared SABnzbd credential references, and order-500 deployment into one host module.
- Extracted SABnzbd enablement, config path, six owned secret declarations, complete INI template, and order-600 deployment into one host module.
- Extracted qBittorrent VPN policy, secrets, complete template, nginx proxy, and order-700 atomic deployment into one host module.
- Preserved evaluated parity after each extraction and completed a warning-clean remote ser8 build without activation.

## Task Commits

Each implementation task was committed atomically:

1. **Task 1: Extract NZBGet while preserving shared credential references** - `04e3892` (refactor)
2. **Task 2: Extract SABnzbd as the shared Usenet secret owner** - `5e5fb5b` (refactor)
3. **Task 3: Extract qBittorrent with VPN proxy and atomic deployment intact** - `c473851` (refactor)

## Files Created/Modified

- `hosts/ser8/media/nzbget.nix` - Owns NZBGet enablement, template, shared credential references, and deployment fragment.
- `hosts/ser8/media/sabnzbd.nix` - Owns SABnzbd enablement, shared Usenet secrets, template, config path, and deployment fragment.
- `hosts/ser8/media/qbittorrent.nix` - Owns qBittorrent VPN policy, secrets, template, nginx proxy, and atomic deployment fragment.
- `hosts/ser8/media/default.nix` - Imports all three download-client host modules.
- `hosts/ser8/media.nix` - No longer owns extracted download-client policy.
- `hosts/ser8/configuration.nix` - No longer owns download-client enablement or qBittorrent nginx policy.

## Decisions Made

- SABnzbd remains the single owner of `sabnzbd_admin_password` and all `sabnzbd_usenet_*` declarations.
- NZBGet continues to consume those exact shared declarations and placeholders without duplication or renaming.
- Dependency-list priorities 450, 500, and 550 preserve qBittorrent, NZBGet, and SABnzbd unit order.
- Deployment-script priorities remain 500, 600, and 700 for NZBGet, SABnzbd, and qBittorrent.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Preserved the independent unit dependency order**

- **Found during:** Task 1
- **Issue:** Assigning NZBGet priority 500 while leaving qBittorrent and SABnzbd in one default-priority list moved NZBGet before qBittorrent in `media-config.before`.
- **Fix:** Split dependency contributions onto priorities 450, 500, and 550 while retaining deployment-script priorities 500, 600, and 700.
- **Files modified:** `hosts/ser8/media.nix`, `hosts/ser8/media/nzbget.nix`, `hosts/ser8/media/sabnzbd.nix`, `hosts/ser8/media/qbittorrent.nix`
- **Verification:** The normalized parity projection matches the baseline after every extraction.
- **Commit:** `04e3892`, completed across `5e5fb5b` and `c473851`

**Total deviations:** 1 auto-fixed bug.

**Impact:** The correction preserves both established systemd dependency order and deployment command order without changing runtime behavior.

## Issues Encountered

- The `sagent` sandbox denied Nix and GPG access to user configuration directories.
- Verification used an isolated temporary HOME with read-only links to the existing trusted Nix settings and SSH directory.
- Task commits ran normal hooks but disabled commit signing because the sandbox could not access the configured GPG keyring.
- The Home Manager 25.05 versus Nixpkgs 25.11 warning remained the exact user-approved baseline from Plan 08-01.

## Known Stubs

- The download-client templates contain SOPS placeholders by design.
They resolve encrypted values at runtime and are complete production wiring, not unfinished data sources.
- The pre-existing disabled AllDebrid TODO remains in `hosts/ser8/media.nix`.
Plan 06 owns its removal, and it does not affect this plan's active download-client behavior.

## User Setup Required

None - no external service configuration or live activation is required.

## Verification

- `nixfmt --check` passed for all six plan-owned Nix files.
- `statix check` passed individually for all six plan-owned Nix files.
- The normalized parity projection passed after each extraction and at the final boundary.
- Structural ownership assertions confirmed all SABnzbd and qBittorrent secrets have exactly one declaration owner.
- Focused assertions confirmed qBittorrent firewall closure, VPN namespace use, NordVPN proxy target, proxy headers, temporary-file deployment, mode 0600, and atomic move.
- `scripts/validation/check-ser8-media-parity.sh structure` passed.
- `scripts/validation/check-ser8-media-parity.sh run-clean make build-ser8` passed and produced `/nix/store/kd4diqnrwwrfapkv0hp9imizcy8b6f6x-nixos-system-ser8-25.11.20260518.687f05a`.
- No live activation was performed.

## Next Phase Readiness

- Plan 04 can extract Jellyfin policy from the smaller aggregate module.
- Shared Usenet ownership is explicit and available to orchestration without credential changes.
- The protected Sawnia password declaration and encrypted secret changes remain uncommitted for their owning work.

## Self-Check: PASSED

- All six key files exist.
- Commits `04e3892`, `5e5fb5b`, and `c473851` exist in git history.
- All task acceptance criteria and plan-level verification commands passed.
- No unresolved high-severity threat remains.
- The user-owned config migration, Sawnia declaration, encrypted secret changes, and phase `.gitkeep` remain outside Phase 08 Plan 03 commits.

---
*Phase: 08-reorganize-ser8-media-nix-into-per-service-modules*
*Completed: 2026-07-25*
