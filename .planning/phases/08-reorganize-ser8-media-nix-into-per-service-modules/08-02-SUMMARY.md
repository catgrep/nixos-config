---
phase: 08-reorganize-ser8-media-nix-into-per-service-modules
plan: 02
subsystem: infra
tags: [nixos, media, sonarr, radarr, prowlarr, exportarr, sops, systemd]

requires:
  - phase: 08-01
    provides: Non-secret media parity fixture, warning classifier, and ordered extraction seam
provides:
  - Complete ser8 host-policy modules for Sonarr, Radarr, and Prowlarr
  - Arr-owned Exportarr instances and ordered media-config contributions
  - Drained grouped Exportarr host-policy module
affects: [08-03, 08-04, 08-05, 08-06, 08-07]

tech-stack:
  added: []
  patterns: [complete host service slices, lib.mkOrder deployment contributions, host-owned exporter instances]

key-files:
  created:
    - hosts/ser8/media/sonarr.nix
    - hosts/ser8/media/radarr.nix
    - hosts/ser8/media/prowlarr.nix
  modified:
    - hosts/ser8/media/default.nix
    - hosts/ser8/media.nix
    - hosts/ser8/configuration.nix
    - modules/media/exportarr.nix

key-decisions:
  - "Keep each Arr service's enablement, secrets, template, exporter instance, and deployment contribution together in one host module."
  - "Preserve deployment order with explicit priorities 200, 300, and 400 rather than import ordering."

patterns-established:
  - "Arr host slice: concrete host policy and exporter wiring live beside the service's SOPS template and deployment fragment."
  - "Ordered unit composition: each service contributes both its media-config.before entry and a uniquely ordered script fragment."

requirements-completed: []

coverage:
  - id: D-01
    description: "Each Arr service is discoverable as a complete ser8 host-policy slice."
    verification:
      - kind: integration
        ref: "scripts/validation/check-ser8-media-parity.sh check"
        status: pass
    human_judgment: false
  - id: D-03
    description: "Each Arr service owns its matching Exportarr instance."
    verification:
      - kind: structural
        ref: "Exporter ownership assertions and drained modules/media/exportarr.nix"
        status: pass
    human_judgment: false
  - id: D-09-D-11
    description: "The shared deployment unit preserves service dependencies and Sonarr, Radarr, Prowlarr ordering."
    verification:
      - kind: integration
        ref: "Normalized parity projection and warning-clean make build-ser8"
        status: pass
    human_judgment: false

duration: 8min
completed: 2026-07-25
status: complete
---

# Phase 08 Plan 02: Arr Host Service Modules Summary

**Sonarr, Radarr, and Prowlarr now own complete host-policy slices with unchanged SOPS templates, exporter endpoints, dependencies, and evaluated deployment behavior.**

## Performance

- **Duration:** 8 min
- **Started:** 2026-07-25T21:43:29Z
- **Completed:** 2026-07-25T21:51:22Z
- **Tasks:** 3
- **Files modified:** 7

## Accomplishments

- Extracted Sonarr, Radarr, and Prowlarr enablement, secrets, templates, Exportarr instances, and deployment fragments into focused host modules.
- Preserved the evaluated media contract after every extraction, including template placeholders, secret metadata, exporter settings, unit dependencies, and generated script order.
- Drained `modules/media/exportarr.nix` of all host-specific exporter instances while leaving it as a valid empty module for removal in Plan 06.
- Completed a warning-clean remote ser8 build without activation.

## Task Commits

Each implementation task was committed atomically:

1. **Task 1: Extract the complete Sonarr host slice** - `c87a302` (refactor)
2. **Task 2: Extract the complete Radarr host slice** - `1621bec` (refactor)
3. **Task 3: Extract the complete Prowlarr host slice** - `bce5415` (refactor)

## Files Created/Modified

- `hosts/ser8/media/sonarr.nix` - Owns Sonarr host settings, SOPS data, Exportarr configuration, and order-200 deployment.
- `hosts/ser8/media/radarr.nix` - Owns Radarr host settings, SOPS data, Exportarr configuration, and order-300 deployment.
- `hosts/ser8/media/prowlarr.nix` - Owns Prowlarr host settings, SOPS data, Exportarr configuration, and order-400 deployment.
- `hosts/ser8/media/default.nix` - Imports the three focused Arr host modules.
- `hosts/ser8/media.nix` - No longer owns the extracted Arr policy blocks.
- `hosts/ser8/configuration.nix` - No longer owns Arr enablement and Prowlarr network policy.
- `modules/media/exportarr.nix` - Remains a valid empty module after all three host instances moved.

## Decisions Made

- Each Arr host module is the single owner of its concrete service policy and exporter instance.
- Explicit `lib.mkOrder` values 200, 300, and 400 preserve deployment order independently of import order.
- The drained Exportarr file remains until Plan 06 removes its reusable-module import and file together.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

- Flake evaluation required each newly created module to be staged before the parity command could see it.
- The Home Manager 25.05 versus Nixpkgs 25.11 warning remained the exact user-approved baseline from Plan 08-01.
No changed or additional warning was accepted.

## Known Stubs

- The Arr XML templates contain SOPS placeholders by design.
They resolve encrypted values at runtime and are complete production wiring, not unfinished data sources.
- `modules/media/exportarr.nix` is intentionally empty after its last instance moved.
Plan 06 owns deletion of the drained file and its existing import.

## User Setup Required

None - no external service configuration or live activation is required.

## Verification

- `nixfmt --check` passed for all seven plan-owned Nix files.
- The normalized parity projection passed after each of the Sonarr, Radarr, and Prowlarr extractions.
- Structural ownership assertions confirmed each template and exporter instance has exactly one owning host module.
- Deployment source assertions confirmed priorities 200, 300, and 400 for Sonarr, Radarr, and Prowlarr.
- `scripts/validation/check-ser8-media-parity.sh run-clean make build-ser8` passed and produced `/nix/store/kd4diqnrwwrfapkv0hp9imizcy8b6f6x-nixos-system-ser8-25.11.20260518.687f05a`.
- No live activation was performed.

## Next Phase Readiness

- Plan 03 can apply the established complete-slice pattern to the remaining download clients.
- The aggregate module still owns shared SOPS defaults, remaining service templates, and orchestration as expected at this phase boundary.
- The protected Sawnia password declaration and encrypted secret changes remain uncommitted for their owning work.

## Self-Check: PASSED

- All seven key files exist.
- Commits `c87a302`, `1621bec`, and `bce5415` exist in git history.
- All task acceptance criteria and plan-level verification commands passed.
- The user-owned config migration, Sawnia declaration, encrypted secret changes, and phase `.gitkeep` remain outside Phase 08 Plan 02 commits.

---
*Phase: 08-reorganize-ser8-media-nix-into-per-service-modules*
*Completed: 2026-07-25*
