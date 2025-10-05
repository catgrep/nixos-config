# Implementation Roadmap - Prioritized Action Plan

## Overview

This roadmap provides a prioritized, step-by-step plan to address all identified architectural gaps. Each item includes:
- Specific files to modify
- Commands to run
- Testing procedures
- Estimated time
- Risk level

## Priority 1: CRITICAL (Do Immediately)

### 1.1 Investigate ser8 Storage State

**Goal:** Determine actual state of storage devices and ZFS pools

**Time:** 30 minutes
**Risk:** None (read-only operations)

**Steps:**

```bash
# 1. Connect to ser8
make ssh-ser8

# 2. Check physical disks
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT

# 3. List disk IDs and compare to disko-config
ls -l /dev/disk/by-id/ | grep -E "wwn-0x5000c500"

# 4. Check ZFS pools
sudo zpool list
sudo zpool import  # List pools available but not imported

# 5. Check if backup pool exists
sudo zpool import | grep -A 10 "pool: backup"

# 6. Check current mounts
mount | grep /mnt
df -h | grep /mnt

# 7. Document findings
# Take screenshots or copy output to ./backups/ser8-disk-audit-$(date +%Y%m%d).txt
```

**Expected Outcomes:**
- **Scenario A:** Backup pool exists but not imported → Proceed to 1.2A
- **Scenario B:** Backup pool never created → Proceed to 1.2B
- **Scenario C:** Media disks mounted but not in fstab → Proceed to 1.3

**Deliverable:** Text file documenting disk state

---

### 1.2A Import Existing Backup Pool (if exists)

**Time:** 1 hour
**Risk:** Low (import is non-destructive)

**Prerequisites:** 1.1 determined pool exists

**Steps:**

1. **Manual import (temporary test):**

```bash
make ssh-ser8

# Import the pool
sudo zpool import backup

# Verify it imported correctly
sudo zpool status backup
sudo zfs list -r backup

# Check mountpoint
ls -la /mnt/backups
```

2. **Make permanent by updating config:**

**File:** `hosts/ser8/configuration.nix`

**Add after line 103** (after ZFS services):

```nix
# Import backup pool automatically on boot
boot.zfs.extraPools = [ "backup" ];
```

**Update line 95** (ZFS auto-scrub) to include backup pool:

```nix
services.zfs = {
  autoScrub = {
    enable = true;
    pools = [ "rpool" "backup" ];  # Add "backup" here
    interval = "weekly";
  };
  # ... rest of config
};
```

3. **Test deployment:**

```bash
# Validate configuration
make check

# Build configuration
make build-ser8

# Test without making permanent
make test-ser8

# SSH in and verify
make ssh-ser8
sudo zpool list
# Should show both rpool and backup

# If good, make permanent
make switch-ser8
```

4. **Reboot test:**

```bash
make ssh-ser8
sudo reboot

# Wait for reboot, then check
make ssh-ser8
sudo zpool list
sudo zfs list
mount | grep backup
```

**Success Criteria:**
- [ ] `zpool list` shows both rpool and backup
- [ ] `backup` pool auto-imports on boot
- [ ] `/mnt/backups` is mounted
- [ ] Samba share for backups becomes accessible

---

### 1.2B Create Backup Pool from Scratch (if never created)

**Time:** 2-3 hours
**Risk:** Medium (destructive to disks, but they should be empty)

**Prerequisites:**
- 1.1 determined pool doesn't exist
- Verified disks are empty or data is backed up

**Steps:**

1. **Verify disks are empty:**

```bash
make ssh-ser8

# Check each backup disk
for id in ea5da96a e9ec4a9a e9ec48bb e9ec29cf; do
  echo "=== Disk wwn-0x5000c500$id ==="
  sudo blkid /dev/disk/by-id/wwn-0x5000c500$id* || echo "No filesystem"
done

# If they have data, STOP and back it up first
```

2. **Create partitions (if not already done):**

```bash
# Check if partitions exist
ls -la /dev/disk/by-id/wwn-0x5000c500ea5da96a*

# If no -part1, create partitions
for id in ea5da96a e9ec4a9a e9ec48bb e9ec29cf; do
  disk="/dev/disk/by-id/wwn-0x5000c500$id"
  sudo parted "$disk" --script mklabel gpt
  sudo parted "$disk" --script mkpart primary 0% 100%
  sudo parted "$disk" --script set 1 zfs on
done
```

3. **Create ZFS pool:**

```bash
sudo zpool create -f backup raidz2 \
  /dev/disk/by-id/wwn-0x5000c500ea5da96a-part1 \
  /dev/disk/by-id/wwn-0x5000c500e9ec4a9a-part1 \
  /dev/disk/by-id/wwn-0x5000c500e9ec48bb-part1 \
  /dev/disk/by-id/wwn-0x5000c500e9ec29cf-part1

# Verify creation
sudo zpool status backup
```

4. **Set ZFS properties (match disko-config.nix:240-254):**

```bash
sudo zfs set ashift=12 backup
sudo zfs set acltype=posixacl backup
sudo zfs set compression=lz4 backup
sudo zfs set dnodesize=auto backup
sudo zfs set normalization=formD backup
sudo zfs set relatime=on backup
sudo zfs set xattr=sa backup
sudo zfs set recordsize=1M backup
sudo zfs set autotrim=on backup
```

5. **Create dataset:**

```bash
sudo zfs create -o mountpoint=/mnt/backups backup/backups
sudo zfs set dedup=on backup/backups

# Verify
sudo zfs list -r backup
ls -la /mnt/backups
```

6. **Set permissions:**

```bash
sudo chown bdhill:users /mnt/backups
sudo chmod 755 /mnt/backups
```

7. **Add to NixOS config** (same as 1.2A step 2)

8. **Deploy and test** (same as 1.2A step 3-4)

**Success Criteria:**
- [ ] Pool created with RAID-Z2 (4 disks, 2 parity)
- [ ] `zpool status backup` shows healthy
- [ ] Dataset mounted at `/mnt/backups`
- [ ] Permissions correct
- [ ] Auto-imports on boot

---

### 1.3 Verify/Fix Media Disk Mounts

**Time:** 1 hour
**Risk:** Low (if disks are already mounted, just documenting)

**Note from user:** "The media drives are mounted. These won't be replicated / backed up."

**Steps:**

1. **Check current state:**

```bash
make ssh-ser8

# Check if /mnt/disk1 and /mnt/disk2 exist
ls -la /mnt/disk1 /mnt/disk2

# Check if they're mounted
mount | grep /mnt/disk

# Check MergerFS
mount | grep mergerfs
ls -la /mnt/media
```

2. **If mounted but not in config, document how they're mounted:**

```bash
# Check systemd mounts
systemctl list-units --type=mount | grep mnt

# Check /etc/fstab (shouldn't have anything in NixOS, but check)
cat /etc/fstab
```

3. **Verify configuration matches reality:**

Check `hosts/ser8/configuration.nix:106-119` - MergerFS is configured.

**If disks are mounted but missing from config**, they might be:
- Manually mounted (will disappear on reboot)
- Configured elsewhere in NixOS config

Search for disk mounts:

```bash
# On local machine
cd /Users/bobby/github/catgrep/nixos-config
grep -r "disk1\|disk2" hosts/ser8/
```

4. **If not in config, add explicit mounts:**

**File:** `hosts/ser8/configuration.nix`

**Add after line 119** (after MergerFS):

```nix
# Explicit mounts for media disks
# (Disko defines these, but making them explicit for clarity)
fileSystems."/mnt/disk1" = {
  device = "/dev/disk/by-id/wwn-0x5000c500b56ea81a-part1";
  fsType = "ext4";
  options = [ "defaults" "nofail" "noatime" ];
};

fileSystems."/mnt/disk2" = {
  device = "/dev/disk/by-id/wwn-0x5000c500b3733a87-part1";
  fsType = "ext4";
  options = [ "defaults" "nofail" "noatime" ];
};
```

**OR if using labels:**

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

5. **Deploy and verify:**

```bash
make test-ser8

make ssh-ser8
mount | grep /mnt
df -h | grep /mnt

# Verify MergerFS and Samba
ls -la /mnt/media
smbclient -L //localhost -U media
```

**Success Criteria:**
- [ ] `/mnt/disk1` and `/mnt/disk2` mounted
- [ ] `/mnt/media` (MergerFS) working
- [ ] Samba share accessible
- [ ] Mounts survive reboot

---

### 1.4 Test Samba Shares

**Time:** 30 minutes
**Risk:** None (testing only)

**Prerequisites:** 1.2 or 1.3 completed (storage mounted)

**Steps:**

1. **From ser8:**

```bash
make ssh-ser8

# Check Samba status
sudo systemctl status smbd

# List shares
smbclient -L //localhost -N

# Test media share (guest access)
smbclient //localhost/media -N
# Try to list files
smb: \> ls
smb: \> quit

# Test backups share (requires authentication)
smbclient //localhost/backups -U bdhill
# Enter password from SOPS
smb: \> ls
smb: \> quit
```

2. **From macOS:**

```bash
# View shares
smbutil view //ser8.local

# Connect via Finder
# Go > Connect to Server (Cmd+K)
# smb://media@ser8.local
```

3. **Test write access:**

```bash
# From ser8
sudo -u media touch /mnt/media/test-write.txt
ls -la /mnt/media/test-write.txt

# From macOS (via Finder)
# Create a file in the media share
# Verify it appears on ser8
```

**Success Criteria:**
- [ ] Samba service running
- [ ] Both shares visible
- [ ] Media share accessible (guest)
- [ ] Backups share accessible (authenticated)
- [ ] Write access works
- [ ] Files visible from macOS

---

## Priority 2: HIGH (This Week)

### 2.1 Add Media Service Secrets

**Time:** 1 hour
**Risk:** Low

**Steps:**

1. **Retrieve API keys:**

```bash
make ssh-ser8

# Sonarr
curl -s http://localhost:8989/api/v3/system/status | jq -r '.apiKey'

# Radarr
curl -s http://localhost:7878/api/v3/system/status | jq -r '.apiKey'

# Prowlarr
curl -s http://localhost:9696/api/v1/system/status | jq -r '.apiKey'

# qBittorrent: check web UI or config file
```

2. **Add to SOPS:**

```bash
# On local machine
make sops-edit-ser8
```

Add these keys to `secrets/ser8.yaml`:

```yaml
sonarr_api_key: "YOUR_API_KEY_HERE"
radarr_api_key: "YOUR_API_KEY_HERE"
prowlarr_api_key: "YOUR_API_KEY_HERE"
qbittorrent_web_password: "YOUR_PASSWORD_HERE"
```

3. **Update module configurations:**

Will create detailed module updates in separate task.

---

### 2.2 Enhance Monitoring (Exporters + Prometheus)

**Time:** 3-4 hours
**Risk:** Low

See `03-monitoring-secrets.md` for detailed implementation.

**Steps:**
1. Add qBittorrent, Sonarr, Radarr, Prowlarr exporters
2. Add AdGuard exporter
3. Add NordVPN status monitoring
4. Update Prometheus scrape configs
5. Deploy and verify

---

### 2.3 Add Grafana Dashboards

**Time:** 2-3 hours
**Risk:** Low

See `03-monitoring-secrets.md` for dashboard recommendations.

**Steps:**
1. Choose provisioning strategy (import vs git)
2. Add Node Exporter dashboard
3. Add ZFS dashboard
4. Create custom media/VPN dashboards
5. Deploy and verify

---

### 2.4 Improve firebat Impermanence (Incremental)

**Time:** 1 hour
**Risk:** Low (doesn't require ZFS migration)

**File:** `hosts/firebat/impermanence.nix`

Enhance to persist critical service data (even on ext4):

```nix
environment.persistence."/persist" = {
  hideMounts = true;
  directories = [
    "/var/log"
    "/var/lib/nixos"
    "/var/lib/systemd/coredump"
    "/var/lib/grafana"
    "/var/lib/prometheus2"
    "/var/lib/caddy"
    "/var/lib/acme"
  ];
  files = [
    "/etc/machine-id"
  ];
};
```

Deploy: `make switch-firebat`

---

## Priority 3: IMPORTANT (This Month)

### 3.1 Plan firebat ZFS Migration

**Time:** Planning: 2-3 hours, Execution: 3-5 hours
**Risk:** Medium (requires downtime and reinstall)

See `02-firebat-impermanence.md` for full migration plan.

**Phases:**
1. Backup Grafana dashboards
2. Test new disko-config in VM (optional but recommended)
3. Schedule maintenance window
4. Perform clean reinstall with ZFS
5. Restore services and verify

---

### 3.2 Implement Prometheus Alerting

**Time:** 2-3 hours
**Risk:** Low

Add alerting rules for:
- Host down
- VPN disconnected
- Disk space low
- ZFS pool degraded

See `03-monitoring-secrets.md` for alerting configuration.

---

### 3.3 Consider Media Storage Architecture

**Time:** Research: 1-2 hours, Implementation: 4-6 hours (if changing)
**Risk:** High (if migrating existing data)

**Current:** 2x12TB ext4 with MergerFS
**Alternative:** ZFS pool (mirror or stripe)

**Trade-offs:**

| Aspect | Current (ext4 + MergerFS) | ZFS Pool |
|--------|---------------------------|----------|
| **Redundancy** | None (JBOD) | Can use mirror/RAID-Z |
| **Snapshots** | None | Built-in ZFS snapshots |
| **Compression** | None | ZFS compression |
| **Flexibility** | Easy to add disks | Harder to expand |
| **Performance** | Good for streaming | Better for random I/O |
| **Data Safety** | Single disk failure = data loss | Mirror = 1 disk redundancy |

**Recommendation:**

**Option A: Keep ext4 + MergerFS (current)**
- ✅ Already working
- ✅ Easy to manage
- ✅ Good for write-heavy media workloads
- ⚠️ No redundancy
- ⚠️ No snapshots

**Option B: Migrate to ZFS mirror**
```nix
# Create mirror of 2x12TB = 12TB usable
sudo zpool create media mirror \
  /dev/disk/by-id/wwn-0x5000c500b56ea81a-part1 \
  /dev/disk/by-id/wwn-0x5000c500b3733a87-part1
```
- ✅ 1-disk fault tolerance
- ✅ Snapshots for backup
- ✅ Compression
- ⚠️ Lose half capacity
- ⚠️ Migration complexity

**Option C: Keep current, add backup strategy**
- Keep ext4 + MergerFS
- Add ZFS send/receive to backup pool
- Best of both worlds but more complex

**Decision needed from user** - document pros/cons in separate plan.

---

## Priority 4: NICE TO HAVE (Long-term)

### 4.1 Implement Backup Automation

**Time:** 4-6 hours
**Risk:** Low

- ZFS snapshot automation (already configured)
- Replication to backup pool
- Offsite backup (rsync/restic to cloud)

---

### 4.2 Add Home Assistant Module

**Time:** 8-10 hours
**Risk:** Low

Complete the planned `modules/automation/home-assistant.nix`

---

### 4.3 Add Gerrit Module

**Time:** 6-8 hours
**Risk:** Low

Complete the planned `modules/development/gerrit.nix`

---

### 4.4 Create VM Test Environment

**Time:** 4-6 hours
**Risk:** None

- Create NixOS VM definitions
- Test configurations before deploying to production
- Useful for testing firebat migration

---

### 4.5 Investigate Overlay Pattern Usage

**Time:** 2-3 hours research
**Risk:** None (research only)

**User noted:** "Another thing to consider would be using `overlays` nix pattern"

**Research topics:**
- When to use overlays vs modules
- Package customization patterns
- Overlay best practices for this repo

**Potential use cases in this repo:**
- Custom package versions for media services
- Patched packages for specific needs
- Package overrides for optimization

**Create:** `.claude/plans/05-overlay-pattern-analysis.md`

---

## Summary Timeline

**Week 1 (This Week):**
- ✅ Priority 1: Fix storage (1-2 days)
- ✅ Priority 2.1: Add secrets (1-2 hours)
- ✅ Priority 2.2-2.3: Monitoring improvements (1 day)

**Week 2:**
- Priority 2.4: Improve firebat persistence
- Priority 3.3: Decide on media storage architecture

**Week 3-4:**
- Priority 3.1: Plan and execute firebat ZFS migration
- Priority 3.2: Implement alerting

**Month 2+:**
- Priority 4: Long-term improvements

## Files Changed Summary

**Priority 1:**
- `hosts/ser8/configuration.nix` - Add extraPools, explicit mounts

**Priority 2:**
- `secrets/ser8.yaml` - Add API keys
- `modules/media/*.nix` - Add exporters
- `modules/gateway/prometheus.nix` - Add scrape configs
- `modules/gateway/grafana.nix` - Add dashboards
- `hosts/firebat/impermanence.nix` - Enhance persistence

**Priority 3:**
- `hosts/firebat/disko-config.nix` - ZFS configuration
- `modules/gateway/prometheus.nix` - Add alerting rules

## Risk Mitigation

**Before any changes:**
1. Run `make check` to validate
2. Run `make build-HOST` to verify builds
3. Use `make test-HOST` before `make switch-HOST`
4. Always have rollback plan

**For critical changes:**
1. Backup data first
2. Test in VM if possible
3. Schedule during low-usage times
4. Have physical/console access ready

**Rollback procedures:**
- Boot previous generation from GRUB
- `make rollback-HOST`
- For ZFS: pool export/import
- Keep NixOS installer USB handy
