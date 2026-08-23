---
phase: 11-homebox-actual-budget-and-donetick
plan: 05
subsystem: infra
tags: [nixos, donetick, caddy, tailscale, sops-nix, rest-api-bootstrap]

# Dependency graph
requires:
  - phase: 11-04
    provides: "Donetick packaged from source, live on ser8 at tcp/2021 (loopback only), with DT_IS_USER_CREATION_DISABLED left open for this plan's bootstrap"
provides:
  - "Donetick live at https://donetick.shad-bangus.ts.net through firebat's Caddy tsnet vhost"
  - "jordan and sawnia hold active Donetick accounts sharing one circle, verified bidirectionally"
  - "Public signup closed (two-stage deploy complete); sops.templates restartUnits wired so future secret/template changes actually restart the unit"
  - "Two new household smoketest scripts (service + endpoint), 9 checks total"
affects: [backup-engine, Phase 12+]

# Actuals (#2632)
actuals:
  tokens: 3855
  tasks: 3
  commits: 2

tech-stack:
  added: []
  patterns:
    - "sops.templates.<name>.restartUnits must be set explicitly whenever a template's content can change post-initial-deploy -- sops-install-secrets only restarts a unit on a raw content diff between the old and new rendered file, and only for units named in restartUnits at the time of that diff. A content change landed with an empty restartUnits list re-renders the file on disk but leaves the running process on stale env vars indefinitely, with zero error signal."
    - "Tracer feedback gate (type=\"tracer\" task 1) exercised as designed: committed and offline-verified the Caddy vhost slice, paused for interactive human-verify before the account-bootstrap and signup-closure expansion tasks, resumed only after the coordinator relayed the user's live UI confirmation."

key-files:
  created:
    - scripts/smoketests/household/test-donetick-service.sh
    - scripts/smoketests/household/test-donetick-endpoint.sh
  modified:
    - modules/gateway/Caddyfile
    - hosts/ser8/household/donetick.nix
    - scripts/smoketests/household/all.sh

key-decisions:
  - "Verified Donetick's actual v0.1.79 auth/circle REST contract against the pinned GitHub source before writing any bootstrap call (internal/user/handler.go, internal/auth/handler.go, internal/circle/handler.go, internal/circle/model/model.go), per the 11-01 lesson to never trust plan-text or training-data assumptions about a third-party API. One correction found: login's JSON response field is access_token (TokenResponse), not a bare token field the plan's prose implied -- everything else (signup fields/validation, route paths, join/accept query params, response shapes) matched the plan exactly."
  - "Ran the entire jordan+sawnia bootstrap (signup, login, invite-code fetch, signup, login, join, list-pending, accept, verify-both-tokens) as one atomic shell invocation with an explicit HTTP-status assertion after every step, per the 11-01 lesson about split-invocation password loss. No repository files change in this task, matching the plan and 11-01's precedent."
  - "Added sops.templates.\"donetick.env\".restartUnits = [ \"donetick.service\" ] as a Rule 1 bug fix, discovered live: the file's content correctly flipped to DT_IS_USER_CREATION_DISABLED=true on disk after make switch-ser8, but the already-running process kept serving with signup open because nothing told systemd to restart it. A one-time manual `systemctl restart donetick` converged the current state; the restartUnits wiring makes every future template change self-correcting."

patterns-established:
  - "sops.templates entries whose content is expected to change again (feature flags, not just secrets) need restartUnits from the first commit that creates them, not added reactively after the first silent no-op deploy."

requirements-completed: [DTK-03, DTK-04]

coverage:
  - id: D1
    description: "Donetick reachable at https://donetick.shad-bangus.ts.net through firebat's Caddy tsnet vhost"
    requirement: "DTK-04"
    verification:
      - kind: integration
        ref: "caddy adapt | jq -e index(tailscale/donetick:443) -> found; curl from firebat -> HTTP 200; dig +short from firebat -> 100.76.196.2; user visually confirmed the live UI at the tracer feedback gate"
        status: pass
    human_judgment: false
  - id: D2
    description: "jordan and sawnia both hold active accounts in one shared circle"
    requirement: "DTK-03"
    verification:
      - kind: e2e
        ref: "atomic bootstrap shell run: signup 201 x2, login 200 x2, join-request 200 (isActive:false), pending-list shows sawnia's request, accept 200, GET /api/v1/circles/members from BOTH tokens returns 2 active members and the same circleId"
        status: pass
    human_judgment: false
  - id: D3
    description: "Public signup closed after bootstrap (two-stage deploy) with household smoketest coverage"
    requirement: "DTK-03"
    verification:
      - kind: integration
        ref: "scripts/smoketests/household/test-donetick-endpoint.sh ser8 (signup_closed: POST /api/v1/auth/ -> 403); scripts/smoketests/household/test-donetick-service.sh ser8; make check exits 0 across all four hosts; ./scripts/smoketests/household/all.sh ser8 8/8"
        status: pass
    human_judgment: false

duration: ~24min active work across 2 sessions (tracer feedback gate checkpoint -- interactive human-verify of the live UI -- excluded from active-work time)
completed: 2026-08-22
status: complete
---

# Phase 11 Plan 05: Donetick Gateway and Bootstrap Summary

**Donetick live at `https://donetick.shad-bangus.ts.net`, jordan and sawnia bootstrapped into one shared circle via Donetick's own signup/join/accept REST API, public signup closed, and a live restart-trigger bug fixed along the way.**

## Performance

- **Duration:** ~24 min active work across 2 sessions (the tracer feedback gate's interactive human-verify of the live UI is excluded, matching 11-04's convention for checkpoint gaps)
- **Started:** 2026-08-22T00:18:05-07:00 (Task 1)
- **Completed:** 2026-08-22T00:42:23-07:00 (Task 3, this session)
- **Tasks:** 3/3
- **Files modified:** 5

## Accomplishments
- Added the `https://donetick.shad-bangus.ts.net` Caddy tsnet vhost (`bind tailscale/donetick`, `reverse_proxy 192.168.68.65:2021`), matching the Mealie/Homebox/Actual pattern exactly; firebat switched and live-verified (Caddy adapt index found, HTTPS 200, DNS resolved)
- Exercised the tracer feedback gate as designed: committed and offline-verified the vhost slice first, paused for a human-verify checkpoint (auto mode was not active for this project), and only proceeded to the bootstrap/signup-closure tasks after the user confirmed the live Donetick UI loads correctly
- Verified Donetick's real v0.1.79 auth/circle REST contract against the pinned GitHub source (not memory) before any live call -- one correction found (login's token lives at `.access_token`, not a bare `.token`), everything else matched the plan
- Bootstrapped jordan and sawnia into one shared circle via the real signup -> login -> invite-code -> join -> pending-list -> accept flow, run atomically in one shell invocation with an HTTP-status assertion after every step; verified bidirectionally (`GET /api/v1/circles/members` returns the identical 2-member list and circle id from both tokens)
- Closed public signup (`DT_IS_USER_CREATION_DISABLED=true`) completing the two-stage deploy DTK-03 asks for -- live-verified: `POST /api/v1/auth/` now returns 403
- Found and fixed a real live bug along the way: the first redeploy correctly re-rendered the config file on disk but never restarted the running `donetick.service`, leaving signup silently open through a full `make switch-ser8`. Fixed by wiring `sops.templates."donetick.env".restartUnits`, and converged the current state with a one-time manual restart
- Added `test-donetick-service.sh` (unit/port/journal/state-dir, 5 checks, mirroring Homebox's static-user shape) and `test-donetick-endpoint.sh` (local-endpoint/signup-closed/tsnet, 4 checks, mirroring Mealie's), wired into `scripts/smoketests/household/all.sh` -- full household suite now 8/8

## Task Commits

Each task was committed atomically:

1. **Task 1: Gateway vhost, activate firebat, verify tsnet reachability** - `253b11b` (feat)
2. **Task 2: Bootstrap both household members into one circle** - no commit (runtime API calls only, no repository file changes, per plan)
3. **Task 3: Close public signup, add household smoketests** - `35b406f` (feat)

**Plan metadata:** (this commit, below)

_Note: Task 2 makes zero repository file changes by design -- matching 11-01/Homebox's precedent for the identical bootstrap-task shape._

## Files Created/Modified
- `modules/gateway/Caddyfile` - `https://donetick.shad-bangus.ts.net` tsnet vhost added after the `actual` entry
- `hosts/ser8/household/donetick.nix` - `DT_IS_USER_CREATION_DISABLED` flipped `false` -> `true`; added `sops.templates."donetick.env".restartUnits = [ "donetick.service" ]` (Deviations #1)
- `scripts/smoketests/household/test-donetick-service.sh` - unit/port/journal/state-dir checks (5 tests)
- `scripts/smoketests/household/test-donetick-endpoint.sh` - endpoint/signup-closed/tsnet checks (4 tests)
- `scripts/smoketests/household/all.sh` - wired both new scripts into the `TESTS` array

## Decisions Made
- Verified the real v0.1.79 REST contract against pinned source before every live call rather than trusting plan prose (see key-decisions above and Deviations #2)
- Ran the entire bootstrap sequence as one atomic shell invocation with explicit status assertions, per the 11-01 lesson
- Added `restartUnits` proactively as a Rule 1 fix rather than leaving the gap for a future template change to rediscover (see Deviations #1)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug, discovered live] `sops.templates."donetick.env"` had no `restartUnits`, so the signup-closure config change silently never reached the running process**
- **Found during:** Task 3, live verification after the first `make switch-ser8`
- **Issue:** The plan's Task 3 action was "change `DT_IS_USER_CREATION_DISABLED` to `true`... Redeploy: `make switch-ser8`", implicitly assuming that redeploy would make the new value effective. `sops-install-secrets` re-rendered `/run/secrets/rendered/donetick.env` with the correct new content (confirmed via direct file read on ser8: `DT_IS_USER_CREATION_DISABLED=true`), but with no `restartUnits` set on the template, nothing told systemd to restart `donetick.service` -- the already-running process kept serving with signup open. A live `POST /api/v1/auth/` against port 2021 still returned 201 after the full switch completed cleanly. `nix eval config.systemd.services.donetick.restartTriggers` confirmed empty; the sops-nix restart mechanism is driven entirely by the `restartUnits`/`reloadUnits` fields in the rendered manifest.json, calling `systemctl try-restart` directly, not via `systemd.services.<name>.restartTriggers`.
- **Fix:** Added `sops.templates."donetick.env".restartUnits = [ "donetick.service" ]` and redeployed so the manifest carries the trigger for all future content changes. Because the file's content itself was already correct from the first switch (only the metadata changed on the second), `sops-install-secrets`'s content-diff-gated restart did not fire retroactively either -- converged the current running state with one manual `sudo systemctl restart donetick` on ser8.
- **Files modified:** `hosts/ser8/household/donetick.nix`
- **Verification:** Post-restart: `systemctl show donetick --property=ActiveEnterTimestamp` moved to the restart time; `POST /api/v1/auth/` against loopback and against the tsnet vhost both return 403; `journalctl --invocation=0 -u donetick --priority=err` empty; `./scripts/smoketests/household/test-donetick-endpoint.sh ser8` passes `signup_closed`; jordan's existing account and circle membership survived the restart intact (SQLite state, confirmed by a subsequent login attempt reaching the real "invalid credentials" path rather than a fresh-DB error).
- **Committed in:** `35b406f`

**2. [Rule 1 - Plan-prose correction] Login's token lives at `.access_token`, not a generic "returns a token"**
- **Found during:** Task 2, before writing the bootstrap script
- **Issue:** The plan's Task 2 action describes `POST /api/v1/auth/login` as returning "a token" without naming the JSON field. Verified against the pinned v0.1.79 source (`internal/auth/handler.go`'s `EnhancedLoginHandler`, `internal/auth/token_service.go`'s `TokenResponse` struct): the response body is `{"access_token": "...", "refresh_token": "...", "access_token_expiry": ..., "token_type": ...}` -- `access_token`, not `token`. (A separate, unused-here `LegacyResponse` type does have a `token` field, but the enhanced login path the plan's own route table names does not return it.)
- **Fix:** Extracted `jq -r '.access_token'` from the login response for both jordan's and sawnia's `Authorization: Bearer` headers.
- **Files modified:** none (Task 2 makes no repository file changes, per plan)
- **Verification:** Both tokens authenticated successfully against `GET /api/v1/circles/` and the full join/accept flow; the atomic bootstrap script's explicit "token empty" guard never fired.

---

**Total deviations:** 2 auto-fixed, both Rule 1 (one a live-discovered bug with real security impact -- signup stayed open longer than intended -- the other a plan-prose API-contract correction caught before any live call)
**Impact on plan:** Deviation #1 was load-bearing: without it, Task 3's stated acceptance criteria (`POST /api/v1/auth/` returning 403) would never have converged from `make switch-ser8` alone, and every *future* change to `donetick.env`'s content (e.g. a JWT secret rotation) would hit the identical silent-no-restart gap until this fix. Deviation #2 was a correction to Task 2's own action text, caught by source verification before it could cause a live failure. No scope creep -- both fixes stayed within Task 2/3's existing file set and objective.

## Issues Encountered
- `make switch-ser8` returned exit 4 on both redeploys in this plan, in both cases for the same pre-existing, already-documented `sabnzbd.service`/`download-clients-setup.service` uid-drift failures tracked since Phase 10 (STATE.md; confirmed unrelated to Donetick both times -- `donetick.service` came up/restarted cleanly on both runs, and the failure signature is byte-identical to 11-01's and 11-04's notes on the same units)
- GPG commit signing is unavailable in this sandboxed session (`gpg: failed to create temporary file ... Operation not permitted`), matching the Phase 9-11 precedent recorded in STATE.md. Both commits in this plan used `--no-gpg-sign` after the signed attempt failed.

## User Setup Required
None outstanding. Both household members' passwords (jordan, sawnia) were generated with `openssl rand -base64 18` and displayed once in this session's output for the operator to store in the household password manager. Neither value was written to any file, script, commit, or `.planning/` artifact -- confirmed by grepping the working scratchpad directory for both literal password strings before deleting it (zero matches).

## Next Phase Readiness
- Donetick is fully live, reachable, bootstrapped, and hardened -- the third and final app in Phase 11's Homebox/Actual/Donetick set is complete
- `sops.templates.*.restartUnits` is now a documented, load-bearing pattern for this repo: any future `sops.templates` entry whose content can change post-initial-deploy (feature flags, not just one-shot secrets) needs it from the first commit, not added reactively
- Nightly backup coverage for Donetick's SQLite database (`/var/lib/donetick/donetick.db`) is not yet wired -- expected with the phase's shared backup-engine work, matching Homebox/Actual/Mealie's current state
- SEC-01 (no household service reachable from outside Tailscale/LAN) remains Deferred for Donetick's new vhost, same as every other household service in this phase -- no negative-access smoketest exists yet for any of them

## Self-Check: PASSED

Both created files confirmed present on disk (`scripts/smoketests/household/test-donetick-service.sh`, `scripts/smoketests/household/test-donetick-endpoint.sh`). Both task commit hashes (`253b11b`, `35b406f`) confirmed present in `git log --oneline --all`.

---
*Phase: 11-homebox-actual-budget-and-donetick*
*Completed: 2026-08-22*
