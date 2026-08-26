# Scrub Result and Staging-Destroy Status

## Scrub result: PASS

Step 5.5 of `SER8-ZFS-MIRROR-MIGRATION.md` (Plan 13-07, Task 2) launched the first scrub of the
restored `media` mirror as a detached `systemd-run` unit (`media-scrub`) so it would survive the
executor's SSH session ending, per D-12/D-13. The unit finished early relative to its initial
throughput-based estimate (~11.7h estimated at launch; 7h42m32s actual).

Independently verified directly against ser8 (not trusted from any relayed report alone):

```
$ zpool status media
  pool: media
 state: ONLINE
  scan: scrub repaired 0B in 07:42:32 with 0 errors on Tue Aug 25 15:59:52 2026
config:

	NAME                              STATE     READ WRITE CKSUM
	media                             ONLINE       0     0     0
	  mirror-0                        ONLINE       0     0     0
	    wwn-0x5000c500b56ea81a-part1  ONLINE       0     0     0
	    wwn-0x5000c500b3733a87-part1  ONLINE       0     0     0

errors: No known data errors

$ systemctl show media-scrub -p ActiveState,SubState,ExecMainStatus,Result --value
inactive
dead
success
0
```

- **Repaired:** `0B` — no data required reconstruction from the mirror's redundant copy.
- **Errors:** `0` across the scan; `errors: No known data errors` in the pool-wide summary.
- **Mirror membership:** both approved WWN members (`wwn-0x5000c500b56ea81a`,
  `wwn-0x5000c500b3733a87`) remained `ONLINE` throughout, `0 0 0` read/write/checksum counters.
- **Unit terminal state:** `ActiveState=inactive`, `SubState=dead`, `Result=success`,
  `ExecMainStatus=0` — a clean exit, not a crash or an externally-killed unit.

This scrub is the last independent, end-to-end integrity check on the restored mirror,
complementing the intrinsic block-checksum guarantee of the Plan 13-06 `zfs send/recv` restore
(D-08). **ZFS-03 is satisfied**: the restore verified intrinsically checksum-clean at receive time
(Plan 13-06), and this scrub independently confirms zero data errors and zero required repairs
across the full 5.24T dataset.

## Staging destroy: executed by the operator directly, not by this plan (D-18)

Mid-plan, the operator decided the destroy of `backup/media-staging` would not be executed by
the plan's automated flow at all. This decision, and the reasoning behind it, is recorded in
`.planning/phases/13-zfs-mirror-migration/deferred-items.md`
("13-07 Step 6.2: `backup/media-staging` destroy deferred to the operator (D-18)").

The operator then ran the destroy themselves, independently, after reviewing the scrub result
above directly against ser8's own `zpool status` output:

```
$ zpool history backup | tail -3
2026-08-24.00:35:43 zfs create -o mountpoint=/mnt/media-staging -o compression=lz4 -o recordsize=1M -o atime=off -o dedup=off -o com.sun:auto-snapshot=false backup/media-staging
2026-08-24.15:27:54 zfs snapshot backup/media-staging@verified
2026-08-25.16:39:47 zfs destroy -r backup/media-staging

$ zfs list -H -o name backup/media-staging
cannot open 'backup/media-staging': dataset does not exist

$ zfs list -o name,used,avail backup
NAME     USED  AVAIL
backup   364G  10.1T
```

The destroy ran at 2026-08-25 16:39:47 PDT — after the scrub completed (15:59:52 PDT) and after
the operator's own review, using the exact sanctioned command (`zfs destroy -r`, targeting only
`backup/media-staging`, matching the migration doc's explicit ban on a recursive filesystem
delete through the mountpoint). Capacity returned to the backup pool (10.1T available, up from
the ~5.05T-consumed state). `backup/media-staging` is not mounted (confirmed via `mount`); the
camera datasets (`backup/cameras`, `backup/cameras/recordings`, `backup/cameras/clips`) are
unaffected; the `media` mirror remains the live, healthy, sole source for `/mnt/media`.

This plan's original Task 3 (observe the cutover), Task 4 (destroy approval checkpoint), and
Task 5 (destroy execution) were still not executed by the plan's own automated flow — the
operator's independent action superseded them, exactly as decided mid-plan. See
`deferred-items.md` for the full rationale.

## D-18 gate status

D-18's trigger condition — "first clean scrub AND Step 5.4 application tests passed" — was fully
satisfied before the destroy ran (this scrub, plus Plan 13-06's Step 5.4 validation). The gate
itself (the actual destroy decision and execution) was satisfied by the operator taking direct,
personal ownership of the one-way action rather than delegating either the approval or the
execution to the executor. This is a stricter fulfillment of D-18's "separately approved"
requirement, not a weaker one — approval and execution lived in the same hands with no
delegation gap, and the destroy only happened after the scrub evidence was available.
