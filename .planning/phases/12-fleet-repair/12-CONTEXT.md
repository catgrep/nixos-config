# Phase 12: Fleet Repair - Context

**Gathered:** 2026-08-23
**Status:** Ready for planning

<domain>
## Phase Boundary

ser8's fleet is stable and API-clean before the Phase 13 storage freeze.
Four repairs, all on the critical path: the NordVPN + qBittorrent stack is removed entirely (FLEET-01, rescoped this session from "fix the loop" to "retire the stack"), sabnzbd's uid-drifted state is diagnosed and repaired (FLEET-02), the repo's media user/group declarations are reconciled to live ser8 identities (FLEET-03), and Radarr's root folders are cleaned via API with zero media loss (FLEET-04).
No storage work, no ZFS, no Nixflix — those are Phases 13-15.

</domain>

<decisions>
## Implementation Decisions

### FLEET-01 rescope: retire the NordVPN + qBittorrent stack

- **D-01:** Torrents are retired; the download path is usenet-only (SABnzbd/NZBGet). Disable-and-delete replaces diagnose-and-fix for the wgnord restart loop. — **Reversibility:** costly — restoring torrents later means resurrecting the module from git history, re-provisioning a NordVPN token, and re-adding client entries to three *arr apps; Phase 15's Nixflix declarations and Phase 14's backup set are being written without qBittorrent.
- **D-02:** Delete the code entirely: `modules/nordvpn/`, the qBittorrent service config (`modules/media/qbittorrent.nix` and its wiring in `hosts/ser8/media.nix`), the nginx exposure, and related smoketests (including `nordvpn/test-forwarding.sh`). Git history is the archive — no dead code, no `enable = false` shims.
- **D-03:** Full state cleanup: remove the impermanence entries and the NordVPN/qBittorrent SOPS secrets from the repo; on ser8, archive-then-delete `/var/lib/qbittorrent` and `/var/lib/wgnord`. — **Reversibility:** one-way once the archived state is discarded — qBittorrent session/history state does not regenerate; take the archive copy before deletion.
- **D-04:** The torrent download tree under `/mnt/media/downloads` is left untouched. No media deletion is authorized in this phase; the tree migrates as-is to ZFS in Phase 13.
- **D-05:** Fix all stale torrent wording in planning docs now, as part of this phase: FLEET-01 requirement text, Phase 13 smoketest list (drop qBittorrent), Phase 14 backup set (drop qBittorrent state), Phase 15 download clients (three → two) and its torrent-import hardlink test (moves to a usenet import). Update REQUIREMENTS.md and ROADMAP.md together.
- **D-06:** Record "torrents retired, usenet-only download path" in PROJECT.md Key Decisions alongside the FLEET-03 identity decision.

### FLEET-03: media identity reconciliation

- **D-07:** Repo adopts live identities: declare uid 1002 / gid 992 for the media user/group, replacing 1100/1100. The ~7.8 TB media tree is never re-chowned. — **Reversibility:** costly — moving to any other uid later would require exactly the mass re-chown this decision avoids.
- **D-08:** The change lands fleet-wide in `modules/common/users.nix` (one source of truth). firebat/pi4/pi5 have no media files, so their `/etc/passwd` shifting on next deploy is harmless.
- **D-09:** Verification is a targeted audit: scoped `find` for files under `/mnt/media` and media-service state dirs NOT owned by 1002/992, review the list, chown only those reviewed paths. No blind recursive re-chown, no full-tree census.
- **D-10:** The identity audit extends beyond the media user/group: one census of jellyfin (declared gid 1101), sonarr, radarr, bazarr, sabnzbd, and nzbget users/groups against live `/etc/passwd` + `/etc/group`. Findings feed Phase 15's Nixflix adapter, which must force live identities.

### FLEET-02: sabnzbd repair

- **D-11:** Full diagnosis first. Understand exactly how `/var/lib/sabnzbd/admin` files came to be owned 38:194 before touching anything — no timeboxed shortcut. The planner should schedule diagnosis as its own task with the repair gated on its findings.
- **D-12:** Repair mechanism after diagnosis: one-time scoped chown of `/var/lib/sabnzbd` to the declared identities, paired with pinning sabnzbd's uid/gid statically in Nix so the drift cannot recur. No standing tmpfiles re-chown rule.
- **D-13:** The known-blind SABnzbd smoketest is NOT fixed in this phase. FLEET-02 success (unit active + firebat `https_sabnzbd` healthy) is verified manually this once; the smoketest overhaul stays a deferred item.

### FLEET-04: Radarr cleanup

- **D-14:** Verification is a movie snapshot diff: export the full movie + moviefile list via the Radarr API before and after root-folder removal, diff, assert zero lost files.
- **D-15:** Any movie records homed under the three bogus roots (`/mnt/media/downloads/usenet/complete/movies/...`) are investigated per-record, then re-homed: re-point to `/mnt/media/movies` if the file already exists there; otherwise a Radarr-managed move first. Never `deleteFiles=true`.
- **D-16:** The dead qBittorrent download-client entries are removed via API from Radarr, Sonarr, AND Prowlarr in this phase (a consequence of D-01). Keeps the stack API-clean; Phase 15 then declares only real clients.

### Claude's Discretion

- Ordering of the four repairs (the assumptions discussion suggested identity decision → sabnzbd → teardown/Radarr in any order; planner decides).
- Exact archive location/format for the pre-deletion qBittorrent/wgnord state copy (D-03).
- Mechanics of the doc updates in D-05 (single commit vs per-file).
- How the targeted ownership audit (D-09) is scripted and evidenced.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Migration contract and live-state facts
- `.planning/SER8-ZFS-MIRROR-MIGRATION.md` — §Known Blockers documents the wgnord/qBittorrent loop and the Radarr root-folder drift this phase resolves; §Verified Application Paths has the confirmed live roots; its no-further-deletion rule constrains D-04. Phase 13 consumes this doc's approval contract, so Phase 12 must leave its facts accurate.

### Requirements and roadmap (targets of D-05 edits)
- `.planning/REQUIREMENTS.md` — FLEET-01..04 definitions; FLEET-01 text needs the retire-torrents rewrite.
- `.planning/ROADMAP.md` — Phase 12 success criteria plus the stale qBittorrent references in Phases 13-15 details.

### Prior-state records
- `.planning/STATE.md` — Deferred Items table maps the v1.2 operational issues to FLEET-01..03 and records the live drift values (media declared 1100, live 1002/992; sabnzbd files 38:194).
- `.planning/PROJECT.md` — Key Decisions table; D-06 and the FLEET-03 record land here.

</canonical_refs>

<code_context>
## Existing Code Insights

### Removal surface (D-02/D-03)
- `modules/nordvpn/` (default.nix, service.nix ~324 lines, template.conf): the whole directory goes. `wgnord-monitor` restarting `wgnord.service` on ping failure is the observed loop mechanism — moot once deleted.
- `modules/media/qbittorrent.nix` + its import in `modules/media/default.nix` and wiring in `hosts/ser8/media.nix` (BindsTo=wgnord.service, nginx exposure).
- `hosts/ser8/impermanence.nix` — persistence entries for qBittorrent/wgnord state.
- `secrets/ser8.yaml` — NordVPN access token and qBittorrent WebUI hash (via `make sops-edit-ser8`; never print values).
- `scripts/smoketests/nordvpn/` and qBittorrent assertions in the media suite.
- Makefile target `sops-gen-hash-qbittorrent` and any deploy.yaml smoketest references.

### Identity surface (D-07/D-08)
- `modules/common/users.nix` — media uid/gid 1100 and jellyfin gid 1101 declarations; imported via `baseModules` in `flake.nix` (all four hosts).
- `modules/media/*.nix` — every service forces `group = "media"` (sonarr, radarr, bazarr, sabnzbd, nzbget, jellyfin), so the gid change propagates automatically.
- `hosts/ser8/impermanence.nix:198` — tmpfiles rule `d /persist/var/lib/sabnzbd 0755 sabnzbd media -` interacts with D-12's static uid pin.

### Established patterns
- `mutableUsers = false` fleet-wide — identity changes take effect at activation; `make dry-activate-ser8` before `make test-ser8` is the safe review path.
- Smoketest philosophy from Phase 10 (assert unit + endpoint + state stores) is the eventual bar for the sabnzbd check, but per D-13 that work is deferred.
- `make test-HOST` (temporary activation) before `make switch-HOST` for live changes.

### Integration points
- firebat's Caddyfile `https_sabnzbd` route is the external health signal for FLEET-02.
- Radarr/Sonarr/Prowlarr API keys come from SOPS; API surgery happens over SSH on ser8 (`make ssh-ser8`).

</code_context>

<specifics>
## Specific Ideas

- The user explicitly chose depth over speed for sabnzbd: "full diagnosis first" was picked over the recommended timeboxed check — the planner should treat diagnosis as a first-class task, not a preamble.
- The user consistently trimmed scope elsewhere: smoketest overhaul deferred, download-tree pruning declined, .vofi todo left in backlog. Keep the phase lean.

</specifics>

<deferred>
## Deferred Ideas

- Blind SABnzbd smoketest fix (and the broader smoketest overhaul from STATE.md deferred items) — explicitly kept out of this phase (D-13).
- Pruning unlinked leftovers in `/mnt/media/downloads` — declined; revisit after Phase 13 if space pressure appears.

### Reviewed Todos (not folded)
- "Migrate .vofi hostnames to public vofi.dev domain" — keyword match only; gateway/DNS work unrelated to ser8 fleet repair. Stays in the backlog.

</deferred>

---

*Phase: 12-Fleet Repair*
*Context gathered: 2026-08-23*
