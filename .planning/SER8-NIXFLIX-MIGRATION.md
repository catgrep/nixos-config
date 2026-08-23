# Nixflix Adoption Proposal for ser8

## Document status

This document proposes a staged migration of the ser8 media automation stack to Nixflix.
It is a research and architecture proposal, not an implementation record.

The upstream analysis is pinned to Nixflix commit
[`e9c20f232d0e09e346578bf6f8a390c34952643e`][nixflix-commit], which was the current
revision inspected on 2026-08-13.
The proposal was written on 2026-08-23.

## Executive summary

Nixflix is a good fit for ser8 and should be adopted as the declarative orchestration layer for
Jellyfin, Sonarr, Radarr, Prowlarr, download clients, Recyclarr, Seerr, and Maintainerr.
It should not be adopted as a wholesale replacement for the complete media stack in one change.

The existing media filesystem already matches the most important Nixflix and TRaSH design
principle: download clients and media managers access one shared filesystem namespace under
`/mnt/media`.
No media files need to move solely to adopt Nixflix.

The safe migration is nevertheless moderately difficult because the live server has persisted
application state, fixed service identities, custom permission enforcement, an external Caddy
proxy, a NordVPN network namespace, and locally implemented orchestration.
Nixflix also reconciles several API resources authoritatively, which means an incomplete
declaration can remove existing root folders, download clients, indexers, applications, or
proxies from application configuration.

The recommended approach is to pin Nixflix, add a ser8-specific adapter module, preserve all
existing identities and state paths, replace the overlapping local orchestration in stages, and
only then onboard new services.

The estimated migration difficulty is **7 out of 10 for a safe production cutover** and **3 out
of 10 for filesystem compatibility**.

## Goals

The migration should accomplish the following outcomes:

- Replace custom API orchestration with maintained declarative modules.
- Preserve all existing media, application databases, history, users, and service access.
- Preserve the shared `media` group and inherited group-write permission model.
- Continue using firebat as the Caddy, TLS, DNS, Tailscale, and monitoring gateway.
- Continue supporting Bazarr and NZBGet even though Nixflix does not provide first-class modules
  for them.
- Introduce TRaSH-aligned quality management through Recyclarr.
- Add a user-facing request workflow through Seerr.
- Add conservative, observable retention automation through Maintainerr.
- Keep secrets outside the Nix store and continue using sops-nix.

## Non-goals

The initial migration should not do any of the following:

- Move or rename the media library.
- Change the MergerFS branch policy.
- Change service UIDs or GIDs.
- Migrate SQLite application databases to PostgreSQL.
- Replace the existing NordVPN network namespace.
- Replace the existing qBittorrent service implementation.
- Replace firebat Caddy with a proxy running on ser8.
- Replace Bazarr before subtitle behavior has been compared and verified.
- Enable automatic media deletion during the first Maintainerr deployment.

## Current ser8 architecture

ser8 currently runs Jellyfin, Sonarr, Radarr, Prowlarr, Bazarr, qBittorrent, SABnzbd, NZBGet,
FlareSolverr, and related exporters through individual NixOS modules imported by
[`hosts/ser8/media/default.nix`][local-media-default].

The media library and download directories are exposed through a MergerFS mount at `/mnt/media`.
The mount combines `/mnt/disk1` and `/mnt/disk2` and currently uses `category.create=mfs`,
`moveonenospc=true`, and `minfreespace=50G` in
[`hosts/ser8/configuration.nix`][local-filesystem].

The relevant layout is:

```text
/mnt/media/
├── books/
├── movies/
├── music/
├── tv/
└── downloads/
    ├── complete/
    ├── incomplete/
    └── usenet/
        ├── complete/
        │   ├── default/
        │   ├── movies/
        │   ├── prowlarr/
        │   └── tv/
        └── incomplete/
```

Application state is persisted through impermanence under `/var/lib` and `/persist/var/lib`.
The persisted service directories are declared in
[`hosts/ser8/impermanence.nix`][local-impermanence].

The repository already centralizes cross-service access around the `media` group.
Setgid media and download directories are declared through tmpfiles, and
[`hosts/ser8/media/permissions.nix`][local-permissions] verifies and repairs access before the
media services start.
NZBGet additionally runs a post-processing script that normalizes ownership and modes after a
download completes in [`hosts/ser8/media/nzbget.nix`][local-nzbget].

The current glue between Prowlarr, the arr services, and download clients is implemented through
custom systemd units and shell helpers in
[`hosts/ser8/media/orchestration.nix`][local-orchestration] and
[`hosts/ser8/media/orchestration-helpers.sh`][local-orchestration-helpers].
This functionality substantially overlaps with Nixflix.

firebat runs Caddy and proxies service traffic to ser8.
The LAN and Tailscale routes are defined in [`modules/gateway/Caddyfile`][local-caddy].
Prometheus blackbox checks cover the exposed media services in
[`modules/gateway/prometheus.nix`][local-prometheus].

## What Nixflix provides

Nixflix provides a NixOS module that configures the applications and the relationships between
them rather than only enabling individual services.
Its documented features include Sonarr, Radarr, Lidarr, Prowlarr, Jellyfin, Seerr, SABnzbd,
qBittorrent, Recyclarr, Maintainerr, FlareSolverr, WireGuard, PostgreSQL, and local reverse proxy
integration.[^nixflix-overview]

The important distinction is that Nixflix manages API-level configuration such as root folders,
download clients, Prowlarr applications, indexers, proxies, Jellyfin libraries, and selected
users.
That is the layer currently maintained by ser8-specific scripts.

Nixflix also includes VM and full-stack tests that exercise service integration.[^nixflix-tests]
This offers a stronger upstream validation surface than maintaining the complete orchestration
locally.

Nixflix does not currently provide first-class Bazarr or NZBGet service modules.
Its download-client abstraction does support extra clients, which allows an externally managed
NZBGet instance to remain part of the declarative Sonarr and Radarr configuration.[^downloadarr]

## Migration difficulty assessment

| Area | Difficulty | Reason |
|---|---:|---|
| Media filesystem | Low | Existing paths can remain unchanged. |
| Sonarr and Radarr state | Medium | Their live data directories differ from the Nixflix defaults. |
| Prowlarr and Jellyfin state | Low to medium | Their main paths are compatible, but ownership and API changes require care. |
| Service identities | High | Several Nixflix fixed IDs differ from the live server. |
| API reconciliation | High | Undeclared resources can be removed from application configuration. |
| Download clients | High | NZBGet and the custom qBittorrent service must be represented before reconciliation. |
| Jellyfin users and keys | Medium to high | Existing hashes and API keys do not map directly to Nixflix creation semantics. |
| Secrets | Low to medium | The sops-nix file interface is compatible, but new key separation is required. |
| Caddy and network access | Low | The existing external proxy can remain authoritative. |
| Bazarr | Medium | It remains a local extension and must retain the shared permission contract. |
| New services | Low to medium | Recyclarr and Seerr are straightforward after the base stack is stable. |

## Filesystem and data migration analysis

### Media layout compatibility

The existing directory structure can be retained with the conceptual Nixflix settings below:

```nix
nixflix = {
  mediaDir = "/mnt/media";
  downloadsDir = "/mnt/media/downloads";
  stateDir = "/var/lib";
};
```

The final implementation must validate these names against the pinned module revision before
activation.
The important contract is that Nixflix must use the existing roots rather than create a parallel
layout.

The shared mount topology also follows the TRaSH recommendation that the download and library
paths reside under one common filesystem view, which enables atomic moves and hardlinks when the
underlying filesystem permits them.[^trash-hardlinks]

MergerFS supports hardlinks only when both paths resolve to the same underlying filesystem.
It cannot create a hardlink across `/mnt/disk1` and `/mnt/disk2` even though both appear beneath
the same MergerFS mount.[^mergerfs-hardlinks]
Nixflix does not remove this limitation.

The prior live inspection did not find media or download files with a link count greater than
one.
That observation suggests the current installation is not consistently realizing hardlink space
savings, although it does not prove that hardlinks never occur.
A migration test should create a representative download through the MergerFS mount, import it,
and verify inode and link-count behavior at both the merged and backing-filesystem levels.

### Application state paths

No application database should be moved during the first phase.
Instead, Nixflix should be configured around the existing state.

The existing Sonarr and Radarr paths are created by
[`hosts/ser8/media/deployment-helpers.sh`][local-deployment-helpers]:

- Sonarr uses `/var/lib/sonarr/.config/NzbDrone`.
- Radarr uses `/var/lib/radarr/.config/Radarr`.
- Prowlarr uses `/var/lib/prowlarr`.
- SABnzbd uses `/var/lib/sabnzbd`.
- NZBGet uses `/var/lib/nzbget`.
- qBittorrent uses `/var/lib/qbittorrent`.
- Jellyfin uses `/var/lib/jellyfin`.

Nixflix defaults arr state beneath `${stateDir}/${service}` through its common arr service
module.[^arr-service]
The Sonarr and Radarr data directories therefore need explicit overrides or the services will
start against fresh paths.

The qBittorrent path also needs explicit handling.
The current custom service uses `/var/lib/qbittorrent`, while the upstream NixOS qBittorrent
module used by Nixflix may use a differently cased profile directory.
The lowest-risk initial choice is to keep the current qBittorrent service and expose it to
Nixflix as an external download client.

### SQLite and PostgreSQL

The existing arr and Jellyfin installations use their current databases and must continue to do
so during the migration.
Enabling Nixflix PostgreSQL does not automatically import those databases.
It risks presenting applications with empty databases or requiring an unrelated database
migration at the same time as the orchestration cutover.

PostgreSQL should remain disabled until Nixflix is stable in production.
A future PostgreSQL proposal should measure the operational benefit against migration,
impermanence, backup, and upgrade complexity rather than assuming it is intrinsically better for
this workload.

### Service identity compatibility

Nixflix assigns fixed service UIDs and GIDs in its globals module.[^nixflix-identities]
The values observed on live ser8 during the prior inspection were:

| Identity | Live ser8 | Nixflix default | Initial action |
|---|---:|---:|---|
| `media` GID | 992 | 169 | Override Nixflix to 992. |
| Jellyfin UID | 993 | 146 | Override Nixflix to 993. |
| Prowlarr UID | 991 | 293 | Override Nixflix to 991. |
| qBittorrent UID | 992 | 70 | Preserve the custom service initially. |
| Sonarr UID | 274 | 274 | Preserve without changing ownership. |
| Radarr UID | 275 | 275 | Preserve without changing ownership. |
| SABnzbd UID | 38 | 38 | Preserve without changing ownership. |

Changing these IDs without a controlled ownership migration can make application databases,
configuration, caches, and media unreadable.
The first implementation must force Nixflix to the existing live IDs rather than recursively
changing persisted ownership.

The repository and the live server also showed identity drift for the `media` group during the
prior inspection.
The live system is authoritative for the initial migration because it owns the persisted files.
The repository declarations should be reconciled to the live identity before Nixflix is allowed
to manage users and groups.

### Shared permissions

The shared `media` group is the correct permission model and should remain the only cross-service
filesystem access mechanism.
Individual service groups can remain as private primary groups where required, but they should
not be the basis for sharing media.

Nixflix creates common directories with group-write permissions, but its directory setup must be
reviewed for setgid preservation.
ser8 relies on mode `2775` so new children inherit the `media` group.

The integration should enforce these ordering rules:

1. The `/mnt/media` MergerFS mount must be available.
2. Nixflix directory creation must complete.
3. `media-permissions.service` must verify ownership, setgid directories, and group-readable
   files.
4. Media applications may start only after the permission verification succeeds.

The existing permission smoketest already checks service access in
[`scripts/smoketests/media/all.sh`][local-media-smoketest].
It should be extended to cover any Nixflix-managed service that reads or writes media.

## Authoritative reconciliation risks

Nixflix treats several configuration lists as desired state rather than additive suggestions.
This is its main operational advantage and its largest migration hazard.

### Root folders

The arr root-folder reconciliation removes root folders that are not declared in Nixflix.[^root-folders]
The prior live inspection found the desired Radarr root `/mnt/media/movies` and several stale
download-directory roots.
Nixflix can clean those stale registrations without moving the files, but only after the desired
roots are completely declared and backed up.

### Download clients

The live arr applications currently include NZBGet, qBittorrent, SABnzbd, and a disabled
Transmission client.
An incomplete Nixflix download-client declaration could remove any of these from Sonarr and
Radarr.

Before the reconciliation service starts, the configuration must include:

- The existing qBittorrent endpoint and categories.
- The existing NZBGet endpoint, credentials, priorities, and categories.
- The existing SABnzbd endpoint, API key, priorities, and categories.
- An explicit decision to remove rather than preserve the disabled Transmission entry.

### Prowlarr

Prowlarr currently contains application links, a FlareSolverr proxy, download clients, and both
enabled and disabled indexers.
Nixflix can reconcile Prowlarr indexers from declarative configuration.[^prowlarr-indexers]
If the configured indexer list is empty or incomplete, existing indexers may be removed.

The initial migration must export the existing Prowlarr API objects and classify each one as:

- Managed and retained in Nixflix.
- Intentionally removed.
- Temporarily retained outside Nixflix until its credentials are available in SOPS.

The first activation must not use an empty authoritative indexer list against the production
database.

### Required pre-activation backup

Before enabling reconciliation, create a recoverable snapshot of the persistent application
state and export the current API resources.
At minimum, the snapshot must cover Jellyfin, Sonarr, Radarr, Prowlarr, Bazarr, qBittorrent,
SABnzbd, and NZBGet.

The rollback procedure must be tested before deployment.
It should restore both the NixOS generation and the matching application-state snapshot because
rolling back only the package configuration will not reverse API or database mutations.

## Secrets integration

Nixflix accepts file-backed secrets through its secret option helper.[^nixflix-secrets]
This fits the existing sops-nix architecture.

Secrets must continue to be referenced by runtime file paths rather than plain Nix strings.
Plain strings can be copied into the world-readable Nix store.
Systemd credentials and root-executed setup services should consume the SOPS material at runtime.

Most existing secrets can retain their current names and encrypted values:

- Sonarr API key and administrator password.
- Radarr API key and administrator password.
- Prowlarr API key and administrator password.
- SABnzbd API, NZB, provider, and administrator credentials.
- NZBGet control and provider credentials.
- qBittorrent plaintext password and password hash.
- Exporter API keys.

The Nixflix migration should add separate secrets for:

- A dedicated Nixflix Jellyfin API key.
- A Seerr API key.
- Any Lidarr or additional arr API keys.
- Credentials for Prowlarr indexers moved from its database into Nix.

### Jellyfin API key handling

The current configuration registers a Jellyfin API key named `jellyfinarr` and also uses it for
the exporter in [`hosts/ser8/media/jellyfin.nix`][local-jellyfin].
Nixflix injects its own Jellyfin API key by editing Jellyfin state while the service is
stopped.[^jellyfin-api-key]

The same token must not be reused under a second key name because the Jellyfin database enforces
token uniqueness.
The migration should create a dedicated `nixflix_jellyfin_api_key` secret and preserve the
existing exporter key until the exporter is deliberately migrated.

### Jellyfin user passwords

The current declarative Jellyfin module consumes hashed password files.
Nixflix user provisioning accepts a password when creating a user and does not continuously
replace existing passwords.[^jellyfin-users]

Existing users can remain in the current Jellyfin database without re-entering their passwords.
The existing password hashes must not be passed as if they were plaintext passwords.
If reproducible disaster-recovery creation of users is required, dedicated bootstrap password
secrets or a local Nixflix extension will be needed.

### Secret organization recommendation

The migration does not need to rename all existing SOPS keys.
A mass secret rename would increase deployment risk without improving the application contract.

New secrets should use a consistent media namespace where practical, for example:

```text
media/sonarr/api-key
media/radarr/api-key
media/prowlarr/api-key
media/jellyfin/nixflix-api-key
media/seerr/api-key
```

Existing names can be converted in a separate change after the migration is stable.

## Caddy, networking, and access

The existing firebat proxy topology should remain unchanged.
firebat already terminates TLS, provides LAN and Tailscale hostnames, and sends traffic to the
service ports on ser8.

Nixflix local nginx and Caddy integration should remain disabled.
Its virtual-host helper can change service binding behavior when a local proxy is enabled.[^nixflix-proxy]
Binding an application only to loopback on ser8 would prevent firebat from reaching it.

Each enabled service should instead retain or receive:

- A stable ser8 port.
- A ser8 firewall rule limited to the required network exposure.
- A firebat Caddy route.
- An AdGuard DNS record for LAN access.
- A Tailscale Caddy route when remote access is needed.
- A Prometheus blackbox target or exporter when operationally useful.
- A media smoketest endpoint.

Jellyfin should trust firebat as a known proxy so forwarded client addresses and headers are
handled correctly.
The known proxy should include firebat at `192.168.68.63` and should be kept narrow rather than
trusting all private networks.

### qBittorrent and NordVPN

The current qBittorrent service runs inside the NordVPN network namespace and is exposed locally
through nginx.
Nixflix WireGuard support is not a direct replacement for that topology.

The initial implementation should keep:

- `qbittorrent-nox.service`.
- The `wgnord` network namespace.
- The existing local nginx bridge.
- The current `/var/lib/qbittorrent` profile.
- The existing Caddy routes to port 8080.

Nixflix should configure the existing endpoint as a download client without assuming ownership
of the underlying qBittorrent service.
A separate proposal can evaluate moving VPN ownership after the orchestration migration has been
verified.

## New service value

### Recyclarr

Recyclarr offers the highest immediate configuration-quality improvement.
Nixflix provides a declarative Recyclarr integration designed around TRaSH profiles and custom
formats.[^recyclarr]

The current arr configuration has generic quality profiles and limited custom-format scoring.
Recyclarr can improve:

- WEB and Blu-ray release selection.
- Codec, audio, release-group, and streaming-source scoring.
- Consistency between Sonarr and Radarr.
- Anime-specific profiles and release scoring.
- Repeatability after rebuilding application state.

The first rollout must keep cleanup of unmanaged profiles disabled.
Existing profiles may still be assigned to series or movies and should not be deleted until the
new scoring behavior has been observed.

### Seerr

Seerr provides a user-facing request and discovery interface connected to Jellyfin, Sonarr, and
Radarr.[^seerr]
It avoids granting household users access to the administrative arr interfaces.

Expected improvements include:

- Jellyfin-based authentication.
- Movie and series requests.
- Request approval and status tracking.
- Automatic dispatch to the appropriate arr service.
- Jellyfin library awareness.
- A clearer boundary between user requests and administrative automation.

Seerr should be added after the core Sonarr, Radarr, Prowlarr, and Jellyfin integrations are
stable.

### Maintainerr

Maintainerr can manage retention, cleanup, and collections using Jellyfin, Seerr, and arr
metadata.[^maintainerr]
It can reclaim storage and make content lifecycle policy explicit.

Potential policies include:

- Removing watched content after a retention period.
- Expiring abandoned requests.
- Keeping recently requested or favorited content.
- Creating cleanup collections for review.
- Exempting selected libraries, users, genres, or tags.

Maintainerr can delete media and therefore requires a conservative rollout.
The initial rules must use preview or no-action behavior.
Rules should be built and verified through the UI, exported, reviewed, and then added to Nix.
Nixflix provides examples for declarative Maintainerr rules.[^maintainerr-rules]

### Separate Sonarr anime instance

A separate Sonarr instance for anime can improve Bleach and similar series through specialized
naming, profiles, custom formats, and release-group scoring.
It should not be introduced during the initial Sonarr migration.

Moving a series between Sonarr instances requires an explicit plan for monitoring, history,
quality profiles, root folders, and ownership.
Both instances must never monitor and import the same series concurrently.
The media may remain in `/mnt/media/tv`, although a dedicated `/mnt/media/anime` root could be
evaluated separately.

### Lidarr

Lidarr can automate the existing `/mnt/media/music` library.
It provides value when automated acquisition, metadata, and quality management are desired.
It has lower immediate value than Recyclarr and Seerr and should be added after the core migration.

### Bazarr and Jellyfin subtitles

Nixflix does not currently replace Bazarr.
The existing Bazarr module, state directory, shared `media` group, exporter behavior, and
permission checks should remain in place.

Nixflix can manage Jellyfin plugins, including subtitle-related plugins, but enabling overlapping
subtitle automation can create duplicates or conflicting language policies.
Bazarr should only be replaced after comparing provider coverage, subtitle placement, hearing-
impaired preferences, forced-subtitle behavior, and existing history.

## Proposed target architecture

```text
Users
  |
  v
firebat: Caddy, TLS, LAN DNS, Tailscale, Prometheus
  |
  v
ser8: stable service ports
  |
  +-- Nixflix orchestration
  |     +-- Sonarr
  |     +-- Radarr
  |     +-- Prowlarr
  |     +-- Jellyfin
  |     +-- Recyclarr
  |     +-- Seerr
  |     +-- Maintainerr
  |     +-- SABnzbd integration
  |     +-- external NZBGet integration
  |     `-- external qBittorrent integration
  |
  +-- ser8 extensions
  |     +-- Bazarr
  |     +-- NZBGet service and permission post-processing
  |     +-- qBittorrent NordVPN namespace
  |     +-- exporters
  |     `-- media permission verification
  |
  `-- /mnt/media MergerFS namespace
        +-- libraries
        `-- downloads
```

This boundary uses Nixflix for the glue it is designed to own while retaining local modules for
host-specific capabilities that it does not model.
Extensions should be implemented in a ser8 adapter module rather than by forking Nixflix unless
an upstream option cannot express a required behavior.

## Staged migration plan

### Phase 0: Pin and inventory

1. Add Nixflix as a flake input pinned to an exact reviewed revision.
2. Import the module without enabling production reconciliation.
3. Record the live UID, GID, state-directory, port, and systemd-unit inventory.
4. Export Sonarr, Radarr, Prowlarr, Jellyfin, SABnzbd, NZBGet, and qBittorrent configuration.
5. Snapshot the persistent application state.
6. Document and test a state-aware rollback procedure.

### Phase 1: Compatibility adapter

1. Add `hosts/ser8/media/nixflix.nix`.
2. Override Nixflix identities to match the live server.
3. Set the existing media, downloads, and state roots.
4. Set the existing Sonarr and Radarr data directories.
5. Keep Nixflix PostgreSQL, proxy, VPN, and qBittorrent service management disabled.
6. Connect Nixflix directory setup to `media-permissions.service` ordering.
7. Evaluate and build ser8 without activating it.

### Phase 2: arr and Prowlarr orchestration

1. Declare every desired root folder.
2. Declare qBittorrent, NZBGet, and SABnzbd before enabling download-client reconciliation.
3. Declare every retained Prowlarr application, proxy, download client, and indexer.
4. Enable Nixflix orchestration for Sonarr, Radarr, and Prowlarr.
5. Remove the overlapping `media-config`, `servarrs-setup`, and `download-clients-setup` units.
6. Run focused API, permission, import, and proxy smoketests.

### Phase 3: Jellyfin

1. Create a dedicated Nixflix Jellyfin API key in SOPS.
2. Preserve the existing Jellyfin database and paths.
3. Declare the existing Shows, Movies, and Books libraries as required.
4. Preserve existing users without treating password hashes as plaintext.
5. Confirm exporter access and firebat known-proxy handling.
6. Remove overlapping declarative Jellyfin ownership only after parity is demonstrated.

### Phase 4: Recyclarr and Seerr

1. Enable Recyclarr without deleting unmanaged profiles.
2. Review scoring and upgrade decisions against representative existing media.
3. Enable Seerr and connect it to Jellyfin, Sonarr, and Radarr.
4. Add firebat Caddy, DNS, Tailscale, monitoring, and smoketest coverage for Seerr.

### Phase 5: Maintainerr

1. Enable Maintainerr without destructive rules.
2. Build rules in the UI and run them in preview or no-action mode.
3. Export the rules to declarative configuration.
4. Add narrow deletion rules only after reviewing multiple evaluation cycles.
5. Add alerts and audit visibility for every deletion action.

### Phase 6: Optional expansion

Evaluate a separate Sonarr anime instance, Lidarr, PostgreSQL, or Nixflix-managed VPN only as
independent changes with their own migration and rollback plans.

## Validation requirements

Every migration phase should pass focused evaluation and a ser8 build before activation.
The following behaviors require direct verification:

- Existing Sonarr, Radarr, Prowlarr, and Jellyfin databases open without migration errors.
- Existing history, monitored items, users, and libraries remain present.
- Nixflix does not remove an intentionally retained download client, root folder, indexer, proxy,
  or application.
- Sonarr and Radarr can import from NZBGet, SABnzbd, and qBittorrent.
- Imports preserve group-readable files and setgid directories.
- Bazarr can read every imported television and movie file.
- Jellyfin can scan and play newly imported files.
- A representative torrent import either creates a verified hardlink or reports why the backing
  branch prevents it.
- firebat Caddy reaches every migrated service over LAN and Tailscale routes.
- Exporters and blackbox probes remain healthy.
- Recyclarr changes only the expected profiles and custom formats.
- Maintainerr performs no deletion during its observation phase.
- Rollback restores both the NixOS generation and the matching application state.

The existing media smoketest is the correct place for permission and service-access assertions.
New tests should verify behavior rather than only checking that systemd units are active.

## Risks and mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| Nixflix identity mismatch | Persisted files become unreadable. | Force the existing live IDs before activation. |
| Wrong data directory | An application starts with an empty database. | Explicitly preserve all current state paths and assert database presence. |
| Incomplete desired-state list | Existing API objects are removed. | Export first, declare the complete inventory, and snapshot application state. |
| Competing orchestration units | Services repeatedly overwrite each other. | Remove each local unit when Nixflix takes over its responsibility. |
| Loss of setgid inheritance | Random cross-service permission failures return. | Keep the shared `media` group, mode `2775`, startup ordering, and smoketests. |
| qBittorrent loses VPN isolation | Torrent traffic bypasses NordVPN. | Keep the current service and namespace during initial adoption. |
| Jellyfin API token collision | Nixflix setup fails or overwrites integration assumptions. | Create a separate Nixflix API key. |
| Jellyfin password misuse | Existing users cannot authenticate. | Preserve the database and never pass hashes as plaintext. |
| Local proxy binding | firebat cannot reach services. | Keep Nixflix proxies disabled and retain stable LAN listeners. |
| Maintainerr deletes wanted media | Irrecoverable content loss. | Begin with preview behavior, review exported rules, and monitor actions. |
| Upstream breaking change | A flake update mutates state or options. | Pin exact commits and review the changelog and diff before updating. |

## Decision

Adopt Nixflix as the declarative service-integration layer for ser8 through a staged migration.

The adoption is justified because it replaces a large local orchestration surface with an
upstream module focused specifically on media-service glue, adds tested integrations, and makes
TRaSH-aligned configuration and request workflows easier to maintain.

The adoption is conditional on preserving the current filesystem, identities, application state,
permission policy, NordVPN topology, and firebat proxy architecture.
Nixflix defaults must not be accepted where they conflict with live persisted state.

The first implementation milestone should stop after the pinned input, compatibility adapter,
state-aware backup procedure, and non-activated build validation are complete.
Production reconciliation should be a separate reviewed deployment.

## References

### Nixflix upstream

[^nixflix-overview]: [Nixflix README and feature overview][nixflix-readme].

[^nixflix-tests]: [Nixflix full-stack VM test][nixflix-full-stack-test].

[^downloadarr]: [Nixflix Downloadarr service][nixflix-downloadarr-service] and
    [Downloadarr options][nixflix-downloadarr-options].

[^arr-service]: [Nixflix common arr service module][nixflix-arr-service].

[^nixflix-identities]: [Nixflix fixed UID and GID definitions][nixflix-globals].

[^root-folders]: [Nixflix arr root-folder reconciliation][nixflix-root-folders].

[^prowlarr-indexers]: [Nixflix Prowlarr indexer reconciliation][nixflix-indexers].

[^nixflix-secrets]: [Nixflix secret option implementation][nixflix-secrets].

[^jellyfin-api-key]: [Nixflix Jellyfin API-key setup service][nixflix-jellyfin-api-key].

[^jellyfin-users]: [Nixflix Jellyfin user options][nixflix-jellyfin-user-options] and
    [user reconciliation][nixflix-jellyfin-users].

[^nixflix-proxy]: [Nixflix virtual-host helper][nixflix-virtual-hosts].

[^recyclarr]: [Nixflix Recyclarr reference][nixflix-recyclarr].

[^seerr]: [Nixflix Seerr reference][nixflix-seerr].

[^maintainerr]: [Nixflix Maintainerr reference][nixflix-maintainerr].

[^maintainerr-rules]: [Nixflix Maintainerr rule examples][nixflix-maintainerr-rules].

[^trash-hardlinks]: [TRaSH hardlink and atomic-move guidance][trash-hardlinks].

[^mergerfs-hardlinks]: [MergerFS hardlink limitations][mergerfs-hardlinks].

Additional upstream review material:

- [Nixflix getting-started guide][nixflix-getting-started].
- [Nixflix basic setup example][nixflix-basic-setup].
- [Nixflix core option reference][nixflix-core-reference].
- [Nixflix changelog][nixflix-changelog].
- [TRaSH hardlink and atomic-move guidance][trash-hardlinks].
- [MergerFS hardlink limitations][mergerfs-hardlinks].

### Local repository evidence

- [ser8 media module imports][local-media-default].
- [ser8 MergerFS configuration][local-filesystem].
- [ser8 persisted service state][local-impermanence].
- [ser8 shared media permissions][local-permissions].
- [ser8 media orchestration][local-orchestration].
- [ser8 orchestration helpers][local-orchestration-helpers].
- [ser8 service configuration deployment helper][local-deployment-helpers].
- [ser8 Jellyfin configuration][local-jellyfin].
- [ser8 NZBGet configuration][local-nzbget].
- [firebat Caddy routes][local-caddy].
- [firebat Prometheus targets][local-prometheus].
- [media service and permission smoketests][local-media-smoketest].

[nixflix-commit]: https://github.com/kiriwalawren/nixflix/tree/e9c20f232d0e09e346578bf6f8a390c34952643e
[nixflix-readme]: https://github.com/kiriwalawren/nixflix/blob/e9c20f232d0e09e346578bf6f8a390c34952643e/README.md
[nixflix-getting-started]: https://kiriwalawren.github.io/nixflix/getting-started/
[nixflix-basic-setup]: https://kiriwalawren.github.io/nixflix/examples/basic-setup/
[nixflix-core-reference]: https://kiriwalawren.github.io/nixflix/reference/core/
[nixflix-changelog]: https://github.com/kiriwalawren/nixflix/blob/e9c20f232d0e09e346578bf6f8a390c34952643e/CHANGELOG.md
[nixflix-full-stack-test]: https://github.com/kiriwalawren/nixflix/blob/e9c20f232d0e09e346578bf6f8a390c34952643e/tests/vm-tests/full-stack.nix
[nixflix-downloadarr-service]: https://github.com/kiriwalawren/nixflix/blob/e9c20f232d0e09e346578bf6f8a390c34952643e/modules/downloadarr/service.nix
[nixflix-downloadarr-options]: https://github.com/kiriwalawren/nixflix/blob/e9c20f232d0e09e346578bf6f8a390c34952643e/modules/downloadarr/options.nix
[nixflix-arr-service]: https://github.com/kiriwalawren/nixflix/blob/e9c20f232d0e09e346578bf6f8a390c34952643e/modules/arr-common/mkArrServiceModule.nix
[nixflix-globals]: https://github.com/kiriwalawren/nixflix/blob/e9c20f232d0e09e346578bf6f8a390c34952643e/modules/globals.nix
[nixflix-root-folders]: https://github.com/kiriwalawren/nixflix/blob/e9c20f232d0e09e346578bf6f8a390c34952643e/modules/arr-common/rootFolders.nix
[nixflix-indexers]: https://github.com/kiriwalawren/nixflix/blob/e9c20f232d0e09e346578bf6f8a390c34952643e/modules/prowlarr/indexers.nix
[nixflix-secrets]: https://github.com/kiriwalawren/nixflix/blob/e9c20f232d0e09e346578bf6f8a390c34952643e/lib/secrets/default.nix
[nixflix-jellyfin-api-key]: https://github.com/kiriwalawren/nixflix/blob/e9c20f232d0e09e346578bf6f8a390c34952643e/modules/jellyfin/apiKeyService.nix
[nixflix-jellyfin-user-options]: https://github.com/kiriwalawren/nixflix/blob/e9c20f232d0e09e346578bf6f8a390c34952643e/modules/jellyfin/users/options.nix
[nixflix-jellyfin-users]: https://github.com/kiriwalawren/nixflix/blob/e9c20f232d0e09e346578bf6f8a390c34952643e/modules/jellyfin/users/default.nix
[nixflix-virtual-hosts]: https://github.com/kiriwalawren/nixflix/blob/e9c20f232d0e09e346578bf6f8a390c34952643e/lib/mkVirtualHosts.nix
[nixflix-recyclarr]: https://kiriwalawren.github.io/nixflix/reference/recyclarr/
[nixflix-seerr]: https://kiriwalawren.github.io/nixflix/reference/seerr/
[nixflix-maintainerr]: https://kiriwalawren.github.io/nixflix/reference/maintainerr/
[nixflix-maintainerr-rules]: https://kiriwalawren.github.io/nixflix/examples/maintainerr-rules/
[trash-hardlinks]: https://trash-guides.info/File-and-Folder-Structure/Hardlinks-and-Instant-Moves/
[mergerfs-hardlinks]: https://trapexit.github.io/mergerfs/latest/faq/technical_behavior_and_limitations/#do-hard-links-work
[local-media-default]: hosts/ser8/media/default.nix
[local-filesystem]: hosts/ser8/configuration.nix#L155
[local-impermanence]: hosts/ser8/impermanence.nix#L51
[local-permissions]: hosts/ser8/media/permissions.nix
[local-orchestration]: hosts/ser8/media/orchestration.nix
[local-orchestration-helpers]: hosts/ser8/media/orchestration-helpers.sh
[local-deployment-helpers]: hosts/ser8/media/deployment-helpers.sh
[local-jellyfin]: hosts/ser8/media/jellyfin.nix
[local-nzbget]: hosts/ser8/media/nzbget.nix
[local-caddy]: modules/gateway/Caddyfile
[local-prometheus]: modules/gateway/prometheus.nix#L200
[local-media-smoketest]: scripts/smoketests/media/all.sh
