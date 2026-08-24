---
phase: 12-fleet-repair
plan: 03
subsystem: media
tags: [nixos, nordvpn, qbittorrent, deletion, monitoring, planning-docs]

# Dependency graph
requires:
  - phase: 12-fleet-repair
    provides: "Plan 12-01's corrected media identity (uid 1100/gid 1100) and Plan 12-02's sabnzbd uid pin, both left untouched by this plan's deletions"
provides:
  - "modules/nordvpn/, modules/media/qbittorrent.nix, hosts/ser8/media/qbittorrent.nix, scripts/smoketests/nordvpn/, and scripts/sops/gen-hash-qbittorrent.py fully deleted from the repository"
  - "Every eval-critical consumer of the deleted modules fixed in the same pass: flake.nix's ser8 module list, host wiring, orchestration scripts, permissions assertions, impermanence rules, monitoring/blackbox probes"
  - "REQUIREMENTS.md and ROADMAP.md rescoped to describe a usenet-only download path (FLEET-01, BKP-07, NIX-03, NIX-05, Phase 12-15 success criteria)"
  - "make dry-activate-ser8 and make check both green with no NordVPN/qBittorrent module namespace remaining anywhere in evaluated configuration"
affects: [12-04-deploy-removal-to-ser8, 13-zfs-mirror-migration, 14-backup-engine, 15-nixflix-migration]

# Actuals (#2632)
actuals:
  tokens: 10500
  tasks: 3
  commits: 3

tech-stack:
  added: []
  patterns:
    - "flake.nix's per-host `modules` list is itself an eval-critical consumer of a deleted module directory — not just the module's own default.nix imports; must be checked alongside modules/media/default.nix and hosts/ser8/media/default.nix whenever a top-level module directory is removed"

key-files:
  created: []
  modified:
    - flake.nix
    - modules/media/default.nix
    - hosts/ser8/media/default.nix
    - hosts/ser8/configuration.nix
    - hosts/ser8/media/orchestration.nix
    - hosts/ser8/media/orchestration-helpers.sh
    - hosts/ser8/media/permissions.nix
    - hosts/ser8/impermanence.nix
    - scripts/smoketests/ser8/all.sh
    - scripts/smoketests/media/all.sh
    - Makefile
    - modules/servers/monitoring.nix
    - modules/gateway/prometheus.nix
    - .planning/REQUIREMENTS.md
    - .planning/ROADMAP.md

key-decisions:
  - "flake.nix's `./modules/nordvpn` entry in ser8's module list was not in the plan's files_modified list but is an eval-critical dangling reference once the directory is deleted — fixed as a Rule 3 blocking-issue auto-fix, since make dry-activate-ser8 failed outright without it (Path 'modules/nordvpn' does not exist in Git repository)"
  - "Left NIX-01's qBittorrent mention, the Trust Boundaries context-table qBittorrent reference, Phase 12's title bullet ('wgnord/qBittorrent loop'), and the 12-03/12-05 plan-title bullets in ROADMAP.md untouched — D-05's scope (per 12-CONTEXT.md) is explicitly 'FLEET-01 text' and 'Phase 12 success criteria plus the stale qBittorrent references in Phases 13-15 details,' not a wholesale rewrite of every qBittorrent mention in either planning doc"

requirements-completed: [FLEET-01]

coverage:
  - id: D1
    description: "modules/nordvpn/, modules/media/qbittorrent.nix, hosts/ser8/media/qbittorrent.nix deleted; every eval-critical consumer (flake.nix, import lists, configuration.nix, orchestration.nix/helpers, permissions.nix) fixed in the same pass"
    requirement: FLEET-01
    verification:
      - kind: automated
        ref: "make dry-activate-ser8 -> exit 0"
        status: pass
    human_judgment: false
  - id: D2
    description: "Persistence rules, NordVPN smoketests, and orphaned Makefile/script residue retired without touching on-disk /mnt/media/downloads data (D-04)"
    requirement: FLEET-01
    verification:
      - kind: automated
        ref: "test -d scripts/smoketests/nordvpn (fails), grep -c qbittorrent across impermanence.nix/ser8/all.sh/media/all.sh/Makefile (all 0), shfmt -d (clean)"
        status: pass
    human_judgment: false
  - id: D3
    description: "Cross-host monitoring/blackbox probes cleaned and REQUIREMENTS.md/ROADMAP.md rescoped to usenet-only per D-05"
    requirement: FLEET-01
    verification:
      - kind: automated
        ref: "make check -> exit 0 (all four hosts evaluate cleanly)"
        status: pass
    human_judgment: false

duration: ~40min
completed: 2026-08-24
status: complete
---

# Phase 12 Plan 3: Delete NordVPN/qBittorrent Stack and Rescope Docs Summary

**Deleted the entire NordVPN + qBittorrent stack (modules, host wiring, orchestration scripts, smoketests, monitoring probes) and rewrote REQUIREMENTS.md/ROADMAP.md to describe a usenet-only download path, with `make dry-activate-ser8` and `make check` both green.**

## Performance

- **Duration:** ~40 min
- **Tasks:** 3
- **Files modified:** 30 (12 deleted, 18 modified/edited across code and planning docs)

## Accomplishments

- Deleted `modules/nordvpn/` (default.nix, service.nix, template.conf), `modules/media/qbittorrent.nix`, and `hosts/ser8/media/qbittorrent.nix`, then fixed every eval-critical consumer in the same pass: import lists in `modules/media/default.nix` and `hosts/ser8/media/default.nix`, the `nordvpn_access_token` secret and `nordvpn` enable block in `hosts/ser8/configuration.nix`, and — critically — `flake.nix`'s own `./modules/nordvpn` entry in ser8's module list, which the plan's file list missed but which broke `make dry-activate-ser8` outright until fixed
- Stripped qBittorrent wiring from `hosts/ser8/media/orchestration.nix` (description text, `after` list, the two `setup_qbittorrent_client` calls) and deleted the now-callerless `setup_qbittorrent_client()` function from `hosts/ser8/media/orchestration-helpers.sh`; removed `"qbittorrent"`/`"qbittorrent-nox.service"` from `hosts/ser8/media/permissions.nix`'s `mediaAccounts`/`mediaServices` lists
- Removed qBittorrent persistence/tmpfiles entries from `hosts/ser8/impermanence.nix` without touching any on-disk `/mnt/media/downloads` data (per D-04); deleted `scripts/smoketests/nordvpn/` (8 files), the `sops-gen-hash-qbittorrent` Makefile target, and the orphaned `scripts/sops/gen-hash-qbittorrent.py`; scrubbed qBittorrent entries from both `scripts/smoketests/ser8/all.sh` and `scripts/smoketests/media/all.sh`
- Removed the `qbittorrent-nox.service` monitored unit and the `qbittorrent` process-exporter entry from `modules/servers/monitoring.nix` (fleet-wide, all four hosts), and the qBittorrent blackbox-http probe target from `modules/gateway/prometheus.nix` (firebat) that would otherwise alert permanently on a deleted endpoint
- Rewrote FLEET-01, BKP-07, NIX-03, and NIX-05 in `.planning/REQUIREMENTS.md`, and Phase 12's success criterion 1, Phase 13's criterion 4, Phase 14's criterion 2, and Phase 15's criteria 3-4 in `.planning/ROADMAP.md`, to describe the usenet-only (SABnzbd/NZBGet) download path instead of active torrent/qBittorrent service text
- Verified end-to-end: `make dry-activate-ser8` exits 0 after Task 1; `make check` (all four hosts, flake check, statix) exits 0 after Task 3

## Task Commits

Each task was committed atomically:

1. **Task 1: Delete NordVPN/qBittorrent modules and fix every eval-critical consumer** - `68d9feb` (feat)
2. **Task 2: Retire persistence rules, NordVPN smoketests, and orphaned Makefile/script residue** - `8d87230` (chore)
3. **Task 3: Clean cross-host monitoring/blackbox probes and rescope planning docs (D-05)** - `b17a731` (docs)

**Plan metadata:** (this commit)

## Files Created/Modified

- `flake.nix` - Removed `./modules/nordvpn` from ser8's module list (dangling reference discovered via `make dry-activate-ser8` failure; not in the plan's original file list)
- `modules/media/default.nix`, `hosts/ser8/media/default.nix` - Removed `./qbittorrent.nix` from `imports`
- `hosts/ser8/configuration.nix` - Removed `nordvpn_access_token` secret and the `nordvpn` enable block
- `hosts/ser8/media/orchestration.nix`, `hosts/ser8/media/orchestration-helpers.sh` - Stripped qBittorrent wiring and deleted `setup_qbittorrent_client()`
- `hosts/ser8/media/permissions.nix` - Removed `qbittorrent`/`qbittorrent-nox.service` from `mediaAccounts`/`mediaServices`
- `hosts/ser8/impermanence.nix` - Removed qBittorrent persistence/tmpfiles entries (on-disk data untouched per D-04)
- `scripts/smoketests/ser8/all.sh`, `scripts/smoketests/media/all.sh` - Removed the nordvpn suite entry and qBittorrent service/account entries
- `Makefile` - Removed `sops-gen-hash-qbittorrent` target and its help line
- `modules/servers/monitoring.nix`, `modules/gateway/prometheus.nix` - Removed qBittorrent monitored unit, process-exporter entry, and blackbox probe target
- `.planning/REQUIREMENTS.md`, `.planning/ROADMAP.md` - Rescoped FLEET-01/BKP-07/NIX-03/NIX-05 and Phase 12-15 success criteria to usenet-only language (D-05)

Deleted entirely: `modules/nordvpn/` (3 files), `modules/media/qbittorrent.nix`, `hosts/ser8/media/qbittorrent.nix`, `scripts/smoketests/nordvpn/` (8 files), `scripts/sops/gen-hash-qbittorrent.py`.

## Decisions Made

- **flake.nix's own module reference was the actual root cause of the first dry-activate failure** — the plan's Task 1 file list enumerated every downstream consumer inside `modules/` and `hosts/ser8/` but not `flake.nix` itself, which independently lists `./modules/nordvpn` in ser8's `modules = [ ... ]` array. Deleting the directory without this fix produced `error: Path 'modules/nordvpn' does not exist in Git repository`, a hard evaluation failure distinct from any option-namespace error. Fixed as a Rule 3 (blocking issue) auto-fix in Task 1's commit, verified by re-running `make dry-activate-ser8` to exit 0.
- **D-05's doc-rescope scope taken literally, not expanded** — `.planning/REQUIREMENTS.md` still contains "qBittorrent" in NIX-01 (Nixflix's VPN/qBittorrent service management staying disabled) and in the Trust Boundaries context table; `.planning/ROADMAP.md` still contains it in Phase 12's title bullet and the 12-03/12-05 plan-title bullets. Per 12-CONTEXT.md, D-05's scope is explicitly "FLEET-01 text" and "Phase 12 success criteria plus the stale qBittorrent references in Phases 13-15 details" — not every occurrence in either file. The plan's own action text names exactly the fields edited here (FLEET-01, BKP-07, NIX-03, NIX-05, and four specific ROADMAP success criteria), instructing scoped `Edit` calls rather than a wholesale rewrite; those untouched lines are the ones D-05 was never scoped to touch.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking issue] flake.nix's `./modules/nordvpn` entry was a dangling reference not listed in the plan's files**
- **Found during:** Task 1, first `make dry-activate-ser8` run
- **Issue:** `flake.nix` independently lists `./modules/nordvpn` in ser8's `modules = [ ... ]` array (line ~200), separate from the `modules/media/default.nix`/`hosts/ser8/media/default.nix` import lists the plan enumerated. Deleting `modules/nordvpn/` without fixing this produced a hard eval failure: `error: Path 'modules/nordvpn' does not exist in Git repository`.
- **Fix:** Removed the `./modules/nordvpn` line from ser8's module list in `flake.nix`.
- **Files modified:** `flake.nix`
- **Verification:** Re-ran `make dry-activate-ser8`; exited 0.
- **Committed in:** `68d9feb`

**2. [Scope Boundary - deferred, not fixed] Pre-existing shellcheck SC2034/SC1091 findings on modified smoketest fan-out scripts**
- **Found during:** Task 2's `<verify>` step
- **Issue:** `shellcheck scripts/smoketests/ser8/all.sh scripts/smoketests/media/all.sh` exits 1 (SC2034 "`SUITE_NAME`/`TESTS` appears unused", SC1091 info on sourced libs not being followed without `-x`). Confirmed via `git show` and cross-checking `scripts/smoketests/gateway/all.sh`/`household/all.sh` (both untouched by this plan) that this is a pre-existing, repo-wide pattern in every `scripts/smoketests/*/all.sh` fan-out entry point, not something introduced by removing the qBittorrent/nordvpn entries. Not enforced by `make check` (no shellcheck target exists there).
- **Action:** Left unfixed per the Scope Boundary rule (only auto-fix issues directly caused by this task's changes). Logged to `.planning/phases/12-fleet-repair/deferred-items.md`. `shfmt -d` on both files is clean.
- **Files modified:** None (documentation only, in `deferred-items.md`)
- **Committed in:** `8d87230`

---

**Total deviations:** 2 (1 Rule 3 auto-fix, 1 scope-boundary deferral)
**Impact on plan:** The Rule 3 fix was required for Task 1's own acceptance criterion (`make dry-activate-ser8` exits 0) to pass at all. The deferred shellcheck finding does not block any of this plan's must_haves or the phase's success criteria; it is pre-existing and repo-wide.

## Issues Encountered

- The plan's Task 2/Task 3 acceptance-criteria checklists assert `grep -c 'qbittorrent\|qBittorrent' .planning/REQUIREMENTS.md` and the equivalent for `.planning/ROADMAP.md` both return `0`, but D-05's actual scope (per 12-CONTEXT.md and the task's own `<action>` text) only names specific requirement IDs and success-criteria lines. Followed the scoped `<action>` instructions as the source of truth rather than the broader grep-based acceptance check; see Decisions Made above for the exact remaining references and why they're out of scope.

## User Setup Required

None — no external service configuration required. This plan only removes code, wiring, and doc text; the live ser8 deployment of this removal (secrets, running services) is Plan 12-04's scope.

## Next Phase Readiness

- FLEET-01's code-side half is complete: no dangling reference to `modules.nordvpn`, `config.services.qbittorrent-nox`, or the deleted SOPS secret paths remains anywhere in the evaluated configuration; `make dry-activate-ser8` and `make check` are both green.
- Plan 12-04 (deploy the removal to ser8, archive-then-delete live state, remove secrets) can proceed — this plan's repo-side deletions are the prerequisite for that live cutover.
- Plan 12-05 (clean Radarr root folders, de-register dead qBittorrent download clients from the arr apps' own state) is independent of this plan's code changes and remains blocked on Wave 2 (12-04) per the roadmap's wave ordering.

## Known Stubs

None.

## Threat Flags

None — this plan only removes surface (module, service, probe, doc text); no new network endpoints, auth paths, or trust-boundary-crossing code was introduced.

---
*Phase: 12-fleet-repair*
*Completed: 2026-08-24*

## Self-Check: PASSED

- FOUND: `flake.nix`, `modules/media/default.nix`, `hosts/ser8/media/default.nix`, `hosts/ser8/configuration.nix`, `hosts/ser8/media/orchestration.nix`, `hosts/ser8/media/orchestration-helpers.sh`, `hosts/ser8/media/permissions.nix`, `hosts/ser8/impermanence.nix`, `scripts/smoketests/ser8/all.sh`, `scripts/smoketests/media/all.sh`, `Makefile`, `modules/servers/monitoring.nix`, `modules/gateway/prometheus.nix`, `.planning/REQUIREMENTS.md`, `.planning/ROADMAP.md`, `.planning/phases/12-fleet-repair/deferred-items.md`
- FOUND (correctly deleted): `modules/nordvpn/`, `scripts/smoketests/nordvpn/`
- FOUND commit: `68d9feb` (Task 1)
- FOUND commit: `8d87230` (Task 2)
- FOUND commit: `b17a731` (Task 3)
