# Phase 12: Fleet Repair - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-08-23
**Phase:** 12-Fleet Repair
**Areas discussed:** NordVPN/qBt teardown depth, Media identity fix, sabnzbd repair durability, Radarr cleanup verification

**Prior-session decision carried in:** FLEET-01 rescoped from "diagnose and fix the wgnord loop" to "disable the whole NordVPN + qBittorrent stack" (user: "not being used, don't want to waste time"); follow-up question confirmed disabling both rather than keeping a VPN-less qBittorrent.

---

## NordVPN/qBt teardown depth

| Option | Description | Selected |
|--------|-------------|----------|
| Delete entirely | Remove modules/nordvpn/, qBittorrent config, nginx exposure, smoketests; git history is the archive | ✓ |
| Keep module, drop import | Dead code stays on disk, easy re-enable | |
| Disable via enable=false | Everything wired but toggled off | |

**User's choice:** Delete entirely

| Option | Description | Selected |
|--------|-------------|----------|
| Full cleanup | Remove impermanence entries + SOPS secrets from repo; archive-then-delete state dirs on ser8 | ✓ |
| Repo cleanup, keep state | Repo cleaned but /var/lib dirs left on disk | |
| Touch nothing on disk | Repo-only change | |

**User's choice:** Full cleanup

| Option | Description | Selected |
|--------|-------------|----------|
| Leave it alone | Download tree migrates as-is to ZFS; no deletion authorized | ✓ |
| Prune unlinked leftovers | Reclaim space before Phase 13 staging | |

**User's choice:** Leave it alone

| Option | Description | Selected |
|--------|-------------|----------|
| Fix all now, in Phase 12 | Update REQUIREMENTS.md + ROADMAP.md for FLEET-01 and Phases 13-15 | ✓ |
| Fix FLEET-01 only | Later phases fix their own wording at plan time | |

**User's choice:** Fix all now, in Phase 12

---

## Media identity fix

| Option | Description | Selected |
|--------|-------------|----------|
| Repo adopts live | Declare uid 1002 / gid 992; zero touch of the media tree | ✓ |
| Migrate disk to 1100 | Re-chown live files to match declaration | |

**User's choice:** Repo adopts live

| Option | Description | Selected |
|--------|-------------|----------|
| Change common module | 1002/992 fleet-wide in modules/common/users.nix | ✓ |
| ser8-level override | mkForce on ser8 only; two identities in repo | |
| You decide at plan time | Researcher confirms firebat live state first | |

**User's choice:** Change common module

| Option | Description | Selected |
|--------|-------------|----------|
| Targeted audit | Scoped find for wrong-owner files; chown only reviewed paths | ✓ |
| Flip and smoke-test only | Rely on service health to surface mismatches | |
| Full ownership inventory | Complete uid/gid census of ~7.8 TB tree | |

**User's choice:** Targeted audit

| Option | Description | Selected |
|--------|-------------|----------|
| Audit all media identities | jellyfin + all *arr users/groups vs live passwd/group | ✓ |
| Media user/group only | Tightest FLEET-03 scope | |

**User's choice:** Audit all media identities

---

## sabnzbd repair durability

| Option | Description | Selected |
|--------|-------------|----------|
| One-time scoped chown | Fix once + pin sabnzbd uid statically | ✓ |
| Declarative tmpfiles rule | Standing recursive chown every boot | |
| Wipe and re-seed state | Lose queue/history, regenerate | |

**User's choice:** One-time scoped chown

| Option | Description | Selected |
|--------|-------------|----------|
| Brief check, then fix | Timeboxed journal skim; static pin is the durability mechanism | |
| Just fix it | No investigation | |
| Full diagnosis first | Understand the drift mechanism completely before touching anything | ✓ |

**User's choice:** Full diagnosis first (declined the recommended timeboxed option — depth over speed here)

| Option | Description | Selected |
|--------|-------------|----------|
| Fix it here | Upgrade check to unit + API + gateway route | |
| Leave for later | Manual verification this once; smoketest overhaul stays deferred | ✓ |

**User's choice:** Leave for later

---

## Radarr cleanup verification

| Option | Description | Selected |
|--------|-------------|----------|
| Movie snapshot diff | Before/after movie + moviefile API export, assert zero lost files | ✓ |
| Full API inventory export | Also export clients/profiles/indexers for Phase 15 | |
| Root-folder check only | Just confirm the folder list shrinks | |

**User's choice:** Movie snapshot diff

| Option | Description | Selected |
|--------|-------------|----------|
| Investigate, then re-home | Per-record check; re-point or Radarr-managed move; never deleteFiles=true | ✓ |
| Re-home blindly to canonical | Bulk-edit without per-record checks | |
| You decide at plan time | Researcher inspects live API first | |

**User's choice:** Investigate, then re-home

| Option | Description | Selected |
|--------|-------------|----------|
| Remove client entries | Delete dead qBittorrent client from Radarr/Sonarr/Prowlarr via API | ✓ |
| Leave until Phase 15 | Nixflix reconciliation replaces client config anyway | |

**User's choice:** Remove client entries

---

## Claude's Discretion

- Ordering of the four repairs
- Archive location/format for pre-deletion qBittorrent/wgnord state
- Mechanics of the D-05 doc updates
- Scripting/evidence format for the targeted ownership audit

## Deferred Ideas

- Blind SABnzbd smoketest fix / broader smoketest overhaul
- Pruning unlinked leftovers in /mnt/media/downloads
- Todo "Migrate .vofi hostnames to public vofi.dev domain" — reviewed, not folded (gateway work, out of scope)
