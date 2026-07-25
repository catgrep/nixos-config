# Phase 8: Reorganize ser8 media.nix into per-service modules - Research

**Researched:** 2026-07-25
**Domain:** NixOS module decomposition, systemd unit composition, and sops-nix behavior parity
**Confidence:** HIGH

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

### Service boundaries

- **D-01:** Each host service file owns its service enablement, host settings, SOPS secrets, SOPS templates, deployment contribution, and host-specific monitoring exporter settings.
- **D-02:** Reusable exporter implementations remain generic under `modules/media/`.
- **D-03:** Each Arr service file owns and enables its corresponding Exportarr instance instead of retaining one host-level grouped Exportarr configuration.
- **D-04:** `hosts/ser8/media/jellyfin.nix` owns the complete `admin`, `jordan`, and `sawnia` household user records, password references, and host API-key wiring.
- **D-05:** Generic Jellyfin service account, network, firewall, and exporter implementation remain in reusable modules.
- **D-06:** Shared media SOPS defaults live in `hosts/ser8/media/sops.nix`.
- **D-07:** Each service file still owns its individual secret and template declarations.
- **D-08:** `hosts/ser8/media/default.nix` remains an import-only entry point for the SOPS support module, active service modules, and orchestration module.

### Deployment and orchestration

- **D-09:** Preserve the existing `media-config.service` interface, but assemble its deployment script from ordered fragments contributed by the owning service files.
- **D-10:** Each service file contributes its own `media-config.service.before` dependency.
- **D-11:** Import and merge ordering must reproduce the existing effective deployment order and startup relationships.
- **D-12:** `servarrs-setup.service`, `download-clients-setup.service`, `media-setup.target`, and other genuinely cross-service wiring remain in one orchestration module.
- **D-13:** Split `hosts/ser8/systemd_helpers.sh` into deployment-focused and orchestration-focused helper files.
- **D-14:** The helper split intentionally supersedes the ROADMAP criterion requiring the identical ser8 system store path.

### Behavior-parity validation

- **D-15:** Behavior parity is proven by comparing the before and after evaluated service settings, SOPS declarations and templates, unit dependencies, and generated scripts.
- **D-16:** Structural path differences caused by the approved module and helper split are allowed.
- **D-17:** `make check` and `make build-ser8` must pass after the evaluated comparison.
- **D-18:** No live activation is required for phase acceptance.

### Disabled configuration and cleanup

- **D-19:** Remove the unused `alldebrid_api_key` and `alldebrid_transmission_admin_password` SOPS declarations.
- **D-20:** Delete the commented-out AllDebrid service block from the old host configuration rather than moving or documenting it.
- **D-21:** Delete `modules/media/alldebrid-proxy.nix` and remove its commented import from `modules/media/default.nix`.
- **D-22:** Audit every file under `modules/media/` and remove commented-out or genuinely dead code while preserving all active service behavior.

### the agent's Discretion

- Exact Nix merge primitives and ordering values used to assemble `media-config.service`.
- Exact names for the deployment-focused and orchestration-focused shell helper files.
- The comparison command or script used to normalize intentional structural differences during parity validation.
- Mechanical formatting and comment wording that do not affect active behavior.

### Deferred Ideas (OUT OF SCOPE)

- Renaming `sabnzbd_usenet_*` secrets to neutral `usenet_*` names remains out of scope.
- Giving NZBGet a separate `nzbget_admin_password` remains out of scope.
</user_constraints>

## Project Constraints (from AGENTS.md)

- Enter the development environment with `make dev` before running repository tooling. [VERIFIED: AGENTS.md]
- Prefer small modules imported through the relevant directory's import-only `default.nix`; do not assume every file is active merely because it exists. [VERIFIED: AGENTS.md]
- Format Nix with `nixfmt-rfc-style` and do not hand-align against formatter output. [VERIFIED: AGENTS.md]
- Use lowercase kebab-case module filenames and preserve existing `SPDX-License-Identifier: GPL-3.0-or-later` headers. [VERIFIED: AGENTS.md]
- New Bash files must use their declared interpreter, start with `set -euo pipefail`, and pass `shellcheck` plus `shfmt -d`. [VERIFIED: AGENTS.md]
- Use `sb` before reading large source files, use `rg` for text search, and use `fd` for file search. [VERIFIED: AGENTS.md]
- Validate behavior at the narrowest relevant level first, then run `make check`; warnings are failures. [VERIFIED: AGENTS.md]
- Add or update media smoketests when deployed media behavior changes, while retaining `all.sh` as the entry point referenced by `deploy.yaml`. [VERIFIED: AGENTS.md]
- Never expose plaintext credentials, decrypted SOPS content, private keys, or tokens in logs, documentation, or diffs. [VERIFIED: AGENTS.md]
- Use the provided SOPS targets for encrypted-data changes instead of ad hoc editing. [VERIFIED: AGENTS.md]
- Do not run `make test-ser8`, `make switch-ser8`, `make apply-ser8`, or other live deployment actions without explicit intent; this phase explicitly requires no live activation. [VERIFIED: AGENTS.md] [VERIFIED: CONTEXT.md]
- Treat `rollback-HOST` as a placeholder and never present it as functional. [VERIFIED: AGENTS.md]
- Keep commits short, scoped, imperative, and limited to one logical change; do not add an agent co-author and do not push to `main`. [VERIFIED: AGENTS.md]
- Review the diff and resolve all formatter, linter, evaluator, and test warnings before committing. [VERIFIED: AGENTS.md]

## Summary

This phase should be planned as a behavior-first extraction, not as seven independent rewrites.
The current host module is 748 lines, the shared helper is 531 lines, and the evaluated configuration couples seven service configurations, three Exportarr instances, seven SOPS-rendered media templates, two setup units, one deployment unit, and one target. [VERIFIED: codebase grep] [VERIFIED: nix eval]
The safest sequence is to capture a normalized evaluated baseline first, establish the import-only directory and shared SOPS defaults, move one complete service slice at a time, then extract orchestration and helper functions without changing their bodies. [VERIFIED: CONTEXT.md] [CITED: https://nixos.org/manual/nixos/stable/]

Use native NixOS module merging for the shared `media-config.script` and `before` lists.
The pinned NixOS definition declares `systemd.services.<name>.script` as `types.lines`, while dependency fields such as `before` are lists, so separate modules can contribute definitions. [VERIFIED: pinned nixpkgs source grep]
Assign explicit `lib.mkOrder` priorities to every fragment instead of relying on import order; the official manual states that `mkBefore`, ordinary definitions, and `mkAfter` use order priorities 500, 1000, and 1500, respectively. [CITED: https://nixos.org/manual/nixos/stable/]
A local `lib.evalModules` probe against the pinned nixpkgs source verified that `types.lines` definitions with orders 100, 200, and 300 evaluate in that order. [VERIFIED: nix eval]

The principal planning risk is an inaccurate baseline.
The worktree already contains uncommitted additions for `jellyfin_sawnia_password`, while the current evaluated Jellyfin user set is only `admin` and `jordan`. [VERIFIED: git diff] [VERIFIED: nix eval]
Therefore `sawnia` is an approved functional addition under D-04 rather than a behavior-preserving move, and parity tooling must encode that expected delta explicitly. [VERIFIED: CONTEXT.md] [VERIFIED: nix eval]
The current Nix invocation also emits pre-existing warnings for unsupported local settings and a Home Manager 25.05 versus nixpkgs 25.11 mismatch; the zero-warning project rule means planning must distinguish environment-only warnings from the repository-owned release mismatch rather than declaring a clean gate prematurely. [VERIFIED: nix eval] [VERIFIED: AGENTS.md]

**Primary recommendation:** Capture a checked-in or durable normalized baseline projection before edits, migrate complete service slices using explicit `lib.mkOrder` values, and compare only documented expected deltas before running the full build gates.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Service enablement and ser8-specific settings | Host configuration | Reusable NixOS module | Host files own policy while reusable modules own generic implementation. [VERIFIED: CONTEXT.md] |
| Media secret declarations and rendered templates | Host configuration | sops-nix activation | Service files declare their own keys/templates; `sops.nix` supplies shared defaults. [VERIFIED: CONTEXT.md] [CITED: https://github.com/Mic92/sops-nix] |
| Jellyfin household identities and API-key wiring | Host configuration | Reusable Jellyfin module | Household records are ser8 policy; accounts, network, firewall, and exporter implementation remain generic. [VERIFIED: CONTEXT.md] |
| Arr exporter instances | Host configuration | NixOS Prometheus exporter implementation | Sonarr, Radarr, and Prowlarr each own their instance URL, key path, port, and enablement. [VERIFIED: CONTEXT.md] [VERIFIED: codebase grep] |
| Per-service configuration deployment | Owning host service module | `media-config.service` | Each file contributes one ordered script fragment and one `before` dependency to the stable aggregate unit. [VERIFIED: CONTEXT.md] |
| Cross-service API registration | Host orchestration module | Service APIs | Prowlarr application registration and download-client registration inherently span multiple services. [VERIFIED: codebase grep] |
| Unit ordering and activation | systemd through NixOS | Host orchestration module | `before`/`after` order units, while `wantedBy`, `wants`, and `requires` determine pull-in and failure coupling. [CITED: https://nixos.org/manual/nixos/stable/] |
| Persistent application databases | Database / storage on ser8 | Impermanence module | Existing `/var/lib` paths are persisted independently of source-module location. [VERIFIED: codebase grep] |

## Standard Stack

### Core

| Component | Version | Purpose | Why Standard |
|-----------|---------|---------|--------------|
| Nix | 2.34.7+1 | Evaluate the flake, inspect configuration attributes, and build ser8 | Installed locally and used by every repository validation target. [VERIFIED: local CLI] |
| NixOS / nixpkgs | 25.11 pin, evaluated system revision `25.11.20260518.687f05a` | NixOS module system and systemd option declarations | This is the repository's pinned target, so its exact option types govern merge behavior. [VERIFIED: AGENTS.md] [VERIFIED: nix eval] |
| NixOS module library | Pinned with nixpkgs | `lib.mkOrder`, `lib.mkIf`, `lib.mkMerge`, and typed option merging | Native merging preserves definition provenance and avoids a custom fragment registry. [CITED: https://nixos.org/manual/nixos/stable/] |
| sops-nix | Flake-locked revision | Secret declarations, placeholders, and runtime-rendered templates | The project already uses it, and official guidance matches the existing declaration/template pattern. [CITED: https://github.com/Mic92/sops-nix] [VERIFIED: codebase grep] |
| systemd NixOS module | Pinned with nixpkgs | Aggregate oneshot units, dependencies, and target wiring | Existing runtime interfaces are already expressed through these options. [VERIFIED: codebase grep] |

### Supporting

| Tool | Version | Purpose | When to Use |
|------|---------|---------|-------------|
| nixfmt | 1.2.0 | Format all changed Nix files | After each extraction and before comparison. [VERIFIED: local CLI] |
| statix | `0-unstable-2026-05-09` package | Static Nix checks | On the affected directories, then through `make check`. [VERIFIED: local CLI store path] |
| ShellCheck | 0.11.0 | Validate both split helper scripts | After helper extraction; justify intentional SC2016 suppressions for jq programs. [VERIFIED: local CLI] [VERIFIED: shellcheck run] |
| shfmt | 3.12.0 | Enforce shell formatting | On both split helper scripts. [VERIFIED: local CLI] |
| `sb` / ast-bro | 3.0.0 | Structure-aware code exploration where the language is supported | Use before large source reads; Nix files currently fall back to `rg` because `sb` returned no Nix structure. [VERIFIED: local CLI] |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Explicit `lib.mkOrder` on native `types.lines` definitions | A custom `media.deploymentFragments` option with sorting logic | The custom option adds an abstraction and schema for a one-host problem; native merging is already typed and verified. [CITED: https://nixos.org/manual/nixos/stable/] |
| Behavior projection plus targeted comparison | Exact `system.build.toplevel` store-path equality | The locked helper split and dead-code cleanup intentionally change source paths and derivations. [VERIFIED: CONTEXT.md] |
| One orchestration module | Assign cross-service API calls to Prowlarr or a download client | That obscures ownership because every call consumes secrets and endpoints from multiple services. [VERIFIED: codebase grep] |

**Installation:** No new package installation is required. [VERIFIED: codebase grep]

## Architecture Patterns

### System Architecture Diagram

```text
hosts/ser8/configuration.nix
        |
        v
hosts/ser8/media/default.nix (imports only)
        |
        +--> sops.nix --------------------------> shared SOPS file/age defaults
        |
        +--> jellyfin.nix ----------------------> users + API key + exporter wiring
        +--> sonarr.nix ----+
        +--> radarr.nix -----+--> secrets/templates/settings/exporters
        +--> prowlarr.nix ---+        |
        +--> qbittorrent.nix +--------+--> ordered media-config fragments
        +--> nzbget.nix -----+        |              |
        +--> sabnzbd.nix ----+        |              v
        |                             |      media-config.service
        v                             |              |
orchestration.nix <-------------------+              v
        |                                     service config files
        +--> servarrs-setup.service --> Prowlarr + Sonarr + Radarr APIs
        +--> download-clients-setup.service --> Arr + qBittorrent/NZBGet/SABnzbd APIs
        +--> media-setup.target
```

The diagram reflects the locked ownership model and existing data flow. [VERIFIED: CONTEXT.md] [VERIFIED: codebase grep]

### Recommended Project Structure

```text
hosts/ser8/
├── configuration.nix
└── media/
    ├── default.nix                  # imports only
    ├── sops.nix                     # shared SOPS defaults
    ├── jellyfin.nix                 # users, secrets, API key, exporter wiring
    ├── sonarr.nix                   # service, secrets, template, Exportarr, fragment
    ├── radarr.nix                   # service, secrets, template, Exportarr, fragment
    ├── prowlarr.nix                 # service, secrets, template, Exportarr, fragment
    ├── qbittorrent.nix              # service, secrets, template, nginx, fragment
    ├── nzbget.nix                   # service, shared Usenet references, template, fragment
    ├── sabnzbd.nix                  # service, Usenet secrets/template, fragment
    ├── orchestration.nix            # aggregate unit envelope, setup units, target
    ├── deployment-helpers.sh        # configure_arr only
    └── orchestration-helpers.sh     # API readiness, sanitization, and registration
```

The helper filenames are discretionary; the functional boundary is the important contract. [VERIFIED: CONTEXT.md]

### Pattern 1: Explicit ordered contributions

**What:** Define the stable unit envelope centrally and contribute one ordered `types.lines` fragment plus one ordered dependency from each service module.

**When to use:** Use for `media-config.service`, where one unit interface must remain stable but ownership is distributed.

```nix
# Source: NixOS manual option-definition ordering and pinned systemd script type
{
  lib,
  config,
  ...
}:
{
  systemd.services.media-config = {
    before = lib.mkOrder 100 [ "sonarr.service" ];
    script = lib.mkOrder 200 ''
      configure_arr sonarr ${config.sops.templates."sonarr-config.xml".path}
    '';
  };
}
```

Use a documented order table rather than ad hoc numbers. [VERIFIED: codebase grep]

| Order | Script fragment | Existing effective order |
|-------|-----------------|--------------------------|
| 100 | Orchestration-owned prologue and deployment-helper source | First [VERIFIED: nix eval] |
| 200 | Sonarr deploy | 1 [VERIFIED: nix eval] |
| 300 | Radarr deploy | 2 [VERIFIED: nix eval] |
| 400 | Prowlarr deploy | 3 [VERIFIED: nix eval] |
| 500 | NZBGet deploy | 4 [VERIFIED: nix eval] |
| 600 | SABnzbd deploy | 5 [VERIFIED: nix eval] |
| 700 | qBittorrent deploy | 6 [VERIFIED: nix eval] |
| 800 | Orchestration-owned completion message | Last [VERIFIED: nix eval] |

The `before` list must separately preserve Sonarr, Radarr, Prowlarr, qBittorrent, NZBGet, SABnzbd order. [VERIFIED: nix eval]

### Pattern 2: Complete vertical service slice

**What:** Move enablement and settings from `configuration.nix`, secret declarations and template content from `media.nix`, exporter instance settings from `modules/media/exportarr.nix`, and the service's deployment line into one host file.

**When to use:** Apply to each of Sonarr, Radarr, Prowlarr, qBittorrent, NZBGet, and SABnzbd.

Keep shared Usenet secret declarations in the SABnzbd owner file but allow NZBGet to reference the same existing secret paths without redeclaring them. [VERIFIED: CONTEXT.md]
This preserves the explicitly deferred shared credential names and avoids conflicting duplicate declarations. [VERIFIED: CONTEXT.md]

### Pattern 3: Generic exporter implementation with host wiring

**What:** Keep the Jellyfin exporter package, wrapper, hardening, and service implementation under `modules/media/`, but expose the minimum option surface needed for host-owned enablement and `apiKeyFile` wiring.

**When to use:** Apply while removing the reusable module's direct dependency on the ser8-specific `jellyfin_api_key` declaration.

The current reusable exporter references `config.sops.secrets.jellyfin_api_key.path` directly, so it is not yet genuinely host-agnostic. [VERIFIED: codebase grep]
The grouped `modules/media/exportarr.nix` contains only ser8 instance values, so move those three definitions into host files and remove the grouped import rather than retaining two owners. [VERIFIED: codebase grep] [VERIFIED: CONTEXT.md]

### Pattern 4: Projection-based parity snapshot

**What:** Evaluate a deliberately selected JSON projection before edits and the same projection after edits, then diff it with a small allowlist for D-04, D-14, and D-19 through D-22.

**When to use:** Capture the baseline before moving any source, especially because the current worktree is already dirty.

```bash
# Source: https://nix.dev/manual/nix/2.34/command-ref/new-cli/nix3-eval.html
nix eval --json \
  --apply 'config: { /* selected serializable attributes */ }' \
  '.#nixosConfigurations.ser8.config' > /tmp/ser8-media-before.json
```

The projection should include selected service settings, all media secret metadata, all media template metadata/content, household users, exporter settings, the three media systemd service definitions, and `media-setup.target`. [VERIFIED: CONTEXT.md]
Never include decrypted secret values. [VERIFIED: AGENTS.md] [CITED: https://github.com/Mic92/sops-nix]

### Anti-Patterns to Avoid

- **Relying on import order:** Definition order is a module-system property and should be explicit with `mkOrder`. [CITED: https://nixos.org/manual/nixos/stable/]
- **Moving only templates:** Leaving enablement, nginx, exporter, or secret declarations in old owners defeats one-stop discovery. [VERIFIED: CONTEXT.md]
- **Creating one file per systemd unit:** Boundaries are services, with genuinely cross-service units together in orchestration. [VERIFIED: CONTEXT.md]
- **Duplicating shared Usenet secrets:** SABnzbd and NZBGet currently share names by locked deferred decision; reference one declaration owner. [VERIFIED: CONTEXT.md]
- **Comparing only the final derivation path:** Approved file/helper movement changes derivations while semantic values can remain equal. [VERIFIED: CONTEXT.md]
- **Editing encrypted YAML directly:** Use repository SOPS workflows and never emit plaintext. [VERIFIED: AGENTS.md]

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Ordered script composition | A custom fragment registry and sorting function | `types.lines` definitions with `lib.mkOrder` | The NixOS module system already merges line definitions deterministically. [CITED: https://nixos.org/manual/nixos/stable/] [VERIFIED: pinned nixpkgs source grep] |
| Secret interpolation | A shell-time substitution engine | `sops.templates` and `config.sops.placeholder` | sops-nix renders secrets at activation and exposes a stable runtime path. [CITED: https://github.com/Mic92/sops-nix] |
| Service activation links | Manual `systemctl enable` calls | `wantedBy`, `wants`, and `requires` | NixOS creates stateless dependency links declaratively. [VERIFIED: pinned nixpkgs source grep] |
| Parity proof | Grep counts or line-by-line source comparison | `nix eval --json` projection and structured diff | Source layout is intentionally changing; evaluated behavior is the contract. [CITED: https://nix.dev/manual/nix/2.34/command-ref/new-cli/nix3-eval.html] [VERIFIED: CONTEXT.md] |
| API secrets in scripts | Literal values or evaluation-time secret reads | Existing secret file paths and systemd credentials | sops-nix secrets are unavailable at evaluation and should not enter the Nix store. [CITED: https://github.com/Mic92/sops-nix] |

**Key insight:** This phase becomes simple when native module merging is treated as the composition mechanism and evaluated configuration is treated as the behavior contract.

## Runtime State Inventory

| Category | Items Found | Action Required |
|----------|-------------|-----------------|
| Stored data | Jellyfin, Sonarr, Radarr, Prowlarr, qBittorrent, SABnzbd, and NZBGet retain state under existing `/var/lib` paths, most persisted through `hosts/ser8/impermanence.nix`. [VERIFIED: codebase grep] | No data migration; preserve users, groups, paths, ownership, and template destinations exactly. [VERIFIED: CONTEXT.md] |
| Live service config | Arr application and download-client registrations live in service databases and are updated by `servarrs-setup` and `download-clients-setup`, not represented fully in Git. [VERIFIED: codebase grep] | No live mutation or migration; preserve unit names, API payloads, ordering, and idempotent upsert functions, and do not activate during acceptance. [VERIFIED: CONTEXT.md] |
| OS-registered state | ser8 has generated systemd units for `media-config`, `servarrs-setup`, `download-clients-setup`, and `media-setup.target`. [VERIFIED: nix eval] | No re-registration task because no live activation is authorized; compare generated unit definitions only. [VERIFIED: CONTEXT.md] |
| Secrets/env vars | Media SOPS keys and templates use `/run/secrets` and `/run/secrets/rendered`; two AllDebrid declarations are evaluated today, and encrypted keys also remain in `secrets/ser8.yaml`. [VERIFIED: nix eval] [VERIFIED: codebase grep] | Remove only the locked Nix declarations unless encrypted-key deletion is separately authorized; preserve all other key names, especially shared `sabnzbd_usenet_*` and the NZBGet password reference. [VERIFIED: CONTEXT.md] |
| Build artifacts | The current toplevel derivation is `/nix/store/4a3sx4n4khjihw8x535ffcxrhg591csm-nixos-system-ser8-25.11.20260518.687f05a.drv`; Nix store outputs are immutable. [VERIFIED: nix eval] | Expect a new derivation because helper source paths change; do not delete old store objects or require store-path equality. [VERIFIED: CONTEXT.md] |

The canonical runtime-state answer is that repository edits alone do not mutate persisted service databases, systemd state, or encrypted values, and this phase deliberately stops before activation. [VERIFIED: CONTEXT.md]

## Common Pitfalls

### Pitfall 1: New module files are invisible to Git flake evaluation

**What goes wrong:** `nix eval '.#...'` reports missing imports or silently evaluates the tracked tree without newly created files.

**Why it happens:** Nix flake workflows default to Git-tracked files for repository inputs. [CITED: https://nix.dev/tutorials/working-with-local-files.html]

**How to avoid:** Stage new files before flake evaluation, or deliberately evaluate an explicit path flake during development; verify `git status` before every parity run.

**Warning signs:** The file exists on disk but the Nix error says it does not exist in the source tree.

### Pitfall 2: Relative paths change one directory deeper

**What goes wrong:** `../../secrets/ser8.yaml` or `./systemd_helpers.sh` resolves to the wrong path after moving under `hosts/ser8/media/`.

**Why it happens:** Nix path literals are resolved relative to the containing file. [VERIFIED: codebase grep]

**How to avoid:** Update the SOPS default to `../../../secrets/ser8.yaml` and point each source expression at the chosen split helper in the new directory.

**Warning signs:** Evaluation fails with a missing path, or a generated unit sources an unexpected store file.

### Pitfall 3: Script fragments reorder deployment

**What goes wrong:** Services receive templates in a different sequence or the prologue runs after a service fragment.

**Why it happens:** Multiple `types.lines` definitions merge, but unqualified module order is not a readable service contract.

**How to avoid:** Give every prologue, service, and epilogue fragment a unique named order constant or documented numeric order and assert the evaluated script sequence.

**Warning signs:** The normalized `media-config.script` diff moves `configure_arr` lines.

### Pitfall 4: Ordering is confused with dependency activation

**What goes wrong:** A unit is ordered after another unit but the dependency is not pulled in, or failure behavior changes because `wants` is substituted for `requires`.

**Why it happens:** `after`/`before` only order units that are already in the transaction; `wants`/`requires` express dependency relationships. [CITED: https://nixos.org/manual/nixos/stable/]

**How to avoid:** Preserve `after`, `before`, `requires`, `wantedBy`, and target `wants` as separate compared fields.

**Warning signs:** List membership matches partially, but generated unit relationships differ.

### Pitfall 5: Generic modules retain host-specific secret dependencies

**What goes wrong:** `modules/media/jellyfin-exporter.nix` still requires `config.sops.secrets.jellyfin_api_key`, so importing the reusable module elsewhere fails.

**Why it happens:** The current exporter module directly references the ser8 secret path. [VERIFIED: codebase grep]

**How to avoid:** Expose a minimal generic enable/key-file interface and set it in `hosts/ser8/media/jellyfin.nix`.

**Warning signs:** The reusable module contains `sops`, `ser8`, or a household username after the refactor.

### Pitfall 6: Cleanup scope is incomplete

**What goes wrong:** The named AllDebrid module is deleted but stale references and replaced Transmission code remain discoverable.

**Why it happens:** The current tree also contains commented AllDebrid references in `flake.nix`, an active AllDebrid tmpfiles directory in `impermanence.nix`, and an unimported `modules/media/transmission.nix`; `TODO.md` states Transmission was replaced by qBittorrent. [VERIFIED: codebase grep]

**How to avoid:** Make the D-22 audit an explicit checklist over every `modules/media/*.nix`, then separately decide the two out-of-directory AllDebrid remnants rather than deleting them accidentally.

**Warning signs:** `rg 'alldebrid|transmission' flake.nix hosts/ser8 modules/media` still returns implementation references after approved cleanup.

### Pitfall 7: Baseline warnings are mistaken for refactor regressions

**What goes wrong:** The final gate is reported clean even though evaluation emits warnings, or unrelated warnings consume debugging time late in the phase.

**Why it happens:** Current evaluation emits unsupported-setting warnings from local Nix configuration and a repository-owned Home Manager release mismatch warning. [VERIFIED: nix eval]

**How to avoid:** Record warning output with the baseline, classify ownership before implementation, and satisfy the repository zero-warning rule before phase completion. [VERIFIED: AGENTS.md]

**Warning signs:** `nix eval`, `make check`, or `make build-ser8` exits zero but prints warnings.

### Pitfall 8: The shell split introduces lint or safety regressions

**What goes wrong:** New helper files omit strict mode, retain formatting drift, or fail ShellCheck on intentional jq expressions.

**Why it happens:** The current combined helper does not start with `set -euo pipefail`, `shfmt -d` reports whole-file indentation drift, and ShellCheck reports seven SC2016 informational findings. [VERIFIED: shellcheck run] [VERIFIED: shfmt run]

**How to avoid:** Add strict mode to both new files, run `shfmt`, and use narrowly scoped SC2016 ignores with comments explaining that single-quoted jq programs intentionally defer `$name` and related variables to jq.

**Warning signs:** Any output from `shellcheck` or `shfmt -d`.

## Code Examples

Verified patterns from official sources and the pinned codebase:

### Host-owned SOPS template

```nix
# Source: https://github.com/Mic92/sops-nix
{
  config,
  ...
}:
{
  sops.secrets.sonarr_api_key = {
    owner = "root";
    group = "root";
    mode = "0600";
  };

  sops.templates."sonarr-config.xml" = {
    content = ''
      <ApiKey>${config.sops.placeholder.sonarr_api_key}</ApiKey>
    '';
    owner = "sonarr";
    group = "sonarr";
    mode = "0600";
  };
}
```

### Ordered lines merge

```nix
# Source: https://nixos.org/manual/nixos/stable/
{
  lib,
  ...
}:
{
  systemd.services.media-config.script = lib.mkOrder 300 ''
    configure_arr radarr /run/secrets/rendered/radarr-config.xml
  '';
}
```

### Stable behavior projection

```nix
# Source: Nix 2.34 nix eval documentation and current ser8 config
config:
let
  mediaSecrets = [
    "jellyfin_admin_password"
    "jellyfin_jordan_password"
    "jellyfin_sawnia_password"
    "jellyfin_api_key"
    "sonarr_admin_password"
    "sonarr_api_key"
    "radarr_admin_password"
    "radarr_api_key"
    "prowlarr_admin_password"
    "prowlarr_api_key"
    "qbittorrent_admin_password"
    "qbittorrent_admin_password_hash"
    "sabnzbd_admin_password"
    "sabnzbd_api_key"
    "sabnzbd_nzb_key"
    "sabnzbd_usenet_username"
    "sabnzbd_usenet_password"
    "sabnzbd_usenet_provider"
  ];
  select = names: attrs: builtins.listToAttrs (
    map (name: {
      inherit name;
      value = attrs.${name};
    }) names
  );
in
{
  secrets = builtins.mapAttrs (_: value: {
    inherit (value) owner group mode path;
  }) (select mediaSecrets config.sops.secrets);
  users = config.services.declarative-jellyfin.users;
  mediaConfig = {
    inherit (config.systemd.services.media-config) before wantedBy script;
  };
  servarrsSetup = {
    inherit (config.systemd.services.servarrs-setup) after requires wantedBy script;
  };
  downloadClientsSetup = {
    inherit (config.systemd.services.download-clients-setup) after requires wantedBy script;
  };
  mediaTarget = config.systemd.targets.media-setup;
}
```

The final projection should also include template content/ownership, service enablement/settings, exporter fields, qBittorrent nginx configuration, firewall ports, and generic system users. [VERIFIED: CONTEXT.md] [VERIFIED: codebase grep]

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| One 748-line host media module | Import-only directory with complete service slices | Locked for Phase 8 | Service ownership becomes discoverable without changing live activation. [VERIFIED: CONTEXT.md] |
| One grouped Exportarr host configuration under `modules/media/` | Arr-owned exporter instances in host files | Locked for Phase 8 | Generic implementation and host policy stop sharing an owner. [VERIFIED: CONTEXT.md] |
| One 531-line helper file | Deployment helper plus orchestration helper | Locked for Phase 8 | Store paths change intentionally, so semantic comparison replaces exact derivation equality. [VERIFIED: CONTEXT.md] |
| Exact system store-path criterion in ROADMAP | Evaluated behavior parity with documented deltas | Context gathered 2026-07-25 | CONTEXT.md supersedes the stale roadmap criterion. [VERIFIED: CONTEXT.md] |

**Deprecated/outdated:**

- The commented AllDebrid host block, reusable module, and commented module import are explicitly removed by D-20 and D-21. [VERIFIED: CONTEXT.md]
- `modules/media/transmission.nix` is unimported and `TODO.md` records Transmission as replaced by qBittorrent, making it a D-22 dead-code candidate. [VERIFIED: codebase grep]
- `modules/media/exportarr.nix` is a grouped host-policy file despite its reusable location; its three instance definitions move to owning host modules. [VERIFIED: codebase grep] [VERIFIED: CONTEXT.md]

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | The new `sawnia` Jellyfin record should mirror Jordan's non-administrator permissions and preferences while using `jellyfin_sawnia_password`. [ASSUMED] | Open Questions / implementation | Wrong household permissions would be an unintended access-control change. |

## Open Questions

1. **What exact permissions and preferences should `sawnia` receive?**
   - What we know: D-04 requires a complete `sawnia` record, and the working tree already declares its password secret, but current evaluated users are only `admin` and `jordan`. [VERIFIED: CONTEXT.md] [VERIFIED: git diff] [VERIFIED: nix eval]
   - What's unclear: No existing source or history defines Sawnia's administrator flag, remote-access policy, deletion permission, subtitle mode, or autoplay preferences. [VERIFIED: codebase grep] [VERIFIED: git log]
   - Recommendation: Use Jordan's record as the proposed household-user template only after a human confirmation checkpoint. [ASSUMED]

2. **How far should dead AllDebrid and Transmission cleanup extend outside `modules/media/`?**
   - What we know: D-19 through D-21 name the host declarations/block and reusable module/import; codebase search also finds two commented `flake.nix` remnants, an active AllDebrid tmpfiles directory, and unimported Transmission code. [VERIFIED: CONTEXT.md] [VERIFIED: codebase grep]
   - What's unclear: The locked decisions do not explicitly authorize deleting the encrypted YAML keys, `impermanence.nix` directory rule, `flake.nix` comments, or `modules/media/transmission.nix`.
   - Recommendation: Remove `modules/media/transmission.nix` under D-22 and stale code comments under the no-phantom-features rule; leave encrypted YAML keys untouched unless the user explicitly authorizes SOPS editing, and make the `impermanence.nix` directory rule a planner checkpoint because it changes evaluated active configuration.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|-------------|-----------|---------|----------|
| Nix daemon and CLI | Evaluation and build gates | Available outside sandbox | 2.34.7+1 | Run approved local Nix commands; no code fallback. [VERIFIED: local CLI] |
| nixfmt | Nix formatting | Yes | 1.2.0 | `make fmt` in development shell. [VERIFIED: local CLI] |
| statix | Static Nix checks | Yes | `0-unstable-2026-05-09` package | `make check`. [VERIFIED: local CLI store path] |
| ShellCheck | Helper validation | Yes | 0.11.0 | None needed. [VERIFIED: local CLI] |
| shfmt | Helper formatting | Yes | 3.12.0 | None needed. [VERIFIED: local CLI] |
| `sb` | Structure-aware exploration | Yes | 3.0.0 | Use `rg` for Nix because the current parser produced no Nix map. [VERIFIED: local CLI] |
| ser8 live host | Activation validation | Not required | Not probed | Evaluated comparison plus builds, per D-18. [VERIFIED: CONTEXT.md] |

**Missing dependencies with no fallback:** None. [VERIFIED: environment audit]

**Missing dependencies with fallback:** None; live ser8 access is intentionally unnecessary. [VERIFIED: CONTEXT.md]

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | Nix evaluator/build checks plus ShellCheck 0.11.0, shfmt 3.12.0, and statix [VERIFIED: local CLI] |
| Config file | `flake.nix`, `Makefile`, and a Wave 0 phase-specific parity projection [VERIFIED: codebase grep] |
| Quick run command | `nix eval --json --apply '<projection>' '.#nixosConfigurations.ser8.config'` [CITED: https://nix.dev/manual/nix/2.34/command-ref/new-cli/nix3-eval.html] |
| Full suite command | `make check && make build-ser8` [VERIFIED: AGENTS.md] [VERIFIED: CONTEXT.md] |

### Phase Requirements -> Test Map

No formal requirement IDs map to Phase 8. [VERIFIED: REQUIREMENTS.md]

| Behavior | Test Type | Automated Command | File Exists? |
|----------|-----------|-------------------|-------------|
| Import-only `media/default.nix`, old file removed, and expected service files present | structural | Phase-specific `rg`/file assertions | No, Wave 0 |
| Evaluated service settings and enablement preserved | evaluation regression | `nix eval --json` projection and JSON diff | No, Wave 0 |
| SOPS declarations/templates preserved except locked removals | evaluation regression | Projection compares names, ownership, modes, paths, and template content | No, Wave 0 |
| Unit dependencies and target relationships preserved | evaluation regression | Projection compares `before`, `after`, `requires`, `wantedBy`, and `wants` | No, Wave 0 |
| Generated script behavior preserved with helper path normalization | evaluation regression | Normalize store helper paths, compare script line order, and compare moved function bodies | No, Wave 0 |
| Split helpers are clean Bash | static | `shellcheck hosts/ser8/media/*.sh && shfmt -d hosts/ser8/media/*.sh` | Existing combined helper only |
| Nix files are formatted and statically valid | static/evaluation | `nixfmt --check hosts/ser8/media/*.nix modules/media/*.nix && statix check hosts/ser8/media` | Framework exists |
| ser8 system evaluates and builds | build | `make build-ser8` | Existing target |
| Repository-wide checks remain green | full regression | `make check` | Existing target |

### Sampling Rate

- **Per task commit:** Run the targeted projection diff, Nix formatting check, and helper linters for files touched by that task.
- **Per wave merge:** Run the full normalized parity comparison and `make build-ser8`.
- **Phase gate:** Run `make check && make build-ser8` with no unresolved warnings before `$gsd-verify-work`. [VERIFIED: AGENTS.md] [VERIFIED: CONTEXT.md]

### Wave 0 Gaps

- [ ] Create a phase-specific Nix projection that serializes only the behavior contract and never secret contents.
- [ ] Capture `/tmp/ser8-media-before.json` or a durable non-secret fixture before any refactor edit, including the current uncommitted Sawnia secret declaration.
- [ ] Define an expected-delta allowlist for Sawnia, AllDebrid declarations, helper store paths, and approved dead-code removals.
- [ ] Add structural assertions for import-only `default.nix`, required service files, absence of `hosts/ser8/media.nix`, and absence of host policy from reusable modules.
- [ ] Establish narrow, justified SC2016 ignores for jq expressions before enforcing zero ShellCheck findings.
- [ ] Record the current warning baseline and decide ownership of the Home Manager 25.05 versus nixpkgs 25.11 mismatch before the final zero-warning gate.

## Security Domain

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | Yes, configuration parity only | Preserve Jellyfin and Arr authentication settings and hashed-password file references exactly except the approved Sawnia addition. [VERIFIED: codebase grep] |
| V3 Session Management | No | This phase does not implement or alter session handling. [VERIFIED: phase scope] |
| V4 Access Control | Yes | Preserve SOPS owners, groups, modes, system users, and Jellyfin permissions; require confirmation for Sawnia's policy. [VERIFIED: codebase grep] |
| V5 Input Validation | Yes | Rely on typed NixOS options, evaluation, ShellCheck, and structured JSON comparison rather than text-only validation. [VERIFIED: pinned nixpkgs source grep] |
| V6 Cryptography | Yes | Keep sops-nix and encrypted source files; never hand-roll encryption or evaluate/decrypt secret values. [CITED: https://github.com/Mic92/sops-nix] |

The category names follow the ASVS 4 structure requested by the research template. [CITED: https://devguide.owasp.org/en/03-requirements/05-asvs/]

### Known Threat Patterns for NixOS and shell configuration

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Secret content enters a generated Nix store script or test artifact | Information Disclosure | Interpolate only runtime secret paths/placeholders and inspect comparison fixtures for plaintext before commit. [CITED: https://github.com/Mic92/sops-nix] |
| Shell argument or API payload changes during extraction | Tampering | Move function bodies mechanically, retain quoting, run ShellCheck, and compare normalized generated scripts. [VERIFIED: codebase grep] |
| Unit dependency semantics change | Denial of Service | Compare `before`, `after`, `requires`, `wantedBy`, and target `wants` independently. [CITED: https://nixos.org/manual/nixos/stable/] |
| Household user receives excessive permissions | Elevation of Privilege | Treat every Jellyfin permission field as an evaluated contract and require confirmation for the new Sawnia record. [VERIFIED: nix eval] [ASSUMED] |
| Sanitized logging regresses | Information Disclosure | Keep `sanitize_api_key` and `curl_safe` in orchestration helpers and preserve all callers. [VERIFIED: codebase grep] |

## Sources

### Primary (HIGH confidence)

- Repository `AGENTS.md`, Phase 8 `CONTEXT.md`, `ROADMAP.md`, `REQUIREMENTS.md`, and `STATE.md` - locked scope, project rules, and roadmap conflict.
- `hosts/ser8/media.nix`, `hosts/ser8/configuration.nix`, `hosts/ser8/systemd_helpers.sh`, `hosts/ser8/impermanence.nix`, `modules/media/*.nix`, `flake.nix`, `Makefile`, and smoketests - current implementation and boundaries.
- Local Nix 2.34.7+1 evaluation of the pinned ser8 configuration - service states, users, exporters, secrets/templates, dependencies, scripts, and derivation baseline.
- Pinned nixpkgs `nixos/lib/systemd-unit-options.nix` - exact `types.lines` and list option declarations.

### Secondary (MEDIUM confidence)

- https://nixos.org/manual/nixos/stable/ - module definition ordering and systemd dependency semantics.
- https://nix.dev/manual/nix/2.34/command-ref/new-cli/nix3-eval.html - JSON evaluation and `--apply` usage.
- https://nix.dev/tutorials/working-with-local-files.html - Git-tracked file behavior in flake workflows.
- https://github.com/Mic92/sops-nix - secret, placeholder, template, and activation patterns.
- https://devguide.owasp.org/en/03-requirements/05-asvs/ - ASVS category applicability review.

### Tertiary (LOW confidence)

- None.

## Metadata

**Confidence breakdown:**

- Standard stack: HIGH - versions and option types were verified locally against the pinned environment.
- Architecture: HIGH - ownership boundaries are locked in CONTEXT.md and mapped to current evaluated code.
- Pitfalls: HIGH - most were reproduced locally; documentation-backed Nix behavior is MEDIUM under the provider confidence seam.
- Sawnia permissions: LOW - no current record or history defines the intended policy.

**Research date:** 2026-07-25
**Valid until:** 2026-08-24 for the stable refactor guidance; re-check pinned revisions if `flake.lock` changes.
