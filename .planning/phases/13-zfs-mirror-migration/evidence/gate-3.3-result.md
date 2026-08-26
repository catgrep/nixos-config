# Gate 3.3 Result: Sampled + Metadata Verification

**Result: PASS**

Gate 3.3 (Step 3.3 of `SER8-ZFS-MIRROR-MIGRATION.md`, D-07/D-09) compared
the frozen source (`/mnt/media`) against staging (`/mnt/media-staging`) on
`ser8` using `scripts/sampled-verify.sh`:

- Deterministic per-file sampling (head + tail + one sample per GiB, offsets
  derived from file size) with full sha256 comparison for files under 1 MiB.
- A 100%-coverage metadata-only `rsync -aHAXn --numeric-ids --itemize-changes`
  dry run (size/mtime/mode/uid/gid/type/symlink-target/hardlink-grouping/
  ACL/xattr).
- Exit status derived exclusively from whether either check produced
  non-empty output -- never from a sub-command's own exit code.

## Manifest content (`/persist/zfs-migration/gate-3.3-manifest.txt` on ser8)

```
sampled-verify run: 2026-08-24T18:29:22Z
source: /mnt/media
dest:   /mnt/media-staging

files sampled (content pass): 3478

PASS -- 3478 files sampled, 0 differences
```

## Verification

- `systemctl show gate-33-sampled-verify -p ActiveState,SubState,Result,ExecMainStatus --value`
  returned `inactive` / `dead` / `success` / `0` -- a clean terminal exit.
- The manifest file itself (the authoritative gate per the plan's
  prohibitions) shows zero differences across both the content-sampling
  pass and the metadata-only pass. All 3,478 regular files in the source
  inventory (matching the Plan 13-01 preflight manifest and the Plan 13-03
  structural count) entered the content-sampling pass -- 100% file-level
  coverage. This is distinct from 100% byte-level coverage: files under
  1 MiB were fully hashed, but files 1 MiB and larger were sampled
  (head + tail + ~1 sample per GiB, roughly 0.4% of bytes for the tree as a
  whole) per D-07's explicit residual-risk acceptance (STRIDE T-13-13),
  backstopped by rsync's own in-flight checksums during the original copy,
  ZFS at-rest checksums on `backup/media-staging`, and the first post-cutover
  scrub (Plan 13-07).
- Zero unexplained differences: the "zero unexplained differences" clause of
  `ZFS-01` is satisfied.

## Conclusion

Gate 3.3 produces zero unexplained differences between the frozen source and
staging. Plan 13-05's destructive disk erase may proceed.
