---
phase: 11-homebox-actual-budget-and-donetick
plan: 02
subsystem: infra
tags: [nixos, actual-budget, caddy, tailscale, impermanence, systemd]

requires:
  - phase: 11-homebox-actual-budget-and-donetick
    provides: "11-01's household two-layer module pattern (modules/household/ + hosts/ser8/household/) and the static-user override shape (PD-01, from Mealie)"
provides:
  - "Actual Budget live on ser8 with a static actual:actual system user (DynamicUser=false), persisted state, and a Caddy tsnet vhost on firebat"
  - "A live, verified Actual server password (bootstrap is provably one-way)"
affects: [11-03-budget-file-creation]

actuals:
  tokens: 1550
  tasks: 2
  commits: 6

tech-stack:
  added: []
  patterns:
    - "PD-01 static-user override repeated a third time (Mealie, Homebox, now Actual): explicit users.groups/users.users + DynamicUser=false in the household module, host policy flips services.<app>.enable"
    - "Impermanence tmpfiles mode must match the service's own StateDirectoryMode exactly (0700 for Actual, not Mealie's 0750) or the two fight on every service start"

key-files:
  created:
    - modules/household/actual.nix
    - hosts/ser8/household/actual.nix
  modified:
    - modules/household/default.nix
    - hosts/ser8/household/default.nix
    - hosts/ser8/impermanence.nix
    - modules/gateway/Caddyfile
    - scripts/validation/test-actual-module.sh

key-decisions:
  - "Server password generated with openssl rand -base64 24, set via one POST to /account/bootstrap, displayed once in terminal output for the operator, never written to any file this task touched, any commit, or any .planning/ artifact"
  - "ACT-02 marked only partially satisfied by this plan (server password half); budget-file creation is explicitly deferred to 11-03 per this plan's own success_criteria, so REQUIREMENTS.md is NOT updated to mark ACT-02 complete here -- only ACT-01 and ACT-03"

patterns-established:
  - "Runtime bootstrap actions (server password) that are secrets-by-nature stay entirely out of the repo -- generated, verified via the app's own API (successful + failing login), then handed to the operator once and discarded from any temp file"

requirements-completed: [ACT-01, ACT-03]

coverage:
  - id: D1
    description: "Actual Budget runs on ser8 with a static actual:actual user (no DynamicUser), persisted /var/lib/actual under impermanence, and a Caddy tsnet vhost live on firebat"
    requirement: "ACT-01"
    verification:
      - kind: integration
        ref: "./scripts/validation/test-actual-module.sh (six ok: lines)"
        status: pass
      - kind: manual_procedural
        ref: "curl https://actual.shad-bangus.ts.net/account/needs-bootstrap from firebat, browser load of the bootstrap landing page confirmed by user"
        status: pass
    human_judgment: false
  - id: D2
    description: "Actual reachable at its tsnet hostname over trusted TLS through Caddy"
    requirement: "ACT-03"
    verification:
      - kind: integration
        ref: "caddy adapt --config ./modules/gateway/Caddyfile | jq -e tailscale/actual:443 listener present"
        status: pass
    human_judgment: false
  - id: D3
    description: "Actual server password generated, bootstrapped, and verified working (correct login succeeds, wrong login fails, retry is rejected as already-bootstrapped)"
    requirement: "ACT-02 (partial -- password half only; budget-file creation is 11-03)"
    verification:
      - kind: integration
        ref: "POST /account/bootstrap -> ok; GET /account/needs-bootstrap -> bootstrapped:true; POST /account/login correct password -> 200 with token; POST /account/login wrong password -> 400 invalid-password; POST /account/bootstrap retry -> error already-bootstrapped"
        status: pass
    human_judgment: false

duration: ~25min
completed: 2026-08-21
status: complete
---

# Phase 11 Plan 02: Actual Budget -- Static User, Gateway, and Server Password Summary

Actual Budget is live on ser8 behind firebat's Caddy tsnet vhost with a static `actual:actual` system user and a verified, one-way-bootstrapped server password; budget-file creation is deferred to 11-03.

## Performance

- **Duration:** ~25 min
- **Started:** 2026-08-20 (Task 1, prior session)
- **Completed:** 2026-08-21 (Task 2, this session, resumed after tracer checkpoint approval)
- **Tasks:** 2/2
- **Files modified:** 7

## Accomplishments
- Actual Budget wired through every layer of the household pattern: static user/group, persisted state dir, gateway vhost, offline-gate assertions -- evaluated, built, and activated on both ser8 and firebat
- Server password generated and bootstrapped via `/account/bootstrap`; verified as genuinely one-way (retry returns `already-bootstrapped`) and functionally correct (right password logs in with a token, wrong password is rejected)

## Task Commits

Each task was committed atomically:

1. **Task 1: Actual through every layer -- static user, persistence, gateway, both hosts activated** -- `a1245a4` (feat: module + host policy), `45e3a87` (feat: impermanence), `cd61580` (feat: Caddy vhost), `4b67f3a` (test: validation script), `744ede7` (fix: `_:` signature), `8da0782` (fix: tmpfiles subdirectories)
2. **Task 2: Set the Actual server password** -- no repository file changes (runtime API call only, per plan); verified via the live endpoints, no commit produced

**Plan metadata:** (this commit, below)

## Files Created/Modified
- `modules/household/actual.nix` -- static `actual:actual` user/group, `services.actual.enable`/`openFirewall` defaulted off, mirrors Mealie's PD-01 shape
- `hosts/ser8/household/actual.nix` -- host policy: enables Actual, sets user/group/openFirewall
- `modules/household/default.nix` -- imports `./actual.nix`
- `hosts/ser8/household/default.nix` -- imports `./actual.nix`
- `hosts/ser8/impermanence.nix` -- adds `/var/lib/actual` to persisted directories, `d /persist/var/lib/actual 0700 actual actual -` tmpfiles rule, plus subdirectory rules for `server-files`/`user-files` (upstream module bug workaround)
- `modules/gateway/Caddyfile` -- adds `https://actual.shad-bangus.ts.net` vhost bound to `tailscale/actual`, proxying to `192.168.68.65:3000`
- `scripts/validation/test-actual-module.sh` -- extends existing Phase 9 script with three ACT-01-scoped assertions (`user`, `group`, `openFirewall`)

## Decisions Made
- Generated the server password with `openssl rand -base64 24`, bootstrapped over the live tsnet vhost, displayed it once in terminal output, and deleted the scratch file immediately after -- it appears in no commit, no script, and no `.planning/` artifact, per the plan's explicit prohibition
- Did not mark ACT-02 complete in `REQUIREMENTS.md` -- the plan's own `success_criteria` states budget-file creation is 11-03's job, so ACT-02 stays `Pending` until that plan lands; only ACT-01 and ACT-03 are marked complete here

## Deviations from Plan

None in this session -- Task 1's deviations (the `_:` signature fix and the tmpfiles subdirectory workaround) were already documented and committed in the prior session (`744ede7`, `8da0782`). Task 2 executed exactly as written: generate, bootstrap, verify both login paths, verify the one-way retry, display once, discard.

## Issues Encountered
None. The tracer checkpoint from the prior session was approved by the user (bootstrap landing page confirmed correct in a browser) before this session began.

## User Setup Required
**The generated Actual server password was displayed once in this session's terminal output and must be stored in the household's password manager now** -- it is not recoverable from any file, log, or commit. If it was not captured, the fix is an ordinary password change from the Actual settings UI after logging in with the /account/login flow, not a repository change.

## Next Phase Readiness
Actual is live, reachable, and password-protected. 11-03 can proceed directly to budget-file creation (a browser-only, one-time household decision) using the password now in the household's password manager.

---
*Phase: 11-homebox-actual-budget-and-donetick*
*Completed: 2026-08-21*

## Self-Check: PASSED

All 6 task commits (`a1245a4`, `45e3a87`, `cd61580`, `4b67f3a`, `744ede7`, `8da0782`) found in `git log`. `11-02-SUMMARY.md` present on disk.
