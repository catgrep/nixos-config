# Phase 8: Reorganize ser8 media.nix into per-service modules - Discussion Log

> **Audit trail only.**
> Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md; this log preserves the alternatives considered.

**Date:** 2026-07-25
**Phase:** 08-reorganize-ser8-media-nix-into-per-service-modules
**Areas discussed:** Service boundaries, deployment units, disabled configuration

---

## Service Boundaries

### Exporter ownership

| Option | Description | Selected |
|--------|-------------|----------|
| Full service slice | Host files own exporter settings; implementation stays generic. | Yes |
| Separate exporter files | Keep Jellyfin Exporter and Exportarr as separate host concerns. | |
| Leave exporters untouched | Move only content explicitly required by the roadmap. | |
| Agent decides | Leave placement to downstream planning. | |

**User's choice:** Full service slice.
**Notes:** Each Arr file owns its corresponding Exportarr instance.

### Shared SOPS defaults

| Option | Description | Selected |
|--------|-------------|----------|
| Host configuration | Put defaults in `hosts/ser8/configuration.nix`. | |
| Dedicated SOPS module | Put defaults in `hosts/ser8/media/sops.nix`. | Yes |
| Repeat defaults | Repeat media SOPS defaults in every service file. | |
| Agent decides | Leave placement to downstream planning. | |

**User's choice:** Dedicated SOPS module.
**Notes:** Service-specific secrets and templates remain locally owned.

### Exportarr representation

| Option | Description | Selected |
|--------|-------------|----------|
| Split ownership | Each Arr host file owns its exporter instance. | Yes |
| Grouped reusable module | Keep all three instances together in a reusable module. | |
| Orchestration ownership | Put all three instances in the cross-service module. | |
| Agent decides | Leave placement to downstream planning. | |

**User's choice:** Split ownership.
**Notes:** Reusable exporter implementation remains generic.

### Jellyfin host boundary

| Option | Description | Selected |
|--------|-------------|----------|
| Household identity only | Move household users, password references, and API-key wiring. | Yes |
| All declarative settings | Move users, networking, API keys, and other declarative settings. | |
| Password wiring only | Keep reusable user profiles and supply only names and secret paths. | |
| Agent decides | Leave the exact boundary to downstream planning. | |

**User's choice:** Household identity only.
**Notes:** Generic account, network, firewall, and exporter implementation stay reusable.

---

## Deployment Units

### Deployment composition

| Option | Description | Selected |
|--------|-------------|----------|
| Service-owned fragments | Service files contribute to the aggregate unit. | Yes |
| Central deployment unit | Keep the complete implementation in orchestration. | |
| Planner decides | Choose any structure that meets parity requirements. | |

**User's choice:** Service-owned fragments.
**Notes:** Preserve the existing `media-config.service` interface and effective order.

### Startup relationships

| Option | Description | Selected |
|--------|-------------|----------|
| Service contribution | Each service file contributes its own `before` dependency. | Yes |
| Orchestration list | Keep the complete dependency list centralized. | |
| Duplicate relationship | Contribute dependencies locally and document the full list centrally. | |
| Agent decides | Leave ownership to downstream planning. | |

**User's choice:** Service contribution.
**Notes:** Import and merge ordering must reproduce the existing effective relationships.

### Helper ownership

| Option | Description | Selected |
|--------|-------------|----------|
| One helper file | Keep the shared helper unchanged. | |
| Split helpers | Separate deployment-focused and orchestration-focused helpers. | Yes |
| Per-service helpers | Put helper logic into individual service files. | |
| Agent decides | Leave helper organization to downstream planning. | |

**User's choice:** Split helpers.
**Notes:** The user explicitly accepted that this prevents exact store-path equality.

### Conflicting acceptance criteria

| Option | Description | Selected |
|--------|-------------|----------|
| Exact store-path parity | Keep one helper file and preserve the original system path. | |
| Split helper ownership | Replace exact path equality with behavior equivalence. | Yes |

**User's choice:** Split helper ownership.
**Notes:** This decision supersedes roadmap success criterion 5.

### Parity evidence

| Option | Description | Selected |
|--------|-------------|----------|
| Evaluated comparison | Compare relevant settings and units, then run build checks. | Yes |
| Build validation only | Rely on `make check` and `make build-ser8`. | |
| Runtime validation | Temporarily activate ser8 and run media smoketests. | |
| Agent decides | Leave verification depth to downstream planning. | |

**User's choice:** Evaluated configuration comparison.
**Notes:** Intentional structural paths may differ; active behavior may not.

---

## Disabled Configuration

### AllDebrid SOPS declarations

| Option | Description | Selected |
|--------|-------------|----------|
| SOPS compatibility section | Preserve declarations in `media/sops.nix`. | |
| Disabled service file | Preserve declarations in an AllDebrid host file. | |
| Disabled-services file | Collect retained disabled configuration. | |
| Remove declarations | Delete both unused secret declarations. | Yes |

**User's choice:** Remove declarations.
**Notes:** This is an approved evaluated configuration change.

### Commented service block

| Option | Description | Selected |
|--------|-------------|----------|
| Delete it | Rely on version control for history. | Yes |
| Move it | Preserve the commented block in a disabled service file. | |
| Document it | Convert the disabled integration into project documentation. | |
| Agent decides | Leave cleanup to downstream planning. | |

**User's choice:** Delete it.
**Notes:** The broken integration is not part of the active service set.

### Reusable AllDebrid module

| Option | Description | Selected |
|--------|-------------|----------|
| Remove module and import | Delete the unimported module and commented import. | Yes |
| Leave both | Limit cleanup to host declarations. | |
| Remove import only | Keep the dormant reusable module. | |
| Defer cleanup | Record removal for a future task. | |

**User's choice:** Remove module and import.
**Notes:** Repository history is the recovery path.

### Adjacent cleanup

| Option | Description | Selected |
|--------|-------------|----------|
| Moved-code cleanup | Remove only obvious residue encountered during the move. | |
| All media modules | Audit all reusable media modules for dead or commented-out code. | Yes |
| AllDebrid only | Preserve all unrelated lines exactly. | |
| Agent decides | Leave cleanup breadth to downstream planning. | |

**User's choice:** All media modules.
**Notes:** Active service behavior must remain unchanged.

## Agent's Discretion

- Exact Nix merge primitives and ordering values.
- Names for the split shell helper files.
- Comparison tooling and normalization of intentional structural differences.

## Deferred Ideas

- Rename shared Usenet secrets to neutral names in a follow-up phase.
- Give NZBGet its own administrator password in a follow-up phase.
