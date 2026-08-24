---
phase: 11-homebox-actual-budget-and-donetick
plan: 01
subsystem: infra
tags: [nixos, homebox, sops-nix, impermanence, caddy, tailscale, sqlite]

# Dependency graph
requires:
  - phase: 10-household-foundation-and-mealie
    provides: "modules/household/ + hosts/ser8/household/ two-layer pattern, firebat tsnet Caddyfile shape, impermanence conventions"
provides:
  - "Homebox 0.25.0 live on ser8 at https://homebox.shad-bangus.ts.net, both household accounts bootstrapped into one group, self-registration closed"
affects: [11-02, 11-03, 11-04, 11-05, 11-06, backup-engine]

# Actuals (#2632)
actuals:
  tokens: 5703
  tasks: 3
  commits: 5

tech-stack:
  added: []
  patterns:
    - "modules/household/<svc>.nix + hosts/ser8/household/<svc>.nix two-layer pattern extended to a static-user (non-DynamicUser, non-Postgres) service"
    - "StateDirectoryMode forced explicitly rather than assumed from systemd defaults"

key-files:
  created:
    - modules/household/homebox.nix
    - hosts/ser8/household/homebox.nix
    - scripts/validation/test-homebox-module.sh
    - scripts/smoketests/household/test-homebox-service.sh
    - scripts/smoketests/household/test-homebox-endpoint.sh
  modified:
    - modules/household/default.nix
    - hosts/ser8/household/default.nix
    - hosts/ser8/impermanence.nix
    - modules/gateway/Caddyfile
    - Makefile
    - scripts/smoketests/household/all.sh

key-decisions:
  - "No sops secret exists for Homebox: HBOX_AUTH_API_KEY_PEPPER is not a real Homebox 0.25.0 config variable (verified against the pinned tag's Go source -- no Pepper/JWT/HMAC anywhere; auth uses argon2id per-password random salts and random session tokens). The plan's entire sops.secrets/sops.templates/EnvironmentFile/user_setup wiring for this was skipped."
  - "HBOX_OPTIONS_ALLOW_REGISTRATION set explicitly to \"true\" in Task 1 (not left unset): nixpkgs 26.05's services.homebox module now defaults this to \"false\" via mkDefault, opposite of Homebox's own binary default and opposite of the plan's assumption. Left unset, Task 2's bootstrap registration would have returned 403."
  - "StateDirectoryMode forced to \"0750\" via systemd.services.homebox.serviceConfig: Homebox's module never sets it, so systemd's real default (0755) applies -- not the 0750 Mealie-derived assumption in the plan text, which is specific to PostgreSQL's own override for major >= 11."
  - "Group invite-token bootstrap uses POST /v1/groups/invitations (returns 201 with a Uses/ExpiresAt-scoped token), not a Group.inviteToken field on GET /v1/groups -- that field does not exist on repo.Group in 0.25.0. The registration JSON field for the token is \"token\", not \"groupToken\". The login JSON field is \"username\" (holding the email value), not \"email\". All four corrected against the pinned v0.25.0 Go source; the plan's own referenced upstream CI script (create-test-data.sh) also gets the login field right (\"username\") but is itself unreliable for the register-response shape (assumes a body register never returns)."

patterns-established:
  - "Verify third-party app config surface against the pinned version's actual source before wiring sops secrets or API bootstrap calls -- plan text describing an app's env vars or REST contract from memory/training data is not authoritative."

requirements-completed: [HBX-01, HBX-02, HBX-03]

coverage:
  - id: D1
    description: "Homebox 0.25.0 wired through modules/household/ + hosts/ser8/household/, firewall opened, impermanence-persisted, no sops secret needed"
    requirement: "HBX-01"
    verification:
      - kind: integration
        ref: "scripts/validation/test-homebox-module.sh (4 check_eval assertions)"
        status: pass
      - kind: integration
        ref: "scripts/smoketests/household/test-homebox-service.sh ser8"
        status: pass
    human_judgment: false
  - id: D2
    description: "Both household members (jordan, sawnia) hold live accounts in one shared Homebox group"
    requirement: "HBX-02"
    verification:
      - kind: e2e
        ref: "GET /api/v1/groups/members from both jordan's and sawnia's tokens -- same 2-member list, same group id d13364b6-611d-4273-aebb-daf7f4f0a915"
        status: pass
    human_judgment: false
  - id: D3
    description: "Self-registration closed after bootstrap; Homebox reachable through firebat's Caddy tsnet vhost"
    requirement: "HBX-03"
    verification:
      - kind: integration
        ref: "scripts/smoketests/household/test-homebox-endpoint.sh ser8 (registration_closed, tsnet_dns, tsnet_https)"
        status: pass
    human_judgment: false

duration: 55min
completed: 2026-08-21
status: complete
---

# Phase 11 Plan 1: Homebox Homebox Summary

**Homebox 0.25.0 live on ser8 with both household accounts bootstrapped into one group, self-registration closed, and zero secrets provisioned for a config variable the app doesn't actually have.**

## Performance

- **Duration:** 55 min
- **Started:** 2026-08-20T20:47:00-07:00
- **Completed:** 2026-08-20T21:42:00-07:00
- **Tasks:** 3
- **Files modified:** 11

## Accomplishments
- Homebox deployed through the exact `modules/household/` + `hosts/ser8/household/` two-layer pattern Mealie established, with no sops secret at all (see Deviations) -- the simplest of the three Phase 11 apps to bootstrap
- `/var/lib/homebox` is impermanence-persisted at mode 0750, owned `homebox:homebox`, confirmed identical on both sides of the bind mount after two live redeploys
- Both household members bootstrapped into one shared group via the real invitation API (`POST /v1/groups/invitations`), verified by both tokens returning the same 2-member `GET /api/v1/groups/members` response and the same group id
- Self-registration closed live: `POST /api/v1/users/register` with no invite token now returns 403, both at the config layer (offline eval gate) and against the running service
- Homebox reachable end-to-end at `https://homebox.shad-bangus.ts.net` through firebat's Caddy tsnet vhost (DNS resolves, HTTPS returns 200)
- Two new household smoketest scripts (9 checks total) wired into `scripts/smoketests/household/all.sh`

## Task Commits

Each logical unit was committed atomically:

1. **Task 1a: scaffold Homebox module and host policy** - `c91ae54` (feat)
2. **Task 1b: persist Homebox state under impermanence** - `97c1301` (feat)
3. **Task 1c: add Homebox tsnet vhost to gateway Caddyfile** - `33cc98d` (feat)
4. **Task 1d: add Homebox module validation script** - `ef719ff` (test)
5. **Task 1 fix: force StateDirectoryMode=0750** - `3d7f8b2` (fix, discovered live after first activation)
6. **Task 2: bootstrap both household members** - no commit (runtime API calls only, no repository file changes, per plan)
7. **Task 3: close self-registration, extend gate, add smoketests** - `7f7e4e8` (feat)

_Note: Task 1 split into four smaller commits per the plan's explicit instruction ("module scaffold + secret, then persistence, then the Caddy vhost, then the validation script"), minus the secret portion which was skipped (see Deviations). A fifth commit was added mid-task after discovering a StateDirectoryMode defect on the live host._

## Files Created/Modified
- `modules/household/homebox.nix` - reusable layer: service disabled by default, firewall port 7745 gated on enable, StateDirectoryMode forced to 0750
- `hosts/ser8/household/homebox.nix` - host policy: package pin, settings block, registration now closed
- `modules/household/default.nix`, `hosts/ser8/household/default.nix` - import wiring
- `hosts/ser8/impermanence.nix` - `/var/lib/homebox` persisted directory + tmpfiles rule
- `modules/gateway/Caddyfile` - `https://homebox.shad-bangus.ts.net` tsnet vhost
- `scripts/validation/test-homebox-module.sh` - 4 offline eval assertions
- `scripts/smoketests/household/test-homebox-service.sh` - unit/port/journal/state-dir checks (5 tests)
- `scripts/smoketests/household/test-homebox-endpoint.sh` - endpoint/registration/tsnet checks (4 tests)
- `scripts/smoketests/household/all.sh`, `Makefile` - wiring

## Decisions Made
- No sops secret for Homebox at all (see Deviations #1) -- simpler than Mealie, which does need one
- `HBOX_OPTIONS_ALLOW_REGISTRATION` explicitly `"true"` in Task 1, flipped to `"false"` in Task 3, rather than relying on any upstream default in either direction (see Deviations #2)
- `StateDirectoryMode = "0750"` forced explicitly rather than assumed (see Deviations #3)
- Group bootstrap uses the real `/v1/groups/invitations` API with corrected JSON field names (see Deviations #4)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Plan factual error] Removed the entire sops secret / EnvironmentFile subsystem for a config variable Homebox 0.25.0 does not have**
- **Found during:** Task 1, before writing `hosts/ser8/household/homebox.nix`
- **Issue:** The plan's central mechanism for Task 1 was `sops.secrets.homebox_auth_api_key_pepper` + `sops.templates."homebox.env"` + `EnvironmentFile` + a `user_setup` step asking the operator to generate and paste in a "pepper" via `openssl rand -base64 48`. Verified against the pinned v0.25.0 tag's full Go source (`sysadminsmedia/homebox` tarball, `backend/`): `grep -rni pepper` across the entire repository returns zero matches; there is no JWT/HMAC library in `go.mod`/`go.sum`; password hashing is argon2id with a random per-password salt (`backend/pkgs/hasher/password.go`); session tokens are `crypto/rand`-generated and SHA-256 hashed for storage (`backend/pkgs/hasher/token.go`), with no server-side secret involved anywhere in either path. As written, the plan would have left `homebox.service` unable to start until a human added a value to `secrets/ser8.yaml` for a variable the binary never reads -- pure phantom-feature busywork and an unnecessary human gate, directly against CLAUDE.md's "no phantom features" directive.
- **Fix:** Skipped `sops.secrets`, `sops.templates`, the `EnvironmentFile` override, the `after`/`wants` sops-nix ordering, the `openssl rand` step, and the `user_setup` frontmatter block entirely. Homebox needs zero secrets for this deployment (SQLite backend, no OIDC, no mailer, no barcode API configured).
- **Files modified:** `hosts/ser8/household/homebox.nix` (omits the secret wiring the plan specified)
- **Verification:** `homebox.service` came up active on the very first `make switch-ser8`, with no human action required and no failed unit. `rg -c 'HBOX_AUTH_API_KEY_PEPPER|homebox_auth_api_key_pepper' modules/household/ hosts/ser8/household/ .planning/` matches only the original plan and research docs, never any actual config file.
- **Committed in:** `c91ae54`

**2. [Rule 1 - Plan factual error] `HBOX_OPTIONS_ALLOW_REGISTRATION` set explicitly to `"true"` in Task 1 instead of left unset**
- **Found during:** Task 1, reading the vendored nixpkgs `nixos/modules/services/web-apps/homebox.nix`
- **Issue:** The plan instructs leaving this setting unset in Task 1, expecting the upstream module's own `mkDefault` to leave it open (`"true"`) until Task 3 closes it. The vendored 26.05 module source shows the opposite: `HBOX_OPTIONS_ALLOW_REGISTRATION = "false";` is itself set via `mkDefault` in the module's own `config` block -- closed by default, opposite of Homebox's own binary default (`conf:"default:true"` in `backend/internal/sys/config/conf.go`). Left unset as the plan specified, Task 2's bootstrap registration call would have returned 403 instead of 204, blocking the entire task.
- **Fix:** Set `HBOX_OPTIONS_ALLOW_REGISTRATION = "true"` explicitly (plain assignment, which has higher merge priority than the module's `mkDefault`) in Task 1, then changed it to `"false"` in Task 3 as originally planned.
- **Files modified:** `hosts/ser8/household/homebox.nix`
- **Verification:** `nix eval` confirmed `"true"` after Task 1's activation; Task 2's bootstrap registration returned 204 as required; `nix eval` confirmed `"false"` after Task 3's activation, and a live registration attempt returned 403.
- **Committed in:** `c91ae54` (Task 1), `7f7e4e8` (Task 3)

**3. [Rule 1 - Bug] Forced `StateDirectoryMode = "0750"` after discovering the declared tmpfiles mode was cosmetic**
- **Found during:** Task 1, live verification after the first `make switch-ser8`
- **Issue:** The persistence commit's tmpfiles rule declared `d /persist/var/lib/homebox 0750 homebox homebox -`, following the plan's stated assumption that "0750" matches "the mode systemd's StateDirectory = homebox produces by default." That assumption is wrong: systemd's actual default for `StateDirectoryMode` is `0755` (Mealie's 0750 precedent is specific to PostgreSQL's own explicit override for major >= 11, not a systemd default). Live `stat` on ser8 after the first activation showed `/var/lib/homebox` at `homebox:homebox 0755` -- ownership was corrected by systemd's own StateDirectory setup at service start (which runs after tmpfiles and wins), but the mode was systemd's real default, not my tmpfiles declaration.
- **Fix:** Added `systemd.services.homebox.serviceConfig.StateDirectoryMode = lib.mkIf config.services.homebox.enable "0750";` to `modules/household/homebox.nix`, forcing the value the tmpfiles rule already declared, narrowing household inventory data (item names, locations, attachment photos) to owner+group rather than world-readable.
- **Files modified:** `modules/household/homebox.nix`, `hosts/ser8/impermanence.nix` (comment correction)
- **Verification:** Redeployed; live `stat` on both `/var/lib/homebox` and `/persist/var/lib/homebox` now shows `homebox homebox 750`. Asserted by `scripts/smoketests/household/test-homebox-service.sh`'s state-directory tests.
- **Committed in:** `3d7f8b2`

**4. [Rule 1 - Plan factual error] Corrected the Task 2 group-invite bootstrap flow against the real v0.25.0 API contract**
- **Found during:** Task 2, before making any live API call
- **Issue:** The plan's Task 2 action text described reading an invite token from `GET /api/v1/groups` (`.inviteToken`) and using a `"groupToken"` JSON field on registration. Verified against the pinned v0.25.0 Go source: `repo.Group` (the type `GET /v1/groups` returns) has no `InviteToken`/`inviteToken` field at all -- that field does not exist in this version. The actual mechanism is the separate group-invitations API: `POST /v1/groups/invitations` (authenticated, `{"uses":1,"expiresAt":...}`) returns 201 with a `GroupInvitation{token, expiresAt, uses}`. The registration handler's JSON field for that token is `"token"` (`services.UserRegistration.GroupToken string \`json:"token"\``), not `"groupToken"`. Separately, the login handler's JSON field is `"username"` (`services.LoginForm.Username`), not `"email"` as the plan's action text stated, even though the value passed is the email address.
- **Fix:** Ran the corrected flow: register jordan (no token) -> login jordan (`"username"` field) -> `POST /v1/groups/invitations` as jordan -> register sawnia with `"token": "<invite>"` -> login sawnia -> verified `GET /api/v1/groups/members` and `GET /api/v1/groups` agree from both tokens.
- **Files modified:** none (Task 2 makes no repository file changes, per plan)
- **Verification:** `GET /api/v1/groups/members` returned the identical 2-member list and identical group id (`d13364b6-611d-4273-aebb-daf7f4f0a915`) from both jordan's and sawnia's tokens.
- **Note:** A first, split-across-two-shell-invocations attempt at this bootstrap lost track of jordan's generated password when the shell session ended before it was printed (each Bash tool call is a fresh, non-persistent shell). Recovered by directly deleting the orphaned `users`/`groups`/`auth_tokens`/`locations`/`tags` rows for that attempt via `sqlite3` (safe: zero real inventory data existed yet) and re-running the entire bootstrap atomically in a single shell invocation with explicit per-step HTTP-status assertions. No stale/orphaned accounts remain; verified via a full `SELECT email FROM users` after the redo.

---

**Total deviations:** 4 auto-fixed (all Rule 1 -- plan described the target app's actual config/API surface incorrectly, or a real bug discovered live)
**Impact on plan:** All four were load-bearing corrections without which the plan as literally written would either fail outright (Task 2's bootstrap, blocked by either the registration-default flip or the wrong API fields) or add meaningless human-facing complexity (the phantom secret) or ship a weaker security posture than intended (StateDirectoryMode). No scope creep -- every fix stayed within Task 1-3's existing file set and objective.

## Issues Encountered
- First bootstrap attempt (Task 2) split the atomic register+login+invite+register sequence across two separate Bash tool invocations, losing a generated password when the first invocation's shell session ended before printing it (Bash tool calls do not persist shell state/env vars across calls). Recovered by deleting the orphaned DB rows and redoing the entire sequence in one invocation with explicit status assertions at every step; documented as deviation #4 above rather than hidden.
- `make switch-ser8` returns exit 4 on every run in this phase due to two pre-existing, already-documented unrelated failures (`sabnzbd.service`, `download-clients-setup.service` -- uid drift under `/var/lib/sabnzbd/admin`, tracked in STATE.md since Phase 10). Out of scope per the deviation rules' scope boundary; not touched.
- GPG commit signing is unavailable in this sandboxed session (`gpg: failed to create temporary file ... Operation not permitted`), matching the Phase 9 precedent recorded in STATE.md. All five commits in this plan used `--no-gpg-sign`.

## User Setup Required
None. The plan's `user_setup` block (adding `HBOX_AUTH_API_KEY_PEPPER` to `secrets/ser8.yaml`) is not needed -- see Deviation #1. Both household members' passwords were shown once in terminal output during Task 2 for the operator to store in the household password manager; they are not recorded anywhere in this repository or in any `.planning/` artifact.

## Next Phase Readiness
- Homebox is fully live, verified end-to-end, and ready for the household to use immediately
- The `modules/household/` + `hosts/ser8/household/` pattern now has three services (Mealie, Homebox, and whichever of Actual/Donetick lands next in this phase) to reference
- No blockers for 11-02 onward. The corrected understanding of Homebox's real config/API surface (no pepper, real registration default, real invitation API) is now recorded here for any future plan touching Homebox again
- Nightly backup coverage for Homebox's SQLite database (`/var/lib/homebox/data/homebox.db`) is not yet wired -- expected to land with the phase's shared backup-engine work, matching the milestone's stated scope for all four services

## Self-Check: PASSED

All 5 created files confirmed present on disk. All 6 commit hashes confirmed present in `git log --oneline --all`.

---
*Phase: 11-homebox-actual-budget-and-donetick*
*Completed: 2026-08-21*
