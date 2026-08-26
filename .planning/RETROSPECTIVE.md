# Project Retrospective

*A living document updated after each milestone. Lessons feed forward into future planning.*

## Milestone: v1.2 — Household Stack

**Shipped:** 2026-08-23
**Phases:** 3 (09-11) | **Plans:** 18 of 23 executed | **Tasks:** 52

### What Was Built

- Whole fleet on NixOS 26.05: ser8 and firebat switched and reboot-proven; both Pis re-platformed from the `nvmd` fork onto upstream nixpkgs + pinned `nixos-hardware`.
- Household service layer (`modules/household/` + `hosts/ser8/household/`) with pinned PostgreSQL 17, static system users, impermanence-safe persistence, and eval gates in `make check`.
- Four apps live behind firebat Caddy tsnet vhosts with Let's Encrypt certs: Mealie 3.22.0, Homebox 0.25.0, Actual Budget, Donetick (packaged from source — the repo's first Go and npm packages).
- Household smoketest area asserting unit state, endpoints, and both state stores, joined to the ser8 and gateway suites.

### What Worked

- The tracer-plan pattern: Phase 10 built the full pattern once (module, persistence, vhost, smoketests, bootstrap), and Phase 11 stamped it three more times at roughly half the per-plan duration.
- The 2026-08-20 descope: dropping backups/TLS/import ceremony got all four apps into daily use within a week instead of stalling on infrastructure.
- Real activation over inference: the caddy vendor-hash mismatch, the revoked Tailscale auth key, and the sops restart-trigger bug were all invisible to `nix build --dry-run` and only surfaced under real builds and activations.
- Per-area smoketest baseline comparison, which kept pre-existing failures (NordVPN, sabnzbd) from blocking unrelated plans while never relaxing the failing tests.

### What Was Inefficient

- Phase 9 gap-closure plans (09-08/09-09) were written but never executed, so the phase closed `gaps_found` and the always-pass smoketests it identified are still live.
- Plan-summary one-liners were inconsistent, so the milestone-close accomplishment extraction produced junk lines ("The gate fix.", "Outcome (b).") that had to be hand-curated.
- The dev machine's broken x86 remote-builder config forced a `nix copy --derivation` + remote `nix-store --realise` workaround for every Donetick hash iteration.

### Patterns Established

- Household service shape: reusable module + host-policy slice, static user with DynamicUser off, `StateDirectoryMode = 0750`, persistence entry, tsnet vhost, smoketests asserting unit + endpoint + both state stores.
- `sops.templates.<name>.restartUnits` set explicitly for any template whose content can change post-deploy.
- Bootstrap-then-close for registration: open self-signup explicitly during bootstrap, close it after, verify with a real signup attempt.
- Smoketests distinguish "could not check" from "checked, found nothing" (journalctl `--invocation=0`, SSH failure ≠ pass).

### Key Lessons

1. A skip counted as a pass is worse than no test — the vacuous TLS subtests and the fake pi smoketest entries both reported coverage that did not exist.
2. Shared long-lived credentials (the Tailscale auth key) need an explicit validity precondition, verified by restarting the consumer on purpose; a running process masks a dead key indefinitely.
3. Nix evaluation-level evidence cannot substitute for a real build or activation; every consequential v1.2 failure was in the gap between the two.
4. Upstream module defaults move between releases (Homebox registration flipped closed, servarr UMask changed, `toString false` = ""): re-verify every assumption at a channel bump rather than porting configs blind.

### Cost Observations

- Model mix: not tracked this milestone
- Sessions: ~18 plan-execution sessions across 7 days (2026-08-16 → 2026-08-22)
- Notable: average plan duration stayed near 30 minutes; the two multi-session plans (10-06 bootstrap, 11-04 packaging) were both human-gated, not model-limited

---

## Cross-Milestone Trends

### Process Evolution

| Milestone | Phases | Plans | Key Change |
|-----------|--------|-------|------------|
| v1.0 | 3 | 6/6 | First GSD milestone; declarative HA/Frigate integration |
| v1.1 | 5 | 9/9 executed | Phases 5-7 shelved mid-milestone rather than blocking |
| v1.2 | 3 | 18/23 | Descope-and-ship: ceremony deferred, apps first; override closeout with recorded gaps |

### Top Lessons (Verified Across Milestones)

1. Shelving or descoping work explicitly (v1.1 phases 5-7, v1.2 backups/TLS/import) beats letting a milestone stall — but the parked items must carry their requirement IDs forward.
2. Declarative-only claims need one live verification per phase; every milestone has caught at least one config that evaluated fine and misbehaved on the host.
