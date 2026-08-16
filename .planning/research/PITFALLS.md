# Pitfalls Research

**Domain:** Self-hosted household web services (Mealie, Donetick, Homebox, Actual Budget) added to an existing NixOS 25.11 host using disko + ZFS root rollback impermanence, sops-nix, and a firebat Caddy local-CA gateway
**Researched:** 2026-08-16
**Confidence:** HIGH for nixpkgs module behaviour and repo facts (read directly from pinned `nixos-25.11` sources and this repo), MEDIUM for upstream app behaviour and community-reported issues, LOW-to-MEDIUM for Google Takeout export fidelity

## Repo Facts This Research Is Grounded In

These were verified by reading the repository, not assumed.

| Fact | Location | Why it matters |
|------|----------|----------------|
| `nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11"` | `flake.nix:7` | All module behaviour below is read from that exact branch |
| `system.stateVersion = "24.11"` on ser8 | `hosts/ser8/configuration.nix:276` | Silently selects `postgresql_16`, not 17 |
| `zfs rollback -r rpool/local/root@blank` in `initrd.postDeviceCommands` | `hosts/ser8/configuration.nix:88-89` | Root wipes every boot before any service starts |
| `/var/lib/private` persisted with `mode = "0700"` | `hosts/ser8/impermanence.nix` | Already the correct pattern for `DynamicUser` services |
| `/var/lib/postgresql` persisted with no user/group | `hosts/ser8/impermanence.nix` | Lands as `root:root 0755`; postgres needs `0700 postgres:postgres` on `$PGDATA` |
| `services.postgresql` is **not enabled anywhere** | verified by `rg` | Mealie will be the first Postgres consumer on this host |
| `backup/backups` dataset has `dedup = "on"`, mounted at `/mnt/backups` | `hosts/ser8/disko-config.nix:256-261` | The intended backup target has ZFS dedup enabled |
| Caddyfile global block sets `local_certs` and `skip_install_trust` | `modules/gateway/Caddyfile:1-9` | The local root CA is never auto-installed on any client |
| Existing vhosts hand-roll `header_up Upgrade` / `Connection "Upgrade"` | `modules/gateway/Caddyfile` (frigate, hass) | A pattern that is wrong to copy for the four new services |
| Ports already claimed on ser8: 1883, 5000, 6767, 6789, 7878, 8080, 8085, 8096, 8123, 8554, 8555, 8989, 9090, 9134, 9696, 9707-9711 | `rg` across `hosts/ser8`, `modules/media`, `modules/automation` | Collision surface for the four new default ports |

---

## Critical Pitfalls

### Pitfall 1: Persisting `/var/lib/<service>` for a `DynamicUser` service breaks the service

**What goes wrong:**
`services.mealie` and `services.actual` in nixpkgs 25.11 both set `DynamicUser = true` with `StateDirectory`.
systemd therefore creates the real state directory at `/var/lib/private/mealie` and `/var/lib/private/actual`, and leaves `/var/lib/mealie` and `/var/lib/actual` as symlinks into `private/`.
The instinctive impermanence entry is `"/var/lib/mealie"`, which bind-mounts a real directory onto the path where systemd needs to place a symlink.
The unit then fails at state-directory setup, or systemd silently writes state somewhere the persistence layer is not watching.

**Why it happens:**
Every other service in this repo's persistence list (`jellyfin`, `sonarr`, `radarr`, `frigate`, `hass`) uses a static user, so `/var/lib/<name>` is the correct entry for them.
Mealie and Actual break that symmetry and nothing in the option docs flags it.
This is [impermanence issue #93](https://github.com/nix-community/impermanence/issues/93), which the maintainers describe as possibly unfixable.

**How to avoid:**
Do **not** add `/var/lib/mealie` or `/var/lib/actual` to `environment.persistence`.
This repo already persists `{ directory = "/var/lib/private"; mode = "0700"; }`, which covers both services correctly: systemd creates the per-service subdirectory inside the bind mount at runtime with the right ownership.
Add a comment in `hosts/ser8/impermanence.nix` recording *why* those two paths are deliberately absent, otherwise a future edit will "helpfully" add them.
If `/var/lib/private` ever ends up `0755`, DynamicUser services refuse to start ([impermanence issue #254](https://github.com/nix-community/impermanence/issues/254)); keep the explicit `mode = "0700"`.

**Warning signs:**
`systemctl status mealie` reporting `Failed to set up special execution directory in /var/lib`.
`ls -l /var/lib/mealie` showing a symlink to `private/mealie` is **normal** and not a fault; `/var/lib/private` is `0700` root-only, so it only resolves for root or the service itself.
The real fault signal is the unit failing to start, or `/persist/var/lib/private/` being empty after a successful run.

**Phase to address:**
The impermanence/persistence foundation phase, before any of the four services is enabled.

---

### Pitfall 2: Homebox uses a static user, so `/var/lib/homebox` is NOT covered by `/var/lib/private`

**What goes wrong:**
`services.homebox` in nixpkgs 25.11 does **not** use `DynamicUser`.
It declares `users.users.homebox` as a normal system user and uses `StateDirectory = "homebox"`, so its SQLite database, uploaded attachments, and item photos live in a real `/var/lib/homebox`.
If persistence is written by pattern-matching on "these are the new services, and Mealie/Actual are covered by `/var/lib/private`", Homebox is silently missed.
On the next reboot the root dataset rolls back, Homebox finds no database, runs its migrations against an empty file, and comes up as a brand-new instance.

**Why it happens:**
The four services look interchangeable from the outside but the four nixpkgs modules make three different lifecycle choices (Mealie/Actual `DynamicUser`, Homebox static user, Donetick not packaged at all).
The failure is silent: the service starts fine and returns HTTP 200.

**How to avoid:**
Add `/var/lib/homebox` explicitly to `environment.persistence."/persist".directories` with `user = "homebox"; group = "homebox"; mode = "0700";` (the module sets `UMask = "0077"`).
Verify by reading `serviceConfig.DynamicUser` for every new service before writing its persistence entry, rather than assuming.
Cross-check on the deployed host with `systemctl show <unit> -p DynamicUser,StateDirectory`.

**Warning signs:**
Homebox login page shows the first-run/registration state after a reboot.
`/persist/var/lib/homebox` does not exist while `/var/lib/homebox` does.
Item count resets to zero.

**Phase to address:**
The Homebox deployment phase; verification must include a real reboot, not just a `systemctl restart`.

---

### Pitfall 3: Homebox registration default locks you out of your own instance

**What goes wrong:**
The nixpkgs module sets `HBOX_OPTIONS_ALLOW_REGISTRATION = "false"` as a `mkDefault`.
That is the correct end state, but it means a fresh instance has no way to create the first account.
The common recovery is to flip it to `"true"`, rebuild, register, flip it back, and rebuild again.
That window is a live open-signup window on a service already published at `homebox.vofi`.

**Why it happens:**
The requirement reads as "registration disabled after initial accounts", which sounds like one-step configuration but is actually a two-state deployment.

**How to avoid:**
Sequence deliberately: enable Homebox with registration allowed but **before** adding the Caddy vhost and the AdGuard DNS rewrite, create both household accounts over the Tailscale address or an SSH port-forward, then set registration false, rebuild, and only then publish the vhost.
Add a smoketest that asserts `HBOX_OPTIONS_ALLOW_REGISTRATION` is `false` in the running unit's environment so a later refactor cannot silently reopen it.

**Warning signs:**
The registration form is reachable at `homebox.vofi/register` after the phase is called done.
`systemctl show homebox -p Environment | grep ALLOW_REGISTRATION` returns `true`.

**Phase to address:**
The Homebox deployment phase, with the ordering encoded in the plan steps, not left to execution improvisation.

---

### Pitfall 4: Donetick is not in nixpkgs at all

**What goes wrong:**
There is no `pkgs.donetick` and no `services.donetick` module in `nixos-25.11` or in `master`.
Verified: `pkgs/by-name/do/donetick/package.nix` returns 404, and `donetick` does not appear in `nixos/modules/module-list.nix` on either branch (Mealie, Actual, and Homebox all do).
A roadmap that treats all four services as "enable the module, add persistence, add a vhost" will underestimate the Donetick phase by an order of magnitude.

**Why it happens:**
The other three are packaged, so the fourth is assumed to be.
Searches for "donetick nixos" return generic Nix documentation, which is easy to skim past.

**How to avoid:**
Budget Donetick as its own phase with an explicit packaging decision recorded up front.
Two viable paths:

1. `virtualisation.oci-containers.containers.donetick` using the upstream `donetick/donetick` image on port 2021. Docker is already enabled and `/var/lib/docker` is already persisted on ser8, so this is the lower-risk path. The container's data volume still needs its own persisted host path.
2. A `buildGoModule` derivation plus a hand-written module. Upstream requires the frontend to be built separately before the server binary embeds it, so this also needs a `buildNpmPackage` stage. Higher maintenance, better fit with the repo's declarative-everything constraint.

Whichever is chosen, record it in PROJECT.md Key Decisions so the choice is not relitigated mid-phase.

**Warning signs:**
A plan step that says "enable `services.donetick`".
`nix eval` failing with `The option 'services.donetick' does not exist`.

**Phase to address:**
A dedicated Donetick packaging phase, ordered before the Google Tasks import phase.

---

### Pitfall 5: Mealie regenerates its session secret and stores images on disk

**What goes wrong:**
Two separate but related failures, both of which pass a naive "does it work?" check.
First, Mealie generates a token-signing secret inside `DATA_DIR` on first run.
If `DATA_DIR` is not persisted, the secret is regenerated after every root rollback and every user is logged out on every reboot with no error anywhere.
Second, recipe images, scraped photos, and user assets are written to disk under `DATA_DIR`, not into PostgreSQL.
A backup strategy of "pg_dump nightly" therefore restores every recipe with every image broken.

**Why it happens:**
"Mealie with PostgreSQL" reads as "the state is in Postgres".
The database restore succeeds, so the backup looks verified until someone opens a recipe.

**How to avoid:**
Treat Mealie as having two state stores that must both be backed up and both be persisted: the Postgres database and `DATA_DIR` (`/var/lib/mealie`, physically `/var/lib/private/mealie`).
The restore test must open a recipe with an uploaded image, not just count rows.

**Warning signs:**
Users report being logged out after a ser8 reboot.
Recipe thumbnails render as broken images after a restore drill.
`/persist/var/lib/private/mealie/recipes/` is empty or absent.

**Phase to address:**
Split across the Mealie deployment phase (persistence) and the backup/restore phase (restore drill criteria must name image assets explicitly).

---

### Pitfall 6: Mealie's `BASE_URL` defaults to `http://localhost:9000` and forwarded headers are ignored

**What goes wrong:**
The nixpkgs module hardcodes `BASE_URL = "http://localhost:${toString cfg.port}"` in the unit environment.
Mealie derives notification links, share links, and OIDC redirect URIs from `BASE_URL`.
Behind Caddy this produces links that point at localhost and are unusable from any other device.
Separately, Mealie's server ignores `X-Forwarded-Proto` unless started with `--forwarded-allow-ips`, so even with a corrected `BASE_URL` it can generate `http://` URLs for an `https://` site.

**Why it happens:**
The module default is a sensible standalone default and there is no assertion or warning when a reverse proxy is in play.
The `settings` attrset is freeform, so a typo in `BASE_URL` produces no evaluation error.

**How to avoid:**
Set `services.mealie.settings.BASE_URL = "https://mealie.vofi";` and pass the proxy address through `services.mealie.extraOptions = [ "--forwarded-allow-ips" "<firebat-ip>" ]`.
Confirm the Caddy vhost forwards `X-Forwarded-Proto` (Caddy v2 sets it on `reverse_proxy` by default; verify rather than assume if any `header_up` overrides are added).
Verify by triggering a password-reset email or copying a share link, not by loading the homepage.

**Warning signs:**
Share links or invite links contain `localhost:9000`.
Any future OIDC integration returns a redirect-URI mismatch.

**Phase to address:**
The Mealie deployment phase; the Caddy vhost step and the `BASE_URL` step belong in the same plan so they cannot drift.

---

### Pitfall 7: Actual Budget needs a genuinely trusted certificate, and this Caddyfile installs trust nowhere

**What goes wrong:**
Actual's web client uses `crypto.subtle` for end-to-end encryption and `SharedArrayBuffer` for its in-browser SQLite engine.
Both require a secure context: `https://` with a certificate the browser actually trusts, or `http://localhost`.
The existing Caddy global block sets `local_certs` **and** `skip_install_trust`, so the local root CA is never installed on any client.
Clicking through the browser interstitial is not sufficient: Chrome refuses to register service workers on an origin with a certificate error, which breaks Actual's PWA and offline behaviour, and the official mobile apps reject a server URL they cannot validate.
The failure is confusing because the login page renders fine before the crypto paths are exercised.

**Why it happens:**
Every existing `.vofi` service in this repo tolerates a click-through certificate warning, so nobody has needed to install the CA.
Actual is the first service on this stack where an untrusted certificate is a hard functional blocker rather than cosmetic.

**How to avoid:**
Make root-CA distribution an explicit deliverable, not an afterthought.
The root lives in Caddy's data directory at `pki/authorities/local/root.crt` on firebat.
Install it on every household laptop and phone that needs Actual.
On iOS this is two steps and the second is routinely missed: install the profile under Settings > General > VPN & Device Management, **then** enable it under Settings > General > About > Certificate Trust Settings.
On Android, user-installed CAs are trusted by browsers but not by apps by default on Android 7+, which affects the Actual mobile app specifically.
Firefox uses its own trust store and needs a separate import.
Consider replacing Caddy's auto-generated root with a long-lived CA you control via a `pki { ca ... }` block, so the root does not change if Caddy's data directory is ever lost and every device does not need re-enrolling.

Also: Caddy's internally issued **leaf** certificates default to a 12h lifetime.
That is fine while Caddy is running and renewing, but a firebat outage longer than 12h means every `.vofi` service starts serving expired certificates.

**Warning signs:**
Actual shows a blank screen or a `SharedArrayBufferMissing` fatal error after login.
The Actual mobile app refuses the server URL.
Browser console reports `crypto.subtle is undefined`.

**Phase to address:**
A gateway/TLS-trust phase that precedes the Actual deployment phase.
This pitfall alone justifies ordering Actual last among the four.

---

### Pitfall 8: Duplicated COOP/COEP headers and subpath hosting break Actual

**What goes wrong:**
Actual's server sets `Cross-Origin-Opener-Policy` and `Cross-Origin-Embedder-Policy` itself.
If the reverse proxy also sets them, browsers see duplicate values (`require-corp, require-corp`), invalidate the policy, and `SharedArrayBuffer` becomes unavailable, producing a fatal error.
Separately, Actual does not support being served from a subpath: it must live at the root of a hostname.

**Why it happens:**
"Add the security headers" is generic reverse-proxy advice that is actively harmful here.

**How to avoid:**
The `actual.vofi` Caddy vhost should be a bare `reverse_proxy ser8.local:<port>` with no header manipulation.
If any global Caddy header snippet exists or is added later, exclude this vhost from it.
Keep Actual at `actual.vofi`, never at `something.vofi/actual`.

**Warning signs:**
`curl -sI https://actual.vofi | grep -i cross-origin` returning two values for either header.

**Phase to address:**
The Actual deployment phase.

---

### Pitfall 9: PostgreSQL major version is chosen silently by `stateVersion`

**What goes wrong:**
ser8 sets `system.stateVersion = "24.11"`.
The NixOS `postgresql` module picks its default package from `stateVersion`, so enabling Postgres for the first time on this host yields **PostgreSQL 16**, not the 25.11 default of 17.
That is not itself wrong, but it is invisible, and it becomes a trap the first time someone "cleans up" by pinning `postgresql_17` or bumping `stateVersion`: the server refuses to start against an existing 16 data directory with `database files are incompatible with server`, and recovery requires an explicit `pg_upgrade` while the data directory lives on an impermanence-managed path.

**Why it happens:**
`services.postgresql.enable = true` arrives implicitly via `services.mealie.database.createLocally = true`, so Postgres gets enabled without anyone consciously choosing a version.

**How to avoid:**
Pin `services.postgresql.package = pkgs.postgresql_17;` explicitly from the very first deploy, before any data exists, and record the pin in PROJECT.md Key Decisions with a note that changing it later requires `pg_upgrade` plus a fresh restore test.
Choosing the pin on day one costs nothing; choosing it after data exists costs a migration.

**Warning signs:**
`SHOW server_version;` returning a version nobody chose.
`/persist/var/lib/postgresql/` containing more than one version subdirectory.

**Phase to address:**
The Mealie/PostgreSQL foundation phase, as the first configuration written.

---

### Pitfall 10: PostgreSQL data directory ownership race on first boot under impermanence

**What goes wrong:**
`/var/lib/postgresql` is already in this repo's persistence list with no `user`/`group`, so impermanence creates it as `root:root 0755`.
PostgreSQL requires `$PGDATA` (`/var/lib/postgresql/<major>`) to be `0700` owned by `postgres`, and refuses to start otherwise.
Impermanence's declared permissions and ownership **override** what `config.users.*` and later tmpfiles rules want, and impermanence's directory creation runs very early, potentially before the `postgres` user exists.
The result is either a first-boot failure that appears to resolve itself on the second rebuild (masking the real ordering problem), or a persistent `data directory has invalid permissions` refusal.

**Why it happens:**
This repo's own impermanence file carries the comment "Don't specify user/group for services that might not exist yet", which is the correct instinct for the media services but leaves Postgres with wrong ownership.
The commented-out line `# "d /persist/var/lib/postgresql 0700 postgres postgres -"` in `hosts/ser8/impermanence.nix` shows this was already noticed once and left unresolved.

**How to avoid:**
`/var/lib/nixos` is already persisted, so UID/GID assignments are stable across rollbacks; that removes the worst of the race but does not fix initial creation on a host that has never run Postgres.
Set the persistence entry explicitly to `{ directory = "/var/lib/postgresql"; user = "postgres"; group = "postgres"; mode = "0750"; }` and let the NixOS postgresql module's own tmpfiles rule create the `0700` version subdirectory inside it.
Test the very first Postgres boot with `make test-ser8` (temporary activation) plus a real reboot, so an ordering bug surfaces before it is baked into the boot default.

**Warning signs:**
`FATAL: data directory "/var/lib/postgresql/16" has invalid permissions`.
`postgresql.service` failing on first boot but succeeding after a manual `chown`.
A manual `chown` being needed at all: that is the tell that the declarative path is wrong.

**Phase to address:**
The impermanence/persistence foundation phase, verified by a cold boot.

---

### Pitfall 11: `cp` of a live SQLite database

**What goes wrong:**
Three of the four services are SQLite-backed, and at least Homebox is explicitly in WAL mode: the nixpkgs module hardcodes `HBOX_DATABASE_SQLITE_PATH = ".../homebox.db?_pragma=busy_timeout=999&_pragma=journal_mode=WAL&_fk=1"`.
A backup script that does `cp homebox.db /mnt/backups/` copies the main file without `-wal` and `-shm`, so recent committed transactions are silently missing, and a copy taken mid-write is corrupt on open.
The backup job exits 0 either way.

**Why it happens:**
`cp` is the obvious thing and it produces a file of plausible size.
Corruption is only discovered at restore time, which is exactly when it matters.

**How to avoid:**
Use `sqlite3 <src> ".backup '<dst>'"` (online backup API, safe against concurrent writers) or `sqlite3 <src> "VACUUM INTO '<dst>'"` (single-transaction snapshot, compacted).
Follow every backup with `sqlite3 <dst> "PRAGMA integrity_check;"` and fail the unit if the result is not `ok`.
`VACUUM INTO` gotchas to encode in the script: the destination must not already exist, the output reverts to DELETE journal mode regardless of the source, and it can transiently need roughly double the database size in free space.

**Warning signs:**
A backup script containing `cp`, `rsync`, or `tar` pointed at a `.db` file while the service is running.
Backup file sizes that never change even though the app is being used, which means you are copying a stale main file while all writes sit in the WAL.

**Phase to address:**
The backup/restore phase, with `PRAGMA integrity_check` as a hard acceptance criterion.

---

### Pitfall 12: Actual Budget's state is not a single SQLite file

**What goes wrong:**
Actual splits its state: `serverFiles` holds `account.sqlite` and session data, and `userFiles` holds each budget as an opaque binary blob.
The nixpkgs module defaults both under `/var/lib/actual`.
A backup that finds and dumps every `*.sqlite` under the data directory captures accounts and sessions but **not** the budgets, which are the actual data.
The restore produces a working login with zero budgets.

**Why it happens:**
"SQLite service" implies one file to back up.
The `.sqlite` glob strategy that works for Homebox and Donetick fails here.

**How to avoid:**
Back up the whole `/var/lib/actual` tree: `serverFiles` via the SQLite backup API and `userFiles` as a file copy (the blobs are written atomically on sync, not held open).
The restore drill must open a budget and confirm transactions are present, not just confirm login works.

**Warning signs:**
Backup archive for Actual is a few hundred KB.
Restore drill checklist stops at "logged in successfully".

**Phase to address:**
The backup/restore phase; write the Actual restore criterion as "a named budget opens with its transactions".

---

### Pitfall 13: `pg_dump` inside a hardened systemd unit fails on peer auth or cannot write its output

**What goes wrong:**
Three overlapping systemd hardening traps, each producing a different confusing error:

1. `PrivateUsers=true` remaps UIDs inside a user namespace, so the UID PostgreSQL reads from `SO_PEERCRED` on the unix socket does not match the expected role. Result: `FATAL: Peer authentication failed for user "postgres"` even though `User=postgres` is set. Note that the nixpkgs `actual` and `homebox` modules both set `PrivateUsers = true`; if a backup unit is written by copying one of their hardening blocks, this is inherited.
2. `ProtectSystem=strict` makes the whole filesystem read-only, so the dump cannot be written to `/mnt/backups` without an explicit `ReadWritePaths`.
3. `ProtectHome=true` hides `~/.pgpass`, so any password-based fallback silently fails.

**Why it happens:**
Hardening directives are copied wholesale from an existing service or a hardening blog post, and each of these three is individually reasonable.

**How to avoid:**
For the Postgres dump unit: `Type=oneshot`, `User=postgres`, **no** `PrivateUsers`, `ProtectSystem=strict` with `ReadWritePaths=/mnt/backups`, and use the unix socket with peer auth so no password exists anywhere.
Add hardening in phases and treat `PrivateUsers` as the last and most likely to break.
For the SQLite dumps, the unit needs read access to each service's state directory: under `DynamicUser` those live in `/var/lib/private/<svc>` which is `0700` root-only, so the backup unit must run as root or be granted the specific paths. Simply setting `User=backup` will fail with permission denied.

**Warning signs:**
`FATAL: Peer authentication failed`.
`Read-only file system` on the dump path.
A backup unit that works when run by hand as root but fails as a timer.

**Phase to address:**
The backup/restore phase.

---

### Pitfall 14: The intended backup target has ZFS dedup enabled

**What goes wrong:**
`backup/backups`, mounted at `/mnt/backups`, is declared with `dedup = "on"` in `hosts/ser8/disko-config.nix`.
Writing nightly `pg_dump` output and SQLite snapshots there feeds a dataset whose deduplication table grows with every unique block written and lives in ARC.
Compressed or `VACUUM INTO`-compacted dumps deduplicate poorly, because near-identical logical content produces entirely different blocks, so the RAM cost buys almost nothing.
The property cannot be meaningfully undone after the fact: turning dedup off stops new blocks from being deduplicated but existing DDT entries persist until every deduplicated block is rewritten, which in practice means recreating the dataset.

**Why it happens:**
The dataset was created for NAS-style backups where dedup made more sense, and the comment in `disko-config.nix` says exactly that.
Nobody re-evaluates a pool property when adding a new consumer.

**How to avoid:**
Decide the target dataset before writing the first backup unit.
Preferred: create a dedicated child dataset for service dumps with `dedup = "off"`, `compression = "zstd"`, and a smaller `recordsize` than the inherited `1M`, and use ZFS snapshots of that dataset for retention rather than dated files.
If the existing dataset is kept, at minimum measure `zpool status -D backup` after a week and confirm the dedup ratio justifies the ARC cost.

**Warning signs:**
`zpool status -D backup` showing a large DDT with a dedup ratio near 1.00x.
ARC pressure or memory alerts on ser8 after backups begin.

**Phase to address:**
The backup/restore phase, as the first design decision in it.

---

### Pitfall 15: Copying this repo's existing WebSocket header pattern into the new vhosts

**What goes wrong:**
The Frigate and Home Assistant vhosts in `modules/gateway/Caddyfile` hand-roll `header_up Upgrade {http.request.header.Upgrade}` and `header_up Connection "Upgrade"`.
That is nginx idiom and it is unnecessary in Caddy v2, which handles HTTP/1.1 upgrades natively.
Worse, `header_up Connection "Upgrade"` is unconditional: it stamps every ordinary page load, XHR, and asset request as a WebSocket upgrade, which backends answer with 400 or 426.
Under HTTP/2 the `Connection` and `Upgrade` headers are forbidden entirely and Caddy logs `http2: invalid Upgrade request header`.
Actual Budget's sync engine uses WebSockets, so it is the most likely service to attract this "fix".

**Why it happens:**
The pattern is already in the file with a comment saying it is required, so it reads as house style.

**How to avoid:**
Write each new vhost as a bare `reverse_proxy ser8.local:<port>` with no `header_up`.
Verify WebSocket-dependent features work before adding anything.
Separately, flag the existing Frigate/HASS blocks for cleanup: they are likely masking rather than solving whatever originally motivated them.

**Warning signs:**
Intermittent 400/426 responses on ordinary page loads.
`http2: invalid Upgrade request header` in Caddy logs.

**Phase to address:**
The gateway/vhost phase.

---

### Pitfall 16: Donetick's signup is open by default and its JWT secret is a placeholder

**What goes wrong:**
Donetick's `selfhosted.yaml` ships `is_user_creation_disabled: false`, so a freshly deployed instance accepts registrations from anyone who can reach it.
The same file ships `jwt.secret` set to the literal string `change_this_to_a_secure_random_string_32_characters_long`.
A secret shorter than 32 characters, or left at the placeholder, produces `token contains an invalid number of segments` 401s on login and account creation ([donetick issue #254](https://github.com/donetick/donetick/issues/254)), which is easy to misdiagnose as a proxy problem.
Rotating the secret later invalidates every session and every mobile-app login.

**Why it happens:**
The config key is top-level (`is_user_creation_disabled`) while the JWT key is nested (`jwt.secret`), so a partial config translation misses one or the other.
The env-var override prefix is `DT_`, not `DONETICK_`, so a guessed variable name is silently ignored and the placeholder default stays in force.

**How to avoid:**
Set `is_user_creation_disabled: true` (or `DT_IS_USER_CREATION_DISABLED=true`) as part of the initial deploy, using the same create-accounts-then-close sequence described for Homebox.
Generate the JWT secret with `openssl rand -hex 32` and deliver it via sops-nix as an `EnvironmentFile` containing `DT_JWT_SECRET=...`.
Never render `selfhosted.yaml` with the secret inline through Nix: everything in `/nix/store` is world-readable, which would violate the milestone's "nothing secret in the Nix store" requirement.
Also set `server.public_host` to `https://donetick.vofi` and add that origin to `server.cors_allow_origins`, whose defaults are localhost-only; without both, the web UI can work while the mobile app fails ([donetick issue #619](https://github.com/donetick/donetick/issues/619)).

**Warning signs:**
`grep -r change_this_to_a_secure /nix/store` returning anything.
401s with `invalid number of segments` in Donetick logs.
Web UI works but the mobile app cannot connect.

**Phase to address:**
The Donetick deployment phase.

---

### Pitfall 17: sops-nix secrets versus `DynamicUser`

**What goes wrong:**
`EnvironmentFile=` is read by PID 1 as root before privileges are dropped, so `services.mealie.credentialsFile = config.sops.secrets.mealie_postgres_password.path` works.
But any secret the **application process itself** opens will fail, because a `DynamicUser` UID is allocated at runtime and cannot be named in `sops.secrets.<name>.owner`.
This is exactly nixpkgs [issue #321623](https://github.com/NixOS/nixpkgs/issues/321623): Mealie 1.9.0 started reading `/run/secrets` during pydantic settings initialisation and crashed with `PermissionError: [Errno 13] Permission denied: '/run/secrets'` on any host using sops-nix, even with no Mealie-specific configuration.
The confirmed workaround at the time was `systemd.services.mealie.serviceConfig.DynamicUser = lib.mkForce false;`.

**Why it happens:**
The interaction is invisible in the option surface: `credentialsFile` is documented and works, so the whole secrets path looks fine until the app touches `/run/secrets` for an unrelated reason.

**How to avoid:**
Prefer `credentialsFile`/`EnvironmentFile` for every secret so nothing is read by the app directly.
Do not set `SECRETS_DIR`-style options that point Mealie at `/run/secrets`.
If `DynamicUser` must be disabled for any reason, that decision cascades: the state directory moves from `/var/lib/private/mealie` to `/var/lib/mealie` and the impermanence entry must move with it (see Pitfall 1). Do not disable `DynamicUser` and forget the persistence half.
Keep `sops.secrets.<name>.mode` at `0400` with an explicit `owner` for any static-user service (Homebox, Donetick under a static user).

**Warning signs:**
`PermissionError: [Errno 13] Permission denied: '/run/secrets'` in `journalctl -u mealie`.
Any secret path appearing in a service's own config file rather than in an `EnvironmentFile`.

**Phase to address:**
The secrets/sops phase, or the Mealie deployment phase if secrets are handled per-service.

---

### Pitfall 18: Port collisions and default all-interface binding

**What goes wrong:**
Default ports for the four services are Mealie 9000, Homebox 7745, Donetick 2021, and Actual **3000** (the nixpkgs module overrides upstream's 5006 with 3000).
ser8 already occupies a dense range including 5000, 8080, 8085, 8096, 8123, 8989, 9090, 9134, 9696, and 9707-9711.
9000 and 3000 are both common defaults elsewhere, and 3000 in particular is already used by Grafana on firebat and AdGuard on pi4, so it reads as "taken" during review even though it is free on ser8.
Separately, `services.mealie.listenAddress` defaults to `0.0.0.0` and `services.actual.settings.hostname` defaults to `::`, so all four bind every interface.

**Why it happens:**
Port assignment gets decided during execution rather than during planning, and each service is added in isolation.

**How to avoid:**
Allocate all four ports in one place during the roadmap phase and record them alongside the existing map.
Do **not** set `openFirewall = true` on any of them, and do not add them to `networking.firewall.allowedTCPPorts`, which is the prevailing habit in `modules/media/`.
Access must arrive through Caddy on firebat over the LAN/Tailscale path only; if the milestone requires strict Tailscale-only reachability, bind to the Tailscale interface address or loopback and let Caddy reach it over Tailscale rather than relying on firewall rules alone.

**Warning signs:**
`ss -tlnp` on ser8 showing the new services on `0.0.0.0`.
Two units failing with `address already in use` after a rebuild.
`curl http://ser8.local:3000` succeeding from an untrusted LAN device.

**Phase to address:**
Roadmap/design, then verified in the gateway phase with a smoketest that asserts the ports are not reachable off-Tailscale.

---

### Pitfall 19: Google Takeout Tasks does not export usable recurrence

**What goes wrong:**
Google's own field list for the Tasks archive claims to include task recurrence and a schedule of recurrences.
In practice, exported JSON does not contain usable repeat information: recurrence is stored as generated instances rather than an RRULE-equivalent, and third-party migration tools report that repetition on recurring tasks is not recoverable from either the Takeout archive or the Tasks API.
Since recurring chores are explicitly half the scope of this import ("one-off todos + recurring chores"), an import script built purely on Takeout data will produce a pile of one-off tasks and zero recurring chores, and the gap will only be noticed after the fact.

**Why it happens:**
The documented field list contradicts the actual export contents, and the discrepancy is only visible by opening a real archive and searching for recurrence keys on a task known to repeat.

**How to avoid:**
Make "inspect a real Takeout archive and enumerate what is actually present" the first step of the import phase, before any script is written.
Plan for recurring chores to be re-entered by hand in Donetick, driven by a list extracted from the Takeout data, rather than translated automatically.
That is a small number of items, and hand-entry is more reliable than a heuristic that infers recurrence from repeated instances.

Other Takeout quirks to expect:

- **Completed-task history**: completion status and completion timestamps are exported, and long-lived lists carry years of completed items. Importing them all into Donetick pollutes the new instance. Filter by status and by a cutoff date.
- **Deleted/hidden items**: deleted data is not exported, but hidden items may appear; decide explicitly whether to skip them.
- **Timezone**: due dates are effectively date-only values anchored at UTC midnight. Rendering them in a local timezone west of UTC shifts every due date back by one day. Normalise to a date, not a timestamp.
- **Structure**: one array of lists, each containing a nested array of tasks with `parent` IDs for subtasks. Parent/child order is not guaranteed, so a single pass that creates children before parents will fail.

**Warning signs:**
An import script with a code path for RRULE parsing that never fires.
Every imported task landing on the day before its real due date.
Donetick showing hundreds of already-completed items after import.

**Phase to address:**
The Google Tasks import phase, with archive inspection as an explicit gate before scripting.

---

### Pitfall 20: A one-time import that is not idempotent, or that is wired into activation

**What goes wrong:**
Two failure modes that compound.
First, an import script with no deduplication key produces a full duplicate set on any re-run, and re-runs are near-certain because the first attempt will get something wrong.
Second, wiring the import into a `systemd.services.*` unit with `wantedBy = [ "multi-user.target" ]` (the pattern used by this repo's `media-config` orchestration unit) means it re-executes on every rebuild and every boot.
Donetick also applies a server-side rate limit of 300 requests per 60 seconds by default (`server.rate_limit` / `server.rate_period`), so a naive loop over a few hundred tasks will start getting throttled part-way through and leave a partial import behind.

**Why it happens:**
The repo's established pattern for "configure a service via its API" is exactly such a systemd unit, so it is the natural thing to copy.
That pattern is right for convergent configuration and wrong for a one-shot data migration.

**How to avoid:**
Ship the import as a standalone script in `scripts/` invoked by hand once, not as a systemd unit.
Make it idempotent: record an external ID (the Google task ID) in the Donetick item's description or a dedicated field, and skip anything already present.
Rate-limit the client to well under 300/60s and handle 429 with backoff.
Take a SQLite backup of Donetick immediately before running it, so recovery from a bad import is a restore rather than a manual cleanup.
Delete or clearly quarantine the script once the import is verified, per the repo's "replace, don't deprecate" rule.

**Warning signs:**
Duplicate chores appearing after a rebuild.
HTTP 429 in the import script's output.
The import script surviving in `modules/` after the milestone closes.

**Phase to address:**
The Google Tasks import phase.

---

### Pitfall 21: AdGuard DNS rewrites pointed at the wrong host

**What goes wrong:**
The `<service>.vofi` names must resolve to **firebat** (the Caddy host), not to ser8 (where the services actually run).
Pointing them at ser8 means the browser talks to the application directly over plain HTTP on a non-standard port, or gets nothing at all.
For Mealie and Homebox this degrades quietly; for Actual it is a hard break, because plain HTTP on a non-localhost hostname is not a secure context.

**Why it happens:**
The mental model is "the service lives on ser8", and the existing `<service>.vofi` entries are added rarely enough that the pattern is not muscle memory.

**How to avoid:**
Add all four DNS rewrites in one change, pointed at firebat, and verify with `dig +short mealie.vofi @192.168.68.56` before touching the browser.
Add the four names to the existing blackbox exporter probe targets so a regression is caught by monitoring rather than by a person.

**Warning signs:**
`dig` returning ser8's address for a `.vofi` name.
A `.vofi` URL that only works with an explicit `:port` suffix.

**Phase to address:**
The gateway/DNS phase.

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Run Donetick as an OCI container instead of packaging it | Working service in hours instead of days; no Go/npm build to maintain | Container image is opaque to `make pkg-list-ser8` and `nix eval '.#packageInfo.ser8'`; version pinning is by tag not by hash; weakens the "all config in Nix" constraint | Acceptable for v1.2 if the decision and its cost are recorded and a follow-up item is filed. Pin by digest, not by `:latest` |
| Leave `skip_install_trust` and click through certificate warnings | No CA distribution work | Actual Budget does not function; PWA/service workers blocked; every new household device hits the same wall | Never, once Actual is in scope |
| Back up to `/mnt/backups` without changing `dedup=on` | No dataset work | DDT grows permanently in ARC for near-zero dedup ratio; cannot be undone without recreating the dataset | Only if measured and the ratio justifies it |
| `cp` the SQLite files with the service stopped, instead of using the backup API | Simple script | Requires stopping four services nightly; a missed stop silently produces a corrupt backup with no error | Acceptable only as a stopgap; the backup API is not meaningfully harder |
| Skip the restore drill and declare backups done | Phase closes faster | The failure mode is discovered during an actual incident, which is the worst possible time | Never. The milestone explicitly requires a demonstrated restore |
| Set `is_user_creation_disabled` / `ALLOW_REGISTRATION` by editing the running config instead of in Nix | Fast | Wiped on the next rebuild or root rollback; the service silently reopens signup | Never on this host |
| Add the new ports to `networking.firewall.allowedTCPPorts` "for testing" | Immediate direct access during debugging | Violates the Tailscale-only requirement and nobody remembers to remove it | Never; use an SSH port-forward instead |

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| Mealie to PostgreSQL | Hand-rolling `POSTGRES_*` env vars and a TCP connection with a password | Use `services.mealie.database.createLocally = true`, which sets `POSTGRES_URL_OVERRIDE` to a unix-socket peer-auth URL and wires `ensureDatabases`/`ensureUsers`. Pin `services.postgresql.package` explicitly |
| Mealie service ordering | Ordering on `postgresql.service` | Order on `postgresql.target`, new in 25.11, which guarantees read-write mode and that ensure-scripts have run. The nixpkgs module already does this; do not override it |
| Any service to Caddy | Copying the Frigate/HASS `header_up Upgrade` block | Bare `reverse_proxy host:port`; Caddy v2 upgrades natively |
| Actual to Caddy | Adding COOP/COEP headers at the proxy | Let Actual set them; the proxy must add nothing |
| Actual to clients | Assuming a click-through certificate is enough | Install the Caddy root CA on every client, including the second iOS trust-settings step |
| Donetick to Caddy | Leaving `public_host` empty and `cors_allow_origins` at localhost defaults | Set `public_host = https://donetick.vofi` and add that origin to CORS; otherwise the web UI works and the mobile app does not |
| Backups to PostgreSQL | `pg_dump` from a unit with `PrivateUsers=true` | `User=postgres`, no `PrivateUsers`, unix socket, `ReadWritePaths` for the dump target |
| Backups to DynamicUser state dirs | `User=backup` on the backup unit | `/var/lib/private` is `0700` root-only; the unit must run as root or be given the specific paths |
| `.vofi` names to AdGuard | Rewrite pointed at ser8 | Rewrite points at firebat; Caddy routes onward |
| Google Tasks to Donetick | Bulk loop over the API | Rate limit under 300 req/60s, back off on 429, key on the Google task ID for idempotence |
| sops-nix to DynamicUser services | Setting `sops.secrets.<n>.owner = "mealie"` | Dynamic UIDs cannot be named; deliver secrets exclusively via `EnvironmentFile`/`credentialsFile` |

## Performance Traps

Household scale here is roughly 2-5 users, so most classic scaling traps do not apply.
The ones that do are storage and memory, not request throughput.

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| ZFS dedup on the backup dataset | ARC pressure on ser8, slow writes to `/mnt/backups`, memory alerts | Dedicated child dataset with `dedup=off`, `compression=zstd` | Noticeable within weeks of nightly dumps; DDT cost scales with total unique blocks written, not with dedup benefit |
| Dated backup files instead of ZFS snapshots | `/mnt/backups` grows without bound; no retention policy exists so nobody prunes | Snapshot the backup dataset and let snapshot retention handle pruning | Months, but the cleanup is manual and error-prone once it happens |
| `VACUUM INTO` transiently doubling database size | Backup job fails with "database or disk is full" | Check free space before vacuuming; use `.backup` for the routine path and `VACUUM INTO` weekly | Only if the pool is near full; low risk here given RAID-Z2 capacity |
| Mealie recipe-image growth under `DATA_DIR` | `/persist` (on `rpool`) grows; the root pool is smaller than the backup pool | Monitor `/persist` usage; consider a dedicated dataset if image volume becomes significant | Low risk at household scale, but `/persist` on the root pool is the constrained resource |
| Four more scrape targets and four more blackbox probes | Prometheus on firebat picks up marginal load | Negligible; add them, do not over-think it | Not a real threshold at this scale |

## Security Mistakes

| Mistake | Risk | Prevention |
|---------|------|------------|
| Leaving Donetick's `is_user_creation_disabled: false` | Anyone reaching `donetick.vofi` (including anything on the LAN, not just Tailscale) can create an account and see household chores | Set it true in Nix; assert it in a smoketest |
| Leaving Homebox registration true after account creation | Same, for the household inventory, which is a list of valuables and their locations | Two-stage deploy; assert `HBOX_OPTIONS_ALLOW_REGISTRATION=false` in a smoketest |
| Rendering Donetick's `selfhosted.yaml` through Nix with the JWT secret inline | `/nix/store` is world-readable; the secret is exposed to every local user and every `nix copy` | Secret via sops-nix `EnvironmentFile` with `DT_JWT_SECRET` |
| Using the shipped placeholder JWT secret | Tokens forgeable by anyone who has read the upstream repo | `openssl rand -hex 32`, delivered from sops |
| `openFirewall = true` or manual `allowedTCPPorts` for the new services | Direct plain-HTTP access from the LAN, bypassing Caddy and TLS entirely; violates the Tailscale-only requirement | Never open these ports; reach them only through Caddy |
| Reusing one sops secret across all four services | One compromised service's environment leaks the others' credentials | One secret per service, `mode = "0400"` |
| Trusting Caddy's auto-generated root CA on phones without controlling the key | If firebat's `pki/authorities/local` is ever exfiltrated, the holder can MITM any hostname for every enrolled device | Understand the blast radius; if a custom `pki { ca }` root is used instead, protect that key at least as carefully as an SSH host key and keep it out of git |
| Backup files world-readable on `/mnt/backups` | Full database dumps, including password hashes and session data, readable by any local account | `UMask=0077` on the backup unit; service-dump subdirectory `0700 root root` |
| Actual Budget over plain HTTP "just for now" | Budget data transmitted unencrypted; end-to-end encryption silently unavailable so the user believes data is encrypted when it is not | HTTPS with a trusted CA is a hard prerequisite, not a polish item |

## UX Pitfalls

| Pitfall | User Impact | Better Approach |
|---------|-------------|-----------------|
| Logged out on every ser8 reboot (Mealie secret not persisted, or Donetick JWT secret regenerated) | Household stops trusting the service and stops using it | Persist `DATA_DIR`; pin the Donetick JWT secret in sops so it is stable across rebuilds |
| Certificate warning on every phone visit | Nobody uses the service on mobile, which is where chores and shopping lists actually get used | Install the root CA on household devices as part of the milestone, not as a follow-up |
| Importing years of completed Google Tasks into Donetick | The new chores app opens onto a wall of noise on day one | Filter completed items by a cutoff date, or skip them entirely |
| Every imported task due one day early | Silent, systematic wrongness that erodes trust in the whole import | Normalise Takeout due values as dates, not UTC timestamps |
| Four separate logins with four separate passwords | Household members use one weak password everywhere, or give up | Accept it for v1.2 (no SSO is in scope) but document the accounts somewhere the household can find; do not half-build an OIDC path |
| Services reachable only when the person is on Tailscale, with no explanation | "It's broken" reports that are actually "I'm on cellular" | Document the access model in household-facing notes; check Tailscale first when troubleshooting |

## "Looks Done But Isn't" Checklist

- [ ] **Persistence:** service runs fine after `systemctl restart` — verify after a real `reboot`, because only a reboot triggers the root rollback
- [ ] **Mealie:** database restores cleanly — verify a recipe with an uploaded image renders, since images live on disk not in Postgres
- [ ] **Mealie:** homepage loads through Caddy — verify a share link or invite link does not contain `localhost:9000`
- [ ] **Actual:** login page renders — verify a budget opens, transactions load, and the browser console shows no `crypto.subtle`/`SharedArrayBuffer` errors
- [ ] **Actual:** works on the laptop where the CA was installed — verify on a phone that has never seen the CA
- [ ] **Homebox:** service is up — verify `/var/lib/homebox` is under `/persist` and registration is `false`
- [ ] **Donetick:** web UI works — verify the mobile app connects, which requires `public_host` and CORS
- [ ] **Donetick:** signup closed — verify by loading the registration URL, not by reading the config
- [ ] **Backups:** the timer runs green — verify `PRAGMA integrity_check` returns `ok` and `pg_restore --list` parses the dump
- [ ] **Backups:** a dump file exists — verify a full restore into a scratch database/directory and confirm row counts and one real record
- [ ] **Backups:** Actual is backed up — verify `userFiles` blobs are included, not just `account.sqlite`
- [ ] **PostgreSQL:** it starts — verify `SHOW server_version;` matches the pinned package and only one version directory exists under `/persist/var/lib/postgresql`
- [ ] **Firewall:** Caddy routes work — verify `curl http://ser8.local:<port>` from a non-Tailscale LAN device is refused
- [ ] **DNS:** the name resolves — verify it resolves to firebat, not ser8
- [ ] **Secrets:** the service starts — verify `grep -r <secret-fragment> /nix/store` returns nothing
- [ ] **Import:** tasks appear in Donetick — verify recurring chores actually recur, and spot-check three due dates against Google Tasks for off-by-one
- [ ] **Import:** it ran once — verify re-running it produces zero new items

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| Homebox state lost to root rollback (Pitfall 2) | HIGH if noticed late, LOW if noticed on the first reboot | If backups predate the loss, restore the SQLite file and attachments. If not, re-enter inventory by hand. Prevention is the only real answer, which is why the reboot test belongs in the deployment phase, not the backup phase |
| Wrong PostgreSQL major pinned after data exists (Pitfall 9) | MEDIUM | `pg_dumpall` from the running old version, stop Postgres, move the old data directory aside, change the pin, let the new version initdb, restore. Do this with `make test-ser8` first so a failure does not become the boot default |
| Corrupt SQLite backup discovered at restore (Pitfall 11) | HIGH | Fall back to an older backup; if all backups used `cp`, all are suspect. Recover from the live database if the service still runs, then fix the backup method immediately |
| ZFS dedup already enabled with a large DDT (Pitfall 14) | MEDIUM | Create a new dataset with `dedup=off`, `zfs send`/`receive` or copy the data across, destroy the old dataset. Cannot be fixed in place |
| Caddy root CA lost (firebat data directory wiped) | MEDIUM | Caddy regenerates a new root; every enrolled device must re-enrol. Avoid by using an explicit `pki { ca }` block with a root key kept in sops, or by backing up `pki/authorities/local` |
| Donetick JWT secret rotated or lost | LOW | Everyone re-logs in. Annoying, not destructive. Keep the secret in sops so this only happens deliberately |
| Duplicate chores from a re-run import (Pitfall 20) | LOW if a pre-import backup exists, MEDIUM otherwise | Restore the pre-import Donetick SQLite backup and re-run the fixed script. Taking that backup is a one-line step; skipping it turns a 5-minute recovery into an afternoon of manual deletion |
| Open signup exploited on the LAN | LOW technically, uncomfortable socially | Delete the account, close signup, rotate the JWT secret to invalidate sessions |
| Actual data lost with only `account.sqlite` backed up (Pitfall 12) | HIGH | Budgets are gone unless a client still holds a local copy; Actual is local-first, so a laptop or phone that has synced may be able to re-upload. Do not rely on this |

## Pitfall-to-Phase Mapping

Phase names below are descriptive, since v1.2 phases are not yet in `ROADMAP.md`.
The roadmapper should map them onto real phase numbers.

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| 1. DynamicUser vs `/var/lib/<svc>` | Persistence foundation | `systemctl show <unit> -p DynamicUser,StateDirectory` matches the persistence entries; reboot test |
| 2. Homebox static user missed | Persistence foundation + Homebox deploy | `/persist/var/lib/homebox` exists and is populated after a reboot |
| 3. Homebox registration lockout/exposure | Homebox deploy | `/register` returns closed; environment asserts `false` |
| 4. Donetick not packaged | Donetick packaging (dedicated) | `nix eval` resolves the chosen derivation or container; decision recorded in PROJECT.md |
| 5. Mealie secret + image persistence | Mealie deploy + backup/restore | Reboot without logout; restored recipe shows its image |
| 6. Mealie `BASE_URL` and forwarded headers | Mealie deploy | Share link contains `https://mealie.vofi` |
| 7. Actual needs trusted TLS | Gateway/TLS trust (must precede Actual deploy) | Actual loads a budget on a phone with the CA installed |
| 8. Duplicated COOP/COEP, subpath | Actual deploy | `curl -sI` shows exactly one value per header |
| 9. PostgreSQL version pinned by stateVersion | Postgres foundation | `SHOW server_version;` matches the explicit pin |
| 10. Postgres data dir ownership | Persistence foundation | Cold boot with no manual `chown` needed |
| 11. `cp` of live SQLite | Backup/restore | `PRAGMA integrity_check` returns `ok` in the unit's own output |
| 12. Actual's split state | Backup/restore | Restored instance opens a named budget with transactions |
| 13. `pg_dump` under hardening | Backup/restore | Timer-triggered run succeeds, not just a manual root run |
| 14. ZFS dedup on backup target | Backup/restore (first design step) | `zfs get dedup` on the chosen dataset returns `off` |
| 15. Caddy WebSocket header copying | Gateway/vhost | No `header_up` in the four new vhosts; sync/live features work |
| 16. Donetick signup + JWT secret | Donetick deploy | Signup closed; `grep` of `/nix/store` finds no secret; mobile app connects |
| 17. sops-nix vs DynamicUser | Secrets, or per-service deploy | Every secret arrives via `EnvironmentFile`; no `/run/secrets` reads in app logs |
| 18. Port collisions and binding | Roadmap design, verified in gateway | `ss -tlnp` matches the allocation table; off-Tailscale probe refused |
| 19. Takeout recurrence gap | Google Tasks import (archive inspection gate) | Recurring chores exist in Donetick and recur; three spot-checked due dates match |
| 20. Non-idempotent import | Google Tasks import | Second run creates zero items; pre-import backup exists |
| 21. DNS rewrite pointed at ser8 | Gateway/DNS | `dig +short <name>.vofi` returns firebat |

**Ordering implications for the roadmap:**

1. Persistence foundation and PostgreSQL pinning must come **first**, before any service is enabled. Pitfalls 1, 2, 9, and 10 are all cheap to prevent and expensive to fix after data exists.
2. The gateway/TLS-trust phase must precede the Actual phase. Pitfall 7 makes Actual non-functional without it, so Actual should be the **last** of the four services.
3. Donetick packaging must precede the Google Tasks import phase and should be sized as its own phase (Pitfall 4).
4. Homebox and Donetick both need a two-stage deploy (open signup, create accounts, close signup) that must be encoded in the plan, not improvised.
5. Backup/restore should come after at least Mealie and one SQLite service exist, so the restore drill exercises both engines, but before the Google Tasks import, so a pre-import backup is available.

**Research flags for phases:**

- Donetick packaging: needs its own research pass on `buildGoModule` plus an embedded frontend if the native path is chosen.
- Google Tasks import: needs the real Takeout archive in hand before any planning; the schema cannot be assumed from documentation.
- Everything else is covered by this document plus the nixpkgs module sources.

## Sources

**Primary (read verbatim from the pinned `nixos-25.11` branch):**

- `nixos/modules/services/web-apps/mealie.nix` — https://raw.githubusercontent.com/NixOS/nixpkgs/nixos-25.11/nixos/modules/services/web-apps/mealie.nix (HIGH)
- `nixos/modules/services/web-apps/actual.nix` — https://raw.githubusercontent.com/NixOS/nixpkgs/nixos-25.11/nixos/modules/services/web-apps/actual.nix (HIGH)
- `nixos/modules/services/web-apps/homebox.nix` — https://raw.githubusercontent.com/NixOS/nixpkgs/nixos-25.11/nixos/modules/services/web-apps/homebox.nix (HIGH)
- `nixos/modules/module-list.nix` on `nixos-25.11` and `master`, plus a 404 on `pkgs/by-name/do/donetick/package.nix`, establishing that Donetick is absent (HIGH)
- Package versions in `nixos-25.11`: mealie 3.9.2, actual-server 26.6.0, homebox 0.24.0 (HIGH)
- This repository: `flake.nix`, `hosts/ser8/configuration.nix`, `hosts/ser8/impermanence.nix`, `hosts/ser8/disko-config.nix`, `modules/gateway/Caddyfile`, `modules/servers/backup.nix` (HIGH)

**Upstream documentation:**

- Mealie backend configuration — https://docs.mealie.io/documentation/getting-started/installation/backend-config/ (MEDIUM)
- Actual Budget configuration — https://actualbudget.org/docs/config/ (MEDIUM)
- Actual Budget reverse proxies — https://actualbudget.org/docs/config/reverse-proxies/ (MEDIUM)
- Actual Budget HTTPS — https://actualbudget.org/docs/config/https/ (MEDIUM)
- Donetick `config/selfhosted.yaml` — https://github.com/donetick/donetick/blob/main/config/selfhosted.yaml (HIGH, read verbatim)
- Caddy automatic HTTPS and local CA — https://caddyserver.com/docs/automatic-https (MEDIUM)
- Caddy `reverse_proxy` directive — https://caddyserver.com/docs/caddyfile/directives/reverse_proxy (MEDIUM)
- Google Tasks export — https://support.google.com/tasks/answer/10017961 (MEDIUM)

**Issue trackers:**

- impermanence #93, DynamicUser + StateDirectory — https://github.com/nix-community/impermanence/issues/93 (MEDIUM)
- impermanence #254, `/var/lib/private` created `0755` — https://github.com/nix-community/impermanence/issues/254 (MEDIUM)
- nixpkgs #321623, Mealie `/run/secrets` PermissionError under DynamicUser + sops-nix — https://github.com/NixOS/nixpkgs/issues/321623 (MEDIUM)
- donetick #619, reverse proxy / internal network — https://github.com/donetick/donetick/issues/619 (MEDIUM, unresolved upstream)
- donetick #254, JWT `invalid number of segments` — https://github.com/donetick/donetick/issues/254 (MEDIUM)
- actual-server #371, `ACTUAL_TRUSTED_PROXIES` ineffective — https://github.com/actualbudget/actual-server/issues/371 (LOW, not independently verified)
- mealie #5023, #4197, #6038, reverse-proxy login and OIDC scheme issues (MEDIUM)
- caddy #7292, HTTP/2 `invalid Upgrade request header` — https://github.com/caddyserver/caddy/issues/7292 (MEDIUM)

**Community:**

- NixOS Discourse, systemd dynamic user persistent directories — https://discourse.nixos.org/t/systemd-dynamic-user-persistant-directories/51468 (LOW)
- NixOS Discourse, crowdsec and DynamicUser — https://discourse.nixos.org/t/nixos-crowdsec-and-dynamicuser/73815 (LOW)
- NixOS 25.11 release notes, `postgresql.target` and stateVersion-gated defaults — https://nixos.org/manual/nixos/stable/release-notes.html (MEDIUM)
- SQLite forum, hot backup in WAL mode by copying — https://sqlite.org/forum/forumpost/2ea989bbe9 (MEDIUM)
- Google Calendar Community, Takeout recurrence missing from JSON — https://support.google.com/calendar/thread/244906743 (LOW)
- `Nockiro/gtask-exporthelper`, recurrence not recoverable from Takeout or the Tasks API — https://github.com/Nockiro/gtask-exporthelper (LOW)

**Caveat:** the shared research cache (`~/.gsd/research-cache`) was not writable in this sandbox (`EPERM`), so digests from this run were not persisted for reuse.

---
*Pitfalls research for: self-hosted household services on an impermanence-based NixOS 25.11 homelab*
*Researched: 2026-08-16*
