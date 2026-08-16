---
phase: 10-household-foundation-and-mealie
plan: 03
subsystem: smoketests
tags: [smoketests, mealie, postgresql, impermanence, tailscale, household]
status: complete

requires:
  - "hosts/ser8/household/mealie.nix (plan 10-01) — the settings values these tests assert at runtime"
  - "hosts/ser8/household/postgresql.nix (plan 10-01) — the postgresql_17 pin the major check asserts"
  - "hosts/ser8/impermanence.nix (plan 10-01) — the persisted directories the ownership checks inspect"
  - "scripts/smoketests/lib/fanout.sh (Phase 9 D-11) — run_suite, reused rather than reinvented"
provides:
  - "scripts/smoketests/household/ — the household smoketest area, reachable from deploy.yaml through the ser8 fan-out"
  - "A deploy-time gate for Mealie that exists before Mealie is deployed"
  - "mealie in the gateway suite EXPECTED_NODES — DNS, HTTPS, and TLS coverage for the tsnet node"
affects:
  - "plan 10-04 — activates ser8 and is judged by this suite; confirms the A3 table names against the live schema"
  - "plan 10-06 — nothing sets MEALIE_ALLOW_UNSEEDED from this point on, so the seeded-data checks assert permanently"
  - "Phase 11 backup work — the state-directory shape assertion is what catches state landing in the private tree"

tech-stack:
  added: []
  patterns:
    - "run_suite fan-out for a new smoketest area (Phase 9 D-11), array append rather than a second dispatch layer"
    - "printf %q escaping on every ssh probe, with the justified shellcheck disable=SC2029 comment"
    - "to_regclass name resolution before querying an unconfirmed table (PD-04)"
    - "assertions on by default with an uncommitted, command-line-only escape hatch (PD-03)"

key-files:
  created:
    - scripts/smoketests/household/all.sh
    - scripts/smoketests/household/test-mealie-service.sh
    - scripts/smoketests/household/test-mealie-endpoint.sh
  modified:
    - scripts/smoketests/ser8/all.sh
    - scripts/smoketests/gateway/test-tailscale.sh

decisions:
  - "Three near-identical table checks collapsed into one shared assert_table_non_empty helper rather than three copies; to_regclass resolution lives in one place and is applied to all three tables."
  - "Port liveness probed by opening a TCP connection from the host's own bash rather than through ss, netstat, or lsof — none of those is guaranteed to be in the closure, and a check that skips when its tool is missing certifies nothing."
  - "The tsnet DNS and HTTPS probes run from firebat, resolved through deploy.yaml as GATEWAY_HOST, because MagicDNS answers for tailnet members only."
  - "A connection failure on the default-credential probe is a test failure, not a pass: a down service rejects those credentials too."
  - "scripts/smoketests/gateway/test-tailscale.sh keeps its 2-space indentation; the one-line append matches the file rather than importing tab style into it."

metrics:
  duration: 8 min
  completed: 2026-08-18

actuals:
  tokens: 8500
  tasks: 3
  commits: 3
---

# Phase 10 Plan 03: Household Smoketest Area Summary

A household smoketest area now gates Mealie on every ser8 activation, written before Mealie is deployed, asserting both of Mealie's independent state stores rather than only the database.

## What Was Built

`scripts/smoketests/household/` is a new smoketest area reachable from `deploy.yaml` through the existing ser8 fan-out.
It holds an entry point and two tests, and `deploy.yaml` itself is unchanged because its ser8 entry already resolves through `scripts/smoketests/ser8/all.sh`.

**`all.sh`** declares `SUITE_NAME="household"` and a two-entry `TESTS` array, then calls `run_suite "$@"`.
The header names what the area covers and where the Homebox, Actual, and Donetick checks belong in Phases 12-13, so the next person adding a household service does not add it to the ser8 array instead.

**`test-mealie-service.sh`** registers twelve subtests against ser8, grouped into service, PostgreSQL, state-directory, seeded-data, and persistence sections:

| Group | Asserts |
|---|---|
| Service | unit active; port 9000 bound; no error-priority journal entries in the current boot |
| PostgreSQL | the `mealie` database answers over the socket; `server_version` is the 17 series; `/var/lib/postgresql/17` is `postgres:postgres` mode `750` |
| State directory | `/var/lib/mealie` is a real directory, not a symlink, owned `mealie:mealie`; `/persist/var/lib/mealie` exists and is owned `mealie:mealie` |
| Seeded data | `ingredient_foods` and `ingredient_units` each hold rows |
| Persistence | `recipes` holds rows AND the persisted recipe image tree holds files |

The persistence group is the reason the plan earned its own slot.
Mealie writes images, uploads, and the session-signing secret to `DATA_DIR` on disk, not into PostgreSQL, so a check that counts rows alone is green while every thumbnail is broken and every household member has been logged out.
Both stores are asserted as separate named subtests.

The journal check is scoped to the current boot because Mealie runs Alembic migrations as an `ExecStartPre` on every start, and a failed migration leaves the unit looking healthy on the next restart.

**`test-mealie-endpoint.sh`** registers seven subtests covering what a homepage load cannot see: the loopback port answers; the deployed `BASE_URL` equals the tsnet URL; the deployed `BASE_URL` is separately asserted not to be the module's `http://localhost:9000` default; `ALLOW_SIGNUP` is present, non-empty, and the string `false`; a token request with Mealie's shipped `changeme@example.com` / `MyPassword` does not return 200; and the tsnet name resolves and answers over HTTPS from firebat.

Both settings assertions read `systemctl show mealie --property=Environment`, so they judge what the service actually runs with rather than what the flake evaluates to.
`ALLOW_SIGNUP` is checked for presence and emptiness separately from its value, because an empty string is the exact footprint of a Nix boolean that stringified away — the trap plan 10-01's eval gate catches at build time and this catches after a hand edit.

**`scripts/smoketests/gateway/test-tailscale.sh`** gains `mealie` in `EXPECTED_NODES`, one added line, which buys DNS, HTTPS, and TLS-expiry coverage from the existing gateway suite.

## PD-03: the escape hatch

The seeded-data and persistence assertions are unconditional by default.
`MEALIE_ALLOW_UNSEEDED=1` downgrades them to informational output for the single pre-bootstrap run in plan 10-04, before any Food, Unit, recipe, or image exists.
The file header states that nothing committed to the repository may set it and that putting it in `deploy.yaml` or a suite entry point would turn a real gate into an always-passing one.
`git grep` confirms the variable appears in exactly one tracked file: the test that reads it.

Table-existence failures are deliberately **not** gated by the escape hatch.
Alembic creates the schema on first start, so a missing table is a real failure even pre-bootstrap.

## Deviations from Plan

### 1. `to_regclass` appears once, not twice (acceptance criterion not met literally)

- **Found during:** Task 2
- **Criterion:** `grep -v '^#' test-mealie-service.sh | grep -c 'to_regclass'` returns at least 2
- **Actual:** returns 1
- **Why:** The Foods, Units, and recipes checks differed only in table name and metric key. Writing three copies of the resolve-then-count sequence would have duplicated ~60 lines to satisfy a grep. They share one `assert_table_non_empty` helper instead, and `mealie_table_exists` resolves every one of the three names through `to_regclass` before it is queried. CLAUDE.md's own rule — abstract once the same code is written three times — points the same way.
- **Intent satisfied:** PD-04 asks that a wrong table name produce a named failure rather than a psql error. All three tables get that, from one place.
- **Files modified:** `scripts/smoketests/household/test-mealie-service.sh`
- **Commit:** b6a8d49

### 2. `shfmt -d` invocation differs per file (acceptance criterion met per file, not under one command)

- **Found during:** Task 3
- **Criterion:** `shfmt -d ... test-tailscale.sh` produces no diff
- **Actual:** `shfmt -d` with its default tab indent rewrites the whole of `test-tailscale.sh`. That file is 2-space indented and was already non-conforming under default `shfmt` before this plan touched it — verified by running `shfmt -d` against `git show HEAD:...` of the pre-change file.
- **Why:** The plan explicitly instructs keeping that file's 2-space indentation rather than importing tab style, and the acceptance criterion `git diff --numstat` shows exactly one added line. Reformatting the file would satisfy one criterion by violating two others.
- **Resolution:** Each file is clean under the invocation matching its own established style. `shfmt -i 2 -d test-tailscale.sh` is clean both before and after the change; `shfmt -d` (tabs) is clean on all three new files and on `ser8/all.sh`.
- **Files modified:** none beyond the one-line append
- **Commit:** d1596f4

### 3. `# shellcheck source=` annotation added to both new test scripts

- **Found during:** Task 2
- **Issue:** `test-home-assistant.sh`, the structural model, sources `scripts/lib/all.sh` without a `source=` directive, so plain `shellcheck` emits SC1091.
- **Fix:** Added the directive already used by every suite entry point in the repository. Both new tests are clean under `shellcheck -x`, which is the invocation the repository's `# shellcheck source=` annotations are written for.
- **Files modified:** `test-mealie-service.sh`, `test-mealie-endpoint.sh`
- **Commits:** b6a8d49, d1596f4

### 4. Two helpers added beyond the model file's shape

- **Found during:** Task 2
- **Issue:** `test-home-assistant.sh` inlines the printf-%q-escaped `ssh` block once for its exit-status probe. Six subtests here need exit status rather than stdout.
- **Fix:** Added `remote_ok` alongside `remote`, using the identical `printf %q` escaping and the same justified `shellcheck disable=SC2029` comment. `test-mealie-endpoint.sh` similarly adds `remote_gateway` for the firebat-side probes. T-10-13's mitigation (no unescaped probe argument reaches a remote shell) holds for every probe in both files.
- **Files modified:** both new test scripts
- **Commits:** b6a8d49, d1596f4

## Verification

All run from the development shell.

| Check | Result |
|---|---|
| `shellcheck -x` on all five files | clean, no output |
| `shfmt -d` on the three new scripts and `ser8/all.sh` | no diff |
| `shfmt -i 2 -d scripts/smoketests/gateway/test-tailscale.sh` | no diff |
| `bash -n` on all three new scripts | exits 0 |
| both test scripts with no argument | usage line, exit 1 |
| `grep -c 'household/all.sh' scripts/smoketests/ser8/all.sh` | 1 |
| `grep -c '"mealie"' scripts/smoketests/gateway/test-tailscale.sh` | 1 |
| `git diff --numstat` on `test-tailscale.sh` | `1 0` — exactly one added line |
| `git diff --stat -- deploy.yaml` | empty |
| `SKIP_VOFI_DNS:-1` in `lib/services.sh` and `gateway/test-caddy.sh` | 1 each, unchanged (D-03) |
| `git grep -l MEALIE_ALLOW_UNSEEDED` outside `.planning/` | one file, the test that reads it |
| `grep -rn '192\.168\.' scripts/smoketests/household/` | 0 — every address comes from `deploy.yaml` |
| `grep -c 'vofi'` in the endpoint test | 0 (D-02) |

Not run: the suites themselves. Every subtest requires a live ser8 with Mealie deployed, which is plan 10-04's job. This plan's gate is static analysis, which is what allowed the checks to be written before the thing they check.

## Known Stubs

None. Every subtest asserts unconditionally by default; the only conditional path is the documented `MEALIE_ALLOW_UNSEEDED` downgrade, which no committed file sets.

## Carried Forward to Plan 10-04

1. **Table names are still assumptions.** `ingredient_foods`, `ingredient_units`, and `recipes` come from RESEARCH.md A3. Confirm each against the live schema and correct `FOODS_TABLE`, `UNITS_TABLE`, and `RECIPES_TABLE` if a guess was wrong. A wrong guess reports a named failure naming the table, not a psql error.
2. **The recipe image path is an assumption.** `MEALIE_PERSIST_RECIPE_DIR` is `/persist/var/lib/mealie/recipes`. Confirm the actual layout under `DATA_DIR` once Mealie has written its first image.
3. **`MEALIE_ALLOW_UNSEEDED=1` is for one run only**, passed on the command line for the pre-bootstrap activation. Do not commit it anywhere.
4. **`sudo` over ssh** is required by the PostgreSQL ownership, `psql`, and image-tree probes. If passwordless sudo is not configured for the deploy user on ser8, those subtests report failures that are about sudo rather than about Mealie.

## Threat Flags

None. This plan adds no network endpoint, auth path, or schema; it adds read-only probes across the developer-machine-to-host ssh boundary already used by every other suite.

## Self-Check: PASSED

Files verified present on disk:

- `scripts/smoketests/household/all.sh` — FOUND, executable
- `scripts/smoketests/household/test-mealie-service.sh` — FOUND, executable
- `scripts/smoketests/household/test-mealie-endpoint.sh` — FOUND, executable

Commits verified in `git log`:

- `7f82cba` — FOUND
- `b6a8d49` — FOUND
- `d1596f4` — FOUND
