# Architecture Research

**Domain:** Self-hosted household web services integrated into an existing NixOS flake homelab (v1.2 Household Stack)
**Researched:** 2026-08-16
**Confidence:** HIGH for repo integration points (read directly from source), HIGH for nixpkgs module behaviour (read from the pinned rev `e4bae1bd10c9c57b2cf517953ab70060a828ee6f`), MEDIUM for Donetick runtime details (upstream docs via web search; no nixpkgs module exists to verify against)

> Prior v1.1 observability research was archived to `.planning/milestones/v1.1-research/` before this file was replaced.

---

## Standard Architecture

### System Overview

```
┌──────────────────────────────────────────────────────────────────────────┐
│  pi4  192.168.68.56          DNS                                          │
│  modules/dns/adguard-home.nix -> services.adguardhome.settings.filtering  │
│  4 NEW rewrites: mealie|donetick|homebox|actual .vofi -> 192.168.68.63    │
└───────────────────────────────┬──────────────────────────────────────────┘
                                │ DNS answer 192.168.68.63
┌───────────────────────────────▼──────────────────────────────────────────┐
│  firebat  192.168.68.63       GATEWAY + MONITORING                        │
│  modules/gateway/Caddyfile  (local_certs, skip_install_trust)             │
│  4 NEW vhosts: <name>.vofi { reverse_proxy ser8.local:<port> }            │
│  modules/gateway/prometheus.nix  4 NEW blackbox-http targets (optional)   │
└───────────────────────────────┬──────────────────────────────────────────┘
                                │ HTTP to ser8.local:<port>
┌───────────────────────────────▼──────────────────────────────────────────┐
│  ser8  192.168.68.65          APPLICATION HOST                            │
│                                                                           │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐                     │
│  │ mealie   │ │ donetick │ │ homebox  │ │ actual   │   NEW services       │
│  │ :9000    │ │ :2021    │ │ :7745    │ │ :5006    │                      │
│  └────┬─────┘ └────┬─────┘ └────┬─────┘ └────┬─────┘                     │
│       │            │            │            │                            │
│  ┌────▼──────┐  ┌──▼────────────▼────────────▼──┐                        │
│  │ postgres  │  │ SQLite files under /var/lib/* │                        │
│  │ (NEW,     │  └────────────────┬──────────────┘                        │
│  │  unix     │                   │                                        │
│  │  socket)  │                   │                                        │
│  └────┬──────┘                   │                                        │
│       └──────────┬───────────────┘                                        │
│                  │ state lives at /var/lib/<svc>                          │
├──────────────────▼────────────────────────────────────────────────────────┤
│  IMPERMANENCE  environment.persistence."/persist" (hosts/ser8/impermanence)│
│  rpool/safe/persist  <- ZFS auto-snapshot (frequent/hourly/daily/...)      │
│  rpool/local/root    <- rolled back to @blank on every boot                │
├───────────────────────────────────────────────────────────────────────────┤
│  NEW household-backup.timer (nightly)                                     │
│    pg_dump -Fc mealie           ─┐                                        │
│    sqlite3 VACUUM INTO donetick  ├─> /mnt/backups/household/<svc>/<date>   │
│    sqlite3 VACUUM INTO homebox   │   zpool backup (raidz2, 4x6TB)          │
│    sqlite3 VACUUM INTO actual   ─┘                                        │
└───────────────────────────────────────────────────────────────────────────┘
```

### Component Responsibilities

| Component | Responsibility | Where it lives in this repo |
|-----------|----------------|-----------------------------|
| Reusable service module | Declares the service user/group, port, firewall, sane defaults, `enable = lib.mkDefault false` | NEW `modules/household/<svc>.nix` (mirrors `modules/media/sonarr.nix`) |
| Host policy module | Enables the service, owns its SOPS secrets and templates, sets `BASE_URL`/host-specific settings, registers its backup job | NEW `hosts/ser8/household/<svc>.nix` (mirrors `hosts/ser8/media/sonarr.nix`) |
| Persistence declaration | Declares stateful paths so ZFS root rollback does not destroy them | MODIFIED `hosts/ser8/impermanence.nix` |
| Secret material | Encrypted at rest, decrypted to `/run/secrets` by sops-nix using the SSH host key | MODIFIED `secrets/ser8.yaml` via `make sops-edit-ser8` |
| Reverse proxy | Terminates TLS with Caddy's local CA, maps `<name>.vofi` to `ser8.local:<port>` | MODIFIED `modules/gateway/Caddyfile` |
| DNS | Answers `<name>.vofi` with firebat's IP | MODIFIED `modules/dns/adguard-home.nix` |
| Backup engine | Nightly consistent logical dumps to the ZFS `backup` pool, with retention | NEW `modules/household/backup.nix` + `hosts/ser8/household/backup.nix` |
| Verification | Post-deploy smoketests wired through `deploy.yaml` | NEW `scripts/smoketests/household/`, MODIFIED `deploy.yaml` |

---

## Answers to the Seven Questions

### 1. Module layout

**Recommendation: yes, a new `modules/household/` group plus a matching `hosts/ser8/household/` policy directory.**

The repo already runs a strict two-layer split, and Phase 08 of the previous milestone made it explicit.
`modules/media/sonarr.nix` is the reusable half: it creates `users.users.sonarr`, sets `services.sonarr.enable = lib.mkDefault false`, forces the group, sets `UMask`, and opens the firewall port under `lib.mkIf config.services.sonarr.enable`.
`hosts/ser8/media/sonarr.nix` is the host-policy half: it does `services.sonarr.enable = true`, declares `sops.secrets."sonarr_admin_password"` and `sops.templates."sonarr-config.xml"`, wires the exporter, and contributes to the shared deployment unit.

Two recorded Phase 08 decisions govern this split and should be honoured verbatim (from `.planning/STATE.md`):

> "Keep each Arr service's enablement, secrets, template, exporter instance, and deployment contribution together in one host module."

> "Keep shared SOPS policy limited to file, format, and host age-key defaults while service modules own every active declaration."

Concrete layout:

```
modules/household/
├── default.nix          # imports the five below, mirrors modules/media/default.nix
├── mealie.nix           # users.users.mealie, static-user override, firewall 9000
├── donetick.nix         # options.services.donetick + package (mirrors modules/subgen/default.nix)
├── homebox.nix          # firewall 7745, HBOX_WEB_* defaults
├── actual.nix           # users.users.actual, firewall 5006
└── backup.nix           # options.household.backup.jobs.<name> = { type; ... }

packages/donetick/
└── default.nix          # NEW, mirrors packages/subgen/default.nix

hosts/ser8/household/
├── default.nix          # imports the below, mirrors hosts/ser8/media/default.nix
├── postgresql.nix       # services.postgresql version pin + persistence policy
├── mealie.nix           # enable, BASE_URL, ALLOW_SIGNUP, database.createLocally, backup job
├── donetick.nix         # enable, sops.secrets.donetick_jwt_secret + template, backup job
├── homebox.nix          # enable, HBOX_OPTIONS_ALLOW_REGISTRATION, backup job
├── actual.nix           # enable, port, backup job
└── backup.nix           # destination dataset, retention, timer schedule
```

Wiring is two one-line edits:

- `flake.nix` lines 232-241, `nixosConfigurations.ser8.modules`: add `./modules/household` next to the existing `./modules/media`, `./modules/nordvpn`, `./modules/automation`.
- `hosts/ser8/configuration.nix` lines 11-15, `imports`: add `./household` next to the existing `./media`.

Do not put the reusable modules in `x86Modules` in `flake.nix`; that list is for things firebat also needs (`./modules/subgen`), and household services are ser8-only.
Do not import `modules/household` from `modules/servers/default.nix`; that group is applied to every host including the Pis.

### 2. Impermanence persistence and tmpfiles ownership

`hosts/ser8/impermanence.nix` uses a two-part convention that every new service must follow.

**Part A: a plain string entry in `environment.persistence."/persist".directories`.**
The file carries an explicit comment on line 55 explaining why the string form is used rather than the attribute form:

```nix
# Services - Don't specify user/group for services that might not exist yet
"/var/lib/jellyfin"
"/var/lib/sonarr"
...
"/var/lib/postgresql"
```

The attribute form (`{ directory = ...; mode = ...; }`) is reserved for directories that need a non-default mode before any user exists, for example `/var/lib/private` at mode `0700` and `/var/lib/docker` at mode `0710`.

**Part B: a `systemd.tmpfiles.rules` entry against the `/persist` side, not the `/var/lib` side.**
Lines 122-141 show the pattern:

```nix
"d /persist/var/lib/sonarr 0755 sonarr media -"
"d /persist/var/lib/radarr 0755 radarr media -"
"d /persist/var/lib/bazarr 0700 bazarr media -"
"d /persist/var/lib/private/prowlarr 0755 prowlarr prowlarr -"
"d /persist/var/lib/sabnzbd 0755 sabnzbd media -"
```

Jellyfin is the one service that gets rules on both sides plus a recursive `Z` fixup, because its directory is shared with the `media` group:

```nix
"d /persist/var/lib/jellyfin 0755 jellyfin media -"
"Z /persist/var/lib/jellyfin 0755 jellyfin media - -"
"d /var/lib/jellyfin 0755 jellyfin media -"
"Z /var/lib/jellyfin 0755 jellyfin media -"
```

Household services are single-owner and share nothing, so they need only the `/persist` side `d` rule.

**Exact additions required.**

To `environment.persistence."/persist".directories`:

```nix
# Household stack
"/var/lib/mealie"
"/var/lib/donetick"
"/var/lib/homebox"
"/var/lib/actual"
# "/var/lib/postgresql" is ALREADY PRESENT at line 60 - do not duplicate
```

To `systemd.tmpfiles.rules`:

```nix
# Household stack
"d /persist/var/lib/mealie 0750 mealie mealie -"
"d /persist/var/lib/donetick 0750 donetick donetick -"
"d /persist/var/lib/homebox 0700 homebox homebox -"
"d /persist/var/lib/actual 0700 actual actual -"
"d /mnt/backups/household 0750 root root -"
```

Plus: **uncomment and correct line 112**, which is currently dead:

```nix
# "d /persist/var/lib/postgresql 0700 postgres postgres -"
```

PostgreSQL refuses to start if its data directory is group- or world-accessible, so `0700 postgres postgres` is correct.
That line was commented out because nothing on ser8 has ever enabled PostgreSQL; enabling it for Mealie makes the rule live.

**The DynamicUser trap.**
Two of the four upstream modules use `DynamicUser = true` by default, which relocates state to `/var/lib/private/<svc>` and allocates a transient UID:

- `services.mealie`: `DynamicUser = true; User = "mealie"; StateDirectory = "mealie";` (nixpkgs `nixos/modules/services/web-apps/mealie.nix`)
- `services.actual`: `DynamicUser = true` unless both `user` and `group` are set (nixpkgs `nixos/modules/services/web-apps/actual.nix`)
- `services.homebox`: already uses a static `homebox` user and group, no override needed

Under `DynamicUser`, `/var/lib/private` is already persisted so data does technically survive, but you cannot write a meaningful tmpfiles ownership rule (the UID is transient), the path stops matching the repo's `/persist/var/lib/<svc>` convention, and sops-nix secrets under `/run/secrets` become unreadable to the unit.

**Recommendation: force static users for Mealie and Actual.**
Every other service in this repo has an explicit `users.users.<name> = { isSystemUser = true; group = ...; }` (`modules/media/jellyfin.nix`, `modules/media/sonarr.nix`, `modules/automation/frigate.nix`).
Follow that.

```nix
# modules/household/mealie.nix
users.users.mealie = lib.mkIf config.services.mealie.enable {
  isSystemUser = true;
  group = "mealie";
  home = "/var/lib/mealie";
  description = "Mealie";
};
users.groups.mealie = lib.mkIf config.services.mealie.enable { };

systemd.services.mealie.serviceConfig = lib.mkIf config.services.mealie.enable {
  DynamicUser = lib.mkForce false;
  User = "mealie";
  Group = "mealie";
};
```

Actual is easier: its module exposes first-class `user` and `group` options (defaulting to `null` for DynamicUser), but the option documentation states the account "won't be automatically created by the service", so `users.users.actual` must still be declared manually.

Prowlarr is the repo's counter-example: it kept `DynamicUser` and consequently needed `"d /persist/var/lib/private/prowlarr 0755 prowlarr prowlarr -"`.
That works, but it is the outlier and it does not consume SOPS secrets directly.

### 3. Secrets wiring

There are three distinct patterns in the repo. Pick per service.

**Pattern A: secret file read directly by the consumer (simplest, most common).**

```nix
# hosts/ser8/configuration.nix:167-176
sops.secrets = {
  "nordvpn_access_token" = { owner = "root"; group = "root"; mode = "0600"; };
  "gmail_smtp_password" = { mode = "0400"; };
};
# consumed at hosts/ser8/configuration.nix:202
nordvpn.accessTokenFile = config.sops.secrets.nordvpn_access_token.path;
```

**Pattern B: SOPS template rendered to an env file, delivered via `EnvironmentFile` (the right pattern for Donetick).**
This is `modules/automation/frigate.nix` lines 17-41 and 485-494, and it is the only pattern in the repo that produces a systemd `EnvironmentFile`:

```nix
sops.secrets = lib.mkIf config.services.frigate.enable {
  "frigate_cam_user" = { owner = "root"; group = "root"; mode = "0600"; };
  "frigate_cam_pass" = { owner = "root"; group = "root"; mode = "0600"; };
};

sops.templates = lib.mkIf config.services.frigate.enable {
  "frigate.env" = {
    content = ''
      FRIGATE_CAM_USER=${config.sops.placeholder."frigate_cam_user"}
      FRIGATE_CAM_PASS=${config.sops.placeholder."frigate_cam_pass"}
    '';
    owner = "frigate";
    group = "frigate";
    mode = "0600";
  };
};

systemd.services.go2rtc = lib.mkIf config.services.frigate.enable {
  after = [ "sops-nix.service" ];
  wants = [ "sops-nix.service" ];
  serviceConfig = {
    DynamicUser = lib.mkForce false;
    User = lib.mkForce "frigate";
    Group = lib.mkForce "frigate";
    EnvironmentFile = config.sops.templates."frigate.env".path;
  };
};
```

Note that this precedent already performs the `DynamicUser = lib.mkForce false` override for exactly the reason described in section 2.

**Pattern C: `LoadCredential` for hardened units that should not read `/run/secrets` directly.**

```nix
# modules/dns/adguard-exporter.nix:69
LoadCredential = "adguard-password:${config.sops.secrets.adguard_password.path}";
```

**What each new service needs.**

| Service | Secret required? | Pattern |
|---------|------------------|---------|
| Mealie | **No, at minimum.** `database.createLocally = true` uses peer auth over `/run/postgresql` (`POSTGRES_URL_OVERRIDE = "postgresql://mealie:@/mealie?host=/run/postgresql"`), so there is no Postgres password. Mealie generates and stores its own session secret in `DATA_DIR`. | If SMTP or OIDC is added later, use Pattern B and feed the rendered file to the module's own `credentialsFile` option, which is documented as taking an `EnvironmentFile`-format file. |
| Donetick | **Yes.** `DT_JWT_SECRET` must not be the upstream placeholder. | Pattern B: `sops.secrets.donetick_jwt_secret` + `sops.templates."donetick.env"` + `EnvironmentFile`. |
| Homebox | No. | Pattern B only if `HBOX_MAILER_*` is configured. |
| Actual | No at deploy time; the server password is set in-app on first visit. | The module supports `settings.<key>._secret = "/path"` through `utils.genJqSecretsReplacementSnippet`, which is the mechanism to use if a secret is ever needed. |

**Rules that apply to all of them.**

- Secret names in `secrets/ser8.yaml` are flat top-level snake_case keys (`nordvpn_access_token`, `gmail_smtp_password`, `sonarr_api_key`). Follow that: `donetick_jwt_secret`.
- Edit only via `make sops-edit-ser8`.
- Do **not** redeclare `sops.defaultSopsFile`, `sops.defaultSopsFormat`, or `sops.age.sshKeyPaths` in new modules. Those defaults are already set in `hosts/ser8/configuration.nix:163-166` and `hosts/ser8/media/sops.nix`. New modules add only `sops.secrets` and `sops.templates`, per the Phase 08 decision quoted above.
- There is no reason to create a `hosts/ser8/household/sops.nix`; the host defaults already cover the new modules.

### 4. Backup architecture

**Current state: there is no backup service on ser8.** This is the largest gap in the milestone.

What actually exists:

| Thing | File | Reality |
|-------|------|---------|
| `modules/servers/backup.nix` | applied to every host via `modules/servers/default.nix` | Installs `borgbackup`, `restic`, `rsync` and writes `/etc/backup/backup-script.sh`, a template whose body is three `echo` statements and a commented-out `rsync` example. Nothing invokes it. **This is dead scaffolding.** |
| `zpool backup` | `hosts/ser8/disko-config.nix` | RAID-Z2 across 4x6TB, `recordsize=1M`, `compression=lz4`. Dataset `backup/backups` mounts at `/mnt/backups` with `dedup = "on"`. Dataset tree `backup/cameras/{recordings,clips}` holds Frigate video with `com.sun:auto-snapshot = "false"`. |
| `/mnt/backups` | `hosts/ser8/impermanence.nix:139` | Only a tmpfiles rule: `"d /mnt/backups 0755 root root -"`. `.planning/SER8-ZFS-MIRROR-MIGRATION.md` records the dataset as "effectively empty". |
| `services.zfs.autoSnapshot` | `hosts/ser8/configuration.nix:99-106` | Enabled host-wide: 4 frequent, 24 hourly, 7 daily, 4 weekly, 12 monthly. Because `rpool/safe/persist` does not set `com.sun:auto-snapshot = false`, **all of `/persist` is already snapshotted**. |
| `sanoid` | `hosts/ser8/configuration.nix:245` | Present in `environment.systemPackages` but never configured. More dead scaffolding. |

**Implication for the design.** The nightly job is not the only copy of the data; `/persist` snapshots already provide crash-consistent point-in-time recovery on the same pool.
What the nightly job adds is a *logically consistent, restorable artifact on a different pool* (raidz2, separate disks), which is exactly what a live PostgreSQL data directory and a WAL-mode SQLite file cannot reliably be recovered from via a snapshot alone.
Framing the phase goal that way prevents the roadmap from over-building.

**Recommended slot-in.**

Create a new dataset rather than writing into `backup/backups`:

```nix
# hosts/ser8/disko-config.nix, zpool.backup.datasets
"household" = {
  type = "zfs_fs";
  options = {
    mountpoint = "/mnt/backups/household";
    compression = "zstd";
    recordsize = "128K";
    dedup = "off";
    "com.sun:auto-snapshot" = "true";
  };
};
```

Rationale, and this matters: `backup/backups` sets `dedup = "on"`.
ZFS dedup costs roughly 1-5 GB of ARC per TB of unique data and cannot be undone for blocks already written.
Nightly dumps of the same databases look like an attractive dedup target, but zstd compression plus ZFS snapshots achieve the same space outcome without the memory tax, and the ARC on this host is already capped at 8 GB by `boot.kernelParams`.
Setting `dedup = "off"` and `recordsize = "128K"` on a dedicated dataset avoids inheriting both the dedup flag and the video-tuned 1M record size.
Setting `com.sun:auto-snapshot = "true"` means the existing `services.zfs.autoSnapshot` schedule gives free retention depth on top of whatever the job's own retention prunes.

**Critical operational gotcha: disko does not create datasets on a live pool.**
`hosts/ser8/disko-config.nix` is executed by disko only at install time; `boot.zfs.extraPools = [ "backup" ]` merely imports the already-existing pool at boot.
Adding a dataset to `disko-config.nix` on a running system is documentation-of-record only.
The dataset must be created once by hand (`zfs create -o mountpoint=/mnt/backups/household ... backup/household`), or the backup unit must create it when missing.
Prefer creating it by hand as an explicit, logged deployment step, and recording the same definition in `disko-config.nix` so a rebuild-from-scratch reproduces it.
Flag this in the phase plan; it is precisely the kind of thing that silently makes the timer write into the root filesystem instead.

**Module shape.** A single reusable module with a small typed interface, so each service module registers itself with one line:

```nix
# modules/household/backup.nix
options.household.backup = {
  enable = lib.mkEnableOption "nightly household database backups";
  destination = lib.mkOption { type = lib.types.path; default = "/mnt/backups/household"; };
  retentionDays = lib.mkOption { type = lib.types.ints.positive; default = 30; };
  jobs = lib.mkOption {
    type = lib.types.attrsOf (lib.types.submodule { options = {
      type = lib.mkOption { type = lib.types.enum [ "postgres" "sqlite" ]; };
      database = lib.mkOption { type = lib.types.str; default = ""; };   # postgres
      path = lib.mkOption { type = lib.types.path; };                    # sqlite
      unit = lib.mkOption { type = lib.types.str; };                     # for ordering
    }; });
    default = { };
  };
};
```

Registration from each host module:

```nix
# hosts/ser8/household/mealie.nix
household.backup.jobs.mealie = { type = "postgres"; database = "mealie"; unit = "mealie.service"; };

# hosts/ser8/household/donetick.nix
household.backup.jobs.donetick = { type = "sqlite"; path = "/var/lib/donetick/donetick.db"; unit = "donetick.service"; };
```

The generated unit runs `pg_dump -Fc -d <db>` for PostgreSQL jobs and `sqlite3 <path> ".backup '<dest>'"` (or `VACUUM INTO`) for SQLite jobs.
Never `cp` a live WAL-mode SQLite file; that is the proposal's stated requirement and it is correct.

Unit conventions to copy from the repo:

```nix
systemd.services.household-backup = {
  description = "Nightly household database backups";
  unitConfig.RequiresMountsFor = [ cfg.destination ];   # matches hosts/ser8/media/permissions.nix:48
  serviceConfig = { Type = "oneshot"; };
};
systemd.timers.household-backup = {
  wantedBy = [ "timers.target" ];
  timerConfig = { OnCalendar = "daily"; Persistent = true; RandomizedDelaySec = "30m"; };
};
```

`Persistent = true` matters on a host that reboots.
The repo's only existing timer, `modules/dns/adguard-home.nix:236-242`, uses `OnBootSec`/`OnUnitActiveSec`, which is the wrong shape for a nightly job; do not copy it.

**Where does `modules/servers/backup.nix` go?**
Per the repo's stated philosophy ("Replace, don't deprecate ... Proactively flag dead code"), do not extend the stub.
Recommend deleting `environment.etc."backup/backup-script.sh"` and the unused `restic`/`borgbackup` packages in the same phase that lands the real backup module, or explicitly deferring that cleanup with a note.
Keep `users.users.backup` only if something actually consumes it; nothing currently does.

**Sequencing note.** `.planning/SER8-ZFS-MIRROR-MIGRATION.md` plans to stage roughly 7.8 TB of media onto the `backup` pool during a media-pool migration, leaving about 3.28 TB free.
That migration does not touch the `backup` pool's topology or the `backup/backups` dataset, so household backups are safe from it, but the two activities should not overlap in time.

### 5. Caddy and DNS changes

**Caddy is fully declarative.** `modules/gateway/caddy.nix:41` sets `configFile = ./Caddyfile`, so `modules/gateway/Caddyfile` is the single source of truth and ships to `/etc/caddy/caddy_config`.

Add four vhosts, matching the minimal form used by every `*arr` service:

```
mealie.vofi {
	reverse_proxy ser8.local:9000
}

donetick.vofi {
	reverse_proxy ser8.local:2021
}

homebox.vofi {
	reverse_proxy ser8.local:7745
}

actual.vofi {
	reverse_proxy ser8.local:5006
}
```

Naming: the existing convention is the service name, not the function (`jellyfin.vofi`, `sonarr.vofi`, `prowlarr.vofi`), with exactly one exception (`torrent.vofi` for qBittorrent).
The proposal's `recipes/chores/inventory/budget` scheme would break that convention for all four at once.
Recommend service names; surface the alternative for the user to override.

The Caddyfile uses **tab indentation** and is validated by `make fmt-caddy`.
Do not indent with spaces.

**AdGuard DNS is declaratively managed in this repo, with a caveat worth stating precisely.**
`modules/dns/adguard-home.nix:139-186` declares `services.adguardhome.settings.filtering.rewrites` as a list of `{ domain; answer; }` attrsets, and the module is configured with `mutableSettings = true` (line 39).

Reading the nixpkgs module at the pinned rev confirms what that flag means: the Nix-declared settings are **merged into the existing `/var/lib/AdGuardHome/AdGuardHome.yaml` on every start, taking precedence over changes made in the web UI**.
So adding a rewrite in Nix is authoritative; the mutable flag only preserves UI-set values for keys Nix does not declare, which is how the admin password survives.

Add four rewrites in the "Caddy managed services" block, pointing at firebat like every other `.vofi` entry:

```nix
{ domain = "mealie.vofi";   answer = "192.168.68.63"; }
{ domain = "donetick.vofi"; answer = "192.168.68.63"; }
{ domain = "homebox.vofi";  answer = "192.168.68.63"; }
{ domain = "actual.vofi";   answer = "192.168.68.63"; }
```

**Both of these changes are self-testing.** See section 6.

**Optional, decide explicitly:** the Caddyfile also carries a parallel set of `https://<name>.shad-bangus.ts.net { bind tailscale/<name>; reverse_proxy 192.168.68.65:<port> }` blocks for remote access via the `caddy-tailscale` plugin.
Each one creates a separate Tailscale node consuming the shared auth key from `sops.secrets.tailscale_authkey`.
The Caddyfile carries a long comment block explaining that these blocks **must use static IPs, not `.local` mDNS names**, because tsnet-bound Caddy instances cannot receive mDNS broadcasts.
The v1.2 requirement only names `<name>.vofi`, so treat the ts.net blocks as an optional follow-on; if added, also add matching `blackbox-tls` targets at `modules/gateway/prometheus.nix:204-225`.

**Monitoring (optional, cheap):** add four entries to the `blackbox-http` job at `modules/gateway/prometheus.nix:141-152`, using direct IPs per the recorded Phase 4 decision ("Blackbox probe targets use direct IPs, not `.local` mDNS"):

```nix
"http://192.168.68.65:9000" # Mealie (ser8)
"http://192.168.68.65:2021" # Donetick (ser8)
"http://192.168.68.65:7745" # Homebox (ser8)
"http://192.168.68.65:5006" # Actual (ser8)
```

### 6. Smoketests

**How the wiring works.** `deploy.yaml` gives each host exactly one smoketest entrypoint, and the Makefile resolves it:

```makefile
# Makefile:37
get-host-smoketests = $(shell yq eval '.hosts."$(1)".smoketests' $(DEPLOY_YAML))
# Makefile:280-281
smoketests-%:
	@$(call get-host-smoketests,$*) $*
```

`deploy.yaml` currently maps `ser8` to `./scripts/smoketests/media/all.sh`.
Note that `scripts/smoketests/nordvpn/all.sh` exists but is **orphaned**; nothing invokes it.

**Two established shapes for `all.sh`:**

- Aggregator (`scripts/smoketests/gateway/all.sh`, `dns/all.sh`): a `TESTS=(...)` array of `test-*.sh` paths, each invoked with `"$@"`.
- Monolith (`scripts/smoketests/media/all.sh`): one script that sources `./scripts/lib/all.sh` and `./scripts/smoketests/lib/services.sh`, resolves `get_ip`/`get_user` from `deploy.yaml`, iterates a `"name:domain:port:unit"` array through `test_media_service`, then runs bespoke permission checks over SSH.

Prefer the aggregator shape for new work; `CLAUDE.md` asks for "descriptive `test-*.sh` names for individual smoketests" with area entrypoints named `all.sh`.

**The important discovery: the gateway and DNS smoketests extend themselves.**

- `scripts/smoketests/gateway/test-caddy.sh` runs `caddy adapt --config modules/gateway/Caddyfile | jq` to extract **every** server/upstream pair, then probes each one. Adding four vhosts automatically adds four gateway assertions.
- `scripts/smoketests/dns/test-dns.sh` runs `sudo yq -r ".filtering.rewrites[].domain" /var/lib/AdGuardHome/AdGuardHome.yaml` on pi4 and resolves **every** rewrite it finds. Adding four rewrites automatically adds four DNS assertions.

So no gateway or DNS smoketest code needs to be written.
Only the ser8-side household tests are new.

**Recommended new files:**

```
scripts/smoketests/household/all.sh              # aggregator over the three below
scripts/smoketests/household/test-services.sh    # reuses test_media_service from smoketests/lib/services.sh
scripts/smoketests/household/test-persistence.sh # the highest-value test in this milestone
scripts/smoketests/household/test-backups.sh
scripts/backup/restore-household.sh              # on-demand restore drill, not run by deploy
```

`test-services.sh` reuses the existing helper verbatim.
Despite its name, `test_media_service` is generic: it takes `name domain port unit host ip user` and falls back to probing the backend over SSH when the gateway path fails.

```bash
HOUSEHOLD_SERVICES=(
	"Mealie:mealie.vofi:9000:mealie"
	"Donetick:donetick.vofi:2021:donetick"
	"Homebox:homebox.vofi:7745:homebox"
	"Actual:actual.vofi:5006:actual"
)
```

`test-persistence.sh` is the one that earns its keep, because the milestone's stated top risk is "all stateful paths declared in impermanence; data survives reboot".
Assert over SSH, for each of `/var/lib/{mealie,donetick,homebox,actual,postgresql}`:

- the path is backed by `/persist` (`findmnt -no SOURCE <path>` resolves under `/persist`, or `findmnt -T <path>` reports the persist dataset)
- the corresponding `/persist/var/lib/<svc>` exists with the expected owner and mode
- the service's database file exists and is non-zero under that path

This catches the failure mode where a service starts, writes to the rolled-back root, and looks perfectly healthy right up until the next reboot.

`test-backups.sh`:

- `/mnt/backups/household` is a ZFS mountpoint on the `backup` pool (`zfs list -H -o name /mnt/backups/household` returns `backup/household`, not `backup/backups`)
- for each service, the newest artifact is younger than 26 hours and non-empty
- the artifact is structurally valid: `pg_restore --list <dump> >/dev/null` for Mealie, `sqlite3 <copy> "PRAGMA integrity_check"` returning `ok` for the other three

`scripts/backup/restore-household.sh` is the "demonstrated restore" the milestone requires: restore the newest Mealie dump into a scratch database (`pg_restore -d mealie_restore_test`), count rows in the recipe tables, drop the scratch database, report.
Run it manually once per milestone; do not put it in `deploy.yaml`.

**`deploy.yaml` change.** Since the key takes a single path, add a host-level aggregator:

```yaml
ser8:
  smoketests: "./scripts/smoketests/ser8/all.sh"
```

with `scripts/smoketests/ser8/all.sh` invoking `media/all.sh` then `household/all.sh`.
This is also the natural place to finally wire in the orphaned `nordvpn/all.sh`, though that is adjacent scope: flag it, do not silently expand the phase.

**Pending todo in `.planning/STATE.md` that touches this:** "Convert gateway, media, DNS, and NordVPN smoketest behavior into NixOS Python integration tests."
The household smoketests should not block on that migration, but the roadmap should not invest heavily in bash slated for replacement either.
Keep the new scripts thin.

### 7. Suggested build order

Dependency graph:

```
                       ┌─────────────────────────────────┐
                       │ A. Household scaffold + Mealie  │
                       │    modules/household/           │
                       │    hosts/ser8/household/        │
                       │    postgres + impermanence      │
                       │    Caddy vhost + AdGuard rewrite│
                       └──────────┬──────────────────────┘
                                  │ establishes: module split, persistence
                                  │ pattern, vhost/DNS pattern, smoketest area
                       ┌──────────▼──────────────────────┐
                       │ B. Backup engine + restore drill│
                       │    modules/household/backup.nix │
                       │    backup/household dataset     │
                       │    pg_dump path proven end-to-  │
                       │    end with a real restore      │
                       └──────────┬──────────────────────┘
                                  │ establishes: household.backup.jobs seam
                 ┌────────────────┼────────────────┐
                 │                │                │
     ┌───────────▼──────┐  ┌──────▼──────────┐  ┌──▼────────────────┐
     │ C. Actual Budget │  │ D. Homebox      │  │ E. Donetick       │
     │ nixpkgs module   │  │ nixpkgs module  │  │ NO nixpkgs module │
     │ SQLite, static   │  │ SQLite, static  │  │ packages/donetick │
     │ user override    │  │ user already    │  │ + custom module   │
     │ first SQLite job │  │ registration    │  │ + JWT secret      │
     │                  │  │ bootstrap dance │  │ + Google Tasks    │
     └──────────────────┘  └─────────────────┘  │   import script   │
                                                 └───────────────────┘
```

**Phase A - Household scaffold, PostgreSQL, Mealie.**
Mealie is the highest-priority service and also the one that exercises every hard integration point at once: a new database engine on the host, the DynamicUser-to-static-user override, impermanence for both `/var/lib/mealie` and `/var/lib/postgresql`, the first `<name>.vofi` vhost, the first AdGuard rewrite, and the new smoketest area.
Getting it right makes the other three near-mechanical.
Ship this and let the household use it before anything else lands, as the proposal directs.

Non-obvious work inside this phase:

- Pin `services.postgresql.package` explicitly (`pkgs.postgresql_16` or `_17`). Nixpkgs bumps the default major version across releases, and a silent bump against an existing data directory is a hard failure requiring `pg_upgrade`. This is the highest-consequence single line in the milestone.
- Set `settings.BASE_URL = "https://mealie.vofi"` and `settings.ALLOW_SIGNUP` explicitly. Mealie builds absolute links from `BASE_URL`; leaving the module default (`http://localhost:9000`) is a documented cause of login loops and broken redirects behind a reverse proxy.
- `services.mealie.database.createLocally = true` handles `ensureDatabases`, `ensureUsers`, and the socket URL. Do not hand-roll a Postgres password.

**Phase B - Backup engine and restore drill.**
Do this second, not last.
It is the milestone's only irreversible requirement ("nightly backups with a demonstrated restore"), it is far easier to prove with one service than four, and it establishes the `household.backup.jobs.<name>` seam so each subsequent service adds one line rather than a new backup mechanism.
The restore drill against Mealie's PostgreSQL dump is the strongest proof available and belongs here.

**Phases C and D - Actual Budget, then Homebox.**
Both have upstream nixpkgs modules at the pinned rev, both are SQLite, and both are the first consumers of the SQLite branch of the backup engine.
Actual first because it is the smaller change: enable, set `settings.port`, force a static user, register the job.
Homebox second because it has one extra wrinkle: `HBOX_OPTIONS_ALLOW_REGISTRATION` defaults to `"false"` in the nixpkgs module, so account creation requires a deliberate flip to `"true"`, create the accounts, flip back, which is a two-deploy dance that should be planned rather than discovered.
These two are genuinely order-independent; merging them into one phase is defensible.

**Phase E - Donetick.**
Last, and the only phase with real unknowns.

Verified: **Donetick is not in nixpkgs.** No package and no module at the pinned `nixos-25.11` rev `e4bae1bd10c9c57b2cf517953ab70060a828ee6f`, at the `nixpkgs-unstable` rev in `flake.lock`, or on `nixpkgs` master.
Two options, and the repo strongly favours the first:

1. **Package it locally.** The repo already does this end to end: `packages/subgen/default.nix` builds the app, `modules/subgen/default.nix` defines `options.services.subgen` with `package`, `listenAddress`, `port`, and `extraEnvironment`, and `hosts/firebat/subgen.nix` enables it with host-specific values. That is exactly the shape Donetick needs. Donetick is a Go binary plus a prebuilt frontend bundle, so either `buildGoModule` with the frontend asset from the upstream release, or a `stdenv.mkDerivation` over the release tarball with `autoPatchelfHook` (the SQLite driver uses cgo, so the binary is dynamically linked against glibc).
2. **OCI container.** This would be the first container on ser8. Nothing in the repo enables `virtualisation.docker`, `virtualisation.podman`, or `virtualisation.oci-containers`; the only traces are a persisted `/var/lib/docker` directory in `hosts/ser8/impermanence.nix:61-64` and `bdhill` being in the `docker` group in `users/bdhill.nix:111`, both leftovers. Introducing a container runtime for one service adds a runtime, a new persistence path, image-pinning discipline, and a second way services are defined.

Recommend option 1.
The packaging work is independent of everything else and can be validated with `nix build .#donetick` without touching ser8, so it can be split into its own early plan and run in parallel with Phases A-D if the roadmapper wants parallelism.

Donetick configuration facts to verify at plan time (MEDIUM confidence, from upstream docs rather than a nixpkgs module):

- Config is a YAML file selected by `DT_ENV` (`selfhosted` -> `config/selfhosted.yaml`), read through viper, with `DT_`-prefixed environment variables overriding YAML keys.
- `DT_SQLITE_PATH` sets the database path; point it at `/var/lib/donetick/donetick.db`.
- Default port is `2021`; the health endpoint is `/api/v1/health`, which is a better Caddy and blackbox target than `/`.
- `serve_frontend` defaults to `false` in the upstream sample config, which produces a working API and a 404 in the browser. Set it to `true`.
- `DT_JWT_SECRET` must come from SOPS; the shipped default is a placeholder.

**The Google Tasks import** rides with Phase E as a separate plan.
Design it as a one-shot script, not a service: the milestone's firm design constraint is "no integration layer or sync between the four services", and a persistent importer would violate the spirit of that.
Precedent for one-off operational scripts: `scripts/lutron/setup.sh` and the Python helpers under `scripts/sops/`.
Put it at `scripts/household/import-google-tasks.py`, take a Google Takeout `Tasks.json` as input, authenticate to the Donetick API with a token created in-app, support `--dry-run`, and skip chores whose name already exists so a partial run can be resumed.
Plan for the fact that Google Takeout's task export does not reliably carry recurrence information; recurring chores will need an explicit mapping table from task title to Donetick frequency, supplied by the user.

---

## Integration Points

### Files that change

| File | New or modified | What changes |
|------|-----------------|--------------|
| `flake.nix` | modified | Add `./modules/household` to `nixosConfigurations.ser8.modules` (near line 236) |
| `hosts/ser8/configuration.nix` | modified | Add `./household` to `imports` (near line 14) |
| `hosts/ser8/impermanence.nix` | modified | 4 entries in `environment.persistence` directories; 5 new tmpfiles rules; uncomment the postgres rule at line 112 |
| `hosts/ser8/disko-config.nix` | modified | Add the `backup/household` dataset (record-of-truth; must also be created by hand on the live pool) |
| `modules/gateway/Caddyfile` | modified | 4 new `<name>.vofi` vhosts (tab-indented) |
| `modules/dns/adguard-home.nix` | modified | 4 new `filtering.rewrites` entries pointing at `192.168.68.63` |
| `modules/gateway/prometheus.nix` | modified | 4 new `blackbox-http` targets using direct IPs (optional) |
| `modules/servers/backup.nix` | modified or deleted | Dead scaffolding; remove the unused `/etc/backup/backup-script.sh` when the real backup module lands |
| `deploy.yaml` | modified | Point `ser8.smoketests` at a host-level aggregator |
| `secrets/ser8.yaml` | modified | Add `donetick_jwt_secret` via `make sops-edit-ser8` |
| `modules/household/*` | **new** | 6 files: `default.nix`, four service modules, `backup.nix` |
| `hosts/ser8/household/*` | **new** | 7 files: `default.nix`, `postgresql.nix`, four service modules, `backup.nix` |
| `packages/donetick/default.nix` | **new** | Local package, mirrors `packages/subgen/` |
| `scripts/smoketests/household/*` | **new** | `all.sh` plus three `test-*.sh` |
| `scripts/smoketests/ser8/all.sh` | **new** | Host aggregator invoking `media/all.sh` and `household/all.sh` |
| `scripts/backup/restore-household.sh` | **new** | On-demand restore drill |
| `scripts/household/import-google-tasks.py` | **new** | One-shot Google Tasks to Donetick import |

### Port allocation on ser8

| Service | Port | Collision check |
|---------|------|-----------------|
| Mealie | 9000 | Free on ser8. `modules/subgen` defaults to 9000 but is imported with `enable = false` on ser8 and only enabled on firebat (`hosts/firebat/subgen.nix`). |
| Donetick | 2021 | Free. |
| Homebox | 7745 | Free. |
| Actual | 5006 | Free. Set explicitly: the nixpkgs module defaults to `settings.port = 3000`, a widely used port worth avoiding on principle. |
| PostgreSQL | 5432 | Unix socket only. Do **not** open the firewall. |

Firewall declarations belong in the reusable modules, guarded exactly like `modules/media/sonarr.nix:27`:

```nix
networking.firewall.allowedTCPPorts = lib.mkIf config.services.mealie.enable [ 9000 ];
```

### Network exposure

The proposal says "bind every service to localhost or the Tailscale interface only."
**That is not achievable here** and the roadmap should say so explicitly: Caddy runs on firebat (192.168.68.63), a different physical host from the services (192.168.68.65), so the services must listen on the LAN interface for the reverse proxy to reach them.
The milestone requirement is the weaker and satisfiable "No service reachable from outside Tailscale/LAN", which plain `allowedTCPPorts` already satisfies and which matches how every existing media service on ser8 is exposed.

If tighter exposure is wanted, there is a repo precedent for restricting a port to a single peer: `hosts/firebat/subgen.nix:19-32` uses `networking.firewall.extraCommands` with an explicit iptables rule accepting only `192.168.68.65 -> 192.168.68.63:9000`.
The same shape, inverted, would restrict the household ports to firebat only.
This stays compatible with monitoring, because Prometheus and the blackbox exporter also run on firebat.
Treat it as optional hardening, not a requirement.

---

## Anti-Patterns

### Anti-Pattern 1: Relying on `/var/lib/private` for DynamicUser services

**What people do:** leave `services.mealie` and `services.actual` on their default `DynamicUser = true`, notice that `/var/lib/private` is already in `environment.persistence`, and conclude persistence is handled.
**Why it's wrong:** it technically survives reboot, but you cannot express ownership in a tmpfiles rule (the UID is transient), the state path stops matching the `/persist/var/lib/<svc>` convention every other service and smoketest uses, and sops-nix secrets under `/run/secrets` become unreadable to the unit, a documented nixpkgs failure mode for Mealie specifically.
**Do this instead:** declare `users.users.<svc>` and `users.groups.<svc>` in the reusable module and set `DynamicUser = lib.mkForce false` in `serviceConfig`, exactly as `modules/automation/frigate.nix:485-489` already does for go2rtc.

### Anti-Pattern 2: Writing household dumps into `backup/backups`

**What people do:** reuse the existing `/mnt/backups` mount because it already exists and already has a tmpfiles rule.
**Why it's wrong:** `backup/backups` is declared with `dedup = "on"` in `hosts/ser8/disko-config.nix` and inherits the pool's `recordsize = "1M"`. Dedup costs GBs of ARC per TB and cannot be undone for blocks already written; 1M records are tuned for video, not for many small compressible dumps. ARC on this host is already capped at 8 GB.
**Do this instead:** a dedicated `backup/household` dataset with `dedup = "off"`, `compression = "zstd"`, `recordsize = "128K"`, and `com.sun:auto-snapshot = "true"`.

### Anti-Pattern 3: Assuming a disko dataset appears on a running pool

**What people do:** add the dataset to `hosts/ser8/disko-config.nix`, run `make switch-ser8`, and assume `/mnt/backups/household` now exists.
**Why it's wrong:** disko runs only at install time. On a live system `boot.zfs.extraPools` imports the pool as-is. The backup unit then happily writes into a plain directory on the root filesystem, which is rolled back to `@blank` on the next boot, so the backups silently vanish.
**Do this instead:** create the dataset once by hand as an explicit deployment step, record it in `disko-config.nix` for rebuild-from-scratch parity, and make the failure loud via `unitConfig.RequiresMountsFor` plus a `zfs list` assertion in `test-backups.sh`.

### Anti-Pattern 4: Letting `services.postgresql.package` float

**What people do:** enable `services.postgresql` without pinning the package and inherit whatever major version the channel defaults to.
**Why it's wrong:** a nixpkgs bump changes the default major version, the new server refuses to open the old data directory, and Mealie is down until someone runs `pg_upgrade` by hand. On an impermanent host with the data directory behind a bind mount, that is a bad afternoon.
**Do this instead:** `services.postgresql.package = pkgs.postgresql_17;` with a comment explaining that changing it requires a deliberate `pg_upgrade`, and treat a version change as its own planned phase.

### Anti-Pattern 5: Copying a live SQLite file

**What people do:** `cp /var/lib/homebox/data/homebox.db /mnt/backups/...` in the nightly job.
**Why it's wrong:** the SQLite services run in WAL mode; Homebox sets `_pragma=journal_mode=WAL` explicitly in its connection string in the nixpkgs module defaults. A raw copy captures the main database without the WAL and can be torn.
**Do this instead:** `sqlite3 <src> ".backup '<dst>'"` or `VACUUM INTO`, both of which take a read lock and produce a consistent single file.

### Anti-Pattern 6: Building an integration layer

**What people do:** notice that Mealie's shopping list and Donetick's chores "obviously" should sync, and write a small glue script.
**Why it's wrong:** this is explicitly forbidden in `.planning/PROJECT.md` under Out of Scope and in `proposal.md` under Design constraints, both of which state the four services are standalone by design and that the decision was made after evaluation.
**Do this instead:** nothing. The Google Tasks import is a one-shot migration, not a sync, and must not become a systemd unit.

---

## Scaling Considerations

This is a household homelab with a handful of users, so "scale" here means resource contention on a host that already runs Frigate NVR, Home Assistant, Jellyfin transcoding, and a full *arr stack.

| Concern | Reality | Action |
|---------|---------|--------|
| Memory | `boot.kernelParams` caps ZFS ARC at 8 GB (`zfs.zfs_arc_max=8589934592`). PostgreSQL adds a few hundred MB; the three SQLite services are tens of MB each. | No action. Do not add dedup to the backup dataset, which would eat the same budget. |
| CPU contention with Frigate | Frigate detection and Jellyfin transcoding are the heavy tenants. Household services are idle most of the time. | If a nightly `pg_dump` ever collides with a Frigate spike, use `RandomizedDelaySec` on the timer and `Nice`/`CPUWeight` on the unit. `hosts/firebat/subgen.nix:16-20` is the repo's precedent (`CPUWeight = 25; MemoryMax = "8G"; Nice = 10;`). |
| Backup pool capacity | Roughly 11 TB available, minus a temporary ~7.8 TB staging need during the pending media-pool migration. | Household dumps are megabytes. Non-issue, but do not schedule the migration and the first backup run in the same window. |
| Mealie recipe search | Choosing PostgreSQL over the SQLite default exists specifically for fuzzy ingredient search. | If it proves inadequate, `proposal.md` names Tandoor Recipes as the fallback and warns to evaluate before the catalog grows large enough to make migration painful. Revisit only if the household complains. |

---

## Confidence and Gaps

| Claim | Confidence | Basis |
|-------|------------|-------|
| Module layout, impermanence pattern, tmpfiles convention, SOPS patterns, Caddy and AdGuard declarativeness, smoketest wiring | HIGH | Read directly from the repo at HEAD; every claim cites a file and line |
| `services.mealie` / `services.homebox` / `services.actual` option surfaces and systemd behaviour | HIGH | Read from nixpkgs at the exact pinned rev `e4bae1bd10c9c57b2cf517953ab70060a828ee6f` recorded in `flake.lock` |
| `mutableSettings = true` merge semantics for AdGuard | HIGH | Read from `nixos/modules/services/networking/adguardhome.nix` at the pinned rev |
| Donetick absent from nixpkgs | HIGH | Verified 404 for both the module and `pkgs/by-name/do/donetick` at the pinned rev, the locked unstable rev, and master |
| Donetick runtime configuration (`DT_ENV`, `DT_SQLITE_PATH`, port 2021, `serve_frontend`, `DT_JWT_SECRET`) | MEDIUM | Upstream docs and repo config via web search; no nixpkgs module exists to cross-check. Verify against `donetick/config/selfhosted.yaml` at the chosen upstream tag during phase planning. |
| Mealie `BASE_URL` requirement behind a reverse proxy | MEDIUM | Upstream docs plus multiple issue reports via web search; not verifiable from nixpkgs source alone |
| Homebox `HBOX_WEB_PORT` default of 7745 | MEDIUM | Upstream convention; the nixpkgs module's freeform `settings` does not declare it and homebox.software returned HTTP 403 to a direct fetch. Confirm before writing the Caddy vhost. |

**Gaps to resolve at phase-planning time, not now:**

- Exact Donetick upstream release artifact layout (binary, frontend dist, config), which determines whether `buildGoModule` or a release-tarball derivation is the right packaging strategy.
- Whether `nixpkgs` should be advanced before this milestone. The pin `e4bae1bd` dates to mid-January 2026; Mealie, Homebox, and Actual all move quickly. Not a blocker, but a deliberate decision.
- Whether the household services also get `.shad-bangus.ts.net` Tailscale vhosts, which affects the Caddyfile, the tsnet node count, and the `blackbox-tls` target list.
- Whether the pending `SER8-ZFS-MIRROR-MIGRATION` runs before or after this milestone. It does not touch the `backup` pool, so either order works, but they should not overlap.

---

## Sources

- Repository at HEAD (`b4664da`): `flake.nix`, `flake.lock`, `deploy.yaml`, `Makefile`, `hosts/ser8/{configuration,impermanence,disko-config}.nix`, `hosts/ser8/media/{default,sonarr,permissions,sops}.nix`, `hosts/firebat/subgen.nix`, `modules/media/{default,sonarr,jellyfin}.nix`, `modules/subgen/default.nix`, `modules/automation/frigate.nix`, `modules/servers/{default,backup}.nix`, `modules/gateway/{Caddyfile,caddy.nix,prometheus.nix,blackbox.nix}`, `modules/dns/{adguard-home,adguard-exporter}.nix`, `scripts/smoketests/**`, `.planning/{PROJECT,STATE,SER8-ZFS-MIRROR-MIGRATION}.md`, `proposal.md` - HIGH
- nixpkgs at pinned rev `e4bae1bd10c9c57b2cf517953ab70060a828ee6f`: `nixos/modules/services/web-apps/{mealie,homebox,actual}.nix`, `nixos/modules/services/networking/adguardhome.nix` - HIGH
- nixpkgs unstable rev `d233902339c02a9c334e7e593de68855ad26c4cb` and `master`: verified absence of Donetick - HIGH
- [Donetick configuration docs](https://docs.donetick.com/getting-started/configration/) - MEDIUM
- [Donetick self-hosting guide](https://docs.donetick.com/getting-started/) - MEDIUM
- [Donetick upstream selfhosted.yaml](https://github.com/donetick/donetick/blob/main/config/selfhosted.yaml) - MEDIUM
- [Mealie backend configuration docs](https://docs.mealie.io/documentation/getting-started/installation/backend-config/) - MEDIUM
- [nixpkgs issue 321623: Mealie DynamicUser vs sops-nix /run/secrets](https://github.com/NixOS/nixpkgs/issues/321623) - MEDIUM
- [Homebox configuration docs](https://homebox.software/en/configure/) - LOW (returned HTTP 403; port default not independently confirmed)

---
*Architecture research for: v1.2 Household Stack integration into the nixos-config homelab flake*
*Researched: 2026-08-16*
