# Mealie Bootstrap Evidence — Plan 10-06 Task 1

**Date:** 2026-08-19
**Host:** ser8 (192.168.68.65)
**Checkpoint:** Task 1, `checkpoint:human-action`, resolved `Bootstrapped — all steps done`

The operator reported all eight steps complete but supplied none of the three facts the resume signal asked for.
This record therefore separates what the database proves from what remains unattested.
Nothing here was taken on report alone.

## Pre-bootstrap shape, for comparison

Plan 10-05 recorded the instance before this checkpoint: `users=1`, `households=1`, `foods=0`, `units=0`, `shopping_lists=0`, `recipes=0`.
Five household subtests were red, including `default_admin_rejected`.

## Corroboration probes

All probes are read-only.
Every count comes from `sudo -u postgres psql -tAq -d mealie` over the socket peer authentication that `database.createLocally` sets up.

| Probe | Pre-bootstrap | Observed now | Verdict |
|---|---|---|---|
| `users` | 1 | **2** | changed — a second account exists |
| `households` | 1 | **1** | one household, as MEAL-04 requires |
| `groups` | 1 | 1 | unchanged |
| `ingredient_foods` | 0 | **2687** | seeded |
| `ingredient_units` | 0 | **24** | seeded |
| `multi_purpose_labels` | not recorded | **32** | seeded |
| `shopping_lists` | 0 | **0** | unchanged — see the finding below |
| `shopping_list_items` | not recorded | 0 | consistent with zero lists |
| `recipes` | 0 | 0 | unchanged, expected; Task 3 creates one |

The database is not in its pre-bootstrap shape.
The bootstrap happened.

## Household membership

```
admin | admin=true | group=Home | household=Family
vodh  | admin=true | group=Home | household=Family
```

Both accounts are in the household `Family` under the group `Home`, the shipped default names, unrenamed.
This is the fact RESEARCH.md Pitfall 8 says produces a silently wrong result when it goes the other way, and it is checked here against the join rather than against the admin interface, which is what Task 2 will look at.

**Unplanned observation:** the second account carries `admin=true`.
The plan never asked for the second member to be an administrator and never forbade it.
Recorded because it is a privilege the plan did not specify, not because it fails anything.

## Credential change

| Check | Result |
|---|---|
| Rows in `users` with email `changeme@example.com` | **0** — the shipped address is gone |
| `POST /api/auth/token` on `127.0.0.1:9000` with the shipped defaults | **HTTP 401**, not 200 |

The token probe is the one that counts.
A changed email alone would not prove the password changed, and the smoketest's own comment is explicit that a connection failure must not be read as hardening — 401 is a live service actively rejecting the credential, not silence from a dead one.

This closes threat T-10-02 and turns the `default_admin_rejected` subtest that plan 10-05 recorded as red.

## Deployed registration control

```
Environment=ALLOW_SIGNUP=false
BASE_URL=https://mealie.shad-bangus.ts.net
```

`ALLOW_SIGNUP` holds the non-empty string `false`, not the empty value a Nix boolean would leave behind.
The registration control provably exists in the deployed environment rather than merely appearing to.

## Seeded exactly once

```
duplicate_food_names=0
duplicate_unit_names=0
```

Grouped by `(name, group_id)`, the pair the unique constraint covers.
A second seed would have either failed on that constraint and left partial data, or produced duplicate rows.
Neither is present, so the seed ran once and completed.

## The three requested facts

The resume signal asked for three things. The operator supplied none of them.

**1. Open Question 4 — did administrator-created accounts work with signup closed?**

**Answer: yes. Status: inferred from the database, NOT operator-attested.**

`ALLOW_SIGNUP=false` has been in the deployed unit environment since first boot (D-09), it is still there now, and a second account nevertheless exists.
Self-service registration was never open during the window in which that account appeared, so an administrator created it with signup closed.
The fallback the plan held in reserve — a deliberate two-deploy reopen-and-close sequence — was not needed and was not used.

Phase 12's Homebox bootstrap has the identical shape and inherits this answer, with the caveat that it is inferred here rather than observed directly.

**2. The real interface path used for the reference-data seed.**

**NOT RECORDED.**

The operator did not report it.
The database proves a seed happened and happened once; it cannot say which control was clicked.
RESEARCH.md Assumption A4 — that seeding is still a Manage Data button with a language picker in 3.22.0 — is therefore neither confirmed nor refuted, and Phase 12's bootstrap instructions must not be written as though it were confirmed.
Inventing a plausible path here would be a fabricated observation.

**3. Household name confirmation.**

**Answered by the database rather than by the operator:** both accounts are in `Family` under `Home`.
This is stronger than the report the checkpoint asked for, since it reads the foreign key rather than a rendered page.

## Finding: no shopping list exists

`shopping_lists=0`, and `to_regclass('public.shopping_lists')` is non-null, so the table exists and the count is genuinely zero rows rather than a wrong table name.

This **refutes, as written**, the plan's `must_haves` truth:

> A freshly bootstrapped Mealie has exactly one shopping list visible to both members and renders without error while that list is empty (MEAL-04, empty-input edge).

Mealie 3.22.0 does not auto-create a shopping list when a household is bootstrapped.
The empty-input edge the plan reasoned about is one level further out than the plan assumed: the empty case is **zero lists**, not one empty list.

Consequence for Task 2: its step 2 instructs the operator to "confirm exactly one shopping list is present."
Member A will see none and must create one first.
Carried into the Task 2 checkpoint so the operator is not left deciding whether an empty Shopping Lists page is a defect.
It is not — it is the documented starting state of a freshly bootstrapped instance.

## Credential posture

No password, session token, or member email address appears in this file.
Usernames and the shipped-default address are recorded; `changeme@example.com` and `MyPassword` are published upstream defaults, are already present throughout this repository's smoketests, and are recorded here only as the credentials proven dead.
