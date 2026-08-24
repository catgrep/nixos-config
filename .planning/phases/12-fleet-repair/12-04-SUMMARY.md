---
phase: 12-fleet-repair
plan: 04
subsystem: media
tags: [nixos, nordvpn, qbittorrent, deployment, sops, secrets, zfs-archive, impermanence]

# Dependency graph
requires:
  - phase: 12-fleet-repair
    provides: "Plan 12-03's committed code removal (modules/nordvpn/, qbittorrent.nix, host wiring, all eval-critical consumers fixed; make dry-activate-ser8 and make check both green)"
provides:
  - "qbittorrent-nox.service and wgnord.service confirmed absent from ser8's running system, persisted as the boot default via make switch-ser8"
  - "Live qBittorrent state (config, BT_backup, session cache, logs — 46MB/15,033 files) and wgnord state (config/template/credentials) archived to /mnt/backups/phase12-fleet-repair-archive/ on ser8's ZFS backup pool before deletion"
  - "/var/lib/qbittorrent, /var/lib/wgnord, and /persist/var/lib/qbittorrent deleted from ser8 (exact paths, human-confirmed at checkpoint after discovering the persist backing path)"
  - "nordvpn_access_token, qbittorrent_admin_password, qbittorrent_admin_password_hash removed from secrets/ser8.yaml"
  - "FLEET-01 retirement decision recorded in PROJECT.md Key Decisions, adjacent to plan 12-01's FLEET-03 row"
affects: [13-zfs-mirror-migration, 14-backup-engine, 15-nixflix-migration]

# Actuals (#2632)
actuals:
  tokens: 1650
  tasks: 3
  commits: 1

tech-stack:
  added: []
  patterns:
    - "Impermanence bind-mounts (/var/lib/X <- /persist/var/lib/X) become two independent paths the moment the mount unit is stopped or its declaration is removed; a deletion plan written against the bind-mounted view (/var/lib/X) can silently miss the real backing data once that bind is gone — check for a live mount before trusting a single deletion/archive path"

key-files:
  created: []
  modified:
    - secrets/ser8.yaml
    - .planning/PROJECT.md

key-decisions:
  - "Task 3's deletion scope was expanded, with explicit human confirmation at the plan's checkpoint, to include the exact hardcoded path /persist/var/lib/qbittorrent in addition to the two paths the plan originally specified (/var/lib/qbittorrent, /var/lib/wgnord) — the persist backing path held the real 46MB/15,033-file qBittorrent state after Task 1's mount-unit fix unbound it from /var/lib/qbittorrent"
  - "SOPS secrets removal (make sops-edit-ser8) could not be performed by the executor in-session: gpg/sops decryption requires access to ~/.gnupg (workstation admin key) or ser8's root-only host SSH key, both blocked by this session's sandbox (macOS seatbelt via sagent blocks writes outside the project directory, including GPG lock files). The human ran make sops-edit-ser8 themselves in an unsandboxed terminal; the executor verified key removal via git diff (key names visible in plaintext in SOPS YAML; values remain ENC[...]) rather than decrypting, per the never-print-decrypted-values constraint"

requirements-completed: [FLEET-01]

coverage:
  - id: D1
    description: "Plan 12-03's code removal deployed to ser8 via make test-ser8 then make switch-ser8; qbittorrent-nox.service and wgnord.service confirmed absent (unit could not be found, not inactive/failed); edited media smoketest passes; removal persisted as boot default"
    requirement: FLEET-01
    verification:
      - kind: automated
        ref: "ssh ... systemctl status qbittorrent-nox.service | grep -qi 'could not be found' -> pass"
        status: pass
      - kind: automated
        ref: "./scripts/smoketests/media/all.sh ser8 -> exit 0, 6/6 services pass"
        status: pass
      - kind: automated
        ref: "journalctl --since '-5 minutes' | grep -ci wgnord -> 0 (after deploy noise rolled out of window; confirmed clean one-time Deactivated/Stopped messages, not restart-loop)"
        status: pass
    human_judgment: false
  - id: D2
    description: "Live /var/lib/qbittorrent and /var/lib/wgnord state archived to /mnt/backups/phase12-fleet-repair-archive/ on ser8's backup pool, verified non-empty and spot-checked, before any deletion"
    requirement: FLEET-01
    verification:
      - kind: automated
        ref: "tar tzf qbittorrent-*.tar.gz | wc -l -> 15033; tar tzf wgnord-*.tar.gz | wc -l -> 5; both test -s -> non-empty"
        status: pass
      - kind: manual_procedural
        ref: "Human confirmed archive contents at the plan's checkpoint:decision (proceed-with-persist-path)"
        status: pass
    human_judgment: true
    rationale: "Irreversible deletion of live qBittorrent session/history state requires human sign-off on archive completeness per D-03; this was the plan's built-in gate, not executor discretion"
  - id: D3
    description: "Archived state deleted from ser8 (/var/lib/qbittorrent, /var/lib/wgnord, /persist/var/lib/qbittorrent); orphaned SOPS secrets removed from secrets/ser8.yaml; PROJECT.md records the FLEET-01 retirement decision adjacent to the FLEET-03 row"
    requirement: FLEET-01
    verification:
      - kind: automated
        ref: "ssh ... test -d /var/lib/qbittorrent || test -d /var/lib/wgnord || test -d /persist/var/lib/qbittorrent -> REMOVED"
        status: pass
      - kind: manual_procedural
        ref: "git diff secrets/ser8.yaml confirms nordvpn_access_token, qbittorrent_admin_password, qbittorrent_admin_password_hash and their comment lines removed, ENC[...] values never decrypted"
        status: pass
    human_judgment: false

duration: ~17min agent-active time (plan also paused across two human checkpoints — an archive-confirmation decision and a SOPS-edit human-action gate — real elapsed time was longer)
completed: 2026-08-24
status: complete
---

# Phase 12 Plan 04: Deploy FLEET-01 Removal to ser8 Summary

**NordVPN + qBittorrent fully retired from ser8's live system: units deployed absent, state archived (46MB/15,033 files) then deleted from both the bind-mount view and its persist backing, orphaned secrets removed, and the decision recorded in PROJECT.md.**

## Performance

- **Duration:** ~17min agent-active (two human checkpoints paused the plan for longer real-world elapsed time)
- **Started:** 2026-08-24T01:35:14Z
- **Completed:** 2026-08-24T01:52:14Z
- **Tasks:** 3/3 completed
- **Files modified:** 2 (`secrets/ser8.yaml`, `.planning/PROJECT.md`)

## Accomplishments
- Deployed plan 12-03's code removal to ser8 via `make test-ser8` then `make switch-ser8`; `qbittorrent-nox.service` and `wgnord.service` both confirmed absent ("could not be found"), persisted as the boot default
- Archived the real live qBittorrent state (config, `BT_backup`, session cache, logs) and the wgnord state to `/mnt/backups/phase12-fleet-repair-archive/` on ser8's ZFS backup pool, both verified non-empty and spot-checked before any deletion
- Deleted the archived live state from ser8 — including a scope correction (human-confirmed) to also delete the persist backing path once a mount-unit side effect was discovered
- Removed the three orphaned SOPS secrets from `secrets/ser8.yaml` (human-executed due to a sandbox restriction; executor-verified without decryption)
- Recorded the FLEET-01 retirement decision in PROJECT.md Key Decisions

## Task Commits

Tasks 1 and 2 produced no repository file changes (pure live-deploy and live-archive operations on ser8) and therefore have no commit hash — see Deviations for the mechanical fixes applied during each.

1. **Task 1: Deploy the FLEET-01 removal to ser8** - no commit (live-only: `make test-ser8`, `make switch-ser8`, smoketest run)
2. **Task 2: Archive live qBittorrent/wgnord state** - no commit (live-only: `tar czf` to ser8's backup pool)
3. **Task 3: Delete archived live state, remove secrets, and record the PROJECT.md decision** - `b73ad14` (feat)

_No plan-metadata "docs: complete plan" commit issued separately in this response — see `<final_commit>` step below for that commit, made after this SUMMARY is written._

## Files Created/Modified
- `secrets/ser8.yaml` - Removed `nordvpn_access_token`, `qbittorrent_admin_password`, `qbittorrent_admin_password_hash` and their orphaned comment lines; all other secrets untouched and still encrypted
- `.planning/PROJECT.md` - Added the FLEET-01 retirement decision row to Key Decisions, adjacent to plan 12-01's FLEET-03 row

## Decisions Made
- Expanded Task 3's deletion scope, with explicit human confirmation at the plan's checkpoint, to include `/persist/var/lib/qbittorrent` (see Deviations — this was necessary because Task 1's mount-unit fix had already unbound `/var/lib/qbittorrent` from its persist backing, so the plan's literal two-path deletion would have been a no-op for the real data)
- Verified SOPS secret removal via `git diff` (plaintext key names visible in SOPS YAML structure) rather than `sops -d | grep`, since this session cannot decrypt `secrets/ser8.yaml` — equally rigorous (never touches decrypted values) and avoids depending on credential access this environment doesn't have

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking issue] `var-lib-qbittorrent.mount` failed to unmount during `make test-ser8`, causing exit code 4**
- **Found during:** Task 1
- **Issue:** `nixos-rebuild test` reported "Failed to stop var-lib-qbittorrent.mount" / "umount: target is busy", causing the overall `switch-to-configuration test` invocation to exit 4, even though `qbittorrent-nox.service` and `wgnord.service` were both already correctly removed from the systemd namespace
- **Fix:** Confirmed nothing held the mount open (race had resolved), ran `ssh bdhill@192.168.68.65 'sudo systemctl stop var-lib-qbittorrent.mount'`, which succeeded immediately and removed the unit
- **Files modified:** none (live ser8 state only)
- **Verification:** `systemctl status var-lib-qbittorrent.mount` → "could not be found"; `mount | grep qbittorrent` → no output
- **Committed in:** N/A (no repo files touched)
- **Side effect discovered and handled:** this fix unbound the impermanence bind-mount between `/persist/var/lib/qbittorrent` and `/var/lib/qbittorrent`, which directly caused Auto-fixed Issue #2 and the Task 3 scope decision below

**2. [Rule 1 - Bug] First qBittorrent archive attempt captured an empty directory instead of the real state**
- **Found during:** Task 2
- **Issue:** Running the plan's literal `tar czf ... -C /var/lib qbittorrent` produced a 121-byte, 1-entry tarball, because Issue #1's fix had already unbound `/var/lib/qbittorrent` from its persist backing, leaving it an empty local directory. The real ~198MB of qBittorrent state (config, `BT_backup`, session cache, logs — confirmed present via git history: `/var/lib/qbittorrent` was declared as an impermanence-persisted directory bound to `/persist/var/lib/qbittorrent`) was untouched but not being archived
- **Fix:** Re-ran the archive from the correct source path: `tar czf ... -C /persist/var/lib qbittorrent`
- **Files modified:** none (live ser8 state only)
- **Verification:** New tarball is 46MB / 15,033 entries; spot-checked contents include `qBittorrent/config/qBittorrent.conf`, `qBittorrent/data/BT_backup`, `qBittorrent/data/logs/*`
- **Committed in:** N/A (no repo files touched)

**3. [Rule 3 - Blocking issue] `make switch-ser8`'s interactive confirmation prompt cannot be satisfied non-interactively**
- **Found during:** Task 1
- **Issue:** `nixos_confirm()` in `scripts/nixos-rebuild.sh` calls `read -p "Continue? (y/N)"`, which blocks indefinitely in a non-interactive session
- **Fix:** Ran `NO_CONFIRM=true make switch-ser8`, per the Makefile's own documented escape hatch (`NO_CONFIRM ?= false`) for intentional non-interactive operations. This was safe because the exact same change had already been dry-run (`make dry-activate-ser8` in 12-03) and test-activated (`make test-ser8` earlier in this same task) before this step
- **Files modified:** none (live ser8 state only)
- **Verification:** `/nix/var/nix/profiles/system` and `/run/current-system` both resolved to the same new generation after the run
- **Committed in:** N/A (no repo files touched)

### Human-action gate (not an auto-fix — required real human execution)

**SOPS secret removal blocked by sandbox, executed by the human**
- **Found during:** Task 3
- **Issue:** `sops unset --idempotent secrets/ser8.yaml '["key"]'` failed to decrypt the file from this session: the age recipient is ser8's root-only host SSH key (unreachable from this workstation by design), and the fallback GPG admin key failed with `Operation not permitted` on `~/.gnupg/*` — consistent with this session's `sagent` seatbelt sandbox blocking writes outside the project directory (including GPG lock files), a restriction that persisted even after attempting to run with the sandbox override
- **Resolution:** Reported this as a `checkpoint:human-action`; the human ran `make sops-edit-ser8` themselves in an unsandboxed terminal and removed the three keys
- **Verification performed by executor (post-human-action):** `git diff secrets/ser8.yaml` shows the three key lines and their orphaned `#ENC[...,type:comment]` lines removed, with no decrypted content ever printed by the executor; all other secrets and their `ENC[...]` values are untouched
- **Committed in:** `b73ad14` (part of Task 3's atomic commit)

### Human-confirmed scope expansion (plan checkpoint, not autonomous)

**4. Task 3's deletion scope expanded to include `/persist/var/lib/qbittorrent`**
- **Found during:** Task 2 (discovered), resolved at the plan's `checkpoint:decision` before Task 3 ran
- **Issue:** The plan's Task 3 specifies `rm -rf /var/lib/qbittorrent /var/lib/wgnord`. Because of Auto-fixed Issue #1, `/var/lib/qbittorrent` was by this point an empty, unbound directory — deleting it as literally written would have been a no-op for the real 46MB/15,033-file qBittorrent state, which now lived at `/persist/var/lib/qbittorrent`, and would have left it there indefinitely (the impermanence bind-mount declaration was already permanently removed from the repo in plan 12-03, so this was not a transient condition)
- **Why not auto-fixed under Rules 1-3:** this plan's frontmatter explicitly flags a prohibition against deleting under `/persist` for review; expanding a destructive deletion's scope past what a human already reviewed and approved is exactly the kind of change Rule 4 (architectural/significant decision) reserves for explicit confirmation, especially given the STRIDE threat register's T-12-10 entry on this exact task
- **Resolution:** Presented the finding and two concrete options (`proceed-as-written` vs `proceed-with-persist-path`) at the existing plan checkpoint; human selected `proceed-with-persist-path`
- **Fix:** `ssh bdhill@192.168.68.65 'sudo rm -rf /var/lib/qbittorrent /var/lib/wgnord /persist/var/lib/qbittorrent'` — three exact hardcoded paths, no wildcards, no other paths under `/persist`
- **Files modified:** none (live ser8 state only)
- **Verification:** `test -d /var/lib/qbittorrent || test -d /var/lib/wgnord || test -d /persist/var/lib/qbittorrent` → `REMOVED`; archive at `/mnt/backups/phase12-fleet-repair-archive/` confirmed untouched (same file sizes before and after)
- **Committed in:** N/A (no repo files touched)

---

**Total deviations:** 3 auto-fixed (2x Rule 3, 1x Rule 1), 1 human-confirmed scope expansion (checkpoint-gated), 1 human-action gate (sandbox-blocked secret edit).
**Impact on plan:** All fixes were necessary for correctness — the mount-unit fix was required for the deploy to complete at all, the archive re-take was required for D-03's actual intent (not just its literal text) to be satisfied, and the deletion scope expansion prevented silently leaving 46MB of supposedly-deleted qBittorrent state on disk indefinitely. No scope creep beyond what FLEET-01 already required.

## Issues Encountered
See Deviations above — all three technical issues (mount-unmount race, stale interactive prompt, wrong archive source) were resolved within this plan. The SOPS decryption limitation is an environment property of this execution session, not a code or plan defect, and is expected to recur for any future secrets-editing task run under the same sandbox.

## User Setup Required
None beyond the one-time human action already completed (removing the three SOPS keys via `make sops-edit-ser8`), which is recorded above as done.

## Next Phase Readiness
FLEET-01 is fully closed: no NordVPN/qBittorrent code, live units, live state, or secrets remain anywhere in the repo or on ser8. Phase 12 has one remaining plan (12-05, FLEET-04 Radarr root-folder cleanup) before Phase 13's ZFS mirror migration, which depends on ser8's fleet being stable and API-clean.
