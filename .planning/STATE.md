---
gsd_state_version: 1.0
milestone: v1.3
milestone_name: ZFS Mirror + Nixflix Migration - Phases 12-16 (in progress)
current_phase: 12
current_phase_name: fleet-repair
status: executing
stopped_at: Completed 12-03-PLAN.md
last_updated: "2026-08-24T01:33:01.701Z"
last_activity: 2026-08-23
last_activity_desc: v1.3 ROADMAP.md created (Phases 12-16, 25/25 requirements mapped)
progress:
  total_phases: 5
  completed_phases: 0
  total_plans: 5
  completed_plans: 3
  percent: 0
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-08-23)

**Core value:** The homelab runs reliably without manual intervention -- when something needs attention, I know about it before it becomes a problem.
**Current focus:** Phase 12 — fleet-repair

## Current Position

Phase: 12 (fleet-repair) — EXECUTING
Plan: 4 of 5
Status: Ready to execute
Last activity: 2026-08-23 — Phase 12 execution started

Progress: [██████░░░░] 60%

## Performance Metrics

**Velocity:**

- Total plans completed: 41 (23 through v1.1 + 18 v1.2)
- v1.2 execution: 18 plans, 52 tasks, 2026-08-16 → 2026-08-22

**By Phase (v1.2):**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 9. Channel Bump to NixOS 26.05 | 7 | ~6.7h | ~57 min |
| 10. Household Foundation and Mealie | 5 | ~2h + 3 sessions | ~25 min |
| 11. Homebox, Actual Budget, Donetick | 6 | ~3.4h | ~34 min |

Pre-v1.2 metrics are archived in `.planning/milestones/`.
**Per-Plan Metrics:**

| Plan | Duration | Tasks | Files |
|------|----------|-------|-------|
| Phase 12 P01 | 35min | 2 tasks | 3 files |
| Phase 12 P02 | 55min | 2 tasks | 3 files |
| Phase 12 P03 | 40min | 3 tasks | 30 files |

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
- [Phase 12]: Deferred a 1,443-file/3.27 TiB uid-38 ownership finding (correlated with FLEET-02 sabnzbd 38:194 drift) rather than mass-chown it; flagged for plan 12-02 or a future plan.
- [Phase 12]: sabnzbd 38:194 drift root cause: unpinned uid auto-allocation reassigned across unrelated declarative user/group changes (recurred twice on ser8); pinned uid=985 in modules/media/sabnzbd.nix, gid inherited from already-pinned media group (1100)
- [Phase 12]: sabnzbd host_whitelist/local_ranges fixed live (API + ini edit) to unblock the tsnet gateway route; not Nix-declared pending the separately-deferred configFile->settings migration; tracked in WINDOWS.md
- [Phase ?]: [Phase 12]: NordVPN + qBittorrent stack deleted from repo (modules, host wiring, orchestration, monitoring, smoketests); flake.nix's own ./modules/nordvpn module-list entry was the dangling eval-critical reference the plan missed, fixed as a blocking-issue auto-fix

### Pending Todos

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

Last session: 2026-08-24T01:33:01.694Z
Stopped at: Completed 12-03-PLAN.md
Resume file: None

## Operator Next Steps

- Run `/gsd-plan-phase 12` to plan the Fleet Repair phase.
