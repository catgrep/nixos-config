---
gsd_state_version: 1.0
milestone: v1.3
milestone_name: ZFS Mirror + Nixflix Migration - Phases 12-16 (in progress)
current_phase: 14
current_phase_name: backup-engine
status: verifying
stopped_at: Completed 14-06-PLAN.md
last_updated: "2026-08-29T19:15:12.894Z"
last_activity: 2026-08-27
last_activity_desc: Phase 14 execution started
state_head: 3fde311e2843aed32ab0cffa3690bd1d371b370c
progress:
  total_phases: 5
  completed_phases: 2
  total_plans: 18
  completed_plans: 18
  percent: 40
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-08-23)

**Core value:** The homelab runs reliably without manual intervention -- when something needs attention, I know about it before it becomes a problem.
**Current focus:** Phase 14 — backup-engine

## Current Position

Phase: 14 (backup-engine) — EXECUTING
Plan: 6 of 6
Status: Phase complete — ready for verification
Last activity: 2026-08-27 — Phase 14 execution started

Progress: [████░░░░░░] 40%

## Performance Metrics

**Velocity:**

- Total plans completed: 30 (23 through v1.1 + 18 v1.2)
- v1.2 execution: 18 plans, 52 tasks, 2026-08-16 → 2026-08-22

**By Phase (v1.2):**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 9. Channel Bump to NixOS 26.05 | 7 | ~6.7h | ~57 min |
| 10. Household Foundation and Mealie | 5 | ~2h + 3 sessions | ~25 min |
| 11. Homebox, Actual Budget, Donetick | 6 | ~3.4h | ~34 min |
| 12 | 5 | - | - |
| 13 | 7 | - | - |

Pre-v1.2 metrics are archived in `.planning/milestones/`.
**Per-Plan Metrics:**

| Plan | Duration | Tasks | Files |
|------|----------|-------|-------|
| Phase 12 P01 | 35min | 2 tasks | 3 files |
| Phase 12 P02 | 55min | 2 tasks | 3 files |
| Phase 12 P03 | 40min | 3 tasks | 30 files |
| Phase 12 P04 | ~17min (2 checkpoints) | 3 tasks | 2 files |
| Phase 12 P05 | ~15min | 3 tasks | 4 files |
| Phase 13 P01 | 25min | 4 tasks | 5 files |
| Phase 13 P02 | ~20min | 3 tasks | 5 files |
| Phase 13 P03 | ~10h47m (~45min active) | 4 tasks | 1 files |
| Phase 13 P04 | ~18min | 2 tasks | 4 files |
| Phase 13 P05 | ~1h20m | 7 tasks | 0 files |
| Phase 13 P06 | ~18h25m (~1h45m active) | 5 tasks | 4 files |
| Phase 13 P07 | ~8h25m (~50min active, ~7h42m scrub) | 5 tasks | 9 files |
| Phase 14 P01 | ~3h | 3 tasks | 12 files |
| Phase 14 P02 | ~4h | 2 tasks | 11 files |
| Phase 14 P03 | ~5h | 3 tasks | 7 files |
| Phase 14 P04 | ~2h | 3 tasks | 13 files |
| Phase 14 P05 | ~6h (5h20m downtime) | 4 tasks | 5 files |
| Phase 14 P06 | ~8h | 4 tasks | 13 files |

## Accumulated Context

### Decisions

Full log: PROJECT.md Key Decisions table.
Historical per-phase decisions live in the archived phase summaries under `.planning/milestones/v1.2-phases/` (and earlier milestone archives).

Still-operative decisions for future work:

- [Phase 09]: nixos-hardware pinned at ff17823245ab; mainline kernel forced on both Pis (vendor kernel has no cache build); Pi bootstrap images deferred with the technical path recorded in PROJECT.md
- [Phase 09]: Back up live SQLite with `sqlite3 '.backup'`, never cp/rsync; ser8's backup pool is the fleet's only durable target (firebat is ext4, no snapshots)
- [Phase 10]: Household service shape — reusable module + host-policy slice, static user with DynamicUser off, StateDirectoryMode 0750, tsnet vhost, smoketests asserting unit + endpoint + both state stores
- [Phase 10]: `services.mealie.settings` values must be Nix strings (`toString false` is "" and would silently reopen registration)
- [Phase 11]: `sops.templates.<name>.restartUnits` must be set explicitly for any template whose content can change post-deploy
- [Phase 11]: Dev machine x86 remote-builder is broken; iterate package hashes via `nix copy --derivation` + `ssh nix-store --realise`; `make switch-ser8` unaffected (buildOnTarget)
- [Phase 12]: Abandoned uid 1002/gid 992 media identity adoption: live ser8 already matches repo (1100/1100); gid 992 belongs to mealie. Corrected PROJECT.md D-07/D-08.
- [Phase 12]: Deferred a 1,443-file/3.27 TiB uid-38 ownership finding (correlated with FLEET-02 sabnzbd 38:194 drift) rather than mass-chown it. RESOLVED post-phase (2026-08-23): targeted `find -uid 38 -exec chown media:media` of 1,597 paths (files + dirs) plus 11 residual uid-1002/755 strays; media tree verified zero stray uid/gid; see evidence/ownership-audit.md follow-up section.
- [Phase 12]: sabnzbd 38:194 drift root cause: unpinned uid auto-allocation reassigned across unrelated declarative user/group changes (recurred twice on ser8); pinned uid=985 in modules/media/sabnzbd.nix, gid inherited from already-pinned media group (1100)
- [Phase 12]: sabnzbd host_whitelist/local_ranges fixed live (API + ini edit) to unblock the tsnet gateway route; not Nix-declared pending the separately-deferred configFile->settings migration; tracked in WINDOWS.md
- [Phase ?]: [Phase 12]: NordVPN + qBittorrent stack deleted from repo (modules, host wiring, orchestration, monitoring, smoketests); flake.nix's own ./modules/nordvpn module-list entry was the dangling eval-critical reference the plan missed, fixed as a blocking-issue auto-fix
- [Phase ?]: [Phase 12] FLEET-01: Task 3 deletion scope expanded (human-confirmed) to include /persist/var/lib/qbittorrent after a mount-unit fix unbound it from /var/lib/qbittorrent's persist backing
- [Phase ?]: [Phase 12] SOPS secrets editing (make sops-edit-ser8) cannot be performed by the executor in this sandboxed session (GPG/age keyring access blocked); requires human execution in an unsandboxed terminal, verified afterward via git diff without decrypting
- [Phase ?]: [Phase 12]: Radarr root-folder cleanup done via API (re-point vs Radarr-managed move per record); D-15 satisfied structurally since Radarr's root-folder DELETE has no deleteFiles option; qBittorrent download-client entries removed from Radarr/Sonarr, Prowlarr confirmed never had one (D-16)
- [Phase ?]: [Phase 13, Plan 01]: Migration doc reconciled to post-Phase-12 world across 10 targeted sections (D-01); Approval Contract/Safety Rules/Approved Disk Inventory preserved byte-identical
- [Phase ?]: [Phase 13, Plan 01]: Both approved 12 TB disks pass short SMART health test gate (D-04) - zero reallocated/pending/offline-uncorrectable, short self-test completed without error
- [Phase ?]: [Phase 13, Plan 01]: Live media usage ~2.06 TB lower than doc's 2026-08-13 snapshot (5.73TB vs 7.79TB), likely from Phase 12 qBittorrent/wgnord deletion; favorable for staging capacity margin
- [Phase ?]: [Phase 13, Plan 02]: zfs-media-mirror branch declares the media zpool mirror (disko/config), removes MergerFS, and ships a six-check smoketest (D-19/D-22 import-write test); validated by make build-ser8, zero live ser8 state changed
- [Phase ?]: [Phase 13, Plan 02]: Both checkpoint:decision tasks auto-approved per operator's explicit checkpoint policy (repo-only/build-only mutations); ZFS-02/ZFS-04 not marked complete since both describe live-state outcomes only reached after Plan 13-05's cutover
- [Phase ?]: [Phase 13, Plan 03]: All 18 freeze-set services stopped and zero writers confirmed under /mnt/media (D-02/D-03) -- the sole freeze window for the whole migration; total app downtime clock started here
- [Phase ?]: [Phase 13, Plan 03]: backup/media-staging created and verified within the D-17 capacity floor; single frozen rsync pass completed (7h43m, systemd-run detached unit) with exact structural match to source (3,478 files, 5,727,815,651,227 bytes both sides); ZFS-01 not yet marked complete pending Plan 13-04's checksum verification gate
- [Phase ?]: [Phase 13, Plan 04]: scripts/sampled-verify.sh implements D-07 sampling in 1-MiB-block-index space (not byte-offset-then-divide) so head/tail samples always land on a file's true first/last bytes regardless of size alignment -- fixed as a Rule 1 bug against the plan's literal dd formula
- [Phase ?]: [Phase 13, Plan 04]: Gate 3.3 PASS -- 3,478 files sampled, 0 differences between frozen /mnt/media and backup/media-staging on ser8, independently re-verified against the manifest file content (not systemctl exit status or a coordinator report alone); ZFS-01 fully satisfied across Plans 13-01/13-03/13-04
- [Phase ?]: [Phase 13, Plan 04]: Task 2's checkpoint auto-approved per operator checkpoint policy (read-only mutation class against ser8); dispatched as a detached systemd-run unit (--setenv=PATH fix required, systemd-run's default env excludes /run/current-system/sw/bin) and tracked via .planning/async-jobs/gate-3.3-sampled-verify.json rather than polled, per the >10min async-dispatch threshold
- [Phase ?]: [Phase 13, Plan 05]: Destructive cutover executed with a mandatory human checkpoint for every disk-mutating step (unmount, erase, mirror create, activate) per operator policy, overriding this plan's own gate=blocking default; both approved WWNs (a81a/3a87) erased and repartitioned, empty two-disk media mirror created ONLINE with media/data mounted at /mnt/media, all 19 freeze-set units masked, ser8 activated as generation 282 (persistent boot default), zfs-media-mirror merged to main (PR #1, dec09b3)
- [Phase ?]: [Phase 13, Plan 05]: NixOS masking discovery -- systemctl mask (incl. --runtime) cannot override a store-backed unit on ser8 since /etc/systemd/system resolves into read-only /nix/store and outranks /run/systemd/system; masking now goes through /etc/systemd/system.control/ instead. Also found zfs-mount.service (unchanged oneshot) doesn't remount a brand-new dataset after a fresh pool import -- requires an explicit systemctl restart
- [Phase ?]: [Phase 13, Plan 05]: Operator decision for Plan 13-06 -- the live /etc/systemd/system.control/ masks do not survive a real reboot (impermanence wipes rpool/local/root); Plan 13-06's FIRST task must add a Nix-config-level declarative disable of the 19 freeze-set units (repo change + activation) before the ~10.7h restore starts, removed only at 13-06's documented service-start step. ZFS-02 marked complete; ZFS-05 remains open (staging deletion approval is still pending, spans through Plan 13-07)
- [Phase ?]: [Phase 13, Plan 06]: zfs send/recv restore executed with two Rule 1 fixes to the plan's literal command (send -s is --skip-missing not a resumability flag; recv needs -F onto the pre-existing empty media/data dataset). Restore independently verified byte-identical to the Plan 13-01 baseline (3,478 files, 5,727,815,651,227 bytes). All 19 freeze-set units restarted after clearing two independent mask layers (declarative Nix disable + leftover Plan 13-05 runtime masks). Full Step 5.4 validation passed (Jellyfin, Radarr/Sonarr, Samba, ZFS exporter). ZFS-04 marked complete; ZFS-03 remains open pending Plan 13-07's scrub.
- [Phase ?]: [Phase 13, Plan 06]: Two pre-existing, non-migration-caused findings surfaced during Step 5.4 and deferred (not fixed) per executor scope boundary: stale scripts/smoketests/media/all.sh downloads/complete path (predates Phase 12 torrent retirement), and a systemic ACL gap on ~280 tv/movies directories blocking Bazarr write access (base group:: entry is r-x not rwx, confirmed identical on backup/media-staging predating any ZFS work). Logged to deferred-items.md and WINDOWS.md (entries 13, 14).
- [Phase ?]: [Phase 13, Plan 06]: Mid-plan git policy correction from operator -- no pushes to origin during the phase at all (not even via PR); all commits local on main, origin updated once at phase completion after a history restructure. History was also rewritten mid-plan (component-scoped commits + docs squash); re-anchored via git log, no pre-rewrite SHA referenced.
- [Phase ?]: [Phase 13, Plan 07]: First media pool scrub PASS -- repaired 0B in 07:42:32 with 0 errors, both approved WWN mirror members ONLINE (independently re-verified, not trusted from any relayed report). ZFS-03 marked complete.
- [Phase ?]: [Phase 13, Plan 07]: Operator decision -- backup/media-staging's destroy is permanently out of this plan's/phase's automated scope; the operator will run it themselves after reviewing the scrub evidence. ZFS-05 stays Pending until then (intentional, not an oversight -- see 13-07-SUMMARY.md's ZFS-05 evaluation).
- [Phase ?]: [Phase 13, Plan 07]: MergerFS swept from CLAUDE.md/hosts/ser8/README.md/samba.nix; rpool/safe/downloads (500G quota) created imperatively matching its disko declaration (same pattern as Plan 13-05) and activated; SABnzbd/NZBGet migrated onto it. Found and fixed a Rule 1 bug: sops.templates for both services needed explicit restartUnits for media-config.service's cp-based config deploy to actually take effect.
- [Phase ?]: [Phase 13, Plan 07]: Post-completion self-check discovered the operator had already run zfs destroy -r backup/media-staging (zpool history: 2026-08-25 16:39:47 PDT), independently of and shortly after the scrub evidence became available -- corrected the just-written SUMMARY/evidence file (which had assumed staging still existed, matching the coordinator's earlier accurate-at-the-time report) rather than leaving stale claims in permanent docs. ZFS-05 marked complete; all five v1.3 Storage requirements (ZFS-01..05) now done. Phase 13 functionally complete.
- [Phase ?]: Replica dataset is not declared in disko: replication must create its own target or the first send is refused
- [Phase ?]: Receive-side mountpoint exclusion is latent insurance; send options carry no properties by default
- [Phase ?]: Ownership tmpfiles rules retargeted from /persist/var/lib/<svc> to /var/lib/<svc>, not deleted: only Jellyfin had both halves of the pair the plan assumed
- [Phase ?]: Layout test asserts each dataset property's source (local vs inherited), not just its value; an inherited value is right for the wrong reason
- [Phase ?]: x86_64-darwin dropped from devShells and packages: nixpkgs removed the platform after 26.05 and the key threw, breaking nix flake show and nix flake check
- [Phase 14]: A refused destroy is not fatal to the prune run: sanoid logs the held snapshot and exits 0, so a long-failing verification produces no prune-side signal
- [Phase 14]: A digest that cannot be delivered fails the verification run, which suppresses the metric stamp; the staleness alert travels over a different host so it is not circular
- [Phase 14]: Staleness alert absence arms are scoped to the expected instance so absent() synthesises a label the summary can name
- [Phase 14]: The replica smoketest asserts mountpoint=none rather than readonly or canmount, because nothing in the repository sets those
- [Phase 14]: The verification never-ran signal is read from the timer's last-trigger stamp, since a oneshot service defaults to Result=success
- [Phase 14]: 14-05: backup/persist-replica must never be pre-created; syncoid refuses an existing target without matching snapshots
- [Phase 14]: 14-05: Jellyfin activation tarballs (8.4 GB) deleted permanently; the first-send saving did not materialise because the pre-upgrade snapshot still carries them
- [Phase 14]: 14-05: on gated live-host plans, estimate the outage in approval round trips, not bytes moved (5h20m actual vs 30-50min estimate)
- [Phase 14]: Databases are identified by their file header, not by the .db filename
- [Phase 14]: A SQLite sidecar without the header is damage, not a foreign file
- [Phase 14]: The whole nightly cycle is anchored to UTC so both halves share one clock
- [Phase 14]: system.autoUpgrade removed from every host rather than repointed
- [Phase 14]: The fifteen pre-migration state directories were deleted

### Pending Todos

- Consolidate alerting onto the standalone Alertmanager: drop the Grafana-mirrored rules so Prometheus rules are evaluated once, keeping the ser8-local mail paths (`.planning/todos/pending/2026-08-29-consolidate-alerting-onto-standalone-alertmanager.md`).
- Convert gateway, media, DNS, and NordVPN smoketest behavior into NixOS Python integration tests.
- Retain deployment scripts only for checks that require live hardware or external services.
- Request the Google Takeout Tasks export before any import milestone (long-lead, hours-to-days).
- Migrate `.vofi` hostnames to the public `vofi.dev` domain with real TLS (`.planning/todos/pending/2026-08-17-migrate-vofi-hostnames-to-public-vofi-dev-domain.md`).

### Blockers/Concerns

Open items carried into the next milestone (resolved and phase-scoped entries pruned at v1.2 close; see git history for the full log):

- The shared `tailscale_authkey` has gone bad three times and takes the entire gateway down when it does; any plan adding tsnet nodes must verify the key by restarting Caddy on purpose. Consider disabling key expiry on the long-lived service nodes.
- tsnet nodes (mealie, homebox, actual, donetick, etc.) are runtime Tailscale state, not repository state — rolling back firebat does not remove them; delete by hand in the admin console.
- Homebox registration flag may not be safely re-enablable after being disabled — test on a scratch instance before any future account work.
- Google Takeout `Tasks.json` envelope is undocumented — inspect the real archive before writing any import code.
- Both Mealie accounts carry admin=true (unplanned privilege), and MEAL-04's two-profile UI confirmation remains operator-deferred — resolve both before a SEC-02-style audit.
- v1.1 leftovers: Alloy HCL config format unverified; firebat impermanence status unclear (both shelved with phases 5-7).
- v1.3 Phase 12 (Fleet Repair) now owns the NordVPN tunnel, sabnzbd uid drift, and media UID/GID drift items previously listed below as deferred; see Deferred Items for their FLEET-01..03 mapping.
- Workstation /nix is on a case-insensitive volume, so guest initrds cannot build locally; all VM tests build remotely on ser8
- 14-05: recvOptions readonly=on is rejected on receive (permission denied, 18 lines/run) because syncoid runs unprivileged; revert to 'u x mountpoint' or delegate the permission
- 14-05: make smoketests-ser8 has 3 failing suites; backup is expected (verify not yet run), media (279 bazarr-unwritable dirs) and household (homebox/donetick signup tests) are pre-existing and unrelated to the cutover

### Roadmap Evolution

- v1.2 phases 9-14 added: channel bump, household foundation + Mealie, backup engine, TLS + Homebox + Actual, Donetick + import, access control + verification
- v1.2 descoped 2026-08-20 to phases 9-11 (apps first); backups, TLS, import, and the access gate parked as Deferred
- v1.2 shipped 2026-08-23 (override closeout); archives under `.planning/milestones/v1.2-*`
- v1.1 phases 5-7 shelved to Future Requirements; phase artifacts archived under `.planning/milestones/v1.1-phases/`
- v1.3 phases 12-16 added 2026-08-23: fleet repair, ZFS mirror migration (human-gated), backup engine, Nixflix migration (arr/Prowlarr/Jellyfin), new services (Recyclarr/Seerr/Maintainerr) — 25/25 v1.3 requirements mapped, no orphans

## Deferred Items

Items acknowledged and deferred at milestone v1.2 close on 2026-08-23 (override closeout).
The raw audit counted 49 open lines; deduplicated below to distinct issues.
Full text lives in each phase's `deferred-items.md` (archived under `milestones/v1.2-phases/`).

| Category | Item | Status |
|----------|------|--------|
| verification | Phase 09 verification `gaps_found` (pi4/pi5 never remotely dry-activated; workstation cachix trust; always-pass smoketests) | acknowledged |
| todo | migrate-vofi-hostnames-to-public-vofi-dev-domain (gateway) | pending |
| operational | ser8 NordVPN tunnel down; qBittorrent has no internet path; sole cause of `make reboot-test-ser8` exit 1 | → FLEET-01, Phase 12 (v1.3) |
| operational | sabnzbd.service fails (uid-drifted 38:194 files under /var/lib/sabnzbd/admin); causes gateway https_sabnzbd 502 | → FLEET-02, Phase 12 (v1.3) |
| operational | media user/group UID/GID drift on ser8 (declared 1100, live 1002/992); needs deliberate re-chown plan | → FLEET-03, Phase 12 (v1.3) |
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

Radarr root-folder drift (FLEET-04) was recorded separately in `.planning/SER8-ZFS-MIRROR-MIGRATION.md` Known Blockers, not in this table; it is also scoped to Phase 12 (v1.3).

## Session Continuity

Last session: 2026-08-29T19:15:05.301Z
Stopped at: Completed 14-06-PLAN.md
Resume file: None

## Operator Next Steps

- Run `/gsd-plan-phase 12` to plan the Fleet Repair phase.
