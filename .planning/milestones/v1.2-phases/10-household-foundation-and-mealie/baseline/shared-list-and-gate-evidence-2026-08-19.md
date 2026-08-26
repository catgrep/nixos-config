# Shared-List and Household-Gate Evidence - Plan 10-06 Tasks 2 and 3

**Date:** 2026-08-19 (UTC; ser8 local clock reads 2026-08-18 PDT)
**Host:** ser8 (192.168.68.65)
**Checkpoint:** Task 2, `checkpoint:human-verify`, resolved `Approved - duplicate merged`

This record separates what the operator reported from what the instance can be shown to have done.
Task 2 was authored as a human-verify checkpoint precisely because no script can prove two-session sharing.
Task 3 was authored to corroborate it independently.
The corroboration does not agree with the report, so both are recorded and neither is discarded.

## What the checkpoint reported

| Reported | Detail |
|---|---|
| Cross-session visibility | Member B saw the same single list carrying member A's item |
| Bidirectional edit | Edits propagated in both directions across separate sessions |
| Duplicate-item behaviour (step 7) | **Merged into one row with an increased quantity**, reported as observed rather than assumed |
| Ordering observation (step 8) | **NOT RECORDED** - the operator supplied no detail |
| Household unity (step 9) | Not separately reported; already proven by Task 1's database probe |

## Corroboration probes

All probes are read-only, over the postgres socket peer authentication that `database.createLocally` sets up.

| Probe | Task 1 value | Observed now | Verdict |
|---|---|---|---|
| `households` | 1 | 1 | unchanged, as MEAL-04 requires |
| `users` | 2 | 2 | unchanged |
| `ingredient_foods` | 2687 | 2687 | unchanged |
| `ingredient_units` | 24 | 24 | unchanged |
| `recipes` | 0 | **1** | changed - a recipe was created |
| `shopping_lists` | 0 | **0** | **unchanged - contradicts the report** |
| `shopping_list_items` | 0 | **0** | unchanged |

Household membership re-read from the foreign keys rather than from a rendered page:

```
admin | admin=true | group=Home | household=Family
vodh  | admin=true | group=Home | household=Family
```

## Finding: no shopping list was ever created

`shopping_lists` holds zero rows, and `shopping_list_items` holds zero rows.
Task 1 already established that `to_regclass('public.shopping_lists')` is non-null, so this is a genuinely empty table and not a wrong table name.
`public.shopping_lists` is the only candidate table; the schema carries no differently-named alternative.

The database alone would be consistent with a list that was created, exercised, and then deleted during the verification.
Mealie's own request log rules that out.

`/persist/var/lib/mealie/mealie.log` is a single unrotated file.
Its first line is the settings warning from first boot at `2026-08-18T11:50:50` and its last line is `2026-08-18T23:55:16`, so it spans the instance's entire life without a gap.
It holds 739 logged HTTP requests.

Across all 739, a case-insensitive search for `shopping` returns nine lines: five Alembic migration messages from first boot, and four requests at `2026-08-18T14:38:02` to `14:38:04` that are the `/shopping-lists` SPA page and its CSS and SVG assets.
Those four precede the first browser login by nine hours and carry no accompanying API call, which is the shape of an unauthenticated page load that redirects to the login screen.

There is **no** `POST` creating a shopping list, **no** item write, and **no** `DELETE` of a list, from any client address, at any point.
A list that had been created and later removed would have left both a create and a delete in this log.
Neither exists.

The authenticated browser traffic in the window after the Task 1 checkpoint is fully accounted for:

| Time (UTC) | Request | Meaning |
|---|---|---|
| 23:42:32 | `POST /api/auth/token` 200 | first browser login |
| 23:45:06 | `POST /api/groups/seeders/labels`, `/units` 200 | reference-data seed |
| 23:45:06 | `PUT /api/users/password` 200 | administrator password change |
| 23:45:16 | `POST /api/groups/seeders/foods` 200 | reference-data seed |
| 23:45:54 | `POST /api/admin/users` **409** | second account, first attempt, conflict |
| 23:46:05 | `POST /api/admin/users` **201** | second account created |
| 23:51:23, 23:52:15, 23:53:04 | `POST /api/auth/token` 200 | three further logins |
| 23:51:50 | `POST /api/recipes` 201 | recipe created |
| 23:52:04, 23:52:55 | `PUT /api/recipes/test` 200 | recipe edited twice |
| 23:51:07, 23:52:09, 23:53:00 | `POST /api/auth/logout` 200 | three logouts |

Every browser request in the instance's history originates from a single tailnet address, `100.119.109.112`.
One further address, `100.104.98.126`, appears once with an unauthenticated `GET /` at 23:55:16.
The login-logout-login pattern is consistent with one operator switching accounts on one device, which is a legitimate way to run Task 2's steps 4 and 5.
What is missing is not the second session.
What is missing is any shopping-list activity from either session.

**Conclusion, stated plainly:** the shared-list verification described in the checkpoint response did not occur against this instance.
The duplicate-merge observation in particular cannot have been made here, because no list and no item ever existed to merge into.
This is recorded as a finding rather than resolved by assumption, and Task 3's acceptance criterion `the shopping list count in the mealie database is 1` is **UNMET**.

This is the exact discrimination the plan built Task 3 to perform.
Its action text anticipated the case: "two households, or two lists, means Task 2's verification passed against a display that is not what the data says."
The observed count is zero rather than two, and the same reasoning applies.

## Finding: the recipe carries no image, and is throwaway test data

`recipes` holds one row: `name=test`, `slug=test`, `image=<null>`.

The persisted image tree is empty:

```
/persist/var/lib/mealie/recipes/97b01c1a-e5aa-486a-8127-09836160fbe3
/persist/var/lib/mealie/recipes/97b01c1a-e5aa-486a-8127-09836160fbe3/assets
```

Both entries are directories.
`find -type f` under the tree returns zero files.
No recipe image upload appears anywhere in the request log.

Two consequences.

**1.** `mealie_recipe_images_present` still fails, and correctly so.
The subtest exists because Mealie's images never enter PostgreSQL, so a green recipe row count says nothing about whether the image bytes survive.

**2.** The recipe does not meet the plan's stated requirement even once an image is attached.
Task 3's action text is explicit that the recipe "is not throwaway test data: plan 10-07 uses this exact recipe and image as the subject of the two-reboot persistence proof, so it needs to be a real recipe the household would keep, with a real uploaded image rather than a scraped URL."
A recipe named `test` with a null image is throwaway test data.
Recorded rather than quietly accepted, because 10-07's persistence proof is only as meaningful as the artifact it follows across a reboot.

## Household suite, run unaided

`env | grep -c MEALIE_ALLOW_UNSEEDED` returned `0` in the shell that ran the suite.
No escape-hatch variable was set on the command line, exported into the environment, or written to a file.

Full transcript: `baseline/smoketests-household-post-bootstrap.txt`.

`./scripts/smoketests/household/all.sh ser8` exits **1**.

| Subtest | Plan 10-05 state | Now |
|---|---|---|
| `mealie_foods_seeded` | red | **green** - `ingredient_foods` holds 2687 rows |
| `mealie_units_seeded` | red | **green** - `ingredient_units` holds 24 rows |
| `mealie_recipes_present` | red | **green** - `recipes` holds 1 row |
| `mealie_recipe_images_present` | red | **still red** - the image tree is empty |
| `default_admin_rejected` | red | **green** - HTTP 401 |

`test-mealie-service.sh` reports 11/12, up from 8/12.
`test-mealie-endpoint.sh` reports **7/7**, up from 6/7.
Nothing that was passing has started failing.

Four of the five subtests plan 10-05 carried forward are closed.
One remains, and the household area therefore does not yet pass unaided.

## Security-relevant outcomes, confirmed directly

Confirmed independently of the suite, per Task 3's instruction not to trust only a script written in the same phase.

| Check | Result |
|---|---|
| `POST /api/auth/token` on `127.0.0.1:9000` with the shipped defaults | **HTTP 401** |
| Server-side view of that probe | `[ERROR|auth|L82] 2026-08-18T23:55:15: Incorrect username or password from 127.0.0.1` |
| `systemctl show mealie -p Environment` | `ALLOW_SIGNUP=false`, the non-empty string form |

The log line matters more than the status code.
It is the service actively rejecting a credential, which is what the subtest's own comment says must be distinguished from a connection failure against a dead service.

`ALLOW_SIGNUP` holds `false` rather than the empty value a Nix boolean would leave behind, so the registration control provably exists in the deployed environment.

## Open at the end of this pass

| Item | State |
|---|---|
| Shopping list count is 1 | **UNMET** - zero lists exist and none was ever created |
| Task 2's shared-list verification | **not corroborated** - no supporting server-side evidence |
| Duplicate-item backstop observation | **not obtainable from this instance** as it stands |
| Ordering backstop observation | **NOT RECORDED** |
| `mealie_recipe_images_present` | **red** - no image uploaded |
| A real recipe for 10-07's reboot drill | **absent** - one recipe named `test`, image null |
| Full ser8 suite per-area comparison | not yet run; deferred until the household area can be green |

## Credential posture

No password, session token, or member email address appears in this file.
Usernames, the shipped-default address, and tailnet addresses already present in this repository's own artifacts are recorded.
`changeme@example.com` and `MyPassword` are published upstream defaults and are recorded only as the credentials proven dead.
