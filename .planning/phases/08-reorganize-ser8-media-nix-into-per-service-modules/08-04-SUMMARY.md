---
phase: 08-reorganize-ser8-media-nix-into-per-service-modules
plan: 04
subsystem: infra
tags: [nixos, media, jellyfin, sops, prometheus]

requires:
  - phase: 08-03
    provides: Extracted download-client host modules and ordered media configuration
provides:
  - Complete ser8 Jellyfin host policy with three household identities
  - Host-owned Jellyfin and declarative Jellyfin enablement
  - Generic Jellyfin exporter interface with typed API key file input
affects: [08-05, 08-06, 08-07]

tech-stack:
  added: []
  patterns: [host-owned service policy, typed secret path boundary, conditional reusable modules]

key-files:
  created:
    - hosts/ser8/media/jellyfin.nix
  modified:
    - hosts/ser8/media/default.nix
    - hosts/ser8/media.nix
    - modules/media/jellyfin.nix
    - modules/media/jellyfin-exporter.nix
    - scripts/validation/check-ser8-media-parity.sh

key-decisions:
  - "Keep all Jellyfin household identities, credentials, API key wiring, and enablement decisions in the ser8 host module."
  - "Expose only enable and apiKeyFile as reusable Jellyfin exporter host inputs."

patterns-established:
  - "Jellyfin host slice: concrete identities and credential paths activate otherwise generic service modules."
  - "Runtime secret boundary: a typed file path feeds systemd LoadCredential without exposing secret contents to the Nix store."

requirements-completed: []

coverage:
  - id: D-01-D-05
    description: "ser8 owns Jellyfin policy while reusable modules retain generic account, network, firewall, and exporter behavior."
    verification:
      - kind: integration
        ref: "scripts/validation/check-ser8-media-parity.sh check"
        status: pass
    human_judgment: false
  - id: T-08-10
    description: "Sawnia has the complete Jordan-equivalent non-administrator authorization contract with her own password path."
    verification:
      - kind: security
        ref: "assert_expected_deltas in check-ser8-media-parity.sh"
        status: pass
    human_judgment: false
  - id: T-08-11-T-08-12
    description: "Exporter credentials remain systemd-managed and existing Jellyfin behavior remains equal to baseline."
    verification:
      - kind: build
        ref: "scripts/validation/check-ser8-media-parity.sh run-clean make build-ser8"
        status: pass
    human_judgment: false

duration: 5min
completed: 2026-07-25
status: complete
---

# Phase 08 Plan 04: Jellyfin Host Policy and Generic Exporter Summary

**Jellyfin identities and credentials now live in a complete ser8 host slice, while reusable service modules accept only generic policy inputs and preserve evaluated runtime behavior.**

## Performance

- **Duration:** 5 min
- **Started:** 2026-07-25T22:14:49Z
- **Completed:** 2026-07-25T22:19:51Z
- **Tasks:** 2
- **Files modified:** 6

## Accomplishments

- Moved both Jellyfin enablement decisions, four SOPS declarations, three complete household user records, and API key wiring into `hosts/ser8/media/jellyfin.nix`.
- Added Sawnia with the same evaluated non-administrator permissions and preferences as Jordan and a distinct `jellyfin_sawnia_password` path.
- Removed household, secret, and enablement policy from the reusable Jellyfin implementation while preserving its account, network, and firewall behavior.
- Added typed `enable` and `apiKeyFile` options to the reusable exporter and retained its wrapper, environment, systemd hardening, port 9711, and firewall behavior.
- Strengthened parity assertions so both enablement values and the complete approved Sawnia record are required.

## Task Commits

Each implementation task was committed atomically:

1. **Task 1: Move Jellyfin enablement, identities, secrets, and API-key policy to ser8** - `52653ed` (refactor)
2. **Task 2: Make the Jellyfin exporter host-agnostic** - `462ea08` (refactor)

## Files Created/Modified

- `hosts/ser8/media/jellyfin.nix` - Owns service enablement, household records, four secret declarations, API key wiring, and exporter host inputs.
- `hosts/ser8/media/default.nix` - Imports the focused Jellyfin host module.
- `hosts/ser8/media.nix` - No longer declares Jellyfin secrets or API key policy.
- `modules/media/jellyfin.nix` - Retains only generic Jellyfin account, network, and firewall implementation.
- `modules/media/jellyfin-exporter.nix` - Exposes a typed host-independent option boundary and conditionally creates the exporter.
- `scripts/validation/check-ser8-media-parity.sh` - Requires true enablement and the exact approved Sawnia policy delta.

## Decisions Made

- Jellyfin household identity and credential policy belongs entirely to the ser8 host slice.
- The exporter accepts only an enable decision and API key file path from its host.
- The reusable exporter continues to deliver the API key through systemd `LoadCredential` rather than environment or store content.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

- The sandbox denied access to the normal user configuration and GPG keyring.
Verification used the established isolated temporary HOME, and commits retained normal hooks with signing disabled per commit.
- Statix accepts only one target path per invocation in this development shell.
Each changed Nix file was checked individually.
- The Home Manager 25.05 versus Nixpkgs 25.11 warning remained the exact user-approved baseline from Plan 08-01.
No changed or additional warning was accepted by the build gate.

## Known Stubs

- `hosts/ser8/media/jellyfin.nix:19` sets `enabledLibraries` to an explicit empty list for every household record.
This is the preserved complete Jellyfin preference contract, not unfinished wiring.
- `hosts/ser8/media.nix:241` retains the pre-existing disabled AllDebrid TODO block.
Plan 06 owns its removal, and it does not affect active Jellyfin behavior.

## User Setup Required

None - the encrypted `secrets/ser8.yaml` change was intentionally left untouched, and no live activation was performed.

## Verification

- `nixfmt --check` passed for all five plan-owned Nix files.
- `statix check` passed individually for all five plan-owned Nix files.
- ShellCheck and `shfmt -d` passed for the strengthened parity runner.
- Normalized evaluated parity passed with both Jellyfin enablement values true and only the complete approved Sawnia addition allowed.
- Structural assertions confirmed reusable Jellyfin modules contain no SOPS, ser8, or household identity references.
- `scripts/validation/check-ser8-media-parity.sh structure` passed.
- `scripts/validation/check-ser8-media-parity.sh run-clean make build-ser8` passed and produced `/nix/store/kbvdm51a6xydhd024jnjc0v9182srb2j-nixos-system-ser8-25.11.20260518.687f05a`.
- No live activation was performed.

## Next Phase Readiness

- Plan 05 can extract the remaining shared SOPS and orchestration policy from the reduced aggregate module.
- Jellyfin household and exporter ownership is explicit, host-local, and covered by evaluated parity.
- The user-owned config migration, encrypted secret changes, and phase `.gitkeep` remain outside Phase 08 Plan 04 commits.

## Self-Check: PASSED

- The created Jellyfin host module exists.
- Commits `52653ed` and `462ea08` exist in git history.
- All task acceptance criteria, threat mitigations, and plan-level verification commands passed.
- No unresolved high-severity threat remains.
- Unrelated user-owned changes remain uncommitted.

---
*Phase: 08-reorganize-ser8-media-nix-into-per-service-modules*
*Completed: 2026-07-25*
