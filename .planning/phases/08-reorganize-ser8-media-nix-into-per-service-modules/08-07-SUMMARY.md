---
phase: 08-reorganize-ser8-media-nix-into-per-service-modules
plan: 07
subsystem: infra
tags: [nixos, media, audit, parity, validation]

requires:
  - phase: 08-06
    provides: Active-only reusable media module tree after dead provider cleanup
provides:
  - Explicit audit outcomes for every remaining reusable media provider
  - Final structural and normalized behavior parity evidence for Phase 8
  - Successful repository and ser8 build gates without live activation
affects: [phase-08-verification, ser8-media]

tech-stack:
  added: []
  patterns: [active-provider audit, normalized evaluated parity, no-activation build gate]

key-files:
  created:
    - .planning/phases/08-reorganize-ser8-media-nix-into-per-service-modules/08-07-SUMMARY.md
  modified:
    - modules/media/sonarr.nix
    - modules/media/radarr.nix
    - modules/media/prowlarr.nix
    - modules/media/qbittorrent.nix

key-decisions:
  - "Accept only the user-approved pre-existing warning classes for repository-wide make check while leaving the Phase 8 parity warning baseline exact and unchanged."
  - "Treat normalized evaluated behavior as the acceptance proof because the approved helper split intentionally changes the ser8 store path."

patterns-established:
  - "Reusable provider audits retain every active runtime and security boundary while removing only proven dead declarations."
  - "Phase acceptance separates exact phase-specific warning classification from explicitly accepted repository-wide warning exceptions."

requirements-completed: [N/A]

coverage:
  - id: D-22
    description: "Every remaining reusable media provider has an explicit audit outcome and contains only active behavior."
    verification:
      - kind: integration
        ref: "nixfmt, statix, provider boundary scans, and normalized parity check"
        status: pass
    human_judgment: false
  - id: D-15-D-17
    description: "The final media structure and evaluated behavior match the locked contract with only approved deltas."
    verification:
      - kind: integration
        ref: "scripts/validation/check-ser8-media-parity.sh structure and check"
        status: pass
      - kind: integration
        ref: "make check and warning-classified make build-ser8"
        status: pass
    human_judgment: false
  - id: D-18
    description: "Phase 8 completed through evaluation and build checks without activating the ser8 configuration."
    verification:
      - kind: other
        ref: "executed command audit limited to format, lint, parity, make check, nix eval, and make build-ser8"
        status: pass
    human_judgment: false

duration: 12min
completed: 2026-07-25
status: complete
---

# Phase 08 Plan 07: Reusable Provider Audit and Final Gate Summary

**All active reusable media providers are audited, normalized ser8 behavior remains equal to baseline, and the final no-activation build gates pass.**

## Performance

- **Duration:** 12 min
- **Started:** 2026-07-25T22:43:00Z
- **Completed:** 2026-07-25T22:55:28Z
- **Tasks:** 3
- **Files modified:** 5

## Accomplishments

- Audited all eight active reusable media providers and removed eight dead declarations from the Arr and qBittorrent modules.
- Confirmed SABnzbd, NZBGet, Jellyfin, and Jellyfin exporter were already active-only and retained them unchanged.
- Passed formatting, Statix, ShellCheck, shfmt, structural, normalized parity, repository check, and ser8 build gates without activating the host.
- Recorded the expected system path change from the approved helper split while preserving semantic behavior.

## Task Commits

Each implementation task was committed atomically:

1. **Task 1: Audit Arr and qBittorrent reusable implementations** - `ae0efb2` (refactor)
2. **Task 2: Audit remaining download and Jellyfin providers** - `2d4e29a` (chore, no-change audit record)
3. **Task 3: Run final no-activation phase gate** - validation evidence recorded in this summary commit

## Files Created/Modified

- `modules/media/sonarr.nix` - Removed an unused module argument.
- `modules/media/radarr.nix` - Removed an unused module argument.
- `modules/media/prowlarr.nix` - Removed an unused module argument.
- `modules/media/qbittorrent.nix` - Removed an unused module argument and commented-out implementation.
- `.planning/phases/08-reorganize-ser8-media-nix-into-per-service-modules/08-07-SUMMARY.md` - Records the provider audit and final acceptance evidence.

## Provider Audit Outcomes

- `sonarr.nix`, `radarr.nix`, and `prowlarr.nix`: Removed unused `pkgs` arguments and preserved packages, users, hardening, ports, and exporter boundaries.
- `qbittorrent.nix`: Removed the unused `pkgs` argument and obsolete commented reverse-proxy fragment while preserving the VPN namespace, nginx, firewall, service, and account behavior.
- `sabnzbd.nix`: No change required because every argument, override, account rule, unit override, and firewall declaration is active.
- `nzbget.nix`: No change required because the enabled-service guard, media group membership, and firewall rule are active.
- `jellyfin.nix`: No change required because it contains only generic account, network, service, and firewall policy.
- `jellyfin-exporter.nix`: No change required because its typed options, credential boundary, wrapper, hardening, ordering, and firewall rule are active.
- Plan 06 covered `modules/media/default.nix`; Plans 06 and 07 therefore cover every current `modules/media/*.nix` file.

## Decisions Made

- The user accepted the pre-existing Raspberry Pi `kernelboot` deprecation, unknown custom flake outputs, deprecated `nixfmt-rfc-style` alias, incompatible-system notice, and FlakeHub HTTP 401 retry warnings for repository-wide `make check` only.
- The existing Phase 8 warning inventory remains unchanged and continues to classify parity and focused build stderr exactly.
- Existing local Nix setting notices, dirty-tree notice, saved trusted-setting notices, and the previously approved Home Manager release mismatch remain the exact Phase 8 baseline.
- The before and after ser8 system paths are expected to differ because D-14 split helper ownership into separate store inputs.

## Deviations from Plan

None - implementation and validation followed the plan, with the final repository warning policy resolved through the explicit user decision checkpoint.

## Issues Encountered

- The repository-wide `make check` gate emits pre-existing warnings outside Phase 8 scope.
The user explicitly accepted the listed warning classes and directed completion without fixing or suppressing them.
- Direct parity evaluation cannot read the sandboxed user configuration path.
The established `HOME`-unset invocation passed without changing repository configuration.
- The plan's combined `statix check hosts/ser8/media modules/media` example passes two targets to a single-target CLI.
Running Statix once per target provided the intended complete coverage with no findings.

## Warning Exceptions

`make check` exited successfully and emitted only the following accepted, pre-existing classes:

- The exact Phase 8 baseline for local Nix settings, dirty-tree and trusted-setting notices, and the Home Manager 25.05 versus Nixpkgs 25.11 mismatch.
- Raspberry Pi `kernelboot` deprecation.
- Unknown custom flake outputs for installer and repository metadata exports.
- The `nixfmt-rfc-style` compatibility alias deprecation.
- Incompatible-system omission notices from flake checking.
- FlakeHub cache HTTP 401 retry notices during cross-host dry builds.

These exceptions apply only to repository-wide `make check`.
The parity runner and focused `make build-ser8` gate still use the exact unchanged `08-warning-baseline.txt` classifier.

## Store Path Evidence

- **Before:** `/nix/store/kd4diqnrwwrfapkv0hp9imizcy8b6f6x-nixos-system-ser8-25.11.20260518.687f05a`
- **After:** `/nix/store/pv3zjmhpialypmb5clclkvy0mav0mhjg-nixos-system-ser8-25.11.20260518.687f05a`
- **Expected difference:** D-14 split `systemd_helpers.sh` into deployment and orchestration helpers, changing immutable source and generated unit-script store inputs.
The normalized projection replaces only the approved helper and unit-script store paths, then proves all active media behavior remains equal.

## Known Stubs

None.

## User Setup Required

None - no secret, dependency, deployment, or live host change is required.

## Verification

- `nixfmt --check` passed for all Phase 8 host media modules, reusable media modules, and touched host or flake files.
- `statix check hosts/ser8/media` and `statix check modules/media` passed with no findings.
- ShellCheck and `shfmt -d` passed for both media helper scripts and the parity runner.
- The structural gate passed for the import-only host media entry point and active configuration import.
- Normalized evaluated parity matched `08-ser8-media-before.json` with only the approved deltas.
- `make check` exited 0 under the explicit accepted-warning decision and reported all host configurations valid.
- `scripts/validation/check-ser8-media-parity.sh run-clean make build-ser8` passed under the unchanged warning baseline.
- `make build-ser8` produced `/nix/store/pv3zjmhpialypmb5clclkvy0mav0mhjg-nixos-system-ser8-25.11.20260518.687f05a`.
- No `make test-ser8`, switch, apply, reboot, or other activation command was run.

## Next Phase Readiness

- Phase 8 is complete and ready for phase verification.
- The accepted repository warning classes remain pre-existing cleanup work outside Phase 8.
- The user-owned config migration, encrypted secret changes, and phase `.gitkeep` remain uncommitted.

## Self-Check: PASSED

- Task commits `ae0efb2` and `2d4e29a` exist in git history.
- All eight active reusable providers and the Plan 06 entry point coverage are documented.
- Every Phase 8-specific acceptance gate and the no-activation build gate passed.
- The summary contains no secret values and introduces no new endpoint, authentication path, file-access boundary, or schema change.
- Unrelated user-owned changes remain uncommitted.

---
*Phase: 08-reorganize-ser8-media-nix-into-per-service-modules*
*Completed: 2026-07-25*
