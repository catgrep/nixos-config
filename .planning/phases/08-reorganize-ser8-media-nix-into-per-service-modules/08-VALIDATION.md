---
phase: 8
slug: reorganize-ser8-media-nix-into-per-service-modules
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-07-25
---

# Phase 8 - Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Nix evaluator and build checks, ShellCheck 0.11.0, shfmt 3.12.0, statix |
| **Config file** | `flake.nix`, `Makefile`, and a Wave 0 parity projection |
| **Quick run command** | Phase-specific normalized `nix eval --json` projection diff |
| **Full suite command** | `make check && make build-ser8` |
| **Estimated runtime** | To be measured during Wave 0 |

---

## Sampling Rate

- **After every task commit:** Run the targeted projection diff, Nix formatting check, and helper linters for files touched by the task.
- **After every plan wave:** Run the full normalized parity comparison and `make build-ser8`.
- **Before `$gsd-verify-work`:** Run `make check && make build-ser8` with no unresolved warnings.
- **Max feedback latency:** Record the measured quick-check runtime during Wave 0 and keep task-level checks below it.

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 08-W0-01 | TBD | 0 | Phase goal | T-08-01 | Projection excludes secret contents | evaluation regression | Normalized `nix eval --json` projection diff | No, Wave 0 | pending |
| 08-W0-02 | TBD | 0 | Phase goal | N/A | N/A | structural | Phase-specific file and import assertions | No, Wave 0 | pending |
| 08-W0-03 | TBD | 0 | Phase goal | T-08-02 | Generated helpers preserve permissions and ordering | static | `shellcheck hosts/ser8/media/*.sh && shfmt -d hosts/ser8/media/*.sh` | No, Wave 0 | pending |
| 08-FINAL-01 | TBD | Final | Phase goal | T-08-01, T-08-02 | No secret disclosure or permission regression | build | `make check && make build-ser8` | Existing | pending |

*Status values are pending, green, red, and flaky.*

---

## Wave 0 Requirements

- [ ] Create a phase-specific Nix projection that serializes only the behavior contract and never secret contents.
- [ ] Capture a non-secret baseline before any refactor edit, including the current uncommitted Sawnia secret declaration.
- [ ] Define an expected-delta allowlist for Sawnia, AllDebrid declarations, helper store paths, and approved dead-code removals.
- [ ] Add structural assertions for an import-only `default.nix`, required service files, absence of `hosts/ser8/media.nix`, and absence of host policy from reusable modules.
- [ ] Establish narrow, justified SC2016 ignores for jq expressions before enforcing zero ShellCheck findings.
- [ ] Record the current warning baseline and resolve ownership of the Home Manager 25.05 versus nixpkgs 25.11 mismatch before the final zero-warning gate.

---

## Manual-Only Verifications

All phase behaviors have automated verification.

---

## Validation Sign-Off

- [ ] All tasks have an automated verification command or Wave 0 dependency.
- [ ] No three consecutive tasks lack automated verification.
- [ ] Wave 0 covers every missing validation artifact.
- [ ] No command uses watch mode.
- [ ] Feedback latency is measured and bounded.
- [ ] `nyquist_compliant: true` is set in frontmatter.

**Approval:** pending
