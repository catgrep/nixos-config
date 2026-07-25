# Phase 8 Multi-Source Coverage Audit

SOURCE | ID | Feature or requirement | Plan | Status | Notes
--- | --- | --- | --- | --- | ---
GOAL | - | Decompose `hosts/ser8/media.nix` into discoverable per-service modules without running-system changes | 01-07 | COVERED | Baseline-first extraction, final structure gate, no activation
REQ | N/A | Maintainability phase has no mapped v1.1 requirement ID | - | EXCLUDED | Confirmed by ROADMAP and REQUIREMENTS
RESEARCH | R-01 | Capture a non-secret evaluated behavior projection before edits | 01 | COVERED | Includes services, SOPS metadata/templates, users, exporters, nginx, units, scripts, accounts, and firewall
RESEARCH | R-02 | Use explicit `lib.mkOrder` values 100 through 800 for distributed script composition | 02-05 | COVERED | Every service and orchestration fragment has a fixed order
RESEARCH | R-03 | Preserve unit ordering separately from activation dependencies | 02-05 | COVERED | `before`, `after`, `requires`, `wants`, and `wantedBy` compared independently
RESEARCH | R-04 | Make Jellyfin exporter generic through enable and `apiKeyFile` options | 04 | COVERED | Host provides runtime SOPS path
RESEARCH | R-05 | Preserve qBittorrent VPN/nginx and atomic deployment behavior | 03 | COVERED | Full evaluated and generated-script comparison
RESEARCH | R-06 | Keep shared Usenet credentials owned by SABnzbd and referenced by NZBGet | 03 | COVERED | Deferred names remain unchanged
RESEARCH | R-07 | Split helpers with strict mode, ShellCheck, shfmt, and sanitized API logging | 05 | COVERED | Function inventory and safety gates included
RESEARCH | R-08 | Stage new Git-backed flake files before evaluation | 01-05 | COVERED | Explicit in extraction and cutover actions
RESEARCH | R-09 | Audit all reusable media modules and remove verified dead code | 06-07 | COVERED | Every current `modules/media/*.nix` file assigned
RESEARCH | R-10 | Treat Home Manager release mismatch as a zero-warning prerequisite | 01, 07 | COVERED | Fails closed without dependency changes or suppression
RESEARCH | R-11 | Do not edit encrypted SOPS data or activate ser8 | 01-07 | COVERED | Final gate is evaluation/build only
CONTEXT | D-01 | Service file owns complete host-specific slice | 02-04 | COVERED | Seven services extracted
CONTEXT | D-02 | Reusable exporter implementations remain generic | 04 | COVERED | Jellyfin option boundary and host-owned Arr instances
CONTEXT | D-03 | Arr files own Exportarr instances | 02 | COVERED | Sonarr, Radarr, Prowlarr
CONTEXT | D-04 | Host owns complete admin, Jordan, and Sawnia records | 04 | COVERED | Sawnia matches user-approved Jordan policy
CONTEXT | D-05 | Generic Jellyfin account/network/firewall/exporter stays reusable | 04, 07 | COVERED | Projected and audited
CONTEXT | D-06 | Shared media SOPS defaults in `sops.nix` | 05 | COVERED | Only shared defaults move
CONTEXT | D-07 | Individual secrets and templates stay service-owned | 02-05 | COVERED | Projection asserts ownership
CONTEXT | D-08 | `default.nix` is import-only | 05 | COVERED | Final structural gate
CONTEXT | D-09 | Preserve `media-config.service` with ordered service fragments | 02-05 | COVERED | Stable interface and generated-script comparison
CONTEXT | D-10 | Each service contributes its own `before` dependency | 02-03 | COVERED | All deploying services covered
CONTEXT | D-11 | Preserve deployment and startup order | 02-05 | COVERED | Explicit order table and unit-field comparison
CONTEXT | D-12 | Cross-service wiring stays in orchestration | 05 | COVERED | Both setup units and target
CONTEXT | D-13 | Split systemd helpers by responsibility | 05 | COVERED | Two strict-mode files
CONTEXT | D-14 | Helper split supersedes exact store-path equality | 01, 05 | COVERED | Store paths normalized narrowly
CONTEXT | D-15 | Compare evaluated behavior before and after | 01-07 | COVERED | Per-task and final comparisons
CONTEXT | D-16 | Allow approved structural path differences | 01, 05 | COVERED | Explicit normalization only
CONTEXT | D-17 | `make check` and `make build-ser8` pass | 07 | COVERED | Final zero-warning gate
CONTEXT | D-18 | No live activation required | 07 | COVERED | Activation commands prohibited
CONTEXT | D-19 | Remove unused AllDebrid secret declarations | 05 | COVERED | Removed with legacy aggregate
CONTEXT | D-20 | Delete commented AllDebrid host block | 05 | COVERED | Removed with legacy aggregate
CONTEXT | D-21 | Delete AllDebrid module and commented import | 06 | COVERED | Exact deletion task
CONTEXT | D-22 | Audit every reusable media file and remove dead code | 06-07 | COVERED | Includes user-approved Transmission deletion

## Exclusions

Renaming `sabnzbd_usenet_*` and introducing `nzbget_admin_password` are deferred by CONTEXT.md and intentionally excluded.
Encrypted `secrets/ser8.yaml` data remains untouched even though its unused encrypted keys may remain.
Live activation is excluded by D-18.

## Result

All goal, research, and locked-context items are covered.
No source-audit item is missing.
