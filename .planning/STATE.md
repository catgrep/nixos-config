---
gsd_state_version: 1.0
milestone: v1.2
milestone_name: Household Stack
status: Awaiting next milestone
stopped_at: Completed 11-06-PLAN.md (real ser8 reboot proved Homebox/Actual/Donetick persistence; household suite 8/8 post-reboot; pre-existing NordVPN gap logged, not fixed)
last_updated: "2026-08-23T21:56:10.899Z"
last_activity: 2026-08-23
last_activity_desc: Milestone v1.2 completed and archived
progress:
  total_phases: 3
  completed_phases: 1
  total_plans: 23
  completed_plans: 18
  percent: 33
current_phase: 11
current_phase_name: homebox-actual-budget-and-donetick
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-08-17)

**Core value:** The homelab runs reliably without manual intervention -- when something needs attention, I know about it before it becomes a problem.
**Current focus:** Phase 11 — homebox-actual-budget-and-donetick

## Current Position

Phase: Milestone v1.2 complete
Plan: —
Status: Awaiting next milestone
Last activity: 2026-08-23 — Milestone v1.2 completed and archived

## Performance Metrics

**Velocity:**

- Total plans completed: 23 (6 v1.0 + 12 v1.1)
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
| 11 | 6 | - | - |

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
| Phase 09 P04 | ~50 min | 4 tasks | 15 files |
| Phase 09 P05 | ~1h | 5 tasks | 12 files |
| Phase 09 P07 | ~2h15m | 3 tasks | 8 files |
| Phase 10 P01 | 9 min | 3 tasks | 11 files |
| Phase 10 P03 | 8 min | 3 tasks | 5 files |
| Phase 10 P04 | 35min | 2 tasks | 6 files |
| Phase 10 P05 | 55min | 3 tasks | 13 files |
| Phase 10 P06 | 3 sessions | 3 tasks | 6 files |
| Phase 11 P01 | 55min | 3 tasks | 11 files |
| Phase 11 P02 | 25min | 2 tasks | 7 files |
| Phase 11 P03 | 20min | 2 tasks | 3 files |
| Phase 11 P04 | ~65min (2 sessions) | 2 tasks | 12 files |
| Phase 11 P05 | ~24min | 3 tasks | 5 files |
| Phase 11 P06 | 16min | 1 tasks | 2 files |

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
- [Phase ?]: [Phase 09]: Delete overlays/frigate-tflite-optional.nix — a real build proved its guard aborts, because nixpkgs 26.05 applies its own ai-edge-litert.patch that rewrites the tensorflow.lite import the overlay grepped for. Keep the PYTHONPATH tensorflow filter in frigate.nix: tensorflow is still in Frigate's closure.
- [Phase ?]: [Phase 09]: Delete the SABnzbd package-version overlay — it had inverted (pinned 5.0.3, stable now ships 5.0.4) and stable's derivation is byte-for-byte identical, including the sabctools 9.4.0 override and par2cmdline-turbo on the wrapper PATH.
- [Phase ?]: [Phase 09]: Force UMask 0002 on radarr and sonarr — 26.05's servarr module sets 0022 itself, which conflicts and would strip the shared media group's write bit.
- [Phase ?]: [Phase 09]: Remove the declarative lovelace-resources workaround entirely — 26.05 selects resource_mode: yaml automatically when custom lovelace modules are present and lists advanced-camera-card.js?7.27.4 in the generated configuration.yaml, while the declarative storage copy had gone stale at 7.6.5. Deleting the Nix rule is not enough: /var/lib/hass is persisted through /persist, so the file was backed up on ser8 to /persist/backups/09-05/ and deleted explicitly.
- [Phase ?]: [Phase 09]: The Frigate live-stream 403 is PRE-EXISTING, not bump-caused — go2rtc rejects the cross-origin WebSocket upgrade Home Assistant's frigate proxy forwards, with identical 403s in ser8's journal on 2026-08-14, three days before the first 26.05 activation. The remedy (go2rtc api.origin) is verified but deliberately NOT applied: it trades away a CSRF protection and belongs in its own plan against modules/automation/frigate.nix.
- [Phase ?]: [Phase 09]: ser8's post-switch smoketest result is identical to the temporary-activation runs, and that equality is the pass condition, not a staleness signal — proven fresh by diffing the transcripts, which differ only in the live frigate/stats MQTT payload size (55101 vs 55112 bytes).
- [Phase ?]: [Phase 09]: The Grafana secret_key pin from 09-01 is CONFIRMED CORRECT by evidence, not inference — a real test notification sent from the reversibly-activated firebat arrived at catgrep@sudomail.com before 'make switch-firebat' ran. Zero 'failed to decrypt'/'invalid key' entries and zero notify failures since the 26.05 activation. No SOPS re-provisioning was needed.
- [Phase ?]: [Phase 09]: Back up a live SQLite database with sqlite3 '.backup', never cp/rsync. firebat's grafana.db was captured this way to /var/backups/09-07/ and copied to ser8:/mnt/backups/firebat/grafana/ (sha256 8243ea3e..., PRAGMA integrity_check ok on the durable copy). firebat is ext4 with no snapshot mechanism, so ser8's backup pool is the only durable target in the fleet.
- [Phase ?]: [Phase 09]: firebat is SWITCHED to 26.05 (generation 73 is the boot default; generation 72 remains a selectable 25.11 entry). NEITHER x86 host was rebooted in this phase — both are activated and selected as boot default only, so no early-boot or bootloader path has been exercised.
- [Phase ?]: [Phase 09]: The 09-07 Home Manager warning-baseline backstop did NOT fire — plan 09-04 had already replaced the stale Phase 08 entry, and STATE.md carries exactly one entry on that baseline.
- [Phase 10]: Mealie runs as a static mealie system user with DynamicUser forced off (PD-01), so state lands at a real persisted /var/lib/mealie the Phase 11 backup job can address
- [Phase 10]: services.postgresql.package pinned to postgresql_17 by plain assignment, not mkDefault — ser8's stateVersion 24.11 would otherwise have silently selected major 16
- [Phase 10]: Every services.mealie.settings value written as a Nix string: the module stringifies with toString, and toString false is the empty string, which would silently reopen registration
- [Phase 10]: modules/household/postgresql.nix deliberately not created (PD-02) — the version pin is host policy and an empty reusable module is worse than none
- [Phase 10]: Household smoketests assert both Mealie state stores (Postgres rows AND the persisted image tree); a row-count-only check is green while every thumbnail is broken
- [Phase 10]: Seeded-data and persistence assertions are on by default; MEALIE_ALLOW_UNSEEDED=1 is a command-line-only escape hatch for the single pre-bootstrap run in plan 10-04 and is set by no committed file
- [Phase 10]: Mealie table names (ingredient_foods, ingredient_units, recipes) are resolved through to_regclass before querying, so an unconfirmed RESEARCH.md A3 guess reports a named failure rather than a psql error
- [Phase 10]: Plan 10-04 checkpoint resolved 'proceed': both one-way thresholds crossed on ser8 (PostgreSQL 17 initdb, Mealie 3.22.0 Alembic migrations). Boot default is now generation 269; recovery path is generation 268.
- [Phase 10]: RESEARCH.md Assumption A3 confirmed against the live Mealie 3.22.0 schema: ingredient_foods, ingredient_units, recipes all resolve. PostgreSQL is 17.11, matching CONTEXT.md D-08 rather than RESEARCH.md's 17.7 'correction'.
- [Phase 10]: make switch-ser8 was run despite the household area exiting 1: the three remaining endpoint failures are owned by plans 10-05 (tsnet) and 10-06 (default admin credentials), and the tests were left failing rather than relaxed.
- [Phase ?]: Phase 10: RESEARCH.md Pitfall 8 corrected — Mealie 3.22.0 shopping_lists carries no household_id column; household is an association proxy through the creator's user_id, and there is no per-user ownership filter on reads
- [Phase ?]: Phase 10: Mealie 3.22.0 auto-creates no shopping list on bootstrap — the empty-input edge is zero lists, not one empty list
- [Phase ?]: Phase 10: RESEARCH.md Open Question 4 answered — administrator-created accounts work with ALLOW_SIGNUP=false; inferred from the database and request log, not operator-attested. Phase 12 Homebox inherits with that caveat
- [Phase ?]: Phase 10: the mealie_recipe_images_present gate was not weakened to close plan 10-06; it is red because the fact it asserts is false
- [Phase ?]: [Phase 11] Homebox needs no sops secret at all -- HBOX_AUTH_API_KEY_PEPPER is not a real 0.25.0 config variable (verified against pinned source); the plan's phantom secret wiring was dropped
- [Phase ?]: [Phase 11] nixpkgs 26.05's homebox module now defaults HBOX_OPTIONS_ALLOW_REGISTRATION to closed via mkDefault (opposite of the app's own default and opposite of the plan's assumption); must be set explicitly open during bootstrap, then closed after
- [Phase 11]: ACT-02 kept Pending in REQUIREMENTS.md after 11-02 -- only the server-password half is done; budget-file creation (11-03) completes it
- [Phase ?]: [Phase 11]: journalctl --invocation=0 scopes no-startup-error smoketests to a unit's current start rather than -b, avoiding false failures from earlier activations within the same uptime
- [Phase 11]: Donetick's UI is NOT in the donetick/donetick backend repo -- it lives in a separate donetick/frontend Vite/npm repository; the backend's own frontend/dist is committed only as an 88-byte placeholder. Packaged both from source (buildGoModule + buildNpmPackage, this repo's first Go and first npm packages), pinning frontend/frontend to the exact commit the real v0.1.79 release build used (traced via the GitHub API against the release workflow's run timestamp)
- [Phase 11]: donetick/frontend's committed package-lock.json is missing resolved/integrity for 909/1382 packages (npm/cli#6301) and is never used as-is by upstream's own build either; vendored a regenerated, fully-resolved lockfile into packages/donetick/ instead
- [Phase 11]: buildGoModule's checkPhase silently scopes go test to subPackages when that attribute is set -- donetick's checkPhase was overridden to run the real, unscoped go test ./... (all 14 internal/*_test.go files), matching upstream's own CI
- [Phase 11]: StateDirectoryMode forced to 0750 for Donetick from the start (proactively applying the 11-01/Homebox lesson that systemd's real default is 0755, not 0750) -- pattern now applies to Mealie(DATA_DIR via Postgres), Homebox, and Donetick; Actual's upstream module already hardcodes 0700
- [Phase 11]: The dev machine's Nix remote-builder config for x86_64-linux is broken (root SSH known_hosts mismatch + macOS Native Linux Builder auth failure); worked around per the 09-04 note's suggested pattern (nix copy --derivation + ssh nix-store --realise as bdhill, not root) to iterate on Donetick's package hashes. make switch-ser8 itself is unaffected (buildOnTarget: true builds on ser8 directly over SSH)
- [Phase 11]: nix eval --json against environment.persistence."/persist".directories fails repo-wide (pre-existing, unrelated to any specific service) on a dead `method` suboption the pinned impermanence input removed upstream; use `nix eval --json --apply` plucking only `.directory` per entry instead. Logged in 11-04's deferred-items.md
- [Phase ?]: [Phase 11]: Donetick is live at https://donetick.shad-bangus.ts.net, jordan and sawnia share one circle, public signup closed. sops.templates.<name>.restartUnits must be set explicitly for any template whose content can change post-deploy -- sops-install-secrets only restarts a unit on a raw content diff for units named in restartUnits at diff time, silently leaving the running process on stale env vars otherwise (discovered live: DT_IS_USER_CREATION_DISABLED flipped to true on disk but signup stayed open until a manual restart).
- [Phase ?]: [Phase 11]: A real ser8 reboot proves Homebox group, Actual's single budget file, and Donetick circle membership are bit-for-bit identical pre/post; the household smoketest suite is 8/8 post-reboot. The literal make reboot-test-ser8 exits 0 criterion stays unmet only because of the pre-existing, already-documented NordVPN suite failure (predates Phase 9), logged to deferred-items.md, not fixed.

### Pending Todos

- Convert gateway, media, DNS, and NordVPN smoketest behavior into NixOS Python integration tests.
- Retain deployment scripts only for checks that require live hardware or external services.
- Request the Google Takeout Tasks export during Phase 10 (long-lead, hours-to-days; Phase 13 depends on it).
- Migrate `.vofi` hostnames to the public `vofi.dev` domain with real TLS (`.planning/todos/pending/2026-08-17-migrate-vofi-hostnames-to-public-vofi-dev-domain.md`).

### Blockers/Concerns

- `nixos-26.05` x pinned `nixos-raspberrypi` interaction is untested (LOW confidence) — resolve inside Phase 9 with `make dry-activate-pi4`
- RESOLVED 2026-08-22: Donetick packaging approach decided and implemented in 11-04 -- local `buildGoModule` (backend) + `buildNpmPackage` (frontend, a separate upstream repo, not an OCI container extraction). See 11-04-SUMMARY.md.
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
- 09-04: RESEARCH.md Pitfall 5 is falsified — it claimed the Frigate overlay's guard lines were present at 26.05's version; a real build proved they are not. Treat that pitfall as superseded.
- 09-04: x86 remote builds from the dev machine need a workaround — the nix daemon cannot ssh to ser8 (root known_hosts, needs sudo) and the local Native Linux Builder returns 'Authentication token is invalid'. Use 'nix copy --derivation' + 'ssh nix-store --realise'. Fix before 09-07.
- 09-05: ser8 is SWITCHED to 26.05 (generation 268 is the boot default) but has NOT been rebooted. TWO PROOFS ARE OUTSTANDING and belong to 09-07 or phase verification: (1) IMPERMANENCE — the marker /IMPERMANENCE-MARKER-09-05 is planted on rpool/local/root and confirmed still present; it MUST NOT survive the first 26.05 boot, or the stage-1 systemd rollback migrated in 09-01 did not fire and impermanence is silently broken. (2) ZFS SKEW — userland is zfs-2.4.3-1 against zfs-kmod-2.3.7-1 from the booted 25.11 kernel, so zfs scrub is rejected; the failed unit state was reset by the switch but the skew is unchanged and zfs-scrub.timer next fires 2026-08-24. Recovery if the reboot goes badly: select generation 267 in the systemd-boot menu (confirmed present in bootctl list). 'make rollback-HOST' prints TODO and is NOT a recovery path.
- 09-05: the switch updated systemd-boot on ser8's ESP from 258.7 to 260.2, so the EFI boot manager binary is already 26.05's while the booted kernel is still 25.11's. Normal for a switch and both generations' BLS entries remain valid, but it is a bootloader-level change made with no reboot to confirm it.
- 09-05: ser8 media UID/GID drift is a year-old pre-existing issue, NOT bump-caused — activation warns it will not apply group media 992->1100 and user media 1002->1100 (declared in modules/common/users.nix since 2025-08-18). Refusing the renumber is the protective behaviour; applying it would orphan every file under /mnt/media. Needs its own plan with a deliberate re-chown.
- 09-07 PHASE-EXIT OUTSTANDING (4 items, block plan completion, all must be visible to phase verification): (1) ser8 first-26.05-boot proofs — /IMPERMANENCE-MARKER-09-05 must NOT survive the first 26.05 boot, and the zfs userland 2.4.3-1 vs kmod 2.3.7-1 skew clears only on reboot (zfs-scrub.timer next fires 2026-08-24); ser8 is NOT rebooted. (2) User must run 'sudo make update-nix-conf' locally and confirm 'grep -c cachix /etc/nix/nix.custom.conf' outputs 0 — threat T-09-06 stays open until then. (3) go2rtc origin 403 on Frigate live streams is pre-existing (identical 403s on 2026-08-14) and deliberately deferred; the api.origin remedy trades away a CSRF protection and is a user decision. (4) pi5's deploy.yaml entry (192.168.0.110, targetUser nixos) is stale and must be corrected before any plan tries to reach that board.
- Plan 10-02 (IMP-01 Google Takeout artifact) has no SUMMARY yet; STATE plan counter reads 3 while plan 03 is complete and 02 is outstanding
- Mealie is LAN-reachable on ser8 0.0.0.0:9000 with the shipped default administrator credentials still authenticating (HTTP 200 from the workstation). ALLOW_SIGNUP=false limits it to that one account. Plan 10-06 closes this and should run promptly.
- sabnzbd.service and download-clients-setup.service fail on ser8 (uid drift 38:194 under /var/lib/sabnzbd/admin). Pre-existing since the generation 268 boot, not caused by Phase 10; makes make test-ser8 and make switch-ser8 return exit 4.
- RESOLVED 2026-08-18: firebat caddy.service outage (shared Tailscale auth key rejected, `invalid key: API key does not exist`). The key was rotated to a reusable non-ephemeral one and committed as `11e0fda`; firebat is switched to generation 74, caddy is active with zero error-priority journal entries, and all thirteen tsnet nodes including `mealie` registered. Outage window 2026-08-18 ~12:05 to 12:52 PDT, latent for the preceding 64 days. Full record: `.planning/phases/10-household-foundation-and-mealie/baseline/incident-firebat-caddy-authkey-2026-08-18.md`.
- 10-05: the shared `tailscale_authkey` has now gone bad three times and takes the ENTIRE gateway down when it does, because a long-lived Caddy masks the dead key until something restarts it. Phases 12 and 13 each add three more tsnet nodes and must treat a valid reusable non-ephemeral key as an explicit PRECONDITION, verified by restarting Caddy on purpose. Consider disabling key expiry on the long-lived service nodes in the Tailscale admin console.
- 10-05: RESEARCH assumption A5 splits in two. TRUE — a new tsnet node needs no ACL edit and no console approval; `mealie` claimed its name unaided. FALSE — the shared key could not be assumed valid just because eleven nodes already used it, and that is the half that caused the outage.
- 10-05: the `mealie` tsnet node is runtime Tailscale state, NOT repository state. Reverting this phase or rolling firebat back will not remove it; it must be deleted by hand in the Tailscale admin console or the name stays claimed.
- 10-05: the gateway suite's eight `tls_*` subtests assert NOTHING — `openssl` is absent from firebat, so each one skips and is then counted as a pass. No certificate chain is inspected by the suite on any node. Logged to deferred-items.md.
- 10-05 CARRIED TO 10-06: the base URL is correct in the deployed unit environment and the endpoint answers there, but no link COMPOSED by the application has been asserted against it. Mealie's three composers (invitation, password reset, shared recipe) all need authentication or seeded data. Not proven via the shipped default administrator on purpose. Close it in 10-06 with a real share link from a real account.
- MEAL-04 half-open: the shared shopping list is proven bidirectionally at the API layer (Mealie's own page_all returns both lists to both members), but the end-user two-profile UI rendering confirmation was deferred by the operator. Remaining probe documented in 10-06-SUMMARY.md — loopback curl as vodh, service-worker unregister, two-profile retest. MEAL-04 left Pending.
- Plan 10-07 has no persistence subject: the only Mealie recipe is named 'test' with a null image and /persist/var/lib/mealie/recipes holds zero files. mealie_recipe_images_present is known-red. A real recipe with an uploaded image must exist before 10-07's two-reboot drill is meaningful.
- Both Mealie accounts carry admin=true. Unplanned privilege, recorded not changed in plan 10-06. Resolve before Phase 14 SEC-02 audits privilege.
- 11-06: make reboot-test-ser8 does not exit 0 post-reboot -- only failing area is nordvpn (2/4), confirmed pre-existing and already documented in this same Blockers list before Phase 9 (tunnel down, test-forwarding.sh queries retired pi4 resolver 192.168.68.56). All Phase 11 acceptance criteria (Homebox/Actual/Donetick pre/post snapshot equality, household suite 8/8) are met; a human should confirm this known, unrelated gap is acceptable before treating ROADMAP.md Success Criterion 3 as fully closed. See .planning/phases/11-homebox-actual-budget-and-donetick/baseline/reboot-2026-08-22.md.

### Roadmap Evolution

- v1.2 phases 9-14 added: channel bump, household foundation + Mealie, backup engine, TLS + Homebox + Actual, Donetick + import, access control + verification
- v1.1 phases 5-7 shelved to Future Requirements; phase artifacts archived under `.planning/milestones/v1.1-phases/`

## Deferred Items

Items acknowledged and deferred at milestone v1.2 close on 2026-08-23 (override closeout).
The raw audit counted 49 open lines; deduplicated below to distinct issues.
Full text lives in each phase's `deferred-items.md` (archived under `milestones/v1.2-phases/`).

| Category | Item | Status |
|----------|------|--------|
| verification | Phase 09 verification `gaps_found` (pi4/pi5 never remotely dry-activated; workstation cachix trust; always-pass smoketests) | acknowledged |
| todo | migrate-vofi-hostnames-to-public-vofi-dev-domain (gateway) | pending |
| operational | ser8 NordVPN tunnel down; qBittorrent has no internet path; sole cause of `make reboot-test-ser8` exit 1 | deferred |
| operational | sabnzbd.service fails (uid-drifted 38:194 files under /var/lib/sabnzbd/admin); causes gateway https_sabnzbd 502 | deferred |
| operational | media user/group UID/GID drift on ser8 (declared 1100, live 1002/992); needs deliberate re-chown plan | deferred |
| operational | pi4 and pi5 offline; pi5 deploy.yaml entry (192.168.0.110, user nixos) stale | deferred |
| operational | Workstation /etc/nix/nix.custom.conf still trusts nixos-raspberrypi.cachix.org (needs `sudo make update-nix-conf`) | deferred |
| smoketest | deploy.yaml pi4/pi5 smoketests are the literal `test` builtin — always pass | deferred |
| smoketest | test-caddy.sh passes with zero routes extracted | deferred |
| smoketest | test-home-assistant.sh treats SSH failure as "no errors" | deferred |
| smoketest | media SABnzbd check passes while unit is dead | deferred |
| smoketest | gateway tls_* subtests skip (no openssl on firebat) but count as passes | deferred |
| smoketest | nordvpn/test-forwarding.sh hard-codes retired pi4 resolver 192.168.68.56 | deferred |
| app | Frigate live-stream 403 (go2rtc api.origin; CSRF tradeoff is an operator decision) | deferred |
| app | Frigate 0.16.3 → 0.17.2 bump unverified (recordings/detection/retention) | deferred |
| app | services.sabnzbd.configFile deprecated in 26.05; migration to `settings` needs its own plan | deferred |
| app | pinned impermanence input's dead `method` option breaks bare `nix eval --json` dumps of persistence dirs | deferred |

## Session Continuity

Last session: 2026-08-22T07:59:33.246Z
Stopped at: Completed 11-06-PLAN.md (real ser8 reboot proved Homebox/Actual/Donetick persistence; household suite 8/8 post-reboot; pre-existing NordVPN gap logged, not fixed)
Resume file: None

## Operator Next Steps

- Start the next milestone with /gsd-new-milestone
