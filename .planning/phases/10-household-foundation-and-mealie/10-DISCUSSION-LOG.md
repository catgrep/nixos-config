# Phase 10: Household Foundation and Mealie - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-08-17
**Phase:** 10-household-foundation-and-mealie
**Areas discussed:** Mealie version commitment, PostgreSQL major pin, Endpoint and .vofi handling, Setup and verification

---

## Mealie version commitment

| Option | Description | Selected |
|--------|-------------|----------|
| 3.22.0 via unstable | `services.mealie.package = unstable.mealie`; already in the locked pin, module contract identical | ✓ |
| 3.16.0 from 26.05 stable | No override, Hydra-cached, ~6 releases behind | |

**User's choice:** 3.22.0 via unstable
**Notes:** Alembic migrations are one-way and no backups exist until Phase 11, so the first-boot version is the kept version.

| Option | Description | Selected |
|--------|-------------|----------|
| flake.lock gates drift | unstable moves only on deliberate staged `nix flake update` commits; no bump that moves Mealie until Phase 11 backups exist | ✓ |
| Pin Mealie to exact rev | Fully explicit upgrades, more machinery | |

**User's choice:** flake.lock gates it

---

## PostgreSQL major pin

| Option | Description | Selected |
|--------|-------------|----------|
| postgresql_17 | 26.05 default (17.11), most ecosystem mileage, supported to Nov 2029 | ✓ |
| postgresql_18 | Newest (18.6), longest runway, less mileage | |
| postgresql_16 | What stateVersion would silently pick; no advantage | |

**User's choice:** postgresql_17

---

## Endpoint and .vofi handling

| Option | Description | Selected |
|--------|-------------|----------|
| Tailscale tsnet URL | `https://mealie.shad-bangus.ts.net` via `bind tailscale/mealie`, matching existing services | ✓ |
| https://mealie.vofi | Matches roadmap text but unreachable (pi4 AdGuard disconnected) | |

**User's choice:** Tailscale tsnet URL as canonical endpoint and BASE_URL

| Option | Description | Selected |
|--------|-------------|----------|
| Skip .vofi entirely | tsnet vhost only; no dead config | ✓ |
| Add Caddy vhost only | Visual consistency, untested | |
| Add vhost + AdGuard rewrite | Full parity, both halves untestable | |

**User's choice:** Skip .vofi entirely

| Option | Description | Selected |
|--------|-------------|----------|
| Update ROADMAP + REQUIREMENTS now | Reword criterion 1 and MEAL-03 before planning; keep .vofi smoketests skip-flagged | ✓ |
| Leave docs, override via CONTEXT.md | Roadmap would keep asserting an unsatisfiable criterion | |

**User's choice:** Update both now (applied in this session)

| Option | Description | Selected |
|--------|-------------|----------|
| Already on the tailnet | Second member's device ready for UAT | ✓ |
| Needs tailnet invite/setup | Would add a manual onboarding task | |

**User's choice:** Already on the tailnet

---

## Setup and verification

| Option | Description | Selected |
|--------|-------------|----------|
| Declarative + manual UI | ALLOW_SIGNUP=false in config; accounts/household/seeding in UI | ✓ |
| Script via Mealie API | Repeatable but more code for one-shot setup | |
| Fully manual UI | Registration state invisible to config | |

**User's choice:** Declarative + manual UI

| Option | Description | Selected |
|--------|-------------|----------|
| Top-level ser8/all.sh fan-out | New entry point calls media/all.sh + household/all.sh; scales for Phases 11-13 | ✓ |
| Extend media/all.sh | No deploy.yaml change but misnamed coupling | |

**User's choice:** Top-level ser8/all.sh fan-out

| Option | Description | Selected |
|--------|-------------|----------|
| Validate boot first | Reboot ser8 before Mealie exists | |
| Fold into MEAL-05 | Persistence reboots double as first-boot validation | |

**User's choice:** Neither — user corrected the premise: ser8 was already rebooted on 26.05 (STATE.md's "neither x86 host rebooted" record is stale). MEAL-05 reboots are pure persistence checks.

---

## Claude's Discretion

- postgresql pin placement and module option shape within the two-layer pattern
- `/var/lib/postgresql` ownership verification on first start
- `--forwarded-allow-ips` / proxy-header details
- Where Takeout archive JSON-structure notes are recorded
- ser8/all.sh fan-out exit-code/output handling

## Deferred Ideas

- Migrate `.vofi` hostnames to public `vofi.dev` domain — pre-existing pending todo, reviewed (match score 0.9) but not folded; user ruled it separate.
