---
phase: 11-homebox-actual-budget-and-donetick
plan: 06
subsystem: infra
tags: [nixos, zfs, impermanence, sqlite, reboot, smoketest]

# Dependency graph
requires:
  - phase: 11-01
    provides: "Homebox live on ser8 with jordan+sawnia sharing one group, persisted SQLite"
  - phase: 11-02
    provides: "Actual live on ser8 with a persisted, unencrypted budget file"
  - phase: 11-03
    provides: "Direct-SQL proof that exactly one unencrypted budget file exists in Actual's account.sqlite"
  - phase: 11-04
    provides: "Donetick packaged and live on ser8, persisted SQLite"
  - phase: 11-05
    provides: "Donetick jordan+sawnia bootstrapped into one circle, gateway vhost live, 8/8 household smoketests"
provides:
  - "Real, value-level proof (not configuration inference) that Homebox, Actual, and Donetick all survive a live ser8 reboot -- group/circle membership and the single budget file are bit-for-bit identical pre/post"
  - "Dated evidence file under baseline/ recording the full pre/post snapshot comparison"
  - "Confirmation that the full ser8 smoketest suite's household area (8/8, all six new Phase 11 scripts) passes against post-reboot state"
affects: [Phase 11 exit, ROADMAP.md Success Criterion 3]

# Actuals (#2632)
actuals:
  tokens: 2700
  tasks: 1
  commits: 1

tech-stack:
  added: []
  patterns:
    - "When no live API token is available and cannot be safely obtained (household passwords are shown once at bootstrap and never stored, per this phase's own security policy), query the same SQLite database the service's own API reads from directly -- mirrors the technique the plan already specified for Actual, extended here to Homebox and Donetick for consistency and to avoid needing any credential at all for a pure persistence check."
    - "scripts/nixos-rebuild.sh's reboot action gates on an interactive confirm() prompt with no TTY-detection bypass other than NO_CONFIRM=true, and its own post-reboot SSH-retry loop budgets only ~51s -- too short for a real BIOS-to-userspace cycle. A non-interactive reboot drill needs NO_CONFIRM=true for the confirm gate, and needs the operator (human or agent) to poll SSH reachability independently and patiently rather than trusting the wrapper's own retry loop to signal success or failure of the reboot itself."

key-files:
  created:
    - .planning/phases/11-homebox-actual-budget-and-donetick/baseline/reboot-2026-08-22.md
  modified:
    - .planning/phases/11-homebox-actual-budget-and-donetick/deferred-items.md

key-decisions:
  - "Verified Homebox and Donetick's group/circle membership via direct SQL against their own SQLite databases rather than a live bearer-token API call, because no household member's password exists anywhere in this repository or session state by explicit prior-plan policy -- mirrors the technique the plan itself specified for Actual and requires zero credentials for a pure persistence check"
  - "Did not retry the destructive reboot action when the wrapper script's own SSH-retry loop timed out after ~51s -- the sudo reboot had already been issued and ser8 was legitimately rebooting; instead polled SSH reachability independently with patience (15s intervals) and ran make smoketests-ser8 directly once the host was back, completing the same verification the wrapper's own target would have run with a longer retry budget"
  - "Reported the plan's literal make reboot-test-ser8 exits 0 acceptance criterion as NOT MET, rather than silently treating a partial pass as a pass -- the failure is entirely attributable to the pre-existing, already-documented NordVPN suite (STATE.md, predating Phase 9), confirmed by an identical failure signature and zero new regressions, and is logged to deferred-items.md rather than fixed, per the scope boundary rule"

patterns-established:
  - "A live reboot drill on ser8 needs NO_CONFIRM=true (the wrapper's confirm() gate has no other non-interactive bypass) and independent SSH polling beyond the wrapper's own ~51s retry budget -- future reboot-test-HOST invocations from an agent session should expect the same two adjustments"

requirements-completed: [HBX-01, ACT-01, DTK-02]

coverage:
  - id: D1
    description: "Homebox's group membership (jordan+sawnia, same group id) is identical before and after a real ser8 reboot"
    requirement: "HBX-01"
    verification:
      - kind: integration
        ref: "direct SQL against /var/lib/homebox/data/homebox.db: groups row d13364b6-611d-4273-aebb-daf7f4f0a915 and user_groups count=2 identical pre- and post-reboot (baseline/reboot-2026-08-22.md)"
        status: pass
    human_judgment: false
  - id: D2
    description: "Actual's account.sqlite files table still shows exactly one non-deleted, unencrypted budget file after a real ser8 reboot"
    requirement: "ACT-01"
    verification:
      - kind: integration
        ref: "direct SQL against /var/lib/actual/server-files/account.sqlite: file 0e8f929b-dcea-4b14-82c9-60d91c0c87b5, deleted=0, encrypt_keyid empty, identical pre- and post-reboot; test-actual-service.sh's ACT-02 check also passes post-reboot"
        status: pass
    human_judgment: false
  - id: D3
    description: "Donetick's circle membership (jordan+sawnia, same circle id, both active) is identical before and after a real ser8 reboot"
    requirement: "DTK-02"
    verification:
      - kind: integration
        ref: "direct SQL against /var/lib/donetick/donetick.db: circle_id=1 (Jordan's circle), 2 active members (jordan, sawnia), identical pre- and post-reboot (baseline/reboot-2026-08-22.md)"
        status: pass
    human_judgment: false
  - id: D4
    description: "All three services' /persist/var/lib/<svc> and bind-mounted /var/lib/<svc> directories exist with correct ownership immediately after the reboot, before any manual intervention"
    verification:
      - kind: integration
        ref: "stat -c '%U %G %a' on all six paths, both pre- and post-reboot: homebox:homebox 750, actual:actual 700, donetick:donetick 750, all identical"
        status: pass
    human_judgment: false
  - id: D5
    description: "The full ser8 household smoketest suite -- including all six new Phase 11 service/endpoint scripts -- passes against the post-reboot state"
    verification:
      - kind: integration
        ref: "scripts/smoketests/household/all.sh ser8, run after the reboot: 8/8 passed"
        status: pass
    human_judgment: false
  - id: D6
    description: "make reboot-test-ser8 exits 0 (the plan's literal top-level acceptance criterion)"
    verification:
      - kind: integration
        ref: "scripts/smoketests/ser8/all.sh post-reboot: 6/7 areas pass; nordvpn fails 2/4 (test-forwarding.sh, test-qbittorrent.sh), a pre-existing failure documented in STATE.md before Phase 9, unrelated to any Phase 11 app -- see deferred-items.md"
        status: fail
    human_judgment: true
    rationale: "The literal exit-0 criterion is not met, but the failure is fully attributed to a pre-existing, out-of-scope, already-documented NordVPN issue with an identical failure signature to prior STATE.md notes -- a human should confirm this attribution is acceptable for closing Phase 11 Success Criterion 3, since automation cannot itself judge whether a known unrelated defect should gate the phase."

duration: ~16min
completed: 2026-08-22
status: complete
---

# Phase 11 Plan 06: Reboot Persistence Verification Summary

**A real ser8 reboot proved Homebox's group, Actual's single budget file, and Donetick's circle are bit-for-bit identical before and after, and all six new household smoketests pass 8/8 post-reboot; the only smoketest failure was ser8's pre-existing, unrelated NordVPN tunnel issue.**

## Performance

- **Duration:** ~16 min (dominated by the actual reboot/boot cycle and patient SSH polling, not investigation)
- **Started:** 2026-08-22T07:42:00Z (approx, pre-reboot snapshot capture)
- **Completed:** 2026-08-22T07:57:56Z
- **Tasks:** 1/1
- **Files modified:** 2

## Accomplishments
- Captured a pre-reboot snapshot of all three apps' household-scoped state (Homebox group membership, Actual's single unencrypted budget file, Donetick circle membership) plus ownership/mode on both sides of each service's bind mount
- Issued a real `sudo reboot` against ser8 via `NO_CONFIRM=true make reboot-test-ser8` (the interactive `confirm()` gate needs the env var in a non-interactive session, matching this repo's documented convention for intentional non-interactive operations) and waited patiently for the host to come back rather than retrying the reboot itself when the wrapper script's own short retry budget timed out
- Re-captured the identical snapshot post-reboot: every value (group id, member count, file id, `encrypt_keyid`, circle id, active-member count, directory ownership/mode) matched exactly -- nothing was left UNVERIFIED
- Ran the full `household` smoketest suite post-reboot: 8/8 passed, covering all six new Phase 11 service/endpoint scripts plus the pre-existing Mealie pair
- Ran the full `ser8` smoketest suite post-reboot: 6/7 areas passed; the one failure (`nordvpn`, 2/4) is confirmed pre-existing and unrelated to any Phase 11 app, matching STATE.md's own notes recorded before Phase 9's channel bump, with zero new regressions from this reboot
- Logged the NordVPN gap to `deferred-items.md` rather than fixing it (out of this plan's scope) and reported the plan's literal `make reboot-test-ser8 exits 0` acceptance criterion as honestly unmet, rather than silently declaring a pass

## Task Commits

Each task was committed atomically:

1. **Task 1: Snapshot, reboot ser8 once, verify all three apps' state survived** - `25d7c58` (test)

**Plan metadata:** (this commit, below)

## Files Created/Modified
- `.planning/phases/11-homebox-actual-budget-and-donetick/baseline/reboot-2026-08-22.md` - full pre/post snapshot comparison, reboot procedure, and smoketest results
- `.planning/phases/11-homebox-actual-budget-and-donetick/deferred-items.md` - new entry documenting the pre-existing NordVPN failure and its lack of relationship to this plan

## Decisions Made
- Used direct SQL against Homebox's and Donetick's own SQLite databases instead of live bearer-token API calls, since no household password is retained anywhere per prior-plan policy (see key-decisions)
- Did not retry the reboot when the wrapper's own SSH-retry loop timed out first -- the reboot had already happened; polled SSH independently instead (see key-decisions)
- Reported the literal `make reboot-test-ser8 exits 0` criterion as unmet rather than treating the partial pass as a pass, attributing the gap precisely to the pre-existing NordVPN suite (see key-decisions and Deviations)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] No live API token available for Homebox/Donetick; substituted direct SQL, matching the plan's own technique for Actual**
- **Found during:** Task 1, before capturing the pre-reboot snapshot
- **Issue:** The plan's action text calls for `GET /api/v1/groups/members` (Homebox) and `GET /api/v1/circles/members` (Donetick) using "any valid token from plan 11-01/11-05." Per those plans' own SUMMARYs, jordan's and sawnia's passwords were displayed once in terminal output during bootstrap and deliberately never stored anywhere in this repository or session state -- there was no credential available to mint a fresh bearer token without either violating that stated security policy or attempting a live password-reset flow, which would itself be a state-mutating action inappropriate for a pure persistence check.
- **Fix:** Queried each app's own SQLite database directly (`/var/lib/homebox/data/homebox.db`'s `groups`/`user_groups` tables; `/var/lib/donetick/donetick.db`'s `circles`/`user_circles` tables), exactly mirroring the plan's own specified technique for Actual (`sqlite3 ... account.sqlite`). This reads the identical underlying state the API would return, requires root SSH access already available to the executor, and needs zero credentials.
- **Files modified:** none (read-only verification)
- **Verification:** Homebox: group `d13364b6-611d-4273-aebb-daf7f4f0a915`, 2 members, identical pre/post-reboot. Donetick: circle 1 ("Jordan's circle"), 2 active members (jordan, sawnia), identical pre/post-reboot. Both match the group/circle ids and member counts recorded in 11-01-SUMMARY.md and 11-05-SUMMARY.md.
- **Committed in:** `25d7c58`

**2. [Rule 3 - Blocking] The reboot wrapper's interactive confirm() gate and short SSH-retry budget required NO_CONFIRM plus independent patient polling**
- **Found during:** Task 1, first `make reboot-test-ser8` invocation
- **Issue:** `scripts/nixos-rebuild.sh`'s `reboot` action calls `nixos_confirm()`, which reads from a TTY via `read -p`; with no TTY in a non-interactive agent session this failed immediately with no reboot attempted. After adding `NO_CONFIRM=true` (this repo's documented, existing bypass for exactly this scenario, per `CLAUDE.md`: "`NO_CONFIRM=true` must only be used for intentional non-interactive operations" -- this plan's explicit, user-authorized purpose), the `sudo reboot` was issued successfully, but the script's own post-reboot SSH-retry loop (`~1s` initial sleep plus 10 retries at 5s intervals, `~51s` total budget) is far shorter than a real BIOS-to-userspace boot cycle takes, and the wrapper failed with `Host did not come back online after 10 attempts` before the host had actually finished booting.
- **Fix:** Did not re-run `sudo reboot` (the plan's own instruction: "do not panic-retry destructive actions"). Instead polled SSH reachability independently at 15s intervals; the host answered on the 3rd attempt (uptime `0:00`, confirming a genuine fresh boot), then ran `make smoketests-ser8` directly to complete the verification `reboot-test-ser8`'s own second half would have run.
- **Files modified:** none (no repository config changed; this is an operational technique, not a fix to `scripts/nixos-rebuild.sh` itself, which is out of this plan's scope)
- **Verification:** Host confirmed back online with a genuinely fresh uptime; the exact same NixOS generation (`nixos-system-ser8-26.05.20260817.0dd31db`) was running both before and after, confirming a clean reboot into the same, already-tested boot entry rather than an unexpected generation change.
- **Committed in:** `25d7c58` (documented in the evidence file; no config changed)

---

**Total deviations:** 2 auto-fixed, both Rule 3 (blocking issues resolved without changing the plan's actual verification intent)
**Impact on plan:** Neither deviation weakened what was actually proven -- the SQL substitution reads the same underlying state the specified API call would have returned, and the manual reboot-completion polling is the same reboot-test-ser8 sequence, just decomposed into its two halves because the wrapper script's own retry budget is too short for a real reboot. No scope creep -- no repository configuration files were touched by either fix.

## Issues Encountered
- `make reboot-test-ser8` (and its underlying `scripts/smoketests/ser8/all.sh`) does not literally exit 0 post-reboot, solely due to the `nordvpn` suite (2/4: `test-forwarding.sh` and `test-qbittorrent.sh` fail). This is confirmed pre-existing and unrelated to Phase 11: STATE.md's Blockers/Concerns already recorded "ser8 NordVPN tunnel down... confinement check and nordvpn suite cannot be observed green until restored" and "nordvpn/test-forwarding.sh still queries the retired pi4 resolver 192.168.68.56" before Phase 9's channel bump, with a byte-identical failure signature reproduced here (tunnel services all ACTIVE, veth/WireGuard interfaces up, qBittorrent namespace confinement itself still passing -- only external egress and the stale DNS target are broken). Logged to `deferred-items.md`, not fixed, per the scope boundary rule. This is the one item preventing an unqualified "criterion met" verdict on this plan's literal acceptance criteria; see the `coverage` D6 entry and `human_judgment: true` for why this needs a human's explicit sign-off to close ROADMAP.md Success Criterion 3 despite it.

## User Setup Required
None. This plan performed only read-only verification queries and one authorized reboot; no repository configuration or secrets changed.

## Next Phase Readiness
- ROADMAP.md Phase 11 Success Criterion 3 ("survives a ser8 reboot") is proven at the value level for all three apps with no UNVERIFIED app -- the household-scoped subject of this plan is fully closed
- The literal `make reboot-test-ser8 exits 0` bar remains blocked by the pre-existing NordVPN issue; a human decision is needed on whether Phase 11 can close with that known, unrelated, already-documented gap still open, or whether NordVPN restoration should be pulled forward as its own remediation before Phase 11 is considered fully exited
- Donetick's leftover single-user test circles (2, 3, 4, from `stranger1`/`stranger2`/an earlier duplicate Sawnia signup attempt during 11-05's bootstrap testing) are harmless but unused rows -- no action needed, noted here only so a future data-cleanup pass isn't surprised by them
- Nightly backup coverage for all three apps' SQLite databases remains unwired, matching every prior plan's note in this phase -- still expected with the phase's shared backup-engine work

## Self-Check: PASSED

Both created/modified files confirmed present on disk: `.planning/phases/11-homebox-actual-budget-and-donetick/baseline/reboot-2026-08-22.md` and `.planning/phases/11-homebox-actual-budget-and-donetick/deferred-items.md`. Commit `25d7c58` confirmed present in `git log --oneline --all`.

---
*Phase: 11-homebox-actual-budget-and-donetick*
*Completed: 2026-08-22*
