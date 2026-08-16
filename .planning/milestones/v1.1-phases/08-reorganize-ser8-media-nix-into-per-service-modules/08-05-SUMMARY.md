---
phase: 08-reorganize-ser8-media-nix-into-per-service-modules
plan: 05
subsystem: infra
tags: [nixos, systemd, sops, shell, media]

requires:
  - phase: 08-04
    provides: Jellyfin host policy and generic exporter boundary
provides:
  - Import-only ser8 media directory with focused shared SOPS and orchestration modules
  - Strict deployment and API orchestration helper files with preserved behavior
  - Removal of the legacy media aggregate and combined helper
affects: [08-06, 08-07, ser8-media]

tech-stack:
  added: []
  patterns: [import-only host entry point, ordered systemd script fragments, split strict shell helpers]

key-files:
  created:
    - hosts/ser8/media/sops.nix
    - hosts/ser8/media/orchestration.nix
    - hosts/ser8/media/deployment-helpers.sh
    - hosts/ser8/media/orchestration-helpers.sh
  modified:
    - hosts/ser8/media/default.nix
    - scripts/validation/check-ser8-media-parity.sh
    - scripts/validation/ser8-media-projection.nix
  deleted:
    - hosts/ser8/media.nix
    - hosts/ser8/systemd_helpers.sh

key-decisions:
  - "Keep shared SOPS policy limited to file, format, and host age-key defaults while service modules own every active declaration."
  - "Preserve stable unit interfaces and explicit script priorities while sourcing deployment and orchestration helpers separately."
  - "Allow absent planned AllDebrid declarations only in the secret inventory projection while keeping all active contracts strict."

patterns-established:
  - "Shared support owner: cross-service defaults and orchestration live beside complete service slices under the host media directory."
  - "Helper safety boundary: deployment contains configure_arr only, while authenticated API handling stays in the sanitized orchestration helper."

requirements-completed: [N/A]

coverage:
  - id: D-06-D-08
    description: "Shared SOPS defaults and all active media imports have focused owners under an import-only host directory entry point."
    verification:
      - kind: integration
        ref: "scripts/validation/check-ser8-media-parity.sh structure"
        status: pass
    human_judgment: false
  - id: D-09-D-16
    description: "Cross-service systemd dependencies, ordered deployment commands, helper behavior, and generated scripts preserve the evaluated baseline."
    verification:
      - kind: integration
        ref: "scripts/validation/check-ser8-media-parity.sh check 08-ser8-media-before.json"
        status: pass
    human_judgment: false
  - id: D-19-D-20
    description: "The legacy aggregate, combined helper, unused AllDebrid declarations, and disabled AllDebrid block are absent."
    verification:
      - kind: other
        ref: "Task 3 file absence and exact import-count assertions"
        status: pass
    human_judgment: false
  - id: T-08-13-T-08-15
    description: "Sanitized API failures, unit activation semantics, and explicit deployment order remain enforced in a buildable ser8 system."
    verification:
      - kind: integration
        ref: "ShellCheck, shfmt, normalized parity, and make build-ser8"
        status: pass
    human_judgment: false

duration: 8min
completed: 2026-07-25
status: complete
---

# Phase 08 Plan 05: Shared Media Support and Legacy Aggregate Removal Summary

**ser8 media now uses focused shared SOPS and orchestration modules, separate strict helpers, and an import-only directory with no legacy aggregate files.**

## Performance

- **Duration:** 8 min
- **Started:** 2026-07-25T22:22:56Z
- **Completed:** 2026-07-25T22:31:02Z
- **Tasks:** 3
- **Files modified:** 9

## Accomplishments

- Split the 531-line combined helper into a single-function deployment helper and a 13-function sanitized API orchestration helper.
- Moved shared SOPS defaults and all cross-service systemd units into focused host support modules while preserving evaluated dependencies and scripts.
- Removed the legacy `hosts/ser8/media.nix` aggregate, its unused AllDebrid policy, and `hosts/ser8/systemd_helpers.sh` only after ownership and source wiring were complete.
- Left `hosts/ser8/media/default.nix` import-only with exactly shared SOPS, seven active services, and orchestration.
- Built the final ser8 system after structural checks, normalized parity, ShellCheck, shfmt, nixfmt, and statix passed.

## Task Commits

Each implementation task was committed atomically:

1. **Task 1: Split deployment and orchestration helper functions** - `6e09102` (refactor)
2. **Task 2: Extract shared SOPS defaults and cross-service orchestration** - `2e878e6` (refactor)
3. **Task 3: Finalize the import-only directory and remove legacy aggregates** - `d2cee75` (refactor)

## Files Created/Modified

- `hosts/ser8/media/deployment-helpers.sh` - Contains only the complete `configure_arr` deployment function under strict mode.
- `hosts/ser8/media/orchestration-helpers.sh` - Contains readiness, idempotent registration, and sanitized API functions under strict mode.
- `hosts/ser8/media/sops.nix` - Defines only the shared SOPS file, format, and host age-key defaults.
- `hosts/ser8/media/orchestration.nix` - Owns the stable deployment unit, setup units, and media target.
- `hosts/ser8/media/default.nix` - Imports exactly the shared support, seven active service slices, and orchestration.
- `scripts/validation/check-ser8-media-parity.sh` - Normalizes only the old and approved split helper store filenames.
- `scripts/validation/ser8-media-projection.nix` - Selects existing media secret metadata so approved removals can be compared without weakening active projections.
- `hosts/ser8/media.nix` - Deleted after all active responsibilities moved.
- `hosts/ser8/systemd_helpers.sh` - Deleted after all source expressions used the split helpers.

## Decisions Made

- Shared SOPS policy remains limited to defaults, with every active secret and template retained by its service owner.
- Stable systemd unit names and dependency fields remain the public contract, independent of source-file ownership.
- Helper path normalization accepts only `systemd_helpers.sh`, `deployment-helpers.sh`, and `orchestration-helpers.sh` store basenames.
- The parity projection tolerates missing inventory entries only for declarations removed by the approved cleanup.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Corrected helper store-path normalization**

- **Found during:** Task 2
- **Issue:** The parity runner normalized a source-tree-shaped helper path, but evaluated scripts used direct Nix store basenames and therefore reported only the approved helper split as a mismatch.
- **Fix:** Matched the old combined helper and the two approved split helper basenames with one exact allowlist expression.
- **Files modified:** `scripts/validation/check-ser8-media-parity.sh`
- **Verification:** The normalized projection passed with no remaining generated-script or unit delta.
- **Committed in:** `2e878e6`

**2. [Rule 1 - Bug] Made planned secret removal evaluable**

- **Found during:** Task 3
- **Issue:** The projection selected the two removed AllDebrid declarations strictly before the comparison layer could remove them, so evaluation failed instead of validating the approved absence.
- **Fix:** Added an existing-secret selector for the secret inventory only; active service, template, unit, exporter, account, and firewall projections remain strict.
- **Files modified:** `scripts/validation/ser8-media-projection.nix`
- **Verification:** The post-deletion normalized projection matched the baseline and the final build passed.
- **Committed in:** `d2cee75`

**Total deviations:** 2 auto-fixed issues (1 blocking validation issue and 1 validation bug).

**Impact:** Both fixes make the locked helper split and AllDebrid cleanup verifiable without widening the accepted behavior delta.

## Issues Encountered

- The sandbox denied access to the normal user configuration and GPG keyring.
Nix verification ran with `HOME` unset, and commits retained normal hooks with signing disabled per commit.
- The Home Manager 25.05 versus Nixpkgs 25.11 warning remained the exact user-approved baseline.
No changed or additional warning was accepted by the build gate.
- The initial shfmt invocation used a two-space override, while the repository check uses shfmt defaults.
Both new helper files were reformatted with the repository default and then produced no shfmt output.

## Known Stubs

- `hosts/ser8/media/orchestration.nix` retains the pre-existing commented qBittorrent readiness probe.
It is intentionally preserved for behavior parity and does not prevent the existing qBittorrent registration flow from being built or evaluated.

## User Setup Required

None - encrypted SOPS sources were not edited and no live activation was performed.

## Verification

- ShellCheck and `shfmt -d` passed for both split helpers and the parity runner.
- `nixfmt --check` and statix passed for every host media Nix file, the ser8 entry point, and the parity projection.
- Structural assertions confirmed both legacy files are absent and the import-only entry point lists exactly nine focused modules.
- Normalized evaluated parity matched the captured baseline with only the approved Sawnia, AllDebrid, and helper-path deltas.
- Sanitization assertions covered query parameters, passwords, authenticated URLs, headers, JSON fields, stderr, and returned error bodies.
- `scripts/validation/check-ser8-media-parity.sh run-clean make build-ser8` passed and produced `/nix/store/1yz9cwywa38mj7bmhm0rcimzh5435kdx-nixos-system-ser8-25.11.20260518.687f05a`.
- No live activation was performed.

## Next Phase Readiness

- Plan 06 can audit and remove dead reusable media modules without any remaining host aggregate ownership.
- The final host media tree has explicit service, shared-support, orchestration, and helper boundaries.
- The user-owned config migration, encrypted secret changes, and phase `.gitkeep` remain outside Plan 05 commits.

## Self-Check: PASSED

- All four created support files exist and both intended legacy files are absent.
- Commits `6e09102`, `2e878e6`, and `d2cee75` exist in git history.
- Every task acceptance criterion, high-severity threat mitigation, and plan-level verification command passed.
- No unplanned network endpoint, authentication path, file-access boundary, or schema change was introduced.
- Unrelated user-owned changes remain uncommitted.

---
*Phase: 08-reorganize-ser8-media-nix-into-per-service-modules*
*Completed: 2026-07-25*
