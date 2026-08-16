---
phase: 10-household-foundation-and-mealie
plan: 01
subsystem: infra
tags: [nixos, mealie, postgresql, impermanence, caddy, tailscale, nix-modules]

# Dependency graph
requires:
  - phase: 09-nixos-2605-upgrade
    provides: the locked 26.05 nixpkgs and nixpkgs-unstable inputs, the `unstable` specialArg plumbing in flake.nix, and the release-mismatch-free evaluation baseline
provides:
  - reusable `modules/household/` module group, the second service group in the repo and the pattern Homebox/Actual/Donetick reuse
  - `hosts/ser8/household/` host-policy layer carrying enablement, version pins, and URLs
  - Mealie pinned to 3.22.0 from nixpkgs-unstable, running as a static `mealie` system user rather than under DynamicUser
  - PostgreSQL explicitly pinned to major 17 before any data exists
  - impermanence persistence for `/var/lib/mealie` and a live (no longer commented-out) postgresql tmpfiles rule at 0750
  - Caddy tsnet vhost `https://mealie.shad-bangus.ts.net` on firebat
  - `scripts/validation/test-mealie-module.sh`, a mutation-tested offline evaluation gate wired into `make check`
affects: [10-02, 10-03, 10-04, 10-05, phase-11-backups, phase-12-homebox-actual, phase-13-donetick, phase-14-security]

actuals:
  tokens: 2632
  tasks: 3
  commits: 3

tech-stack:
  added: [mealie, postgresql_17]
  patterns:
    - "Two-layer service module split: reusable modules/<group>/<svc>.nix (guarded, enable defaults false, no host identity) paired with hosts/<host>/<group>/<svc>.nix (enablement, pins, URLs, secrets)"
    - "Offline evaluation gate: assert one-way configuration choices against the evaluated closure in scripts/validation/, wired into make check, proven non-vacuous by mutation"

key-files:
  created:
    - modules/household/default.nix
    - modules/household/mealie.nix
    - hosts/ser8/household/default.nix
    - hosts/ser8/household/mealie.nix
    - hosts/ser8/household/postgresql.nix
    - scripts/validation/test-mealie-module.sh
  modified:
    - flake.nix
    - hosts/ser8/configuration.nix
    - hosts/ser8/impermanence.nix
    - modules/gateway/Caddyfile
    - Makefile

key-decisions:
  - "Mealie runs as a static `mealie` system user with DynamicUser forced off (PD-01), following modules/media/prowlarr.nix, so state lands at a real /var/lib/mealie that impermanence and the Phase 11 backup job can address"
  - "modules/household/postgresql.nix deliberately not created (PD-02): the version pin is host policy and there is no non-version hygiene left for a reusable file to carry"
  - "services.postgresql.package is a plain assignment, not mkDefault — a defaultable one-way version pin is not a pin"
  - "Every services.mealie.settings value is written as a Nix string because the module stringifies with toString, and toString false is the empty string"
  - "extraOptions sets --forwarded-allow-ips to the literal firebat LAN address rather than a wildcard, which would disable gunicorn's front-end IP check entirely"
  - "No LAN-domain (.vofi) vhost for Mealie (D-02): those names resolve for nobody today and such a block would fold into Caddy's srv0 and immediately fail the existing gateway suite"

patterns-established:
  - "Reusable module inertness: every config stanza wrapped in lib.mkIf config.services.<svc>.enable with enable = lib.mkDefault false, so importing without enabling is a no-op"
  - "Reusable layer carries no host identity — no IP, no hostname, no package pin, no secret path; enforced by a grep acceptance criterion"
  - "One-way choices (package major, on-disk data format) get an eval-time assertion in scripts/validation/ before first activation, not a runtime smoketest after"

requirements-completed: [FOUND-03, FOUND-04, MEAL-01, MEAL-02, MEAL-03]

coverage:
  - id: D1
    description: "Reusable modules/household/ layer exists with the guarded, defaultable-false shape and carries no host identity"
    requirement: "FOUND-03"
    verification:
      - kind: integration
        ref: "rg -c 'lib\\.mkIf config\\.services\\.mealie\\.enable' modules/household/mealie.nix (returns 4)"
        status: pass
      - kind: integration
        ref: "rg -c 'lib\\.mkDefault' modules/household/mealie.nix (returns 1)"
        status: pass
      - kind: integration
        ref: "rg -c '192\\.168\\.68\\.' modules/household/ (returns 0)"
        status: pass
    human_judgment: false
  - id: D2
    description: "Mealie resolves to 3.22.0 from nixpkgs-unstable, not stable's 3.16.0"
    requirement: "MEAL-01"
    verification:
      - kind: integration
        ref: "scripts/validation/test-mealie-module.sh#MEAL-01 mealie package version"
        status: pass
    human_judgment: false
  - id: D3
    description: "PostgreSQL is pinned to major 17 by explicit assignment, with dataDir following at /var/lib/postgresql/17, rather than being derived from system.stateVersion (which would select 16)"
    requirement: "FOUND-04"
    verification:
      - kind: integration
        ref: "scripts/validation/test-mealie-module.sh#FOUND-04 postgresql major"
        status: pass
      - kind: integration
        ref: "scripts/validation/test-mealie-module.sh#FOUND-04 postgresql dataDir"
        status: pass
    human_judgment: false
  - id: D4
    description: "ALLOW_SIGNUP evaluates to the string \"false\", not the empty string a Nix boolean would produce, so registration is closed at the config layer"
    requirement: "MEAL-02"
    verification:
      - kind: integration
        ref: "scripts/validation/test-mealie-module.sh#MEAL-02 mealie ALLOW_SIGNUP"
        status: pass
    human_judgment: false
  - id: D5
    description: "BASE_URL evaluates to the tsnet endpoint and gunicorn trusts forwarded headers only from firebat's LAN address"
    requirement: "MEAL-03"
    verification:
      - kind: integration
        ref: "scripts/validation/test-mealie-module.sh#MEAL-03 mealie BASE_URL"
        status: pass
      - kind: integration
        ref: "nix eval .#nixosConfigurations.ser8.config.services.mealie.extraOptions"
        status: pass
    human_judgment: false
  - id: D6
    description: "Mealie runs as a static mealie:mealie system user with DynamicUser forced off, and tcp/9000 is opened on ser8"
    requirement: "FOUND-03"
    verification:
      - kind: integration
        ref: "nix eval .#nixosConfigurations.ser8.config.systemd.services.mealie.serviceConfig.DynamicUser (false) and .Group (\"mealie\")"
        status: pass
      - kind: integration
        ref: "nix eval .#nixosConfigurations.ser8.config.networking.firewall.allowedTCPPorts | jq -e 'index(9000)'"
        status: pass
    human_judgment: false
  - id: D7
    description: "Mealie's on-disk state store is persisted across an impermanence rollback and the previously dead postgresql tmpfiles rule is live at 0750"
    requirement: "FOUND-04"
    verification:
      - kind: integration
        ref: "nix eval ...environment.persistence.\"/persist\".directories --apply 'map (d: d.directory)' | jq -e 'index(\"/var/lib/mealie\")'"
        status: pass
      - kind: integration
        ref: "nix eval ...systemd.tmpfiles.rules filtered to mealie|postgresql — yields the two 0750 rules"
        status: pass
    human_judgment: false
  - id: D8
    description: "The adapted Caddy config carries a tailscale/mealie:443 listener and no LAN-domain Mealie vhost"
    requirement: "MEAL-03"
    verification:
      - kind: integration
        ref: "caddy adapt --config ./modules/gateway/Caddyfile | jq -e '[.apps.http.servers[].listen[]] | index(\"tailscale/mealie:443\")'"
        status: pass
      - kind: integration
        ref: "rg -c '^https://mealie\\.vofi' modules/gateway/Caddyfile (returns 0)"
        status: pass
    human_judgment: false
  - id: D9
    description: "The offline gate runs from make check, asserts five values, and discriminates — a mutated copy fails loudly"
    verification:
      - kind: integration
        ref: "./scripts/validation/test-mealie-module.sh (exit 0, five ok: lines)"
        status: pass
      - kind: integration
        ref: "mutated copy with one impossible expected value (exit 1, one FAIL: line)"
        status: pass
      - kind: unit
        ref: "shellcheck + shfmt -d scripts/validation/test-mealie-module.sh"
        status: pass
    human_judgment: false
  - id: D10
    description: "Repo-wide green: make check exits 0 across all four hosts and this plan introduces no new evaluation warning class"
    verification:
      - kind: integration
        ref: "make check (exit 0, all four hosts dry-build)"
        status: pass
      - kind: integration
        ref: "nix build ...ser8... --dry-run | grep -ci 'you are using' (returns 0)"
        status: pass
    human_judgment: true
    rationale: "The plan's warning criterion permits additional warnings only if each is named and justified in this SUMMARY. Six warning lines remain in the raw output; all six are proven host-independent (identical set on pi4, which this plan does not touch), but accepting that inventory as unchanged-from-baseline is a judgment call a human should sign off on. See ## Evaluation Warning Inventory."
  - id: D11
    description: "No credential material was written into the repository, the Nix store, .planning artifacts, or commit messages"
    verification:
      - kind: integration
        ref: "rg -c 'DEFAULT_PASSWORD|credentialsFile' hosts/ser8/household/ modules/household/ (returns 0)"
        status: pass
    human_judgment: true
    rationale: "The plan marks this prohibition verification: flagged-unverified. The grep proves the two known credential-bearing option paths are absent, but 'no credential material anywhere' is a negative claim broader than any single automated check can close."

# Metrics
duration: 9 min
completed: 2026-08-18
status: complete
---

# Phase 10 Plan 01: Household Foundation and Mealie Configuration Surface Summary

**Two-layer `modules/household/` + `hosts/ser8/household/` service group wiring Mealie 3.22.0 (static system user, DynamicUser forced off) onto an explicitly pinned PostgreSQL 17, exposed via a firebat tsnet Caddy vhost, and locked behind a mutation-tested offline eval gate in `make check`.**

## Performance

- **Duration:** 9 min
- **Started:** 2026-08-18T06:46:28Z
- **Completed:** 2026-08-18T06:55:30Z
- **Tasks:** 3
- **Files modified:** 11 (6 created, 5 modified)

## Accomplishments

- Established `modules/household/` as the repo's second service module group, proving out the two-layer split that Homebox, Actual, and Donetick reuse in Phases 12-13. The reusable layer guards all four config stanzas on `lib.mkIf config.services.mealie.enable`, defaults `enable` to false, and carries no IP, hostname, package pin, or secret path.
- Closed the two one-way choices this phase can never take back, before any data exists: Mealie at 3.22.0 (evaluated, not assumed) and PostgreSQL at major 17 by plain assignment. Without the postgres pin, ser8's `system.stateVersion = "24.11"` would have silently selected major 16, recoverable afterwards only via `pg_upgrade` against an impermanence-managed directory.
- Wrote Mealie's state to a real, persisted, owned directory instead of DynamicUser's `/var/lib/private/mealie` (PD-01), and revived the postgresql tmpfiles rule that had sat commented out in `hosts/ser8/impermanence.nix` — at 0750 to agree with systemd's `StateDirectoryMode` rather than fight it on every start.
- Built `scripts/validation/test-mealie-module.sh` and proved it discriminates: a copy with one expected value replaced exits 1 with a `FAIL:` line naming the assertion. A gate that cannot fail certifies nothing.

## Task Commits

1. **Task 1 (tracer): Mealie through every layer** - `af31df3` (feat) — household module scaffold, host policy, flake/host/impermanence wiring
2. **Task 1 (tracer), second logical change: gateway vhost** - `714d71f` (feat) — Caddy tsnet vhost
3. **Task 2: offline evaluation gate** - `ae52a9b` (test) — validation script + Makefile wiring
4. **Task 3: repo-wide green** — no commit; the task is pure verification and required no code change (see Issues Encountered)

## Files Created/Modified

- `modules/household/default.nix` - Flat aggregator importing only `./mealie.nix`
- `modules/household/mealie.nix` - Reusable layer: static `mealie` user/group, `DynamicUser = lib.mkForce false` with explicit `User`/`Group`, `enable = lib.mkDefault false`, firewall port from `config.services.mealie.port`
- `hosts/ser8/household/default.nix` - Host aggregator importing `./postgresql.nix` and `./mealie.nix`
- `hosts/ser8/household/mealie.nix` - Host policy: `unstable.mealie`, `database.createLocally`, string-typed `BASE_URL`/`ALLOW_SIGNUP`/`TZ`, `--forwarded-allow-ips 192.168.68.63`
- `hosts/ser8/household/postgresql.nix` - `services.postgresql.package = pkgs.postgresql_17;` as a plain assignment, with the pg_upgrade consequence recorded in a comment
- `scripts/validation/test-mealie-module.sh` - Five eval assertions, each labelled with the requirement it defends
- `flake.nix` - ser8 modules list gains `./modules/household` (one line; deliberately not `x86Modules`, which reaches firebat)
- `hosts/ser8/configuration.nix` - imports gains `./household` (one line)
- `hosts/ser8/impermanence.nix` - `/var/lib/mealie` persisted; postgresql tmpfiles rule uncommented at 0750; new mealie tmpfiles rule at 0750
- `modules/gateway/Caddyfile` - `https://mealie.shad-bangus.ts.net` tsnet vhost, bare (no `header_up` pair)
- `Makefile` - `check` target gains the new validation script

## Decisions Made

- **Static user over DynamicUser (PD-01, executed as planned).** Verified at eval time: `serviceConfig.DynamicUser` is `false` and `serviceConfig.Group` is `"mealie"`. The explicit `Group` matters because upstream sets only `User`, leaving systemd to infer the group.
- **`modules/household/postgresql.nix` intentionally absent (PD-02).** Asserted as an acceptance criterion (`ls` must fail), so the asymmetry reads as deliberate rather than forgotten.
- **0750, not 0700, on both persisted directories.** The postgresql module sets `StateDirectoryMode = 0750` for any major at or above 11; a 0700 declarative rule would flap on every start.
- **Caddy vhost placed in a new `# -- Household services` section** at the end of the tsnet block, after the smart-home entries, rather than interleaved with the media *Arr group. `caddy fmt` and `caddy validate` both clean.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] New files invisible to flake evaluation until staged**

- **Found during:** Task 1 (first `nix build --dry-run` after creating the module files)
- **Issue:** `nix build` failed with `error: Path 'hosts/ser8/household' in the repository ... is not tracked by Git`. Flake evaluation reads from the git tree, so untracked new files do not exist as far as `nix` is concerned — the ser8 import of `./household` resolved to nothing.
- **Fix:** `git add` the five new Nix files before evaluating. No code change; a workflow ordering step that every future plan adding files to this flake will hit.
- **Files modified:** none (staging only)
- **Verification:** `nix build .#nixosConfigurations.ser8.config.system.build.toplevel --dry-run` exits 0 afterwards
- **Committed in:** `af31df3` (the files themselves)

**2. [Rule 1 - Bug in a verification command] Persistence acceptance criterion could not run as written**

- **Found during:** Task 1 (acceptance criteria verification loop)
- **Issue:** The plan's criterion `nix eval --json '...environment.persistence."/persist".directories' | jq ...` aborts with `error: The option 'method' can no longer be used since it's been removed`. Serialising the whole submodule list to JSON forces evaluation of every attribute, including a removed option the impermanence module retains only to produce that error. This is a defect in the check, not in the configuration — the underlying fact was correct all along.
- **Fix:** Substituted an equivalent that projects only the field under test: `nix eval --json '...directories' --apply 'map (d: d.directory)' | jq -e 'index("/var/lib/mealie")'`. Also added a companion check on `systemd.tmpfiles.rules` filtered to mealie/postgresql, which returns both new 0750 rules.
- **Files modified:** none (verification method only)
- **Verification:** the substituted command exits 0 and reports index 16; the tmpfiles filter returns exactly the two expected rules
- **Committed in:** n/a — recorded in `.planning/WINDOWS.md` as a `deviation` entry so plans 10-02 onward do not re-inherit the broken command shape

---

**Total deviations:** 2 auto-fixed (1 blocking, 1 verification-command bug)
**Impact on plan:** Neither changed what was built. The first is a flake-evaluation fact worth carrying forward; the second replaced a broken check with a narrower one that proves the same truth. No scope creep.

## Evaluation Warning Inventory

Task 3's acceptance criterion permits warnings beyond `nixfmt-rfc-style` only if each is named and justified here. The raw command returns 6 lines. All six are Nix CLI / local daemon-config / substituter-auth warnings, host-independent and pre-existing — the identical set appears on `pi4`, which this plan does not touch.

| Warning | Source | Status |
|---|---|---|
| `unknown experimental feature 'provenance'` | local `/etc/nix/nix.custom.conf` naming a feature this nix build does not know | Pre-existing, environmental. Identical on pi4. |
| `unknown setting 'eval-cores'` | same | Pre-existing, environmental. Identical on pi4. |
| `unknown setting 'lazy-trees'` | same | Pre-existing, environmental. Identical on pi4. |
| `Git tree ... is dirty` | uncommitted `.planning/` files during execution | Transient, disappears on a clean tree. |
| `warning:` + `unable to download 'https://cache.flakehub.com/nix-cache-info': HTTP error 401` (2 lines) | FlakeHub substituter without credentials on this workstation | Pre-existing, environmental. Identical on pi4. |

Two genuine **evaluation** warnings surface with the eval cache disabled, and neither is a Phase 10 finding:

- `sabnzbd.configFile is deprecated, consider using sabnzbd.settings` — a pre-existing media-service deprecation, untouched by this plan. Logged as out-of-scope, not fixed here.
- `stdenv.isDarwin is deprecated, use stdenv.hostPlatform.isDarwin instead` — an upstream nixpkgs notice emitted whenever a package derivation is forced from this Darwin workstation. Confirmed pre-existing: it also fires for `services.jellyfin.package.version` and on the firebat closure, which imports no household module.

**The result Task 3 was actually looking for:** the newly enabled `services.postgresql` module emitted *nothing* about `stateVersion`, `dataDir`, or package selection. That silence is the explicit pin working — the module's `mkWarn` path stays quiet precisely because the major was chosen rather than derived. The release-mismatch class (`you are using`) remains at 0 matches, as the Phase 09 record requires.

## Issues Encountered

- **Task 3 produced no commit.** The task's stated output is a green repo with no new warning class, and none of its listed files needed a change: `make fmt` and `make fmt-caddy` left the tree clean, `statix check` was clean repo-wide and on both new module directories specifically, and no new evaluation warning appeared to fix. A verification task with nothing to fix correctly yields no diff.
- **Nothing was deployed.** This plan is entirely config-layer. `services.mealie` and `services.postgresql` exist only in the evaluated closure; no host was activated, no PostgreSQL data directory was created or touched, and the prohibition on destroying pre-existing `/persist/var/lib/postgresql` data is untested because nothing ran against a host. Plan 10-04 owns first activation and the blocking pre-flight check.

## User Setup Required

None - no external service configuration required. (`user_setup: []` in the plan frontmatter.)

## Next Phase Readiness

**Ready.** The Phase 10 configuration surface exists, evaluates on all four hosts, and is defended offline.

Carried forward to later plans in this phase:

- **10-04 (first activation)** inherits the one-way commitments encoded here. Its pre-flight must confirm no pre-existing PostgreSQL major sits under `/persist/var/lib/postgresql` before activating, and must verify `stat -c '%U %G %a'` returns `postgres postgres 750` on all three of `/var/lib/postgresql`, `/var/lib/postgresql/17`, and `/persist/var/lib/postgresql`.
- **10-05 (tsnet endpoint)** proves reachability, which this plan explicitly does not claim. Assumption A5 — that a new tsnet node needs no Tailscale admin-console or ACL action — is still unproven.
- **MEAL-03 is complete at the config layer only.** `BASE_URL`, the forwarded-header trust list, the firewall port, and the Caddy listener are all asserted; that the endpoint answers is a later plan's claim.
- **Phase 11 backups** can now address `/var/lib/mealie` as a real directory owned by a real user, which was the practical reason for PD-01.
- **D-07 remains load-bearing:** `unstable.mealie` must not move before Phase 11 backups exist. Beyond the Alembic-migration reason, the package's launch line hard-codes the deprecated `uvicorn.workers` import, which fails at runtime rather than at eval — so a future bump needs `systemctl is-active mealie` on a real activation, not just a green build.

## Self-Check: PASSED

All six created files verified present on disk with `[ -f ]`. All three commit hashes (`af31df3`, `714d71f`, `ae52a9b`) verified present in `git log --oneline --all`. All Task 1 and Task 2 acceptance criteria re-run and passing; Task 3 criteria passing with the warning inventory documented above per the criterion's own escape clause.

---
*Phase: 10-household-foundation-and-mealie*
*Completed: 2026-08-18*
