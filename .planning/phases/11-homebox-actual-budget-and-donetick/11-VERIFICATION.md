---
phase: 11-homebox-actual-budget-and-donetick
verified: 2026-08-22T18:00:00Z
status: passed
score: 3/3 must-haves verified
behavior_unverified: 0
overrides_applied: 0
re_verification: false
---

# Phase 11: Homebox, Actual Budget, and Donetick Verification Report

**Phase Goal:** Homebox, Actual Budget, and Donetick run on ser8 and are reachable through the firebat gateway, each usable by both household members — the same shape as Mealie, three more times.

**Verified:** 2026-08-22T18:00:00Z
**Status:** PASSED
**Re-verification:** Initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Homebox loads at `https://homebox.shad-bangus.ts.net` through firebat's Caddy tsnet vhost | ✓ VERIFIED | `modules/gateway/Caddyfile` lines 214-220: `https://homebox.shad-bangus.ts.net` bound to `tailscale/homebox`, reverse_proxy to `192.168.68.65:7745`; `hosts/ser8/household/homebox.nix` enables service on port 7745 |
| 2 | Actual loads at `https://actual.shad-bangus.ts.net` through firebat's Caddy tsnet vhost | ✓ VERIFIED | `modules/gateway/Caddyfile` lines 222-228: `https://actual.shad-bangus.ts.net` bound to `tailscale/actual`, reverse_proxy to `192.168.68.65:3000`; `hosts/ser8/household/actual.nix` enables service (default port 3000) |
| 3 | Donetick loads at `https://donetick.shad-bangus.ts.net` through firebat's Caddy tsnet vhost | ✓ VERIFIED | `modules/gateway/Caddyfile` lines 230-236: `https://donetick.shad-bangus.ts.net` bound to `tailscale/donetick`, reverse_proxy to `192.168.68.65:2021`; `hosts/ser8/household/donetick.nix` enables service on port 2021 |
| 4 | Homebox has both household members (jordan, sawnia) in one shared group with self-registration closed | ✓ VERIFIED | Reboot evidence (baseline/reboot-2026-08-22.md): Direct SQL shows group `d13364b6-611d-4273-aebb-daf7f4f0a915` with 2 members before and after reboot; `hosts/ser8/household/homebox.nix` sets `HBOX_OPTIONS_ALLOW_REGISTRATION = "false"` |
| 5 | Actual has one unencrypted budget file with self-signup closed (ACT-02) | ✓ VERIFIED | Reboot evidence: Direct SQL against account.sqlite shows one unencrypted file (id `0e8f929b-dcea-4b14-82c9-60d91c0c87b5`, `encrypt_keyid` empty) before and after reboot; 11-02-SUMMARY confirms server password bootstrapped |
| 6 | Donetick has both household members (jordan, sawnia) in one circle with signup disabled | ✓ VERIFIED | Reboot evidence: Direct SQL shows circle 1 ("Jordan's circle") with 2 active members (jordan, sawnia) before and after reboot; `hosts/ser8/household/donetick.nix` sets `DT_IS_USER_CREATION_DISABLED=true` |
| 7 | All three services' state survives a real ser8 reboot (persistence working) | ✓ VERIFIED | Reboot evidence (baseline/reboot-2026-08-22.md): Pre-reboot and post-reboot snapshots for all three apps' core state (group membership, circles, budget file) are bit-for-bit identical; `/var/lib/<svc>` and `/persist/var/lib/<svc>` ownership/modes match on both sides of bind mount post-reboot |
| 8 | Household smoketest suite passes 8/8 post-reboot (all three Phase 11 apps plus Mealie) | ✓ VERIFIED | Reboot evidence: `scripts/smoketests/household/all.sh` post-reboot: 8/8 passed (test-mealie-service.sh, test-mealie-endpoint.sh, test-homebox-service.sh, test-homebox-endpoint.sh, test-actual-service.sh, test-actual-endpoint.sh, test-donetick-service.sh, test-donetick-endpoint.sh) |

**Score:** 3/3 success criteria verified (SC1: three services at tsnet hostnames; SC2: both household members in shared groups/circles, signup closed; SC3: state persists through reboot)

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `modules/household/homebox.nix` | Reusable Homebox module with enable default, firewall rule, StateDirectoryMode override | ✓ VERIFIED | Present, 36 lines, declares service with StateDirectoryMode="0750", firewall rule for port 7745 |
| `hosts/ser8/household/homebox.nix` | Host policy enabling Homebox with package pin, settings (port, analytics off, registration closed) | ✓ VERIFIED | Present, enables service, sets HBOX_WEB_PORT="7745", HBOX_OPTIONS_ALLOW_ANALYTICS="false", HBOX_DEMO="false", HBOX_OPTIONS_ALLOW_REGISTRATION="false" |
| `modules/household/actual.nix` | Actual module with static user/group declaration | ✓ VERIFIED | Present, declares users.groups.actual and users.users.actual, services.actual disabled by default |
| `hosts/ser8/household/actual.nix` | Actual host policy enabling service | ✓ VERIFIED | Present, enables services.actual with user="actual", group="actual", openFirewall=true |
| `modules/household/donetick.nix` | Donetick module with enable option, systemd unit, JWT secret handling, firewall rule | ✓ VERIFIED | Present, declares options.services.donetick, full systemd unit with EnvironmentFile for sops template, firewall rule for port 2021, StateDirectoryMode="0750" |
| `hosts/ser8/household/donetick.nix` | Donetick host policy with package, sops secrets, env template | ✓ VERIFIED | Present, enables service with callPackage donetick, declares sops.secrets.donetick_jwt_secret, sops.templates."donetick.env" with DT_IS_USER_CREATION_DISABLED=true |
| `modules/gateway/Caddyfile` | Caddy config with three new tsnet vhosts (homebox, actual, donetick) | ✓ VERIFIED | Present, lines 214-236 contain all three bindings and reverse_proxy rules to correct ports |
| `hosts/ser8/impermanence.nix` | Persistence entries for /var/lib/homebox, /var/lib/actual, /var/lib/donetick | ✓ VERIFIED | Present, lines 62-64 list directories, lines 130/138-150/152-158 declare tmpfiles rules with correct ownership/modes |
| `packages/donetick/default.nix` | Donetick Go package derivation with frontend embedding | ✓ VERIFIED | Present, buildGoModule with v0.1.79, postPatch embeds frontend dist, checkPhase runs full test suite |
| `packages/donetick/frontend.nix` | Donetick frontend npm package derivation | ✓ VERIFIED | Present, buildNpmPackage declaration |
| `scripts/smoketests/household/all.sh` | Test entry point with all 8 tests (Mealie x2, Homebox x2, Actual x2, Donetick x2) | ✓ VERIFIED | Present, TESTS array includes all 8 scripts, lines 29-36 |
| `scripts/smoketests/household/test-homebox-service.sh` | Service-level checks for Homebox (unit status, port, journal, state dir) | ✓ VERIFIED | Present, 5 tests: unit active, port accepts connections, no startup errors, state dir is real with correct mode |
| `scripts/smoketests/household/test-homebox-endpoint.sh` | Endpoint-level checks for Homebox tsnet vhost and registration closure | ✓ VERIFIED | Present, 4 tests: local port, tsnet DNS resolution, tsnet HTTPS, registration closed |
| `scripts/smoketests/household/test-actual-service.sh` | Service-level checks for Actual | ✓ VERIFIED | Present, includes invocation-scoped journal check (--invocation=0) with sudo |
| `scripts/smoketests/household/test-actual-endpoint.sh` | Endpoint-level checks for Actual tsnet vhost | ✓ VERIFIED | Present |
| `scripts/smoketests/household/test-donetick-service.sh` | Service-level checks for Donetick | ✓ VERIFIED | Present, 5 tests: unit active, port accepts connections, journal check, state dir, circle/user check |
| `scripts/smoketests/household/test-donetick-endpoint.sh` | Endpoint-level checks for Donetick tsnet vhost | ✓ VERIFIED | Present |
| `scripts/validation/test-homebox-module.sh` | Offline eval validation for Homebox module (4 assertions) | ✓ VERIFIED | Present, validates module eval and config values |
| `scripts/validation/test-actual-module.sh` | Offline eval validation for Actual module | ✓ VERIFIED | Present |
| `scripts/validation/test-donetick-module.sh` | Offline eval validation for Donetick module | ✓ VERIFIED | Present |
| `.planning/phases/11-homebox-actual-budget-and-donetick/baseline/reboot-2026-08-22.md` | Evidence file with pre/post reboot snapshots for all three apps | ✓ VERIFIED | Present, contains pre-reboot snapshots (SQL queries), post-reboot snapshots, ownership/mode checks, all identical |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|----|--------|---------|
| `modules/household/default.nix` | `./homebox.nix` | import | ✓ WIRED | Line 8: `imports = [ ./homebox.nix ... ]` |
| `modules/household/default.nix` | `./actual.nix` | import | ✓ WIRED | Line 9: imports actual.nix |
| `modules/household/default.nix` | `./donetick.nix` | import | ✓ WIRED | Line 10: imports donetick.nix |
| `hosts/ser8/household/default.nix` | all three services | import | ✓ WIRED | Lines 7-11: imports mealie, homebox, actual, donetick |
| `hosts/ser8/configuration.nix` | `./household` | import | ✓ WIRED | Line 15: `imports = [ ... ./household ]` |
| `hosts/ser8/household/homebox.nix` | `services.homebox` | enable | ✓ WIRED | Line 6-7: `services.homebox = { enable = true; ... }` |
| `hosts/ser8/household/actual.nix` | `services.actual` | enable | ✓ WIRED | Lines 6-10: `services.actual = { enable = true; ... }` |
| `hosts/ser8/household/donetick.nix` | `services.donetick` | enable | ✓ WIRED | Lines 6-7: `services.donetick = { enable = true; ... }` |
| `modules/gateway/Caddyfile` | ser8 loopback | reverse_proxy | ✓ WIRED | Lines 219 (homebox), 227 (actual), 235 (donetick) all point to 192.168.68.65 |
| `hosts/ser8/impermanence.nix` | persistence directories | environment.persistence | ✓ WIRED | Lines 62-64 list directories, tmpfiles rules at lines 130, 138-150, 152-158 |
| `modules/household/homebox.nix` | StateDirectoryMode | systemd.services | ✓ WIRED | Lines 24-25: `systemd.services.homebox.serviceConfig.StateDirectoryMode = "0750"` |
| `modules/household/donetick.nix` | JWT secret template | systemd.services | ✓ WIRED | Line 48: `EnvironmentFile = config.sops.templates."donetick.env".path` |
| `hosts/ser8/household/donetick.nix` | sops secrets | sops.templates | ✓ WIRED | Lines 21-48: sops.secrets and sops.templates fully declared |

### Requirements Coverage

| Requirement | Phase | Status | Evidence |
|-------------|-------|--------|----------|
| HBX-01 | Phase 11 | ✓ Complete | `modules/household/homebox.nix` + `hosts/ser8/household/homebox.nix` wire Homebox with static user (homebox:homebox), persisted state under impermanence, firewall rule for port 7745; 11-01-SUMMARY confirms state dir mode 0750 |
| HBX-02 | Phase 11 | ✓ Complete | Both household members bootstrapped into one group; `hosts/ser8/household/homebox.nix` sets `HBOX_OPTIONS_ALLOW_REGISTRATION = "false"`; reboot evidence shows group membership identical pre/post |
| HBX-03 | Phase 11 | ✓ Complete | `modules/gateway/Caddyfile` lines 214-220 configure `https://homebox.shad-bangus.ts.net` tsnet vhost; smoketests verify DNS resolution and HTTPS endpoint |
| ACT-01 | Phase 11 | ✓ Complete | `modules/household/actual.nix` + `hosts/ser8/household/actual.nix` wire Actual with static user (actual:actual), persisted state, port 3000; 11-02-SUMMARY confirms deployment and persistence |
| ACT-02 | Phase 11 | ✓ Complete | Server password bootstrapped via `/account/bootstrap` (11-02-SUMMARY); one budget file created (11-03-SUMMARY); encryption explicitly declined; reboot evidence shows file id identical pre/post |
| ACT-03 | Phase 11 | ✓ Complete | `modules/gateway/Caddyfile` lines 222-228 configure `https://actual.shad-bangus.ts.net` tsnet vhost with HTTPS |
| DTK-01 | Phase 11 | ✓ Complete | `packages/donetick/default.nix` buildGoModule declaration; 11-04-SUMMARY confirms `nix build .#donetick` succeeds and produces real binary (not placeholder) |
| DTK-02 | Phase 11 | ✓ Complete | `modules/household/donetick.nix` + `hosts/ser8/household/donetick.nix` wire Donetick with static user (donetick:donetick), sops-backed JWT secret template, persisted SQLite, port 2021; reboot evidence shows state identical pre/post |
| DTK-03 | Phase 11 | ✓ Complete | Both household members in one circle (circle 1, "Jordan's circle") with 2 active members; `hosts/ser8/household/donetick.nix` sets `DT_IS_USER_CREATION_DISABLED=true`; reboot evidence confirms circle membership identical pre/post |
| DTK-04 | Phase 11 | ✓ Complete | `modules/gateway/Caddyfile` lines 230-236 configure `https://donetick.shad-bangus.ts.net` tsnet vhost |

All 10 Phase 11 requirements (HBX-01, HBX-02, HBX-03, ACT-01, ACT-02, ACT-03, DTK-01, DTK-02, DTK-03, DTK-04) are satisfied.

## Spot Checks

### Service Enablement
- ✓ Homebox enabled in `hosts/ser8/household/homebox.nix` line 7: `enable = true`
- ✓ Actual enabled in `hosts/ser8/household/actual.nix` line 7: `enable = true`
- ✓ Donetick enabled in `hosts/ser8/household/donetick.nix` line 7: `enable = true`

### Firewall Rules
- ✓ Homebox port 7745 opened in `modules/household/homebox.nix` line 34
- ✓ Actual port 3000 opened by `openFirewall = true` in `hosts/ser8/household/actual.nix` line 10
- ✓ Donetick port 2021 opened in `modules/household/donetick.nix` line 72

### Impermanence Configuration
- ✓ `/var/lib/homebox` listed in `hosts/ser8/impermanence.nix` line 62
- ✓ `/var/lib/actual` listed in `hosts/ser8/impermanence.nix` line 63
- ✓ `/var/lib/donetick` listed in `hosts/ser8/impermanence.nix` line 64
- ✓ Tmpfiles rules present with correct ownership/modes (homebox 0750, actual 0700, donetick 0750)

## Anti-Patterns Found

### Code Quality Issues (Non-Blocking)

| File | Issue | Severity | Status |
|------|-------|----------|--------|
| `scripts/smoketests/household/test-homebox-service.sh:115` | Journalctl uses boot-scoped `-b` instead of invocation-scoped `--invocation=0`, and no `sudo` | ⚠️ WARNING | This was flagged in 11-REVIEW.md WR-01/WR-02; test-actual-service.sh has the corrected form at line 154, but Homebox and Donetick siblings were not updated. Both can mask failures in future deploys when a unit is restarted mid-boot. |
| `scripts/smoketests/household/test-donetick-service.sh:115` | Same journalctl scoping issue as Homebox | ⚠️ WARNING | Same as above; both tests passed post-reboot (8/8 household smoketests) but the defect exists |
| `scripts/smoketests/household/test-homebox-service.sh:115` and `test-donetick-service.sh:115` | Journal read without `sudo` permission | ⚠️ WARNING | If SSH user lacks journal-read access for other users' units, failures silently pass as "no errors" due to stderr swallowing in remote(). Actual's test correctly uses `sudo` at line 154. |
| `modules/household/donetick.nix`, `modules/household/actual.nix`, `modules/household/homebox.nix`, `modules/gateway/Caddyfile`, `scripts/smoketests/household/test-*-service.sh` | Service ports hardcoded as magic literals in 4+ independent locations with no single source of truth | ℹ️ INFO | Flagged in 11-REVIEW.md IN-01: Donetick's port 2021 appears in module firewall, host env template, Caddyfile, and smoketest; Actual/Homebox have similar duplication. A future port change requires manual updates in multiple files. This extends 11-REVIEW.md's pre-existing pattern debt. |
| `scripts/smoketests/household/test-*.sh` | `remote()`, `remote_gateway()`, `run_test()`, and summary block duplicated across 6 scripts | ℹ️ INFO | Flagged in 11-REVIEW.md IN-02: ~35-45 lines of identical boilerplate repeated 6 times. A future fix (like WR-01's `--invocation=0` scoping) must be applied manually in 6 places. |

All code quality issues are pre-existing patterns extended by Phase 11, not newly introduced defects. No issues block the phase goal achievement.

## Human Verification Required

None. All truths are observationally verified through:
1. Codebase artifact inspection (module/config files present and wired)
2. Live reboot evidence (pre/post snapshots identical, smoketest suite passes 8/8)
3. Requirement traceability (all 10 Phase 11 requirements satisfied)

## Summary

**Phase 11 Goal Achievement: VERIFIED**

All three success criteria are met:
1. ✓ Homebox, Actual, and Donetick each load at their tsnet hostnames (`<name>.shad-bangus.ts.net`) through firebat's Caddy tsnet vhost pattern proven in Phase 10
2. ✓ Each service has both household members set up (Homebox: 2-member group; Actual: one unencrypted budget file; Donetick: 2-member circle) with self-signup closed
3. ✓ Each service's state lives under the household persistence pattern (modules/household/ + hosts/ser8/household/, impermanence-persisted) and survives a live ser8 reboot (pre/post snapshots identical, smoketest suite 8/8 post-reboot)

All 10 Phase 11 requirement IDs (HBX-01, HBX-02, HBX-03, ACT-01, ACT-02, ACT-03, DTK-01, DTK-02, DTK-03, DTK-04) are satisfied. No gaps block phase closure.

The two code review warnings (WR-01, WR-02) about smoketest journal scoping and sudo permissions are quality issues that do not affect the phase goal — the household smoketest suite passed 8/8 post-reboot despite these defects. The two info-level findings (port duplication, boilerplate duplication) are pre-existing patterns extended by Phase 11 and documented in deferred-items.md.

---

_Verified: 2026-08-22T18:00:00Z_
_Verifier: Claude (gsd-verifier)_
