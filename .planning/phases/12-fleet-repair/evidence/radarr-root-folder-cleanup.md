# Radarr Root Folder Cleanup (FLEET-04, D-14/D-15)

Date: 2026-08-24
Host: ser8 (192.168.68.65), Radarr API v3, port 7878 (internal, not the Exportarr port 9708)

## Before-Snapshot

Exported via `GET /api/v3/movie` (embeds `movieFile` per record, so a separate
`/api/v3/moviefile` export was not needed for the diff — a plain `GET /api/v3/moviefile`
call returns HTTP 400 without a `movieId` filter, confirming the per-movie embed is the
correct source).

Saved to `.planning/phases/12-fleet-repair/evidence/radarr-movie-snapshot-before.json`.
50 movie records total.

## Root Folders Found (before cleanup)

`GET /api/v3/rootfolder` returned four root folders:

| id | path | Status |
|----|------|--------|
| 1 | `/mnt/media/movies` | Canonical — kept |
| 2 | `/mnt/media/downloads/usenet/complete/movies/Tenet 2020 2160p UHD Blu-ray HEVC DTS-HD MA 5.1-ESiR` | Bogus — removed |
| 3 | `/mnt/media/downloads/usenet/complete/movies/Tenet (2020)` | Bogus — removed |
| 4 | `/mnt/media/downloads/usenet/complete/movies` | Bogus — removed |

## Movie Records Found Under Bogus Roots

Three movie records had `rootFolderPath` under a bogus root:

### Movie id 11 — "Tenet" (tmdbId 577922)

- Before: `path` = `/mnt/media/downloads/usenet/complete/movies/Tenet 2020 2160p UHD Blu-ray HEVC DTS-HD MA 5.1-ESiR/`, `rootFolderPath` = `/mnt/media/downloads/usenet/complete/movies`, `hasFile` = `false`.
- Investigation: the folder is a raw, un-remuxed Blu-ray disc dump (`BDMV`/`CERTIFICATE`/`MAKEMKV` structure), which Radarr has never recognized as an importable movie file — this record carries **no registered `movieFile`**, so there is nothing to lose regardless of outcome.
- Found that `/mnt/media/movies/Tenet (2020)` already existed as a symlink pointing at the same physical directory (`realpath` and `stat -c %i` both confirmed identical inode across `/mnt/media/movies/Tenet (2020)`, `/mnt/media/downloads/usenet/complete/movies/Tenet (2020)`, and `/mnt/media/downloads/usenet/complete/movies/Tenet 2020 2160p UHD Blu-ray HEVC DTS-HD MA 5.1-ESiR` — pre-existing symlinks created outside this plan, not touched or created by this plan).
- Resolution: **re-pointed** (no file move performed, none needed) — `PUT /api/v3/movie/11` (no `moveFiles` param) with `path` = `/mnt/media/movies/Tenet (2020)`, `rootFolderPath` = `/mnt/media/movies`. Confirmed via `GET /api/v3/movie/11` afterward: `path` = `/mnt/media/movies/Tenet (2020)`, `rootFolderPath` = `/mnt/media/movies`, `hasFile` still `false` (unchanged, as expected — this record never had a file).

### Movie id 50 — "Avatar Aang: The Last Airbender" (tmdbId 980431)

- Before: `path` = `/mnt/media/downloads/usenet/complete/movies/Avatar Aang - The Last Airbender (2026)`, `rootFolderPath` = `/mnt/media/downloads/usenet/complete/movies`, `hasFile` = `true` (movieFileId 164, ~7.78 GB).
- Investigation: no folder existed yet at the canonical `/mnt/media/movies` path for this title.
- Resolution: **moved** — `PUT /api/v3/movie/50?moveFiles=true` with `path`/`rootFolderPath`/`folderName` set to `/mnt/media/movies/Avatar Aang - The Last Airbender (2026)`. Returned HTTP 200 synchronously with the updated resource. Confirmed on disk: the `.mkv`, both `.srt` subtitle files, and the bazarr tarball backup all now live at `/mnt/media/movies/Avatar Aang - The Last Airbender (2026)/`; the old downloads-tree folder for this title no longer exists (moved, not copied).

### Movie id 51 — "Malibu's Most Wanted" (tmdbId 13411)

- Before: `path` = `/mnt/media/downloads/usenet/complete/movies/Malibu's Most Wanted (2003)`, `rootFolderPath` = `/mnt/media/downloads/usenet/complete/movies`, `hasFile` = `true` (~3.1 GB).
- Investigation: no folder existed yet at the canonical `/mnt/media/movies` path for this title.
- Resolution: **moved** — `PUT /api/v3/movie/51?moveFiles=true` with `path`/`rootFolderPath`/`folderName` set to `/mnt/media/movies/Malibu's Most Wanted (2003)`. Returned HTTP 202 (queued as an async Radarr move command); polled `GET /api/v3/movie/51` after a few seconds and confirmed `path` = `/mnt/media/movies/Malibu's Most Wanted (2003)`, `rootFolderPath` = `/mnt/media/movies`, `hasFile` still `true`. Confirmed on disk: the `.mkv`, `.srt`, and tarball backup now live under the canonical path; the old downloads-tree folder for this title no longer exists.

No other movie record (of the 50 in the before-snapshot) had a `rootFolderPath` under any bogus root.

## Root Folder Removal

Once all three records above were confirmed re-homed (verified via a fresh `GET /api/v3/rootfolder`
showing zero remaining movie records referencing any bogus root's `unmappedFolders`/registered
movies), all three bogus roots were removed:

- `DELETE /api/v3/rootfolder/2` — HTTP 200
- `DELETE /api/v3/rootfolder/3` — HTTP 200
- `DELETE /api/v3/rootfolder/4` — HTTP 200

Post-removal `GET /api/v3/rootfolder` returns exactly one entry: `/mnt/media/movies` (id 1).

No command run in this task passed a file-deletion flag to Radarr. Every `PUT`
body was the movie's full resource with only `path`/`rootFolderPath`/`folderName` changed, and every
`DELETE` targeted `/api/v3/rootfolder/{id}` only (Radarr's root-folder delete endpoint has no
file-deletion option — it only removes the root-folder record, never touches disk).

## Untouched Per D-04

The `/mnt/media/downloads/usenet/complete/movies` directory itself, and its remaining unrelated
contents (`Children.of.Men.2006.1080p.BRA.Blu-ray.AVC.DTS-HD.MA.5.1-MPira/`,
`Malibus.Most.Wanted.2003.1080p.WEB.h264-NOMA/` — an older, lower-quality duplicate download not
referenced by any current movie record, and the Tenet raw-disc folder/symlink pair), were left
exactly as found. No files or directories were deleted anywhere in this task. The pre-existing
`Tenet (2020)` symlinks (both under `/mnt/media/movies/` and under the bogus downloads root) were
not created or modified by this plan; they already existed and were only referenced for the
re-pointing decision on movie id 11.

## Post-Cleanup Snapshot and Zero-Loss Diff (Task 2, D-14)

Exported the same `GET /api/v3/movie` snapshot again after the root-folder cleanup and saved it to
`.planning/phases/12-fleet-repair/evidence/radarr-movie-snapshot-after.json`.

Diffed the before- and after-snapshots by movie `id` (stable across the re-home, since re-homing
only changed `path`/`rootFolderPath`/`folderName`, never the record's identity):

- **Movie count:** 50 before, 50 after — unchanged.
- **Movie ID set:** identical — zero IDs missing from the after-snapshot, zero new IDs.
- **TMDB ID set:** identical.
- **`hasFile` flips (true → false):** none. Every record that had a file before the cleanup still
  has a file after it (including movie ids 50 and 51, whose files were physically moved).
- The three re-homed records (ids 11, 50, 51) each show their `path`/`rootFolderPath` now under the
  canonical `/mnt/media/movies`, with `hasFile` unchanged from its before-value (`false` for id 11,
  `true` for ids 50 and 51).

### Conclusion

**Zero movie/moviefile records were lost.** Before: 50 movies. After: 50 movies. All 50 movie IDs
and TMDB IDs present before the cleanup are present after it, and no record's file-presence flag
regressed from `true` to `false`. D-14's zero-loss requirement is satisfied.
