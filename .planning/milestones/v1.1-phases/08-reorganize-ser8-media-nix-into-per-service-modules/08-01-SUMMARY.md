---
phase: 08-reorganize-ser8-media-nix-into-per-service-modules
plan: 01
subsystem: infra
tags: [nixos, media, parity, sops, systemd]

requires: []
provides:
  - Non-secret evaluated ser8 media behavior baseline
  - Exact warning-baseline classifier with fail-closed new-warning detection
  - Ordered media configuration fragments and directory import seam
affects: [08-02, 08-03, 08-04, 08-05, 08-06, 08-07]

tech-stack:
  added: [jq-based parity projection]
  patterns: [evaluated behavior fixtures, lib.mkOrder script fragments, import-only directory entrypoints]

key-files:
  created:
    - scripts/validation/ser8-media-projection.nix
    - scripts/validation/check-ser8-media-parity.sh
    - .planning/phases/08-reorganize-ser8-media-nix-into-per-service-modules/08-ser8-media-before.json
    - .planning/phases/08-reorganize-ser8-media-nix-into-per-service-modules/08-warning-baseline.txt
    - .planning/phases/08-reorganize-ser8-media-nix-into-per-service-modules/08-ser8-store-path-before.txt
    - hosts/ser8/media/default.nix
  modified:
    - hosts/ser8/configuration.nix
    - hosts/ser8/media.nix
    - scripts/nixos-rebuild.sh

key-decisions:
  - "Continue with the user-approved Home Manager 25.05 versus Nixpkgs 25.11 warning as an exact baseline exception without changing dependency pins or release checks."
  - "Normalize only approved helper and generated unit-script store paths while comparing evaluated behavior."

patterns-established:
  - "Parity gate: evaluate a JSON-safe contract, normalize documented structural paths, and diff against the durable fixture."
  - "Warning gate: allow only exact classified baseline warning lines and reject changed or new warnings."

requirements-completed: []

coverage:
  - id: D1
    description: "Non-secret evaluated ser8 media behavior is captured in a durable baseline fixture."
    verification:
      - kind: integration
        ref: "scripts/validation/check-ser8-media-parity.sh capture/check"
        status: pass
    human_judgment: false
  - id: D2
    description: "ser8 imports the media directory through a behavior-neutral ordered extraction seam."
    verification:
      - kind: integration
        ref: "scripts/validation/check-ser8-media-parity.sh structure/check and make build-ser8"
        status: pass
    human_judgment: false

duration: 14min
completed: 2026-07-25
status: complete
---

# Phase 08 Plan 01: Media Parity Baseline and Import Seam Summary

**A non-secret evaluated media contract now guards an ordered directory import seam while permitting only the user-approved exact Home Manager mismatch warning.**

## Performance

- **Duration:** 14 min
- **Started:** 2026-07-25T21:24:13Z
- **Completed:** 2026-07-25T21:37:26Z
- **Tasks:** 2 implementation tasks plus 1 resumed prerequisite checkpoint
- **Files modified:** 9

## Accomplishments

- Captured service settings, SOPS metadata and placeholders, templates, household users, exporters, nginx wiring, accounts, firewall ports, units, targets, and generated scripts without secret values.
- Added capture, comparison, structure, and warning-clean command modes with explicit Sawnia and AllDebrid delta handling.
- Reassembled `media-config.script` with native priorities 100 through 800 and routed ser8 through an import-only media directory entry point.
- Built the resulting ser8 system remotely without activation.

## Task Commits

Each implementation task was committed atomically:

1. **Task 2: Build the non-secret parity projection and capture the baseline** - `1485835` (test)
2. **Task 3: Order the aggregate script and introduce the directory import seam** - `3b5cc76` (refactor)

## Files Created/Modified

- `scripts/validation/ser8-media-projection.nix` - Projects the JSON-safe evaluated media behavior contract.
- `scripts/validation/check-ser8-media-parity.sh` - Captures, compares, structurally checks, and classifies command warnings.
- `.planning/phases/08-reorganize-ser8-media-nix-into-per-service-modules/08-ser8-media-before.json` - Stores the normalized pre-refactor behavior fixture.
- `.planning/phases/08-reorganize-ser8-media-nix-into-per-service-modules/08-warning-baseline.txt` - Stores the exact approved warning and local Nix notices.
- `.planning/phases/08-reorganize-ser8-media-nix-into-per-service-modules/08-ser8-store-path-before.txt` - Records the pre-refactor system store path.
- `hosts/ser8/media/default.nix` - Imports the aggregate module through the new directory seam.
- `hosts/ser8/configuration.nix` - Imports `./media` instead of `./media.nix`.
- `hosts/ser8/media.nix` - Uses ordered native module definitions without changing evaluated script bytes.
- `scripts/nixos-rebuild.sh` - Uses current rebuild flags and clean formatting so the build warning gate can distinguish repository warnings from operational output.

## Decisions Made

- The user explicitly approved continuing despite the Home Manager release mismatch.
- Dependency pins and `home.enableNixpkgsReleaseCheck` remain unchanged.
- Repeated occurrences of an exact baseline warning line are allowed during multi-step local and remote Nix commands.
- Any changed warning line, synthetic warning, evaluation error, fatal message, or trace still fails `run-clean`.

## Deviations from Plan

### User-Approved Checkpoint Deviation

**1. Continued with the exact Home Manager mismatch warning**

- **Found during:** Task 1 prerequisite checkpoint
- **Plan gate:** Required the mismatch to be resolved externally before implementation.
- **User decision:** "Why does the home manager version mismatch matter -- just ignore and keep going"
- **Implementation:** Captured the exact warning as the permitted baseline and retained fail-closed handling for changed or additional warnings.
- **Scope protection:** No dependency pin or warning-suppression setting changed.

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Classified operational build stderr separately from warnings**

- **Found during:** Task 3 remote build verification
- **Issue:** Verbose rebuild diagnostics produced non-warning stderr that obscured warning classification.
- **Fix:** Warning validation now checks warning, error, fatal, trace, and complete Home Manager warning content while allowing ordinary build progress.
- **Files modified:** `scripts/validation/check-ser8-media-parity.sh`
- **Verification:** Synthetic warnings fail and the exact baseline warning passes during `make build-ser8`.
- **Committed in:** `3b5cc76`

**2. [Rule 3 - Blocking] Replaced deprecated nixos-rebuild flags**

- **Found during:** Task 3 remote build verification
- **Issue:** `--use-remote-sudo` and `--fast` emitted additional warnings, and `--verbose` emitted debug diagnostics.
- **Fix:** Replaced them with `--sudo` and `--no-reexec`, removed verbose mode, and formatted the changed shell script.
- **Files modified:** `scripts/nixos-rebuild.sh`
- **Verification:** ShellCheck, shfmt, and warning-clean remote ser8 build passed.
- **Committed in:** `3b5cc76`

---

**Total deviations:** 2 auto-fixed blocking issues and 1 explicit user-approved prerequisite exception.
**Impact on plan:** The media configuration behavior remains equal to the baseline, and warning detection is stricter for new warnings while intentionally permitting the exact known mismatch.

## Issues Encountered

- Native `types.lines` merging inserts separators between definitions.
The middle fragments remove only their trailing newline so the evaluated aggregate script remains byte-identical to the original.
- The Home Manager 25.05 versus Nixpkgs 25.11 mismatch remains present by explicit user decision.
It is tracked as exact baseline debt rather than suppressed.

## Known Stubs

- `hosts/ser8/media.nix` uses SOPS placeholders throughout template content by design.
They are runtime secret references, not incomplete data wiring.
- `hosts/ser8/media.nix:763` contains a pre-existing disabled AllDebrid TODO block.
Its removal is locked for a later Phase 8 cleanup plan.

## User Setup Required

None - no external service configuration is required.

## Verification

- `shellcheck scripts/validation/check-ser8-media-parity.sh` passed.
- `shellcheck -x scripts/nixos-rebuild.sh` passed.
- `shfmt -d scripts/validation/check-ser8-media-parity.sh scripts/nixos-rebuild.sh` passed.
- `nixfmt --check` passed for all changed Nix files.
- Baseline JSON category and secret-metadata safety assertions passed.
- Same-tree normalized parity and structural assertions passed.
- Synthetic warning rejection passed.
- `scripts/validation/check-ser8-media-parity.sh run-clean make build-ser8` passed without activation.

## Next Phase Readiness

- Plan 02 can move already-ordered service definitions into focused modules and use the parity gate after each extraction.
- The exact Home Manager mismatch remains known and user-approved.
Any text change or new warning will block subsequent `run-clean` checks.

## Self-Check: PASSED

- All key created files exist.
- Commits `1485835` and `3b5cc76` exist in git history.
- The user-owned `jellyfin_sawnia_password` working-tree block and encrypted secret changes remain uncommitted.

---
*Phase: 08-reorganize-ser8-media-nix-into-per-service-modules*
*Completed: 2026-07-25*
