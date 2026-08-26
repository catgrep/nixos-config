---
phase: 12-fleet-repair
plan: 02
subsystem: media
tags: [nixos, sabnzbd, uid-drift, identity, tailscale, caddy]

# Dependency graph
requires:
  - phase: 12-fleet-repair
    provides: "Plan 12-01's identity census/correction (media = uid 1100/gid 1100, corrected D-07/D-08) and its deferred uid-38 ownership finding, which this plan resolves for the sabnzbd portion"
provides:
  - "sabnzbd.service active on ser8 with a statically-pinned uid (985), immune to future auto-allocation drift"
  - "Diagnosis evidence explaining the uid-38/gid-194 drift mechanism, reusable for the still-deferred /mnt/media uid-38 finding (1,443 files / ~3.27 TiB, per 12-01's ownership-audit.md)"
  - "firebat https_sabnzbd tsnet route returns a healthy 200 (via /login/ redirect)"
affects: [13-zfs-mirror-migration, 15-nixflix-migration]

# Actuals (#2632)
actuals:
  tokens: 3155
  tasks: 2
  commits: 2

tech-stack:
  added: []
  patterns:
    - "Static uid pin on a NixOS system user (users.users.<name>.uid) to prevent declarative-allocator drift, without needing an explicit gid field since gid rides on the already-pinned group (users.groups.<name>.gid)"

key-files:
  created:
    - .planning/phases/12-fleet-repair/evidence/sabnzbd-diagnosis.md
  modified:
    - modules/media/sabnzbd.nix

key-decisions:
  - "Pinned uid = 985 (live-confirmed) rather than the plan's stale 'gid = 992' instruction; media's real gid is 1100 (already pinned fleet-wide in modules/common/users.nix), and users.users.<name> has no gid option in NixOS at all"
  - "Live one-time fixes (not Nix-declared) for sabnzbd's host_whitelist and local_ranges, required to make the tsnet gateway route pass, deliberately kept out of the deferred configFile->settings Nix migration scope"

patterns-established:
  - "When pinning a NixOS system user's identity, verify whether the group's gid is already pinned via a shared groups.<name> declaration before adding a uid+gid pair — users.users.<name> only supports uid + a group name string, not a numeric gid"

requirements-completed: [FLEET-02]

coverage:
  - id: D1
    description: "Diagnosed the sabnzbd 38:194 ownership drift and confirmed the mechanism (unpinned uid auto-allocation reassigned across unrelated declarative user/group changes, observed recurring twice on ser8)"
    requirement: FLEET-02
    verification:
      - kind: manual_procedural
        ref: ".planning/phases/12-fleet-repair/evidence/sabnzbd-diagnosis.md"
        status: pass
    human_judgment: false
  - id: D2
    description: "Pinned sabnzbd's uid in modules/media/sabnzbd.nix, chowned /var/lib/sabnzbd to the correct identity, and confirmed sabnzbd.service active + firebat https_sabnzbd route healthy"
    requirement: FLEET-02
    verification:
      - kind: other
        ref: "ssh bdhill@192.168.68.65 'systemctl is-active sabnzbd' -> active"
        status: pass
      - kind: other
        ref: "curl -sS -L -o /dev/null -w '%{http_code}' https://sabnzbd.shad-bangus.ts.net -> 200 (via /login/ redirect)"
        status: pass
    human_judgment: false

duration: ~55min
completed: 2026-08-24
status: complete
---

# Phase 12 Plan 2: SABnzbd Ownership Drift Diagnosis and Repair Summary

**Diagnosed and fixed a recurring NixOS uid-auto-allocation drift for sabnzbd (uid pinned to 985), one-time chowned its state tree back to a working identity, and unblocked the firebat tsnet gateway route which was silently rejecting Tailscale's CGNAT client IPs.**

## Performance

- **Duration:** ~55 min
- **Started:** 2026-08-23 (session start)
- **Completed:** 2026-08-24T01:17:00Z
- **Tasks:** 2
- **Files modified:** 2 (1 created, 1 modified) in repo; 1 live-only ini edit on ser8 (no repo artifact)

## Accomplishments

- Confirmed the root cause of the 38:194 ownership drift: sabnzbd's uid was never pinned in Nix, so NixOS's declarative id-allocation pool (`/var/lib/nixos/uid-map`) reassigned it whenever the fleet's declared user/group set changed elsewhere — demonstrated to have happened at least twice on ser8 (the 26.05 channel bump, and again during this very phase's 12-01 switch, at the exact second `sabnzbd.service` last failed)
- Pinned `users.users.sabnzbd.uid = 985` in `modules/media/sabnzbd.nix`, the live-confirmed collision-free identity; gid needs no separate field because `services.sabnzbd.group` is already forced to `"media"`, whose gid (1100) is already pinned fleet-wide in `modules/common/users.nix`
- One-time scoped `chown -R 985:1100 /var/lib/sabnzbd` on ser8, resolving the stale `admin/`, `backup/`, `logs/`, and `sabnzbd.ini.bak` ownership without touching `hosts/ser8/impermanence.nix` (no standing re-chown tmpfiles rule added, per D-12)
- `sabnzbd.service` is active on ser8; found and fixed a second, previously-unknown blocker on the firebat `https_sabnzbd` tsnet route (SABnzbd was rejecting Caddy's forwarded Tailscale client IPs as "External internet access denied" because Python's `ipaddress.is_private()` does not recognize the Tailscale CGNAT range) — the route now returns a healthy `200` via its `/login/` redirect

## Task Commits

Each task was committed atomically:

1. **Task 1: Diagnose the sabnzbd 38:194 ownership drift (D-11, gates Task 2)** - `e97996b` (docs)
2. **Task 2: Repair — scoped chown, static uid/gid pin, deploy, and verify (D-12/D-13)** - `bac4c33` (fix)

**Plan metadata:** (this commit)

## Files Created/Modified

- `.planning/phases/12-fleet-repair/evidence/sabnzbd-diagnosis.md` - Full diagnosis: root cause, raw command output, generation/activation timeline correlation, and target uid/gid values for the repair
- `modules/media/sabnzbd.nix` - Added `uid = 985;` to `users.users.sabnzbd`, with an inline comment explaining why no `gid` field is added (and why one would be invalid)

## Decisions Made

- **uid 985, no gid field** — the plan's Task 2 text instructed `gid = 992;` inside `users.users.sabnzbd`, citing "the media group's target gid per D-07/plan 12-01." Both parts of that instruction were wrong: (1) `users.users.<name>` has no `gid` option in NixOS at all — verified directly against `nixos/modules/config/users-groups.nix`; only `uid` and `group` (a name string) exist there, and (2) even if it did, 992 is the live `mealie` group's gid (confirmed via `/var/lib/nixos/gid-map` and `getent group mealie`), not media's — media's real gid is 1100 per 12-01's own corrected D-07/D-08 finding. Since `services.sabnzbd.group` is already forced to `"media"` and `modules/common/users.nix` already pins `groups.media.gid = 1100`, sabnzbd's gid was already statically pinned by inheritance; only `uid` needed adding.
- **Live, non-declarative fix for host_whitelist/local_ranges** — SABnzbd's own DNS-rebinding and IP-allowlist protections were blocking the tsnet route independently of the uid/gid work. Fixed live (API call for `host_whitelist`, direct ini edit while stopped for the API-protected `local_ranges`) rather than migrating to `services.sabnzbd.settings` in Nix, because that migration (`services.sabnzbd.configFile` is deprecated in 26.05) is an existing, separately-scoped deferred item — folding it into this plan would have expanded scope beyond FLEET-02's uid/gid repair. Recorded in `.planning/WINDOWS.md` (entry 11) so it isn't lost before that migration lands.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Plan's Task 2 instruction to set `gid = 992` on `users.users.sabnzbd` was factually and structurally wrong**
- **Found during:** Task 2
- **Issue:** The plan text said to add `gid = 992;` alongside `uid` in the `users.users.sabnzbd` block. `users.users.<name>` has no `gid` option in NixOS — confirmed against the actual module source (`nixos/modules/config/users-groups.nix`) — so this would have been a hard eval error, not a no-op. Separately, 992 is the live `mealie` service group's gid (confirmed via `/var/lib/nixos/gid-map` and `getent group mealie`), not media's — a stale reference from before 12-01's D-07/D-08 correction, which found media's real gid is 1100.
- **Fix:** Added only `uid = 985;` (the live-confirmed, collision-free identity). Gid is already statically pinned via `modules/common/users.nix`'s `groups.media.gid = 1100`, inherited through sabnzbd's forced `"media"` group membership — no additional field needed.
- **Files modified:** `modules/media/sabnzbd.nix`
- **Verification:** `make dry-activate-ser8` and `make test-ser8` both evaluated cleanly with the corrected pin; `getent passwd sabnzbd` on ser8 confirms `985:1100`.
- **Committed in:** `bac4c33`

**2. [Rule 2 - Missing critical functionality] SABnzbd's own access-control config was blocking the tsnet gateway route, independent of the uid/gid repair**
- **Found during:** Task 2's final verification step
- **Issue:** After the uid pin and chown, `sabnzbd.service` was active but `curl https://sabnzbd.shad-bangus.ts.net` returned `403 External internet access denied`. Root cause (confirmed via journal + source read of `sabnzbd/interface.py`/`misc.py`): SABnzbd's `check_access()` rejects requests whose `X-Forwarded-For` IP isn't recognized as local, and Python's `ipaddress.ip_address(...).is_private` does not include the Tailscale CGNAT range (`100.64.0.0/10`, RFC 6598) — so every tsnet client was rejected as "external," regardless of the identity fix.
- **Fix:** Added `sabnzbd.shad-bangus.ts.net` to `host_whitelist` via SABnzbd's own API (works live). Added `100.64.0.0/10` (plus the standard RFC1918 ranges, to avoid narrowing existing LAN access) to `local_ranges` — this key is `protect=True` in SABnzbd's config and cannot be set via the API, so it required stopping the service, editing `/var/lib/sabnzbd/sabnzbd.ini` directly, and restarting.
- **Files modified:** None in repo — live-only sabnzbd.ini state on ser8; recorded in `.planning/WINDOWS.md` (entry 11) since it is not declaratively captured and depends on the still-deferred `configFile`→`settings` migration to become durable in Nix.
- **Verification:** `curl -sS -L -o /dev/null -w '%{http_code}' https://sabnzbd.shad-bangus.ts.net` returns `200` (via its `/login/` redirect).
- **Committed in:** N/A (live-only fix, no repo diff)

---

**Total deviations:** 2 auto-fixed (1 Rule 1, 1 Rule 2)
**Impact on plan:** Both were necessary to satisfy this plan's own must_haves.truths (unit active AND gateway route healthy) and threat-register mitigation (T-12-05 collision check). No scope creep beyond what D-13 already required to be verified.

## Issues Encountered

- `journalctl -u sabnzbd`, `_PID=<pid>`, and a full-journal `--grep=sabnzbd` all showed zero lines for the process's own crash, despite `StandardOutput=journal`/`StandardError=journal` — the process dies too early (474ms) for its buffered Python stdout to flush before exit. Root cause was instead established from file ownership/mtime evidence and `/var/lib/nixos/{uid,gid}-map` correlation with system generation activation timestamps, not from application logs. This is the same "known-blind" pattern already flagged for the SABnzbd smoketest (D-13 explicitly leaves that smoketest unfixed).
- `make switch-ser8` prompts interactively by default (`nixos_confirm`); ran with `NO_CONFIRM=true` per this repo's documented non-interactive deploy path (CLAUDE.md), since this was an intentional, plan-directed switch.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- FLEET-02 is fully resolved: sabnzbd.service active, firebat gateway route healthy, static identity pin in place, no standing re-chown mechanism added.
- The diagnosis in `evidence/sabnzbd-diagnosis.md` directly informs 12-01's still-deferred uid-38 finding (1,443 files / ~3.27 TiB under `/mnt/media`, same 38:194 pattern) — the mechanism is now understood (unpinned auto-allocation drift, not a one-off historical accident), which should make scoping that follow-up decision easier, though the media-tree portion itself remains untouched per 12-01's explicit scope boundary.
- The live-only host_whitelist/local_ranges fix is recorded in `.planning/WINDOWS.md` (entry 11) and depends on the deferred `services.sabnzbd.configFile`→`settings` migration to become Nix-declared and durable across a full state rebuild.

---
*Phase: 12-fleet-repair*
*Completed: 2026-08-24*

## Self-Check: PASSED

- FOUND: `modules/media/sabnzbd.nix`
- FOUND: `.planning/phases/12-fleet-repair/evidence/sabnzbd-diagnosis.md`
- FOUND: `.planning/phases/12-fleet-repair/12-02-SUMMARY.md`
- FOUND commit: `e97996b` (Task 1 diagnosis)
- FOUND commit: `bac4c33` (Task 2 repair)
- FOUND commit: `ec1203b` (this summary)
