# firebat Impermanence Migration Plan

## Current State

### Disk Configuration
`hosts/firebat/disko-config.nix`:
- Simple ext4 on single NVMe SSD
- No ZFS, no impermanence pattern
- Traditional Linux filesystem layout

### Persistence Configuration
`hosts/firebat/impermanence.nix`:
- Only 27 lines (vs ser8's 156 lines)
- Only persists SSH host keys
- Missing critical service state

### Services on firebat
- **Caddy** - Reverse proxy (SSL certs need persistence)
- **Grafana** - Dashboards and database
- **Prometheus** - Time-series database (lots of data)
- **Node Exporter** - Metrics collection

## The Gap

### What Should Be Persisted (Currently Isn't)

**Critical Service Data:**
- `/var/lib/grafana` - Dashboards, users, database
- `/var/lib/prometheus2` - Metrics database (~GBs of data)
- `/var/lib/caddy` - Certificates, ACME state
- `/var/lib/acme` - Let's Encrypt certificates (if used)

**System State:**
- `/var/log` - System and service logs
- `/var/lib/systemd` - Systemd state
- `/etc/machine-id` - Machine identification

**Without these:**
- Grafana dashboards reset on every boot
- Prometheus loses all historical metrics
- Caddy has to re-request certificates
- Service configuration drifts

## Goal: "Erase Your Darlings" on firebat

Mirror ser8's pattern:
- Root filesystem rolls back on boot (stateless)
- Critical data explicitly persisted in ZFS datasets
- Clean separation of ephemeral vs persistent

## Migration Strategy

### Option A: Clean Reinstall (RECOMMENDED)

**Pros:**
- ✅ Clean, matches ser8 architecture exactly
- ✅ No risk of partial migration state
- ✅ Tests disko-config from scratch

**Cons:**
- ❌ Requires downtime
- ❌ Need to backup Grafana dashboards and Prometheus data
- ❌ More disruptive

**Steps:**
1. Export critical data (Grafana dashboards, Prometheus config)
2. Boot from NixOS installer
3. Run disko with new ZFS-based config
4. Deploy NixOS configuration
5. Import Grafana dashboards, Prometheus will rebuild metrics

### Option B: Live Migration (ADVANCED)

**Pros:**
- ✅ Less downtime
- ✅ Can preserve data in place

**Cons:**
- ❌ More complex
- ❌ Higher risk of errors
- ❌ Requires careful execution

**Steps:**
1. Create ZFS pool on free space
2. Copy data to ZFS datasets
3. Update bootloader and config
4. Reboot into ZFS root
5. Remove old ext4 partition

### Option C: Deferred (Keep ext4, improve persistence)

**Pros:**
- ✅ Least disruptive
- ✅ Can do immediately

**Cons:**
- ❌ Doesn't achieve architectural consistency
- ❌ Still missing impermanence benefits
- ❌ Technical debt remains

**Steps:**
1. Enhance `impermanence.nix` to persist service data
2. Keep ext4 for now
3. Plan ZFS migration later

## Recommended Approach: Option A (Clean Reinstall)

### Pre-Migration Checklist

**1. Backup Critical Data**

```bash
make ssh-firebat

# Export Grafana dashboards
sudo grafana-cli admin export /tmp/grafana-backup.json

# Backup Prometheus config (already in NixOS config)
# Data will be rebuilt from node exporters

# Backup any custom Caddy config (should be in NixOS config)

# Copy backups to local machine
scp bdhill@firebat.local:/tmp/grafana-backup.json ./backups/
```

**2. Document Current State**

```bash
# List all services
sudo systemctl list-units --type=service --state=running

# Check disk usage
df -h

# Document mounted filesystems
mount

# Check Caddy certificates
sudo ls -la /var/lib/caddy/

# Note current IPs and DNS
ip addr
cat /etc/resolv.conf
```

**3. Prepare New Configuration**

Create new `hosts/firebat/disko-config.nix` (see below)

### New Disko Configuration

`hosts/firebat/disko-config.nix`:

```nix
# SPDX-License-Identifier: GPL-3.0-or-later
#
# ZFS-based configuration for firebat gateway
# Implements "Erase Your Darlings" pattern like ser8

{ ... }:
{
  disko.devices = {
    disk = {
      main = {
        type = "disk";
        device = "/dev/disk/by-id/nvme-NVME_SSD_512GB_D5BIRL16301155";
        content = {
          type = "gpt";
          partitions = {
            ESP = {
              size = "512M";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = [ "umask=0077" ];
              };
            };
            zfs = {
              end = "-8G";
              content = {
                type = "zfs";
                pool = "rpool";
              };
            };
            swap = {
              size = "100%";
              content = {
                type = "swap";
                randomEncryption = true;
              };
            };
          };
        };
      };
    };

    zpool = {
      rpool = {
        type = "zpool";
        mode = "";
        options = {
          ashift = "12";
          autotrim = "on";
        };
        rootFsOptions = {
          acltype = "posixacl";
          canmount = "off";
          compression = "lz4";
          dnodesize = "auto";
          mountpoint = "none";
          normalization = "formD";
          relatime = "on";
          xattr = "sa";
        };
        datasets = {
          # Blank root dataset
          "local" = {
            type = "zfs_fs";
            options = {
              mountpoint = "none";
            };
          };
          # Root filesystem - gets rolled back on boot
          "local/root" = {
            type = "zfs_fs";
            options = {
              mountpoint = "legacy";
            };
            mountpoint = "/";
            postCreateHook = ''
              zfs snapshot rpool/local/root@blank
            '';
          };
          # Nix store - persistent across reboots
          "local/nix" = {
            type = "zfs_fs";
            options = {
              mountpoint = "legacy";
              atime = "off";
            };
            mountpoint = "/nix";
          };
          # Persistent data parent
          "safe" = {
            type = "zfs_fs";
            options = {
              mountpoint = "none";
            };
          };
          # Home directories - persistent
          "safe/home" = {
            type = "zfs_fs";
            options = {
              mountpoint = "legacy";
            };
            mountpoint = "/home";
          };
          # System state persistence
          "safe/persist" = {
            type = "zfs_fs";
            options = {
              mountpoint = "legacy";
            };
            mountpoint = "/persist";
          };
        };
      };
    };
  };
}
```

### Enhanced Impermanence Configuration

`hosts/firebat/impermanence.nix`:

```nix
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Impermanence configuration for firebat gateway
# Defines what persists across reboots when root is rolled back

{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:

{
  imports = [ inputs.impermanence.nixosModules.impermanence ];

  # Enable impermanence
  environment.persistence."/persist" = {
    hideMounts = true;

    directories = [
      # System essentials
      "/var/log"
      "/var/lib/nixos"
      "/var/lib/systemd/coredump"

      # Grafana - dashboards, users, database
      "/var/lib/grafana"

      # Prometheus - time-series database
      # This can be large, but historical data is valuable
      "/var/lib/prometheus2"

      # Caddy - certificates and state
      "/var/lib/caddy"

      # ACME/Let's Encrypt certificates (if used)
      "/var/lib/acme"

      # NetworkManager (if used)
      # "/etc/NetworkManager/system-connections"
    ];

    files = [
      # Machine ID (required for systemd)
      "/etc/machine-id"

      # If using DHCP, might want to persist lease
      # "/var/lib/dhcpcd/dhcpcd-eth0.lease"
    ];

    users.bdhill = {
      directories = [
        # User's home directory files
        "Downloads"
        "Music"
        "Pictures"
        "Documents"
        "Videos"
        ".ssh"
        ".config"
        ".local"
        ".cache"
      ];
      files = [
        ".bashrc"
        ".bash_history"
      ];
    };
  };

  # Persist SSH host keys
  services.openssh.hostKeys = [
    {
      path = "/persist/etc/ssh/ssh_host_ed25519_key";
      type = "ed25519";
    }
    {
      path = "/persist/etc/ssh/ssh_host_rsa_key";
      type = "rsa";
      bits = 4096;
    }
  ];

  # Roll back root filesystem on boot
  boot.initrd.postDeviceCommands = lib.mkAfter ''
    zfs rollback -r rpool/local/root@blank
  '';

  # SOPS configuration - use persisted SSH key
  sops = {
    age.sshKeyPaths = [ "/persist/etc/ssh/ssh_host_ed25519_key" ];
  };
}
```

### Migration Procedure

**Phase 1: Preparation (No Downtime)**

1. **Update configuration files locally:**
```bash
# On your Mac
cd /Users/bobby/github/catgrep/nixos-config

# Replace disko-config.nix (see above)
# Replace impermanence.nix (see above)

# Validate builds
make check
make build-firebat
```

2. **Backup Grafana dashboards:**
```bash
make ssh-firebat
curl -u admin:admin http://localhost:3000/api/search | jq . > /tmp/dashboards.json
# Export each dashboard individually if needed

# Copy to local machine
exit
scp bdhill@firebat:/tmp/dashboards.json ./backups/firebat-grafana-$(date +%Y%m%d).json
```

3. **Document current service config:**
```bash
make ssh-firebat
sudo systemctl status grafana
sudo systemctl status prometheus
sudo systemctl status caddy
```

**Phase 2: Installation (DOWNTIME REQUIRED - ~1-2 hours)**

1. **Create NixOS installer USB:**
```bash
# If you don't have one already
# Or boot from existing installer
```

2. **Boot firebat from installer**
- Connect monitor and keyboard OR use serial console
- Boot from USB
- Connect to network

3. **Run disko:**
```bash
# On the installer, clone repo or copy disko-config
nix run github:nix-community/disko -- --mode disko /path/to/disko-config.nix

# This will:
# - Partition the disk
# - Create ZFS pool
# - Create datasets
# - Mount everything under /mnt
```

4. **Install NixOS:**
```bash
# Generate hardware-config (or use existing)
nixos-generate-config --root /mnt

# Copy your configuration
# (easiest to git clone your repo)
git clone https://github.com/yourusername/nixos-config /mnt/etc/nixos

# Install
nixos-install --flake /mnt/etc/nixos#firebat

# Set root password when prompted

# Reboot
reboot
```

**Phase 3: Post-Installation (Restore Services)**

1. **Verify ZFS impermanence:**
```bash
make ssh-firebat

# Check ZFS layout
sudo zfs list

# Check mounts
mount | grep zfs

# Verify blank snapshot exists
sudo zfs list -t snapshot
```

2. **Import Grafana dashboards:**
```bash
# Copy backup to firebat
scp ./backups/firebat-grafana-*.json bdhill@firebat:/tmp/

# Import dashboards via Grafana UI or API
# Grafana will be running with empty database initially
```

3. **Verify services:**
```bash
# Check all services started
sudo systemctl status grafana
sudo systemctl status prometheus
sudo systemctl status caddy

# Check persistence
ls -la /persist/var/lib/grafana
ls -la /persist/var/lib/prometheus2
```

4. **Test reverse proxy:**
```bash
# From another machine
curl -k https://grafana.vofi.app
curl -k https://prometheus.vofi.app
```

5. **Reboot and verify impermanence:**
```bash
# Reboot to test root rollback
sudo reboot

# After reboot, check that services still have their data
sudo systemctl status grafana
# Should show persistent dashboards

# Check that root was rolled back
sudo ls -la /  # Should be clean
sudo ls -la /persist  # Should have service data
```

### Rollback Plan

**If something goes wrong during migration:**

1. **Boot from installer again**
2. **Mount old ext4 partition** (if not overwritten)
3. **Restore from backup**

**If issues after installation:**

```bash
# Can boot into previous generation from GRUB
# Or from installer, import the pool and fix config

# From installer:
zpool import -f rpool
mount -t zfs rpool/local/root /mnt
mount -t zfs rpool/local/nix /mnt/nix
mount -t zfs rpool/safe/persist /mnt/persist

# Fix configuration
nano /mnt/etc/nixos/configuration.nix

# Reinstall
nixos-install --root /mnt --flake /mnt/etc/nixos#firebat
```

### Testing Checklist

After migration:

- [ ] ZFS pool `rpool` exists and is healthy
- [ ] All datasets mounted correctly
- [ ] Blank snapshot exists (`rpool/local/root@blank`)
- [ ] Boot rollback works (test with `sudo touch /test && sudo reboot`, file should be gone)
- [ ] Grafana runs and dashboards are persistent across reboots
- [ ] Prometheus collects metrics and retains data
- [ ] Caddy serves reverse proxy correctly
- [ ] SSL certificates work (Caddy local CA or ACME)
- [ ] All monitored services are accessible
- [ ] SSH keys persisted correctly
- [ ] SOPS secrets decrypt properly

### Timeline Estimate

- **Preparation:** 1-2 hours (testing configs, backups)
- **Installation:** 1-2 hours (actual downtime)
- **Verification:** 30 minutes - 1 hour
- **Total:** 3-5 hours

### Risk Assessment

**Low Risk:**
- ✅ Configuration validated with `make check`
- ✅ Can boot from installer if needed
- ✅ Critical data backed up (Grafana dashboards)
- ✅ Services will rebuild data from exporters (Prometheus)

**Medium Risk:**
- ⚠️ First time running disko on this host
- ⚠️ Downtime required for gateway services
- ⚠️ Need physical or console access

**Mitigation:**
- Test disko config in VM first
- Schedule during low-usage time
- Have backup monitoring ready
- Keep installer USB handy

## Alternative: Gradual Approach (Option C)

If full migration is too risky, enhance persistence first:

**Step 1:** Update `impermanence.nix` with service directories (see above)
**Step 2:** Deploy and test: `make switch-firebat`
**Step 3:** Verify services persist across reboots
**Step 4:** Plan ZFS migration for later

This gets 80% of the benefit with 20% of the risk.

## Summary

- **Goal:** Implement ZFS impermanence on firebat to match ser8
- **Method:** Clean reinstall with new disko config
- **Downtime:** 1-2 hours
- **Risk:** Medium (mitigated with backups and testing)
- **Benefit:** Consistent architecture, stateless root, easier maintenance
