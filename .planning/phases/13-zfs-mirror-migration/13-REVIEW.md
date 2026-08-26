---
phase: 13-zfs-mirror-migration
reviewed: 2026-08-25T23:59:37Z
depth: standard
files_reviewed: 12
files_reviewed_list:
  - CLAUDE.md
  - hosts/ser8/README.md
  - hosts/ser8/configuration.nix
  - hosts/ser8/disko-config.nix
  - hosts/ser8/impermanence.nix
  - hosts/ser8/media/nzbget.nix
  - hosts/ser8/media/permissions.nix
  - hosts/ser8/media/sabnzbd.nix
  - hosts/ser8/samba.nix
  - scripts/sampled-verify.sh
  - scripts/sampled-verify.test.sh
  - scripts/smoketests/media/all.sh
  - scripts/smoketests/media/test-zfs-media.sh
findings:
  critical: 1
  warning: 2
  info: 1
  total: 4
status: clean
---

# Phase 13: Code Review Report

**Reviewed:** 2026-08-25T23:59:37Z
**Depth:** standard
**Files Reviewed:** 12
**Status:** issues_found

## Summary

The 13 files were checked for correctness against the stated migration (MergerFS/ext4 → ZFS mirror for
`/mnt/media`, NVMe-quota'd download staging at `/mnt/downloads`, verification tooling, smoketests, docs).
Nix formatting (`nixfmt --check`), `statix check`, `shellcheck`, and `shfmt -d` are all clean across every
touched file, and `scripts/sampled-verify.test.sh` passes all five of its self-tests locally.

One blocker was found by tracing the path rename in `hosts/ser8/media/nzbget.nix` into the
post-processing script it invokes: the script's safety-check default was never updated for the new
download path, so it will reject (not silently skip — actively error) every completed NZBGet download
once this ships. Two further issues were found: dead tmpfiles rules left over from the old download
layout, and a permission-normalization/smoketest coverage gap for two of the four media libraries the
migration's own documentation claims are covered.

## Critical Issues

### CR-01: NZBGet post-processing permission normalization will reject every completed download

**File:** `hosts/ser8/media/nzbget-normalize-permissions.sh:18` (invoked by `hosts/ser8/media/nzbget.nix:26-85`)

**Issue:**
This phase renames NZBGet's `DestDir`/category directories from `/mnt/media/downloads/usenet/complete/*`
to `/mnt/downloads/complete/*` (`hosts/ser8/media/nzbget.nix:26-85`). NZBGet runs
`nzbget-normalize-permissions.sh` as a post-processing extension for every category
(`Category{1..4}.Extensions=nzbget-normalize-permissions`), passing the finished job's directory via
`NZBPP_DIRECTORY`.

The script guards against operating outside an expected root:

```sh
complete_root=${NZBGET_COMPLETE_ROOT:-/mnt/media/downloads/usenet/complete}
...
case "$download_dir" in
"$complete_root"/*) ;;
*)
	echo "[ERROR] Refusing to modify path outside $complete_root: $download_dir"
	exit "$POSTPROCESS_ERROR"
	;;
esac
```

`NZBGET_COMPLETE_ROOT` is never set anywhere in production config — it is only ever set (to the correct
value) inside `scripts/validation/test-nzbget-permissions.sh`, which is why this was never caught. In
production the script falls back to the **old, pre-migration** default
`/mnt/media/downloads/usenet/complete`. After this change, every real job's `download_dir` will be under
the **new** `/mnt/downloads/complete/...` path, which never matches `"$complete_root"/*`. The `realpath -e`
resolution of `complete_root` still succeeds (see WR-01 below — the old directory is never removed), so
the script doesn't fail loudly on a missing path; it silently trips the "outside root" guard and exits 94
(`POSTPROCESS_ERROR`) on every single completed download. NZBGet records this as a post-processing
failure, permissions are never normalized on extracted archive contents (the exact case the script exists
to fix — see the script's own test fixture), and downstream tooling (Sonarr/Radarr polling
download-client history) may treat completed imports as failed.

**Fix:** Either update the script's default to the new root, or (better, so the two files can't drift
again) pass the root explicitly from the Nix config instead of relying on a hardcoded default:

```nix
# hosts/ser8/media/nzbget.nix
systemd.services.nzbget.environment.NZBGET_COMPLETE_ROOT = "/mnt/downloads/complete";
```

```sh
# hosts/ser8/media/nzbget-normalize-permissions.sh
complete_root=${NZBGET_COMPLETE_ROOT:-/mnt/downloads/complete}
```

## Warnings

### WR-01: Dead tmpfiles rules for the retired `/mnt/media/downloads` layout

**File:** `hosts/ser8/impermanence.nix:166-178`

**Issue:** This phase adds new tmpfiles rules for `/mnt/downloads/*` (lines 180-189) but leaves the old
`/mnt/media/downloads/*` rules in place:

```
"d /mnt/media/downloads 2775 media media -"
"d /mnt/media/downloads/tv 2775 media media -"
"d /mnt/media/downloads/movies 2775 media media -"
"d /mnt/media/downloads/usenet 2775 media media -"
"d /mnt/media/downloads/usenet/incomplete 2775 media media -"
"d /mnt/media/downloads/usenet/complete 2775 media media -"
"d /mnt/media/downloads/usenet/complete/tv 2775 media media -"
"d /mnt/media/downloads/usenet/complete/movies 2775 media media -"
"d /mnt/media/downloads/usenet/complete/prowlarr 2775 media media -"
"d /mnt/media/downloads/usenet/complete/default 2775 media media -"
```

No service writes to these paths anymore (both `nzbget.nix` and `sabnzbd.nix` were repointed at
`/mnt/downloads` in this same diff), and `hosts/ser8/media/permissions.nix`'s `mediaRoots` was updated to
drop `/mnt/media/downloads` in favor of `/mnt/downloads`, so these directories are no longer even covered
by the ongoing permission-normalization service. They will persist as empty clutter directly on the ZFS
media mirror forever — the opposite of the migration's stated goal of keeping churn off the mirror — and,
as described in CR-01, their continued existence is precisely what lets the stale `complete_root` default
resolve instead of failing loudly.

**Fix:** Remove the ten `/mnt/media/downloads*` tmpfiles rules (and delete the directories on the live host
as part of the migration, per the repository's "replace, don't deprecate" convention).

### WR-02: Permission normalization and smoketest coverage skip two of the four media libraries

**File:** `hosts/ser8/media/permissions.nix:27-31`, `scripts/smoketests/media/test-zfs-media.sh:142,161-178`

**Issue:** `hosts/ser8/README.md` (added by this phase) and the `media` zpool comment in
`hosts/ser8/disko-config.nix:295-303` both describe `media/data` as "a single dataset holding the media
libraries (movies, tv, music, books)". However:

- `mediaRoots` in `permissions.nix` only lists `/mnt/downloads`, `/mnt/media/movies`, `/mnt/media/tv` — the
  ongoing `media-permissions.service` normalization never touches `/mnt/media/music` or
  `/mnt/media/books`.
- The new `test-zfs-media.sh` smoketest's `test_canonical_dirs` (line 142) checks all four directories
  exist, but `test_service_access` (lines 161-178) only checks read access on `movies` and `tv`, and
  `scripts/smoketests/media/all.sh`'s pre-existing permission checks are likewise scoped to
  `movies`/`tv` only.

This predates this phase (the array already excluded music/books before the rename), but the phase's own
new documentation and new smoketest both assert full four-library coverage without actually closing the
gap, so files touched by music/book imports have no automated permission guarantee or verification.

**Fix:** Add `/mnt/media/music` and `/mnt/media/books` to `mediaRoots` in `permissions.nix`, and extend
`test_service_access` (and the `all.sh` permission-check `find` invocations) to cover all four library
directories, or narrow the README/disko-config comment claims to match actual coverage.

## Info

### IN-01: Magic UID in smoketest lacks a source comment

**File:** `scripts/smoketests/media/test-zfs-media.sh:33`

**Issue:** `MEDIA_UID="1100"` is a bare literal. It does correctly match `modules/common/users.nix:43`
today, but nothing in the smoketest ties the two together, so a future change to the media user's uid in
`modules/common/users.nix` would silently desync this test until it starts failing with a confusing
mismatch.

**Fix:** Add a one-line comment pointing at `modules/common/users.nix`, mirroring the existing
`APPROVED_WWN_*` comment style two lines above (`# Approved disk WWNs (hosts/ser8/disko-config.nix, media zpool)`).

---

_Reviewed: 2026-08-25T23:59:37Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_


## Fix Disposition (2026-08-25)

All findings resolved in commit `60b1b3c` ("media: fix nzbget post-processing root and download permissions after NVMe move"), verified live on ser8:

- CR-01 (Blocker): `nzbget-normalize-permissions.sh` `complete_root` default now `/mnt/downloads/complete`; rebuilt script confirmed in the active generation.
- WR-01: stale `/mnt/media/downloads/*` tmpfiles rules removed; new `/mnt/downloads` tree declared `2775` throughout (was `0775` at the top levels — also the root cause of the earlier setgid smoketest failure).
- WR-02: `music`/`books` added to `media-permissions` roots, tmpfiles modes aligned to `2775`, and `test-zfs-media.sh` group-access check now covers all four libraries.
- IN-01: `MEDIA_UID` now documented as pinned in `modules/common/users.nix`.

Post-fix validation: `make build-ser8` clean, `test-zfs-media.sh` 6/6 pass, media suite passes except the pre-existing Bazarr ACL finding (tracked in WINDOWS.md entry 14, outside phase scope).
