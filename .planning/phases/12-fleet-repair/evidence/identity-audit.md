# Identity Audit — Phase 12 Fleet Repair (D-10)

**Gathered:** 2026-08-24, via SSH to `bdhill@192.168.68.65` (ser8, live production).
**Scope:** Extended identity census across media-adjacent service accounts, per D-10.
**Status:** Discovery-only. No service identity, unit file, or Nix declaration was changed by this task.

## Premise correction (read this first)

This plan (12-01) originally assumed live ser8 already used uid 1002 / gid 992 for the shared
`media` user/group, with the repo's `modules/common/users.nix` declaration of 1100/1100 being the
stale side (D-07/D-08 as first written). Live verification during execution showed the opposite:

- `id media` on ser8 reports `uid=1100(media) gid=1100(media)` — **already matching** the repo's
  current declaration exactly.
- `getent group 992` resolves to `mealie`, an unrelated live household-app service group. gid 992
  was never the media group's live identity.
- `getent passwd 1002` returns no match on ser8 today.

The uid 1002 / gid 992 identity-adoption decision (original D-07/D-08) was abandoned as
unnecessary and unsafe (see `.planning/PROJECT.md` Key Decisions for the corrected record). No
edit was made to `modules/common/users.nix`. This census proceeds as originally scoped — it was
discovery-only regardless of the identity-adoption outcome — but its "declared" column reflects
the fleet's actual, unchanged declaration (media = 1100/1100), not the abandoned 1002/992 target.

## Census

| Service | Declared uid/gid | Live uid/gid | Drift observed | Note |
|---------|-------------------|--------------|-----------------|------|
| jellyfin | auto-allocated uid; group forced to `media` (gid 1100) via `modules/media/jellyfin.nix` | uid=993, gid=1100 | no | A separate `jellyfin` group (gid 1101) is declared in `modules/common/users.nix` but is not jellyfin's primary group — jellyfin's `group = lib.mkForce "media"` wins. gid 1101 is used only by `/var/cache/jellyfin`. Not a defect; recorded for Phase 15's Nixflix adapter awareness. |
| sonarr | auto-allocated uid; group forced to `media` (gid 1100) via `modules/media/sonarr.nix` | uid=274, gid=1100 | no | No dedicated `sonarr` group exists; primary group is `media`. |
| radarr | auto-allocated uid; group forced to `media` (gid 1100) via `modules/media/radarr.nix` | uid=275, gid=1100 | no | No dedicated `radarr` group exists; primary group is `media`. |
| bazarr | auto-allocated uid; group forced to `media` (gid 1100) via `modules/media/bazarr.nix` | uid=986, gid=1100 | no | No dedicated `bazarr` group exists; primary group is `media`. |
| sabnzbd | auto-allocated uid; group forced to `media` (gid 1100) via `modules/media/sabnzbd.nix` | uid=985, gid=1100 (service account itself) | no (service account) | The service account's own uid/gid are correct. The separate, already-known FLEET-02 issue is stale *file* ownership inside `/var/lib/sabnzbd` (1,258 files owned by uid 38, 1,262 by gid 194) — that is a state-directory content drift, not a drift in the declared/live sabnzbd account itself. Diagnosed and repaired in plan 12-02 (D-11/D-12), not this plan. |
| nzbget | auto-allocated uid; group forced to `media` (gid 1100) via `modules/media/nzbget.nix` | uid=245, gid=1100 | no | No dedicated `nzbget` group exists; primary group is `media`. |
| media (shared group) | gid 1100 (`modules/common/users.nix`) | gid 1100 | no | `getent group media` → `media:x:1100:bdhill,frigate`. Declaration and live state match exactly; this is the finding that overturned the original D-07 premise. |

**Summary:** Zero identity drift found across all six censused services and the shared `media`
group. Every service's live primary group is `media` (gid 1100), matching each module's forced
`group = "media"` declaration. Every service uid is NixOS-auto-allocated (no explicit uid pinned
in Nix for jellyfin/sonarr/radarr/bazarr/nzbget); their current live allocations are recorded
above for Phase 15's Nixflix adapter reference. sabnzbd's own account is not drifted; sabnzbd's
*file-ownership* drift is a separate, already-tracked issue (FLEET-02, plan 12-02).
