---
phase: 12-fleet-repair
plan: 01
subsystem: infra
tags: [nixos, users, identity, chown, ser8, media, sabnzbd]

requires: []
provides:
  - "Verified fact: live ser8 media user/group is already uid 1100 / gid 992... correction: uid 1100 / gid 1100, matching modules/common/users.nix exactly - no reconciliation needed"
  - "Corrected PROJECT.md Key Decisions record superseding the original (incorrect) D-07/D-08"
  - "Identity census (D-10) across jellyfin/sonarr/radarr/bazarr/sabnzbd/nzbget: zero drift"
  - "18 stray files (uid 1002/755) chowned to media:media on ser8"
  - "Documented, deferred finding: 1,443 files / ~3.27 TiB owned by non-existent uid 38, correlated with FLEET-02's sabnzbd 38:194 drift"
affects: [12-02-sabnzbd-repair, 15-nixflix-migration]

actuals:
  tokens: 3800
  tasks: 2
  commits: 2

tech-stack:
  added: []
  patterns:
    - "Live pre-flight verification before any identity-declaration edit (getent passwd/group over SSH) catches stale planning assumptions before they cause a production collision"
    - "Scoped find by exact candidate uid (not a blind full-tree scan) keeps an ownership audit safely bounded"

key-files:
  created:
    - .planning/phases/12-fleet-repair/evidence/identity-audit.md
    - .planning/phases/12-fleet-repair/evidence/ownership-audit.md
  modified:
    - .planning/PROJECT.md

key-decisions:
  - "Abandoned the planned uid 1002 / gid 992 adoption for the media user/group: live ser8 already matches the repo's 1100/1100 declaration, and gid 992 belongs to the live mealie service group"
  - "Chowned 18 individually-reviewed stray files (uid 1002, uid 755) to media:media; excluded 5 macOS .DS_Store files as transient, continuously-regenerated artifacts"
  - "Deliberately left 1,443 files (~3.27 TiB) owned by non-existent uid 38 unfixed - fixing them would be the mass re-chown this plan's frontmatter explicitly prohibits; documented for a future decision, correlated with FLEET-02's sabnzbd 38:194 drift"

patterns-established:
  - "When a plan's core premise depends on a live-system fact, verify that fact via the plan's own pre-flight step before editing anything, and treat a contradiction as a blocking checkpoint, not something to auto-fix"

requirements-completed: [FLEET-03]

coverage:
  - id: D1
    description: "Live ser8 media identity verified against the repo's modules/common/users.nix declaration; no code change needed since they already match"
    requirement: "FLEET-03"
    verification:
      - kind: manual_procedural
        ref: "ssh bdhill@192.168.68.65 'id media' reports uid=1100 gid=1100, matching modules/common/users.nix"
        status: pass
    human_judgment: false
  - id: D2
    description: "Extended identity census (D-10) across jellyfin/sonarr/radarr/bazarr/sabnzbd/nzbget recorded in evidence/identity-audit.md"
    requirement: "FLEET-03"
    verification:
      - kind: manual_procedural
        ref: ".planning/phases/12-fleet-repair/evidence/identity-audit.md"
        status: pass
    human_judgment: false
  - id: D3
    description: "Scoped ownership audit (D-09): 18 stray files individually reviewed and chowned to media:media; large uid-38 finding documented and deliberately deferred"
    requirement: "FLEET-03"
    verification:
      - kind: manual_procedural
        ref: ".planning/phases/12-fleet-repair/evidence/ownership-audit.md"
        status: pass
    human_judgment: true
    rationale: "The decision to defer the 1,443-file/3.27 TiB uid-38 finding rather than chown it was made under explicit human direction (checkpoint Option A) but the follow-up disposition (fold into plan 12-02, or a dedicated future plan) is still open and needs human confirmation at the next relevant phase boundary."

duration: 35min
completed: 2026-08-24
status: complete
---

# Phase 12 Plan 1: Media Identity Reconciliation (Corrected Premise) Summary

**Live ser8 media identity already matched the repo (1100/1100); the planned uid 1002/gid 992 adoption was abandoned as unnecessary and unsafe, replaced with a small targeted ownership cleanup (18 files) plus a documented, deliberately-deferred 3.27 TiB finding.**

## Performance

- **Duration:** ~35 min (including a mid-plan human checkpoint)
- **Started:** 2026-08-23T23:42:00Z (approx, plan read/context load)
- **Completed:** 2026-08-24T00:55:00Z
- **Tasks:** 2 of 3 original tasks executed as commits (Task 1 became a no-op discovery finding, folded into Task 3's commit and this summary rather than its own commit, since no file changed for it)
- **Files modified:** 3 (2 created, 1 modified)

## Accomplishments

- Verified via live SSH pre-flight (mandated by the plan's own Task 1 action) that ser8's `media` user/group is already uid 1100 / gid 1100 — exactly matching `modules/common/users.nix`. The plan's founding premise (D-07/D-08: live is 1002/992, repo is stale at 1100/1100) was factually wrong.
- Discovered gid 992 belongs to the live `mealie` household-app group — adopting it for `media` would have collided with an active, unrelated service.
- Completed the extended identity census (D-10) across jellyfin, sonarr, radarr, bazarr, sabnzbd, and nzbget: zero identity drift found; every service's primary group is `media` (1100) as declared.
- Completed a scoped ownership audit (D-09) targeting the actual anomalies found (not the abandoned 1002/992 target): 18 stray files owned by uid 1002 or uid 755 were individually reviewed and chowned to `media:media`. One of them (a PDF under `/mnt/media/books`) had a genuine `group=mealie` mismatch, now corrected.
- Found and documented, but deliberately did NOT fix, a much larger anomaly: 1,443 files (~3.27 TiB) owned by non-existent uid 38, spanning roughly 120 movies/shows. This correlates strongly with FLEET-02's already-tracked `sabnzbd` 38:194 state-directory drift (`/var/lib/sabnzbd` has 1,258 files at uid 38 and 1,262 at gid 194) — likely a shared historical origin. Fixing it here would be the mass re-chown this plan's frontmatter explicitly prohibits.
- Corrected `.planning/PROJECT.md`'s Key Decisions table to record the verified facts in place of the original (incorrect) D-07/D-08 entry.

## Task Commits

The plan's original three tasks were re-scoped mid-execution per a human checkpoint decision (see Deviations). Two commits resulted:

1. **Task 2: Extended identity census (D-10)** - `e9a039a` (docs)
2. **Task 3 (re-scoped): Ownership audit, targeted chown, and PROJECT.md correction (D-09/D-06)** - `7458615` (fix)

Task 1 ("Declare live media identity and activate on ser8") produced no file change — the pre-flight check it mandated is what surfaced the false premise, so there was nothing to commit for it as originally scoped. Its finding is documented in both evidence files and the PROJECT.md correction above.

**Plan metadata:** commit pending (this SUMMARY + STATE.md + ROADMAP.md)

## Files Created/Modified

- `.planning/phases/12-fleet-repair/evidence/identity-audit.md` - D-10 census: six services + shared media group, zero drift, plus the premise-correction writeup
- `.planning/phases/12-fleet-repair/evidence/ownership-audit.md` - D-09 audit: 18 files chowned with before/after table, plus the deferred uid-38 finding and its FLEET-02 correlation
- `.planning/PROJECT.md` - Key Decisions table: new row correcting D-07/D-08

`modules/common/users.nix` was explicitly NOT modified — this is the core deviation from the plan (see below).

## Decisions Made

- **Abandoned the uid 1002 / gid 992 identity adoption entirely.** Live already matches the repo (1100/1100); adopting 1002/992 would have both been unnecessary and would have collided with the live `mealie` group's gid 992. Recorded via human checkpoint decision (Option A).
- **Chowned only the specific, individually-reviewed small-scope files** (18 total, uid 1002 and uid 755) rather than any file matching the abandoned 1002/992 criterion, since that criterion no longer meant anything on this host.
- **Excluded 5 macOS `.DS_Store` files from the uid-1002 fix.** They are continuously regenerated by an actively-mounted macOS Samba client during this very session (confirmed by the candidate list shifting between two read-only passes) and provide no lasting value if chowned.
- **Declined to chow uid-38's 1,443 files (~3.27 TiB).** The plan's own frontmatter prohibits a mass/full-tree re-chown; this volume qualifies as one even though it was reached via a scoped-by-uid `find`, not a blind traversal. Documented instead, with a strong correlation flagged for FLEET-02 (plan 12-02).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 4 - Architectural/Factual Premise Correction] Abandoned the planned uid 1002 / gid 992 media identity change**
- **Found during:** Task 1's mandated pre-flight collision check (`getent passwd 1002; getent group 992` against live ser8, plus `grep` of the repo)
- **Issue:** The plan's founding decision (D-07/D-08 in PROJECT.md, sourced from STATE.md's Deferred Items) asserted live ser8 already used uid 1002 / gid 992 for the media user/group. Live verification showed the opposite: `id media` on ser8 returns `uid=1100 gid=1100`, exactly matching the repo's current declaration. `getent group 992` resolves to `mealie`, a live, unrelated household-app group — adopting gid 992 for media would have caused a gid collision with an active service.
- **This is not something Rules 1-3 cover** — it directly contradicts an explicit, `flagged: true` plan constraint and the plan's own acceptance criteria (`getent group 992` returning exactly one line that is the media group — which is now known to be impossible without first evicting mealie). Per the deviation rules' Rule 4 guidance and the instruction to halt on architectural-scale mismatches, this was raised to the coordinator as a `checkpoint:decision` before any file was edited.
- **Resolution:** Coordinator selected Option A — abandon the identity change, re-scope Task 3's audit mechanism to the actual findings, and correct PROJECT.md.
- **Fix:** No edit to `modules/common/users.nix`. PROJECT.md's Key Decisions table corrected. Evidence files record the verified facts.
- **Files modified:** `.planning/PROJECT.md`, `.planning/phases/12-fleet-repair/evidence/identity-audit.md`, `.planning/phases/12-fleet-repair/evidence/ownership-audit.md`
- **Verification:** `ssh bdhill@192.168.68.65 'id media'` — confirmed uid=1100/gid=1100 both before and after this plan (no change made, none needed)
- **Committed in:** `e9a039a`, `7458615`

**2. [Rule 4 - Scope Boundary Held] Declined to chown the 1,443-file / ~3.27 TiB uid-38 finding**
- **Found during:** Task 3's re-scoped ownership audit, after an initial spot-sample under-reported this as "dozens of files" (the coordinator's Option A directive was based on that under-count)
- **Issue:** A full, read-only, uid-scoped `find` revealed the true scope: 1,443 files across ~120 movies/shows, ~3.27 TiB, correlated with FLEET-02's already-known sabnzbd 38:194 drift. Chowning this set would functionally be the mass re-chown this plan's frontmatter explicitly prohibits (`Must not perform a blind recursive re-chown of the media tree ... or any full-tree census`), even though the `find` itself was scoped by uid criteria rather than blind.
- **Fix:** No chown performed on this set. Fully documented in `evidence/ownership-audit.md` with the FLEET-02 correlation, flagged for a follow-up decision (either folded into plan 12-02's sabnzbd diagnosis, D-11, or a dedicated future plan).
- **Files modified:** `.planning/phases/12-fleet-repair/evidence/ownership-audit.md` (documentation only; no target files touched)
- **Verification:** `find /mnt/media -uid 38 -type f | wc -l` re-confirmed at 1,443 immediately before this summary was written; no chown was issued against any of them.
- **Committed in:** `7458615`

---

**Total deviations:** 2 (both Rule 4 - premise correction and scope-boundary enforcement, both surfaced to and resolved by the human coordinator before any risky action)
**Impact on plan:** No `modules/common/users.nix` change was made (none was needed or safe). The plan's D-09 ownership-audit mechanism was reused successfully against the real findings instead of the abandoned target. FLEET-03's requirement is satisfied: the repo's media identity is verified reconciled with live ser8 (they already matched), with no blind recursive re-chown performed at any point.

## Issues Encountered

- The live `/mnt/media` Samba share was actively mounted by a macOS client during this audit, causing `.DS_Store` file counts to shift between separate read-only `find` invocations. Resolved by taking one final, immediately-pre-chown snapshot and explicitly excluding `.DS_Store` paths from remediation (they are Finder housekeeping artifacts, not identity drift).
- An initial `maxdepth`-limited sample under-reported the uid-38 finding as "dozens of files" when the true count was 1,443 files / ~3.27 TiB. This was caught before any chown was issued against that set by re-running a full (still read-only, still scoped-by-uid) count immediately before acting, and the corrected number is what's documented and deferred.

## User Setup Required

None - no external service configuration required. All work was infrastructure verification and targeted file-ownership correction on ser8, plus documentation.

## Next Phase Readiness

- FLEET-03 is complete: media identity is verified reconciled (no drift existed to begin with), extended census is recorded, and the scoped ownership audit's small findings are fixed.
- Plan 12-02 (SABnzbd repair, FLEET-02) should review `evidence/ownership-audit.md`'s uid-38 correlation before finalizing its own diagnosis (D-11) — the `/mnt/media` uid-38 finding (1,443 files, 3.27 TiB) and `/var/lib/sabnzbd`'s uid-38/gid-194 drift look related, and 12-02's root-cause finding may explain (and potentially resolve) both.
- Phase 15's Nixflix adapter should consult `evidence/identity-audit.md` for each service's current live uid, since none are pinned in Nix (all NixOS-auto-allocated).

---
*Phase: 12-fleet-repair*
*Completed: 2026-08-24*
