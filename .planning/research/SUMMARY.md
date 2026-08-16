# Project Research Summary

**Project:** v1.2 Household Stack (Mealie, Donetick, Homebox, Actual Budget on the catgrep/nixos-config homelab)
**Domain:** Self-hosted household web apps deployed declaratively into an existing NixOS flake homelab
**Researched:** 2026-08-16
**Confidence:** HIGH for repo integration facts and nixpkgs module behavior (read directly from pinned source). MEDIUM for Donetick runtime behavior and Google Takeout export fidelity (no nixpkgs module to verify against; Takeout envelope undocumented by Google).

## Executive Summary

This milestone is not really "build four apps" -- all four ship complete upstream products. The actual work is threefold: (A) declarative NixOS deployment (module, persistence, secrets, Caddy/DNS, backup) for four services with three different lifecycle shapes; (B) a written, repeatable bootstrap checklist for the in-app configuration that cannot be made declarative (creating the first household/circle/group, inviting a second user, seeding reference data, opening then closing registration); and (C) a one-time Google Tasks -> Donetick import script, which is the only genuinely new software in the milestone. All three researchers independently converged on the same top risk: impermanence persistence is the single most consequential place to get wrong, because Mealie and Actual use `DynamicUser` (state lands at `/var/lib/private/<svc>`, already covered by existing persistence -- do NOT add new entries) while Homebox uses a static user (state at `/var/lib/homebox`, NOT currently covered -- must be added explicitly with a tmpfiles ownership rule). Getting this backwards either breaks the service outright or silently loses data on the next reboot, and only a real reboot test catches it.

The recommended approach: bump the flake to `nixos-26.05` first (25.11 has been EOL since 2026-06-30, and materially improves the Actual and Mealie modules), then ship Mealie alone on PostgreSQL and let it soak before touching anything else, build the backup/restore pipeline second (proving pg_dump + SQLite `.backup` + a real restore drill against Mealie before three more services need the same pattern), then Homebox and Actual (either order -- both have simple nixpkgs modules), and land Donetick plus the Google Tasks import last, since Donetick is the only service with real engineering unknowns (no nixpkgs package exists at all) and the import depends on Donetick already having real accounts.

Key risks and mitigations: (1) PostgreSQL's major version is silently chosen by `stateVersion` -- pin `services.postgresql.package` explicitly on the very first deploy, before data exists. (2) Actual Budget is non-functional without genuinely trusted TLS (`crypto.subtle`/`SharedArrayBuffer` require a real secure context) -- this Caddyfile currently installs trust nowhere, so CA distribution to household devices must be a deliberate deliverable, and is the reason Actual should deploy last among the four native/module services. (3) Backups are not uniform: Mealie needs a Postgres dump *and* its image directory, Actual needs `account.sqlite` *and* the entire `user-files/` blob tree (a SQLite-only Actual backup restores nothing useful), and none of the three SQLite services may ever be `cp`'d live. (4) Google Takeout has no recurrence data at all -- this is not a parsing gap, the field does not exist in the export -- so recurring chores must be re-authored by hand in Donetick using a small operator-authored map, while one-off todos import automatically. (5) Donetick's packaging approach is a genuinely open decision between the researchers (see below) and should be resolved explicitly, in Nix, before the Donetick phase starts.

## Key Findings

### Recommended Stack

Bump `nixpkgs` to `nixos-26.05` as a precondition (25.11 EOL'd 2026-06-30; 26.05 carries a materially better `services.actual` module with real `user`/`group`/`dataDir` options instead of hard-coded `DynamicUser`, and lets Mealie's package be overridden to 3.22.0 safely since the module is byte-identical across branches). Use native NixOS modules for Mealie (PostgreSQL via `database.createLocally = true`, unix-socket peer auth, zero secrets), Homebox (pin to 0.25.0 -- 0.26.x requires an `HBOX_AUTH_API_KEY_PEPPER` the nixpkgs module doesn't set and will boot-loop), and Actual (26.05 module, keep `DynamicUser`). Donetick has no nixpkgs module or package on any branch -- see the open packaging decision below. Google Tasks import uses Takeout JSON (not the live API -- neither source has recurrence, so the API's only advantage, repeatability, is worthless for a one-time import) plus a Python stdlib script (no third-party deps) that authenticates to Donetick's *internal* `POST /api/v1/chores` endpoint, never the public `eapi/v1/chore` endpoint (which hard-codes `frequencyType: once` and cannot create recurring chores).

**Core technologies:**
- `nixpkgs` @ `nixos-26.05` -- base channel bump; non-negotiable given EOL, and unlocks better Actual/Mealie modules
- `services.mealie` (native, PostgreSQL) -- recipe manager; module handles DB wiring, needs `BASE_URL` and `--forwarded-allow-ips` overrides behind Caddy
- `services.homebox` (native, SQLite, pin 0.25.0) -- inventory; static user means persistence needs explicit new entries
- `services.actual` (native, 26.05 module) -- budgeting; keep `DynamicUser`; requires genuinely trusted TLS to function at all
- Donetick -- packaging approach is an **open decision**, see below
- Python stdlib (`json`, `urllib.request`, `datetime`) -- Google Tasks importer, one-shot script, not a service

### Expected Features

Almost every user-visible feature is already built upstream. The milestone's real feature work is: (A) declarative deployment, (B) an irreducible manual bootstrap checklist per service (no declarative path exists for "user B is in the same household as user A" in any of the four apps), and (C) the Google Tasks import. Mealie is the only service with no bootstrap ordering hazard (it ships a default admin, so signup can stay closed from day one); Donetick and Homebox both require a two-stage deploy -- registration open at first boot, both accounts created, registration closed -- and Homebox is the dangerous one, since it has **no default admin account**, so closing registration before an account exists is an unrecoverable lockout.

**Must have (table stakes):**
- Reachable at `<name>.vofi` with valid local-CA TLS, DNS pointed at firebat (not ser8), registration closed after bootstrap
- Every stateful path declared in impermanence with correct tmpfiles ownership; demonstrated restore, not just a backup that runs
- Two accounts in one shared household/circle/group per service (three different mechanisms, do not try to unify them)
- Mealie: PostgreSQL, default admin credentials changed, Foods/Units seeded, "Show All" toggle enabled on the shopping list (otherwise each person thinks the other's list doesn't exist), correct `BASE_URL`
- Donetick: packaging resolved, JWT secret >= 32 chars from SOPS, one Circle, `POST /api/v1/chores` for the import (not the public `eapi`)
- Homebox: registration open->closed two-stage dance, invite (not self-register) for the second user, analytics off, upload size raised
- Actual: trusted TLS (hard functional requirement, not polish), server password set in-app, encryption left OFF (irreversible in-place, undermines demonstrated-restore)

**Should have (differentiators):**
- Verified negative access test (Tailscale off -> connection refused)
- Reboot-twice persistence smoketest
- Restore rehearsal into a scratch instance -- highest-value single item after Mealie itself
- Blackbox probe + Grafana row per service (reuses validated v1.1 infrastructure, nearly free)
- Google Tasks importer with dry-run + idempotency map (Donetick has no import-ref concept; a naive re-run duplicates everything)

**Defer (v2+, or never):**
- Any cross-service sync/glue (firm constraint -- this is exactly the Grocy failure mode)
- Mealie AI/OCR import, HA integration, OIDC
- Donetick points/gamification/notifications (chore set will churn heavily in month one)
- Homebox maintenance schedules (would create a second chore system), CSV bulk import, asset IDs/QR
- Actual OpenID multi-user, SimpleFIN bank sync (in-app only, never in Nix)

### Architecture Approach

Follow the repo's established two-layer split: a reusable `modules/household/<svc>.nix` (service user, port, firewall, `enable = mkDefault false`) plus a host-policy `hosts/ser8/household/<svc>.nix` (enablement, secrets, BASE_URL-style settings, backup job registration) -- mirroring `modules/media/sonarr.nix` / `hosts/ser8/media/sonarr.nix` exactly, per a recorded Phase 08 decision. A single reusable `modules/household/backup.nix` module exposes a typed `household.backup.jobs.<name>` option (type postgres|sqlite) so each service registers its backup job in one line rather than each phase inventing a new backup mechanism. Secrets follow the existing SOPS template pattern (Pattern B in ARCHITECTURE.md, precedented by `modules/automation/frigate.nix`): a `sops.secrets` entry, a `sops.templates."<svc>.env"` rendering an `EnvironmentFile`, delivered to a static (non-DynamicUser) unit. Caddy vhosts are bare `reverse_proxy ser8.local:<port>` with **no** `header_up` WebSocket header dance (that pattern is nginx idiom copied into this Caddyfile for Frigate/HASS and is actively wrong for Caddy v2 -- copying it into the new vhosts risks 400/426 errors on ordinary page loads). AdGuard rewrites point at firebat (192.168.68.63), never at ser8. Backups land in a **new** dedicated `backup/household` ZFS dataset with `dedup = off`, not the existing `backup/backups` dataset (which has `dedup = on` and would grow an unrecoverable ARC-hungry dedup table for near-zero benefit on compressed dumps) -- and that dataset must be created by hand on the live pool, since disko only runs at install time.

**Major components:**
1. `modules/household/` + `hosts/ser8/household/` -- reusable/policy module pair for all four services plus PostgreSQL and backup
2. `modules/household/backup.nix` -- typed backup-job registration seam, one nightly timer, `pg_dump`/`sqlite3 .backup` per job type
3. `modules/gateway/Caddyfile` + `modules/dns/adguard-home.nix` -- four new vhosts/rewrites; both existing smoketests (`test-caddy.sh`, `test-dns.sh`) extend themselves automatically
4. `scripts/smoketests/household/` -- service reachability, persistence-after-reboot, and backup-integrity smoketests; `scripts/backup/restore-household.sh` for the manual restore drill
5. `scripts/household/import-google-tasks.py` -- one-shot, not a service; dry-run + idempotency map; run once then quarantine per the repo's replace-don't-deprecate rule

### Critical Pitfalls

1. **Persisting `/var/lib/<svc>` for the two `DynamicUser` services (Mealie, Actual) breaks them; Homebox needs the opposite fix.** Mealie/Actual state already lands correctly under the existing `/var/lib/private` persistence entry -- adding `/var/lib/mealie` or `/var/lib/actual` explicitly persists a symlink and can break state-directory setup. Homebox uses a static user and is **not** covered by anything currently in `hosts/ser8/impermanence.nix` -- it needs an explicit new entry plus a tmpfiles ownership rule, or it silently comes up as a fresh empty instance after every reboot with no error.
2. **PostgreSQL's major version is silently chosen by `system.stateVersion` ("24.11" on ser8 -> Postgres 16, not 17)** the moment `services.mealie.database.createLocally = true` implicitly enables it. Pin `services.postgresql.package` explicitly on the very first deploy, before any data exists -- changing it later requires a manual `pg_upgrade`.
3. **Actual Budget is non-functional without genuinely trusted TLS.** The Caddyfile's global block sets `local_certs` *and* `skip_install_trust`, so the root CA is installed nowhere. `crypto.subtle`/`SharedArrayBuffer` require a real secure context -- a click-through certificate warning is not enough. This alone justifies deploying Actual last, after a deliberate CA-distribution step.
4. **Backup completeness differs per service and a naive strategy silently restores nothing useful.** Mealie needs `pg_dump` *plus* its recipe-image directory (images live on disk, not in Postgres). Actual needs `account.sqlite` *plus* the entire `user-files/` blob tree (budgets are opaque blobs, not in the SQLite DB -- a SQLite-only backup restores a login with zero budgets). No SQLite service may ever be `cp`'d live (WAL mode tears) -- use `sqlite3 <db> ".backup"` or `VACUUM INTO`, always followed by `PRAGMA integrity_check`.
5. **Google Takeout has no recurrence data at all -- not a parsing gap, the field genuinely does not exist in the export.** An import script that tries to infer recurrence from repeated task instances will produce silently wrong chore schedules. The correct design is: automate one-off todos (clean field mapping), hand-author the ~10-30 recurring chores using Donetick's richer frequency model, and treat the Takeout archive inspection as a gate that happens *before* any script is written (its exact JSON envelope is undocumented by Google).

## Reconciled Cross-Researcher Conflicts

Three points where the four research files disagreed. Each is resolved below with the reasoning; the roadmapper should treat these as decisions to make explicit in the roadmap/PROJECT.md, not gaps to leave open.

### (a) Donetick packaging: OCI container vs. locally-built package -- OPEN DECISION, presented with tradeoffs

STACK.md recommends a digest-pinned OCI container (`virtualisation.oci-containers` on podman) as the lower-effort path. ARCHITECTURE.md and PITFALLS.md recommend a locally-built `buildGoModule` package following the repo's own `packages/subgen/` / `modules/subgen/` precedent (a Go binary + npm-built frontend, mirrored module and host-policy files). Both files verified: **no nixpkgs package or module for Donetick exists on any branch** (25.11, 26.05/unstable, or master); the only nixpkgs activity is an open, package-only PR (#551607) that should not be planned around.

Neither position is wrong -- they optimize for different things:

| | OCI container (STACK.md) | Local `buildGoModule` package (ARCHITECTURE.md / PITFALLS.md) |
|---|---|---|
| Effort | Low -- pin `docker.io/donetick/donetick:v0.1.76@sha256:...`, write a systemd-adjacent container unit | Higher -- a `buildGoModule` derivation, a `buildNpmPackage` frontend stage (frontend must be built and embedded before the Go binary), a hand-written `options.services.donetick` module |
| New capability introduced | **Yes.** No container runtime is configured anywhere in this repo today (`rg 'oci-containers\|virtualisation.docker\|podman'` returns nothing meaningful -- `/var/lib/docker` in impermanence and `docker` group membership are vestigial leftovers). Podman/docker, rootless-vs-rootful, and a new `/var/lib/containers` persistence path all become new repo-wide surface area for one service. | **No.** Fits the repo's existing pattern exactly (`packages/subgen/` -> `modules/subgen/` -> `hosts/firebat/subgen.nix`); `nix build .#donetick` is independently testable without touching ser8, and can be split into its own early plan run in parallel with other phases. |
| Fits "all config in Nix" constraint | Weaker -- image is opaque to `make pkg-list-ser8` / `nix eval '.#packageInfo.ser8'`; version pinning is by digest, not by nixpkgs-tracked hash; the container config format (YAML + `DT_`-prefixed env overrides) sits outside the module option surface. | Fully -- same declarative shape and inspectability as Mealie/Homebox/Actual. |
| Ongoing maintenance | Lower per-deploy, but a real container runtime is now a repo-wide dependency to maintain indefinitely for one service. | A Go + Node derivation to track upstream releases against, but scoped entirely to this one package and mirrors work already being done for subgen. |

**Recommendation for the roadmapper:** default to the local `buildGoModule` package (architecture/pitfalls position) on repo-consistency grounds -- it avoids introducing a first-ever container runtime for a single service and fits the "declarative-everything" constraint the rest of this milestone is built around. Treat the OCI container as the explicit fallback if the Go+npm packaging proves harder than expected during the Donetick phase (e.g., the frontend build step or cgo/SQLite linking turns out to be nontrivial) -- in which case pin by digest per STACK.md's guidance and record the tradeoff (container opacity, new podman surface area) as accepted tech debt in PROJECT.md Key Decisions. Either way, resolve this **before** the Donetick phase starts, not during it, and record the choice explicitly so it isn't relitigated mid-phase.

### (b) Phase ordering -- reconciled into one order

All three researchers agree on the two hard constraints (persistence/Postgres pinning first; Actual last, after TLS trust) and differ mainly on where the backup/restore phase sits and how finely Homebox/Actual/Donetick are split. Reconciled order:

1. **Precondition: bump `nixpkgs` to `nixos-26.05`.** STACK.md frames this as a precondition phase rather than separate maintenance, gated by `make check` + `make dry-activate-pi4` (the `nixos-raspberrypi` pin is the one real risk). ARCHITECTURE.md and PITFALLS.md don't dispute this but treat it as a decision to make explicit rather than a numbered phase of its own -- reconcile by giving it its own phase, since it's the only piece of work in the milestone that touches the Pi hosts.
2. **Household scaffold + PostgreSQL + Mealie.** All three agree Mealie goes first: it's the highest-priority service, exercises every hard integration point at once (new DB engine, DynamicUser-to-static-user or DynamicUser-with-correct-persistence decision, first vhost/DNS pattern, first smoketest area), and PITFALLS.md is explicit that Postgres version pinning must happen here, "as the first configuration written," before any data exists.
3. **Backup engine + restore drill (against Mealie).** ARCHITECTURE.md places this second, explicitly "not last," arguing it's the milestone's only irreversible requirement and is far easier to prove with one service than four. PITFALLS.md agrees in spirit but notes the drill should exercise both the Postgres *and* SQLite backup engines, meaning it should land after Mealie *and* at least one SQLite service -- implying a thin slice here (prove the Postgres path and the `household.backup.jobs` seam) with the SQLite side of the restore drill validated once Actual/Homebox land. Reconcile as: build the backup engine and do the Mealie restore drill in this phase; do not defer backup infrastructure to "late," but treat full multi-engine restore validation as completed once Actual/Homebox exist.
4. **Actual and Homebox, either order between them (order-independent).** ARCHITECTURE.md suggests Actual before Homebox ("smaller change"); PITFALLS.md's ordering-implications section only requires that Actual come *after* a gateway/TLS-trust step and *before or with* Homebox -- no researcher requires Actual specifically last relative to Homebox, only last relative to *all* work needed to make TLS trust real. Since TLS trust work (CA distribution) has no other natural phase in this milestone, fold it into whichever phase deploys Actual, and put Actual after Homebox if a two-stage registration dance is judged simpler to rehearse once (on Homebox) before repeating a similar bootstrap sequencing discipline on Actual's simpler interactive-password flow. Either order is defensible; what's non-negotiable is Actual not shipping before its CA-distribution step exists.
5. **Donetick packaging + deploy + Google Tasks import, last.** Unanimous across all three files: Donetick is the only phase with real engineering unknowns (no nixpkgs artifact at all), and the import strictly depends on Donetick already having real accounts and a circle. PITFALLS.md additionally flags that Takeout export is a long-lead external dependency ("request it early... it can take hours to days") -- the roadmapper should have the household request the Google Takeout export during the Mealie phase so it has landed by the time this phase starts, even though the phase itself runs last.

### (c) NixOS 26.05 channel bump as precondition phase -- confirmed

All three researchers independently flag the EOL channel as a live issue rather than background maintenance, and STACK.md is the most emphatic: "Treat 'bump nixpkgs to nixos-26.05' as a precondition phase for this milestone rather than as separate maintenance work." Reconciled recommendation: give it its own numbered phase 0/1, gated by `make check` plus `make dry-activate-pi4` (the only unverified risk -- LOW confidence -- is the interaction between the bumped top-level `nixpkgs` and the pinned `nixos-raspberrypi` input's own nixpkgs fork used by the Pi hosts). If that risk turns out to be unbounded, STACK.md's documented fallback is staying on 25.11 and overlaying `services.mealie.package`/`services.actual.package` from the already-present `nixpkgs-unstable` input -- this works for Mealie and Actual but must explicitly **not** be applied to Homebox (the 25.11 module sets the pre-rename `HBOX_OPTIONS_CHECK_GITHUB_RELEASE` env var, which silently re-enables outbound GitHub release checks against a 0.25.0 binary expecting the renamed key).

## Implications for Roadmap

### Phase 1: Channel bump to nixos-26.05
**Rationale:** Precondition per STACK.md; 25.11 has been EOL since 2026-06-30 and three of four services get materially better nixpkgs modules on 26.05. Gates everything else.
**Delivers:** Flake pinned to `nixos-26.05`, `make check` and `make dry-activate-pi4` green, Pi-host risk (the `nixos-raspberrypi` pin) explicitly resolved or accepted.
**Addresses:** Foundational requirement, not a named feature.
**Avoids:** N/A directly, but unlocks the improved Actual/Mealie modules referenced throughout PITFALLS.md and STACK.md.

### Phase 2: Household scaffold, PostgreSQL, Mealie
**Rationale:** Highest-priority service; exercises every hard integration point (new DB engine, persistence pattern, first vhost/DNS, first smoketest area) at once, so getting it right makes the remaining three near-mechanical.
**Delivers:** `modules/household/` + `hosts/ser8/household/` scaffold, PostgreSQL pinned explicitly (`postgresql_17` or similar) before any data exists, Mealie deployed with correct `BASE_URL`/`--forwarded-allow-ips`, household created, second user invited, Foods/Units seeded, shopping-list "Show All" verified, `mealie.vofi` vhost + DNS rewrite, negative-access smoketest.
**Addresses:** Mealie table-stakes features from FEATURES.md.
**Avoids:** Pitfalls 1 (DynamicUser persistence), 5 (Mealie secret/image persistence), 6 (BASE_URL), 9 (Postgres version pin), 10 (Postgres ownership race), 21 (DNS pointed at wrong host).

### Phase 3: Backup engine + restore drill
**Rationale:** The milestone's only irreversible requirement; far easier to prove correct with one service before three more need the same pattern. Establishes the `household.backup.jobs.<name>` seam so later services register in one line.
**Delivers:** New `backup/household` ZFS dataset (dedup off, hand-created on the live pool), `modules/household/backup.nix` typed job registration, nightly timer, `pg_dump` job for Mealie proven via a real restore into a scratch database, `scripts/backup/restore-household.sh`.
**Uses:** `household.backup.jobs` seam from ARCHITECTURE.md.
**Implements:** Backup engine component from ARCHITECTURE.md.
**Avoids:** Pitfalls 11 (cp of live SQLite -- n/a yet but sets the pattern), 13 (pg_dump under hardening), 14 (ZFS dedup on backup target).

### Phase 4: Actual Budget and Homebox
**Rationale:** Both have simple upstream nixpkgs modules and are order-independent between themselves; both are first consumers of the SQLite branch of the backup engine built in Phase 3. Actual's TLS-trust requirement means CA distribution must land as part of this phase regardless of which service goes first internally.
**Delivers:** CA distribution to household devices (Caddy root CA, iOS/Android/Firefox trust steps), Actual deployed with encryption declined and accounts/budget entered, Homebox deployed via the open-signup->create-accounts->close-signup two-stage dance with explicit persistence entry (static user, not covered by existing `/var/lib/private`), both wired into the backup engine's SQLite job type, both smoketested and probed.
**Addresses:** Actual and Homebox table-stakes features from FEATURES.md.
**Avoids:** Pitfalls 2 (Homebox static-user persistence gap), 3 (Homebox registration lockout), 7 (Actual TLS trust), 8 (duplicated COOP/COEP headers), 12 (Actual's split backup state), 15 (WebSocket header copying), 18 (port collisions).

### Phase 5: Donetick packaging + deploy + Google Tasks import
**Rationale:** Only phase with real engineering unknowns (no nixpkgs artifact exists at all); the import strictly depends on Donetick already having real accounts. Request the Google Takeout export during Phase 2 (Mealie) since it is a long-lead external dependency (async, hours to days).
**Delivers:** Donetick packaging decision resolved and recorded (default: local `buildGoModule` package per architecture/pitfalls; fallback: digest-pinned OCI container per stack -- see reconciliation above), JWT secret from SOPS, two-stage signup dance, `donetick.vofi` + DNS + backup job, real Takeout archive inspected before any import code is written, import script (`scripts/household/import-google-tasks.py`) writing to `POST /api/v1/chores` (never the public `eapi`) with dry-run and idempotency map, recurring chores hand-authored using Donetick's frequency model.
**Addresses:** Donetick table-stakes features and the Google Tasks import concept mapping from FEATURES.md.
**Avoids:** Pitfalls 4 (Donetick not in nixpkgs), 16 (open signup + placeholder JWT), 19 (Takeout recurrence gap), 20 (non-idempotent import wired into activation).

### Phase Ordering Rationale

- Persistence and PostgreSQL-version pinning must happen before any service holds real data -- cheap to get right on day one, expensive after data exists (PITFALLS.md, unanimous across researchers).
- Actual cannot ship before TLS trust is real; this is a hard functional blocker, not polish, so it anchors Actual to the end of the native-module services regardless of internal Homebox/Actual ordering.
- Donetick is last because it is the only phase with unresolved packaging unknowns, and the Google Tasks import has a hard dependency on Donetick already having accounts -- sequencing it any earlier would block on work that isn't ready.
- The channel bump is isolated to its own first phase because it is the one piece of work in this milestone that touches the Pi hosts (via shared `modules/`) rather than ser8 alone, and needs its own `make dry-activate-pi4` gate independent of household-service work.

### Research Flags

Phases likely needing deeper research during planning:
- **Phase 5 (Donetick):** needs a dedicated research pass on `buildGoModule` + embedded-frontend packaging (or confirming the OCI fallback) before planning can proceed; also needs the real Google Takeout archive in hand before the import script is designed -- its exact JSON envelope is undocumented by Google and only confirmed against community samples.
- **Phase 1 (channel bump):** the `nixos-26.05` x `nixos-raspberrypi` interaction is LOW confidence (untested); worth a `make dry-activate-pi4` spike inside this phase rather than assuming it's clean.

Phases with standard patterns (skip research-phase):
- **Phase 2 (Mealie):** module and package facts read directly from pinned nixpkgs source; HIGH confidence throughout.
- **Phase 3 (backup engine):** patterns for `pg_dump`/`sqlite3 .backup`/systemd timers are all precedented in-repo or well-documented upstream.
- **Phase 4 (Actual, Homebox):** both have stable, well-documented nixpkgs modules; the TLS-trust and two-stage-registration procedures are fully specified in PITFALLS.md.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | Module/package facts read directly from the pinned nixpkgs source trees and branch heads; Donetick API surface read from upstream Go source. MEDIUM only on Takeout field-level detail (single community sample, not this household's real export). |
| Features | MEDIUM-HIGH | Donetick model read directly from upstream source (HIGH); Mealie/Homebox/Actual behavior from official docs cross-checked against maintainer discussions (MEDIUM-HIGH). Homebox registration-lockout recoverability has conflicting sources -- flagged as a gap below. |
| Architecture | HIGH for repo integration points (every claim cites a file and line at HEAD); MEDIUM for Donetick runtime configuration details, since no nixpkgs module exists to cross-check upstream docs against. |
| Pitfalls | HIGH for nixpkgs module behavior and repo facts (read directly from pinned sources); MEDIUM for upstream app behavior and community-reported issues; LOW-MEDIUM for Google Takeout export fidelity. |

**Overall confidence:** HIGH for the deployment/architecture mechanics of this milestone, MEDIUM for Donetick specifics and Google Tasks import fidelity -- both concentrated entirely in Phase 5, which is already flagged for deeper research during planning.

### Gaps to Address

- **Donetick packaging approach (open decision, see reconciliation above):** default to local `buildGoModule`, but confirm feasibility of the Go+npm frontend build during Phase 5 planning before committing; fall back to the digest-pinned OCI container if it proves nontrivial, and record whichever choice is made in PROJECT.md Key Decisions.
- **Whether Homebox's registration flag can be safely re-enabled after being disabled:** sources conflict (FEATURES.md notes official docs vs. older archived docs disagree). Test on a scratch instance before flipping it on the real deployment; do not assume based on documentation alone.
- **Exact Google Takeout `Tasks.json` envelope:** undocumented by Google. Inspect the real household export's key union as the first step of Phase 5, before writing the parser -- do not code against an assumed schema.
- **Whether the NixOS `services.mealie` module surfaces `DEFAULT_EMAIL`/`DEFAULT_PASSWORD` at first init, or whether bootstrap must go through the stock `changeme@example.com` account:** affects the Phase 2 bootstrap checklist wording, not the design; confirm during Phase 2 execution.
- **Whether Actual's server password can be set non-interactively:** not found in config docs; assume interactive first-visit setup for the Phase 4 bootstrap checklist.
- **`nixos-26.05` x `nixos-raspberrypi` interaction:** untested (LOW confidence). Resolve with `make dry-activate-pi4` inside Phase 1 before merging the channel bump.

## Sources

### Primary (HIGH confidence)
- Locked nixpkgs 25.11 and nixpkgs-unstable (26.05) source trees, read directly from the local Nix store
- `raw.githubusercontent.com/NixOS/nixpkgs/{master,nixos-26.05,nixos-25.11}` -- mealie/homebox/actual-server package and module files
- Repository at HEAD (`b4664da`): `flake.nix`, `flake.lock`, `deploy.yaml`, `Makefile`, `hosts/ser8/{configuration,impermanence,disko-config}.nix`, `modules/gateway/Caddyfile`, `modules/dns/adguard-home.nix`, `modules/servers/backup.nix`, `modules/media/*`, `modules/automation/frigate.nix`, `modules/subgen/*`, `scripts/smoketests/**`, `.planning/{PROJECT,STATE}.md`, `proposal.md`
- Donetick upstream `main` source: `internal/chore/{model,handler,api}.go`, `internal/auth/multiauthmiddleware.go`, `config/selfhosted.yaml`
- GitHub API: NixOS/nixpkgs PR #551607 (donetick init, package-only, open); Docker Hub registry digest for `donetick/donetick:v0.1.76`
- Google Tasks API v1 `Task` resource reference (official, complete field list -- confirms no recurrence field)

### Secondary (MEDIUM confidence)
- Mealie/Actual/Homebox/Donetick upstream documentation sites, cross-checked against maintainer GitHub discussions
- nixpkgs issue #321623 (Mealie DynamicUser + sops-nix), impermanence issues #93 and #254, donetick issues #254 and #619, caddy issue #7292

### Tertiary (LOW confidence)
- Google Takeout `Tasks.json` envelope, corroborated only by third-party converter tools (`thethales/GoogleTasksJSONtoTXT`, `Nockiro/gtask-exporthelper`) and a Google Calendar Community thread -- needs validation against this household's real export
- `nixos-26.05` x `nixos-raspberrypi` interaction -- not tested, needs a `make dry-activate-pi4` spike

---
*Research completed: 2026-08-16*
*Ready for roadmap: yes*
