# Step 0.5: Source Inventory Manifest Summary

Recorded 2026-08-24 during Plan 13-01, Task 4.

## Manifest location

`/persist/zfs-migration/media-inventory-preflight.tsv` on ser8 (impermanence-persisted, outside `/mnt/media` and outside any staging dataset).

Columns: type, size, uid, gid, mode, mtime (epoch), inode, path — produced by:

```
find /mnt/media -xdev -printf '%y\t%s\t%U\t%G\t%m\t%T@\t%i\t%p\n'
```

## Totals

| Metric | Value |
|---|---|
| Manifest entries (files + directories) | 3,809 |
| Regular files (`find -type f`) | 3,478 |
| Apparent bytes (`du -sb --apparent-size /mnt/media`) | 5,727,815,651,227 |
| Manifest byte-column sum (regular files only) | 5,727,815,651,130 |
| Reconciliation delta | 97 bytes (~0.0000017%) — within rounding, expected from a live filesystem sampled a few seconds apart across `find` and `du` |

## Reconciliation with df

`df -B1 /mnt/media` reported `5,727,839,801,344` bytes used (filesystem block accounting) at the time of the Task 2 live-state check a few minutes earlier — consistent with the `du --apparent-size` figure above (block accounting vs. logical byte accounting on the same live, still-in-use filesystem).

## Cross-reference: media-usage drift vs. the original 2026-08-13 doc snapshot

The doc's §Verified State at Handoff recorded `7,788,285,710,336` bytes used. The current total (`~5.73 TB`) is about `2.06 TB` lower. See the plan's SUMMARY.md for the full drift discussion (Task 2 finding); the leading explanation is Phase 12's qBittorrent/wgnord stack deletion, which included removal of `/persist/var/lib/qbittorrent` and associated torrent-side files under `/mnt/media/downloads`.
