---
phase: 10
slug: household-foundation-and-mealie
# status lifecycle: draft (seeded by plan-phase) → validated (set by validate-phase §6)
# audit-milestone §5.5 distinguishes NOT-VALIDATED (draft) from PARTIAL (validated + nyquist_compliant: false) (#2117)
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-08-17
---

# Phase 10 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | shell smoketests (`scripts/smoketests/`) + `nix` eval / dry-run builds |
| **Config file** | `deploy.yaml` (smoketest entry points) |
| **Quick run command** | `nix build .#nixosConfigurations.ser8.config.system.build.toplevel --dry-run` |
| **Full suite command** | `make check` |
| **Estimated runtime** | ~120 seconds |

---

## Sampling Rate

- **After every task commit:** Run `nix build .#nixosConfigurations.<host>.config.system.build.toplevel --dry-run` for the affected host
- **After every plan wave:** Run `make check`
- **Before `/gsd-verify-work`:** Full suite must be green
- **Max feedback latency:** 180 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 10-01 T1 | 10-01 | 1 | FOUND-03, FOUND-04, MEAL-01, MEAL-02, MEAL-03 | T-10-01, T-10-04, T-10-05 | Signup closed as a string; no credential in the Nix store; postgres major pinned explicitly | eval | `nix build .#nixosConfigurations.ser8.config.system.build.toplevel --dry-run` plus five `nix eval` assertions plus `caddy adapt` listener check | ✅ Makefile, caddy in dev shell | ⬜ pending |
| 10-01 T2 | 10-01 | 1 | FOUND-04, MEAL-01, MEAL-02, MEAL-03 | T-10-01, T-10-05 | Offline gate that discriminates, proven by mutation | eval | `./scripts/validation/test-mealie-module.sh` plus a mutated copy exiting non-zero | ❌ created by this task | ⬜ pending |
| 10-01 T3 | 10-01 | 1 | FOUND-03 | — | No new evaluation warning class from enabling PostgreSQL | eval | `make check` | ✅ Makefile | ⬜ pending |
| 10-02 T1 | 10-02 | 1 | IMP-01 | T-10-11, T-10-12 | No credential captured; list count recorded to detect a partial export | manual | human action at takeout.google.com | manual | ⬜ pending |
| 10-02 T2 | 10-02 | 1 | IMP-01 | T-10-10 | Structure and counts only; no archive committed | file | `test -f .planning/research/google-tasks-takeout.md` plus checklist and size greps | ❌ created by this task | ⬜ pending |
| 10-03 T1 | 10-03 | 1 | MEAL-01, MEAL-03 | T-10-14 | Aggregate exit status via `run_suite`, never a hand-rolled loop; D-03 skip flags untouched | lint | `shellcheck`, `shfmt -d`, `bash -n`, `grep -c 'household/all.sh'` | ❌ created by this task | ⬜ pending |
| 10-03 T2 | 10-03 | 1 | FOUND-04, MEAL-01, MEAL-04, MEAL-05 | T-10-06, T-10-13, T-10-14 | Both state stores asserted; ownership and mode asserted; escape hatch uncommitted | lint | `shellcheck`, `shfmt -d`, `bash -n`, usage-exit check, structural greps | ❌ created by this task | ⬜ pending |
| 10-03 T3 | 10-03 | 1 | MEAL-02, MEAL-03 | T-10-01, T-10-02 | Default credentials rejected; signup value non-empty in the deployed environment | lint | `shellcheck`, `shfmt -d`, `bash -n`, `grep -c '"mealie"'` on the gateway node list | ❌ created by this task | ⬜ pending |
| 10-04 T1 | 10-04 | 2 | FOUND-04 | T-10-05, T-10-16 | Empty-PostgreSQL premise proven before anything starts; no destructive cleanup | smoke | `make status` plus a remote count of numeric major-version directories | ✅ Makefile, deploy.yaml | ⬜ pending |
| 10-04 checkpoint | 10-04 | 2 | FOUND-04, MEAL-01 | T-10-05, T-10-15 | The one-way step taken as a recorded human decision | manual | blocking decision checkpoint | manual | ⬜ pending |
| 10-04 T2 | 10-04 | 2 | FOUND-03, FOUND-04, MEAL-01, MEAL-04 | T-10-05, T-10-06, T-10-14, T-10-15 | Migration proven by a clean journal, not by unit liveness; ownership 750; state directory not a symlink | smoke | `MEALIE_ALLOW_UNSEEDED=1 ./scripts/smoketests/household/all.sh ser8` | ⬜ from 10-03 | ⬜ pending |
| 10-05 T1 | 10-05 | 3 | MEAL-03 | T-10-17 | Gateway route set unchanged in the default server | smoke | `make fmt-caddy`, `git diff --exit-code`, `./scripts/smoketests/gateway/all.sh firebat` | ✅ existing suite | ⬜ pending |
| 10-05 T2 | 10-05 | 3 | MEAL-03 | T-10-03, T-10-08, T-10-19 | Reachability asserted from a tailnet member, rejecting 502 and 000 | smoke | `./scripts/smoketests/gateway/all.sh firebat`; `./scripts/smoketests/household/test-mealie-endpoint.sh ser8` | ⬜ from 10-03 | ⬜ pending |
| 10-05 checkpoint | 10-05 | 3 | MEAL-03 | T-10-18 | Publicly issued certificate confirmed in a real browser | manual | blocking human-verify | manual | ⬜ pending |
| 10-06 T1 | 10-06 | 4 | MEAL-02, MEAL-04 | T-10-02, T-10-04, T-10-21 | Credential change and same-household placement; seed exactly once | manual | blocking human-action | manual | ⬜ pending |
| 10-06 T2 | 10-06 | 4 | MEAL-04 | T-10-07, T-10-20 | Shared list proven by cross-session edit, not by two logins | manual | blocking human-verify | manual | ⬜ pending |
| 10-06 T3 | 10-06 | 4 | MEAL-02, MEAL-04 | T-10-01, T-10-02, T-10-20 | Default credentials dead; signup value non-empty; one household and one list in the database | smoke | `./scripts/smoketests/household/all.sh ser8` with no escape hatch | ⬜ from 10-03 | ⬜ pending |
| 10-07 T1 | 10-07 | 5 | FOUND-04, MEAL-05 | T-10-22 | Negative control planted so a pass cannot come from an inert rollback | smoke | `./scripts/smoketests/household/all.sh ser8` plus a recorded baseline | ⬜ from 10-03 | ⬜ pending |
| 10-07 T2 | 10-07 | 5 | MEAL-05 | T-10-24 | Two consecutive reboots with a recorded recovery generation | manual | blocking human-action | manual | ⬜ pending |
| 10-07 T3 | 10-07 | 5 | FOUND-04, MEAL-05 | T-10-05, T-10-06, T-10-22, T-10-23 | Control marker absent; image SHA-256 identical; pre-reboot session still valid | smoke | `./scripts/smoketests/household/all.sh ser8` plus baseline-to-observed comparison | ⬜ from 10-03 | ⬜ pending |
| 10-08 T1 | 10-08 | 5 | IMP-01 | T-10-26 | Archive extracted outside the working tree | manual | blocking human-action | manual | ⬜ pending |
| 10-08 T2 | 10-08 | 5 | IMP-01 | T-10-10, T-10-25, T-10-27 | Structure and counts only; recurrence answered as a recorded observation | file | checklist completion greps plus `git status` archive greps | ⬜ from 10-02 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

All five gaps are created inside Wave 1, before anything they gate is deployed.

- [ ] `scripts/validation/test-mealie-module.sh` — offline eval gate covering FOUND-04, MEAL-01, MEAL-02, MEAL-03 (plan 10-01 Task 2)
- [ ] `Makefile` `check` target — the new validation script joined to the three existing ones (plan 10-01 Task 2)
- [ ] `scripts/smoketests/household/all.sh` — area entry point, name fixed by the `deploy.yaml` convention (plan 10-03 Task 1)
- [ ] `scripts/smoketests/household/test-mealie-service.sh` — unit, port, database, ownership, seed counts, both state stores (plan 10-03 Task 2)
- [ ] `scripts/smoketests/household/test-mealie-endpoint.sh` — tsnet URL, default-credential rejection, deployed base URL and signup value (plan 10-03 Task 3)
- [ ] `scripts/smoketests/ser8/all.sh` — append the household area to the existing `TESTS` fan-out (plan 10-03 Task 1)
- [ ] `scripts/smoketests/gateway/test-tailscale.sh` — append `mealie` to `EXPECTED_NODES` (plan 10-03 Task 3)
- [ ] Confirm the real Mealie 3.22.0 Foods and Units table names before the assertion is trusted (plan 10-04 Task 2, closing RESEARCH.md assumption A3)

*No framework install needed: every tool is already in the development shell.*

---

## Gating Notes

`make smoketests-ser8` exits 1 today because of the pre-existing NordVPN tunnel failure this phase does not own. It must NOT be a phase gate. The gate is the household area's own exit status plus a per-area diff against the transcript captured before each activation, which is the pattern Phase 9 plan 05 established.

`MEALIE_ALLOW_UNSEEDED=1` is used exactly once, on the command line, in plan 10-04 Task 2. It must not appear in `deploy.yaml`, in any suite entry point, or in any other committed file. Plans 10-03, 10-04, and 10-06 each carry an acceptance criterion greping for it.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Both users log in and share one shopping list | MEAL-02, MEAL-04 | Requires interactive browser login as two accounts | Log in as each household member at `https://mealie.shad-bangus.ts.net`, add an item to the shared list from one account, confirm visibility from the other |
| Data survives two consecutive ser8 reboots | MEAL-05, FOUND-04 | Requires physical reboots of live host | Create a recipe with image, reboot ser8 twice, confirm recipe and image still present |
| Google Takeout export requested and JSON shape recorded | IMP-01 | External Google service, human account action | Request Tasks export at takeout.google.com, download archive, record real JSON structure in phase notes |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 180s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
