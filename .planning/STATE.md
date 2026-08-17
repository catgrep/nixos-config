---
gsd_state_version: 1.0
milestone: v1.2
milestone_name: Household Stack
current_phase: 09
current_phase_name: channel-bump-to-nixos-26-05
status: executing
stopped_at: Completed 09-03-PLAN.md
last_updated: "2026-08-17T08:27:44.113Z"
last_activity: 2026-08-17
last_activity_desc: 09-02 complete — both Pi hosts migrated off the nvmd fork onto upstream nixpkgs + pinned nixos-hardware
progress:
  total_phases: 6
  completed_phases: 0
  total_plans: 7
  completed_plans: 4
  percent: 0
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-08-16)

**Core value:** The homelab runs reliably without manual intervention -- when something needs attention, I know about it before it becomes a problem.
**Current focus:** Phase 09 — channel-bump-to-nixos-26-05

## Current Position

Phase: 09 (channel-bump-to-nixos-26-05) — EXECUTING
Plan: 5 of 7
Status: Ready to execute
Last activity: 2026-08-17 — 09-02 finished all 3 tasks; Pi fork removed, cachix trust grant still installed

Progress: [██████░░░░] 57%

## Performance Metrics

**Velocity:**

- Total plans completed: 18 (6 v1.0 + 12 v1.1)
- Average duration: ~15 min
- Total execution time: ~4.1 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 1. Integration Foundation | 2 | ~35 min | ~18 min |
| 2. Push Notifications | 2 | ~32 min | ~16 min |
| 3. Camera Dashboard | 2 | ~40 min | ~20 min |
| 4. Alert Delivery & Service Probes | 2 | ~45 min | ~23 min |
| 5. Hardware Alerts & Status Dashboard | 2 | ~21 min | ~11 min |
| 8. Reorganize ser8 media.nix | 7 | ~59 min | ~8 min |

**Recent Trend:**

- Last 2 plans: Phase 08 P06 (3 min), Phase 08 P07 (12 min)
- Trend: Stable

*Updated after each plan completion*
**Per-Plan Metrics:**

| Plan | Duration | Tasks | Files |
|------|----------|-------|-------|
| Phase 09 P01 | ~45 min | 2 tasks | 17 files |
| Phase 09 P02 | ~25 min | 3 tasks | 14 files |
| Phase 09 P06 | 35m | 3 tasks | 13 files |
| Phase 09 P03 | ~50 min | 3 tasks | 8 files |

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- [v1.1]: Grafana Unified Alerting for metrics alerts (not standalone Alertmanager)
- [v1.1]: Gmail SMTP for email notifications (app password via SOPS)
- [v1.1]: Loki on firebat (NOT ser8 -- impermanence would lose data)
- [v1.1]: Alloy replaces Promtail (EOL Feb 28 2026)
- [v1.1]: Blackbox exporter on firebat, probes direct service ports (not Caddy proxies)
- [Phase 4]: Alert recipient is catgrep@sudomail.com (sender shadbangus@gmail.com)
- [Phase 4]: Blackbox probe targets use direct IPs, not .local mDNS (exporter can't resolve mDNS)
- [Phase 4]: Prometheus ruleFiles kept as defense-in-depth alongside Grafana-managed rules
- [Phase 5]: Grafana deleteRules needed to remove deprecated file-provisioned alert rules
- [Phase 5]: rate() over irate() for alert PromQL expressions (smoother signal, fewer false positives)
- [Phase 5]: msmtp as lightweight MTA on ser8 (not full Postfix); only zed needs email capability
- [Phase 5]: Grafana field overrides for friendly display names in state-timeline panels
- [Phase 09]: SUPERSEDES the Phase 08 accepted Home Manager mismatch baseline. As of 09-04 the home-manager input is on `release-26.05`, matching the nixpkgs channel at both the top level and in the `home-manager/` subflake, so the two-release gap that produced the release-mismatch warning no longer exists. That warning is GONE (`nix build --dry-run` on ser8 reports 0 matches for "you are using"), and it is no longer an accepted baseline: any release-mismatch warning appearing in evaluation output from now on is a finding to investigate, not a permitted condition. One new warning class replaced it — home-manager 26.05 renamed `programs.git.userName`/`userEmail`/`extraConfig` to `programs.git.settings.*` — and it was migrated away in the same commit rather than accepted, so the post-alignment warning count is zero for that class too. One unrelated warning remains outstanding and is NOT accepted: `nixfmt-rfc-style is now the same as pkgs.nixfmt`, introduced by the 09-01 nixpkgs bump.
- [Phase 08]: Normalize approved helper and generated unit-script store paths — compare evaluated media behavior while allowing only documented structural derivation changes.
- [Phase 08]: Keep each Arr service's enablement, secrets, template, exporter instance, and deployment contribution together in one host module. - This makes each service a complete discoverable host-policy slice.
- [Phase 08]: Preserve Arr deployment order with explicit priorities 200, 300, and 400 rather than import ordering. - Explicit priorities keep generated deployment behavior deterministic across module boundaries.
- [Phase 08]: Keep SABnzbd as the single declaration owner for shared administrator and Usenet credentials consumed by NZBGet. — Preserves existing credential names and avoids duplicate SOPS declarations.
- [Phase 08]: Use dependency priorities 450, 500, and 550 independently from deployment-script priorities 500, 600, and 700. — Preserves both evaluated unit ordering and deployment command ordering.
- [Phase 08]: Keep all Jellyfin household identities, credentials, API key wiring, and enablement decisions in the ser8 host module. - This keeps concrete household authorization and secret ownership out of reusable modules.
- [Phase 08]: Expose only enable and apiKeyFile as reusable Jellyfin exporter host inputs. - This is the minimum typed interface needed to preserve systemd credential delivery without host-specific references.
- [Phase 08]: Keep shared SOPS policy limited to file, format, and host age-key defaults while service modules own every active declaration. — This preserves one complete service owner for every secret and template.
- [Phase 08]: Preserve stable media unit interfaces and explicit script priorities while sourcing deployment and orchestration helpers separately. — This keeps dependency and execution behavior stable across the ownership split.
- [Phase 08]: Allow absent planned AllDebrid declarations only in the secret inventory projection while keeping all active contracts strict. — This verifies the approved cleanup without masking active configuration drift.
- [Phase 08]: Delete drained provider modules only after active-owner, caller-absence, and parity proof. - This prevents dead-code cleanup from removing behavior still consumed by ser8.
- [Phase 08]: Limit adjacent AllDebrid cleanup to the approved tmpfiles rule and stale flake comments. - This preserves every unrelated persistence path, flake input, and encrypted secret.
- [Phase 08]: Accept only the user-approved pre-existing warning classes for repository-wide make check while leaving the Phase 8 parity warning baseline exact and unchanged.
- [Subgen]: Run the pinned medium model on firebat with CPU int8 inference and one concurrent job.
- [Subgen]: Treat generated English subtitles as a batch fallback when synchronized human subtitles are unavailable.
- [Subgen]: Firebat measured a 0.630 median RTF and remained responsive with less than 4 GiB peak RSS.
- [Phase ?]: [Phase 09]: Migrate ser8's erase-your-darlings ZFS rollback to a boot.initrd.systemd stage-1 oneshot rather than pinning boot.initrd.systemd.enable = false — 26.05 asserts on postDeviceCommands under the new systemd-initrd default.
- [Phase ?]: [Phase 09]: CRITICAL for 09-05 — evaluation cannot prove the new ser8 initrd boots; impermanence rollback must be confirmed working after ser8's first reboot on 26.05 (marker file must not survive) before treating activation as successful.
- [Phase ?]: [Phase 09]: Migrate services.resolved to the structured settings.Resolve form; 26.05 removed extraConfig and renamed domains/dnssec/dnsovertls/fallbackDns. No dual-format shim.
- [Phase ?]: [Phase 09]: Commit unsigned (--no-gpg-sign) for this phase; GPG is unavailable in the sandboxed session. Hooks still run; --no-verify never used.
- [Phase ?]: [Phase 09]: Pin nixos-hardware to ff17823245ab (2026-08-16) rather than following master — raspberry-pi/common/ is under active development and a flake update must not silently change how the Pis boot.
- [Phase ?]: [Phase 09]: Keep the two kexec installerConfigurations entries and the nixos-images input; only the two fork-built sd-image entries were dropped. Pi bootstrap images are deferred (D-02).
- [Phase ?]: [Phase 09]: Declare options.homelab.raspberryPi.variant in modules/raspberrypi/base.nix with no default and set it per host, replacing the fork-only boot.loader.raspberryPi read. An unset variant must fail at eval, not produce an empty tag.
- [Phase ?]: [Phase 09]: Force boot.kernelPackages = pkgs.linuxPackages on both Pis to beat nixos-hardware's mkDefault vendor kernel, which has no Hydra cache build.
- [Phase ?]: [Phase 09]: Drop pi5's two serial-console UART settings entirely rather than porting them — upstream disables the mini UART under [pi5] on purpose (ghost input into boot).
- [Phase ?]: SKIP_VOFI_DNS defaults to 1 (skip pi4 lookup); Phase 10 sets it to 0 once .vofi ownership is re-established
- [Phase ?]: VPN kill-switch test moved to a manually-invoked disruptive suite rather than being deleted or run on every deploy
- [Phase ?]: Confinement check treats an unobtainable egress address as a failure, never a skip
- [Phase ?]: [Phase 09]: ZFS feature-flag check inverted: assert pools are NOT upgraded, so the previous generation can still import them. Plan 05 must not run 'zpool upgrade'.
- [Phase ?]: [Phase 09]: ser8 pre-bump smoketest baseline stored at .planning/phases/09-.../baseline/smoketests-ser8-2511.txt; plan 05 compares per-area, not top-level exit status.

### Pending Todos

- Convert gateway, media, DNS, and NordVPN smoketest behavior into NixOS Python integration tests.
- Retain deployment scripts only for checks that require live hardware or external services.
- Request the Google Takeout Tasks export during Phase 10 (long-lead, hours-to-days; Phase 13 depends on it).

### Blockers/Concerns

- `nixos-26.05` x pinned `nixos-raspberrypi` interaction is untested (LOW confidence) — resolve inside Phase 9 with `make dry-activate-pi4`
- Donetick packaging approach (local `buildGoModule` vs digest-pinned OCI container) must be decided before Phase 13 planning
- Homebox registration flag may not be safely re-enablable after being disabled — test on a scratch instance before Phase 12 bootstrap
- Google Takeout `Tasks.json` envelope is undocumented — inspect the real archive before writing any import code
- v1.1 leftovers: Alloy HCL config format unverified; firebat impermanence status unclear (both shelved with phases 5-7)
- 09-01: NEITHER x86 host has completed a remote activation preview, so the phase must_have "ser8 and firebat each receive a real remote activation preview" is UNMET and the channel bump is NOT validated by activation. ser8 blocked on jellyfin; firebat bounded only by an uncached multi-hour torch source build. Both carried to 09-04. Run 1 proved this matters: a caddy hash mismatch was invisible to `nix build --dry-run` and only surfaced under a real build.
- 09-01: firebat's `subgen` service pulls python3.12-torch 2.11.0, which has no binary-cache build at the pinned 26.05 rev and compiles from source (~hours on 16 cores). This cost is unavoidable for the real switch too — budget for it in 09-07.
- 09-01: grafana_secret_key was written to secrets/firebat.yaml by the user out of band; the executor could neither decrypt nor read secrets/. The `sops -d ... | grep -c` acceptance check is USER-ATTESTED ONLY and should be re-run by anyone re-validating the phase.
- 09-01: declarative-jellyfin locked at 3843ca5 supports Jellyfin <=10.11.8 but 26.05 ships 10.11.11; ser8 toplevel and make check stay red until 09-04 refreshes the input to c758527 or later.
- 09-01: pi4/pi5 cannot evaluate on 26.05 (systemd-resolved collision); D-12 stateVersion verification for both Pis deferred to 09-02. make check stays red until 09-02 lands.
- 09-02: The third-party cachix trusted key is STILL installed in /etc/nix/nix.custom.conf on the dev machine (threat T-09-06 open). Repo declarations are clean but 'make update-nix-conf' needs root and the sandboxed session has no sudo. User must run 'sudo make update-nix-conf' and confirm 'grep -c cachix /etc/nix/nix.custom.conf' outputs 0.
- 09-02: pi5 is unreachable at its deploy.yaml address 192.168.0.110 (SSH timeout; ser8 control SSH succeeded, so this is pi5-specific). pi5 is the only host on 192.168.0.0/24 and its targetUser is the installer default 'nixos' — the entry is very likely stale and needs correcting before any plan tries to reach that host.
- 09-02: make check still red — only remaining failure is ser8's declarative-jellyfin vs Jellyfin 10.11.11 (09-04 owns it). statix, all three validation scripts, and firebat/pi4/pi5 dry-run builds are green.
- ser8 NordVPN tunnel down (0-byte handshake, wgnord-monitor restart-looping qBittorrent); confinement check and nordvpn suite cannot be observed green until restored
- make smoketests-ser8 exits 1 pre-bump: NordVPN tunnel down (pre-existing) and nordvpn/test-forwarding.sh still queries the retired pi4 resolver 192.168.68.56

### Roadmap Evolution

- v1.2 phases 9-14 added: channel bump, household foundation + Mealie, backup engine, TLS + Homebox + Actual, Donetick + import, access control + verification
- v1.1 phases 5-7 shelved to Future Requirements; phase artifacts archived under `.planning/milestones/v1.1-phases/`

## Session Continuity

Last session: 2026-08-17T08:27:44.105Z
Stopped at: Completed 09-03-PLAN.md
Resume file: None
