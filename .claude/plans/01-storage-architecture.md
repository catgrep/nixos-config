# Storage Architecture - Detailed Analysis & Solutions

## Current State

### Overview
ser8 has three storage layers defined in `hosts/ser8/disko-config.nix`:

1. **✅ rpool (NVMe)** - 1TB, ZFS, Working
2. **❌ backup (4x6TB HDD)** - RAID-Z2, Defined but not mounted
3. **❌ media (2x12TB HDD)** - ext4, Defined but not mounted

### Actual vs Expected

**Expected (from disko-config.nix):**
```
/boot           - ESP partition on NVMe
/ (root)        - rpool/local/root (ephemeral, rolls back on boot)
/nix            - rpool/local/nix (persistent)
/home           - rpool/safe/home (persistent)
/persist        - rpool/safe/persist (persistent)
/mnt/backups    - backup/backups (RAID-Z2 on 4x6TB)
/mnt/disk1      - ext4 on first 12TB drive
/mnt/disk2      - ext4 on second 12TB drive
/mnt/media      - MergerFS union of disk1 + disk2
```

**Actual (runtime):**
```
/boot           ✅ Working
/               ✅ Working (rpool/local/root)
/nix            ✅ Working (rpool/local/nix)
/home           ✅ Working (rpool/safe/home)
/persist        ✅ Working (rpool/safe/persist)
/mnt/backups    ❌ MISSING
/mnt/disk1      ❌ MISSING
/mnt/disk2      ❌ MISSING
/mnt/media      ❌ BROKEN (can't mount non-existent sources)
```

### ZFS Pools

**Current (from user):**
```
NAME                 USED  AVAIL  REFER  MOUNTPOINT
rpool               13.2G   878G    96K  none
rpool/local         12.8G   878G    96K  none
rpool/local/nix     12.8G   878G  12.8G  legacy
rpool/local/root    25.8M   878G  25.8M  legacy
rpool/safe           326M   878G    96K  none
rpool/safe/home      484K   878G   484K  legacy
rpool/safe/persist   326M   878G   326M  legacy
```

**Missing:**
```
backup              ~12TB   ~12TB  (RAID-Z2 of 4x6TB)
backup/backups                     /mnt/backups
```

## Root Cause Analysis

### Why Storage Is Missing

**Disko is an installer tool**, not a runtime configuration manager. It:
1. ✅ Partitions disks during installation
2. ✅ Creates filesystems during installation
3. ✅ Creates ZFS pools during installation
4. ❌ Does NOT ensure pools are imported after reboot
5. ❌ Does NOT ensure filesystems are mounted after reboot

### What Likely Happened

**Scenario A: Never Installed**
- User ran NixOS install with disko-config.nix
- Installation process only formatted the main NVMe disk
- Backup and media disks were never touched
- They still have factory filesystems or old data

**Scenario B: Installed But Not Imported**
- Installation DID create the pools/filesystems
- System rebooted after install
- ZFS pools need explicit `boot.zfs.extraPools` to auto-import
- Media disks need explicit `fileSystems.*` entries for auto-mount

**Scenario C: Disks Not Connected**
- Physical drives aren't connected or have different IDs
- Disko config references wrong disk IDs

## Diagnostic Procedure

### Step 1: Check Physical Disks

```bash
make ssh-ser8

# List all block devices
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT

# List disk IDs (compare to disko-config.nix)
ls -l /dev/disk/by-id/ | grep -E "wwn-0x5000c500"

# Expected disk IDs from disko-config.nix:
# Backup disks:
#   wwn-0x5000c500ea5da96a  (6TB)
#   wwn-0x5000c500e9ec4a9a  (6TB)
#   wwn-0x5000c500e9ec48bb  (6TB)
#   wwn-0x5000c500e9ec29cf  (6TB)
# Media disks:
#   wwn-0x5000c500b56ea81a  (12TB)
#   wwn-0x5000c500b3733a87  (12TB)
```

### Step 2: Check ZFS Pool Status

```bash
# List imported pools
sudo zpool list

# List available but not imported pools
sudo zpool import

# Check if backup pool exists
sudo zpool import | grep -A 10 "pool: backup"
```

### Step 3: Check Filesystem Status

```bash
# Check if media disks have filesystems
sudo blkid | grep -E "wwn-0x5000c500b56ea81a|wwn-0x5000c500b3733a87"

# Check what's mounted
mount | grep -E "/mnt"
```

### Step 4: Check Current Configuration

```bash
# On ser8, check if ZFS knows about backup pool
cat /etc/nixos/configuration.nix | grep -A 5 "extraPools"

# Check fileSystems definitions
cat /etc/nixos/configuration.nix | grep -A 10 "fileSystems"
```

## Solution Paths

### Solution A: Import Existing Pool (if it exists)

**If `zpool import` shows the backup pool:**

1. **Manual import (temporary):**
```bash
sudo zpool import backup
sudo zfs mount backup/backups
```

2. **Make it permanent** - Add to `hosts/ser8/configuration.nix`:

```nix
# After the ZFS services section (around line 95)
boot.zfs.extraPools = [ "backup" ];

# Ensure ZFS services manage it
services.zfs.autoScrub.pools = [ "rpool" "backup" ];
```

3. **Deploy:**
```bash
make test-ser8  # Test first
make switch-ser8  # Make permanent
```

### Solution B: Create Pool from Scratch (if never created)

**If `zpool import` shows nothing and disks are blank:**

1. **Verify disks exist and are empty:**
```bash
lsblk -o NAME,SIZE,FSTYPE /dev/disk/by-id/wwn-0x5000c500ea5da96a
# Should show 6TB with no FSTYPE
```

2. **Create partitions (if needed):**
```bash
# Disko should have done this, but if not:
for disk in \
  /dev/disk/by-id/wwn-0x5000c500ea5da96a \
  /dev/disk/by-id/wwn-0x5000c500e9ec4a9a \
  /dev/disk/by-id/wwn-0x5000c500e9ec48bb \
  /dev/disk/by-id/wwn-0x5000c500e9ec29cf; do
  sudo parted "$disk" --script mklabel gpt
  sudo parted "$disk" --script mkpart primary 0% 100%
done
```

3. **Create ZFS pool:**
```bash
sudo zpool create -f backup raidz2 \
  /dev/disk/by-id/wwn-0x5000c500ea5da96a-part1 \
  /dev/disk/by-id/wwn-0x5000c500e9ec4a9a-part1 \
  /dev/disk/by-id/wwn-0x5000c500e9ec48bb-part1 \
  /dev/disk/by-id/wwn-0x5000c500e9ec29cf-part1
```

4. **Set ZFS properties (match disko-config.nix:244-254):**
```bash
sudo zfs set ashift=12 backup
sudo zfs set acltype=posixacl backup
sudo zfs set compression=lz4 backup
sudo zfs set dnodesize=auto backup
sudo zfs set normalization=formD backup
sudo zfs set relatime=on backup
sudo zfs set xattr=sa backup
sudo zfs set recordsize=1M backup
```

5. **Create dataset:**
```bash
sudo zfs create -o mountpoint=/mnt/backups backup/backups
sudo zfs set dedup=on backup/backups
```

6. **Add to NixOS config** (same as Solution A step 2)

### Solution C: Mount Media Disks

**If disks have no filesystem:**

1. **Create ext4 filesystems:**
```bash
sudo mkfs.ext4 -L media-disk1 /dev/disk/by-id/wwn-0x5000c500b56ea81a-part1
sudo mkfs.ext4 -L media-disk2 /dev/disk/by-id/wwn-0x5000c500b3733a87-part1
```

2. **Add explicit mount configuration** to `hosts/ser8/configuration.nix`:

```nix
# Add after the MergerFS section (around line 119)
fileSystems."/mnt/disk1" = {
  device = "/dev/disk/by-label/media-disk1";
  fsType = "ext4";
  options = [
    "defaults"
    "nofail"
    "noatime"
  ];
};

fileSystems."/mnt/disk2" = {
  device = "/dev/disk/by-label/media-disk2";
  fsType = "ext4";
  options = [
    "defaults"
    "nofail"
    "noatime"
  ];
};
```

**Note:** The disko config defines these mounts, but they need to be explicitly referenced in the main configuration or disko needs to be re-run.

3. **Deploy and verify:**
```bash
make test-ser8
make ssh-ser8
ls -la /mnt/disk1 /mnt/disk2
mount | grep /mnt
```

## MergerFS Fix

Once `/mnt/disk1` and `/mnt/disk2` are mounted, MergerFS should work automatically because it's already configured at `hosts/ser8/configuration.nix:106-119`.

**Verify:**
```bash
sudo systemctl status mnt-media.mount
mount | grep mergerfs
ls -la /mnt/media
```

## Samba Fix

Once storage is mounted, Samba should work automatically because it's configured at `hosts/ser8/samba.nix:66-94`.

**Verify:**
```bash
sudo systemctl status smbd
smbclient -L //localhost -U bdhill
```

From macOS:
```bash
smbutil view //ser8.local
# Then in Finder: smb://media@ser8.local
```

## Testing Checklist

After implementing fixes:

```bash
# On ser8
make ssh-ser8

# ✓ Check ZFS pools
sudo zpool list
# Should show: rpool, backup

# ✓ Check ZFS datasets
sudo zfs list
# Should include: backup/backups

# ✓ Check mounts
mount | grep -E "(zfs|mergerfs)"
# Should show: backup/backups on /mnt/backups
#              mergerfs on /mnt/media

# ✓ Check disk space
df -h | grep /mnt
# Should show:
#   /mnt/backups  ~12TB  (RAID-Z2)
#   /mnt/disk1    ~12TB
#   /mnt/disk2    ~12TB
#   /mnt/media    ~24TB  (MergerFS)

# ✓ Check Samba
sudo systemctl status smbd
smbclient -L //localhost -U media
# Enter password from SOPS

# ✓ Check permissions
ls -la /mnt/backups
ls -la /mnt/media
# Should be owned by appropriate users

# ✓ Test write access
sudo -u media touch /mnt/media/test.txt
sudo -u bdhill touch /mnt/backups/test.txt
```

## Rollback Plan

If something goes wrong:

1. **For ZFS pool import issues:**
```bash
sudo zpool export backup
make rollback-ser8
```

2. **For filesystem mount issues:**
```bash
sudo umount /mnt/disk1
sudo umount /mnt/disk2
sudo umount /mnt/media
make rollback-ser8
```

3. **For catastrophic failures:**
```bash
# Boot into previous generation from GRUB menu
# ZFS will rollback root automatically
# Then investigate what went wrong
```

## Long-term Improvements

### 1. Add Storage Health Monitoring

Add to `modules/servers/monitoring.nix`:

```nix
# ZFS exporter for Prometheus
services.prometheus.exporters.zfs = {
  enable = true;
  port = 9134;
  pools = [ "rpool" "backup" ];
};
```

### 2. Automated Snapshots for Backup Pool

Add to `hosts/ser8/configuration.nix`:

```nix
services.zfs.autoSnapshot = {
  enable = true;
  flags = "-k -p --utc";
  frequent = 4;  # 15-minute intervals
  hourly = 24;
  daily = 7;
  weekly = 4;
  monthly = 12;
};
```

### 3. Backup Replication

Consider adding ZFS send/receive to offsite backup:

```nix
# Future: replicate backup/backups to cloud storage
services.syncoid = {
  enable = true;
  # ... configuration for ZFS replication
};
```

### 4. SMART Monitoring

Monitor disk health:

```nix
services.smartd = {
  enable = true;
  notifications.wall.enable = true;
  # Add email notifications once configured
};
```

## Files to Modify

### hosts/ser8/configuration.nix

Add after line 103 (ZFS services):
```nix
boot.zfs.extraPools = [ "backup" ];
```

Add after line 119 (MergerFS):
```nix
fileSystems."/mnt/disk1" = {
  device = "/dev/disk/by-label/media-disk1";
  fsType = "ext4";
  options = [ "defaults" "nofail" "noatime" ];
};

fileSystems."/mnt/disk2" = {
  device = "/dev/disk/by-label/media-disk2";
  fsType = "ext4";
  options = [ "defaults" "nofail" "noatime" ];
};
```

## Summary

**Problem:** ~36TB of defined storage not accessible
**Root Cause:** Disko definitions not translated to runtime configuration
**Solution:** Add explicit pool import and filesystem mount configs
**Risk Level:** Medium (mostly configuration, physical disks should be safe)
**Estimated Time:** 2-4 hours (investigation + implementation + testing)
