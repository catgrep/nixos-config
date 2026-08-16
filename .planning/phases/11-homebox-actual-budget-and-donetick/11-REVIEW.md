---
phase: 11-homebox-actual-budget-and-donetick
reviewed: 2026-08-22T08:07:48Z
depth: standard
files_reviewed: 22
files_reviewed_list:
  - Makefile
  - flake.nix
  - hosts/ser8/household/actual.nix
  - hosts/ser8/household/default.nix
  - hosts/ser8/household/donetick.nix
  - hosts/ser8/household/homebox.nix
  - hosts/ser8/impermanence.nix
  - modules/gateway/Caddyfile
  - modules/household/actual.nix
  - modules/household/default.nix
  - modules/household/donetick.nix
  - modules/household/homebox.nix
  - packages/donetick/default.nix
  - packages/donetick/frontend.nix
  - scripts/smoketests/household/all.sh
  - scripts/smoketests/household/test-actual-endpoint.sh
  - scripts/smoketests/household/test-actual-service.sh
  - scripts/smoketests/household/test-donetick-endpoint.sh
  - scripts/smoketests/household/test-donetick-service.sh
  - scripts/smoketests/household/test-homebox-endpoint.sh
  - scripts/smoketests/household/test-homebox-service.sh
  - scripts/validation/test-actual-module.sh
  - scripts/validation/test-donetick-module.sh
  - scripts/validation/test-homebox-module.sh
findings:
  critical: 0
  warning: 2
  info: 2
  total: 4
status: issues_found
---

# Phase 11: Code Review Report

**Reviewed:** 2026-08-22T08:07:48Z
**Depth:** standard
**Files Reviewed:** 22
**Status:** issues_found

## Summary

Reviewed the Homebox, Actual Budget, and Donetick additions: the two-layer `modules/household/` + `hosts/ser8/household/` module pattern, the locally-packaged `packages/donetick` derivation (Go backend + separately-sourced React frontend), the household smoketest suite, and the offline validation gates. `nixfmt --check`, `statix check`, and `shellcheck` all pass clean on every reviewed file, and no hardcoded secrets, injection vectors, or eval/exec misuse were found — the Donetick JWT secret is correctly threaded through a sops-nix template placeholder rather than a literal.

No Critical/security-blocking issues were found. The two Warning-level findings are both in the smoketest suite: an inconsistent `journalctl` scoping/permission pattern was fixed for Actual's service check (in response to a documented real false positive) but not backported to the sibling Homebox and Donetick checks added in the same phase, leaving those two exposed to the same failure mode. The Info-level findings are pre-existing-pattern quality debt (magic-number port duplication, boilerplate duplication across six near-identical smoketest scripts) that this phase extended rather than introduced, but which is now three times larger as a result.

## Warnings

### WR-01: Donetick and Homebox service smoketests use boot-scoped journalctl instead of invocation-scoped, reintroducing a false-positive class already found and fixed for Actual in this same phase

**File:** `scripts/smoketests/household/test-donetick-service.sh:111-129` and `scripts/smoketests/household/test-homebox-service.sh:111-129`
**Issue:**
`scripts/smoketests/household/test-actual-service.sh:150-168` deliberately scopes its startup-error check to `journalctl -u "$ACTUAL_UNIT" --priority=err --invocation=0` (the unit's *current* start), with an extensive comment explaining why: NixOS activations happen without a reboot, so a boot-scoped `-b` query keeps reporting a previous, now-fixed generation's startup failure as evidence about the current, successfully-running one. The comment states this exact false positive was "found and produced" during this plan's own deploy history.

`test-donetick-service.sh:115` and `test-homebox-service.sh:115` — both new in this same phase — still use `journalctl -b -u "$UNIT" --priority=err --no-pager -q -o cat`, i.e. the boot-scoped form the Actual fix was written to replace. Any activation of ser8 that restarts Donetick or Homebox more than once within the same boot (a routine occurrence during iterative deploys) can now reproduce the identical false failure that was just diagnosed and fixed one file over.

**Fix:**
Apply the same `--invocation=0` scoping used in `test-actual-service.sh:154` to both sibling checks:
```bash
# test-donetick-service.sh and test-homebox-service.sh, matching test-actual-service.sh:154
errors=$(remote sudo journalctl -u "$UNIT" --priority=err --no-pager -q -o cat --invocation=0)
```

### WR-02: Donetick and Homebox service smoketests read the journal without `sudo`, unlike the just-fixed Actual counterpart — risks a silent false pass instead of a false failure

**File:** `scripts/smoketests/household/test-donetick-service.sh:115` and `scripts/smoketests/household/test-homebox-service.sh:115`
**Issue:**
`test-actual-service.sh:154` runs `remote sudo journalctl -u ...`. `test-donetick-service.sh:115` and `test-homebox-service.sh:115` run the equivalent check as plain `remote journalctl -b -u ...` with no `sudo`. If the SSH deploy user is not a member of a group with journal-read rights for other users' units (the Donetick/Homebox services run as their own static system users, not the SSH user), `journalctl` can fail or return nothing for permission reasons rather than because there really are no error-level entries. Because `remote()` swallows stderr (`2>/dev/null`) and the check treats empty output as "pass" (`test_*_no_startup_errors`'s `if [ -z "$errors" ]; then pass ...`), a permission failure and a genuinely clean journal are indistinguishable — this check can pass "green" while silently checking nothing at all.

**Fix:**
Add `sudo` to the journal read in both scripts, matching `test-actual-service.sh:154`:
```bash
errors=$(remote sudo journalctl -u "$UNIT" --priority=err --no-pager -q -o cat --invocation=0)
```

## Info

### IN-01: Service ports are duplicated as unlinked magic literals across module, host config, Caddyfile, and smoketest, with no single source of truth

**File:** `modules/household/donetick.nix:72`, `hosts/ser8/household/donetick.nix:45`, `modules/gateway/Caddyfile:235`, `scripts/smoketests/household/test-donetick-endpoint.sh:36`; also `hosts/ser8/household/actual.nix:12-14` (undocumented) vs. `modules/gateway/Caddyfile:227`
**Issue:**
Donetick's port `2021` is hardcoded independently in the module's firewall rule (`modules/household/donetick.nix:72`), the env template's `DT_SERVER_PORT` (`hosts/ser8/household/donetick.nix:45`), the Caddyfile's `reverse_proxy` target (`modules/gateway/Caddyfile:235`), and the smoketest's `DONETICK_PORT` constant — four independent literals with nothing tying them together, and unlike `modules/household/mealie.nix:37` (which derives its firewall rule from `config.services.mealie.port`), the `modules/household/donetick.nix` custom module doesn't expose a `port` option at all, so there is no config value to derive from even if the other sites wanted to.

Actual's port coupling (`services.actual`'s default port 3000, documented only in a comment in `hosts/ser8/household/actual.nix:12-14`, vs. the literal `3000` in `modules/gateway/Caddyfile:227`) is worse: nothing in the repository documents that the Caddyfile's reverse-proxy target must be kept in sync with Actual's upstream-module default port, so a future change to `services.actual.settings.port` (or an upstream default change) would silently 502 at the proxy with no test or comment pointing at the cause. Homebox has the same Caddyfile-vs-setting gap, though `modules/household/homebox.nix:27-32` at least documents (without fixing) the settings-vs-firewall half of it.

**Fix:** Add a `port` option to `modules/household/donetick.nix` (mirroring Mealie's pattern), derive the firewall rule and a comment cross-referencing the Caddyfile from it, and add a short comment in `hosts/ser8/household/actual.nix` and `modules/household/homebox.nix` noting the Caddyfile's hardcoded reverse-proxy port must be kept in sync, the same way `modules/household/homebox.nix:30-32` already documents the firewall half.

### IN-02: `remote`/`remote_gateway`/`remote_ok`/`run_test` boilerplate is duplicated near-verbatim across all six new household smoketest scripts

**File:** `scripts/smoketests/household/test-actual-endpoint.sh:49-82`, `test-actual-service.sh:61-95`, `test-donetick-endpoint.sh:49-82`, `test-donetick-service.sh:43-77`, `test-homebox-endpoint.sh:49-82`, `test-homebox-service.sh:43-77`
**Issue:**
Each of the six new smoketest scripts defines its own copy of `run_test()`, `remote()` (and `remote_gateway()`/`remote_ok()` variants), the `tests_run`/`tests_passed` tally, and the final pass/fail summary block — roughly 35-45 lines of identical logic repeated six times (this phase alone tripled the count from the two pre-existing Mealie scripts). A future fix to the escaping/error-handling logic in `remote()` (as WR-01/WR-02 above would require) now has to be applied in six places by hand, and already has drifted once (Actual has `--invocation=0` + `sudo`; its two siblings do not).
**Fix:** Extract `remote()`, `remote_gateway()`, `remote_ok()`, `run_test()`, and the summary block into `scripts/smoketests/lib/remote.sh` (alongside the existing `scripts/smoketests/lib/fanout.sh`) and source it from each script, the way `scripts/lib/all.sh` is already shared.

---

_Reviewed: 2026-08-22T08:07:48Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
