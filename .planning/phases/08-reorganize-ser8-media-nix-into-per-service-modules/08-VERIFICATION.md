---
phase: 08-reorganize-ser8-media-nix-into-per-service-modules
verified: 2026-07-25T23:10:12Z
status: gaps_found
score: 18/20 must-haves verified
behavior_unverified: 0
overrides_applied: 2
overrides:
  - must_have: "make check passes and make build-ser8 evaluates the ser8 system to the same store path as before the refactor, proving a pure behavior-preserving move"
    reason: "The user approved the Sawnia Jellyfin identity addition and D-14 helper split, both of which intentionally change the system path; the accepted contract is normalized evaluated parity with those exact deltas."
    accepted_by: "user"
    accepted_at: "2026-07-25T23:10:12Z"
  - must_have: "make check and make build-ser8 pass with zero repository-owned warnings and no live activation"
    reason: "The user explicitly accepted the exact Home Manager mismatch and the enumerated pre-existing repository-wide make check warning classes; both commands exited successfully and no activation command ran."
    accepted_by: "user"
    accepted_at: "2026-07-25T23:10:12Z"
gaps:
  - truth: "The pre-refactor ser8 media behavior is captured without plaintext secret values."
    status: partial
    reason: "The fixture is non-secret and broad, but the projection reads config.services.qbittorrent instead of the active config.services.qbittorrent-nox contract, so it does not capture or protect qBittorrent enablement, port, firewall, or VPN namespace settings."
    artifacts:
      - path: "scripts/validation/ser8-media-projection.nix"
        issue: "Lines 155-165 project the inactive services.qbittorrent option set."
      - path: "scripts/validation/check-ser8-media-parity.sh"
        issue: "Lines 144-155 accept a default.nix with only one expected import, so the structural proof does not close the missing-projection risk."
    missing:
      - "Project services.qbittorrent-nox enable, user, group, port, openFirewall, and useVpnNamespace."
      - "Migrate or regenerate the baseline with an explicitly reviewed qBittorrent expected delta."
      - "Make structure reject the legacy aggregate and require every exact service, SOPS, and orchestration import."
  - truth: "Repository-owned evaluation warnings block the refactor instead of being hidden or changed out of scope."
    status: failed
    reason: "run-clean ignores arbitrary non-empty stderr unless it contains a small keyword allowlist; the verifier reproduced a successful exit for an unclassified repository diagnostic."
    artifacts:
      - path: "scripts/validation/check-ser8-media-parity.sh"
        issue: "validate_stderr at lines 101-113 checks only warning/error/fatal/trace text and the Home Manager block."
    missing:
      - "Fail on every non-empty stderr line not present in the exact approved baseline."
      - "Add a negative test proving a keyword-free repository diagnostic is rejected."
---

# Phase 8: Reorganize ser8 media.nix into per-service modules Verification Report

**Phase Goal:** `hosts/ser8/media.nix` is decomposed into focused per-service files under `hosts/ser8/media/`, each owning its own SOPS secrets, templates, and systemd units, so a service's full configuration is discoverable in one place and adding a user or service is a self-contained change, with no unintended change to the running system.

**Verified:** 2026-07-25T23:10:12Z

**Status:** gaps_found

**Re-verification:** No, initial verification.

## Goal Achievement

### Observable Truths

Roadmap criteria are retained as the contract and plan truths that directly restate them are deduplicated.
The two approved user decisions are recorded as explicit overrides rather than silently weakening the roadmap.

| # | Truth | Status | Evidence |
|---|---|---|---|
| 1 | The legacy aggregate is gone and ser8 imports an import-only media directory entry point. | VERIFIED | `hosts/ser8/media.nix` is absent; `hosts/ser8/configuration.nix:14` imports `./media`; `hosts/ser8/media/default.nix:6-15` contains only nine imports. |
| 2 | All seven active services have focused host files owning their host policy, secrets or shared-secret references, templates where applicable, proxy policy, and deployment contributions. | VERIFIED | Direct inspection of `jellyfin.nix`, `sonarr.nix`, `radarr.nix`, `prowlarr.nix`, `nzbget.nix`, `sabnzbd.nix`, and `qbittorrent.nix`; all are imported by `default.nix`. |
| 3 | Jellyfin household users live in host policy while reusable Jellyfin modules remain generic. | VERIFIED | `hosts/ser8/media/jellyfin.nix:43-103` owns enablement, users, secrets, API key, and exporter inputs; `modules/media/jellyfin.nix` contains only account/network/firewall policy. |
| 4 | Cross-service registration, target wiring, and startup relationships are isolated in orchestration. | VERIFIED | `hosts/ser8/media/orchestration.nix:43-210` owns `media-config`, `servarrs-setup`, `download-clients-setup`, and `media-setup.target`; service files contribute ordered deployment fragments. |
| 5 | Repository checks pass and the accepted expected-delta contract replaces literal store-path equality. | PASSED (override) | Current path is `/nix/store/pv3zjmhpialypmb5clclkvy0mav0mhjg-nixos-system-ser8-25.11.20260518.687f05a`, versus baseline `/nix/store/kd4diqnrwwrfapkv0hp9imizcy8b6f6x-nixos-system-ser8-25.11.20260518.687f05a`; the user approved Sawnia and D-14 helper deltas, and normalized parity passes. |
| 6 | The pre-refactor media behavior is captured without plaintext secret values. | FAILED | Secret schema contains only owner/group/mode/path, but `ser8-media-projection.nix:155-165` captures inactive `services.qbittorrent`, not `services.qbittorrent-nox`. |
| 7 | Repository-owned evaluation warnings block the refactor. | FAILED | `run-clean bash -c 'echo repository-diagnostic >&2'` returned 0, reproducing the fail-open classifier defect at `check-ser8-media-parity.sh:101-113`. |
| 8 | ser8 entered the media directory through a behavior-neutral extraction seam. | VERIFIED | Final import wiring evaluates; normalized parity passes; direct current qBittorrent evaluation matches pre-phase source values. |
| 9 | Each Arr service owns and enables its matching Exportarr instance. | VERIFIED | `sonarr.nix:50-56`, `radarr.nix:50-56`, and `prowlarr.nix:53-59`; the old grouped Exportarr module is absent. |
| 10 | Arr secrets, templates, deployment order, and evaluated runtime configuration remain unchanged. | VERIFIED | Projection comparison passes for Arr services, templates, exporters, accounts, unit dependencies, and generated scripts; orders 200, 300, and 400 are present. |
| 11 | Shared Usenet and administrator credential names remain unchanged. | VERIFIED | `nzbget.nix` references `sabnzbd_admin_password` and `sabnzbd_usenet_*`; `sabnzbd.nix:11-48` remains the single declaration owner. |
| 12 | qBittorrent remains VPN-namespaced and uses the same nginx proxy and atomic deployment. | VERIFIED | Current evaluation reports enable=true, port=8080, openFirewall=false, useVpnNamespace=true; source comparison with `1485835^` confirms proxy, WebUI, chmod, and atomic move markers are unchanged. |
| 13 | ser8 owns both Jellyfin and declarative Jellyfin enablement. | VERIFIED | `hosts/ser8/media/jellyfin.nix:43-51`; both evaluate true through the passing delta assertion. |
| 14 | Sawnia matches Jordan's non-admin policy with her own password path. | VERIFIED | `jellyfin.nix:62-76`; `assert_expected_deltas` compares complete evaluated records after removing only `hashedPasswordFile`. |
| 15 | Shared SOPS defaults are isolated while active secrets remain service-owned. | VERIFIED | `sops.nix` contains only file, format, and age key defaults; direct scans locate active declarations in owning service modules. |
| 16 | Deployment and orchestration helpers are split without changing the accepted command and sanitization contract. | VERIFIED | `deployment-helpers.sh` has only `configure_arr`; `orchestration-helpers.sh` contains API readiness, registration, and sanitization functions; ShellCheck and shfmt pass. |
| 17 | Dead Exportarr, AllDebrid, and Transmission implementations are absent. | VERIFIED | All three module files are absent and no active import/source references remain in `modules/media`. |
| 18 | Approved AllDebrid persistence state and stale flake comments are removed. | VERIFIED | No `alldebrid` match remains in `hosts/ser8/impermanence.nix` or `flake.nix`. |
| 19 | Every remaining reusable media provider has an independently checked audit outcome. | VERIFIED | All nine current `modules/media/*.nix` files were read; eight providers are substantive and wired through `modules/media/default.nix`; no dead provider import remains. |
| 20 | `make check` and `make build-ser8` completed under the accepted warning policy without activation. | PASSED (override) | User-provided execution context records `make check` exit 0, focused build success, accepted warning classes, and no activation; verifier independently evaluated the current toplevel and reran focused static/parity checks. |

**Score:** 18/20 truths verified, including 2 explicit user-approved overrides.

### Required Artifacts

| Artifact group | Expected | Status | Details |
|---|---|---|---|
| Seven host service modules | Complete service-owned host policy | VERIFIED | All exist, are substantive, imported, and evaluate. |
| `hosts/ser8/media/default.nix` | Imports-only entry point | VERIFIED | Exact source has only the module argument and nine imports. |
| `hosts/ser8/media/sops.nix` | Shared defaults only | VERIFIED | No individual secret or template declaration. |
| `hosts/ser8/media/orchestration.nix` | Stable shared units and target | VERIFIED | All four systemd interfaces and helper sources are present. |
| Split shell helpers | Deployment versus orchestration responsibilities | VERIFIED | Both are substantive, sourced, strict-mode files and pass linters. |
| `scripts/validation/ser8-media-projection.nix` | Complete non-secret behavior projection | STUB | Broad and substantive, but omits the active qBittorrent option contract by selecting the wrong module. |
| `scripts/validation/check-ser8-media-parity.sh` | Fail-closed parity and structure CLI | PARTIAL | Capture/check work, but two negative reproductions show fail-open warning and structure checks. |
| Baseline JSON and store path | Durable non-secret before state | PARTIAL | Files are valid and non-secret; qBittorrent service coverage is incomplete. |
| Reusable media modules | Active generic providers only | VERIFIED | Import-only default plus eight active providers; obsolete modules are absent. |

### Key Link Verification

| From | To | Via | Status | Details |
|---|---|---|---|---|
| `hosts/ser8/configuration.nix` | `hosts/ser8/media/default.nix` | `./media` import | WIRED | Exact import at line 14 and successful Nix evaluation. |
| Host service modules | `systemd.services.media-config` | ordered `before` and `script` contributions | WIRED | Orders 200 through 700 are present and merge with orchestration orders 100 and 800. |
| `orchestration.nix` | split helpers | Nix path sources | WIRED | Deployment helper is sourced by `media-config`; orchestration helper is sourced by both setup services. |
| `jellyfin.nix` | generic Jellyfin exporter | typed `apiKeyFile` option | WIRED | Host passes the SOPS runtime path; reusable module consumes it through `LoadCredential`. |
| `nzbget.nix` | `sabnzbd.nix` | shared SOPS placeholders | WIRED | NZBGet consumes the exact declarations owned once by SABnzbd. |
| qBittorrent nginx | NordVPN namespace bridge | `config.nordvpn.vethBridge.vpnIp` | WIRED | Proxy target uses the evaluated VPN bridge address and qBittorrent remains namespace-enabled. |
| parity runner | behavior projection | `nix eval --apply` | PARTIAL | Connected and runnable, but the projection contract is incomplete. |

### Data-Flow Trace (Level 4)

This phase contains declarative configuration rather than UI-rendered dynamic data.
The relevant flow was traced from host modules to evaluated NixOS options, SOPS runtime paths, generated systemd scripts, and nginx proxy settings.
No hollow props or static fallback data pattern applies.

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|---|---|---|---|
| Focused Nix formatting | `nixfmt --check` on host media, reusable media, and touched host/flake files | No output, exit 0 | PASS |
| Focused Nix static analysis | `statix check` once per media directory | No findings, exit 0 | PASS |
| Shell quality | `shellcheck` and `shfmt -d` on both helpers and parity runner | No output, exit 0 | PASS |
| Normalized evaluated parity | `env -u HOME check-ser8-media-parity.sh check 08-ser8-media-before.json` | Exit 0 | PASS, with coverage gap noted |
| Current qBittorrent contract | Direct `nix eval` of `services.qbittorrent-nox` | true/qbittorrent/qbittorrent/8080/false/true | PASS |
| Keyword-free stderr rejection | `run-clean bash -c 'echo repository-diagnostic >&2'` | Incorrectly returned 0 | FAIL |
| Missing-import rejection | Temporarily test `structure` against an entry point retaining only `sops.nix`, then restore the file | Incorrectly returned 0 | FAIL |
| Current toplevel evaluation | `env -u HOME nix eval --raw ...system.build.toplevel` | `/nix/store/pv3z...-nixos-system-ser8...` | PASS |

### Probe Execution

SKIPPED.
No Phase 8 plan declares a probe and no conventional `scripts/**/tests/probe-*.sh` exists.

### Requirements Coverage

Phase 8 has no formal requirement ID in `REQUIREMENTS.md`.
All roadmap criteria and merged plan must-haves are covered in the observable-truth table.
No orphaned Phase 8 requirement exists.

### Anti-Patterns and Review Findings

No `TBD`, `FIXME`, or `XXX` debt marker exists in the phase implementation files.
SOPS placeholder matches are intentional runtime secret wiring, not stubs.

| Finding | Classification | Effect on Phase 8 verification |
|---|---|---|
| qBittorrent CSRF and host-header defenses disabled | BLOCKER security debt | Pre-existing configuration was preserved, so it does not prove a refactor regression; it remains a ship-blocking security issue outside the decomposition goal. |
| Jellyfin API key passed in exporter argv | BLOCKER security debt | Pre-existing exporter behavior remains wired; genericization did not introduce it, but it must be resolved before a security gate can pass. |
| Rebuild SSH host verification disabled | BLOCKER operational security debt | Outside the running media configuration goal, but present in a phase-touched helper and unresolved. |
| Hardware refresh can truncate its destination | BLOCKER operational safety debt | Outside the media decomposition goal, but present in a phase-touched helper and unresolved. |
| Prowlarr form auth omits declared admin credentials | BLOCKER pre-existing correctness debt | The phase preserved the original template, so parity holds; the service's existing fresh-state login contract remains defective. |
| Two Servarr compact-JSON idempotence checks fail | WARNING reliability debt | Preserved helper behavior, not a refactor delta. |
| qBittorrent password JSON is not escaped | WARNING reliability/security debt | Preserved helper behavior, not a refactor delta. |
| Parity projects the wrong qBittorrent module | BLOCKER phase gap | Directly invalidates the baseline coverage must-have. |
| Structural gate accepts incomplete imports | BLOCKER phase gap | Directly invalidates the claimed structural guard. |
| `run-clean` accepts arbitrary stderr | BLOCKER phase gap | Directly invalidates the fail-closed warning must-have. |

Security enforcement is active, but no `08-SECURITY.md` exists.
This is workflow debt distinct from the two goal-verification gaps, and the critical review findings mean a security completion claim cannot currently be made.

### Human Verification Required

None for this verifier status.
The Home Manager and repository-wide warning decisions were explicitly resolved by the user, and D-18 explicitly excludes live activation from Phase 8 acceptance.

### Gaps Summary

The module decomposition itself is real and satisfies the ownership goal.
The phase is blocked by its proof layer rather than by missing service files: the behavior baseline omits active qBittorrent options, the structural check does not require the complete import set, and warning classification is fail-open for keyword-free stderr.
These concerns are not addressed by later milestone Phases 5, 6, or 7, whose goals cover monitoring and logging rather than Phase 8 validation tooling.

---

_Verified: 2026-07-25T23:10:12Z_

_Verifier: the agent (gsd-verifier)_
