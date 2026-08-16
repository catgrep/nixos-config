---
phase: 10-household-foundation-and-mealie
plan: 06
subsystem: infra
tags: [mealie, household, bootstrap, postgresql, shopping-lists, meal-04, meal-02, smoketests]
status: complete

requires:
  - "ser8 running Mealie 3.22.0 against pinned PostgreSQL 17 as boot default (plan 10-04) — the instance bootstrapped here"
  - "firebat serving https://mealie.shad-bangus.ts.net with a trusted certificate (plan 10-05) — the browser path every operator step used"
  - "scripts/smoketests/household/ (plan 10-03) — the gate written before any of its subject existed"
  - "10-04-SUMMARY.md confirmed table names ingredient_foods / ingredient_units — the seeded-data assertions query these"
provides:
  - "A Mealie instance in daily household condition: two accounts, one household, seeded reference data, dead shipped-default credentials, registration closed by configuration"
  - "Bidirectional proof that a shopping list created by either member is returned to the other by Mealie's own executed query path"
  - "A corrected model of Mealie 3.22.0 shopping-list scoping that replaces RESEARCH.md Pitfall 8"
  - "The answer to RESEARCH.md Open Question 4 (administrator-created accounts work with signup closed), inferred from the database rather than operator-attested"
  - "Four evidence records under baseline/ that separate what the instance can be shown to have done from what was reported"
  - "A post-bootstrap ser8 transcript for per-area comparison against the 10-04 baseline"
affects:
  - "plan 10-07 — its two-reboot persistence proof has no subject: the one recipe is named test with a null image and the persisted image tree holds zero files"
  - "phase 12 Homebox bootstrap — inherits the Open Question 4 answer, and must NOT inherit a seeding UI path, which was never recorded"
  - "phase 14 SEC-02 — both accounts carry admin=true, an unplanned privilege this plan recorded rather than changed"
  - "verify-work / UAT — the end-user two-profile UI rendering confirmation is deferred here with its exact remaining probe"

actuals:
  tokens: 21000
  tasks: 3
  commits: 5

tech-stack:
  added: []
  patterns:
    - "Corroborate a human checkpoint against the service's own request log, not just against the database: a database alone cannot distinguish 'never happened' from 'happened and was undone'"
    - "When a reconstructed SQL predicate and an operator observation disagree, execute the shipped application code against live data rather than reasoning further about either"
    - "Identify which account a session belongs to from avatar fetches and self-referential queryFilter values in an access log that records no user"

key-files:
  created:
    - .planning/phases/10-household-foundation-and-mealie/baseline/bootstrap-evidence-2026-08-19.md
    - .planning/phases/10-household-foundation-and-mealie/baseline/shared-list-and-gate-evidence-2026-08-19.md
    - .planning/phases/10-household-foundation-and-mealie/baseline/shared-list-visibility-diagnosis-2026-08-19.md
    - .planning/phases/10-household-foundation-and-mealie/baseline/smoketests-household-post-bootstrap.txt
    - .planning/phases/10-household-foundation-and-mealie/baseline/smoketests-household-final-2026-08-20.txt
    - .planning/phases/10-household-foundation-and-mealie/baseline/smoketests-ser8-final-2026-08-20.txt
  modified: []

key-decisions:
  - "The `mealie_recipe_images_present` gate was NOT weakened, skipped, or given an escape hatch. It is red because the fact it asserts is false, which is the subtest working. Plan 10-07 inherits it as a known-red carried item."
  - "No Mealie data was changed to make an acceptance criterion pass. Moving an account between households or recreating a list would have been a change against a cause the code and the data both contradict, and would have destroyed the evidence."
  - "Two operator UI reports were recorded as contradicted rather than accepted or quietly dropped, because the request log refutes both and the phase cannot close on a report the instance disagrees with."
  - "The shopping-list count criterion is recorded as literally UNMET (the count is 2, not 1) even though the failure mode it guards against is absent. Rewriting the criterion to match the outcome would have destroyed its meaning."
  - "The plan's `must_haves` truth that a fresh bootstrap has exactly one shopping list is recorded as REFUTED rather than reinterpreted. Mealie 3.22.0 creates none."

patterns-established:
  - "A human-verify checkpoint is a claim, not a result. Author every one of them with an independent mechanical corroboration, and record the disagreement when the two differ."
  - "An access log that records no user identity can still be attributed: avatar fetches and self-referential filter parameters carry the user id."

metrics:
  duration: "3 sessions across 2026-08-19 and 2026-08-20"
  completed: 2026-08-20
---

# Phase 10 Plan 06: Bootstrap Mealie into Household Condition Summary

Mealie now holds two accounts in one household with seeded reference data, dead shipped-default credentials, and a registration control that provably lives in configuration; the shared-list requirement is proven bidirectionally through Mealie's own executed query path, while the end-user UI confirmation and the recipe-image persistence subject are carried forward as documented gaps.

## Performance

| Metric | Value |
|---|---|
| Tasks | 3 of 3 |
| Commits | 5 |
| Repository files changed | 0 (this plan changes no repository file, as planned) |
| Evidence records produced | 6 under `baseline/` |
| Checkpoint rounds | 4 (Task 1, Task 2, and two diagnosis rounds) |

## Accomplishments

- Both household member accounts exist and both are in the household `Family` under the group `Home`, verified against the foreign keys rather than a rendered page.
- The shipped default administrator credentials are provably dead: `POST /api/auth/token` on the loopback port with `changeme@example.com` / `MyPassword` returns **HTTP 401**, and the service log records the rejection as `Incorrect username or password`, distinguishing a live service refusing a credential from silence from a dead one.
- Reference data seeded exactly once: `ingredient_foods=2687`, `ingredient_units=24`, `multi_purpose_labels=32`, with zero duplicate `(name, group_id)` pairs.
- `ALLOW_SIGNUP` holds the non-empty string `false` in the deployed unit environment, not the empty value a Nix boolean would leave behind. The registration control provably exists.
- Cross-member shopping-list visibility proven bidirectionally by executing Mealie's own `page_all` against live data (below).
- Four of the five household subtests plan 10-05 carried forward as expected failures are now green.
- RESEARCH.md Pitfall 8's model of shopping-list scoping was found wrong and is corrected here.

## Task Commits

| Task | Name | Commit | Artifact |
|---|---|---|---|
| 1 | Bootstrap accounts, credentials, reference data | `53af32e` | `baseline/bootstrap-evidence-2026-08-19.md` |
| 2 | Confirm both members share one shopping list (round 0) | `2a3a56f` | `baseline/shared-list-and-gate-evidence-2026-08-19.md` |
| 2 | Shared-list diagnosis, round 1 | `7de2115` | `baseline/shared-list-visibility-diagnosis-2026-08-19.md` |
| 2 | Shared-list diagnosis, round 2 | `ea2108d` | same file, amended |
| 3 | Close the household gate | this commit | `baseline/smoketests-{household,ser8}-final-2026-08-20.txt` |

## MEAL-04: what is verified, and what is not

This is the requirement the plan exists to protect, and it went through four rounds. The evidence is separated below by how strongly it is held.

### VERIFIED — the server path, bidirectionally

Mealie's own `page_all` was executed read-only against the live database, under the `mealie` service account, with the same interpreter and the same `PYTHONPATH` the running gunicorn workers carry, instantiating `AllRepositories` with each user's real `group_id` and `household_id` exactly as `routes/_base/base_controllers.py` does:

```
--- list creators (ground truth) ---
    'testie'      created_by=admin
    'trader joes' created_by=vodh
--- executed page_all, per requesting user ---
    as admin: total=2  items=['testie (by admin)', 'trader joes (by vodh)']
    as vodh:  total=2  items=['testie (by admin)', 'trader joes (by vodh)']
```

Each member receives the list created by the other. This is stronger than the round-2 result, which had only one list created by one account and so could only show symmetry, not exchange. Two lists with two different creators make the property observable in both directions at once.

Three independent lines support it:

1. **The shipped source carries no user-scoped predicate.** `_filter_builder` in `repos/repository_generic.py` only ever emits `group_id` and `household_id`. `RepositoryShoppingList` overrides `update` only, adding nothing to reads. No `queryFilter` was attached by the frontend on any shopping-list index request in the instance's entire history.
2. **The compiled SQL names only group and household.** The `household_id` association proxy resolves to an `EXISTS` subquery over `users`; the requesting user's id appears nowhere in the statement. Both accounts carry byte-identical `group_id` and `household_id`, so the endpoint is symmetric in them by construction.
3. **Executed, not reconstructed** — the block above.

### STRENGTHENED but NOT operator-attested — the browser

The request log for 2026-08-20 19:39 shows something the earlier rounds never had: **two concurrently live authenticated sessions belonging to different accounts.**

- No `POST /api/auth/token` and no `/api/auth/logout` appears anywhere between 19:10 and 19:45. Neither session logged in or out during the window, so both held pre-existing tokens simultaneously. That is the two-separate-sessions condition Task 2 step 4 asks for, and it is the condition every earlier attempt failed to meet.
- Avatars were fetched for **both** user ids six seconds apart: `a4b5728b` (`admin`) at 19:39:12 and `a971ed52` (`vodh`) at 19:39:18. A third fetch of `a971ed52` follows at 19:40:03.
- At 19:39:44 a request carries `queryFilter=favoritedBy.id = "a4b5728b-..."`, which the frontend builds from the logged-in user, independently confirming a live `admin` session.
- Both list-detail endpoints returned **200**, repeatedly and interleaved: `8d207a6a` (`testie`, created by `admin`) at 19:39:14, :19, :34, :39, and `9ba5a502` (`trader joes`, created by `vodh`) at 19:39:10 and :15.

**The limit, stated plainly:** all browser traffic originates from a single tailnet address and the access log records no user per request, so which of the two sessions issued which detail fetch cannot be pinned from the log. The window is consistent with each member opening the other's list, and it is also consistent with one session opening both. This is recorded as corroboration, not as the direct observation.

### UNRESOLVED — deferred by the operator

A direct end-user confirmation that the list *renders* in a second browser profile was not obtained. The operator declined the final verification and directed the plan closed as-is.

The exact remaining probe, carried to verify-work / UAT:

1. On ser8 over SSH, as household member `vodh`, run the loopback `curl` against `http://127.0.0.1:9000/api/households/shopping/lists?page=1&perPage=-1&orderBy=name&orderDirection=asc` with a token minted by `read -s` (never echoed, never on the command line). Report only `total` and the list names. This removes Caddy, tailscale, the browser, the service worker, and the frontend from the loop.
2. In each browser profile: devtools, Application, Service Workers, unregister the Mealie worker; then Storage, Clear site data; then hard-reload. Mealie 3.22.0 ships a PWA service worker (`GET /sw.js` appears on a two-minute cadence throughout the log) and it is the only component left between a correct API response and a blank page.
3. Re-run Task 2 steps 1 to 6 with the two accounts in genuinely separate profiles, recording the **full request URL** next to the `total` value so a misread row is self-evident.

**The service-worker staleness hypothesis is the remaining unproven client-side explanation** for the original blank page. It is a hypothesis, not a finding.

### The two operator reports the instance contradicts

Recorded because dropping them would hide a real disagreement between what was reported and what happened.

| Report | What the instance says |
|---|---|
| Task 2 resolved `Approved - duplicate merged` | At that moment `shopping_lists` and `shopping_list_items` both held **zero** rows, and across 739 logged requests there was no `POST` creating a list, no item write, and no `DELETE`. No list existed to merge into. The observation cannot have been made against this instance. |
| Round-1 probe reported `total: 0` | The probe window contains a `404` on `GET /shopping-lists//api/households/shopping/lists` (a malformed relative URL) and a `401` on the bare API URL opened without a token. Neither response body carries a `total` field. The `200` response at 00:10:50 was the shopping-list index, and three independent proofs say it carried `total: 1`. |

Neither report is discarded and neither is accepted. Both are recorded alongside the contradicting evidence.

## Corrections to the phase's research

### RESEARCH.md Pitfall 8 is wrong about the mechanism

The phase assumed `shopping_lists` carries a `household_id` column. **It does not.** The deployed schema is:

```
shopping_lists: created_at, update_at, id, group_id (NOT NULL, FK groups),
                name, user_id (NOT NULL, FK users)
```

`household_id` is a derived ORM attribute in `db/models/household/shopping_list.py`:

```python
household_id: AssociationProxy[GUID] = association_proxy("user", "household_id")
```

**A shopping list's household is whatever household its creator is in, read live through `user_id`.** It is not stored, so it follows the creator if the creator is ever moved. And `user_id` records who created the list; it never restricts who may read it — there is no per-user ownership filter on shopping lists at all.

The phase's `key_links` entry is right that the household placement is load-bearing, but right for a different mechanical reason than assumed. Phase 12 must not inherit the column-based model.

### Mealie 3.22.0 does not auto-create a shopping list

`shopping_lists` held zero rows after bootstrap, with `to_regclass('public.shopping_lists')` non-null, so this was a genuinely empty table and not a wrong table name.

This **refutes as written** the plan's `must_haves` truth:

> A freshly bootstrapped Mealie has exactly one shopping list visible to both members and renders without error while that list is empty (MEAL-04, empty-input edge).

The empty-input edge sits one level further out than the plan reasoned: the empty case is **zero lists**, not one empty list. An empty Shopping Lists page on a fresh instance is the documented starting state, not a defect.

### Open Question 4, answered — but inferred

**Administrator-created accounts do work with signup closed. Status: inferred from the database and the request log, NOT operator-attested.**

`ALLOW_SIGNUP=false` has been in the deployed unit environment since first boot (D-09) and is still there. A second account nevertheless exists, and the log carries `POST /api/admin/users` returning **409** at 23:45:54 (a name conflict on the first attempt) then **201** at 23:46:05. Self-service registration was never open in that window, so an administrator created the account with signup closed. The reserve fallback — a deliberate two-deploy reopen-and-close sequence — was not needed and was not used.

Phase 12's Homebox bootstrap has the identical shape and inherits this answer, with the caveat that it is inferred here rather than observed.

### The seeding interface path was NOT recorded

The operator did not report it. The database proves a seed happened and happened exactly once; it cannot say which control was clicked.

**RESEARCH.md Assumption A4** — that seeding in 3.22.0 is still a Manage Data button with a language picker — is therefore **neither confirmed nor refuted**. Phase 12's bootstrap instructions must not be written as though it were confirmed. Inventing a plausible path here would be a fabricated observation.

### Account names are inverted relative to the operator's mental model

| Username | Created | What it actually is |
|---|---|---|
| `vodh` | 2026-08-18 18:50:52 UTC | the **original** administrator from first boot, later renamed |
| `admin` | 2026-08-19 06:46:05 UTC | the **second** household member, created through the admin area |

`vodh`'s row was created in the same second as the `Family` household. `admin`'s creation timestamp matches the `POST /api/admin/users` 201 exactly. Any remedial action taken against "the admin account" would hit the wrong one.

### Both accounts carry site-administrator rights

| Username | `admin` | `can_manage` | `can_manage_household` | `advanced` |
|---|---|---|---|---|
| `vodh` | true | true | true | true |
| `admin` | true | true | true | true |

The plan neither asked for nor forbade this. The second member does not need site-administrator rights to share a shopping list, and MEAL-02's posture is weakened by granting them. **Recorded, not changed** — no data was modified by this plan. Worth resolving before Phase 14's SEC-02 audits privilege.

## Task 3: database counts

Queried directly over the postgres socket, 2026-08-20.

| Table | Count | Note |
|---|---|---|
| `groups` | 1 | |
| `households` | **1** | MEAL-04's shape; both members belong to it |
| `users` | 2 | |
| `ingredient_foods` | **2687** | > 0, criterion met |
| `ingredient_units` | **24** | > 0, criterion met |
| `multi_purpose_labels` | 32 | |
| `shopping_lists` | **2** | criterion said 1 — see below |
| `shopping_list_items` | 2 | both on `testie`, two different foods |
| `recipes` | 1 | `name=test`, `slug=test`, `image=<null>` |
| `long_live_tokens` | 0 | no API token exists, so no unattended authenticated probe is possible without a household password |

Household membership, read from the foreign keys:

```
vodh  | admin=true | group=Home | household=Family
admin | admin=true | group=Home | household=Family
```

## Task 3: the household gate, run unaided

`env | grep -c MEALIE_ALLOW_UNSEEDED` returned **0** in the shell that ran the suite. No escape-hatch variable was set on the command line, exported into the environment, or written to a file.

`./scripts/smoketests/household/all.sh ser8` exits **1**.

| Subtest | Plan 10-05 state | Now |
|---|---|---|
| `mealie_foods_seeded` | red | **green** — 2687 rows |
| `mealie_units_seeded` | red | **green** — 24 rows |
| `mealie_recipes_present` | red | **green** — 1 row |
| `mealie_recipe_images_present` | red | **still red** — the image tree holds zero files |
| `default_admin_rejected` | red | **green** — HTTP 401 |

`test-mealie-service.sh`: **11/12**, up from 8/12 at the 10-04 baseline.
`test-mealie-endpoint.sh`: **7/7**, up from 4/7 at the 10-04 baseline.
Household suite: **1/2**, up from 0/2. Nothing that was passing has started failing.

Full transcript: `baseline/smoketests-household-final-2026-08-20.txt`.

## Task 3: security outcomes confirmed independently of the suite

Per the plan's instruction not to trust only a script written in the same phase.

| Check | Result |
|---|---|
| `POST /api/auth/token` on `127.0.0.1:9000` with the shipped defaults | **HTTP 401** |
| Server-side view of that probe | `[ERROR\|auth\|L82] Incorrect username or password from 127.0.0.1` |
| `systemctl show mealie -p Environment` | `ALLOW_SIGNUP=false` |
| Explicit emptiness test on that value | non-empty: `[false]` |

The log line matters more than the status code: it is the service actively rejecting a credential, which is exactly what the subtest's own comment says must be distinguished from a connection failure against a dead service. Threat **T-10-02** is closed.

The emptiness test is the guard against a Nix boolean surviving the module's stringification and leaving `ALLOW_SIGNUP=` — which would mean the registration control silently does not exist. It does exist. Threat **T-10-01** is closed.

## Task 3: full ser8 suite, per-area against the 10-04 baseline

The gate is per-area equality plus a green household area, not a zero top-level status — the top-level status cannot reach 0 while the pre-existing NordVPN tunnel failure this phase does not own persists.

| Area | 10-04 baseline | Now |
|---|---|---|
| media services | pass | pass |
| **household** | **FAIL** (0/2) | **FAIL** (1/2) |
| qBittorrent confinement | pass (3/3) | pass (3/3) |
| **nordvpn** | **FAIL** (3/4, `test-forwarding.sh`) | **FAIL** (3/4, `test-forwarding.sh`) — unchanged, not owned by this phase |
| ZFS health | pass (7/7) | pass (7/7) |
| VAAPI | pass (5/5) | pass (5/5) |
| Frigate | pass (5/5) | pass (5/5) |
| Home Assistant | pass (3/3) | pass (3/3) |
| **ser8 total** | 5/7 | 5/7 |

The failing set is identical to the baseline. No area regressed. The household area improved but is not green.

Full transcript: `baseline/smoketests-ser8-final-2026-08-20.txt`.

## Acceptance criteria: honest status

| Criterion | Status |
|---|---|
| household area exits 0 with no escape hatch | **UNMET** — exits 1 on one subtest |
| `env \| grep -c MEALIE_ALLOW_UNSEEDED` returns 0 | **MET** |
| exactly the 10-05 expected failures turned green, no new failures | **PARTIAL** — four of five turned green, none regressed |
| default admin token request returns other than 200 | **MET** — 401 |
| `ALLOW_SIGNUP` non-empty string in the deployed environment | **MET** — `false` |
| Foods and Units counts > 0, recorded | **MET** — 2687 and 24 |
| household count is 1, both members belong to it | **MET** |
| shopping list count is 1 | **UNMET as written** — the count is 2 |
| one recipe with an uploaded image, title and filename recorded | **UNMET** — one recipe named `test`, image null, zero files in the tree |
| post-bootstrap ser8 transcript matches baseline per area | **MET** — identical failing set |
| no password in the SUMMARY or any committed file | **MET** |

### On the shopping-list count

The criterion exists to catch one specific failure: two households or two lists meaning two people are not actually sharing. That failure is **absent**. There is one household, both lists sit in it, and Mealie's own executed query returns both lists to both members.

What happened instead is that the household made a second list for a different shop (`trader joes`, created by `vodh` on 2026-08-19 at 21:25:08 UTC). Two lists in one household, mutually visible, is a working household — it is simply not the number the criterion names.

The criterion is recorded as **literally unmet** rather than rewritten to match the outcome. Rewriting an acceptance criterion after seeing the result destroys its meaning, and a later reader deserves to see that the number moved and why.

## Backstop truths: not observed

Both are recorded as unobserved. The phase required them observed, not answered a particular way — and they were not observed.

**Duplicate-item behaviour (Task 2 step 7): NOT OBSERVED.** `shopping_list_items` holds two rows on `testie` with two **different** `food_id` values (`chutney` quantity 1, `achiote oil` quantity 0). No food was ever added twice, so the merge-or-append question was never exercised against this instance. The `duplicate merged` report in the Task 2 resume signal was made at a time when no list and no item existed.

**Ordering observation (Task 2 step 8): NOT RECORDED.** The operator supplied no detail in either round.

The `must_haves` truth that *no phase acceptance check asserts relative display order* **holds** — no such check exists anywhere in the suite. It is the observation, not the truth, that is missing.

## Files Created/Modified

**Repository files changed: none.** This plan changes no repository file, as its frontmatter declares.

Created under `.planning/phases/10-household-foundation-and-mealie/baseline/`:

- `bootstrap-evidence-2026-08-19.md` — Task 1 corroboration
- `shared-list-and-gate-evidence-2026-08-19.md` — Task 2 round 0, and the first contradiction
- `shared-list-visibility-diagnosis-2026-08-19.md` — diagnosis rounds 1 and 2
- `smoketests-household-post-bootstrap.txt`
- `smoketests-household-final-2026-08-20.txt`
- `smoketests-ser8-final-2026-08-20.txt`

## Deviations from Plan

### Auto-fixed Issues

None. This plan modifies no code, so there was nothing to auto-fix. Every discrepancy found was recorded rather than repaired, deliberately — see Decisions.

### Plan assumptions found false during execution

**1. [Finding] `shopping_lists` has no `household_id` column**
- **Found during:** Task 2 diagnosis round 1
- **Issue:** RESEARCH.md Pitfall 8's model was mechanically wrong
- **Resolution:** corrected in this SUMMARY and in the diagnosis record; no code change, the phase's conclusion is unaffected
- **Commit:** `7de2115`

**2. [Finding] Mealie 3.22.0 auto-creates no shopping list**
- **Found during:** Task 1 corroboration
- **Issue:** a `must_haves` truth is refuted as written
- **Resolution:** recorded as refuted; carried into the Task 2 checkpoint so an empty Shopping Lists page would not be misread as a defect
- **Commit:** `53af32e`

**3. [Finding] Two operator UI reports contradicted by the request log**
- **Found during:** Task 2 rounds 0 and 2
- **Issue:** the reported observations could not have been made against this instance
- **Resolution:** both recorded alongside the contradicting evidence; neither accepted, neither discarded
- **Commits:** `2a3a56f`, `ea2108d`

## Issues Encountered

**`mealie_recipe_images_present` is red and stays red.** The one recipe is named `test` with a null image, and `find -type f` under `/persist/var/lib/mealie/recipes` returns zero files. The subtest exists precisely because Mealie's images never enter PostgreSQL, so a green recipe row count says nothing about whether image bytes survive. It is doing its job. It was not weakened, skipped, or given an escape hatch.

**Plan 10-07 has no subject.** Its two-reboot persistence proof needs a real recipe the household would keep, carrying a real uploaded image rather than a scraped URL. What exists is throwaway test data with no image at all. The 15 recurring 404s in the log are the frontend asking for that missing image on every recipe-page load.

**No Mealie API token exists** (`long_live_tokens=0`), so no authenticated end-to-end request can be made without a household password. This is why the remaining decisive probe is written for the operator to run rather than performed here.

## User Setup Required

Carried to verify-work / UAT:

1. **The loopback probe and two-profile retest** described under "UNRESOLVED" above. Read-only, under a minute for step 1.
2. **Create a real recipe with an uploaded image** as a household member, before plan 10-07 runs. Record its title and image filename so 10-07 can look for the same bytes.
3. **Optional, before Phase 14:** decide whether the second member should keep site-administrator rights.

## Next Phase Readiness

| Item | State |
|---|---|
| MEAL-02 (dead defaults, closed registration, two accounts) | **satisfied** |
| MEAL-04 server-side truth | **verified bidirectionally** |
| MEAL-04 end-user UI rendering | **deferred** — probe documented above |
| Household smoketest area green unaided | **not achieved** — one red subtest |
| Plan 10-07 persistence subject | **absent** — blocks a meaningful reboot drill until a real recipe with an image exists |
| Phase 12 Homebox bootstrap instructions | **partially informed** — Open Question 4 answered (inferred); the seeding UI path is unknown and must not be invented |

## Credential Posture

No password, session token, or household member email address appears in this SUMMARY, in any command recorded in it, or in any file this plan committed. `changeme@example.com` and `MyPassword` are published upstream defaults, are already quoted verbatim in `10-06-PLAN.md` and in this repository's own smoketests, and are recorded only as the credentials proven dead. Usernames, user ids, group and household ids, and tailnet addresses already present in this repository's artifacts are recorded. Every probe run during this plan was a `SELECT`, a read of a Nix store path, a read of the request log, or a request that was rejected. No data was written to the Mealie database or its state directory.

Prohibition `Must NOT write any household member's Mealie password...` — **verified by scan**, not merely asserted: see Self-Check.

## Self-Check: PASSED

Files claimed created, verified present:

- `baseline/bootstrap-evidence-2026-08-19.md` — FOUND
- `baseline/shared-list-and-gate-evidence-2026-08-19.md` — FOUND
- `baseline/shared-list-visibility-diagnosis-2026-08-19.md` — FOUND
- `baseline/smoketests-household-post-bootstrap.txt` — FOUND
- `baseline/smoketests-household-final-2026-08-20.txt` — FOUND
- `baseline/smoketests-ser8-final-2026-08-20.txt` — FOUND

Commits claimed, verified present: `53af32e`, `2a3a56f`, `7de2115`, `ea2108d` — all FOUND.

Credential scan over every file this plan committed: no password value present.
