# Phase 10: Household Foundation and Mealie - Research

**Researched:** 2026-08-18
**Domain:** NixOS service module design (two-layer split), PostgreSQL pinning under impermanence, Mealie 3.22.0 deployment behind a Caddy tsnet reverse proxy
**Confidence:** HIGH for everything in-repo and in-nixpkgs (read from source this session); MEDIUM for Mealie application semantics (official docs + upstream release notes); LOW for the Google Takeout archive shape (IMP-01 exists precisely to replace this with fact)

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Access path (supersedes stale roadmap wording)**

- **D-01:** Tailscale is the primary access path, local and remote. Mealie's canonical endpoint is `https://mealie.shad-bangus.ts.net` via a new tsnet vhost on firebat (`bind tailscale/mealie`, reverse_proxy to ser8), matching every existing service block in `modules/gateway/Caddyfile`. `BASE_URL` is set to this URL.
- **D-02:** No `.vofi` config for Mealie at all — no Caddy vhost, no AdGuard rewrite. pi4's AdGuard is disconnected (Phase 9 D-06) so `.vofi` names resolve for nobody, and the planned `vofi.dev` migration (deferred todo) will redefine the LAN-name scheme. Dead config is not added for pattern symmetry.
- **D-03:** The Phase 9 D-16 skip-flagged `.vofi` smoketests stay skip-flagged. Phase 10 does not re-enable them (the D-16 note "Phase 10 re-enables once `.vofi` DNS is re-established" is superseded); their fate belongs to the vofi.dev migration todo.
- **D-04:** ROADMAP.md Phase 10 success criterion 1 and REQUIREMENTS.md MEAL-03 were reworded from the AdGuard/`.vofi` framing to the Tailscale endpoint before planning (done in this discussion session).
- **D-05:** The second household member is already on the tailnet — no invite/onboarding work in this phase.

**Mealie version**

- **D-06:** Commit to Mealie 3.22.0 at first boot via `services.mealie.package = unstable.mealie`. The locked `nixpkgs-unstable` (`e5bdc4a41d4c`) already carries 3.22.0 — no input bump needed. Start on the version we keep: no standing up 3.16.0 "to test" first. — **Reversibility:** one-way — Mealie runs Alembic migrations on start with no downgrade path, and no backups exist until Phase 11.
- **D-07:** Version drift is gated by flake.lock: `unstable.mealie` only moves when a deliberate, staged `nix flake update` commit lands (repo convention from Phase 9 D-09). Rule for downstream phases: no unstable bump that moves Mealie until Phase 11 backups exist and a fresh `pg_dump` is taken.

**PostgreSQL**

- **D-08:** Pin `services.postgresql.package = pkgs.postgresql_17` explicitly (17.11 on the current 26.05 pin). Without the pin, ser8's `stateVersion = "24.11"` silently selects postgresql 16. — **Reversibility:** one-way — changing majors after data exists requires a manual `pg_upgrade` against the impermanence-persisted data directory.

**Bootstrap and hardening**

- **D-09:** Registration is closed declaratively (`ALLOW_SIGNUP=false` in `services.mealie.settings`), not via UI toggle — the security posture lives in config.
- **D-10:** One-time setup is manual UI work: change default admin credentials, create both user accounts in one shared household, seed Foods/Units, confirm the single shared shopping list. No bootstrap scripting via the Mealie API.

**Verification**

- **D-11:** Household smoketests are wired through a new top-level `scripts/smoketests/ser8/all.sh` that fans out to `media/all.sh` and `household/all.sh`; `deploy.yaml`'s single ser8 smoketest entry points at it. Scales for Phases 11-13. Smoketests probe the tsnet URL, not `.vofi`.
- **D-12:** ser8 has ALREADY been rebooted on 26.05 (user correction — STATE.md's "neither x86 host rebooted" record is stale). No boot-path validation step is needed; MEAL-05's two consecutive reboots are pure persistence checks.

### Claude's Discretion

- Where the postgresql pin expression lives (`modules/household/` vs `hosts/ser8/household/`) and how the module options are shaped, following the two-layer pattern.
- Verifying `/var/lib/postgresql` ownership lands as `postgres:postgres 0700` on first start (PITFALLS.md flags the persisted dir defaults root-owned).
- `--forwarded-allow-ips` value and proxy-header details for Mealie behind the firebat Caddy proxy.
- Where the Takeout archive's JSON structure notes are recorded (a `.planning/` doc is fine); the export request itself is a manual user action early in the phase.
- How the ser8/all.sh fan-out handles per-area exit codes and output.

### Deferred Ideas (OUT OF SCOPE)

**Reviewed Todos (not folded)**

- **Migrate .vofi hostnames to public vofi.dev domain** (`.planning/todos/pending/2026-08-17-migrate-vofi-hostnames-to-public-vofi-dev-domain.md`) — matched this phase (score 0.9) but explicitly ruled separate by the user. Phase 10 adds no `.vofi` config, which keeps the migration surface from growing.

Also out of scope per the roadmap: backups and restore drills (Phase 11), trusted-TLS distribution / Homebox / Actual (Phase 12), Donetick and the actual Google Tasks import (Phase 13), negative-access smoketests / Nix-store secret scanning / blackbox probes (Phase 14).
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| FOUND-03 | `modules/household/` + `hosts/ser8/household/` scaffold follows the repo's two-layer module pattern | "Architecture Patterns → Pattern 1/2" gives the verbatim in-repo template (`modules/media/bazarr.nix`, `modules/media/prowlarr.nix`, `hosts/ser8/media/default.nix`) and the two exact wiring edits (`flake.nix:196-200`, `hosts/ser8/configuration.nix:11-15`) |
| FOUND-04 | PostgreSQL enabled on ser8 with an explicitly pinned package version before any service data exists | "Standard Stack → Core" (verified `postgresql_17` = 17.7, `psqlSchema` = `"17"`), Pitfall 3 (stateVersion silently selects 16), Pitfall 4 (persisted-dir ownership, and why systemd's `StateDirectory` mostly already handles it) |
| MEAL-01 | Mealie runs on ser8 with a PostgreSQL backend via the native module (package overridden to a current release) | "Standard Stack" (unstable `mealie` = 3.22.0 verified at the locked rev; module byte-identical between 26.05 and locked unstable), "Code Examples → Mealie host policy", Pitfall 6 (uvicorn worker deprecation = drift risk) |
| MEAL-02 | Both household members have accounts in one shared household; default admin credentials changed; registration closed | Pitfall 1 (`ALLOW_SIGNUP` must be the **string** `"false"`), "Mealie Application Model" (default admin `changeme@example.com`/`MyPassword`; `DEFAULT_GROUP`=`Home`, `DEFAULT_HOUSEHOLD`=`Family`, first-init-only) |
| MEAL-03 | Mealie is reachable at `mealie.shad-bangus.ts.net` through the firebat Caddy Tailscale (tsnet) vhost with correct `BASE_URL` | "Code Examples → Caddy tsnet vhost" (exact block, no `header_up`), Pitfall 2 (`BASE_URL` + `--forwarded-allow-ips 192.168.68.63`), Pitfall 5 (firewall port 9000 must be open for firebat to reach ser8) |
| MEAL-04 | Foods and Units are seeded, and both users can see and edit the single shared shopping list | **"Mealie Application Model"** — shopping lists are **household-scoped**, Foods/Units are **group-scoped**; both users must land in the SAME household or MEAL-04 silently fails |
| MEAL-05 | Recipes, images, and uploads survive two consecutive reboots (impermanence check) | "Decision Point 1" (DynamicUser vs static user, and where state physically lands), "Validation Architecture" (what the reboot check must actually inspect — Postgres rows AND the image tree) |
| IMP-01 | Google Takeout export requested early (async, hours-to-days) and the real archive inspected before any import code is written | "Google Takeout Tasks Archive" — expected shape to diff the real archive against, plus the known recurrence gap; deliberately framed as a hypothesis to falsify, not a fact to build on |
</phase_requirements>

## Summary

Almost everything this phase needs already exists in the repo and in the pinned inputs; the work is assembly plus one genuinely new subsystem (PostgreSQL). The `services.mealie` NixOS module is **byte-identical** between the locked `nixpkgs` (26.05, `e4bae1bd`) and the locked `nixpkgs-unstable` (`e5bdc4a4`), which is exactly what makes D-06's package-only override safe: `unstable.mealie` is 3.22.0 while stable is 3.16.0, and the module's whole contract with the package is `$out/bin/mealie` plus `$out/libexec/init_db`, both of which the 3.22.0 expression still emits. `/var/lib/private` and `/var/lib/postgresql` are already persisted. The `postgres` tmpfiles rule already exists in `hosts/ser8/impermanence.nix`, commented out, waiting for exactly this phase.

Two research findings change the shape of the plan. First, **D-11 is already ~80 % done**: `scripts/smoketests/ser8/all.sh` exists today, uses the shared `run_suite` fan-out helper (which correctly returns non-zero if *any* sub-suite fails), and `deploy.yaml:16` already points at it. Phase 10 does not build that scaffold — it appends one line to an existing `TESTS` array. Second, and more consequential: **Mealie's shopping lists are household-scoped, not group-scoped** (v2.0.0 moved them under `/api/households/shopping/lists`). If the two accounts land in different households — which is easy to do accidentally, since the admin UI lets you pick — MEAL-04 fails silently while every page still returns HTTP 200. The success criterion "both users see and edit the same single shared shopping list" is therefore a real assertion about account placement, not a formality.

The one open design question is whether Mealie keeps nixpkgs' `DynamicUser = true` or is forced to a static user. CONTEXT.md's canonical-refs summary asserts "Mealie needs zero new impermanence entries" (the DynamicUser path). But the repo's own precedent contradicts that framing: `modules/media/prowlarr.nix` takes a nixpkgs module that defaults to `DynamicUser` and forces it off with a static system user. Since FOUND-03 asks for a pattern that Homebox (static user upstream) and Actual (26.05 module exposes `user`/`group`) reuse in Phase 12, and a DynamicUser-shaped pattern does not generalize to either, this research recommends the static-user path. See **Decision Point 1** — it sits squarely inside "Claude's Discretion" (module option shaping), so it is the planner's call, but it must be made deliberately rather than inherited.

**Primary recommendation:** Build `modules/household/{default,mealie,postgresql}.nix` + `hosts/ser8/household/{default,postgresql,mealie}.nix` mirroring `modules/media` / `hosts/ser8/media` exactly; force Mealie to a static `mealie` user (Prowlarr precedent) so the pattern generalizes; pin `postgresql_17` in the host-policy layer; set `settings.BASE_URL`/`ALLOW_SIGNUP` as **strings**; add one `header_up`-free tsnet vhost to the Caddyfile; append one line to the existing `ser8/all.sh` `TESTS` array; and gate the whole thing with an offline `nix eval` assertion script modelled on `scripts/validation/test-actual-module.sh`.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Recipe/meal-plan application logic | ser8 application service (`mealie.service`) | — | Upstream app; nothing in this repo implements it |
| Relational persistence | ser8 database tier (`postgresql.service`) | ser8 impermanence layer (`/persist`) | Mealie owns the schema; the host owns the major-version pin and the persisted data directory |
| Binary/blob persistence (recipe images, uploads) | ser8 filesystem (`DATA_DIR`) | ser8 impermanence layer | Mealie writes images to disk, **not** into Postgres — two state stores, both must be persisted (Pitfall 7) |
| TLS termination + public name | firebat gateway (`caddy.service`, tsnet node) | Tailscale control plane (ACME) | Every existing service terminates TLS on firebat; the tsnet plugin obtains the cert |
| Network reachability ser8 ← firebat | ser8 firewall (`networking.firewall`) | LAN | Caddy proxies from firebat's LAN address to `192.168.68.65:9000`, so the port must be open on ser8 |
| Reusable defaults (user, port, firewall, `enable = mkDefault false`) | `modules/household/` | — | Repo's reusable-module layer; must contain no host-specific identity |
| Concrete enablement, version pins, secrets, endpoint URL | `hosts/ser8/household/` | — | Repo's host-policy layer (Phase 08 decision: enablement + secrets + policy live together per service) |
| Deploy-path verification | `scripts/smoketests/` (ser8 area + gateway area) | `deploy.yaml` | One smoketest entry per host; the ser8 fan-out already exists |
| Evaluation-time verification | `scripts/validation/` via `make check` | — | Catches module/option/pin regressions offline, before any host is touched |
| Account/household/seed-data state | Mealie UI (manual, D-10) | — | Deliberately not scripted this phase |

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| `services.mealie` (NixOS module, from the pinned `nixpkgs` 26.05) | module is **byte-identical** to the locked unstable copy | Recipe manager unit, Postgres wiring, migrations | Native module; wires `services.postgresql` itself, runs `init_db` as `ExecStartPre`. `diff` of `nixos/modules/services/web-apps/mealie.nix` between `/nix/store/kfcxqcxb9hcq6x33sg4cmwakbb1ifwg9-source` (26.05) and `/nix/store/rd49sb5is1wap50ifnlm5amjpabwbdk1-source` (locked unstable) reports identical [VERIFIED: `diff -q` this session] |
| `unstable.mealie` | **3.22.0** | Mealie application | `nix eval --raw 'github:NixOS/nixpkgs/e5bdc4a41d4c072fe1e3787eaa0320a384741d44#mealie.version'` → `3.22.0` [VERIFIED: npm-equivalent registry check = nix eval at the locked rev]. Stable 26.05 ships `3.16.0` (`nix eval .#nixosConfigurations.ser8.pkgs.mealie.version` → `3.16.0`) [VERIFIED] |
| `pkgs.postgresql_17` | **17.7** | Mealie backing store | `nix eval --raw 'github:NixOS/nixpkgs/e4bae1bd10c9c57b2cf517953ab70060a828ee6f#postgresql_17.version'` → `17.7`; `.psqlSchema` → `17` [VERIFIED, both this session] |
| `services.postgresql` (NixOS module, 26.05) | — | Database service, `ensureDatabases`/`ensureUsers`, `dataDir` | Enabled implicitly by `services.mealie.database.createLocally = true` |
| caddy-tailscale plugin (already on firebat) | `v0.0.0-20260106222316-bb080c4414ac` | tsnet node + ACME cert for `mealie.shad-bangus.ts.net` | Already built into firebat's caddy [VERIFIED: `modules/gateway/caddy.nix:15`]; adding a service is one vhost block and **no new secret** — the shared `sops.secrets.tailscale_authkey` is exported as `TS_AUTHKEY` for the whole process [VERIFIED: `modules/gateway/caddy.nix:25-30,70`] |

**Correction to D-08's parenthetical:** the decision text says "17.11 on the current 26.05 pin". The locked 26.05 rev actually carries **PostgreSQL 17.7**, not 17.11 [VERIFIED this session]. The decision itself (pin `postgresql_17`) is unaffected — only the minor number in the note is wrong. Worth correcting so a plan does not assert 17.11 and then fail its own acceptance check.

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `python3Packages.gunicorn` (inside `mealie`) | 26.0.0 | WSGI/ASGI process manager | Not declared by us — but it is what `services.mealie.extraOptions` are passed to [VERIFIED: unstable rev] |
| `python3Packages.uvicorn` (inside `mealie`) | 0.51.0 | ASGI worker | Ditto; source of the proxy-header behaviour [VERIFIED: unstable rev] |
| `scripts/smoketests/lib/fanout.sh` (`run_suite`) | in-repo | Multi-suite fan-out with correct aggregate exit status | Adding the `household` area to `ser8/all.sh` |
| `scripts/smoketests/lib/services.sh`, `scripts/lib/all.sh` | in-repo | `pass`/`fail`/`info`/`title`/`get_ip`/`get_user` helpers | Every new smoketest sources these |
| `scripts/validation/test-actual-module.sh` | in-repo | Template for an offline `nix eval` assertion gate wired into `make check` | Model for `test-mealie-module.sh` |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `unstable.mealie` package override | Stable 26.05 `mealie` 3.16.0 | Ruled out by D-06. Would mean a later forced Alembic migration with no backups — worse, not better |
| `services.mealie.database.createLocally = true` | Hand-written `services.postgresql.ensureDatabases`/`ensureUsers` + explicit `POSTGRES_*` | The module already emits exactly that, plus the socket-auth URL with the quirky empty `:` before `@`. Hand-rolling reintroduces upstream bug mealie-recipes/mealie#3573 |
| tsnet vhost on firebat | `tailscale serve` on ser8, or Caddy on ser8 | Ruled out by D-01 and by every existing service block; would also fragment TLS ownership across two hosts |
| Static `mealie` user | nixpkgs' default `DynamicUser = true` | See Decision Point 1 — genuine tradeoff, recommendation given |
| `mkDefault`-shaped `services.postgresql.package` in `modules/household/` | Explicit pin in `hosts/ser8/household/postgresql.nix` | Prefer the host-policy layer: FOUND-04 is a host-durability decision, and `mkDefault` on a version pin is exactly how a version silently drifts later |

**Installation:** Nothing is installed from a public package registry. Every package resolves from the two pinned flake inputs (`nixpkgs` `e4bae1bd`, `nixpkgs-unstable` `e5bdc4a4`) already recorded in `flake.lock`. Deployment is `make check` → `make test-ser8` → `make smoketests-ser8` → `make switch-ser8`, plus the same ladder on firebat for the Caddyfile change.

**Version verification (run before writing any plan that asserts a version):**
```bash
nix eval --raw '.#nixosConfigurations.ser8.pkgs.mealie.version'                      # stable: 3.16.0
nix eval --raw 'github:NixOS/nixpkgs/e5bdc4a41d4c072fe1e3787eaa0320a384741d44#mealie.version'      # unstable: 3.22.0
nix eval --raw 'github:NixOS/nixpkgs/e4bae1bd10c9c57b2cf517953ab70060a828ee6f#postgresql_17.version'  # 17.7
```

## Package Legitimacy Audit

**Not applicable to this phase.** No package is installed from npm, PyPI, crates.io, or any other public registry. Every dependency (`mealie`, `postgresql_17`, `gunicorn`, `uvicorn`) is resolved from the two content-addressed, revision-pinned nixpkgs flake inputs already present in `flake.lock`, and the Caddy Tailscale plugin is pinned to an exact Go pseudo-version with a vendor-tree hash in `modules/gateway/caddy.nix:11-19`. The slopsquatting threat model that the audit exists to catch has no attack surface here.

**Packages removed due to `[SLOP]` verdict:** none
**Packages flagged as suspicious `[SUS]`:** none

The one supply-chain-adjacent risk that *does* apply is version drift on `nixpkgs-unstable`, which D-07 already governs: `unstable.mealie` moves only on a deliberate, staged `nix flake update` commit. Pitfall 6 below documents a concrete upstream change that makes this rule load-bearing rather than ceremonial.

## Project Constraints (from CLAUDE.md)

Extracted from `./CLAUDE.md` (project) and `~/.claude/CLAUDE.md` (global). The planner must not produce tasks that violate these.

| Constraint | Source | Effect on this phase |
|-----------|--------|----------------------|
| Format Nix with `nixfmt-rfc-style`; do not hand-align against formatter output | project | Every new `.nix` file goes through `make fmt` before commit |
| Module filenames lowercase and kebab-case | project | `modules/household/mealie.nix`, `hosts/ser8/household/postgresql.nix` |
| Preserve `SPDX-License-Identifier: GPL-3.0-or-later` headers where present | project | Every new `.nix` and `.sh` file starts with the SPDX comment — all sibling files have it |
| New Bash scripts start with `set -euo pipefail`; run `shellcheck` and `shfmt -d` | project + global | New smoketests and the validation script |
| Keep area entry points named `all.sh` when referenced by `deploy.yaml` | project | `scripts/smoketests/household/all.sh` |
| Add or update smoketests when changing deployed services, networking, or gateway behavior | project | Both the ser8 household area AND the firebat gateway tsnet node list |
| Treat warnings from formatters, linters, evaluators, and tests as failures | project + global | A new evaluation warning from enabling Postgres is a finding, not a baseline |
| Never commit plaintext credentials or decrypted SOPS content | project | The default admin password change and both user passwords are UI actions, recorded nowhere in the repo |
| Prefer small modules imported through the directory's `default.nix` | project | `modules/household/default.nix` + `hosts/ser8/household/default.nix` |
| Use short, scoped imperative commit subjects; one logical change per commit; no agent co-author | project + global | e.g. `household: add mealie module`, `gateway: add mealie tsnet vhost` |
| Do not push directly to `main` | project + global | Phase work lands on a branch |
| "Replace, don't deprecate" — proactively flag dead code | global | The stale `d /persist/var/lib/private/prowlarr` tmpfiles rule (see Adjacent Cleanup) |
| No em dashes in prose | global | Applies to comments and commit messages |
| `make test-HOST` is safer than `switch`; `NO_CONFIRM=true` only for intentional non-interactive ops | project | The rollout ladder in every deploy task |
| `make rollback-HOST` is a placeholder and must not be presented as functional | project | Recovery is "select the previous generation in systemd-boot", not `make rollback` |
| Absolute imports only, ≤100 lines/function, ≤100-char lines | global | Applies to the shell/validation scripts |

**One stale statement to note:** `CLAUDE.md` says "a NixOS homelab flake built around NixOS 25.11". `flake.nix:7` reads `nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";` [VERIFIED]. Phase 9 completed the bump and CLAUDE.md was not updated. Not this phase's job to fix, but do not let a plan reason from the 25.11 claim.

## Architecture Patterns

### System Architecture Diagram

```
  Household member's phone / laptop
  (on the tailnet — D-05: both members already are)
              │
              │  https://mealie.shad-bangus.ts.net
              │  DNS: Tailscale MagicDNS
              ▼
  ┌──────────────────────────────────────────────────────┐
  │ firebat (192.168.68.63)                              │
  │                                                      │
  │  caddy.service (caddy + caddy-tailscale plugin)      │
  │    TS_AUTHKEY  ← sops.secrets.tailscale_authkey      │
  │                                                      │
  │    ┌─ tsnet node "mealie" ──────────────┐            │
  │    │  listener: tailscale/mealie:443    │            │
  │    │  TLS: Tailscale ACME (automatic)   │            │
  │    │  adds X-Forwarded-Proto: https     │            │
  │    └──────────────┬─────────────────────┘            │
  └───────────────────┼──────────────────────────────────┘
                      │ plain HTTP over the LAN
                      │ src 192.168.68.63 → 192.168.68.65:9000
                      ▼
  ┌──────────────────────────────────────────────────────┐
  │ ser8 (192.168.68.65)                                 │
  │                                                      │
  │  networking.firewall  ── must allow tcp/9000 ────┐   │
  │                                                  ▼   │
  │  mealie.service                                      │
  │    ExecStartPre: $out/libexec/init_db  (Alembic)     │
  │    ExecStart:    gunicorn -b 0.0.0.0:9000            │
  │                    --forwarded-allow-ips 192.168.68.63│
  │                    -k uvicorn.workers.UvicornWorker   │
  │    env: BASE_URL, ALLOW_SIGNUP, TZ, DB_ENGINE,        │
  │         POSTGRES_URL_OVERRIDE, DATA_DIR               │
  │         │                          │                  │
  │         │ unix socket              │ file writes      │
  │         │ /run/postgresql          │ (images, uploads,│
  │         │ peer auth, no password   │  token secret)   │
  │         ▼                          ▼                  │
  │  postgresql.service          DATA_DIR=/var/lib/mealie │
  │    package = postgresql_17                    │       │
  │    dataDir = /var/lib/postgresql/17           │       │
  │    db "mealie" owned by role "mealie"         │       │
  │         │                                     │       │
  └─────────┼─────────────────────────────────────┼───────┘
            │                                     │
            │  ── impermanence bind mounts ──     │
            ▼                                     ▼
   /persist/var/lib/postgresql/17      /persist/var/lib/mealie
   (already persisted, line 60)        (see Decision Point 1)
            │                                     │
            └──────────► rpool/safe/persist ◄─────┘
                 survives the boot-time rollback of rpool/local/root
                          = MEAL-05
```

Read the two bottom arrows together: **Mealie has two independent state stores.** A verification that only counts Postgres rows will pass while every recipe image is broken (Pitfall 7).

### Recommended Project Structure

```
modules/household/                  # reusable layer — no host identity, no secrets
├── default.nix                     # imports the two below (mirrors modules/media/default.nix)
├── postgresql.nix                  # users/group hygiene + enable = mkDefault false
└── mealie.nix                      # static user+group, DynamicUser override, firewall 9000,
                                    #   enable = mkDefault false

hosts/ser8/household/               # host-policy layer — enablement, pins, endpoint, secrets
├── default.nix                     # imports the two below (mirrors hosts/ser8/media/default.nix)
├── postgresql.nix                  # services.postgresql.package = pkgs.postgresql_17  (FOUND-04)
└── mealie.nix                      # enable, package = unstable.mealie, BASE_URL, ALLOW_SIGNUP,
                                    #   TZ, database.createLocally, extraOptions

hosts/ser8/impermanence.nix         # EDIT: uncomment/correct the postgres tmpfiles rule (line 112)
                                    #       + household state entry per Decision Point 1
hosts/ser8/configuration.nix        # EDIT: imports += ./household   (next to ./media, line 14)
flake.nix                           # EDIT: ser8 modules += ./modules/household (next to ./modules/media)
modules/gateway/Caddyfile           # EDIT: one tsnet vhost block

scripts/smoketests/household/
├── all.sh                          # area entry point (name fixed by convention)
├── test-mealie-service.sh          # unit active, port listening, DB reachable
└── test-mealie-endpoint.sh         # tsnet URL responds; BASE_URL is not localhost

scripts/smoketests/ser8/all.sh      # EDIT: append household/all.sh to TESTS
scripts/smoketests/gateway/test-tailscale.sh  # EDIT: append "mealie" to EXPECTED_NODES
scripts/validation/test-mealie-module.sh      # NEW: offline nix eval gate
Makefile                            # EDIT: add the validation script to `check`
```

### Pattern 1: Reusable module (the `modules/media/*.nix` shape)

**What:** Declares the user/group, forces service-hardening overrides, opens the firewall port, and sets `enable = lib.mkDefault false` so importing the module is inert.
**When to use:** Every file under `modules/household/`.
**Example (the in-repo template, quoted verbatim):**

```nix
# Source: modules/media/bazarr.nix:10-25 [VERIFIED, read this session]
  services.bazarr = {
    enable = lib.mkDefault false;
    user = "bazarr";
    group = lib.mkForce "media";
  };

  users.users.bazarr = lib.mkIf config.services.bazarr.enable {
    description = "Bazarr";
    group = "media";
  };

  systemd.services.bazarr.serviceConfig.UMask = lib.mkIf config.services.bazarr.enable "0002";

  networking.firewall.allowedTCPPorts = lib.mkIf config.services.bazarr.enable [
    config.services.bazarr.listenPort
  ];
```

Note the discipline: every `config` stanza is guarded by `lib.mkIf config.services.<svc>.enable`, so a host that imports the module but never enables the service gets no user, no group, and no open port.

### Pattern 2: Overriding a nixpkgs module that defaults to `DynamicUser`

**What:** Force `DynamicUser = false` and supply a real system user/group.
**When to use:** Any upstream module whose state must be persisted, owned, or read by a backup job.
**Example (the in-repo precedent, quoted verbatim):**

```nix
# Source: modules/media/prowlarr.nix:21-53 [VERIFIED, read this session]
    # Create dedicated prowlarr system group
    users.groups.prowlarr = lib.mkIf config.services.prowlarr.enable { };

    # Create dedicated prowlarr system user
    users.users.prowlarr = lib.mkIf config.services.prowlarr.enable {
      isSystemUser = true;
      group = "prowlarr";
      # Note: Prowlarr uses /var/lib/prowlarr/config.xml as its config file
      home = "/var/lib/prowlarr";
      description = "Prowlarr";
    };

    services.prowlarr = {
      enable = lib.mkDefault false;
    };

    # Override systemd service to use static user instead of DynamicUser
    systemd.services.prowlarr = lib.mkIf config.services.prowlarr.enable (
      lib.mkMerge [
        {
          serviceConfig = {
            DynamicUser = lib.mkForce false;
            User = "prowlarr";
            Group = "prowlarr";
          };
        }
        # ...
      ]
    );
```

### Pattern 3: Host-policy module (the `hosts/ser8/media/*.nix` shape)

**What:** Sets `enable = true`, pins packages, declares secrets and templates, and holds every host-specific value (URLs, IPs, identities).
**Phase 08 decision governing it (from STATE.md):** "Keep each Arr service's enablement, secrets, template, exporter instance, and deployment contribution together in one host module." Mealie's enablement, its `BASE_URL`, its `ALLOW_SIGNUP`, and its package override therefore all live in `hosts/ser8/household/mealie.nix` — not split across files.

**Directory aggregation is one flat `imports` list:**

```nix
# Source: hosts/ser8/media/default.nix:1-19 [VERIFIED, read this session]
# SPDX-License-Identifier: GPL-3.0-or-later

{ ... }:

{
  imports = [
    ./sops.nix
    ./permissions.nix
    ./jellyfin.nix
    # ...
  ];
}
```

### Pattern 4: tsnet vhost (`modules/gateway/Caddyfile`)

Every tsnet block is four lines and uses the **static IP**, never `ser8.local` — the Caddyfile carries a long comment block (`modules/gateway/Caddyfile:76-97`) explaining that tsnet-bound Caddy instances cannot resolve mDNS and produce intermittent `device or resource busy` 502s.

```
# Source: modules/gateway/Caddyfile:99-105 [VERIFIED, read this session]
https://jellyfin.shad-bangus.ts.net {
	log tailscale {
		level DEBUG
	}
	bind tailscale/jellyfin
	reverse_proxy 192.168.68.65:8096
}
```

Verified structurally: `caddy adapt` on the current Caddyfile produces `srv0` listening on `:443` (all the `.vofi` names) plus `srv1`..`srv12`, each listening on `tailscale/<name>:443` with exactly one host matcher [VERIFIED: ran `caddy adapt` this session]. A new tsnet block therefore creates a new server, and does **not** enter `srv0` — which matters because `scripts/smoketests/gateway/test-caddy.sh` extracts routes from `.apps.http.servers.srv0.routes[]` only. Adding the Mealie vhost will not perturb that test.

### Anti-Patterns to Avoid

- **Copying the `header_up Upgrade` / `header_up Connection "Upgrade"` pair** from the Frigate and Home Assistant blocks (`modules/gateway/Caddyfile:186-189, 197-200`). That is nginx idiom; Caddy v2 handles HTTP/1.1 upgrades natively, and the unconditional `Connection: Upgrade` stamps every ordinary page load as an upgrade request. Mealie needs no WebSocket handling. Write the vhost bare.
- **Adding a `.vofi` block for symmetry.** D-02 forbids it, and `caddy adapt` folds `.vofi` names into `srv0`, which *is* what `test-caddy.sh` enumerates — a `mealie.vofi` block would immediately add a failing route to the gateway suite.
- **Putting `./modules/household` into `x86Modules`** (`flake.nix:148-153`). That list is applied to firebat too. Household services are ser8-only; the module belongs in ser8's own `modules` list at `flake.nix:196-200`.
- **Importing `modules/household` from `modules/servers/default.nix`.** That group reaches the Pis.
- **Setting `services.mealie.settings.ALLOW_SIGNUP = false;` as a Nix boolean.** See Pitfall 1 — it silently becomes an empty string.
- **Writing `services.postgresql.package = lib.mkDefault pkgs.postgresql_17`.** A `mkDefault` on a one-way version pin is how the pin gets silently overridden later. FOUND-04 says "explicitly pinned"; use a plain assignment.
- **Wiring the one-time Mealie setup into a systemd unit.** D-10 makes bootstrap manual. The repo's `media-config` orchestration-unit pattern is right for convergent config and wrong for a one-shot.

## Decision Points for the Planner

### Decision Point 1 — Mealie: keep `DynamicUser`, or force a static user?

This is the one genuinely open design question, and it sits inside "Claude's Discretion" ("how the module options are shaped"). CONTEXT.md's `## Canonical References` section *summarises* PITFALLS.md as "Mealie needs zero new impermanence entries", which presumes Option A. That summary is a pointer to prior research, not a locked decision — but the planner should surface the choice rather than inherit it.

**Ground truth, read from source this session:**

```nix
# Source: nixpkgs 26.05 nixos/modules/services/web-apps/mealie.nix:95-103 [VERIFIED]
      serviceConfig = {
        DynamicUser = true;
        User = "mealie";
        ExecStartPre = "${pkg}/libexec/init_db";
        ExecStart = "${lib.getExe pkg} -b ${cfg.listenAddress}:${toString cfg.port} ${lib.escapeShellArgs cfg.extraOptions}";
        EnvironmentFile = lib.mkIf (cfg.credentialsFile != null) cfg.credentialsFile;
        StateDirectory = "mealie";
        StandardOutput = "journal";
      };
```

```nix
# Source: nixpkgs 26.05 nixos/modules/services/web-apps/mealie.nix:86-93 [VERIFIED]
      environment = {
        PRODUCTION = "true";
        API_PORT = toString cfg.port;
        BASE_URL = "http://localhost:${toString cfg.port}";
        DATA_DIR = "/var/lib/mealie";
        NLTK_DATA = pkgs.nltk-data.averaged-perceptron-tagger-eng;
      }
      // (builtins.mapAttrs (_: val: toString val) cfg.settings);
```

Note `User = "mealie"` with **no `Group =`** — under `DynamicUser = false` systemd falls back to the user's primary group, so Option B must set `Group` explicitly.

**Option A — keep `DynamicUser = true`**

- State lands at `/var/lib/private/mealie`, with `/var/lib/mealie` as a symlink into it.
- Already covered: `hosts/ser8/impermanence.nix:38-41` reads verbatim
  ```nix
      {
        directory = "/var/lib/private";
        mode = "0700";
      }
  ```
  [VERIFIED: `hosts/ser8/impermanence.nix:38-41`]
- Zero impermanence edits for Mealie. Smallest diff.
- Costs: no tmpfiles ownership rule is expressible (the UID is transient); the `/persist` path breaks the repo's `/persist/var/lib/<svc>` convention; Phase 11's backup job must run as root to descend into a `0700` root-owned `/var/lib/private`; and the pattern does not generalise to Homebox (static user upstream) or Actual (26.05 module exposes `user`/`group`), which is the whole point of FOUND-03.

**Option B — force a static `mealie` user (recommended)**

- Exactly the Prowlarr pattern already in the repo (Pattern 2 above, `modules/media/prowlarr.nix:36-45`).
- State lands at a real `/var/lib/mealie`; add `"/var/lib/mealie"` to `environment.persistence."/persist".directories` and `"d /persist/var/lib/mealie 0750 mealie mealie -"` to `systemd.tmpfiles.rules` — the same two-part convention every other service uses.
- Generalises to all four household services, so Phase 12 adds Homebox/Actual by copying, not by re-deciding.
- Makes MEAL-05 directly inspectable: `ls /persist/var/lib/mealie/...` instead of a root-only `/var/lib/private` descent.
- Cost: four extra lines of Nix and two impermanence edits.

**PITFALLS.md Pitfall 1 does not contradict Option B.** Its warning is specifically "do not persist `/var/lib/<svc>` **while** `DynamicUser` is on", because that bind-mounts a directory over a path where systemd needs a symlink. Under Option B `DynamicUser` is off, `/var/lib/mealie` *is* a real directory, and persisting it is the correct move. The two are consistent; only CONTEXT.md's one-line summary reads otherwise.

**Recommendation: Option B.** If the planner picks Option A instead, the plan must (a) not add `/var/lib/mealie` to impermanence, and (b) state explicitly that Phase 11's backup job runs as root.

### Decision Point 2 — where the PostgreSQL pin lives

FOUND-04 is a host-durability decision with a one-way migration cost (D-08). Put the plain assignment `services.postgresql.package = pkgs.postgresql_17;` in `hosts/ser8/household/postgresql.nix`. Keep `modules/household/postgresql.nix` limited to non-version hygiene, or omit the reusable file entirely if it would be empty — an empty module is worse than no module.

### Decision Point 3 — D-11 is already substantially built

`scripts/smoketests/ser8/all.sh` **already exists** and `deploy.yaml:16` already reads `smoketests: "./scripts/smoketests/ser8/all.sh"` [VERIFIED, both read this session]. Its `TESTS` array is:

```bash
# Source: scripts/smoketests/ser8/all.sh:29-39 [VERIFIED]
SUITE_NAME="ser8"
TESTS=(
	./scripts/smoketests/media/all.sh
	./scripts/smoketests/nordvpn/all.sh
	./scripts/smoketests/ser8/test-zfs-health.sh
	./scripts/smoketests/ser8/test-vaapi.sh
	./scripts/smoketests/ser8/test-frigate.sh
	./scripts/smoketests/ser8/test-home-assistant.sh
)

run_suite "$@"
```

D-11's stated concerns are already satisfied: `run_suite` "runs EVERY entry even after one fails" and "returns non-zero if ANY test failed" [VERIFIED: `scripts/smoketests/lib/fanout.sh:26-28,47-66`]. So the Claude's-Discretion item "how the ser8/all.sh fan-out handles per-area exit codes and output" is **already answered by existing code** — do not redesign it. Phase 10's work is one appended line: `./scripts/smoketests/household/all.sh`. A plan that budgets a task for "create the ser8 fan-out" is spending effort on work that is done.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Creating the `mealie` DB, role, and connection URL | `ensureDatabases` + `ensureUsers` + hand-written `POSTGRES_*` env | `services.mealie.database.createLocally = true` | The module emits exactly that plus `POSTGRES_URL_OVERRIDE = "postgresql://mealie:@/mealie?host=/run/postgresql"` — note the empty-but-required `:` before `@`, which upstream's parser needs (mealie-recipes/mealie#3573). Retyping it by hand is how that character gets dropped [VERIFIED: module lines 106-120] |
| Running Alembic migrations on deploy | An activation script or a `postStart` hook | `ExecStartPre = "${pkg}/libexec/init_db"` | Already in the module, already ordered before `ExecStart` [VERIFIED: module line 98] |
| Ordering Mealie after the database | `after = [ "postgresql.service" ]` in a host module | Nothing — the module sets `requires`/`after` on `postgresql.target` when `createLocally` is true | [VERIFIED: module lines 81-82] |
| Creating and owning `/var/lib/postgresql/17` | A bespoke activation `chown` | `StateDirectory` + the repo's `/persist`-side tmpfiles rule | `StateDirectory = "postgresql postgresql/${cfg.package.psqlSchema}"` with `StateDirectoryMode = if groupAccessAvailable then "0750" else "0700"`, and `groupAccessAvailable = versionAtLeast cfg.finalPackage.version "11.0"` — true for 17.7, so systemd creates both levels at `0750 postgres postgres` [VERIFIED: `postgresql.nix:69, 850-851`]. A manual `chown` is the tell that something declarative is wrong |
| Aggregating smoketest exit codes across areas | A `for` loop over test scripts | `run_suite` from `scripts/smoketests/lib/fanout.sh` | The helper's own comment states the failure mode a loop has: "a loop's exit status is that of its last iteration, so a failing media suite followed by a passing Home Assistant check would certify the activation" [VERIFIED: `scripts/smoketests/ser8/all.sh:11-15`] |
| Probing the endpoint / resolving host addresses in a new script | `curl` against a hard-coded IP | `get_ip`/`get_user` from `scripts/lib/all.sh` (which sources `ssh.sh`, `yq.sh`, `logging.sh`) | Addresses come from `deploy.yaml`, which the project README names as the source of truth |
| Asserting the right module/version/pin resolved | A deploy-time check | An offline `nix eval` assertion script in `scripts/validation/`, wired into `make check` | `scripts/validation/test-actual-module.sh` is the exact template; it runs in seconds, needs no host, and its own comment records the right discipline: "Evaluation failures are allowed to propagate: wrapping these eval calls in a fallback that substitutes a default on error would make the gate certify nothing" |
| TLS certificates for the tsnet endpoint | ACME config, cert paths, renewal timers | `bind tailscale/mealie` | The plugin obtains and renews the cert via Tailscale's ACME; the Caddyfile comment at line 74 says so, and eleven existing services prove it |
| Seeding Foods and Units | An API script or SQL inserts | Mealie's own Manage Data → Seed button | D-10 makes this manual; and re-seeding is known to fail on the `ingredient_foods_name_group_id_key` unique constraint, so an idempotent script is not straightforwardly buildable [CITED: github.com/mealie-recipes/mealie/issues/7273] |

**Key insight:** the nixpkgs `services.mealie` module is only 122 lines and does the entire database dance. Nearly every temptation to write Nix in this phase is a temptation to duplicate something the module already emits. The genuinely new code is four small files, three one-line edits, and the verification scripts.

## Common Pitfalls

### Pitfall 1: `services.mealie.settings` boolean values become the empty string

**What goes wrong:** `services.mealie.settings.ALLOW_SIGNUP = false;` produces the environment variable `ALLOW_SIGNUP=""`, not `ALLOW_SIGNUP="false"`. Registration stays open (or Mealie's pydantic settings reject the value), while `nix build` succeeds and the UI loads fine.

**Why it happens:** the module stringifies every setting with `builtins.mapAttrs (_: val: toString val) cfg.settings` [VERIFIED: module line 93]. In Nix, `toString false` is the empty string and `toString true` is `"1"` — confirmed this session:

```
$ nix eval --expr 'builtins.toJSON { f = toString false; t = toString true; s = toString "false"; }' --impure
"{\"f\":\"\",\"s\":\"false\",\"t\":\"1\"}"
```

The option type is `attrsOf anything`, so a boolean type-checks. Nothing warns.

**How to avoid:** write every setting as a **string**: `ALLOW_SIGNUP = "false";`. Upstream's own option example uses the string form (`example = { ALLOW_SIGNUP = "false"; };`, module lines 37-39). Assert it in the offline validation script:
```bash
nix eval --json '.#nixosConfigurations.ser8.config.services.mealie.settings.ALLOW_SIGNUP'   # must be "false"
```

**Warning signs:** anyone reaching the endpoint can create an account; `systemctl show mealie -p Environment` shows `ALLOW_SIGNUP=` with nothing after it.

**Requirement at risk:** MEAL-02, and the D-09 "security posture lives in config" intent.

---

### Pitfall 2: `BASE_URL` defaults to localhost, and forwarded headers are ignored by default

**What goes wrong:** two separate failures that both survive a "does the homepage load?" check. The module hardcodes `BASE_URL = "http://localhost:${toString cfg.port}"` [VERIFIED: module line 89], so share links, password-reset links, and any future OIDC redirect point at `localhost:9000`. Separately, even with a corrected `BASE_URL`, gunicorn ignores `X-Forwarded-Proto` from an untrusted peer, so generated URLs can come out `http://` on an `https://` site.

**Why it happens:** the `//` merge at module line 92 means `settings.BASE_URL` *does* win over the hardcoded default — but only if you remember to set it. And gunicorn's trust list defaults to loopback only:

```python
# Source: benoitc/gunicorn gunicorn/config.py:1352-1358 [VERIFIED via gh api this session]
class ForwardedAllowIPS(Setting):
    name = "forwarded_allow_ips"
    section = "Server Mechanics"
    cli = ["--forwarded-allow-ips"]
    meta = "STRING"
    validator = validate_string_to_addr_list
    default = os.environ.get("FORWARDED_ALLOW_IPS", "127.0.0.1,::1")
```

Caddy proxies from firebat's LAN address, so the peer gunicorn sees is `192.168.68.63`, which is not in the default list.

**How to avoid:**
```nix
services.mealie.settings.BASE_URL = "https://mealie.shad-bangus.ts.net";
services.mealie.extraOptions = [ "--forwarded-allow-ips" "192.168.68.63" ];
```
`extraOptions` reach gunicorn because the package's `bin/mealie` is a wrapper around it:
```bash
# Source: nixpkgs unstable pkgs/by-name/me/mealie/package.nix:174 [VERIFIED]
        ${lib.getExe pythonpkgs.gunicorn} "$@" -k uvicorn.workers.UvicornWorker mealie.app:app;
```
and uvicorn's gunicorn worker forwards the setting through: `"forwarded_allow_ips": self.cfg.forwarded_allow_ips,` [VERIFIED: encode/uvicorn `uvicorn/workers.py:52` at tag `0.51.0`].

Prefer the explicit address over `*`. `*` disables front-end IP checking entirely, which is a real downgrade for a service that will later sit beside Actual Budget.

**Verify by:** copying a recipe share link and confirming it starts `https://mealie.shad-bangus.ts.net`. Loading the homepage proves nothing here.

**Requirement at risk:** MEAL-03.

---

### Pitfall 3: PostgreSQL major version is chosen silently by `stateVersion`

**What goes wrong:** `services.mealie.database.createLocally = true` sets `services.postgresql.enable = true` as a side effect. The postgresql module then picks its package from `system.stateVersion`, and ser8's is `system.stateVersion = "24.11";` [VERIFIED: `hosts/ser8/configuration.nix:292`], which selects **PostgreSQL 16**:

```nix
# Source: nixpkgs 26.05 nixos/modules/services/databases/postgresql.nix:658-670 [VERIFIED]
          if versionAtLeast config.system.stateVersion "25.11" then
            pkgs.postgresql_17
          else if versionAtLeast config.system.stateVersion "24.11" then
            pkgs.postgresql_16
          else if versionAtLeast config.system.stateVersion "23.11" then
            pkgs.postgresql_15
```

No warning fires — the module's `mkWarn` path only triggers for the oldest surviving major. Once data exists at `/persist/var/lib/postgresql/16`, "cleaning up" to 17 makes the server refuse to start with `database files are incompatible with server`, recoverable only via `pg_upgrade` against an impermanence-managed directory.

**How to avoid:** pin explicitly, in the very first commit that enables Postgres, before any data exists (D-08). The default is `mkDefault`, so a plain assignment wins:
```nix
services.postgresql.package = pkgs.postgresql_17;   # 17.7 on the locked 26.05 rev
```
`dataDir` then resolves to `/var/lib/postgresql/17` (`mkDefault "/var/lib/postgresql/${cfg.package.psqlSchema}"`, `psqlSchema` = `"17"`) [VERIFIED: `postgresql.nix:682`, and `nix eval` of `psqlSchema`].

**Warning signs:** `SHOW server_version;` returns a version nobody chose; `/persist/var/lib/postgresql/` contains more than one version subdirectory.

**Requirement at risk:** FOUND-04, and irreversibly so.

---

### Pitfall 4: the persisted `/var/lib/postgresql` ownership question is smaller than PITFALLS.md implies, but the dead rule is real

**What goes wrong (as feared):** `/var/lib/postgresql` is persisted as a bare string entry, so impermanence creates `/persist/var/lib/postgresql` as `root:root 0755`, and PostgreSQL refuses to start on a data directory it does not own.

**What is actually true:** the postgresql module sets `StateDirectory = "postgresql postgresql/${cfg.package.psqlSchema}"` with `StateDirectoryMode` of `0750` for any version ≥ 11 [VERIFIED: `postgresql.nix:850-851`, `groupAccessAvailable` at line 69]. systemd creates *and chowns* both levels at unit start, and the bind mount propagates that to `/persist`. So the ordering hazard is largely handled upstream — but this has never been exercised on ser8, and the repo already noticed the gap once and left it dead:

```nix
# Source: hosts/ser8/impermanence.nix:112 [VERIFIED — this exact line, still commented out]
    # "d /persist/var/lib/postgresql 0700 postgres postgres -"
```

**How to avoid:** uncomment it, and **change `0700` to `0750`** so the declarative rule agrees with what systemd will set rather than fighting it. PostgreSQL accepts `0750` on `PGDATA` for any version ≥ 11, so `0750` is correct and `0700` invites a permission flap on every start. Then verify on the live host after the first activation:
```bash
stat -c '%U %G %a' /var/lib/postgresql /var/lib/postgresql/17 /persist/var/lib/postgresql
# expect: postgres postgres 750  (all three)
```
This is the Claude's-Discretion item "verifying `/var/lib/postgresql` ownership lands as `postgres:postgres 0700`" — the answer is that the correct target is `0750`, not `0700`, and the reason is `StateDirectoryMode`.

**Warning signs:** `FATAL: data directory "/var/lib/postgresql/17" has invalid permissions`; needing a manual `chown` at all.

**Requirement at risk:** FOUND-04, MEAL-05.

---

### Pitfall 5: the firewall port is not optional, and no `openFirewall` option exists

**What goes wrong:** the `services.mealie` module has **no `openFirewall` option** [VERIFIED: full module read, options are `enable`, `package`, `listenAddress`, `port`, `settings`, `extraOptions`, `credentialsFile`, `database.createLocally`]. Caddy on firebat reverse-proxies to `192.168.68.65:9000` over the LAN, so with ser8's firewall closed the tsnet vhost returns 502 while `curl localhost:9000` on ser8 works perfectly — a confusing split-brain symptom.

**Why it happens:** the tsnet architecture makes it tempting to reason "Tailscale-only, therefore no LAN port needed". But the tsnet node lives on *firebat*; the ser8 hop is plain LAN HTTP.

**How to avoid:** open 9000 in the reusable module, guarded like every sibling:
```nix
networking.firewall.allowedTCPPorts = lib.mkIf config.services.mealie.enable [ config.services.mealie.port ];
```
Port 9000 is free on ser8 — `rg '9000'` across `hosts/ser8/configuration.nix`, `modules/media/`, `modules/automation/`, and `modules/common/` returns no port assignment [VERIFIED this session]. ser8's own extra list is `8080`, `9134`, `445`, `139` [VERIFIED: `hosts/ser8/configuration.nix:24-32`].

**Deliberately deferred:** narrowing exposure (bind to a specific interface, or restrict the source address to firebat) is Phase 14's SEC-01 "from outside the LAN with Tailscale off, none of the four services is reachable, verified by a negative-access smoketest". Do not smuggle that work into Phase 10, but do not claim Phase 10 achieves it either.

**Requirement at risk:** MEAL-03.

---

### Pitfall 6: `unstable.mealie` carries a deprecated uvicorn worker — D-07 is load-bearing

**What goes wrong:** a future `nix flake update` moves `nixpkgs-unstable` and breaks `mealie.service` at startup rather than at eval time, because the package's launch line hard-codes a deprecated import path:

```bash
# Source: nixpkgs unstable pkgs/by-name/me/mealie/package.nix:174 [VERIFIED]
        ${lib.getExe pythonpkgs.gunicorn} "$@" -k uvicorn.workers.UvicornWorker mealie.app:app;
```

At the locked rev, uvicorn is 0.51.0 and that module already warns on import: `"The \`uvicorn.workers\` module is deprecated. Please use \`uvicorn-worker\` package instead.\n"` with `DeprecationWarning` [VERIFIED: `gh api` on `encode/uvicorn` `uvicorn/workers.py` at tag `0.51.0`, lines 18-20].

**Why it matters here:** D-07 already forbids moving `unstable.mealie` before Phase 11 backups exist, framed around Alembic migrations. This is a second, independent reason — and it is the kind that `nix build` will not catch, because the failure is at runtime import, not at evaluation.

**How to avoid:** honour D-07. When the input eventually moves, the acceptance check must include `systemctl is-active mealie` on a real activation, not just a successful build.

---

### Pitfall 7: Mealie has two state stores, and one of them is not in PostgreSQL

**What goes wrong:** recipe images, scraped photos, user assets, and the token-signing secret are written to `DATA_DIR` on disk, not into Postgres. A "does the database survive a reboot?" check therefore passes while every recipe thumbnail is broken and every user has been logged out.

**Why it happens:** "Mealie with PostgreSQL" reads as "the state is in Postgres". `DATA_DIR = "/var/lib/mealie"` is set in the module's `environment` block [VERIFIED: module line 90] and is easy to overlook because it is not an option, just a hardcoded env var.

**How to avoid:** MEAL-05's reboot check must assert **both** stores. Before the first reboot, create a recipe *with an uploaded image*; after the second, confirm the image renders and that the session was not invalidated. Structure the check as: `psql` row count for recipes AND a non-empty image tree under the persisted `DATA_DIR` AND an HTTP 200 on the image URL.

**Warning signs:** users report being logged out after every ser8 reboot (the token secret is being regenerated); thumbnails render as broken images.

**Requirement at risk:** MEAL-05 — and this pitfall is the difference between a check that certifies the criterion and one that certifies nothing.

---

### Pitfall 8: two accounts in different households do not share a shopping list

See "Mealie Application Model" below for the full detail. Summarised as a pitfall: MEAL-04 is a statement about *where the second account is placed*, and placing it wrong produces no error anywhere. Both users must be in the same **household**, not merely the same **group**.

## Mealie Application Model (what MEAL-02 and MEAL-04 actually require)

Mealie v2.0.0 introduced **Households** as a subdivision of **Groups**, and moved several things from group scope to household scope. The relevant split [CITED: github.com/mealie-recipes/mealie/releases/tag/v2.0.0]:

| Entity | Scope | Consequence for this phase |
|--------|-------|----------------------------|
| Foods, Units, Labels | **Group** | Seed once per group. MEAL-04's seeding half is group-level work |
| Categories, Tags, Tools | Group | Shared automatically |
| **Shopping Lists** | **Household** | **Both users must be in the SAME household** or MEAL-04 fails silently |
| Meal Plans | Household | Same constraint |
| Recipes / Cookbooks | Household (with cross-household visibility settings) | Household-level "view-only vs editable by any user from any household" toggle exists |
| Integrations (notifiers, webhooks) | Household | Not used this phase |

Shopping-list API endpoints moved under `/api/households/shopping/lists` in v2.0.0 — useful as the smoketest target and as the unambiguous confirmation that the scope really is household-level.

**Bootstrap facts (all first-init-only):**

| Value | Default | Note |
|-------|---------|------|
| Admin email | `changeme@example.com` | [CITED: docs.mealie.io installation-checklist] |
| Admin password | `MyPassword` | Change immediately — D-10, MEAL-02 |
| `DEFAULT_GROUP` | `Home` | [CITED: docs.mealie.io backend-config] |
| `DEFAULT_HOUSEHOLD` | `Family` | [CITED: docs.mealie.io backend-config] |
| `ALLOW_SIGNUP` | `false` | Upstream default is already false; D-09 sets it explicitly anyway so the posture is visible in config rather than inherited |
| `ALLOW_PASSWORD_LOGIN` | `true` | Leave alone; no OIDC this phase |
| `TOKEN_TIME` | `48` (hours) | Leave alone |
| `SECURITY_MAX_LOGIN_ATTEMPTS` / `SECURITY_USER_LOCKOUT_TIME` | `5` / `24` | Leave alone; both are sane and both are relevant to the household threat model |

`DEFAULT_GROUP`, `DEFAULT_HOUSEHOLD`, `DEFAULT_EMAIL`, and `DEFAULT_PASSWORD` apply **only at first database initialisation** and are ignored thereafter [CITED: docs.mealie.io installation-checklist]. Since D-10 makes bootstrap manual, the plan can either leave them at defaults and rename via the UI, or set `DEFAULT_GROUP`/`DEFAULT_HOUSEHOLD` in `settings` for a self-documenting first boot. Either is fine; do not set `DEFAULT_PASSWORD` (it would put a credential into the Nix store, which Phase 14's SEC-02 explicitly forbids).

**Seeding procedure (manual, D-10)** [CITED: docs.mealie.io + github.com/mealie-recipes/mealie/issues/7273]: user menu → Manage Data (`/group/data/foods`) → Foods → Seed → pick language → wait → switch to Units → Seed → pick language. Do it **exactly once**: re-seeding produces duplicates or fails on the `ingredient_foods_name_group_id_key` unique constraint. Labels are what make shopping lists auto-categorise, so seed them too if a separate seed action exists in 3.22.0's UI.

**TZ:** the repo sets `time.timeZone = "America/Los_Angeles";` [VERIFIED: `modules/common/locale.nix:12`]. Mealie's `TZ` defaults to `UTC` and its docs say it "Must be set to get correct date/time on the server" [CITED: docs.mealie.io backend-config], and `DAILY_SCHEDULE_TIME` (default `23:45`) is interpreted in the server's local time. Set `TZ = "America/Los_Angeles";` in `settings` to match the host.

## Google Takeout Tasks Archive (IMP-01)

IMP-01 is deliberately a *fact-finding* requirement: request the export early (it takes hours to days), then record the delivered archive's **real** structure. Nothing below is a fact about the household's archive — it is the hypothesis the inspection exists to confirm or falsify. Write no import code this phase (that is Phase 13, IMP-02/IMP-03).

**Expected top-level shape** [ASSUMED — from community tooling and the Tasks API schema, not from a real archive]:

```json
{ "items": [ { "<list metadata>": "...", "items": [ { "<task>": "..." } ] } ] }
```

An array of lists, each carrying a nested array of tasks. Task objects appear to mirror the Google Tasks API `Task` resource: `kind`, `id`, `etag`, `title`, `updated`, `selfLink`, `parent`, `position`, `notes`, `status` (`needsAction` | `completed`), `due` (RFC 3339, date-only semantics — the time part is discarded), `completed`, `deleted`, `hidden`, `links` [CITED: developers.google.com/tasks/reference/rest/v1/tasks].

**The finding that matters most:** Google's Takeout export for Tasks does **not** include usable recurrence information. Recurring chores are stored as generated instances rather than an RRULE equivalent. Since "recurring chores" is half of Phase 13's import scope, this is the single highest-value thing for the inspection to confirm or refute against the real archive.

**Checklist for the inspection write-up** (the Claude's-Discretion item says a `.planning/` doc is fine — suggest `.planning/research/google-tasks-takeout.md`):

1. Exact top-level key names and nesting, quoted from the real file.
2. Full field list on a single task, quoted verbatim.
3. Search a task **known to repeat**: does *any* recurrence key appear? Record the literal answer.
4. How many entries have `status: "completed"`, and how far back completion timestamps go (long-lived lists carry years of noise).
5. Whether `deleted` / `hidden` entries are present.
6. Whether `parent`/`position` ordering places children before parents anywhere (a single-pass importer would fail).
7. Timezone handling of `due`: confirm it is date-only anchored at UTC midnight. Rendering that in America/Los_Angeles shifts every due date back by one day.
8. Record the file's SHA-256 and where the archive is stored, so Phase 13 works against the same bytes.

**Do not** commit the archive itself — it is household personal data. Record structure and counts only.

## Code Examples

All examples below are shaped from source read this session. Values that appear here also appear in the verbatim quotes above; anything not quoted above is marked.

### `modules/household/default.nix`

```nix
# SPDX-License-Identifier: GPL-3.0-or-later
# Shape from: modules/media/default.nix:1-17 [VERIFIED]

{ ... }:

{
  imports = [
    ./mealie.nix
  ];
}
```

### `modules/household/mealie.nix` (Decision Point 1, Option B)

```nix
# SPDX-License-Identifier: GPL-3.0-or-later
# Shape from: modules/media/prowlarr.nix:21-56 and modules/media/bazarr.nix:10-25 [both VERIFIED]

{
  config,
  lib,
  ...
}:

{
  users.groups.mealie = lib.mkIf config.services.mealie.enable { };

  users.users.mealie = lib.mkIf config.services.mealie.enable {
    isSystemUser = true;
    group = "mealie";
    home = "/var/lib/mealie";
    description = "Mealie";
  };

  services.mealie.enable = lib.mkDefault false;

  # Upstream sets DynamicUser = true, which relocates state to
  # /var/lib/private/mealie and allocates a transient UID. Same override as
  # modules/media/prowlarr.nix so household state is owned, persistable, and
  # readable by the Phase 11 backup job.
  systemd.services.mealie.serviceConfig = lib.mkIf config.services.mealie.enable {
    DynamicUser = lib.mkForce false;
    User = "mealie";
    Group = "mealie";
  };

  # No openFirewall option exists on services.mealie; Caddy on firebat
  # reverse-proxies to this port over the LAN.
  networking.firewall.allowedTCPPorts = lib.mkIf config.services.mealie.enable [
    config.services.mealie.port
  ];
}
```

### `hosts/ser8/household/mealie.nix`

```nix
# SPDX-License-Identifier: GPL-3.0-or-later
# `unstable` arrives via flake.nix specialArgs (flake.nix:170-177) [VERIFIED]

{ unstable, ... }:

{
  services.mealie = {
    enable = true;

    # D-06: commit to 3.22.0 at first boot. Stable 26.05 ships 3.16.0 and the
    # module is byte-identical across both branches, so a package-only override
    # is safe. Alembic migrations are one-way: D-07 gates any future bump.
    package = unstable.mealie;

    database.createLocally = true;

    settings = {
      # Every value MUST be a string: the module stringifies with `toString`,
      # and `toString false` is "" in Nix.
      BASE_URL = "https://mealie.shad-bangus.ts.net";
      ALLOW_SIGNUP = "false";
      TZ = "America/Los_Angeles";
    };

    # gunicorn trusts only 127.0.0.1,::1 for X-Forwarded-* by default;
    # firebat proxies from its LAN address.
    extraOptions = [
      "--forwarded-allow-ips"
      "192.168.68.63"
    ];
  };
}
```

### `hosts/ser8/household/postgresql.nix`

```nix
# SPDX-License-Identifier: GPL-3.0-or-later

{ pkgs, ... }:

{
  # FOUND-04 / D-08. services.postgresql.enable arrives implicitly from
  # services.mealie.database.createLocally. Without this pin, ser8's
  # system.stateVersion = "24.11" silently selects postgresql_16, and changing
  # majors after data exists requires pg_upgrade against a persisted dataDir.
  # Plain assignment, not mkDefault: a defaultable version pin is not a pin.
  services.postgresql.package = pkgs.postgresql_17;
}
```

### `modules/gateway/Caddyfile` — the new block

```
# Append alongside the existing tsnet blocks. No header_up: Mealie needs no
# WebSocket handling, and the unconditional Connection: Upgrade pattern used by
# the frigate/hass blocks breaks ordinary requests. Static IP, not ser8.local,
# per the comment block at lines 76-97.
https://mealie.shad-bangus.ts.net {
	log tailscale {
		level DEBUG
	}
	bind tailscale/mealie
	reverse_proxy 192.168.68.65:9000
}
```

Run `make fmt-caddy` after editing — it runs `caddy fmt --overwrite` then `caddy validate` [VERIFIED: `Makefile:160-162`]. Caddy's formatter uses tabs, matching the existing file.

### `scripts/smoketests/ser8/all.sh` — the one-line edit

```bash
TESTS=(
	./scripts/smoketests/media/all.sh
	./scripts/smoketests/household/all.sh    # <-- added
	./scripts/smoketests/nordvpn/all.sh
	./scripts/smoketests/ser8/test-zfs-health.sh
	./scripts/smoketests/ser8/test-vaapi.sh
	./scripts/smoketests/ser8/test-frigate.sh
	./scripts/smoketests/ser8/test-home-assistant.sh
)
```

### `scripts/smoketests/household/all.sh`

```bash
#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Shape from: scripts/smoketests/ser8/all.sh:22-39 [VERIFIED]

set -euo pipefail

# shellcheck source=scripts/lib/all.sh
. ./scripts/lib/all.sh
# shellcheck source=scripts/smoketests/lib/fanout.sh
. ./scripts/smoketests/lib/fanout.sh

SUITE_NAME="household"
TESTS=(
	./scripts/smoketests/household/test-mealie-service.sh
	./scripts/smoketests/household/test-mealie-endpoint.sh
)

run_suite "$@"
```

### `scripts/validation/test-mealie-module.sh` — the offline gate

```bash
#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Shape from: scripts/validation/test-actual-module.sh [VERIFIED]
#
# Asserts, without touching a host, the four things this phase can get silently
# wrong: the Mealie version actually resolved, the postgres major actually
# pinned, the string-typed settings, and the endpoint URL.

set -euo pipefail

project_root=$(git rev-parse --show-toplevel)
cd "$project_root"

host=ser8
failures=0

check_eval() {
	local label=$1 expr=$2 expected=$3 actual
	actual=$(nix eval --json "$expr")
	if [ "$actual" != "$expected" ]; then
		echo "FAIL: $label is $actual, expected $expected" >&2
		failures=$((failures + 1))
		return
	fi
	echo "ok: $label = $actual"
}

check_eval "mealie package version" \
	".#nixosConfigurations.${host}.config.services.mealie.package.version" '"3.22.0"'

check_eval "postgresql major" \
	".#nixosConfigurations.${host}.config.services.postgresql.package.psqlSchema" '"17"'

check_eval "mealie BASE_URL" \
	".#nixosConfigurations.${host}.config.services.mealie.settings.BASE_URL" \
	'"https://mealie.shad-bangus.ts.net"'

# The toString-boolean trap: a Nix `false` would evaluate to "" here.
check_eval "mealie ALLOW_SIGNUP" \
	".#nixosConfigurations.${host}.config.services.mealie.settings.ALLOW_SIGNUP" '"false"'

check_eval "postgres dataDir" \
	".#nixosConfigurations.${host}.config.services.postgresql.dataDir" '"/var/lib/postgresql/17"'

if [ "$failures" -ne 0 ]; then
	echo "$failures assertion(s) failed" >&2
	exit 1
fi

echo "✓ Mealie/PostgreSQL configuration confirmed on $host"
```

Wire it into `make check` next to the three existing validation scripts [VERIFIED: `Makefile:138-151`].

## Runtime State Inventory

Phase 10 is greenfield — it introduces services, it does not rename or migrate anything. The categories are answered anyway, because the interaction between *new* services and *existing* runtime state is exactly where this phase can go wrong.

| Category | Items Found | Action Required |
|----------|-------------|-----------------|
| Stored data | **None pre-existing.** `rg 'postgresql'` across the repo excluding `.planning/` and `flake.lock` returns exactly two hits, both in `hosts/ser8/impermanence.nix` (lines 60 and 112) — no host has ever enabled PostgreSQL [VERIFIED]. `/persist/var/lib/postgresql` on ser8 should therefore be empty or absent; if it is **not**, that is a finding and the plan must inspect it before first start | Verify on the live host that `/persist/var/lib/postgresql` has no pre-existing version subdirectory before the first Postgres activation |
| Live service config | firebat's Caddy config is fully declarative (`modules/gateway/Caddyfile`, deployed to `/etc/caddy/caddy_config`); `test-caddy.sh` already diffs deployed vs working-tree and warns on drift. Tailscale node registrations are created by the caddy-tailscale plugin at runtime from `TS_AUTHKEY` — a **new tsnet node named `mealie` will be registered in the tailnet** and will persist in the Tailscale admin console independently of this repo | After the firebat switch, confirm the `mealie` node appears in `tailscale status`. If the phase is ever rolled back, the orphaned tailnet node must be removed from the admin console by hand |
| OS-registered state | **None.** No new timers, no Task Scheduler equivalent, no pm2. Backup timers are Phase 11 | None |
| Secrets/env vars | **None new.** `createLocally` uses peer auth over the unix socket with no password; `credentialsFile` stays `null` (no SMTP, no OIDC this phase). The Caddy tsnet node reuses the existing shared `sops.secrets.tailscale_authkey` — no per-service key [VERIFIED: `modules/gateway/caddy.nix:25-30`]. Mealie account passwords are set in the UI and stored nowhere in the repo | None — and a plan that adds a `secrets/ser8.yaml` entry for Mealie has misunderstood `createLocally` |
| Build artifacts | **None.** Nothing is compiled or installed outside the Nix store | None |
| **Adjacent dead state (flagged, not owned)** | `hosts/ser8/impermanence.nix:150` still carries `"d /persist/var/lib/private/prowlarr 0755 prowlarr prowlarr -"` while `modules/media/prowlarr.nix:40` forces `DynamicUser = lib.mkForce false` — the rule targets a path Prowlarr no longer uses. Both `/var/lib/prowlarr` (line 56) and the `private/` rule exist [VERIFIED] | Out of scope, but note it: a plan that adds a household `private/` rule by copying line 150 would be copying dead code. Worth a separate todo under "replace, don't deprecate" |

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| `nix` | everything | ✓ | 2.34.7+1 | — |
| `caddy` (dev shell) | `make fmt-caddy`, `caddy adapt` in `test-caddy.sh` | ✓ | 2.11.3 | — |
| `statix` | `make check` | ✓ | present | — |
| `nixfmt` (rfc-style) | `make fmt` | ✓ | 1.2.0 | — |
| `sops` | not needed this phase | ✓ | 3.13.0 | — |
| `yq` | `deploy.yaml` reads in smoketests | ✓ | v4.53.2 | — |
| `jq` | smoketests | ✓ | 1.8.1 | — |
| `shellcheck` / `shfmt` | new shell scripts | ✓ | present / 3.12.0 | — |
| `rg` / `fd` | exploration | ✓ | 15.1.0 / 10.3.0 | — |
| `nixpkgs` input @ `e4bae1bd` | postgresql_17, mealie module | ✓ | 26.05 | — |
| `nixpkgs-unstable` input @ `e5bdc4a4` | `unstable.mealie` 3.22.0 | ✓ | already locked, no bump needed | — |
| `unstable` in `specialArgs` | the package override | ✓ | `flake.nix:170-177`, comment reads "Retained with no in-tree consumers: Phase 10 needs this plumbing." [VERIFIED] | — |
| ser8 reachable at `192.168.68.65` | deploy + smoketests | not probed this session | — | none — blocking if down |
| firebat reachable at `192.168.68.63` | Caddyfile deploy | not probed this session | — | none — blocking if down |
| Tailscale tailnet + second member enrolled | MEAL-01..04 acceptance | asserted by D-05 | — | none |
| Google account with Tasks data | IMP-01 | user action | — | none — long-lead, request at phase start |

**Missing dependencies with no fallback:** none identified locally. Host reachability was deliberately not probed (it would require SSH from this session); the plan's first deploy task should begin with `make status`.

**Known environment hazards inherited from Phase 9** (from STATE.md, must be visible to planning, none of them owned by this phase):
- ser8's NordVPN tunnel is down and `make smoketests-ser8` exits 1 pre-existing. A Phase 10 plan that gates on "`make smoketests-ser8` exits 0" will never pass. Gate on the **household area's** exit status, or on a per-area diff against a captured baseline, exactly as Phase 9 plan 05 did.
- `nordvpn/test-forwarding.sh` still queries the retired pi4 resolver.
- Remote x86 builds from the dev machine need the `nix copy --derivation` + `ssh nix-store --realise` workaround (09-04).
- `make rollback-HOST` prints TODO and is not a recovery path; recovery is selecting the previous generation in systemd-boot.

## Validation Architecture

`workflow.nyquist_validation` is absent from `.planning/config.json`, so it is treated as enabled.

### Test Framework

| Property | Value |
|----------|-------|
| Framework | No unit-test framework. Two real layers: (a) evaluation-time assertions via `nix eval` in `scripts/validation/*.sh`, aggregated by `make check`; (b) deploy-time shell smoketests under `scripts/smoketests/`, aggregated by `run_suite` and dispatched from `deploy.yaml` |
| Config file | `Makefile:138-151` (`check` target); `deploy.yaml:16` (ser8 smoketest entry point) |
| Quick run command | `nix eval --json '.#nixosConfigurations.ser8.config.services.mealie.settings.BASE_URL'` — sub-second, no host needed |
| Full suite command (offline) | `make check` |
| Full suite command (live) | `make smoketests-ser8` and `make smoketests-firebat` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| FOUND-03 | `modules/household` and `hosts/ser8/household` are in the closure and evaluate | eval | `nix build .#nixosConfigurations.ser8.config.system.build.toplevel --dry-run` (already in `make check`) | ✅ `Makefile` |
| FOUND-04 | postgres major is 17, not stateVersion-derived 16 | eval | `nix eval --json '.#nixosConfigurations.ser8.config.services.postgresql.package.psqlSchema'` → `"17"` | ❌ Wave 0 — `scripts/validation/test-mealie-module.sh` |
| FOUND-04 | `dataDir` and on-disk ownership | smoke | `ssh ser8 stat -c '%U %G %a' /var/lib/postgresql/17` → `postgres postgres 750` | ❌ Wave 0 — `scripts/smoketests/household/test-mealie-service.sh` |
| MEAL-01 | Mealie 3.22.0 resolved, not 3.16.0 | eval | `nix eval --json '.#nixosConfigurations.ser8.config.services.mealie.package.version'` → `"3.22.0"` | ❌ Wave 0 — same validation script |
| MEAL-01 | unit active and DB reachable | smoke | `ssh ser8 systemctl is-active mealie` and `ssh ser8 sudo -u postgres psql -tAc "\l mealie"` | ❌ Wave 0 — `test-mealie-service.sh` |
| MEAL-02 | registration closed in config, not just the UI | eval | `nix eval --json '...services.mealie.settings.ALLOW_SIGNUP'` → `"false"` (catches the `toString false` trap) | ❌ Wave 0 — validation script |
| MEAL-02 | default admin credentials no longer work | smoke | `curl -s -o /dev/null -w '%{http_code}' -X POST .../api/auth/token -d 'username=changeme@example.com&password=MyPassword'` → **not** 200 | ❌ Wave 0 — `test-mealie-endpoint.sh` |
| MEAL-03 | `BASE_URL` is the tsnet URL | eval | `nix eval --json '...services.mealie.settings.BASE_URL'` | ❌ Wave 0 — validation script |
| MEAL-03 | tsnet node exists and endpoint answers | smoke | from firebat: `curl -s -o /dev/null -w '%{http_code}' https://mealie.shad-bangus.ts.net` ∈ {200,301,302,303,401,403}; plus `mealie` appended to `EXPECTED_NODES` in `scripts/smoketests/gateway/test-tailscale.sh` | ❌ Wave 0 — edit existing file |
| MEAL-03 | Caddyfile still adapts and validates | eval | `caddy validate --config ./modules/gateway/Caddyfile` (already in `make fmt-caddy`) | ✅ `Makefile:162` |
| MEAL-04 | Foods and Units are non-empty | smoke | `sudo -u postgres psql mealie -tAc 'select count(*) from ingredient_foods'` > 0, same for units *(table names [ASSUMED] — confirm against the live schema before writing the assertion)* | ❌ Wave 0 — `test-mealie-service.sh` |
| MEAL-04 | one shopping list, both users, same household | **manual-only** | UAT: log in as each member, add an item as user A, confirm it appears for user B. Justification: proving *shared editing* requires two authenticated sessions and a credential the repo must not hold (D-10) | manual |
| MEAL-05 | data survives two consecutive reboots | smoke, run after each reboot | recipe row count unchanged AND image tree non-empty under the persisted `DATA_DIR` AND the image URL returns 200 (see Pitfall 7) | ❌ Wave 0 — `test-mealie-service.sh` |
| IMP-01 | export requested and real structure recorded | **manual-only** | Human action (Google Takeout request) + a written artifact. Justification: no automatable surface | manual — artifact at `.planning/research/google-tasks-takeout.md` |

### Sampling Rate

- **Per task commit:** `nix eval` on whichever option that task touched (sub-second), plus `shellcheck` + `shfmt -d` for shell changes, plus `make fmt`.
- **Per wave merge:** `make check` (flake check + statix + the four validation scripts + dry-run builds for all four hosts).
- **Per deploy:** `make test-ser8` → `./scripts/smoketests/household/all.sh ser8` → `make switch-ser8`; and the same ladder on firebat for the Caddyfile change.
- **Phase gate:** `make check` green; the household smoketest area green; the gateway suite green; MEAL-05's reboot check run twice; then `/gsd-verify-work` for the two manual-only criteria.

**Explicit note on the ser8 suite:** `make smoketests-ser8` exits 1 today because of the pre-existing NordVPN failure. Do **not** make "`make smoketests-ser8` exits 0" a phase gate — it would be unsatisfiable through no fault of this phase. Gate on the household area's own exit status plus a per-area diff against the pre-change transcript, which is the pattern Phase 9 plan 05 established.

### Wave 0 Gaps

- [ ] `scripts/validation/test-mealie-module.sh` — covers FOUND-04, MEAL-01, MEAL-02, MEAL-03 at eval time
- [ ] `Makefile` `check` target — add the new validation script next to the existing three
- [ ] `scripts/smoketests/household/all.sh` — area entry point (name fixed by the `deploy.yaml` convention)
- [ ] `scripts/smoketests/household/test-mealie-service.sh` — unit, port, DB, ownership, seed counts, persistence
- [ ] `scripts/smoketests/household/test-mealie-endpoint.sh` — tsnet URL, default-credential rejection, `BASE_URL` not localhost
- [ ] `scripts/smoketests/ser8/all.sh` — append `household/all.sh` to `TESTS`
- [ ] `scripts/smoketests/gateway/test-tailscale.sh` — append `"mealie"` to `EXPECTED_NODES`
- [ ] Confirm the real Mealie 3.22.0 table names for the Foods/Units assertions before writing them (currently `[ASSUMED]`)
- [ ] Framework install: none needed — every tool is already in the dev shell

## Security Domain

`security_enforcement` is absent from `.planning/config.json`, so it is enabled.

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | **yes** | Mealie's own auth. Controls this phase: default admin credentials changed (MEAL-02); `ALLOW_SIGNUP = "false"` declaratively (D-09); upstream `SECURITY_MAX_LOGIN_ATTEMPTS = 5` and `SECURITY_USER_LOCKOUT_TIME = 24` left at their defaults (both sane). Do not set `DEFAULT_PASSWORD` in Nix — it would land world-readable in `/nix/store` |
| V3 Session Management | **yes** | `TOKEN_TIME = 48` hours (upstream default, left alone). The session-signing secret lives in `DATA_DIR`; **if `DATA_DIR` is not persisted the secret is regenerated on every rollback and every user is silently logged out on every reboot** (Pitfall 7). Persistence is a session-integrity control here, not only a data-durability one |
| V4 Access Control | **yes** | Two layers. Network: reachability is Tailscale-only *by intent*, but the ser8 LAN port is genuinely open (Pitfall 5) — the negative-access proof is Phase 14 SEC-01 and Phase 10 must not claim it. Application: Mealie's group/household model is the authorization boundary; note that upstream v2.5.0 shipped fixes for household-level privilege-escalation vulnerabilities exploitable by users with existing accounts, which is a point in favour of D-06's "start on 3.22.0" |
| V5 Input Validation | yes (upstream) | Recipe scraping and ingredient parsing are upstream's surface. `ALLOWED_IFRAME_HOSTS` defaults to `""`; leave it empty — the docs warn that adding hosts "opts into rendering embeds from those origins to all viewers, including the public" |
| V6 Cryptography | **yes** | TLS is terminated by Caddy using a certificate obtained through Tailscale's ACME — a genuinely trusted cert, not the `local_certs` local CA that the `.vofi` names use. Nothing is hand-rolled. No secret material is introduced by this phase |
| V7 Error Handling / Logging | partial | `log tailscale { level DEBUG }` on the vhost matches every sibling block. DEBUG on a tsnet listener logs request metadata to firebat's journal; acceptable, and consistent |
| V8 Data Protection | **yes** | Household recipe data at rest on ZFS. No encryption-at-rest requirement is stated anywhere in REQUIREMENTS.md — do not invent one. Backups are Phase 11 |
| V12 Secure Communication | yes | firebat → ser8 is **plaintext HTTP over the LAN** (`reverse_proxy 192.168.68.65:9000`). This is the established repo pattern for all eleven existing services and is not a Phase 10 regression, but it should be stated in the plan rather than glossed |
| V14 Configuration | **yes** | `ALLOW_SIGNUP` and the postgres pin are configuration-as-security. Phase 14's SEC-02 ("no household secret appears anywhere in the Nix store") is best served by Phase 10 introducing **no secret at all** — which `createLocally` peer auth achieves |

### Known Threat Patterns

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Open registration on a freshly deployed instance | Spoofing / Elevation | `ALLOW_SIGNUP = "false"` **as a string** — the Nix-boolean form silently disables the control (Pitfall 1) |
| Default admin credentials left in place | Spoofing | Change at first login (D-10, MEAL-02); assert with a negative smoketest that a `changeme@example.com`/`MyPassword` token request does **not** return 200 |
| Credential material in `/nix/store` | Information Disclosure | Introduce no secrets; do not set `DEFAULT_PASSWORD`; keep `credentialsFile = null`. Phase 14 SEC-02 automates the check |
| `X-Forwarded-Proto` spoofing from an untrusted peer | Spoofing | `--forwarded-allow-ips 192.168.68.63` — an explicit address, **not** `*`, which disables front-end IP checking entirely |
| Wrong Postgres major after data exists | Denial of Service (self-inflicted, unrecoverable without `pg_upgrade`) | Explicit pin before first start (Pitfall 3) |
| Session invalidation via non-persisted `DATA_DIR` | Denial of Service | Persist the state directory; verify across two reboots (MEAL-05) |
| Cross-household data exposure within one Mealie group | Information Disclosure | Both members intentionally in the SAME household; recipes are then shared by design. Start on 3.22.0, which is past the v2.5.0 household privilege-escalation fixes |
| Orphaned tsnet node if the phase is reverted | Spoofing (a stale tailnet name) | Remove the `mealie` node from the Tailscale admin console if the Caddyfile change is rolled back — the node is runtime state, not repo state |

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| One Mealie "Group" per family; shopping lists group-scoped | Groups contain **Households**; shopping lists, meal plans, and integrations moved to household scope | Mealie v2.0.0 | Directly governs MEAL-02/MEAL-04 — see "Mealie Application Model" |
| `ALLOW_SIGNUP` as the primary onboarding path | Invite links; `ALLOW_SIGNUP` defaults to `false` upstream | Mealie v1.x → v3.x | D-09 sets it explicitly anyway, which is the right call: an inherited default is not a recorded posture |
| `uvicorn.workers.UvicornWorker` bundled with uvicorn | Deprecated in favour of the separate `uvicorn-worker` package | uvicorn ≤ 0.51.0 already emits the DeprecationWarning | The nixpkgs mealie launcher still uses the old path — a runtime-only breakage risk on a future unstable bump (Pitfall 6) |
| `services.postgresql.package` floats from `stateVersion` | Pin explicitly; upstream added a `mkWarn` nudge (only for the oldest major) | ongoing nixpkgs policy | ser8's `24.11` sits in the silent band — no warning at all (Pitfall 3) |
| `hosts/ser8/media.nix` as one large host file | Two-layer `modules/media/` + `hosts/ser8/media/` split | Phase 08 (this repo) | The pattern FOUND-03 asks Phase 10 to extend |
| `deploy.yaml` ser8 entry pointing straight at `media/all.sh` | `scripts/smoketests/ser8/all.sh` fan-out via `run_suite` | already landed (Phase 09 era) | **D-11 is mostly already built** — Decision Point 3 |

**Deprecated / outdated in the inputs to this phase:**
- CONTEXT.md D-08's "17.11" — the locked 26.05 rev carries PostgreSQL **17.7**.
- CONTEXT.md's canonical-refs line "Mealie needs zero new impermanence entries" — true only under Decision Point 1 Option A.
- STACK.md's `BASE_URL = "https://mealie.vofi"` and PITFALLS.md's `mealie.vofi` references — superseded by D-01/D-02.
- STACK.md's "The `nixpkgs-unstable` input is currently locked at `d233902339c0` ... which carries mealie 3.12.0. Bump that input" — **stale**; the input is now `e5bdc4a4` carrying 3.22.0, and D-06 confirms no bump is needed [VERIFIED via `flake.lock` and `nix eval`].
- `CLAUDE.md`'s "built around NixOS 25.11" — the flake is on 26.05.
- `hosts/ser8/impermanence.nix:150`'s `private/prowlarr` rule — dead since Prowlarr went static.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Google Takeout `Tasks.json` has the nested `{ items: [ { ..., items: [task] } ] }` shape with Tasks-API-style task fields | Google Takeout Tasks Archive | Low for Phase 10 (IMP-01 is inspection only, and the inspection is what corrects this), high for Phase 13 if carried forward unverified |
| A2 | Takeout exports no usable recurrence data | Google Takeout Tasks Archive | High for Phase 13 scoping — if recurrence *is* present, Phase 13's "hand-author recurring chores" plan is unnecessary work. This is the single most valuable thing for IMP-01 to settle |
| A3 | Mealie 3.22.0's Foods/Units tables are `ingredient_foods` / `ingredient_units` | Validation Architecture | A smoketest assertion that errors instead of failing meaningfully. Confirm against the live schema before writing it |
| A4 | Seeding Foods and Units is still a Manage Data → Seed button with a language picker in 3.22.0's UI | Mealie Application Model | D-10 setup steps would be wrong; the operator would find the right UI anyway, but the plan's instructions would mislead |
| A5 | Adding a tsnet vhost requires no Tailscale ACL / admin-console change (the shared `TS_AUTHKEY` covers new nodes) | Runtime State Inventory | MEAL-03 blocks on a manual tailnet action nobody planned for. Eleven existing nodes were created this way, so confidence is reasonably high — but no new node has been added in this project's recorded history |
| A6 | `time.timeZone = "America/Los_Angeles"` is the right `TZ` for Mealie | Mealie Application Model | Meal-plan dates and `DAILY_SCHEDULE_TIME` land in the wrong zone. Matches the host, so low risk, but it is a household-preference question the user could answer differently |
| A7 | Both ser8 and firebat are reachable and healthy at their `deploy.yaml` addresses | Environment Availability | The first deploy task fails. Not probed this session; `make status` first |
| A8 | The second household member's Mealie account is created by the admin in the UI (not by invite link), and D-05 means no tailnet work | Mealie Application Model | Minor — an invite link would need working SMTP, which is out of scope, so admin-creates-the-account is the only path that does not add scope |

## Open Questions (RESOLVED)

All five questions were resolved during planning.
Per-question resolution pointers are inline below.

1. **Decision Point 1 — DynamicUser or static user for Mealie?**
   - RESOLVED: static user chosen — see PD-01 in plan 10-01.
   - What we know: nixpkgs defaults to `DynamicUser = true`; `/var/lib/private` is already persisted at `0700`; the repo's own Prowlarr module forces `DynamicUser` off; Homebox is static upstream and Actual's 26.05 module exposes `user`/`group`.
   - What's unclear: nothing factual — this is a design choice, and CONTEXT.md's canonical-refs summary leans one way while the repo's precedent and FOUND-03's "pattern the remaining three services reuse" lean the other.
   - Recommendation: **Option B, static user.** Surface it to the user as a one-line confirmation during planning, since the CONTEXT summary implies otherwise. It is cheap to decide now and expensive to change after data exists.

2. **Does the tsnet `mealie` node need any Tailscale admin-console or ACL action?** (A5)
   - RESOLVED: node presence in `tailscale status` is an explicit acceptance step in plan 10-05.
   - What we know: `TS_AUTHKEY` is exported once for the whole Caddy process and eleven nodes already exist.
   - What's unclear: whether the auth key is reusable/non-expiring, and whether the tailnet ACL is default-allow.
   - Recommendation: make "the `mealie` node appears in `tailscale status`" an explicit acceptance step on the firebat deploy task, so a missing ACL surfaces immediately rather than as a mystery 502.

3. **What are Mealie 3.22.0's actual Foods/Units table names?** (A3)
   - RESOLVED: PD-04 — resolved via `to_regclass` in plans 10-01/10-03 and confirmed live in plan 10-04.
   - Recommendation: resolve during execution with `\dt` on the live database, before writing the MEAL-04 assertion. Do not guess it into a plan.

4. **`ALLOW_SIGNUP` after bootstrap — does closing signup block admin-created accounts?**
   - RESOLVED: plan 10-06 sequences accounts-first-then-verify-signup-closed.
   - What we know: `ALLOW_SIGNUP` controls "user sign-up without token" [CITED: docs.mealie.io backend-config], which reads as self-service registration only.
   - What's unclear: whether admin-created accounts and invite tokens still work with it false — relevant because D-09 sets it false declaratively from the very first boot, so it is `false` *before* the second account exists.
   - Recommendation: order the bootstrap steps so this cannot bite: create both accounts first, verify, then confirm signup is closed. If admin creation turns out to be blocked, the fallback is a temporary `ALLOW_SIGNUP = "true"` deploy — which would contradict D-09's intent, so it is worth checking early rather than discovering at the end. Phase 12's Homebox has the identical shape and STATE.md already carries it as an open concern ("registration flag may not be safely re-enablable").

5. **Is `/persist/var/lib/postgresql` on ser8 genuinely empty?**
   - RESOLVED: plan 10-04 Task 1 proves emptiness with a pre-flight directory listing before activation.
   - What we know: no repo config has ever enabled PostgreSQL.
   - What's unclear: whether anything was ever created there by hand.
   - Recommendation: one `ls -la` before the first activation. If a `16/` directory exists, FOUND-04's "before any service data exists" premise is false and the plan changes shape.

## Sources

### Primary (HIGH confidence — read from source this session)

- `nixos/modules/services/web-apps/mealie.nix` at `/nix/store/kfcxqcxb9hcq6x33sg4cmwakbb1ifwg9-source` (nixpkgs 26.05, `e4bae1bd`) — full module, all 122 lines
- Same file at `/nix/store/rd49sb5is1wap50ifnlm5amjpabwbdk1-source` (locked nixpkgs-unstable, `e5bdc4a4`) — `diff -q` reports identical
- `pkgs/by-name/me/mealie/package.nix` (locked unstable) — version 3.22.0, gunicorn/uvicorn launch line, `bin/mealie` + `libexec/init_db` wrappers
- `nixos/modules/services/databases/postgresql.nix` (26.05) — `package` default logic, `dataDir`, `StateDirectory`/`StateDirectoryMode`, `groupAccessAvailable`
- `benoitc/gunicorn` `gunicorn/config.py` `class ForwardedAllowIPS` (via `gh api`)
- `encode/uvicorn` `uvicorn/workers.py` at tag `0.51.0` (via `gh api`) — `forwarded_allow_ips` pass-through and the deprecation warning
- In-repo, all read this session: `flake.nix`, `flake.lock`, `hosts/ser8/{default,configuration,impermanence}.nix`, `hosts/ser8/media/default.nix`, `modules/media/{default,bazarr,prowlarr}.nix`, `modules/gateway/{Caddyfile,caddy.nix}`, `modules/common/locale.nix`, `deploy.yaml`, `Makefile`, `scripts/lib/all.sh`, `scripts/smoketests/{ser8/all.sh,lib/fanout.sh,lib/services.sh,media/all.sh,gateway/test-caddy.sh,gateway/test-tailscale.sh}`, `scripts/validation/test-actual-module.sh`
- Live tool checks: `nix eval` (mealie 3.16.0 stable / 3.22.0 unstable, postgresql_17 = 17.7, psqlSchema = 17, `toString false` = `""`), `caddy adapt` server/listener enumeration, dev-shell tool version probe

### Secondary (MEDIUM confidence — official docs and upstream release notes)

- docs.mealie.io — Backend Configuration (env var tables incl. `ALLOW_SIGNUP`, `BASE_URL`, `TZ`, `DEFAULT_GROUP`, `DEFAULT_HOUSEHOLD`, `DB_ENGINE`, `SECURITY_*`, `ALLOWED_IFRAME_HOSTS`)
- docs.mealie.io — Installation Checklist (default admin credentials; first-init-only semantics of `DEFAULT_*`)
- github.com/mealie-recipes/mealie/releases/tag/v2.0.0 — Households under Groups; group-vs-household scope split; `/api/households/shopping/lists`
- github.com/mealie-recipes/mealie/releases/tag/v2.5.0 — household-level privilege-escalation fixes
- github.com/mealie-recipes/mealie/issues/7273 — re-seeding and the `ingredient_foods_name_group_id_key` constraint
- developers.google.com/tasks/reference/rest/v1/tasks — Task resource field semantics
- Prior milestone research (v1.2), reconciled and corrected above: `.planning/research/{STACK,PITFALLS,ARCHITECTURE}.md`

### Tertiary (LOW confidence — community sources, flagged for validation)

- Community Google-Tasks converter tooling (`exploids/google-tasks-to-todoist`, `thethales/GoogleTasksJSONtoTXT`) for the Takeout envelope shape — A1/A2, superseded the moment IMP-01's real archive lands

## Metadata

**Confidence breakdown:**

- Standard stack: **HIGH** — every version, module contract, and option name was read from the pinned store paths or evaluated this session, not recalled
- Architecture / module layout: **HIGH** — templates quoted verbatim from the in-repo files they mirror, with line ranges
- Pitfalls 1-7: **HIGH** — each is grounded in a specific quoted line of nixpkgs, gunicorn, uvicorn, or this repo
- Mealie application semantics (households, seeding, bootstrap): **MEDIUM** — official docs and upstream release notes; no live instance was available to confirm 3.22.0's exact UI or schema
- Google Takeout archive shape: **LOW** — explicitly the hypothesis IMP-01 exists to test
- Decision Point 1: **HIGH on the facts, open on the choice** — both options are fully characterised; the selection is the planner's

**Research date:** 2026-08-18
**Valid until:** 2026-09-17 for the in-repo and pinned-input findings (they move only when `flake.lock` moves, which D-07 gates). The Mealie application-semantics section should be re-checked if the target version ever changes.
