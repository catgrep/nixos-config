# Shared-List Visibility Diagnosis - Plan 10-06 Task 2 re-run

**Date:** 2026-08-19 (round 1), amended 2026-08-19 (round 2)
**Host:** ser8 (192.168.68.65)
**Trigger:** the operator re-ran Task 2, created a list named `testie` as one account, logged in as the other, and the second account did not see the list.
**Method:** read-only PostgreSQL probes, read-only reads of the deployed Mealie 3.22.0 source in the Nix store, execution of the shipped repository code against live data, and the unrotated request log at `/persist/var/lib/mealie/mealie.log`.
**Data modified:** none.

> **Round 2 supersedes the round-1 conclusion below.**
> The operator ran the decisive probe and reported `total: 0`, which round 1 said would mean "the server really is filtering it out, and every read above is wrong".
> Round 2 tested that claim by executing the shipped code and found the opposite: the server cannot filter by requesting user, because the SQL it generates contains no reference to the requesting user at all.
> Read [Round 2](#round-2-the-server-cannot-be-the-filter) first.
> The round-1 findings about schema, scoping, household count, and log decoding are unchanged and were re-verified.

## Verdict (round 1)

The failure is **not** the household split that MEAL-04 exists to catch.

There is exactly one group and exactly one household, and both accounts belong to it.
The server-side visibility filter, reconstructed from Mealie's own source and executed as SQL, **returns `testie` for the account that could not see it**.
That account's browser received HTTP 200 from the shopping-list index endpoint twice during the failed attempt, and the instance has never returned a 403 or a 5xx to anyone.

The list was therefore served and not displayed.
The remaining explanation is client-side, and the most likely one is that both accounts were exercised in the same browser profile rather than in two separate sessions, which is the one instruction in Task 2's procedure that was not followed.

This is recorded as a diagnosis with a decisive next probe rather than as a resolved finding, because response bodies are not in the log and the inference is one step short of direct observation.

## Round 2: the server cannot be the filter

The operator ran the round-1 probe in a fresh private window as `vodh`, opened Shopping Lists, and reported the response body as `total: 0`.
Round 1 said that outcome would mean the server is filtering the row out.
It does not, and the reason is stronger than "the predicate happens to match".

### The live filter carries no reference to the requesting user

Traced through the shipped source that the running workers actually execute:

```
routes/households/controller_shopping_lists.py:177  get_all -> self.repo.page_all(pagination=q, override=ShoppingListSummary)
routes/households/controller_shopping_lists.py:167  self.repo   -> self.repos.group_shopping_lists
repos/repository_factory.py:318                     -> RepositoryShoppingList(session, PK_ID, ShoppingList, ShoppingListOut,
                                                          group_id=self.group_id, household_id=self.household_id)
routes/_base/base_controllers.py                    group_id/household_id <- self.user.group_id / self.user.household_id
repos/repository_generic.py:334                     fltr = self._filter_builder()   # {group_id, household_id} only
repos/repository_generic.py:335                     q = q.filter_by(**fltr)
```

`RepositoryShoppingList` adds nothing to reads: it overrides `update` only.
`page_all` applies `_filter_builder()` and then `add_pagination_to_query`, which applies `pagination.query_filter` if one is present.
**The frontend attached no `queryFilter`** on any of the relevant requests: the logged query string is `page=1&perPage=-1&orderBy=name&orderDirection=asc` every time, and the log records query strings in full (other endpoints in the same session do show `queryFilter=...`).

The `household_id` association proxy resolves to an `EXISTS` subquery, which is why the round-1 reconstruction matched.
Compiled from the shipped code against the live database:

```sql
SELECT shopping_lists.id, shopping_lists.group_id, shopping_lists.user_id,
       shopping_lists.name, shopping_lists.created_at, shopping_lists.update_at
FROM shopping_lists
WHERE shopping_lists.group_id = 'b0adf1f4-2271-4858-87a2-b223cee0b105'
  AND (EXISTS (SELECT 1 FROM users
               WHERE users.id = shopping_lists.user_id
                 AND users.household_id = '006e0b23-0104-4ec3-adf6-28b1dc6d8160'))
```

**Nothing in that statement mentions the requesting user's id.**
The only inputs are `group_id` and `household_id`, and those two values are byte-identical for both accounts:

```
vodh   a971ed52-...5646b  group b0adf1f4-...  household 006e0b23-...
admin  a4b5728b-...ce7ac  group b0adf1f4-...  household 006e0b23-...
```

So the endpoint is **symmetric in the two accounts by construction**.
Whatever it returns for `admin`, it returns for `vodh`, because it is literally the same query with the same bound parameters.
A server-side filter that discriminates between them cannot exist unless one of those two values differs, and neither does.

### Executed, not reconstructed

Round 1 reconstructed the predicate by hand.
Round 2 ran the shipped code itself: instantiated `AllRepositories` with each user's real `group_id` and `household_id`, called the same `page_all` the route calls, with the same `ShoppingListSummary` override and a `PaginationQuery` mirroring the logged request.

```
--- as admin: raw count: 1   page_all total: 1   items: ['testie']
--- as vodh:  raw count: 1   page_all total: 1   items: ['testie']
```

Both users get `total: 1` with `testie` present.
This was run read-only, under the `mealie` service account, against the live database, with the same Python interpreter and the same `PYTHONPATH` the running workers use.

### The code that was read is the code that is running

- `systemctl show mealie -p ExecStart` -> `/nix/store/h7rqbff936wsdj8cq870zxmjc2r26skn-mealie-3.22.0/bin/mealie`
- Both gunicorn workers (pids 1067563, 1067565) carry that same store path in their environment, confirmed from `/proc/<pid>/environ`
- One service, one listener on `0.0.0.0:9000`, one `mealie.service`, no second instance, no SQLite file left in the data directory
- The gateway is a plain `reverse_proxy 192.168.68.65:9000` in `modules/gateway/Caddyfile` with no cache directive

### Ruled out

| Candidate | Status |
|---|---|
| Per-user ownership filter on shopping lists | Does not exist. `user_id` records the creator only. |
| `queryFilter` narrowing the result | No `queryFilter` was sent on any shopping-list index request. |
| Cached or stale `PrivateUser` | `get_current_user` does no caching, and a stale object would carry the same household anyway. |
| Second Mealie instance or second database | One unit, one listener, one Postgres database. |
| Reverse-proxy or tsnet response cache | Caddy config is a bare `reverse_proxy`. |
| Client-side filtering in the frontend | The bundle maps the endpoint to a plain URL with no household or user predicate. |
| Household changed between test and probe | `admin` has never been updated; `vodh`'s last update predates the list's creation. |
| Upstream defect in 3.22.0 | No matching issue in the Mealie tracker (searched shopping-list / household / visibility). More decisively, there is no code path in the shipped source that could produce the observed result, so there is nothing for an upstream fix to change. |

### The clean-session probe in the log

The probe is visible and identifiable.

| Local time | Event | Reading |
|---|---|---|
| 00:10:42 | full cold fetch of every `_nuxt` asset | a genuinely fresh browser profile, as instructed |
| 00:10:47 | `POST /api/auth/token` **200**, then `GET /api/media/users/a971ed52-.../profile.webp` | the session is **`vodh`** |
| 00:10:50 | `GET /api/households/shopping/lists?page=1&perPage=-1&orderBy=name&orderDirection=asc` **200** | the probed request, no `queryFilter` |
| 00:11:00 | `POST /api/auth/token` **200**, zero `_nuxt` requests, no avatar fetch | a second, warm-cache window |
| 00:11:02-03 | recipe detail, then shopping-lists index, labels, **`GET .../lists/8d207a6a-...` 200**, units | this session received a non-empty index and opened `testie` |
| 00:13:07 | `GET /shopping-lists//api/households/shopping/lists` **404** | a hand-typed or mis-resolved relative URL |
| 00:13:16 | `GET /api/households/shopping/lists` **401**, no query string | the bare API URL opened without a token |
| 00:13:29 | `GET /api/households/shopping/lists?page=1&...` **200** | |

The 00:11:00 session cannot be pinned to an account from the log: it fetched no avatar and no assets, which is what a re-login looks like in **either** window once that user's avatar is cached.
That ambiguity does not matter, because the query is user-independent.

The two entries at 00:13:07 and 00:13:16 are worth noting: someone was hand-assembling the API URL around the time of the report.
A `401` body carries `{"detail": ...}` and no `total`, and the `404` carries no `total` either, so neither is the source of a `total: 0` reading.

### What this leaves

The server returned `total: 1` to the request at 00:10:50.
Three independent lines of evidence say so: the source has no user-scoped predicate, the compiled SQL names only group and household, and executing the real `page_all` for `vodh` against live data returns the row.

The reported `total: 0` therefore did not come from that response body.
The remaining explanations are all on the reading side, and the phase cannot close on an inference:

1. A different Network row was inspected (the `401` at 00:13:16 and the `404` at 00:13:07 are both in the window, and neither carries a `total`).
2. The rendered page was read rather than the response body.
3. The response body of a different endpoint was read.

This is stated as the remaining explanation, not as a proven one.
The probe below removes the browser from the loop entirely and settles it in one command.

### Decisive probe: server-side, no browser

Run this on ser8, over SSH, as the household member `vodh`.
It bypasses Caddy, tailscale, the browser, the service worker, and the frontend, and talks straight to the application over loopback.
The password is read with `read -s`, never echoed, never placed on the command line, and never written to shell history.

```bash
ssh bdhill@192.168.68.65
read -rp  'mealie email: ' MEALIE_EMAIL
read -rsp 'mealie password: ' MEALIE_PASS; echo
TOKEN=$(curl -s -X POST http://127.0.0.1:9000/api/auth/token \
  --data-urlencode "username=$MEALIE_EMAIL" \
  --data-urlencode "password=$MEALIE_PASS" | python3 -c 'import sys,json; print(json.load(sys.stdin)["access_token"])')
unset MEALIE_PASS
curl -s -H "Authorization: Bearer $TOKEN" \
  'http://127.0.0.1:9000/api/households/shopping/lists?page=1&perPage=-1&orderBy=name&orderDirection=asc' \
  | python3 -m json.tool | head -30
unset TOKEN
history -c 2>/dev/null || true
```

Report only the `total` value and the list names.
Do not paste the token or the password.

| Outcome | Meaning | Action |
|---|---|---|
| `total: 1`, `testie` present | The API is correct and MEAL-04 holds at the data and API level. The earlier reading was of something other than this response. | Clear the browser side (below), then re-run Task 2 step 5. |
| `total: 0` | Three independent proofs are wrong at once, which the shipped source does not allow. | Stop. Confirm which account the email belongs to, and re-open with the exact request and response captured. |

### Recommended fix

**No Mealie data change is warranted, and none should be made.**
Moving an account between households, recreating the list, or editing household preferences would all be changes against a cause that the code and the data both contradict, and the first two destroy the evidence.

The minimal path to MEAL-04:

1. Run the loopback probe above. It is read-only and takes under a minute.
2. If it returns `total: 1`, clear the browser side before re-testing the interface: in each browser profile open devtools, Application, Service Workers, unregister the Mealie worker, then Storage, Clear site data, then hard-reload. Mealie 3.22.0 ships a PWA service worker (`GET /sw.js` appears repeatedly in the log) and it is the only remaining component between a correct API response and a blank page.
3. Re-run Task 2 steps 1 to 6 with the two accounts in genuinely separate profiles, and when reading the Network tab, record the **full request URL** next to the `total` value so a misread row is self-evident next time.
4. Task 2's remaining acceptance items are still unobserved and unaffected by any of this: the duplicate-item behaviour in step 7 and the ordering note in step 8.

If step 2 does not restore the display while the API returns `total: 1`, that is a genuine Mealie 3.22.0 frontend defect: record it, file it upstream, and satisfy MEAL-04 from the API response plus the database counts that Task 3 already asserts.

## The account names are inverted relative to the report

This matters for the operator's mental model, so it is stated before anything else.

| Username | User id | Created | What it actually is |
|---|---|---|---|
| `vodh` | `a971ed52-...5646b` | 2026-08-18 18:50:52 UTC | the **original** administrator created at first boot, later renamed |
| `admin` | `a4b5728b-...ce7ac` | 2026-08-19 06:46:05 UTC | the **second** household member, created through the admin area |

`vodh`'s row was created at `18:50:52.710553`, in the same second as the `Family` household (`18:50:52.509212`) and the first line of the log (first boot, `11:50:50` local).
It is the account that was seeded with the shipped defaults and then renamed: the log carries `PUT /api/users/a971ed52-...` twice, and a single `PUT /api/users/password`.

`admin`'s row was created at `06:46:05.875322` UTC, matching `POST /api/admin/users` returning 201 at `23:46:05` local exactly.
Its `update_at` differs from its `created_at` only in microseconds, so it has never been modified since creation.

So the list titled `testie` was created by the **second member**, and the account that could not see it was the **original administrator** - the reverse of how the report reads.
The conclusion below is unchanged by this, because both accounts sit in the same household, but the labels should be corrected before any remedial action is taken against the wrong account.

## There is one household, and there has only ever been one

```
groups:     1 row  - Home   b0adf1f4-2271-4858-87a2-b223cee0b105
households: 1 row  - Family 006e0b23-0104-4ec3-adf6-28b1dc6d8160 (group_id = Home)
```

Both users carry `group_id = Home` and `household_id = Family`.

The complete set of mutating requests over the instance's entire life contains no household creation and no household deletion:

```
2 PUT  /api/users/<vodh>              2 PUT  /api/recipes/test
2 POST /api/households/shopping/items/create-bulk
2 POST /api/admin/users               1 PUT  /api/users/password
1 PUT  /api/households/preferences    1 PUT  /api/groups/ai-providers/settings
1 PUT  /api/admin/households/<Family> 1 PUT  /api/admin/groups/<Home>
1 POST /api/recipes                   1 POST /api/households/shopping/lists
1 POST /api/groups/seeders/{foods,units,labels}
```

The only household-directed write is a single `PUT` editing the one existing household.
A second household never existed, so it cannot have been the cause and cannot have been silently cleaned up.

## How Mealie 3.22.0 actually scopes a shopping list

The phase's working assumption, taken from RESEARCH.md Pitfall 8, is that `shopping_lists` carries a `household_id`.
It does not.
The deployed schema is:

```
shopping_lists: created_at, update_at, id, group_id (NOT NULL, FK groups),
                name, user_id (NOT NULL, FK users)
```

`household_id` is not a column on this table.
It is a derived attribute in the ORM, at
`lib/python3.14/site-packages/mealie/db/models/household/shopping_list.py`:

```python
class ShoppingList(SqlAlchemyBase, BaseMixins):
    __tablename__ = "shopping_lists"
    group_id: ... = mapped_column(GUID, ForeignKey("groups.id"), nullable=False, index=True)
    household_id: AssociationProxy[GUID] = association_proxy("user", "household_id")
    household:    AssociationProxy["Household"] = association_proxy("user", "household")
    user_id: ... = mapped_column(GUID, ForeignKey("users.id"), nullable=False, index=True)
```

**A shopping list's household is whatever household its creator is in, read live through `user_id`.**
It is not stored, so it follows the creator if the creator is ever moved.

The filter applied to every read is in `repos/repository_generic.py`, and it is only ever these two keys:

```python
def _filter_builder(self, **kwargs) -> dict[str, Any]:
    dct = {}
    if self.group_id:     dct["group_id"] = self.group_id
    if self.household_id: dct["household_id"] = self.household_id
    return {**dct, **kwargs}
```

`page_all`, which serves `GET /api/households/shopping/lists`, applies exactly that and nothing else.
`_query` adds no user predicate.
`routes/_base/base_controllers.py` binds those two values to `self.user.group_id` and `self.user.household_id`.

**There is no per-user ownership filter on shopping lists.**
`user_id` records who created the list; it never restricts who may read it.
So the correct expectation is that every member of a household sees every list created by any member of that household, and the phase's key_links entry is right about the household being load-bearing even though it is right for a different mechanical reason than assumed.

## The filter matches, executed against live data

Reconstructing the exact predicate the server applies for `vodh` and running it read-only:

```sql
SELECT sl.name, sl.id, ou.username AS owner, ou.household_id AS list_household
FROM shopping_lists sl JOIN users ou ON ou.id = sl.user_id
WHERE sl.group_id = '<Home>'
  AND EXISTS (SELECT 1 FROM users u
              WHERE u.id = sl.user_id
                AND u.household_id = (SELECT household_id FROM users WHERE username='vodh'));
```

```
  name  |                  id                  | owner |            list_household
--------+--------------------------------------+-------+--------------------------------------
 testie | 8d207a6a-c1b3-4f82-8a04-49b7b9ce5afe | admin | 006e0b23-0104-4ec3-adf6-28b1dc6d8160
(1 row)
```

`vodh` is entitled to `testie` right now, on the data as it stands.

Neither account's household could have differed at test time.
`admin` has never been updated since creation.
`vodh`'s last update is `06:50:28` UTC, which is **before** the list was created at `06:58:58` UTC.

## The failed session, decoded from the log

Log timestamps are ser8 local (PDT); database timestamps are UTC, seven hours ahead.

| Local time | Event | Which account, and how it is known |
|---|---|---|
| 23:53:04 | login | `admin` - this session creates the list, and `shopping_lists.user_id` is `admin` |
| 23:58:58 | `POST /api/households/shopping/lists` **201** | `testie` created |
| 23:59:06, 23:59:15 | `POST .../items/create-bulk` **201** | two items added |
| 23:59:24 | `POST /api/auth/logout` **200** | |
| 23:59:28 | `POST /api/auth/token` **200** | **`vodh`** |
| 23:59:31 | `GET /api/households/shopping/lists?...` **200** | Shopping Lists opened |
| 23:59:34 | `GET /api/recipes?...` | navigated away |
| 23:59:36 | `GET /api/households/shopping/lists?...` **200** | Shopping Lists opened again |
| 23:59:39 | `GET /api/recipes?...&queryFilter=favoritedBy.id = "a971ed52-...5646b"` | |
| 23:59:40 | `GET /api/admin/households`, `/api/admin/groups` | the operator went looking for a second household |
| 23:59:44 | `POST /api/auth/logout` **200** | |
| 23:59:48 | `POST /api/auth/token` **200** | `admin` again, avatar `a4b5728b` fetched |
| 00:00:01-00:01:20 | `GET .../lists/8d207a6a-...` **200** every 5s | `admin` sitting on the list detail page |

The session identity at 23:59:28 is not a guess.
At 23:59:39 that session asked for its own favourites with `favoritedBy.id = "a971ed52-ae67-471a-a5ee-31f19a75646b"`, which is `vodh`'s user id.
The frontend builds that filter from the logged-in user, so the session was `vodh`.

**`vodh` requested the shopping-list index twice and received HTTP 200 both times.**

Across the instance's whole life the only non-2xx/3xx responses are:

```
2 x 401  - the shipped default credentials, correctly rejected
15 x 404 - all of them /api/media/recipes/97b01c1a-.../images/min-original.webp
1 x 409  - the first attempt to create the second account
```

No 403 was ever returned to anyone.
No 5xx was ever returned to anyone.
The log contains zero `ERROR` or `WARNING` lines in this window.

So `vodh` was not denied, and the request did not fail.

## What round 1 left

> Superseded by [Round 2](#round-2-the-server-cannot-be-the-filter).
> The shared-browser-profile hypothesis below was the leading candidate before the probe ran.
> It is no longer the leading candidate: the probe was run in a genuinely fresh profile, which the cold `_nuxt` fetch at 00:10:42 confirms, so a stale client store from an in-place account switch is ruled out.
> The server-side half of this section stands and was re-verified by execution.

The server matched the row and answered 200.
The screen showed nothing.
The gap between those two facts is client-side, and the response body is the one thing the log does not record.

The strongest contributing factor available in the evidence: **both accounts were exercised in the same browser profile.**
Every browser request in the instance's history originates from a single tailnet address, and the account switch was a logout followed by a login in place, not a second profile or a private window.
Task 2's step 4 says "in a separate browser profile or a private window" specifically to avoid this.
Mealie 3.22.0 ships a PWA service worker - `GET /sw.js` appears at 00:01:09, 00:03:09 and 00:05:08 - and keeps shopping-list state in a client-side store, so a stale store or a cached response surviving an in-place account switch is a plausible way for a 200 carrying one list to render as an empty page.

This is stated as the leading hypothesis, not as a proven cause.
It is cheap to discriminate, and the next probe below does so in one step.

## Decisive next probe (round 1, completed)

> **Outcome:** the operator ran this and reported `total: 0`, which selects the third row of the table below.
> Round 2 followed that instruction, reopened the diagnosis, and found that the third row's premise does not hold: see [Round 2](#round-2-the-server-cannot-be-the-filter).
> The replacement probe is [Decisive probe: server-side, no browser](#decisive-probe-server-side-no-browser).

Re-run the visibility check as `vodh` in a genuinely separate session, and capture the response body rather than the rendered page.

1. Open a **private window**, or a second browser profile, that has never held a Mealie session.
2. Open the browser devtools **Network** tab before logging in.
3. Log in as `vodh` at `https://mealie.shad-bangus.ts.net`.
4. Open Shopping Lists.
5. Find the request to `/api/households/shopping/lists?page=1&perPage=-1&...` and read its **response body**.
6. Report the value of `"total"` and whether `"items"` contains an entry named `testie`.

The outcome splits cleanly:

| Response body | Meaning | Action |
|---|---|---|
| `total: 1`, `testie` present, and the page shows it | the original failure was stale client state in the shared browser profile | Task 2 passes; no data change needed |
| `total: 1`, `testie` present, but the page shows nothing | a genuine Mealie 3.22.0 frontend defect | record it, file upstream, and satisfy MEAL-04 from the API response |
| `total: 0` | the server really is filtering it out, and every read above is wrong | stop and reopen the diagnosis with the response body in hand |

No fix should be applied before this probe runs.
Moving an account between households, recreating the list, or editing household preferences would all be changes made against an unconfirmed cause, and the first two would destroy the evidence.

## Secondary findings

**The shipped default administrator credentials are dead (round 2, incidental).**

A token request against the loopback port using the public upstream defaults returns `401`:

```
POST http://127.0.0.1:9000/api/auth/token  (changeme@example.com / MyPassword)  -> 401
```

That is one of Task 3's acceptance criteria, confirmed in passing.
It is recorded here so Task 3 corroborates rather than discovers it.

**No Mealie API token exists.**

`long_live_tokens` holds zero rows, so no authenticated end-to-end request could be made during this diagnosis without a household password.
That is why the decisive probe above is written for the operator to run rather than performed here.

**Both accounts are full site administrators.**

| Username | `admin` | `can_manage` | `can_manage_household` | `advanced` |
|---|---|---|---|---|
| `vodh` | true | true | true | true |
| `admin` | true | true | true | true |

The second household member does not need site-administrator rights to share a shopping list, and MEAL-02's posture is weakened by granting them.
Recorded, not changed - this pass modifies no data.
Worth resolving before Phase 14's SEC-02 audits privilege.

**Household preferences were edited after the failed test, not before.**

`household_preferences.update_at` is `07:01:48` UTC, matching `PUT /api/households/preferences` at `00:01:48` local, which is after the failure.
Current state includes `private_household = false` and `lock_recipe_edits_from_other_households = true`.
Whatever was changed there is not a candidate cause, because the row was untouched at defaults throughout the test.

**The recipe situation is unchanged, and the sharing claim is not supported.**

`recipes` still holds exactly one row: `name=test`, `slug=test`, `image` **null**, owned by `admin`.
`find -type f` under `/persist/var/lib/mealie/recipes` returns **zero files**.
The 15 recurring 404s in the log are the frontend asking for that missing image on every recipe-page load.

`users_to_recipes` holds **0 rows** and `households_to_recipes` holds **0 rows**, so no recipe was favourited, rated, or attached to a household.
The log shows one `POST /api/recipes` and two `PUT /api/recipes/test`, all inside the `admin` session at 23:51-23:52, and no recipe write by `vodh` at any point.

Nothing that could be called a deliberate share was performed.
Recipes in Mealie are group-scoped, so both accounts could already see `test` with no action taken - which is the likely origin of the impression that a recipe was shared.

This leaves plan 10-07 without its subject.
Its two-reboot persistence proof needs a real recipe carrying a real uploaded image, and `mealie_recipe_images_present` stays red until one exists.

**The duplicate-item backstop is still unobserved.**

`shopping_list_items` holds two rows on `testie`, with two **different** `food_id` values and quantities 1 and 0.
No food was added twice, so Task 2 step 7's merge-or-append question has still not been exercised.

## Credential posture

No household password, session token, or member email address appears in this file.
The only credential values recorded are Mealie's shipped upstream defaults, which are public, are already quoted verbatim in `10-06-PLAN.md`, and are proven dead above.
Usernames, user ids, group and household ids, and the tailnet hostname already present in this repository's artifacts are recorded.
No data was written to the Mealie database or its state directory during this diagnosis, in either round.
Every probe was a `SELECT`, a read of a Nix store path, a read of the request log, or an unauthenticated request that was rejected.
