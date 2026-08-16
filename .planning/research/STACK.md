# Stack Research — v1.2 Household Stack

**Domain:** Self-hosted household web apps on an existing NixOS homelab (ser8 app host + firebat Caddy gateway)
**Researched:** 2026-08-16
**Confidence:** HIGH for nixpkgs module/package facts (read directly from the pinned nixpkgs source trees in the local Nix store and from `raw.githubusercontent.com/NixOS/nixpkgs` branch heads). HIGH for Donetick API surface (read from upstream Go source). MEDIUM for Google Takeout field-level detail (confirmed against a community sample + the official Tasks API reference, not against this household's actual export).

> Prior milestone research (v1.1 monitoring/alerting) archived to `.planning/research/archive/v1.1-STACK.md`.

---

## Headline: the flake is on an EOL channel and that gates everything below

`flake.nix` pins `nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11"`, locked at `e4bae1bd10c9` (2026-01-16).
NixOS 25.11 "Xantusia" reached end of life on **2026-06-30** — it has received no security updates for ~7 weeks as of this research.
26.05 "Yarara" is the only supported release (supported through 2026-12-31).

This is not a tangent: for three of the four services the 25.11 packages are meaningfully worse than the 26.05 ones, and for Actual the 26.05 *module* is materially better.
Treat "bump `nixpkgs` to `nixos-26.05`" as a precondition phase for this milestone rather than as separate maintenance work.

**Known cost:** the `nixos-raspberrypi` input is deliberately pinned to `a12cce571003` because its `main` moved to upstream 25.11 where `boot.loader.raspberryPi` is removed (see the comment in `flake.nix`).
The Pi hosts consume `nixos-raspberrypi`'s own nixpkgs fork (`nixpkgs_2` = `nvmd/nixpkgs` @ `59714dfc31ef`), so bumping the top-level `nixpkgs` primarily risks the shared `modules/` used by pi4/pi5.
Scope the bump as its own phase with `make check` + `make dry-activate-pi4` gates before touching household services.

**Fallback if the channel bump is deferred:** stay on 25.11 modules and override only `services.<svc>.package` from the already-present `nixpkgs-unstable` input (which `flake.nix` already threads into hosts as `unstable` at lines 188/218).
This works for Mealie and Actual; see the per-service notes for the caveat on Homebox.

---

## Recommended Stack

### Core Technologies

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| `nixpkgs` @ `nixos-26.05` | 26.05 | Base channel for ser8 | 25.11 is EOL (2026-06-30). 26.05 also carries newer Mealie/Actual and the improved `services.actual` module. Non-negotiable for a security-relevant milestone. |
| `services.mealie` (native module) | module identical in 25.11 / 26.05 / master | Recipe manager | Native module exists, handles PostgreSQL wiring, `EnvironmentFile` secrets, and DB init out of the box. No container needed. |
| `pkgs.mealie` | **use 3.22.0** via package override (26.05 ships 3.16.0; 25.11 ships 3.9.2) | Mealie app | 25.11's 3.9.2 is ~13 minor releases and ~9 months behind upstream v3.22.0 (2026-07-28). The module is byte-identical across branches, so a package-only override is safe. |
| `services.actual` (native module) | **26.05 module** | Budgeting | 26.05 adds `user`/`group` (opt out of `DynamicUser`), promotes `dataDir`/`serverFiles`/`userFiles` to real options, and adds `ReadWritePaths` for them. The 25.11 module hard-codes all three. |
| `pkgs.actual-server` | 26.7.0 (26.05) — upstream is 26.8.1 | Actual Budget app | One month behind upstream is fine; Actual ships monthly and the server is backward compatible with older budget files. Not worth an overlay. |
| `services.homebox` (native module) | 26.05 module | Inventory | Native module with static `homebox` user, SQLite defaults, and `HBOX_OPTIONS_ALLOW_REGISTRATION = "false"` already the default — exactly the milestone requirement. |
| `pkgs.homebox` | **0.25.0 (26.05/master). Do NOT chase upstream 0.26.x** | Homebox app | 0.26 is the items+locations→entities rewrite: it replaces `/v1/items*` and `/v1/locations*` with `/v1/entities*` and **refuses to start without `HBOX_AUTH_API_KEY_PEPPER`** (≥32 chars), which the nixpkgs module does not set. Wait for nixpkgs to carry 0.26 with a matching module change. |
| `virtualisation.oci-containers` (podman backend) | NixOS 26.05 | Donetick runtime | **No Donetick package or module exists in nixpkgs on any branch.** Only nixpkgs PR #551607 ("donetick: init at 0.1.76", opened 2026-08-11, still open, package-only, no module). Container is the only sane option. |
| `docker.io/donetick/donetick` | `v0.1.76` @ `sha256:2f32646ef4e613f44066163646f53c02d6d5b728b31abe47dfd111b3dfd53643` | Donetick app | Upstream latest stable release (2026-07-26). Digest verified against Docker Hub registry on 2026-08-16. Pin by digest — the tag list is full of `-beta.N` tags and upstream reuses tags. |
| `services.postgresql` (via `services.mealie.database.createLocally = true`) | 26.05 default | Mealie backing store | The Mealie module wires this itself: creates the `mealie` DB + role with `ensureDBOwnership`, and sets `POSTGRES_URL_OVERRIDE = "postgresql://mealie:@/mealie?host=/run/postgresql"` (peer auth over the unix socket, no password anywhere). |

### Supporting Libraries / Tooling

| Tool | Version | Purpose | When to Use |
|------|---------|---------|-------------|
| `pkgs.sqlite` | 26.05 | `.backup` / `VACUUM INTO` for Donetick, Homebox, Actual `account.sqlite` | Required on ser8 for the nightly backup phase. Not currently in `environment.systemPackages`. |
| `pg_dump` (from `services.postgresql`) | 26.05 | Mealie logical backup | Already on PATH once postgres is enabled. Run as the `postgres` user via a systemd timer. |
| `pkgs.python3` (stdlib only: `json`, `urllib.request`, `datetime`) | 26.05 | Google Tasks → Donetick import script | The import needs JSON parsing, date arithmetic and a JWT login round-trip. Bash + `jq` + `curl` also works, but date/recurrence mapping is fiddly enough to justify Python. **No third-party deps — do not pull in `requests` or `google-api-python-client`.** |
| `sops-nix` (already in flake) | current pin | `DT_JWT_SECRET`, optional Mealie SMTP/OIDC creds | Existing pattern: `sops.secrets.<name>` → path consumed via `EnvironmentFile` or `$__file{}`. |
| `prometheus-blackbox-exporter` (already on firebat) | current | HTTP probes for the four new vhosts | The existing blackbox target list just needs four new entries. No new component. |

### Development / Validation Tools

| Tool | Purpose | Notes |
|------|---------|-------|
| `make check` | flake checks + statix + dry-run host builds | Run after the channel bump *before* adding services. |
| `make dry-activate-ser8` / `make test-ser8` | Non-destructive activation | `test-ser8` is the right gate for the first deploy of each service (does not touch the boot default). |
| `scripts/smoketests/` | Per-area smoketests wired via `deploy.yaml` | Add household smoketests — but note `deploy.yaml` allows only **one** smoketest entry per host and ser8's is already `./scripts/smoketests/media/all.sh`. Either fan out from `media/all.sh` or introduce a top-level `ser8/all.sh`. Flag for the roadmapper. |

---

## Per-Service Detail

### 1. Mealie — native module, override the package

**Module:** `nixos/modules/services/web-apps/mealie.nix`. Verified **byte-identical** across `nixos-25.11`, `nixos-unstable` (26.05) and `master`. That stability is what makes the package override safe.

**Options that matter:**

| Option | Default | Notes |
|--------|---------|-------|
| `listenAddress` | `"0.0.0.0"` | Caddy on firebat reaches ser8 over the LAN, so leave as-is and open the port; see "Ports" below. |
| `port` | `9000` | Free on ser8 (no collision with 8080/9134/445/139 or any media port). |
| `settings` | `{}` | `attrsOf anything`, stringified and injected as the systemd `environment`. This is where `BASE_URL`, `ALLOW_SIGNUP`, `TZ` go. |
| `credentialsFile` | `null` | `EnvironmentFile=` format. **This is the sops seam.** |
| `database.createLocally` | `false` | Set `true`. |
| `extraOptions` | `[]` | Gunicorn args, e.g. `[ "--log-level" "debug" ]`. |

**PostgreSQL wiring (the module does all of it):**

```
services.postgresql.enable = true;
services.postgresql.ensureDatabases = [ "mealie" ];
services.postgresql.ensureUsers = [ { name = "mealie"; ensureDBOwnership = true; } ];
services.mealie.settings.DB_ENGINE = "postgres";
services.mealie.settings.POSTGRES_URL_OVERRIDE = "postgresql://mealie:@/mealie?host=/run/postgresql";
```

Unix-socket peer auth, no password, nothing secret. The unit gets `requires`/`after` on `postgresql.target`, and `ExecStartPre = ${pkg}/libexec/init_db` runs migrations.
Note the empty-but-present `:` before `@` in the URL — upstream Mealie's URL parser needs it (mealie-recipes/mealie#3573).

**What the module gets wrong for this deployment:**
`BASE_URL` is hard-coded to `http://localhost:${port}`.
Behind `mealie.vofi` on the Caddy gateway this breaks password-reset links, share links, and OIDC redirects.
**Override it:** `services.mealie.settings.BASE_URL = "https://mealie.vofi";`

**Secrets:** with `createLocally = true` there is no DB password. `credentialsFile` is only needed if the household wants SMTP invites (`SMTP_HOST`, `SMTP_USER`, `SMTP_PASSWORD`) or OIDC. The repo already has `gmail_smtp_password` in sops for ser8 (used at `hosts/ser8/configuration.nix:133`) — reuse that pattern rather than minting a new secret.

**Persistence:** `DynamicUser = true` + `StateDirectory = "mealie"` ⇒ the real directory is **`/var/lib/private/mealie`**, with `/var/lib/mealie` as a symlink. `DATA_DIR` is set to `/var/lib/mealie`.
`hosts/ser8/impermanence.nix` **already persists `/var/lib/private`** (mode `0700`) and **already persists `/var/lib/postgresql`**. Mealie therefore needs **zero new impermanence entries**. This is the single biggest "already solved" finding in this research.

**Package override:**

```nix
services.mealie.package = unstable.mealie;  # `unstable` is already threaded into hosts by flake.nix
```

The `nixpkgs-unstable` input is currently locked at `d233902339c0` (2026-05-15), which carries mealie **3.12.0**. Bump that input to reach **3.22.0**. The master expression rebuilt the frontend inline (`fetchYarnDeps` + `dart-sass` instead of the old `mealie-frontend.nix`) but still emits `$out/bin/mealie` and `$out/libexec/init_db`, which is the entire contract the module depends on.

**Migration direction is one-way.** Mealie runs Alembic migrations on start and does not support downgrade. Start on the version you intend to keep; do not stand up 3.9.2 "to test" and then jump to 3.22.0 with real household data unless a `pg_dump` exists first.

---

### 2. Donetick — OCI container, digest-pinned (no native option exists)

**Verified absent from nixpkgs:** `pkgs/by-name/do/donetick/package.nix` and `nixos/modules/services/web-apps/donetick.nix` both 404 on `master`; neither exists in the locked 25.11 tree nor in the 26.05/unstable tree. The only activity is **open** PR `NixOS/nixpkgs#551607` (package only, five files, no module, opened 2026-08-11).
Do not plan around that PR landing.

**Recommended:**

```nix
virtualisation.oci-containers.backend = "podman";
virtualisation.oci-containers.containers.donetick = {
  image = "docker.io/donetick/donetick:v0.1.76@sha256:2f32646ef4e613f44066163646f53c02d6d5b728b31abe47dfd111b3dfd53643";
  # ...
};
```

**This introduces a new capability to the repo.** `rg 'oci-containers|virtualisation.docker|podman'` returns nothing — there is currently no container runtime configured on any host, even though `/var/lib/docker` is (vestigially) in the impermanence list. Budget a phase step for enabling podman, the rootless/rootful decision, and `/var/lib/containers` persistence.

**Configuration format:** YAML at `/config/selfhosted.yaml`, selected by `DT_ENV=selfhosted`, loaded through **viper**, which means **every key is overridable by a `DT_`-prefixed env var**. Prefer env vars over templating the YAML — it keeps secrets out of the Nix store.

Key settings (from upstream `config/selfhosted.yaml`):

| Setting | Env override | Value for this deployment |
|---------|--------------|---------------------------|
| `database.type` | `DT_DATABASE_TYPE` | `sqlite` |
| (sqlite file) | `DT_SQLITE_PATH` | `/donetick-data/donetick.db` (bind-mounted from `/var/lib/donetick`) |
| `jwt.secret` | `DT_JWT_SECRET` | **32-char random.** sops secret → `environmentFiles`. Placeholder default is `change_this_to_a_secure_random_string_32_characters_long`. |
| `server.port` | `DT_SERVER_PORT` | `2021` (free on ser8) |
| `server.serve_frontend` | `DT_SERVER_SERVE_FRONTEND` | `true` (a `false` here is the classic "404 on the web UI" cause) |
| `server.public_host` | `DT_SERVER_PUBLIC_HOST` | `https://donetick.vofi` |
| `is_user_creation_disabled` | `DT_IS_USER_CREATION_DISABLED` | `true` **after** the household accounts exist |
| `single_circle_instance` | `DT_SINGLE_CIRCLE_INSTANCE` | `true` — one household circle, hides circle join/leave UI. Matches the milestone's "no integration layer, one household" framing. |
| `realtime.enabled` | — | leave `true`; SSE. Caddy needs no special config for SSE, unlike WebSocket. |

Also bind-mount `/usr/share/zoneinfo:ro` and set `TZ` — without it, recurring chores schedule in UTC.

Health endpoint: `GET /api/v1/health` on `:2021` — use it for the smoketest and the blackbox probe.

**Persistence:** new impermanence entry `/var/lib/donetick` (owned by whatever uid the container runs as), plus the container-runtime state dir.

**Caveat worth flagging to the roadmapper:** multiple upstream reports describe the Donetick **mobile app** refusing to pair with a self-hosted server behind a self-signed / private CA. firebat uses Caddy `local_certs` (a local CA). If mobile-app use is desired, that is a known friction point — plan for browser/PWA use, or accept installing the Caddy root CA on the phones.

**API surface for the import — read the source, not the docs:**

There are two APIs and only one of them can do what this milestone needs.

| API | Auth | Verdict |
|-----|------|---------|
| `eapi/v1/chore` (external, "API token") | `APITokenMiddleware` | **Unusable for the import.** `POST` (`internal/chore/api.go:CreateChore`) hard-codes `FrequencyType: chModel.FrequencyTypeOnce` and `AssignStrategy: random`, and the frequency field is literally commented out. Worse, `PUT /:id` and `POST /:id/complete` sit behind `RequirePlusMemberMiddleware` (paid tier), so you cannot even fix up the frequency afterwards. |
| `api/v1/chores` (internal, frontend) | JWT from `POST /api/v1/auth/login` | **Use this.** `ChoreReq` (`internal/chore/handler.go:306`) accepts the full model. |

`POST /api/v1/chores` body fields relevant to the import:

- `name` (required)
- `frequencyType` (required, one of `once daily weekly monthly yearly adaptive interval days_of_the_week day_of_the_month trigger no_repeat`)
- `frequency` (int)
- `frequencyMetadata`: `{ days[], months[], unit (hours|days|weeks|months|years), time (RFC3339), timezone, weekPattern (every_week|week_of_month|week_of_quarter), occurrences[] }`
- `nextDueDate` (RFC3339; required when `isRolling`)
- `assignStrategy` (required, one of `no_assignee least_assigned least_completed random keep_last_assigned random_except_last_assigned round_robin`)
- `assignees[]`, `assignedTo`, `description`, `priority`, `points`, `labelsV2[]`, `subTasks[]`, `isPrivate`, `isActive`

Auth flow: `POST /api/v1/auth/login` (the enhanced handler; `/api/v1/auth/login/legacy` also exists), then `Authorization: Bearer <jwt>` on `api/v1/chores`.
Session lifetime is `168h` by default — plenty for a one-shot script.
Rate limit is `300 / 60s` (`server.rate_limit` / `rate_period`) — a few hundred tasks is fine, but throttle to be safe.

---

### 3. Homebox — native module, pin to 0.25.0

**Module:** `nixos/modules/services/web-apps/homebox.nix`. The 25.11→26.05 diff is a **single line**: `HBOX_OPTIONS_CHECK_GITHUB_RELEASE` renamed to `HBOX_OPTIONS_GITHUB_RELEASE_CHECK` (upstream renamed the env var between 0.24 and 0.25).

**Options:** `enable`, `package`, `user` (default `homebox`), `group`, `settings` (freeform `attrsOf (nullOr str)` → env vars), `database.createLocally`.

Module-supplied defaults (all `mkDefault`, so overridable):
`HBOX_STORAGE_CONN_STRING = "file:///var/lib/homebox"`, `HBOX_STORAGE_PREFIX_PATH = "data"`, `HBOX_DATABASE_DRIVER = "sqlite3"`, `HBOX_DATABASE_SQLITE_PATH = "/var/lib/homebox/data/homebox.db?_pragma=busy_timeout=999&_pragma=journal_mode=WAL&_fk=1"`, `HBOX_OPTIONS_ALLOW_REGISTRATION = "false"`, `HBOX_MODE = "production"`, `HOME = "/var/lib/homebox"`, `TMPDIR = "/var/lib/homebox/tmp"`.

**The milestone requirement "registration disabled after initial accounts" is the module default.** That means *initial* account creation needs `HBOX_OPTIONS_ALLOW_REGISTRATION = "true"` temporarily, then a flip back. Plan that as an explicit two-step in the phase, not an afterthought.

Default web port is **7745** (`conf:"default:7745"` in `backend/internal/sys/config/conf.go`). Free on ser8.

**Persistence — this one needs work.** Unlike Mealie/Actual, Homebox uses a **static `homebox` user**, so `StateDirectory = "homebox"` resolves to a real `/var/lib/homebox`, *not* `/var/lib/private/homebox`.
Add an explicit `environment.persistence."/persist".directories` entry for `/var/lib/homebox`, plus a `systemd.tmpfiles` ownership rule mirroring the existing pattern (e.g. `"d /persist/var/lib/homebox 0700 homebox homebox -"`).
Attachments live under `/var/lib/homebox/data/<uuid>/documents` — inside the same tree, so one entry covers DB + blobs.

**Stay on 0.25.0.** Upstream v0.26.2 (2026-06-14) is the entity merge:
- `/v1/items*` and `/v1/locations*` → `/v1/entities*`
- **requires** `HBOX_AUTH_API_KEY_PEPPER` (≥32 random chars) or the server will not start — the nixpkgs module does not set it, so a naive package overlay to 0.26 produces a boot loop
- upstream explicitly says skip 0.26.0 (broken attachments) and go to 0.26.1+
- carries a security advisory patch (GHSA-r9pf-rg22-655m)

Since nixpkgs `master` is *also* still on 0.25.0, there is no low-risk path to 0.26 in this milestone. Revisit when nixpkgs lands 0.26 with a module that sets the pepper from a secret file.

---

### 4. Actual Budget — native module, use the 26.05 module

**Module:** `nixos/modules/services/web-apps/actual.nix`. The 26.05 module is a real improvement over 25.11:

| | 25.11 | 26.05 |
|---|---|---|
| `user` / `group` | not options; always `DynamicUser` | `nullOr str`, `null` ⇒ `DynamicUser` |
| `settings.dataDir` | hard-coded `/var/lib/actual` via `mkDefault` inside a `config` block | a real `types.str` option |
| `settings.serverFiles` / `userFiles` | same | real options, defaulting off `dataDir` |
| `ReadWritePaths` | absent (with `ProtectSystem = "strict"`) | set to the three dirs |

**Recommendation: keep `DynamicUser` (leave `user`/`group` at `null`).** That puts state at `/var/lib/private/actual`, which the existing impermanence config already persists. Setting an explicit user buys nothing here and would require a new impermanence entry.

**Secrets:** `settings` is a JSON freeform submodule processed by `utils.genJqSecretsReplacementSnippet`, so any value can be written as `{ _secret = config.sops.secrets.foo.path; }` and is materialised at runtime into `/run/actual/config.json`, never into the Nix store. Use this if OIDC is ever wired up. The Actual *server password* is set in-app on first visit, not in config — and per PROJECT.md, SimpleFIN bank sync is explicitly configured in-app only, so no secret is strictly required at deploy time.

Defaults: `hostname = "::"`, `port = 3000`. Port 3000 is free on ser8 (Grafana's 3000 is on firebat, AdGuard's on pi4).

**Version:** 26.05 ships 26.7.0; upstream is 26.8.1 (2026-08-07). One release behind. Accept it — no overlay.

---

## Google Tasks → Donetick Import

### Verdict: Google Takeout JSON, plus an operator-authored recurrence map

**Takeout vs Tasks API.** Use **Takeout**. Rationale:

| | Takeout JSON | Tasks API v1 |
|---|---|---|
| Setup cost | zero — download a zip | GCP project + OAuth client + consent screen + token dance |
| Data completeness | same field set as the API | same field set |
| Repeatable | no (manual re-export) | yes |
| Recurrence data | **none** | **none** |

Since neither source has recurrence and this is a **one-time** import, the API's only advantage (repeatability) is worthless here. Takeout wins on setup cost.

**Shape of `Tasks.json`:**

```json
{
  "kind": "tasks#taskLists",
  "items": [
    {
      "kind": "tasks#taskList",
      "id": "...", "title": "My list", "updated": "...", "selfLink": "...",
      "items": [
        { "kind": "tasks#task", "id": "...", "title": "...", "notes": "...",
          "due": "2026-08-20T00:00:00.000Z", "status": "needsAction",
          "updated": "...", "task_type": "...", "selfLink": "...",
          "parent": "...", "position": "...", "deleted": false, "hidden": false,
          "links": [] }
      ]
    }
  ]
}
```

i.e. the Tasks API v1 `Task` resource nested one level under each task list.

### The critical finding: recurrence is not exportable

The Google Tasks API v1 `Task` resource is exactly: `kind, id, etag, title, updated, selfLink, parent, position, notes, status, due, completed, deleted, hidden, links[], webViewLink, assignmentInfo`.
**There is no `recurrence`, `repeat`, or `rrule` field, in the API or in Takeout.**
Recurring Google Tasks appear only as their currently-materialised instance. Google Takeout's Calendar export does not include Tasks either, so there is no side channel.

Also note `due` carries **date only** — "Only date information is recorded; the time portion is discarded." Every imported due date will need a household-chosen time-of-day.

**Therefore the import is a two-input process:**

1. `Tasks.json` from Takeout → the task inventory (title, notes, due, status, list).
2. A hand-authored `recurrence-map.yaml` (or CSV) checked into the repo, keyed by task title or Google task id, mapping the recurring ones onto Donetick's `frequencyType` + `frequency` + `frequencyMetadata`.

Anything not in the map imports as `frequencyType: "once"` (a one-off todo), which is exactly the milestone's "mix of one-off todos and recurring chores" split.

**Do not build a recurrence inference heuristic from task titles.** It will be wrong, silently, on a small dataset where hand-mapping takes minutes.

**Import mechanics:**

1. `POST /api/v1/auth/login` → JWT
2. For each task: `POST /api/v1/chores` with `Authorization: Bearer <jwt>`, body built from the Takeout record + the recurrence map
3. Filter out `status == "completed"` and `deleted == true` unless the household explicitly wants history
4. Map Google list titles → Donetick `labelsV2` or `projectId` (Donetick has both; labels are simpler and don't require pre-creating projects)
5. Sleep ~250ms between requests (rate limit is 300/60s)
6. Make the script **idempotent-by-refusal**: `GET /api/v1/chores` first, skip names that already exist. A one-shot script that double-runs is the classic way to get 400 duplicate chores.

Run it **after** Donetick has real accounts and **before** flipping `DT_IS_USER_CREATION_DISABLED`.

---

## Integration With Existing ser8 / firebat Infrastructure

### Ports (all verified free on ser8)

| Service | Port |
|---------|------|
| Mealie | 9000 |
| Donetick | 2021 |
| Homebox | 7745 |
| Actual | 3000 |

ser8's `networking.firewall.allowedTCPPorts` currently lists `8080, 9134, 445, 139`. Caddy on firebat reaches ser8 over the LAN, so **these four ports must be opened on ser8's firewall** (or fronted by a local nginx like the qBittorrent/NordVPN pattern). Opening four LAN ports is simpler and consistent with how the *arr services are already reached.

### Caddy (`modules/gateway/Caddyfile`)

Four new blocks following the existing `<service>.vofi` pattern:

```
mealie.vofi   { reverse_proxy ser8.local:9000 }
donetick.vofi { reverse_proxy ser8.local:2021 }
homebox.vofi  { reverse_proxy ser8.local:7745 }
actual.vofi   { reverse_proxy ser8.local:3000 }
```

**If any of these ever gets a Tailscale-bound node, switch that block to `192.168.68.65`** — the Caddyfile's own comment block documents that `.local` mDNS resolution fails from Tailscale-bound Caddy contexts ("device or resource busy").

No WebSocket header dance needed — Donetick uses SSE (plain HTTP), and none of the four need the Frigate/HA `header_up Upgrade` treatment.
Run `make fmt-caddy` after editing.

### AdGuard (`modules/dns/adguard-home.nix`)

Four `rewrites` entries pointing at **`192.168.68.63`** (firebat), matching every existing `*.vofi` entry.

### Impermanence (`hosts/ser8/impermanence.nix`)

| Path | Needed? | Why |
|------|---------|-----|
| `/var/lib/private` | **already present** | Covers Mealie *and* Actual (both `DynamicUser`) |
| `/var/lib/postgresql` | **already present** | Covers Mealie's DB |
| `/var/lib/homebox` | **ADD** | Static user ⇒ real path. Add a tmpfiles ownership rule too. |
| `/var/lib/donetick` | **ADD** | Container bind-mount target |
| container runtime state (`/var/lib/containers` for podman) | **ADD** | `/var/lib/docker` is already listed but podman uses a different path |

### Backups (nightly → ZFS backup pool at `/mnt/backups`)

`modules/servers/backup.nix` is currently a stub (a template shell script in `/etc/backup/`, plus borg/restic/rsync installed but unwired). This milestone will be its first real consumer.

| Service | Method | Gotcha |
|---------|--------|--------|
| Mealie | `pg_dump` (as `postgres`) + copy `/var/lib/private/mealie` | The DB alone is **not** a complete backup — recipe images and uploaded files live on disk. |
| Donetick | `sqlite3 donetick.db ".backup /mnt/backups/..."` | WAL mode; `.backup` is correct, plain `cp` is not. |
| Homebox | `sqlite3 ... ".backup"` + copy `/var/lib/homebox/data/<uuid>/documents` | Same split: DB + attachment blobs. |
| Actual | copy `server-files/account.sqlite` **and** the whole `user-files/` tree | **The budget data is opaque binary blobs in `user-files/`, not in the SQLite DB.** `account.sqlite` only holds the hashed server password, the file registry, and the session token. A SQLite-only backup of Actual restores nothing useful. This is the highest-risk backup mistake in this milestone. |

Stop the units (or at minimum quiesce writes) around the copy, or accept a `.backup`-consistent DB alongside possibly-torn blob files.

### Monitoring (firebat)

Add the four `*.vofi` URLs to the existing Prometheus blackbox target list in `modules/gateway/`. Donetick has a real health endpoint (`/api/v1/health`); the other three should be probed on `/` with a 200/302 expectation.

---

## Alternatives Considered

| Recommended | Alternative | When to Use Alternative |
|-------------|-------------|-------------------------|
| Bump flake to `nixos-26.05` | Stay on 25.11 + per-package overlays from `nixpkgs-unstable` | Only if the Pi-host risk from the `nixos-raspberrypi` pin turns out to be unbounded. Works for Mealie and Actual; for Homebox it silently sets the *old* env var name (`HBOX_OPTIONS_CHECK_GITHUB_RELEASE`) against a 0.25 binary that expects the new one, re-enabling outbound GitHub release checks. Cosmetic, but it's the kind of drift that rots. |
| Donetick as OCI container | Package Donetick in-repo (`buildGoModule` + npm frontend) and hand-write a systemd module | If the household wants a fully native, no-container ser8, or if PR #551607 stalls indefinitely. The upstream PR's `package.nix` is a usable starting point. Cost: a Go + Node derivation to maintain plus a hand-rolled module — real ongoing work for one app. |
| Donetick as OCI container | Wait for nixpkgs PR #551607 | Do not. It is package-only (no module), opened five days before this research, and would still leave you writing the systemd unit. |
| Mealie 3.22.0 via package override | Ship 26.05's 3.16.0 as-is | Perfectly defensible if the milestone values "one channel, no overlays" over four months of Mealie fixes. 3.16.0 is not a bad version. Do **not** ship 25.11's 3.9.2. |
| Mealie + PostgreSQL | Mealie + SQLite (`DB_ENGINE = "sqlite"`) | Never here — PROJECT.md explicitly scopes Mealie to PostgreSQL, and `database.createLocally = true` makes PG genuinely zero-effort (peer auth, no password, module-managed role). |
| Homebox on SQLite | `services.homebox.database.createLocally = true` (PostgreSQL) | Only if item/attachment volume grows past what SQLite is comfortable with — which for a household durable-goods inventory is never. Milestone says SQLite; the module's SQLite defaults are well-tuned (WAL, busy_timeout, FKs on). |
| Actual with `DynamicUser` | Explicit `user`/`group` (26.05 only) | Only if a backup script needs a stable uid to read the state dir. Prefer running the backup as root and reading `/var/lib/private/actual`. |
| Google Takeout | Google Tasks API v1 | Only if the import needs to be re-runnable over months. It isn't — this is explicitly a one-time import. Neither source has recurrence, so the API buys nothing. |
| Python stdlib import script | `google-api-python-client` / `requests` | Never. Adds OAuth machinery and dependencies for a script that makes ~N HTTP POSTs against a local service. |

---

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| `nixpkgs` @ `nixos-25.11` | EOL 2026-06-30; no security updates. Also carries Mealie 3.9.2 (9 months stale). | `nixos-26.05` |
| Homebox 0.26.x (any source) | Requires `HBOX_AUTH_API_KEY_PEPPER`, which no nixpkgs module sets ⇒ boot loop. Entity-merge rewrite replaces `/v1/items*` + `/v1/locations*`. nixpkgs master is still on 0.25.0 anyway. | `pkgs.homebox` 0.25.0 from 26.05 |
| Donetick `eapi/v1/chore` for the import | `CreateChore` hard-codes `FrequencyType: once`; `PUT /:id` and `POST /:id/complete` are gated behind `RequirePlusMemberMiddleware`. Cannot create or repair recurring chores. | `POST /api/v1/chores` with a JWT from `POST /api/v1/auth/login` |
| Donetick image by mutable tag (`:latest`, `:v0.1.76` without digest) | 85 tags on Docker Hub with heavy `-beta.N` churn (`v0.1.78-beta.2` already published). Tag reuse is real. | `v0.1.76@sha256:2f32646ef4e613f44066163646f53c02d6d5b728b31abe47dfd111b3dfd53643` |
| Mealie's default `BASE_URL` | Module hard-codes `http://localhost:9000`; breaks reset/share links and OIDC redirects behind Caddy. | `services.mealie.settings.BASE_URL = "https://mealie.vofi"` |
| SQLite-only backup of Actual | Budget data is binary blobs in `user-files/`, not in `account.sqlite`. A restore from the DB alone yields an empty server. | `account.sqlite` **plus** the whole `user-files/` tree |
| `cp` of a live SQLite DB | All three SQLite services run WAL mode; a raw copy can be torn. | `sqlite3 <db> ".backup <dest>"` or `VACUUM INTO` |
| A recurrence heuristic inferred from Google task titles | Recurrence data genuinely does not exist in the export. Guessing produces silently wrong chore schedules that nobody notices for weeks. | Explicit operator-authored recurrence map, checked into the repo |
| New impermanence entries for Mealie / Actual | `/var/lib/private` and `/var/lib/postgresql` are already persisted; both services are `DynamicUser`. Adding `/var/lib/mealie` would persist a *symlink*. | Nothing — verify, don't add |
| Grocy / any pantry tracker | Explicitly rejected in PROJECT.md Out of Scope. | Mealie's shopping list only |

---

## Stack Patterns by Variant

**If the `nixos-26.05` bump is approved (recommended):**
- Use the 26.05 modules for all three native services
- Override only `services.mealie.package = unstable.mealie` (after bumping `nixpkgs-unstable` to reach 3.22.0)
- Homebox and Actual ship as-is from the channel

**If the `nixos-26.05` bump is deferred:**
- Keep 25.11 modules
- Override `services.mealie.package` and `services.actual.package` from `unstable`
- **Leave Homebox on 25.11's 0.24.0** — do not overlay 0.25.0, because the 25.11 module sets the pre-rename env var
- Accept that `services.actual` lacks `dataDir`/`user`/`group` options and `ReadWritePaths` (works, just less configurable)
- Record this as explicit tech debt with the EOL date attached

**If the household wants Donetick on mobile (native app, not PWA):**
- The private-CA problem is real. Either install the Caddy root CA on each phone, or reconsider a publicly-trusted cert for that one hostname
- This should be surfaced during the Donetick phase's UAT, not discovered afterwards

---

## Version Compatibility

| Component | Compatible With | Notes |
|-----------|-----------------|-------|
| `services.mealie` (25.11 / 26.05 / master) | `pkgs.mealie` 3.9.2 → 3.22.0 | Module is byte-identical across all three branches; the only contract is `$out/bin/mealie` + `$out/libexec/init_db`, preserved through the master frontend rewrite. Package override is safe. |
| `pkgs.mealie` 3.22.0 | PostgreSQL 15–17 | `ExecStartPre` runs Alembic; **migrations are one-way**. `pg_dump` before every version bump. |
| `services.homebox` 25.11 module | `pkgs.homebox` 0.24.0 only | Sets `HBOX_OPTIONS_CHECK_GITHUB_RELEASE` (old name). Mismatched with 0.25.0. |
| `services.homebox` 26.05 module | `pkgs.homebox` 0.25.0 | Sets `HBOX_OPTIONS_GITHUB_RELEASE_CHECK` (new name). **Not** compatible with 0.26.x (missing pepper). |
| `services.actual` 26.05 module | `pkgs.actual-server` 26.4.0 → 26.8.1 | Module gained `dataDir`/`user`/`group` options and `ReadWritePaths`; works with any of these server versions. |
| `actual-server` 26.7.0 | Actual web/desktop clients | Actual is backward compatible with older budget files; the client warns if the *server* is older than the client. Keeping the server within one release of upstream avoids this. |
| Donetick `v0.1.76` container | SQLite (bundled), Caddy reverse proxy, SSE | `serve_frontend: true` required. Mobile app has known friction with private-CA TLS (firebat uses `local_certs`). |
| `nixos-26.05` | `nixos-raspberrypi` @ `a12cce571003` | **Unverified interaction — the main risk of the channel bump.** The pin exists because `boot.loader.raspberryPi` was removed in 25.11+; the Pis use `nixpkgs_2` (nvmd fork) not the top-level input, but shared `modules/` are evaluated against the bumped channel. Gate with `make dry-activate-pi4` before merging. |
| `virtualisation.oci-containers` podman backend | ser8 impermanence | Needs `/var/lib/containers` persisted; the existing `/var/lib/docker` entry does not cover podman. |

---

## Confidence Notes

| Claim | Confidence | Basis |
|-------|------------|-------|
| Module existence + option sets for mealie/homebox/actual | **HIGH** | Read the module `.nix` files directly out of the flake's own locked nixpkgs store path (`/nix/store/0mrdxm…-source`) and the unstable input, plus `diff`ed 25.11 against 26.05. First-party source, not documentation. |
| Package versions on 25.11 / 26.05 / master | **HIGH** | `version = "…"` read from `pkgs/by-name/*/package.nix` in the store and from `raw.githubusercontent.com` branch heads. |
| Upstream latest versions | **HIGH** | GitHub Releases API, 2026-08-16. |
| Donetick absent from nixpkgs; PR #551607 is package-only | **HIGH** | 404s on all three branches + GitHub PR files API listing (5 files, no `nixos/modules/`). |
| Donetick container digest | **HIGH** | `docker-content-digest` header from `registry-1.docker.io` for tag `v0.1.76`, 2026-08-16. |
| Donetick API limitations (`eapi` hard-codes `once`, Plus gating) | **HIGH** | Read `internal/chore/api.go` and `internal/chore/handler.go` from upstream `main`. |
| Google Tasks/Takeout has no recurrence field | **HIGH** | Official Tasks API v1 `Task` resource reference (full field list, no recurrence) cross-checked against a community Takeout sample and a Google Calendar Community thread on exactly this gap. |
| Exact Takeout JSON key names | **MEDIUM** | Confirmed against one community sample file, not against this household's export. Expect `notes`/`completed`/`deleted` to be present-but-omitted-when-empty. Have the phase start by dumping the real export's key union. |
| Homebox 0.26 pepper requirement / entity merge | **MEDIUM-HIGH** | Upstream release notes and changelog via search, not read from source. The direction (don't chase 0.26) holds regardless, since nixpkgs master is still on 0.25.0. |
| `nixos-26.05` × `nixos-raspberrypi` interaction | **LOW** | Not tested. This is the one item that needs an actual `make dry-activate-pi4` to resolve. Flag for a spike in the channel-bump phase. |

---

## Sources

- Locked nixpkgs 25.11 source tree — `/nix/store/0mrdxm84242xz3anvbrvdllp3p24b1jy-source` (module + package files read directly)
- Locked nixpkgs-unstable (26.05) source tree — `/nix/store/77dbgds155bbz3vd3qywq1sii07i5ljs-source`
- `raw.githubusercontent.com/NixOS/nixpkgs/{master,nixos-26.05}` — `pkgs/by-name/{me/mealie,ho/homebox,ac/actual-server}/package.nix`
- GitHub API — `NixOS/nixpkgs` PR #551607 (donetick init); releases for `mealie-recipes/mealie`, `sysadminsmedia/homebox`, `actualbudget/actual`, `donetick/donetick`
- `registry-1.docker.io` — `donetick/donetick:v0.1.76` manifest digest
- Donetick upstream `main` — `config/selfhosted.yaml`, `internal/chore/api.go`, `internal/chore/handler.go`, `internal/chore/model/model.go`, `internal/user/handler.go`
- [NixOS 26.05 release announcement](https://nixos.org/blog/announcements/2026/nixos-2605/) and [NixOS 26.05 release schedule #503391](https://github.com/NixOS/nixpkgs/issues/503391) — 25.11 EOL 2026-06-30
- [Google Tasks API v1 — Task resource](https://developers.google.com/workspace/tasks/reference/rest/v1/tasks) — complete field list, no recurrence
- [Google Calendar Community — Takeout tasks export omits repeats](https://support.google.com/calendar/thread/244906743/exported-tasks-data-from-takeout-doesn-t-include-information-on-repeats-in-json-file?hl=en)
- [thethales/GoogleTasksJSONtoTXT `Tasks_sample.json`](https://github.com/thethales/GoogleTasksJSONtoTXT) — Takeout JSON shape
- [Donetick configuration docs](https://docs.donetick.com/getting-started/configration/)
- [Mealie backend configuration](https://docs.mealie.io/documentation/getting-started/installation/backend-config/) and [Mealie PostgreSQL guide](https://docs.mealie.io/documentation/getting-started/installation/postgres/)
- [mealie-recipes/mealie#3573](https://github.com/mealie-recipes/mealie/issues/3573) — `POSTGRES_URL_OVERRIDE` colon requirement
- [Homebox v0.26.1 release notes](https://github.com/sysadminsmedia/homebox/releases/tag/v0.26.1) and [Homebox changelog](https://homebox.software/en/changelog/) — pepper requirement, entity merge
- Repository files inspected: `flake.nix`, `flake.lock`, `deploy.yaml`, `hosts/ser8/{configuration,impermanence}.nix`, `modules/gateway/Caddyfile`, `modules/dns/adguard-home.nix`, `modules/servers/backup.nix`

---
*Stack research for: v1.2 Household Stack (Mealie, Donetick, Homebox, Actual Budget on NixOS)*
*Researched: 2026-08-16*
