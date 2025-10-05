# Media Storage Architecture - ext4 + MergerFS vs ZFS

## Current Setup

**User confirmed:** "The media drives are mounted. These won't be replicated / backed up."

**Current Configuration:**
- 2x 12TB hard drives
- ext4 filesystem on each
- MergerFS for unified view
- Mounted at `/mnt/disk1`, `/mnt/disk2`, and `/mnt/media` (MergerFS union)

**Status:** Working as designed

## The Question

**User:** "But maybe they should still be ZFS pools, I'm not sure."

Should we migrate the media storage from ext4+MergerFS to ZFS?

## Comparison Analysis

### Current: ext4 + MergerFS

**Architecture:**
```
/mnt/disk1  (12TB ext4)  ─┐
                          ├─→ /mnt/media (MergerFS union = 24TB)
/mnt/disk2  (12TB ext4)  ─┘
```

**Characteristics:**

✅ **Pros:**
- **Simple and stable:** ext4 is mature, well-tested
- **Performance:** Excellent sequential write (important for media downloads)
- **Flexibility:** Easy to add/remove disks from MergerFS pool
- **Low overhead:** No parity calculations, no COW overhead
- **Disk replacement:** Can replace a single disk easily
- **Full capacity:** 24TB usable from 24TB raw
- **Transparent operation:** Files are just files on individual disks

❌ **Cons:**
- **No redundancy:** Single disk failure = data loss on that disk
- **No snapshots:** Can't snapshot before changes
- **No compression:** Wastes space on compressible media
- **No checksumming:** Silent data corruption possible
- **No deduplication:** If you have duplicate files
- **Manual backup required:** Must copy data elsewhere for safety

**Good for:**
- Large media files (movies, TV shows)
- Download-heavy workloads (torrents)
- When capacity > redundancy
- When files are replaceable (can re-download)

### Alternative: ZFS Mirror

**Architecture:**
```
/dev/disk1  ─┐
             ├─→ media pool (ZFS mirror = 12TB usable)
/dev/disk2  ─┘
```

**Characteristics:**

✅ **Pros:**
- **Redundancy:** 1-disk fault tolerance (can lose either disk)
- **Snapshots:** Point-in-time snapshots for backup/rollback
- **Compression:** Can compress media (lz4, zstd)
- **Checksumming:** Detects and corrects data corruption
- **Deduplication:** Optional (but memory-intensive)
- **Integration:** Consistent with backup pool (also ZFS)
- **Self-healing:** Scrubs detect and fix errors
- **Snapshots for backup:** Can zfs send to backup pool

❌ **Cons:**
- **Half capacity:** 12TB usable from 24TB raw (50% overhead)
- **Performance overhead:** COW and checksumming cost CPU/RAM
- **Less flexible:** Harder to add single disk (need pairs for mirror)
- **Memory usage:** ZFS wants ~1GB RAM per TB for ARC
- **Migration complexity:** Need to copy 24TB data somewhere first
- **Overkill?:** For replaceable media files

**Good for:**
- Critical data that can't be lost
- Data that benefits from snapshots
- When you have spare capacity
- Integration with existing ZFS infrastructure

### Alternative: ZFS Stripe (RAID-0)

**Architecture:**
```
/dev/disk1  ─┐
             ├─→ media pool (ZFS stripe = 24TB usable)
/dev/disk2  ─┘
```

**Characteristics:**

✅ **Pros:**
- **Full capacity:** 24TB usable like current setup
- **Snapshots:** Get ZFS snapshot benefits
- **Compression:** Space savings on media
- **Checksumming:** Data integrity verification
- **Integration:** Matches other ZFS pools
- **Performance:** Good sequential throughput

❌ **Cons:**
- **No redundancy:** Worse than current (entire pool fails if 1 disk dies)
- **Migration complexity:** Still need to copy data
- **Performance overhead:** COW writes
- **Less flexible than MergerFS:** Can't easily see which disk has what

**Good for:**
- When you want ZFS features without redundancy
- Replaceable data
- Simpler management than MergerFS

**Not good for:**
- This use case (MergerFS is better for JBOD)

### Alternative: Keep Current + ZFS Snapshots to Backup Pool

**Architecture:**
```
/mnt/disk1 (ext4)  ─┐
                    ├─→ /mnt/media (MergerFS)
/mnt/disk2 (ext4)  ─┘
         │
         ├─→ rsync/borg backup to /mnt/backups (ZFS)
         │
/mnt/backups (ZFS RAID-Z2, 12TB usable)
```

**Characteristics:**

✅ **Pros:**
- **Best of both worlds:** Keep fast ext4+MergerFS, add backup
- **No migration needed:** Keep current working setup
- **Snapshots on backup:** ZFS snapshots of backup data
- **Selective backup:** Only backup important media
- **Incremental:** Only backup changes

❌ **Cons:**
- **More complexity:** Two different systems to manage
- **Backup lag:** Backup isn't real-time
- **Requires automation:** Need backup scripts/services

**Good for:**
- This exact use case!
- Want safety net without full migration

## Workload Analysis

### Media Server Characteristics

**Jellyfin on ser8:**
- Mostly **read-heavy** (streaming to clients)
- Occasional **writes** (new downloads from qBittorrent)
- Large sequential files (movies: 2-20GB, TV: 500MB-2GB)
- Compressibility: Low (video already compressed)

**Download Workflow:**
1. qBittorrent downloads to `/mnt/media/downloads`
2. Sonarr/Radarr moves files to `/mnt/media/tv` or `/mnt/media/movies`
3. Jellyfin streams files to clients

**Data Characteristics:**
- **Replaceable:** Can re-download most media
- **Large files:** Not ideal for ZFS dedup
- **Already compressed:** Little benefit from ZFS compression
- **Append-only:** Rarely modify existing files

**Access Pattern:**
- Sequential reads (streaming)
- Sequential writes (downloads)
- Minimal random I/O

**Conclusion:** This workload favors simple, low-overhead filesystems like ext4.

## Recommendations

### Recommendation 1: Keep Current Setup (RECOMMENDED)

**Why:**
- ✅ Already working well
- ✅ Optimized for the workload (sequential I/O)
- ✅ Full capacity utilization (24TB)
- ✅ Simple, proven, stable
- ✅ Easy disk management with MergerFS
- ✅ No migration needed

**Enhance with:**
- Selective backups to ZFS backup pool
- SMART monitoring for early disk failure detection
- Regular scrubs to check disk health

**Implementation:**
Nothing to do - it's already set up correctly!

**Add monitoring:**
```nix
# In hosts/ser8/configuration.nix
services.smartd = {
  enable = true;
  notifications.wall.enable = true;
  devices = [
    { device = "/dev/disk/by-id/wwn-0x5000c500b56ea81a"; }
    { device = "/dev/disk/by-id/wwn-0x5000c500b3733a87"; }
  ];
};
```

**Add selective backup:**
```nix
# Backup critical media to backup pool
services.borgbackup.jobs.media = {
  paths = [
    "/mnt/media/important"
    "/mnt/media/purchased"
    # Don't backup easily replaceable content
  ];
  repo = "/mnt/backups/borg/media";
  compression = "auto,zstd";
  startAt = "daily";
};
```

### Recommendation 2: Migrate to ZFS Mirror (If Data is Critical)

**Only if:**
- ⚠️ Media library contains irreplaceable content
- ⚠️ Re-downloading would be difficult/impossible
- ⚠️ You value redundancy over capacity
- ⚠️ You're willing to lose 12TB capacity

**Migration steps:**
1. Backup all data to backup pool or external drive
2. Destroy ext4 filesystems
3. Create ZFS mirror
4. Restore data
5. Update NixOS configuration

**Estimated time:** 12-24 hours (copying 24TB twice)

**Not recommended for this use case.**

### Recommendation 3: Hybrid Approach

**If you want ZFS benefits without full migration:**

Convert ONE disk to ZFS for important media:
```
/mnt/disk1 (ext4, 12TB)     → Replaceable media
/mnt/media-zfs (ZFS, 12TB)  → Important media
```

Use MergerFS to combine both:
```nix
fileSystems."/mnt/media" = {
  device = "/mnt/disk1:/mnt/media-zfs";
  fsType = "fuse.mergerfs";
  # MergerFS config as before
};
```

**Benefits:**
- Important files get ZFS protection
- Bulk media stays on fast ext4
- Gradual migration path
- Only need to migrate once

**Complexity:** Higher than keeping current setup

## Decision Matrix

| Criteria | Current (ext4+MergerFS) | ZFS Mirror | ZFS Stripe | Hybrid |
|----------|-------------------------|------------|------------|--------|
| **Capacity** | 24TB | 12TB | 24TB | 18-24TB |
| **Redundancy** | None | 1-disk fault | None | Partial |
| **Performance** | Excellent | Good | Good | Good |
| **Complexity** | Low | Medium | Medium | High |
| **Migration** | None | Full | Full | Partial |
| **Flexibility** | High | Low | Low | Medium |
| **Snapshots** | No | Yes | Yes | Partial |
| **Compression** | No | Yes (minimal benefit) | Yes (minimal benefit) | Partial |
| **Best For** | **This workload** | Critical data | Not recommended | Transitional |

## Final Recommendation

**KEEP CURRENT SETUP** (ext4 + MergerFS) because:

1. **Already working perfectly** for the use case
2. **Optimized for media workloads** (large sequential files)
3. **Full capacity utilization** (24TB usable)
4. **Simple and stable** (no unnecessary complexity)
5. **Media is replaceable** (can re-download from sources)

**Enhancements to add:**

### 1. SMART Monitoring

Detect disk failures early:

```nix
# hosts/ser8/configuration.nix
services.smartd = {
  enable = true;
  autodetect = true;
  notifications = {
    wall.enable = true;
    # Future: add email notifications
  };
};
```

Add Prometheus exporter:

```nix
services.prometheus.exporters.smartctl = {
  enable = true;
  port = 9633;
  devices = [
    "/dev/disk/by-id/wwn-0x5000c500b56ea81a"
    "/dev/disk/by-id/wwn-0x5000c500b3733a87"
  ];
};
```

### 2. Selective Backup Strategy

Backup only irreplaceable content to the backup pool:

```nix
# Use rsync or borg to backup to /mnt/backups
systemd.services.media-backup = {
  description = "Backup critical media to ZFS backup pool";
  startAt = "weekly";

  serviceConfig = {
    Type = "oneshot";
    User = "media";
  };

  script = ''
    # Backup purchased/important media only
    ${pkgs.rsync}/bin/rsync -av --delete \
      /mnt/media/purchased/ \
      /mnt/backups/media-backup/purchased/

    # Create ZFS snapshot after backup
    ${pkgs.zfs}/bin/zfs snapshot backup/backups@media-$(date +%Y%m%d)
  '';
};
```

### 3. Disk Health Dashboard

Add Grafana dashboard showing:
- Disk temperature
- SMART attributes
- Read/write errors
- Reallocated sectors

### 4. Document Replacement Procedure

Create runbook for disk failure:

```markdown
## Disk Failure Recovery

If /mnt/disk1 fails:
1. Unmount /mnt/media (MergerFS)
2. Replace failed disk
3. Format as ext4: `mkfs.ext4 -L media-disk1 /dev/sdX`
4. Mount new disk at /mnt/disk1
5. Re-mount /mnt/media
6. Restore data from backup or re-download
```

## Migration Path (If You Change Your Mind Later)

If you decide to migrate to ZFS later:

**Phase 1:** Add third disk as ZFS
**Phase 2:** Copy data from ext4 to ZFS
**Phase 3:** Remove one ext4 disk, add to ZFS mirror
**Phase 4:** Copy remaining data, remove second ext4 disk
**Phase 5:** Extend ZFS mirror or add as stripe

This provides a gradual migration path without data loss risk.

## Summary

**Current Setup:** ✅ Optimal for this use case
**Recommendation:** Keep it, add monitoring and selective backups
**Alternative:** Only migrate if data becomes irreplaceable
**Migration Complexity:** High (24TB data movement)
**Benefit of Migration:** Low (media is replaceable, already compressed)

**Action Items:**
1. ✅ Verify disks are mounted (user confirmed they are)
2. 📝 Add SMART monitoring
3. 📝 Add disk health Prometheus exporter
4. 📝 Implement selective backup to backup pool
5. 📝 Create Grafana dashboard for disk health
6. 📝 Document disk replacement procedure

**Time to implement enhancements:** 2-3 hours
**Time for full ZFS migration:** 24-48 hours (not recommended)
