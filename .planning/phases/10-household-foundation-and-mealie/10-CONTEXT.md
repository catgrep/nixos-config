# Phase 10: Household Foundation and Mealie - Context

**Gathered:** 2026-08-17
**Status:** Ready for planning

<domain>
## Phase Boundary

Stand up the first household service: Mealie with a pinned PostgreSQL on ser8, on the reusable-module / host-policy split (`modules/household/` + `hosts/ser8/household/`) that Homebox, Actual, and Donetick reuse in later phases.
Mealie is in daily household use at its Tailscale endpoint with both members sharing one shopping list, data survives two ser8 reboots, and the Google Takeout Tasks export has been requested with the delivered archive's real JSON structure recorded.
Backups (Phase 11), trusted household-device TLS (Phase 12), other services and import code (Phases 12-13) are out of scope.

</domain>

<decisions>
## Implementation Decisions

### Access path (supersedes stale roadmap wording)
- **D-01:** Tailscale is the primary access path, local and remote. Mealie's canonical endpoint is `https://mealie.shad-bangus.ts.net` via a new tsnet vhost on firebat (`bind tailscale/mealie`, reverse_proxy to ser8), matching every existing service block in `modules/gateway/Caddyfile`. `BASE_URL` is set to this URL.
- **D-02:** No `.vofi` config for Mealie at all — no Caddy vhost, no AdGuard rewrite. pi4's AdGuard is disconnected (Phase 9 D-06) so `.vofi` names resolve for nobody, and the planned `vofi.dev` migration (deferred todo) will redefine the LAN-name scheme. Dead config is not added for pattern symmetry.
- **D-03:** The Phase 9 D-16 skip-flagged `.vofi` smoketests stay skip-flagged. Phase 10 does not re-enable them (the D-16 note "Phase 10 re-enables once `.vofi` DNS is re-established" is superseded); their fate belongs to the vofi.dev migration todo.
- **D-04:** ROADMAP.md Phase 10 success criterion 1 and REQUIREMENTS.md MEAL-03 were reworded from the AdGuard/`.vofi` framing to the Tailscale endpoint before planning (done in this discussion session).
- **D-05:** The second household member is already on the tailnet — no invite/onboarding work in this phase.

### Mealie version
- **D-06:** Commit to Mealie 3.22.0 at first boot via `services.mealie.package = unstable.mealie`. The locked `nixpkgs-unstable` (`e5bdc4a41d4c`) already carries 3.22.0 — no input bump needed. Start on the version we keep: no standing up 3.16.0 "to test" first. — **Reversibility:** one-way — Mealie runs Alembic migrations on start with no downgrade path, and no backups exist until Phase 11.
- **D-07:** Version drift is gated by flake.lock: `unstable.mealie` only moves when a deliberate, staged `nix flake update` commit lands (repo convention from Phase 9 D-09). Rule for downstream phases: no unstable bump that moves Mealie until Phase 11 backups exist and a fresh `pg_dump` is taken.

### PostgreSQL
- **D-08:** Pin `services.postgresql.package = pkgs.postgresql_17` explicitly (17.11 on the current 26.05 pin). Without the pin, ser8's `stateVersion = "24.11"` silently selects postgresql 16. — **Reversibility:** one-way — changing majors after data exists requires a manual `pg_upgrade` against the impermanence-persisted data directory.

### Bootstrap and hardening
- **D-09:** Registration is closed declaratively (`ALLOW_SIGNUP=false` in `services.mealie.settings`), not via UI toggle — the security posture lives in config.
- **D-10:** One-time setup is manual UI work: change default admin credentials, create both user accounts in one shared household, seed Foods/Units, confirm the single shared shopping list. No bootstrap scripting via the Mealie API.

### Verification
- **D-11:** Household smoketests are wired through a new top-level `scripts/smoketests/ser8/all.sh` that fans out to `media/all.sh` and `household/all.sh`; `deploy.yaml`'s single ser8 smoketest entry points at it. Scales for Phases 11-13. Smoketests probe the tsnet URL, not `.vofi`.
- **D-12:** ser8 has ALREADY been rebooted on 26.05 (user correction — STATE.md's "neither x86 host rebooted" record is stale). No boot-path validation step is needed; MEAL-05's two consecutive reboots are pure persistence checks.

### Claude's Discretion
- Where the postgresql pin expression lives (`modules/household/` vs `hosts/ser8/household/`) and how the module options are shaped, following the two-layer pattern.
- Verifying `/var/lib/postgresql` ownership lands as `postgres:postgres 0700` on first start (PITFALLS.md flags the persisted dir defaults root-owned).
- `--forwarded-allow-ips` value and proxy-header details for Mealie behind the firebat Caddy proxy.
- Where the Takeout archive's JSON structure notes are recorded (a `.planning/` doc is fine); the export request itself is a manual user action early in the phase.
- How the ser8/all.sh fan-out handles per-area exit codes and output.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Milestone research (v1.2)
- `.planning/research/STACK.md` — Mealie module analysis (byte-identical across branches, PostgreSQL wiring via `createLocally`, the empty-`:`-before-`@` URL quirk, `BASE_URL` override, DynamicUser/StateDirectory persistence), postgres pinning rationale, pg_dump notes.
- `.planning/research/PITFALLS.md` — The `/var/lib/private` impermanence symlink trap (do NOT persist `/var/lib/mealie`), postgres major chosen silently by stateVersion, Mealie's two state stores (Postgres + `DATA_DIR` images/uploads), `BASE_URL`/forwarded-headers pitfall.
- `.planning/research/ARCHITECTURE.md` — The `modules/household/` + `hosts/ser8/household/` scaffold layout, flake.nix/configuration.nix import points, and what NOT to import (`x86Modules`, `modules/servers/`).

### Prior phase decisions
- `.planning/phases/09-channel-bump-to-nixos-26-05/09-CONTEXT.md` — D-06 (pi4 disconnected/pending retirement), D-11 (unstable kept for the Mealie override), D-16 (`.vofi` smoketests skip-flagged; its "Phase 10 re-enables" expectation is superseded by D-03 above).

### Current implementation to follow
- `modules/gateway/Caddyfile` — The tsnet vhost block pattern (`https://<name>.shad-bangus.ts.net`, `bind tailscale/<name>`) that D-01 mirrors.
- `hosts/ser8/impermanence.nix` — Already persists `/var/lib/private` and `/var/lib/postgresql`; Mealie needs zero new impermanence entries.
- `deploy.yaml` — ser8 smoketest entry to repoint at `scripts/smoketests/ser8/all.sh` (D-11).

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `modules/media/*.nix` + `hosts/ser8/media/*.nix` — the two-layer pattern (Phase 8) that `modules/household/` mirrors: reusable module declares user/port/firewall/defaults with `enable = lib.mkDefault false`; host policy enables and configures.
- `unstable` is already threaded into host modules via `flake.nix` specialArgs — the D-06 override consumes it directly.
- Caddyfile tsnet blocks + `modules/gateway/caddy.nix` (caddy-tailscale plugin, shared `tailscale_authkey` SOPS secret) — adding a service is one vhost block; no new secrets.
- `scripts/smoketests/<area>/all.sh` convention — household tests join as a new area under the D-11 fan-out.

### Established Patterns
- SOPS secrets per host (`secrets/ser8.yaml`) — likely NOT needed this phase: `createLocally` peer auth has no DB password, and SMTP/OIDC are out of scope.
- `make test-ser8` → smoketests → `make switch-ser8` rollout ladder for live changes; firebat needs the same for the Caddyfile change.
- Staged one-logical-change commits with validation between.

### Integration Points
- `flake.nix` ser8 module list: add `./modules/household` next to `./modules/media` (NOT in `x86Modules`).
- `hosts/ser8/configuration.nix` imports: add `./household` next to `./media`.
- `modules/gateway/Caddyfile`: one new tsnet vhost on firebat.

</code_context>

<specifics>
## Specific Ideas

- Endpoint naming follows the existing convention exactly: `mealie.shad-bangus.ts.net`, lowercase service name as the tsnet node name.
- The Takeout Tasks export request happens at phase start (async, hours-to-days) so the archive can arrive within the phase window.

</specifics>

<deferred>
## Deferred Ideas

### Reviewed Todos (not folded)
- **Migrate .vofi hostnames to public vofi.dev domain** (`.planning/todos/pending/2026-08-17-migrate-vofi-hostnames-to-public-vofi-dev-domain.md`) — matched this phase (score 0.9) but explicitly ruled separate by the user. Phase 10 adds no `.vofi` config, which keeps the migration surface from growing.

</deferred>

---

*Phase: 10-household-foundation-and-mealie*
*Context gathered: 2026-08-17*
