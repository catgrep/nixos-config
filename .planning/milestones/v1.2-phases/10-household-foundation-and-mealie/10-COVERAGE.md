# Phase 10 — External API Coverage Matrix

**Decided:** 2026-08-17
**External API surface in scope:** the Mealie HTTP API (v3.22.0) on ser8, reached over loopback for verification and through the firebat tsnet vhost for endpoint probes.

## Why this matrix exists

Phase 10 touches an external application's HTTP surface. Without an enumerated matrix, "we integrated Mealie" silently means "we touched whatever the smoketests happened to exercise", and every un-built capability becomes an invisible hole discovered later by a household member who reasonably expected it to work.

The dominant constraint here is **D-10**: one-time setup is manual UI work, with no bootstrap scripting through the Mealie API. That decision opts this phase out of most of the write surface on purpose. This matrix records that as a decision with a reason, not as an oversight.

## Coverage matrix

| Capability | Endpoint / surface | Status | Reason |
|---|---|---|---|
| Instance liveness and version | `GET /api/app/about` | COVERED | Probed by `scripts/smoketests/household/test-mealie-endpoint.sh` as part of the serving-status check |
| Authentication — negative case | `POST /api/auth/token` with the shipped default administrator credentials | COVERED | Asserted to return a status other than 200 (MEAL-02, threat T-10-02). This is the security-relevant direction |
| Authentication — positive case | `POST /api/auth/token` with real household credentials | COVERED (manual) | Exercised by human login in plans 10-05, 10-06, and 10-07. Deliberately not scripted: the repository must hold no household credential (threat T-10-04) |
| Session durability | token validity across two reboots | COVERED | Plan 10-07 re-tests a pre-reboot session to prove the token-signing secret persisted |
| Recipe image serving | `GET` on a recipe image URL | COVERED | Plan 10-07 asserts 200 with a stable content length against the SHA-256 baseline (Pitfall 7) |
| Shopping lists — read and write | `/api/households/shopping/lists`, `/api/households/shopping/items` | OPT-OUT | D-10 makes bootstrap manual; MEAL-04 is verified through two authenticated browser sessions and by direct database counts, not through the API |
| Administrator user creation | `POST /api/admin/users` | OPT-OUT | D-10. Account creation is a UI action in plan 10-06, and scripting it would require holding a credential the repository must not contain |
| Household and group administration | `/api/groups/households` | OPT-OUT | D-10. Household placement is verified in the UI and independently in the database |
| Foods, Units, and Labels seeding | `/api/groups/seeders/*` | OPT-OUT | D-10, plus a hard technical reason: re-seeding fails on a unique constraint over food name and group, so an idempotent script is not straightforwardly buildable. Seeding is a once-only UI action |
| Foods and Units read | `/api/foods`, `/api/units` | OPT-OUT | Verified by direct row counts in PostgreSQL instead, which is stronger evidence than an API response for MEAL-04 |
| Recipe create, read, update, delete | `/api/recipes` | OPT-OUT | No requirement in this phase asks for programmatic recipe management. The single recipe this phase creates is a real household recipe created in the UI |
| Recipe scraping and import | `/api/recipes/create/url` and related | OPT-OUT | Not requested by any requirement. REQUIREMENTS.md Out of Scope also excludes Mealie's AI and OpenAI import features |
| Meal plans | `/api/households/mealplans` | OPT-OUT | No Phase 10 requirement. Meal planning is household usage, not phase scope |
| Cookbooks, tags, categories, tools | `/api/organizers/*` | OPT-OUT | No Phase 10 requirement |
| Notifiers and webhooks | household integrations | OPT-OUT | RESEARCH.md marks these unused this phase; no requirement asks for them |
| Backup and restore | `/api/admin/backups` | OPT-OUT | Phase 11 owns backups (BKP-01, BKP-02, BKP-05), and RESEARCH.md establishes the backup artifact must be a `pg_dump` plus the image tree rather than Mealie's own backup endpoint |
| Home Assistant integration via API token | API token management | OPT-OUT | Deferred to Future Requirements HAI-01 in REQUIREMENTS.md |
| OIDC and SMTP configuration | `credentialsFile` settings | OPT-OUT | Explicitly out of scope for this phase; both would introduce secret material that Phase 14 SEC-02 wants absent |
| Public or unauthenticated exposure | any endpoint from outside the tailnet | OPT-OUT | REQUIREMENTS.md Out of Scope forbids public exposure, port forwarding, and inbound ACME. The negative-access proof is Phase 14 SEC-01, and Phase 10 does not claim it |

## Summary

- **COVERED:** 5 capabilities — all verification-shaped, all in the direction that catches a security or durability failure.
- **OPT-OUT:** 14 capabilities — 6 by D-10 (manual bootstrap), 6 by requirement scope, 2 by explicit REQUIREMENTS.md exclusions.
- **Undecided:** 0.

Every OPT-OUT carries a reason. None is "we ran out of time".

## Reassessment triggers

This matrix should be revisited if any of these change:

- D-10 is superseded and API-driven bootstrap becomes acceptable — the six manual-bootstrap opt-outs all move to a decision.
- Phase 11 chooses Mealie's own backup endpoint over `pg_dump` plus the image tree.
- Future Requirement HAI-01 is promoted, which turns API token management into a covered capability.
