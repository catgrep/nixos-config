# Phase 8: Reorganize ser8 media.nix into per-service modules - Context

**Gathered:** 2026-07-25
**Status:** Ready for planning

<domain>
## Phase Boundary

Decompose `hosts/ser8/media.nix` into focused host-level media modules under `hosts/ser8/media/`.
Each active service must become discoverable as a complete host-specific configuration slice,
while reusable modules remain generic and genuinely cross-service behavior stays isolated.
The refactor must preserve active runtime behavior, but exact system store-path equality is no
longer required because helper ownership will be split and dead AllDebrid configuration will be
removed.

</domain>

<decisions>
## Implementation Decisions

### Service boundaries

- **D-01:** Each host service file owns its service enablement, host settings, SOPS secrets, SOPS
  templates, deployment contribution, and host-specific monitoring exporter settings.
- **D-02:** Reusable exporter implementations remain generic under `modules/media/`.
- **D-03:** Each Arr service file owns and enables its corresponding Exportarr instance instead of
  retaining one host-level grouped Exportarr configuration.
- **D-04:** `hosts/ser8/media/jellyfin.nix` owns the complete `admin`, `jordan`, and `sawnia`
  household user records, password references, and host API-key wiring.
- **D-05:** Generic Jellyfin service account, network, firewall, and exporter implementation remain
  in reusable modules.
- **D-06:** Shared media SOPS defaults live in `hosts/ser8/media/sops.nix`.
- **D-07:** Each service file still owns its individual secret and template declarations.
- **D-08:** `hosts/ser8/media/default.nix` remains an import-only entry point for the SOPS support
  module, active service modules, and orchestration module.

### Deployment and orchestration

- **D-09:** Preserve the existing `media-config.service` interface, but assemble its deployment
  script from ordered fragments contributed by the owning service files.
- **D-10:** Each service file contributes its own `media-config.service.before` dependency.
- **D-11:** Import and merge ordering must reproduce the existing effective deployment order and
  startup relationships.
- **D-12:** `servarrs-setup.service`, `download-clients-setup.service`, `media-setup.target`, and
  other genuinely cross-service wiring remain in one orchestration module.
- **D-13:** Split `hosts/ser8/systemd_helpers.sh` into deployment-focused and
  orchestration-focused helper files.
- **D-14:** The helper split intentionally supersedes the ROADMAP criterion requiring the
  identical ser8 system store path.

### Behavior-parity validation

- **D-15:** Behavior parity is proven by comparing the before and after evaluated service settings,
  SOPS declarations and templates, unit dependencies, and generated scripts.
- **D-16:** Structural path differences caused by the approved module and helper split are allowed.
- **D-17:** `make check` and `make build-ser8` must pass after the evaluated comparison.
- **D-18:** No live activation is required for phase acceptance.

### Disabled configuration and cleanup

- **D-19:** Remove the unused `alldebrid_api_key` and `alldebrid_transmission_admin_password` SOPS
  declarations.
- **D-20:** Delete the commented-out AllDebrid service block from the old host configuration rather
  than moving or documenting it.
- **D-21:** Delete `modules/media/alldebrid-proxy.nix` and remove its commented import from
  `modules/media/default.nix`.
- **D-22:** Audit every file under `modules/media/` and remove commented-out or genuinely dead code
  while preserving all active service behavior.

### Agent's Discretion

- Exact Nix merge primitives and ordering values used to assemble `media-config.service`.
- Exact names for the deployment-focused and orchestration-focused shell helper files.
- The comparison command or script used to normalize intentional structural differences during
  parity validation.
- Mechanical formatting and comment wording that do not affect active behavior.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase scope

- `.planning/ROADMAP.md` - Phase 8 defines the decomposition target, active service list,
  reusable-module boundary, and cross-service orchestration boundary.

No external specifications or ADRs apply to this phase.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets

- `modules/media/`: Existing reusable modules already provide generic Jellyfin, Sonarr, Radarr,
  Prowlarr, qBittorrent, SABnzbd, NZBGet, Jellyfin exporter, and Exportarr behavior.
- `hosts/ser8/systemd_helpers.sh`: Existing shell functions cover configuration deployment, API
  readiness, Arr application registration, and download-client registration.
- SOPS templates in `hosts/ser8/media.nix`: Existing generated configurations can move intact into
  their owning service files before approved cleanup.

### Established Patterns

- Role directories use an import-only `default.nix` and focused lowercase Nix modules.
- Reusable `modules/media/` files own generic service accounts, packages, networking, and firewall
  behavior.
- Host configuration owns concrete secrets, credentials, household identity, and deployment wiring.
- Systemd oneshot units use explicit readiness checks, fail-fast shell behavior, and sanitized API
  handling.

### Integration Points

- `hosts/ser8/configuration.nix` currently imports `./media.nix` and must import the new `./media`
  directory.
- `modules/media/default.nix` currently imports grouped exporter modules and contains the commented
  AllDebrid import targeted for removal.
- `modules/media/jellyfin.nix` currently contains household users that must move to
  `hosts/ser8/media/jellyfin.nix`.
- `hosts/ser8/media.nix` currently defines all media SOPS declarations, templates, the aggregate
  deployment unit, cross-service setup units, and the orchestration target.

</code_context>

<specifics>
## Specific Ideas

- A service's host file should provide one-stop discovery of its host-specific configuration,
  including its exporter instance and deployment contribution.
- The final structure should retain one visible orchestration module for relationships that cannot
  truthfully belong to one service.
- Validation should distinguish intentional source-layout changes from changes to active service
  behavior.

</specifics>

<deferred>
## Deferred Ideas

- Renaming `sabnzbd_usenet_*` secrets to neutral `usenet_*` names remains out of scope.
- Giving NZBGet a separate `nzbget_admin_password` remains out of scope.

</deferred>

---

*Phase: 08-reorganize-ser8-media-nix-into-per-service-modules*
*Context gathered: 2026-07-25*
