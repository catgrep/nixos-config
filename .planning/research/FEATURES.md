# Feature Research: v1.2 Household Stack

**Domain:** Self-hosted household management apps (recipes, chores, inventory, budgeting) on an existing NixOS homelab
**Researched:** 2026-08-16
**Confidence:** MEDIUM-HIGH (Donetick model/API read directly from upstream source; Mealie/Homebox/Actual behaviour from official docs cross-checked against maintainer discussions)

---

## Framing: What "Features" Means In This Milestone

Almost every user-visible feature in this milestone is already built by upstream.
Mealie, Donetick, Homebox and Actual Budget ship complete products.
What this milestone actually delivers is three things, and the roadmap should be structured around that split:

| Layer | What it is | Declarative? | Where the work is |
|-------|-----------|--------------|-------------------|
| **A. Deployment** | NixOS module/container, Caddy vhost, AdGuard record, persistence, secrets, backup | Yes, fully | Nix + `deploy.yaml` + smoketests |
| **B. Bootstrap + in-app config** | First admin, second user, household/circle/group membership, closing registration, seeding reference data | **No.** Inherently manual and one-time | A written, verifiable checklist per service |
| **C. Google Tasks import** | The only real software being written | Script, run once | Donetick API + Takeout JSON |

**The most important structural finding:** the repo constraint is "all config must be in NixOS Nix files, not UI-only configuration," but every one of these four services requires irreducible in-app bootstrap.
There is no declarative path to "user B is in the same household as user A."
The roadmap must treat layer B as a first-class deliverable with recorded, re-runnable steps, not as an afterthought that happens in a terminal and is forgotten.
Otherwise a restore test will produce a running service with no users in it, and the failure will not be noticed until someone tries to log in.

**Second structural finding:** three of the four services have a bootstrap ordering hazard.
Registration must be **open** at first boot and **closed** afterwards, which is a two-deploy sequence, not a single declarative state.
Homebox is the dangerous one: it has no default admin account, so closing registration before creating an account is unrecoverable.

---

## Feature Landscape

### Table Stakes: Cross-Cutting (All Four Services)

| Feature | Why Expected | Complexity | Depends On (existing infra) |
|---------|--------------|------------|------------------------------|
| Reachable at `<name>.vofi` with valid local-CA TLS | Matches the existing service naming pattern; typing ports is the thing people stop doing | LOW | firebat Caddy (`local_certs`), `modules/gateway/Caddyfile` |
| AdGuard DNS A record per hostname | Caddy vhost is inert without name resolution | LOW | pi4 AdGuard Home, `modules/dns/` |
| Service binds localhost or Tailscale only | Firm constraint: nothing public | LOW to configure, MEDIUM to *verify* | Tailscale; needs a negative smoketest (reachable with Tailscale up, refused without) |
| Every stateful path in `environment.persistence` | ser8 ZFS root rollback silently destroys anything not declared | MEDIUM | impermanence on ser8; `systemd.tmpfiles.rules` for ownership on fresh boot |
| Secrets from sops-nix, nothing in `/nix/store` | Repo standard; Mealie Postgres password and Donetick JWT secret are both real secrets | LOW-MEDIUM | `secrets/ser8.yaml`, existing `make sops-edit-ser8` |
| Nightly backup to the ZFS backup pool | Recipe collections and budget history are irreplaceable by hand | MEDIUM | ZFS backup pool on ser8; existing backup pattern |
| **Demonstrated restore** | A backup never restored is not a backup | MEDIUM-HIGH | Scratch instance + the bootstrap checklist from layer B |
| Two accounts, one per person, in a shared scope | The entire point is a two-person household, not two private silos | LOW per service, but **three different mechanisms** | None |
| Registration closed after bootstrap | Nothing is public, but an open signup form on a shared LAN is still wrong | LOW | Two-stage deploy |
| Prometheus blackbox probe per service | Every other service on this homelab has one; a household app that is quietly down is worse than one that is loudly down | LOW | Existing blackbox exporter on firebat (v1.1 Phase 4, already validated) |

**Backup mechanics differ per service and this matters for the restore test:**

- Mealie: `pg_dump` of the Postgres database **plus** the recipe image / user upload directory. A DB-only restore loses every recipe photo.
- Donetick, Homebox, Actual: SQLite `.backup` or `VACUUM INTO`, never a raw `cp` of a live database file. Homebox additionally needs its attachments directory.
- Actual with end-to-end encryption ON would make the server-side backup ciphertext, which changes what "demonstrated restore" can even prove. See the Actual anti-features section.

---

### Table Stakes: Mealie

**Highest priority service. Ship it alone and let it soak.**

| Feature | Why Expected / Day-One | Complexity | Notes |
|---------|------------------------|------------|-------|
| PostgreSQL, not SQLite | Decided upstream in the proposal; fuzzy ingredient search needs Postgres and migrating later is avoidable work | MEDIUM | `DB_ENGINE=postgres` + `POSTGRES_USER/PASSWORD/SERVER/PORT/DB`; `services.mealie` exists in nixpkgs 25.11 |
| Change the default admin credentials | Mealie initialises a default account (`changeme@example.com` / `MyPassword`) on first DB init | LOW | Overridable at *first init only* via `DEFAULT_EMAIL` / `DEFAULT_PASSWORD`; changing them later does nothing |
| `ALLOW_SIGNUP=false` | Already the default since v1.4.0 | LOW | Because a default admin exists, Mealie has **no** bootstrap ordering hazard: you can ship with signup closed from day one |
| Second user added via invite link into the **same household** | Meal plans and shopping lists are household-scoped. Two households = two disconnected plans | LOW | Admin > Users > Invite User, targeted at a specific group/household |
| **Seed Foods and Units** | Not automatic. Without it, ingredient parsing is weak and shopping-list aggregation does not merge duplicates | LOW effort, HIGH impact | User menu > Manage Data > Foods > Seed (per language), then repeat for Units. Unit seed is fairly complete; food seed is partial |
| Correct `BASE_URL` | Invite links, share links and notification links are built from it; wrong value breaks the invite flow behind Caddy | LOW | Must be `https://recipes.vofi` (or agreed name), not the internal port |
| Recipe import by URL | This is the feature the household actually asked for | LOW (built in) | Scrapes hundreds of sites; also has importers for Paprika, Tandoor, Nextcloud Cookbooks, Copy Me That |
| Shopping list "Show All" toggle enabled | **Gotcha:** lists are household-scoped, but the list page defaults to filtering to lists *you* created, so each person thinks the other's list does not exist | LOW effort, HIGH impact | Directly load-bearing for the "Mealie's list is the only shopping list" constraint |
| Correct `TZ` | Meal planner day boundaries | LOW | Match the host |

**Mealie group/household model (verified):**

| Scope | What lives there |
|-------|------------------|
| **Group** (isolated tenant) | Recipes, organizers (categories, tags, tools) |
| **Household** (subdivision of a group) | Meal plans, shopping lists, integrations, per-household settings |
| **User** | Belongs to exactly one household. No multi-household membership |

For a 2-person household: **one group, one household, two users.**
That is the only configuration where both people see one meal plan and one shopping list.

**Can wait (not day-one):**

- Categories / tags / tools taxonomy. Let it emerge from ~20 real recipes rather than designing it up front.
- Cookbooks (saved filtered views). Meaningless with an empty catalog.
- Meal Planner Rules (restrict random selection by tag/category/day). Needs a catalog first.
- Apprise notifiers and webhooks. No consumer for them in this milestone.
- OIDC. No IdP in this homelab.
- Recipe Actions (custom per-recipe links).

---

### Table Stakes: Donetick

| Feature | Why Expected / Day-One | Complexity | Notes |
|---------|------------------------|------------|-------|
| Packaging | **No `services.donetick` in nixpkgs 25.11** (mealie, homebox and actual all have modules; donetick does not) | MEDIUM-HIGH | Container pinned by digest, or a hand-written module. Real work, unlike the other three |
| SQLite path persisted | Single Go binary, SQLite is correct at this scale | LOW | `database.type: sqlite`; persist the DB file's directory |
| JWT secret >= 32 chars from SOPS | App refuses weak secrets; rotating it invalidates all sessions | LOW | `jwt.secret` in config; must not be a Nix-store literal |
| One **Circle** containing both users | A Circle is Donetick's household. Chores belong to a circle; a user outside it sees nothing | LOW | Second user joins via the circle's `invite_code` |
| `DONETICK_DISABLE_SIGNUP=true` after both accounts exist | Config key `is_user_creation_disabled`, env override `DONETICK_DISABLE_SIGNUP` | LOW | **Ordering hazard:** must be false at first boot |
| API access token minted | Required for the Google Tasks import | LOW | Sent as the `secretkey` header |
| Assignment strategy chosen | Determines whether chores rotate or stick | LOW | See enum below. For 2 adults, `round_robin` or `keep_last_assigned` |

**Donetick concept model (read directly from upstream `internal/chore/model/model.go` and `internal/chore/handler.go`, confidence HIGH):**

`FrequencyType` enum (11 values):

| Value | Meaning |
|-------|---------|
| `once` | One-off task with a due date. **This is what a Google Tasks todo maps to** |
| `no_repeat` | One-off, no recurrence semantics |
| `daily` / `weekly` / `monthly` / `yearly` | Calendar cadence, multiplied by the integer `frequency` field (frequency=2 + weekly = fortnightly) |
| `interval` | Every N of `frequencyMetadata.unit` where unit is `hours`/`days`/`weeks`/`months`/`years` |
| `days_of_the_week` | Specific weekdays via `frequencyMetadata.days[]`, optionally narrowed by `weekPattern` (`every_week`, `week_of_month`, `week_of_quarter`) and `occurrences[]` (1st, 3rd, last) |
| `day_of_the_month` | Specific day(s) of month, optionally restricted to `frequencyMetadata.months[]` |
| `adaptive` | Learns cadence from completion history and predicts the next due date |
| `trigger` | Fires when a **Thing** (a tracked number/boolean/text value) changes |

`AssignmentStrategy` enum (7 values): `random`, `least_assigned`, `least_completed`, `keep_last_assigned`, `random_except_last_assigned`, `round_robin`, `no_assignee`.

Other chore fields that matter: `isRolling` (next due date anchored to **completion** rather than to the previous due date), `points`, `priority` (int), `completionWindow` (seconds before due that completion is allowed), `requireApproval`, `isPrivate`, `projectId`, `labelsV2`, `subTasks[]` (each with `orderId`, `name`, `completedAt`, `completedBy`, and a `parentId` that permits nesting), `notificationMetadata` (dueDate / preDue / completion / nagging plus up to 5 templates in minutes/hours/days).

Circle membership (`UserCircle`) carries `role`, `points` and `pointsRedeemed`, so the points system is per-circle-member state.

**Can wait / should not be enabled:**

- Points and the redemption ledger. Built for kid-incentive workflows. Two adults keeping score is friction that predicts abandonment.
- `requireApproval`. Same reasoning.
- Notifications (Telegram / Discord / Pushover). Proposal says leave unconfigured, and the chore set will churn heavily in the first month. Wiring alerts to an unstable chore set trains people to ignore them.
- Things and trigger-based chores. Interesting, but there is no data source feeding a Thing without an integration, and integrations are out of scope.
- Projects, timers, NFC tags, attachments, MFA.

---

### Table Stakes: Homebox

| Feature | Why Expected / Day-One | Complexity | Notes |
|---------|------------------------|------------|-------|
| `HBOX_OPTIONS_ALLOW_REGISTRATION=true` at first boot, `false` after | Homebox has **no default admin account** | LOW effort, **HIGH risk** | Closing registration before an account exists locks you out with no documented recovery. This is the single most dangerous bootstrap step in the milestone |
| Second user joins the **same Group** via invite token | All users in a Group see the same items. A second self-registration creates a second, empty, invisible inventory | LOW | Invite generated from Profile, not by registering separately |
| Data directory and SQLite path persisted | `HBOX_STORAGE_DATA`, `HBOX_STORAGE_SQLITE_URL` | LOW | Attachments live under the data dir; back both up together |
| `HBOX_OPTIONS_ALLOW_ANALYTICS=false` | Nothing on this homelab phones home | LOW | |
| `HBOX_WEB_MAX_UPLOAD_SIZE` raised | Default is small; receipts and PDF manuals are the main reason to use Homebox | LOW | |
| A minimal Location tree | Items without locations are a list, not an inventory | LOW | Nested locations supported (`Home / Office / Desk`) |

**Can wait:**

- Labels. Add when the first cross-location query ("all warranties expiring") is actually needed.
- Custom fields (`HB.field.{name}`).
- Asset IDs and printable QR label sheets (Avery 5260). Genuinely useful later; pure overhead on day one.
- Reports / bill-of-materials TSV export.
- CSV bulk import. See anti-features.
- Themes (29 of them).

---

### Table Stakes: Actual Budget

| Feature | Why Expected / Day-One | Complexity | Notes |
|---------|------------------------|------------|-------|
| Server password set at first visit | `ACTUAL_LOGIN_METHOD=password` is the default | LOW | Set through the browser on first load, not declaratively. Store it in the household password manager |
| `ACTUAL_DATA_DIR` persisted | Holds `ACTUAL_SERVER_FILES` (sqlite: password hashes, session tokens) and `ACTUAL_USER_FILES` (budget blobs) | LOW | Both must be in impermanence or the server password resets on reboot |
| One budget file created | Actual auto-creates one on first login if none exists | LOW | |
| Encryption decision made **before** entering data | Cannot be disabled in place; reversing requires export + import | LOW effort, irreversible | Recommendation: **leave OFF**. See anti-features |
| Accounts + starting balances + first month's categories | An empty budget file is not a budget | MEDIUM (data entry, not engineering) | Genuinely day-one; a half-entered budget is abandoned within a week |

**Critical model fact:** under password auth Actual has **no user identity at all**.
Both people share one server password and open the same budget file.
There is no per-user view, no permissions, no audit of who changed what.
Multi-user (User Directory with Basic/Admin roles, per-file User Access, ownership transfer) requires OpenID and shipped as experimental in 25.1.0.

For two people who share finances, the no-identity model is fine and is the simplest thing that works.
State this explicitly in the roadmap so nobody "fixes" it later by standing up an IdP.

**Can wait:**

- SimpleFIN bank sync. Constraint says in-app only, never provisioned in Nix. It is also a paid third-party bridge holding bank credentials. Defer until the budget is actually being used.
- OpenID / multi-user.
- Custom reports, scheduled transactions, rules. All post-adoption refinements.

---

### Differentiators

Not required, but these are what make the stack feel deliberate rather than assembled.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| **Verified negative access test** | "Nothing is exposed" becomes a checked fact rather than a belief. Turn Tailscale off, confirm connection refused | LOW | Belongs in `scripts/smoketests/`; the repo already has this pattern |
| **Reboot-twice persistence smoketest** | The proposal names impermanence as the most likely thing to be wrong. An automated check beats hoping | MEDIUM | `make test-ser8` then reboot, assert data survives |
| **Restore rehearsal into a scratch instance** | Converts backups from decoration into infrastructure. Also the only way to discover that the bootstrap checklist was never written down | MEDIUM-HIGH | Highest-value single item in the milestone after Mealie itself |
| **Blackbox probe + Grafana row per service** | v1.1 already built the alerting pipeline. Adding four probes is nearly free and closes the loop with Core Value ("I know before it becomes a problem") | LOW | Reuses validated v1.1 infrastructure |
| **Donetick `isRolling` used deliberately** | Chores like "clean the shower" should reschedule from when you actually did it, not from when it was due. Fixed-schedule chores (bin day) should not | LOW | A per-chore decision, but knowing the distinction up front prevents a wall of permanently-overdue chores |
| **Google Tasks importer with dry-run + idempotency map** | Donetick has no import-ref concept, so a naive re-run duplicates everything. A `googleTaskId -> choreId` map file makes the import safe to re-run and safe to abort | MEDIUM | Real engineering; see the import section |
| **Homebox seeded opportunistically, not bulk** | The behaviour that made Grocy fail is bulk up-front entry followed by drift. Entering an item at purchase time, once, is sustainable | LOW (a policy, not code) | Worth writing into the milestone doc as an explicit operating rule |

---

### Anti-Features

These respect the firm constraints in PROJECT.md. Several are things the upstream apps actively offer, which is exactly why they need naming.

| Feature | Why Requested | Why Problematic | Instead |
|---------|---------------|-----------------|---------|
| **Mealie AI / OpenAI import** (recipe OCR, video transcription) | Mealie ships it; scanning a cookbook page feels magical | Explicitly excluded by the milestone. Adds an external API dependency, an API key in SOPS, egress from a Tailscale-only host, and per-import cost | URL scraping covers hundreds of sites; manual entry for the rest |
| **HA integration for Mealie or Donetick** | Mealie has a first-party HA integration exposing the shopping list as a to-do entity. Genuinely the most useful integration available | Explicitly deferred to a later milestone. Pulling it in now means Mealie must be stable *and* an HA config change must land, coupling two systems during the highest-churn period | Ship the four services standalone. Revisit after a month of real use |
| **Any sync or glue between the four services** | Recipe to shopping list to inventory decrement is the obvious "complete" design | Firm constraint. It is also the exact mechanism by which Grocy-style systems drift: every cross-service write is a chance for state to diverge silently, and nobody debugs a household chore bot | Four independent apps. The human is the integration layer |
| **Homebox maintenance schedules** | Homebox ships recurring maintenance with notifications. "Change the furnace filter" feels like an inventory concern | Creates a **second chore system** competing with Donetick. Two places to look for "what needs doing" means neither gets checked. This is the no-glue constraint applied inside a single app | All recurring work goes in Donetick, including item maintenance. Homebox records *what you own*, not *what to do* |
| **Homebox CSV bulk import of everything you own** | Import/Export under Profile > Tools makes it look like a weekend project | This is the Grocy failure mode with a different noun. A 400-row inventory entered in one sitting is stale in three months and nobody reconciles it | Enter items at the moment of purchase or warranty registration. Accept that the inventory is partial and useful rather than complete and wrong |
| **Homebox built-in ZIP export as the primary backup** | It exists, it is scheduled, it is one checkbox | Proposal is explicit: second layer only. It is app-mediated, so it fails silently when the app fails, which is the case that matters | SQLite `.backup` / `VACUUM INTO` to the ZFS pool is primary. Enable the ZIP export as a secondary layer |
| **Actual end-to-end encryption** | It is offered, it sounds strictly safer | Threat model does not support it: Tailscale-only, single operator, ZFS-backed, no hosted third party. Costs are real: server-side backups become opaque ciphertext (undermining the demonstrated-restore requirement), a forgotten second password is unrecoverable, it cannot be turned off in place, and bank-sync tokens are stored outside the encryption anyway | Leave it off. Rely on Tailscale isolation, ZFS, and the backup/restore pipeline |
| **Actual OpenID for multi-user** | "Proper" per-user accounts | Requires an IdP this homelab does not have. Two people sharing finances need one shared file, not two identities with an access-control matrix. Experimental as of 25.1.0 | Shared server password in the household password manager |
| **Donetick points / gamification / approval workflow** | It is a headline feature | Designed for households with children. Between two adults it adds ceremony to every completion and creates a scoreboard nobody asked for | Leave `points` unset and `requireApproval` false |
| **Donetick notifications wired on day one** | Chores you are not reminded about do not get done | The chore set will churn heavily in month one. Alerts on an unstable set train people to dismiss them, and the dismissal habit outlives the churn | Leave unconfigured. Revisit once the chore list has been stable for a few weeks |
| **A second shopping list anywhere** | Donetick can hold a "buy milk" one-off; Homebox tracks things you own | Firm constraint, and splitting the list is how both lists die | Mealie's list only. The Mealie "Show All" toggle is what makes it actually shared |
| **Pantry / stock / expiry / barcode anything** | Every one of these apps has an adjacent feature that gestures at it | Firm constraint. Requires logging every consumption event to stay accurate, which is the drift-and-abandon pattern already evaluated and rejected | Two-bin physical reserve shelf. Not modelled in software |
| **Importing completed Google Tasks** | Completeness instinct | Donetick writes completion history through `POST /:id/do`, not at create time, so the timestamp would be "now" rather than the original date. You would manufacture a fake history | Import only `status: needsAction`. Archive the Takeout JSON as the historical record |
| **Public exposure / external ACME** | Access from outside the house | Firm constraint. Inbound reachability for an ACME challenge is exactly the hole the constraint forbids | Tailscale + firebat's existing `local_certs` local CA |

---

## Google Tasks to Donetick: Concept Mapping

**Confidence: HIGH on the Donetick side** (field names and enums read from upstream source).
**MEDIUM on the Takeout side** (the Google Tasks API `Task` resource is documented; Takeout's exact envelope is documented by third-party tooling and forensic write-ups, not by Google).

### Source shape

Google Takeout produces `Tasks.json`, structured as `items[]` (task lists), each containing its own `items[]` (tasks).
Task objects mirror the Google Tasks API `Task` resource, plus a Takeout-only `task_type` field (only `PERSONAL_TASK` observed in the wild).

### Which Donetick endpoint to write to (decisive finding)

Donetick exposes two create paths, and the documented one is a trap:

| Endpoint | Binds | Verdict |
|----------|-------|---------|
| `POST /eapi/v1/chore` | `ChoreLiteReq` = `{name, description, dueDate, createdBy}` **only**. Server hardcodes `frequencyType=once`, `assignStrategy=random`, assignee=creator | **Cannot create recurring chores, labels, subtasks or assignees.** This is the endpoint the public docs point at |
| `POST /api/v1/chores/` | Full `ChoreReq`: `name`, `frequencyType` (required), `frequency`, `frequencyMetadata`, `nextDueDate`, `isRolling`, `assignedTo`, `assignees[]`, `assignStrategy` (required), `isActive`, `notification`, `notificationMetadata`, `labelsV2`, `priority`, `completionWindow`, `points`, `description`, `subTasks[]`, `requireApproval`, `isPrivate`, `projectId`, `thingTrigger` | **Use this one.** It is guarded by `MultiAuthMiddleware`, which tries the `secretkey` API key *first* and only falls back to JWT, so the same API token works. No login flow needed |

This single fact determines whether the importer is a one-liner that loses everything or a real import.

### Field-by-field mapping

| Google Tasks field | Donetick target | Fidelity | Notes |
|--------------------|-----------------|----------|-------|
| Task list (`items[].title`) | `labelsV2` (a label per list) | Degraded | Donetick has no "list" concept. `projectId` also exists but is heavier. Labels are `{name, color, circleId}` and must be created first, then referenced by id |
| `title` | `name` | Exact | Google caps at 1024 chars |
| `notes` | `description` | Exact | Google caps at 8192 chars; Donetick `description` is TEXT |
| `due` | `nextDueDate` | **Lossy** | Google stores date only and *discards time of day* (unreadable and unwritable via the API). Donetick's full endpoint wants RFC3339. The importer must synthesise a time (recommend 09:00 in the host timezone) |
| (no `due`) | omit `nextDueDate`, set `frequencyType: once` | Exact | `nextDueDate` is only required when `isRolling` is set |
| `status: needsAction` | `isActive: true` | Exact | |
| `status: completed` + `completed` timestamp | **no target** | **Lost** | Completion history is written via `POST /api/v1/chores/:id/do`, not at create. Skip these (see anti-features) |
| `parent` (task id of parent) | `subTasks[]` entry on the parent chore | **Conditionally lossy** | Donetick `SubTask` = `{orderId, name, completedAt, completedBy, parentId}` and the `parentId` allows nesting. But a subtask is a checklist row on a chore, **not an independent task, and has no due date of its own.** Recommended rule: if the Google subtask has its own `due`, promote it to a top-level chore; otherwise nest it |
| `position` | `subTasks[].orderId` for nested items; nothing for top level | **Lost at top level** | Donetick orders by due date and priority, not by manual position |
| **recurrence** | `frequencyType` / `frequency` / `frequencyMetadata` | **Entirely lost** | The Tasks API `Task` resource has no recurrence field. Google materialises recurring tasks as separate instances, so the export contains repeats, not rules. There is nothing to translate |
| `links[]` (`type`, `link`, `description`) | nothing | Lost | Read-only pointers to Gmail / Chat / Keep. Optionally append the URL into `description` |
| `assignmentInfo` | `assignedTo` / `assignees[]` | N/A in practice | Only populated for tasks assigned from Docs/Chat. Set `assignedTo` to the importing user and pick `assignStrategy` by policy |
| `id`, `etag`, `kind`, `selfLink`, `webViewLink`, `hidden`, `deleted`, `task_type` | nothing | Dropped | Keep `id` **outside** Donetick in an idempotency map file |
| (no source) | `points`, `priority`, `completionWindow`, `requireApproval`, `isPrivate`, `isRolling`, `notification` | N/A | Leave at defaults. Do not invent values |

### What is lost in this migration, ranked

1. **Recurrence rules.** The export has no recurrence data at all. This is not a tooling gap that better parsing solves; the information is not in the file. Recurring chores must be re-authored by hand.
2. **Completion history.** Not settable at create; importing it would fabricate timestamps.
3. **Per-subtask due dates**, unless subtasks are promoted to top-level chores.
4. **Manual ordering** (`position`) at the top level.
5. **Task-list identity**, degraded from a container to a label.
6. **Links** to Gmail threads, Chat messages and Keep notes.
7. **Time-of-day on due dates**, which Google never stored in the first place.

### Recommended import strategy

Split the migration in two, because the two halves have completely different economics:

- **Automate the one-off todos.** These map cleanly (`title` to `name`, `notes` to `description`, `due` to `nextDueDate`, `frequencyType: once`). This is the bulk of the rows and the boring part.
- **Hand-author the recurring chores.** There is no source data to import, and there are typically only 10-30 of them. Re-entering them by hand is a feature, not a compromise: Donetick's frequency model (`days_of_the_week` with `week_of_month` occurrences, `interval` with arbitrary units, `adaptive`, `isRolling`) is strictly richer than anything Google Tasks could have expressed, so a mechanical translation would have produced worse chores than a human will. Donetick's natural-language "smart task creation" makes this fast.

Additional importer requirements:

- **Request the Takeout export early.** It is asynchronous and can take hours to days. It is a long-lead dependency on the Donetick phase and should be started before the phase begins.
- **Dry-run mode** printing the planned chores without writing.
- **Idempotency map** (`googleTaskId` to `choreId`) written to a local file. Donetick has no import-ref concept (unlike Homebox's `HB.import_ref`), so a naive re-run silently duplicates every task.
- **Filter to `status: needsAction`** and skip `deleted: true`.
- **Run once, then delete the script**, or keep it under `scripts/` clearly marked one-time. Per the repo's replace-don't-deprecate rule, a migration script that lingers as apparent infrastructure is dead code.

---

## Feature Dependencies

```
AdGuard A record ──requires──> agreed <name>.vofi naming
Caddy vhost ──requires──> AdGuard A record
                       └──requires──> service listening on localhost/Tailscale

Service usable ──requires──> impermanence persistence declared
                                 └──requires──> tmpfiles ownership rules
                                                (fresh boot creates empty dirs as root)

Nightly backup ──requires──> persistence (nothing to back up otherwise)
Demonstrated restore ──requires──> nightly backup
                                └──requires──> written bootstrap checklist
                                               (restored DB + no checklist = unusable instance)

Second user account ──requires──> registration OPEN at first boot   [Donetick, Homebox]
Registration CLOSED ──requires──> both accounts already created      [Donetick, Homebox]
   (Mealie is exempt: it ships a default admin, so signup stays closed throughout)

Shared meal plan + shopping list ──requires──> both Mealie users in the SAME household
Shared inventory ──requires──> second user joined Homebox group by INVITE, not self-registration
Shared chores ──requires──> both users in the SAME Donetick circle

Google Tasks import ──requires──> Donetick running
                              └──requires──> circle with both users
                              └──requires──> API token minted
                              └──requires──> Takeout export delivered  [LONG LEAD, start early]
                              └──requires──> POST /api/v1/chores (NOT /eapi/v1/chore)

Mealie shopping list actually usable ──requires──> Foods + Units seeded
                                              └──requires──> "Show All" toggle known/enabled

Blackbox probe ──enhances──> every service (reuses validated v1.1 alerting)

Actual E2E encryption ──conflicts──> demonstrated restore (server backup becomes ciphertext)
Homebox maintenance schedules ──conflicts──> Donetick recurring chores (two chore systems)
Homebox ZIP export ──conflicts──> "primary backup" framing (app-mediated, fails with the app)
```

### Dependency Notes

- **tmpfiles ownership is the classic impermanence bug.** Persistence declares the path; it does not declare who owns it. On a fresh boot the directory materialises owned by root and the service user cannot write. This fails at first-start of each service and is worth a single shared pattern across all four rather than four ad-hoc fixes.
- **The restore test depends on the bootstrap checklist, not just the backup.** Restoring Mealie's Postgres dump into a scratch instance proves the dump is valid. It does not prove you can rebuild a working service, because the household membership, seeded foods and invite state all live in that same database (which is good) while the Homebox group invite and Actual server password do not. Test the whole path.
- **Takeout is the only long-lead external dependency in the milestone.** Everything else is local. It should be requested during the Mealie phase so it has landed by the time Donetick is ready.
- **Mealie is the only service without a bootstrap ordering hazard**, because it self-creates a default admin. Donetick and Homebox both need a two-stage deploy. Actual sets its password interactively at first visit. Three services, three different bootstrap shapes: do not try to unify them.

---

## MVP Definition

### Launch With (this milestone)

Ordered. The proposal is explicit that these should not be built simultaneously, and that is correct: each service is an independent adoption bet, and shipping all four at once means discovering four sets of persistence bugs at the same time.

**1. Mealie (ship alone, then soak)**

- [ ] `services.mealie` with PostgreSQL, secrets from SOPS
- [ ] Persistence: Postgres data dir + recipe images/uploads dir, with tmpfiles ownership
- [ ] Caddy vhost + AdGuard record + Tailscale-only binding, with a negative access smoketest
- [ ] Bootstrap: default admin credentials changed, household created, second user invited into it
- [ ] Foods and Units seeded; "Show All" verified on the shopping list
- [ ] `BASE_URL` correct behind Caddy
- [ ] Nightly `pg_dump` + image dir backup to the ZFS pool
- [ ] **Demonstrated restore into a scratch instance**
- [ ] Reboot-twice persistence check
- [ ] Blackbox probe

Then stop. Real recipes get entered and a real week gets planned before anything else is deployed.
The proposal's fallback trigger is worth carrying into the roadmap verbatim: if ingredient-based search proves inadequate, evaluate Tandoor **before** the catalog grows large enough to make migration painful.

**2. Donetick + Google Tasks import**

- [ ] Packaging decision resolved (no nixpkgs module; container pinned by digest, or a written module)
- [ ] SQLite persisted; JWT secret from SOPS
- [ ] Two accounts, one circle, then `DONETICK_DISABLE_SIGNUP=true` (two-stage deploy)
- [ ] Caddy + DNS + Tailscale-only + negative test
- [ ] Backup via SQLite `.backup`/`VACUUM INTO`, restore demonstrated
- [ ] Importer against `POST /api/v1/chores/` with dry-run and an idempotency map
- [ ] Recurring chores hand-authored using Donetick's frequency model
- [ ] Blackbox probe

**3. Homebox and Actual Budget (either order, neither urgent)**

- [ ] Homebox: registration open, accounts created, **invite** for user two, registration closed. Analytics off, upload size raised, minimal location tree
- [ ] Actual: server password set, data dir persisted, one budget file, encryption explicitly declined, accounts and first month entered
- [ ] Backups + restore + probes + negative access tests for both

### Add After Validation (later milestone)

- [ ] Home Assistant Mealie integration (shopping list as an HA to-do entity). **Trigger:** Mealie has been in daily use for a month and the shopping list is the thing people reach for.
- [ ] Donetick notifications. **Trigger:** the chore list has been stable for several weeks with no additions or deletions.
- [ ] Actual SimpleFIN bank sync, configured in-app only. **Trigger:** the budget is being reconciled manually and the manual step is the bottleneck.
- [ ] Homebox asset IDs and printed QR labels. **Trigger:** the inventory is large enough that finding an item is slower than scanning one.

### Future Consideration (v2+, or never)

- [ ] Actual OpenID multi-user. Needs an IdP that does not exist here and solves a problem two people sharing finances do not have.
- [ ] Mealie OIDC. Same.
- [ ] Any cross-service integration. Currently a firm constraint; would need an explicit reversal with a stated reason.
- [ ] Tandoor migration. Only if Mealie's ingredient search proves inadequate, and only while the catalog is still small.

---

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| Mealie deployed with Postgres + shared household | HIGH | MEDIUM | P1 |
| Impermanence persistence + tmpfiles ownership (all four) | HIGH (data loss otherwise) | MEDIUM | P1 |
| Foods/Units seeded + "Show All" on shopping list | HIGH | LOW | P1 |
| Caddy vhost + AdGuard record (all four) | HIGH | LOW | P1 |
| Tailscale-only binding + negative access test | HIGH | LOW-MEDIUM | P1 |
| Nightly backups (pg_dump + SQLite `.backup`) | HIGH | MEDIUM | P1 |
| Demonstrated restore | HIGH | MEDIUM-HIGH | P1 |
| Secrets via SOPS | HIGH | LOW | P1 |
| Written bootstrap checklist per service | HIGH | LOW | P1 |
| Registration closed after bootstrap (all four) | MEDIUM | LOW | P1 |
| Donetick packaging (no nixpkgs module) | MEDIUM | MEDIUM-HIGH | P1 |
| Google Tasks import of one-off todos | MEDIUM | MEDIUM | P2 |
| Recurring chores hand-authored | HIGH | LOW (manual) | P2 |
| Homebox deployed with group invite flow | MEDIUM | LOW-MEDIUM | P2 |
| Actual deployed, one budget file, encryption declined | MEDIUM | LOW-MEDIUM | P2 |
| Reboot-twice persistence smoketest | MEDIUM | MEDIUM | P2 |
| Blackbox probes + Grafana row | MEDIUM | LOW | P2 |
| Homebox minimal location tree | LOW | LOW | P3 |
| Homebox ZIP export as secondary backup layer | LOW | LOW | P3 |
| Mealie taxonomy, cookbooks, planner rules | LOW (emerges from use) | LOW | P3 |

---

## Comparative Notes (How Similar Stacks Handle This)

| Concern | Grocy (rejected) | Tandoor | This stack's approach |
|---------|------------------|---------|------------------------|
| Pantry / consumption | Perpetual inventory; requires logging every consumption event | Optional inventory features | **None.** Physical two-bin reserve shelf. This is the decision that makes the stack survivable |
| Chores | Built in, coupled to inventory | None | Donetick, fully independent |
| Recipe search | Basic | Strong, Postgres-backed, mandatory Postgres | Mealie on Postgres. Tandoor is the documented fallback if ingredient search disappoints |
| Shopping list | Generated from stock deltas | Generated from meal plan | Mealie only, populated from the meal plan by a human |
| Integration model | One monolith, everything coupled | Semi-coupled | Four independent apps, human as the integration layer |

The reason the monolith loses here is not capability, it is failure mode.
A coupled system degrades everywhere at once when one input stops being maintained.
Four independent apps degrade independently, and an abandoned one can be deleted without touching the other three.

---

## Confidence Assessment

| Area | Confidence | Basis |
|------|------------|-------|
| Donetick chore model, enums, field names | HIGH | Read directly from upstream `internal/chore/model/model.go`, `handler.go`, `api.go`, `config/local.yaml` |
| Donetick eAPI vs internal API create-fidelity gap | HIGH | Read from `internal/chore/api.go` (`ChoreLiteReq`, hardcoded defaults) and `internal/auth/multiauthmiddleware.go` (API key tried before JWT) |
| Google Tasks field semantics, absence of recurrence | MEDIUM-HIGH | Official Tasks API `Task` resource; Takeout envelope corroborated by multiple independent converter tools |
| Mealie group/household scoping + shopping list "Show All" | MEDIUM-HIGH | Official docs cross-checked against maintainer comments in discussions #2134, #5425, #5452 |
| Mealie default admin credentials | MEDIUM | Widely corroborated across install guides and issue reports; not stated in the current official FAQ |
| Homebox registration flag and lockout hazard | MEDIUM | Official env var documented; the lockout warning comes from the older archived docs and conflicts with current maintainer guidance. **Treat as real until tested** |
| Actual password-auth single-identity model, E2EE tradeoffs | MEDIUM-HIGH | Official config and sync docs, plus 25.1.0 release notes for the OpenID multi-user path |
| nixpkgs module availability (mealie/homebox/actual yes, donetick no) | HIGH | `nixos/modules/module-list.nix` on the `nixos-25.11` branch |

### Gaps

- Whether Homebox's registration flag can be safely re-enabled after being disabled. Sources conflict. **Test on a scratch instance before flipping it on the real one.**
- Whether the NixOS `services.mealie` module surfaces `DEFAULT_EMAIL`/`DEFAULT_PASSWORD` at first init, or whether the bootstrap must go through the stock `changeme@example.com` account. Affects the bootstrap checklist, not the design.
- Exact Takeout `Tasks.json` envelope. Google does not document it. Inspect the real export before writing the parser rather than coding against an assumed schema.
- Whether Actual's server password can be set non-interactively. Not found in the config docs; assume interactive first-visit setup.

## Sources

- Mealie docs: FAQ, Backend Configuration, Features, Permissions and Public Access (`docs.mealie.io`)
- Mealie discussions #2134 (households design), #4252 (household-targeted invites), #5425 / #5452 (shopping list sharing), #6893 (multi-household)
- Donetick upstream source (`github.com/donetick/donetick`, `main`): `internal/chore/model/model.go`, `internal/chore/handler.go`, `internal/chore/api.go`, `internal/subtask/model/model.go`, `internal/label/model/model.go`, `internal/circle/model/model.go`, `internal/auth/multiauthmiddleware.go`, `config/config.go`, `config/local.yaml`
- Donetick docs: `docs.donetick.com/advance-settings/api/`
- Google Tasks API `Task` resource reference (`developers.google.com/tasks/reference/rest/v1/tasks`); Takeout envelope corroborated by `exploids/google-tasks-to-todoist`, `Nockiro/gtask-exporthelper`, `thethales/GoogleTasksJSONtoTXT`
- Homebox docs (`homebox.software`), Homebox CSV import reference, `sysadminsmedia/homebox` discussions
- Actual Budget docs: Configuration, Syncing Across Devices, Managing Multi-User Support, Authenticating With an OpenID Provider; release notes 25.1.0
- nixpkgs `nixos-25.11` `nixos/modules/module-list.nix`

---
*Feature research for: self-hosted household stack on NixOS (v1.2)*
*Researched: 2026-08-16*
