---
phase: 8
slug: reorganize-ser8-media-nix-into-per-service-modules
status: planned
nyquist_compliant: true
validation_bootstrap_plan: 08-01
created: 2026-07-25
---

# Phase 8 - Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Nix evaluator and build checks, ShellCheck 0.11.0, shfmt 3.12.0, statix |
| **Config file** | `flake.nix`, `Makefile`, and the Plan 01 Wave 1 parity projection |
| **Quick run command** | Phase-specific normalized `nix eval --json` projection diff |
| **Full suite command** | `make check && make build-ser8` |
| **Estimated runtime** | To be measured during Plan 01 Wave 1 |

---

## Sampling Rate

- **After every task commit:** Run the targeted projection diff, Nix formatting check, and helper linters for files touched by the task.
- **After every plan wave:** Run the full normalized parity comparison and `make build-ser8`.
- **Before `$gsd-verify-work`:** Run `make check && make build-ser8` with no unresolved warnings.
- **Max feedback latency:** Record the measured quick-check runtime during Plan 01 Wave 1 and keep task-level checks below it.

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 08-01-01 | 08-01 | 1 | Phase goal | T-08-03 | HM mismatch blocks before refactor execution | preflight | Warning classifier in repository dev shell | Planned in 08-01 | pending |
| 08-01-02 | 08-01 | 1 | Phase goal | T-08-01, T-08-02 | Projection excludes secret contents and normalizes only approved deltas | evaluation regression | `check-ser8-media-parity.sh capture/check` | Planned in 08-01 | pending |
| 08-01-03 | 08-01 | 1 | Phase goal | T-08-02 | Aggregate prologue, service fragments, and epilogue have explicit order | evaluation regression | Normalized generated-script comparison | Planned in 08-01 | pending |
| 08-05-01 | 08-05 | 5 | Phase goal | T-08-13, T-08-15 | Split helpers preserve sanitization, permissions, and ordering | static | `shellcheck hosts/ser8/media/*.sh && shfmt -d hosts/ser8/media/*.sh` | Planned in 08-05 | pending |
| 08-07-03 | 08-07 | 7 | Phase goal | T-08-20, T-08-21 | No disclosure, permission regression, repository warning, or activation | build | Warning-classified `make check` and `make build-ser8` | Existing commands, planned wrapper | pending |

*Status values are pending, green, red, and flaky.*

---

## Plan 01 Wave 1 Validation Bootstrap

- [ ] Create a phase-specific Nix projection that serializes only the behavior contract and never secret contents.
- [ ] Capture a non-secret baseline before any refactor edit, including the current uncommitted Sawnia secret declaration.
- [ ] Define an expected-delta allowlist for Sawnia, AllDebrid declarations, helper store paths, and approved dead-code removals.
- [ ] Add structural assertions for an import-only `default.nix`, required service files, absence of `hosts/ser8/media.nix`, and absence of host policy from reusable modules.
- [ ] Establish narrow, justified SC2016 ignores for jq expressions before enforcing zero ShellCheck findings.
- [ ] Run a blocking manual preflight that requires the Home Manager 25.05 versus nixpkgs 25.11 mismatch to be resolved outside Phase 8 before extraction starts.
- [ ] Reorder the current aggregate script into explicit prologue 100, services 200 through 700, and epilogue 800 definitions before the first service moves.

---

## Manual-Only Verifications

The Home Manager release mismatch has one blocking human prerequisite checkpoint because dependency changes are outside Phase 8 authorization.
All in-phase behaviors have automated verification.

---

## Validation Sign-Off

- [x] All tasks have an automated verification command or an explicit blocking prerequisite.
- [x] No three consecutive tasks lack automated verification.
- [x] Plan 01 Wave 1 covers every missing validation artifact.
- [x] No command uses watch mode.
- [x] Feedback latency will be measured and bounded during Plan 01 execution.
- [x] `nyquist_compliant: true` is set in frontmatter.

**Approval:** planned; execution evidence remains pending
